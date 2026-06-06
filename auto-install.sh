#!/usr/bin/env bash
# ============================================================================
# auto-install.sh — Self-healing, resumable installer for caelestia-shell
# ============================================================================
# Runs each step of install-ubuntu.sh individually so that:
#   - If step 4 fails, it fixes the issue and resumes FROM step 4
#   - Missing pkg-config / CMake / apt dependencies are auto-resolved
#   - Progress is saved to disk so you can even restart the script
#
# Usage:
#   chmod +x auto-install.sh
#   ./auto-install.sh           # normal run (resumes from last failure)
#   ./auto-install.sh --reset   # start fresh from step 1
#   ./auto-install.sh --from 4  # force start from step 4
# ============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/install-ubuntu.sh"
PROGRESS_FILE="/tmp/caelestia-install-progress"
LOG_FILE="/tmp/caelestia-step-$$.log"
MAX_RETRIES_PER_STEP=10

# ── Colors ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[AUTO]${NC} $*"; }
log_success() { echo -e "${GREEN}[AUTO ✓]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[AUTO ⚠]${NC} $*"; }
log_error()   { echo -e "${RED}[AUTO ✗]${NC} $*"; }
log_fix()     { echo -e "${MAGENTA}[FIX]${NC} $*"; }
log_step()    { echo -e "\n${CYAN}${BOLD}━━━ $* ━━━${NC}"; }

# ── The 9 steps (function names from install-ubuntu.sh) ─────────
STEPS=(
    "preflight_checks"
    "install_apt_deps"
    "build_hyprland_ecosystem"
    "build_quickshell"
    "build_caelestia_cli"
    "install_helper_tools"
    "install_fonts"
    "build_caelestia_shell"
    "configure_system"
)

STEP_NAMES=(
    "Pre-flight checks"
    "Install APT dependencies"
    "Build Hyprland ecosystem"
    "Build Quickshell"
    "Build caelestia-cli"
    "Install helper tools"
    "Install fonts"
    "Build caelestia-shell"
    "Configure system"
)

# ── Track installed packages ────────────────────────────────────
declare -A AUTO_INSTALLED

# ── Progress management ─────────────────────────────────────────
save_progress() {
    echo "$1" > "$PROGRESS_FILE"
}

load_progress() {
    if [[ -f "$PROGRESS_FILE" ]]; then
        cat "$PROGRESS_FILE"
    else
        echo "0"
    fi
}

clear_progress() {
    rm -f "$PROGRESS_FILE"
}

# ── Dependency resolution ───────────────────────────────────────
find_apt_package() {
    local dep="$1"
    local found=""
    local dep_lower
    dep_lower=$(echo "$dep" | tr '[:upper:]' '[:lower:]')

    # Exact matches first (lowercase)
    for pattern in "^lib${dep_lower}-dev$" "^${dep_lower}-dev$" "^lib${dep_lower}[0-9]*-dev$"; do
        found=$(apt-cache search "$pattern" 2>/dev/null | head -1 | awk '{print $1}')
        [[ -n "$found" ]] && echo "$found" && return 0
    done

    # Normalized (dots → hyphens)
    local norm; norm=$(echo "$dep" | tr '.' '-')
    for pattern in "^lib${norm}-dev$" "^${norm}-dev$"; do
        found=$(apt-cache search "$pattern" 2>/dev/null | head -1 | awk '{print $1}')
        [[ -n "$found" ]] && echo "$found" && return 0
    done

    # Versioned: lua5.5 → liblua5.5-dev
    if [[ "$dep" =~ ^([a-z]+)[-_]?([0-9]+)\.([0-9]+)$ ]]; then
        local base="${BASH_REMATCH[1]}" maj="${BASH_REMATCH[2]}" min="${BASH_REMATCH[3]}"
        for pattern in "^lib${base}${maj}.${min}-dev$" "^lib${base}-${maj}.${min}-dev$"; do
            found=$(apt-cache search "$pattern" 2>/dev/null | head -1 | awk '{print $1}')
            [[ -n "$found" ]] && echo "$found" && return 0
        done
    fi

    # Broad search
    found=$(apt-cache search "${dep}" 2>/dev/null | grep -iE "[-]dev\b" | grep -i "${dep}" | head -1 | awk '{print $1}')
    [[ -n "$found" ]] && echo "$found" && return 0

    # .pc file in dpkg
    found=$(dpkg -S "${dep}.pc" 2>/dev/null | grep -oP '^[^:]+' | head -1)
    [[ -n "$found" ]] && echo "$found" && return 0

    return 1
}

