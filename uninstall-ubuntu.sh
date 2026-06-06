#!/usr/bin/env bash
# ============================================================================
# caelestia-shell — Ubuntu 26.04 Uninstaller
# ============================================================================
# Removes caelestia-shell and all from-source dependencies installed by
# install-ubuntu.sh. Does NOT remove APT packages (as they may be shared).
#
# Usage:
#   chmod +x uninstall-ubuntu.sh
#   ./uninstall-ubuntu.sh
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "  ${CYAN}[INFO]${NC} $*"; }
log_success() { echo -e "  ${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "  ${YELLOW}[WARN]${NC} $*"; }

BUILD_DIR="${HOME}/.local/src/caelestia-build"

echo -e "${RED}${BOLD}"
echo "  ╔═══════════════════════════════════════════════════════════╗"
echo "  ║       caelestia-shell — Ubuntu Uninstaller               ║"
echo "  ╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "  This will remove:"
echo "    • caelestia-shell (Quickshell config + plugin)"
echo "    • Quickshell"
echo "    • Hyprland and its ecosystem libs"
echo "    • caelestia-cli"
echo "    • Session file and PAM config"
echo ""
echo -e "  ${YELLOW}APT packages will NOT be removed (they may be used by other software).${NC}"
echo ""
read -rp "  Are you sure? [y/N] " yn
[[ "$yn" =~ ^[Yy]$ ]] || exit 0

echo ""

# ----------------------------------
# Remove installed files via cmake
# ----------------------------------
uninstall_cmake_project() {
    local name="$1"
    local dir="$BUILD_DIR/$name"

    if [[ -d "$dir/build" && -f "$dir/build/install_manifest.txt" ]]; then
        log_info "Removing $name (via install_manifest.txt)..."
        while IFS= read -r file; do
            sudo rm -f "$file" 2>/dev/null
        done < "$dir/build/install_manifest.txt"
        log_success "$name removed"
    elif [[ -d "$dir/build" ]]; then
        log_info "Removing $name (via cmake --install with dry-run check)..."
        # Try ninja uninstall if available
        pushd "$dir" >/dev/null
        sudo ninja -C build uninstall 2>/dev/null || true
        popd >/dev/null
        log_success "$name removed (best effort)"
    else
        log_warn "$name build dir not found at $dir, skipping"
    fi
}

uninstall_meson_project() {
    local name="$1"
    local dir="$BUILD_DIR/$name"

    if [[ -d "$dir/build" ]]; then
        log_info "Removing $name..."
        pushd "$dir" >/dev/null
        sudo ninja -C build uninstall 2>/dev/null || true
        popd >/dev/null
        log_success "$name removed"
    else
        log_warn "$name build dir not found, skipping"
    fi
}

# ----------------------------------
# Remove shell config
# ----------------------------------
log_info "Removing caelestia-shell config..."
sudo rm -rf /etc/xdg/quickshell/caelestia 2>/dev/null || true
sudo rm -rf /usr/local/lib/caelestia 2>/dev/null || true
log_success "Shell config removed"

# ----------------------------------
# Remove session file
# ----------------------------------
log_info "Removing desktop session..."
sudo rm -f /usr/share/wayland-sessions/caelestia-hyprland.desktop 2>/dev/null || true
sudo rm -f /usr/local/bin/caelestia-session 2>/dev/null || true
log_success "Session file removed"

# ----------------------------------
# Remove PAM config
# ----------------------------------
log_info "Removing PAM config..."
sudo rm -f /etc/pam.d/caelestia 2>/dev/null || true
log_success "PAM config removed"

# ----------------------------------
# Remove built projects (reverse order)
# ----------------------------------
uninstall_cmake_project "caelestia-shell"
uninstall_cmake_project "caelestia-cli"
uninstall_cmake_project "quickshell"
uninstall_cmake_project "hyprpaper"
uninstall_cmake_project "hyprlock"
uninstall_cmake_project "hypridle"
uninstall_cmake_project "Hyprland"
uninstall_cmake_project "aquamarine"
uninstall_cmake_project "hyprgraphics"
uninstall_meson_project "hyprland-protocols"
uninstall_cmake_project "hyprwayland-scanner"
uninstall_cmake_project "hyprlang"
uninstall_cmake_project "hyprutils"

# ----------------------------------
# Remove caelestia-cli binary
# ----------------------------------
log_info "Removing caelestia binary..."
sudo rm -f /usr/local/bin/caelestia 2>/dev/null || true
log_success "caelestia binary removed"

# ----------------------------------
# Remove app2unit
# ----------------------------------
log_info "Removing app2unit..."
sudo rm -f /usr/local/bin/app2unit 2>/dev/null || true
log_success "app2unit removed"

# ----------------------------------
# Remove ldconfig entry
# ----------------------------------
log_info "Cleaning ldconfig..."
sudo rm -f /etc/ld.so.conf.d/usr-local.conf 2>/dev/null || true
sudo ldconfig 2>/dev/null || true
log_success "ldconfig cleaned"

# ----------------------------------
# Optionally remove build sources
# ----------------------------------
echo ""
if [[ -d "$BUILD_DIR" ]]; then
    read -rp "  Remove build sources at $BUILD_DIR? (~1-2 GB) [y/N] " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        rm -rf "$BUILD_DIR"
        log_success "Build sources removed"
    else
        log_info "Build sources kept at $BUILD_DIR"
    fi
fi

# ----------------------------------
# Optionally remove user configs
# ----------------------------------
echo ""
read -rp "  Remove user configs (~/.config/caelestia and ~/.config/hypr)? [y/N] " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
    rm -rf "$HOME/.config/caelestia" 2>/dev/null || true
    rm -rf "$HOME/.config/hypr" 2>/dev/null || true
    log_success "User configs removed"
else
    log_info "User configs kept"
fi

echo ""
echo -e "${GREEN}${BOLD}  Uninstallation complete!${NC}"
echo -e "  You may also want to remove fonts from ${CYAN}~/.local/share/fonts/${NC}"
echo ""