extract_missing_deps() {
    local log="$1"
    {
        # pkg-config: Package 'X' not found
        grep -oP "Package '\\K[^']+(?=' not found)" "$log" 2>/dev/null

        # pkg-config: None of the required 'X;Y;Z' found
        grep -oP "None of the required '\\K[^']+(?=' found)" "$log" 2>/dev/null |
            tr ';' '\n' | grep -oP '^[a-zA-Z][a-zA-Z0-9._-]+'

        # CMake: find_package("X")
        grep -oP 'provided by "\\K[^"]+' "$log" 2>/dev/null

        # CMake: - X (after "required packages were not found")
        grep -A2 'required packages were not found' "$log" 2>/dev/null |
            grep -oP '^\s+- \K\S+'

        # Meson: Dependency 'X' not found
        grep -oP "Dependency\\s+'?\\K[a-zA-Z][a-zA-Z0-9._-]+(?='?\\s+not found)" "$log" 2>/dev/null

        # apt: Unable to locate package X
        grep -oP "Unable to locate package \\K\\S+" "$log" 2>/dev/null

        # apt: Package 'X' has no installation candidate
        grep -oP "Package '\\K[^']+(?=' has no installation candidate)" "$log" 2>/dev/null

        # Shell errors: line NN: <package>: command not found (from broken apt syntax)
        grep -oP 'line \d+: \K\S+(?=: command not found)' "$log" 2>/dev/null

        # Meson: build file not found (wrong build system)
        grep -q "Neither source directory" "$log" 2>/dev/null && echo "__WRONG_BUILD_SYSTEM__"

    } | sort -u
}

fix_missing_deps() {
    local log="$1"
    local fixed=false

    local deps
    deps=$(extract_missing_deps "$log")

    if [[ -z "$deps" ]]; then
        return 1
    fi

    while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        [[ "$dep" == "__WRONG_BUILD_SYSTEM__" ]] && {
            log_warn "Detected wrong build system (meson vs cmake) — needs manual script fix"
            continue
        }

        log_info "Resolving missing dependency: ${BOLD}$dep${NC}"

        local apt_pkg
        apt_pkg=$(find_apt_package "$dep") || {
            log_warn "Could not find apt package for '$dep' — may need manual build"
            continue
        }

        if dpkg -s "$apt_pkg" &>/dev/null; then
            log_warn "'$apt_pkg' already installed but '$dep' still not found — skip"
            continue
        fi

        log_fix "Installing ${BOLD}$apt_pkg${NC}"
        if sudo apt-get install -y "$apt_pkg" 2>&1; then
            log_success "Installed $apt_pkg"
            AUTO_INSTALLED[$dep]="$apt_pkg"
            fixed=true
        else
            log_error "Failed to install $apt_pkg"
        fi
    done <<< "$deps"

    # Clean stale build directories
    local build_dir
    build_dir=$(grep -oP 'Build files have been written to: \K.+' "$log" | tail -1)
    if [[ -n "$build_dir" && -d "$build_dir" ]]; then
        log_info "Cleaning stale build: $build_dir"
        rm -rf "$build_dir"
    fi

    sudo ldconfig 2>/dev/null || true

    $fixed
}

# ── Generate a single-step runner script ────────────────────────
# This sources install-ubuntu.sh for its functions/variables,
# then calls just ONE function.
run_step() {
    local step_func="$1"
    local step_num="$2"
    local step_name="$3"

    log_step "Step $step_num/${#STEPS[@]}: $step_name"

    # Create a temporary script that sources the installer and runs one step
    local runner="/tmp/caelestia-run-step-$$.sh"
    cat > "$runner" << RUNNER_EOF
#!/usr/bin/env bash
set -euo pipefail

# Source the installer to get all functions and variables
# We need to skip the 'main' call at the bottom
source <(sed '/^main "\\\$@"/d' "$INSTALL_SCRIPT")

# Set up environment (normally done in build_hyprland_ecosystem)
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/share/pkgconfig:\${PKG_CONFIG_PATH:-}"
export CMAKE_PREFIX_PATH="/usr/local:\${CMAKE_PREFIX_PATH:-}"
export QML2_IMPORT_PATH="/usr/local/lib/qt6/qml:/usr/local/lib/x86_64-linux-gnu/qt6/qml:\${QML2_IMPORT_PATH:-}"

# Run just this step
$step_func
RUNNER_EOF
    chmod +x "$runner"

    # Execute it, capturing output
    if bash "$runner" 2>&1 | tee "$LOG_FILE"; then
        rm -f "$runner"
        return 0
    else
        rm -f "$runner"
        return 1
    fi
}

# ── Handle the interactive prompt in install-ubuntu.sh ──────────
# The main() function has a Y/n prompt. Our step runner skips main()
# and calls functions directly, so no prompt is needed.

# ── Main ────────────────────────────────────────────────────────
main() {
    local start_from=-1
    local reset=false

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reset)  reset=true; shift ;;
            --from)   start_from="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: $0 [--reset] [--from STEP_NUM]"
                echo "  --reset    Start fresh from step 1"
                echo "  --from N   Start from step N (1-${#STEPS[@]})"
                echo ""
                echo "Steps:"
                for i in "${!STEPS[@]}"; do
                    echo "  $((i+1)). ${STEP_NAMES[$i]}"
                done
                exit 0
                ;;
            *) log_error "Unknown arg: $1"; exit 1 ;;
        esac
    done

    echo -e "${CYAN}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════════════════╗"
    echo "  ║   caelestia-shell — Smart Resumable Installer            ║"
    echo "  ╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    if $reset; then
        clear_progress
        log_info "Progress reset — starting from step 1"
    fi

    # Determine starting step
    local current_step
    if [[ $start_from -ge 1 ]]; then
        current_step=$((start_from - 1))
        log_info "Forced start from step $start_from: ${STEP_NAMES[$current_step]}"
    else
        current_step=$(load_progress)
        if [[ $current_step -gt 0 ]]; then
            log_info "Resuming from step $((current_step + 1)): ${STEP_NAMES[$current_step]}"
            echo -e "  ${DIM}(Steps 1-$current_step already completed. Use --reset to redo all.)${NC}"
        else
            log_info "Starting fresh installation"
        fi
    fi

    echo ""
    echo -e "  Steps to run:"
    for i in "${!STEPS[@]}"; do
        if [[ $i -lt $current_step ]]; then
            echo -e "    ${GREEN}✓${NC} ${DIM}$((i+1)). ${STEP_NAMES[$i]} (done)${NC}"
        else
            echo -e "    ○ $((i+1)). ${STEP_NAMES[$i]}"
        fi
    done
    echo ""

    local start_time
    start_time=$(date +%s)

    # Run each step starting from current_step
    while [[ $current_step -lt ${#STEPS[@]} ]]; do
        local step_func="${STEPS[$current_step]}"
        local step_name="${STEP_NAMES[$current_step]}"
        local step_num=$((current_step + 1))
        local retries=0

        while true; do
            if run_step "$step_func" "$step_num" "$step_name"; then
                log_success "Step $step_num completed: $step_name"
                current_step=$((current_step + 1))
                save_progress "$current_step"
                break
            else
                retries=$((retries + 1))
                echo ""
                log_warn "Step $step_num failed (attempt $retries/$MAX_RETRIES_PER_STEP)"

                if [[ $retries -ge $MAX_RETRIES_PER_STEP ]]; then
                    log_error "Step $step_num exceeded max retries. Stopping."
                    log_error "Fix the issue and re-run. It will resume from step $step_num."
                    echo ""
                    log_info "Last error output:"
                    tail -30 "$LOG_FILE" 2>/dev/null
                    rm -f "$LOG_FILE"
                    exit 1
                fi

                log_info "Attempting to auto-resolve..."
                if fix_missing_deps "$LOG_FILE"; then
                    log_success "Dependencies fixed! Retrying step $step_num..."
                else
                    log_error "Could not auto-resolve the failure."
                    log_error "Fix the issue manually and re-run. Will resume from step $step_num."
                    echo ""
                    log_info "Last error output:"
                    tail -30 "$LOG_FILE" 2>/dev/null
                    rm -f "$LOG_FILE"
                    exit 1
                fi
            fi
        done
    done

    # All done!
    clear_progress
    rm -f "$LOG_FILE"

    local end_time elapsed_min
    end_time=$(date +%s)
    elapsed_min=$(( (end_time - start_time) / 60 ))

    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════════════════╗"
    echo "  ║          Installation completed successfully!            ║"
    echo "  ╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  Total time: ${BOLD}${elapsed_min} minutes${NC}"
    echo ""

    if [[ ${#AUTO_INSTALLED[@]} -gt 0 ]]; then
        log_success "Auto-installed packages during this run:"
        for dep in "${!AUTO_INSTALLED[@]}"; do
            echo -e "  ${GREEN}✓${NC} ${AUTO_INSTALLED[$dep]} (for '$dep')"
        done
        echo ""
    fi

    echo -e "  ${BOLD}Next steps:${NC}"
    echo -e "    1. Log out of your current session"
    echo -e "    2. Select ${BOLD}Caelestia (Hyprland)${NC} from your display manager"
    echo -e "    3. Log in and enjoy! 🎉"
    echo ""
}

main "$@"
