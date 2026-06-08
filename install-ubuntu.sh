#!/usr/bin/env bash
# ============================================================================
# caelestia-shell — Ubuntu 26.04 Installer
# ============================================================================
# This script automates the full build-from-source installation of
# caelestia-shell and ALL of its dependencies on Ubuntu 26.04 (Noble+).
#
# It will install:
#   1. Build tools & libraries via apt
#   2. Hyprland ecosystem (hyprutils, hyprlang, hyprwayland-scanner,
#      hyprgraphics, hyprland-protocols, aquamarine, hyprland)
#   3. Quickshell (git/master)
#   4. caelestia-cli
#   5. Helper tools (app2unit, libcava, swappy)
#   6. Fonts (Material Symbols, CaskaydiaCove Nerd Font)
#   7. caelestia-shell itself
#   8. Desktop session file & PAM configuration
#
# Usage:
#   chmod +x install-ubuntu.sh
#   ./install-ubuntu.sh
#
# To uninstall:
#   ./uninstall-ubuntu.sh
#
# License: Same as caelestia-shell (see LICENSE)
# ============================================================================

set -euo pipefail

# ----------------------------------
# Configuration
# ----------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${HOME}/.local/src/caelestia-build"
INSTALL_PREFIX="/usr/local"
JOBS="$(nproc)"
SHELL_REPO="https://github.com/caelestia-dots/shell.git"
CLI_REPO="https://github.com/caelestia-dots/cli.git"
QUICKSHELL_REPO="https://git.outfoxxed.me/outfoxxed/quickshell"
REQUIRED_QT_MAJOR=6
REQUIRED_QT_MINOR=9

# Hyprland ecosystem repos
HYPRUTILS_REPO="https://github.com/hyprwm/hyprutils.git"
HYPRLANG_REPO="https://github.com/hyprwm/hyprlang.git"
HYPRWAYLAND_SCANNER_REPO="https://github.com/hyprwm/hyprwayland-scanner.git"
HYPRGRAPHICS_REPO="https://github.com/hyprwm/hyprgraphics.git"
HYPRLAND_PROTOCOLS_REPO="https://github.com/hyprwm/hyprland-protocols.git"
AQUAMARINE_REPO="https://github.com/hyprwm/aquamarine.git"
HYPRCURSOR_REPO="https://github.com/hyprwm/hyprcursor.git"
HYPRLAND_REPO="https://github.com/hyprwm/Hyprland.git"
HYPRIDLE_REPO="https://github.com/hyprwm/hypridle.git"
HYPRLOCK_REPO="https://github.com/hyprwm/hyprlock.git"
HYPRPAPER_REPO="https://github.com/hyprwm/hyprpaper.git"
HYPRTOOLKIT_REPO="https://github.com/hyprwm/hyprtoolkit.git"

# Helper tool repos
APP2UNIT_REPO="https://github.com/Vladimir-csp/app2unit.git"
LIBCAVA_REPO="https://github.com/LukashonakV/cava.git"

# Font URLs
MATERIAL_SYMBOLS_URL="https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf"
NERD_FONTS_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip"

# ----------------------------------
# Colors & Logging
# ----------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()    { echo -e "\n${CYAN}${BOLD}==> $*${NC}"; }

die() {
    log_error "$*"
    exit 1
}

# ----------------------------------
# Pre-flight Checks
# ----------------------------------
preflight_checks() {
    log_step "Running pre-flight checks"

    # Must not be root
    if [[ $EUID -eq 0 ]]; then
        die "Do not run this script as root. It will ask for sudo when needed."
    fi

    # Check Ubuntu version
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" ]]; then
            log_warn "This script is designed for Ubuntu. Detected: $ID $VERSION_ID"
            read -rp "Continue anyway? [y/N] " yn
            [[ "$yn" =~ ^[Yy]$ ]] || exit 1
        else
            log_info "Detected: $PRETTY_NAME"
        fi
    fi

    # Check for sudo
    if ! command -v sudo &>/dev/null; then
        die "sudo is required. Install it with: apt install sudo"
    fi

    # Check internet connectivity
    if ! ping -c 1 github.com &>/dev/null; then
        die "No internet connectivity. This script needs to download source code."
    fi

    # Check Qt version (needed by the C++ plugin: qt_standard_project_setup(REQUIRES 6.9))
    if command -v qmake6 &>/dev/null; then
        local qt_version
        qt_version=$(qmake6 -query QT_VERSION 2>/dev/null || echo "0.0.0")
        local qt_major qt_minor
        qt_major=$(echo "$qt_version" | cut -d. -f1)
        qt_minor=$(echo "$qt_version" | cut -d. -f2)
        log_info "System Qt version: $qt_version"
        if [[ "$qt_major" -lt "$REQUIRED_QT_MAJOR" ]] || \
           { [[ "$qt_major" -eq "$REQUIRED_QT_MAJOR" ]] && [[ "$qt_minor" -lt "$REQUIRED_QT_MINOR" ]]; }; then
            log_warn "Qt $qt_version detected, but the plugin requires Qt >= ${REQUIRED_QT_MAJOR}.${REQUIRED_QT_MINOR}"
            log_warn "The build may fail. Consider installing a newer Qt from:"
            log_warn "  • Qt online installer: https://www.qt.io/download-qt-installer"
            log_warn "  • A PPA with backported Qt packages"
            read -rp "Continue anyway? [y/N] " yn
            [[ "$yn" =~ ^[Yy]$ ]] || exit 1
        else
            log_success "Qt $qt_version meets requirements (>= ${REQUIRED_QT_MAJOR}.${REQUIRED_QT_MINOR})"
        fi
    else
        log_info "Qt not yet installed (will be installed via apt in Step 1)"
    fi

    # Detect if running from inside the shell repo
    if [[ -f "$SCRIPT_DIR/shell.qml" && -d "$SCRIPT_DIR/plugin" && -d "$SCRIPT_DIR/services" ]]; then
        log_info "Detected local shell repo at: $SCRIPT_DIR"
        log_info "Will build from local source instead of cloning from GitHub"
        USE_LOCAL_REPO=true
    else
        USE_LOCAL_REPO=false
    fi

    log_success "Pre-flight checks passed"
}

# ----------------------------------
# Step 1: Install APT Dependencies
# ----------------------------------
install_apt_deps() {
    log_step "Step 1/8: Installing APT build & runtime dependencies"

    sudo apt-get update

    # Build essentials
    sudo apt-get install -y \
        build-essential \
        cmake \
        cmake-extras \
        ninja-build \
        git \
        pkg-config \
        meson \
        gettext \
        curl \
        wget \
        unzip \
        autoconf \
        automake \
        libtool \
        golang-go

    # Qt6 development
    sudo apt-get install -y \
        qt6-base-dev \
        qt6-base-private-dev \
        qt6-declarative-dev \
        qt6-declarative-private-dev \
        qt6-shadertools-dev \
        qt6-svg-dev \
        qt6-wayland-dev \
        qt6-wayland-private-dev \
        qml6-module-qtquick \
        qml6-module-qtquick-controls \
        qml6-module-qtquick-layouts \
        qml6-module-qtquick-shapes \
        qml6-module-qtqml-workerscript \
        qml6-module-qtquick-templates \
        qml6-module-qt5compat-graphicaleffects \
        qt6-tools-dev \
        qt6-tools-dev-tools \
        qt6-l10n-tools

    # Wayland development
    sudo apt-get install -y \
        libwayland-dev \
        wayland-protocols \
        libxkbcommon-dev \
        libxkbregistry-dev \
        xwayland \
        xdg-desktop-portal-wlr \
        libdrm-dev \
        libgbm-dev \
        libegl-dev \
        libgles-dev \
        libvulkan-dev \
        glslang-tools \
        glslang-dev \
        vulkan-utility-libraries-dev \
        libseat-dev \
        libdisplay-info-dev \
        libliftoff-dev

    # Input & display
    sudo apt-get install -y \
        libinput-dev \
        libudev-dev \
        libpixman-1-dev \
        libcairo2-dev \
        libpango1.0-dev \
        libtomlplusplus-dev \
        libpugixml-dev \
        librsvg2-dev \
        libxcursor-dev \
        libmuparser-dev \
        liblcms2-dev \
        uuid-dev \
        libzip-dev \
        libglib2.0-dev \
        libhyprcursor-dev 2>/dev/null || true

    # hwdata (needed by aquamarine)
    sudo apt-get install -y \
        hwdata

    # Lua 5.5 (needed by Hyprland)
    sudo apt-get install -y \
        liblua5.5-dev

    # Multimedia & audio
    sudo apt-get install -y \
        libpipewire-0.3-dev \
        pipewire \
        libfftw3-dev \
        libiniparser-dev \
        libpulse-dev \
        libaubio-dev \
        libsndfile1-dev

    # Networking & system
    sudo apt-get install -y \
        network-manager \
        libnm-dev \
        lm-sensors \
        libsensors-dev \
        libsystemd-dev \
        libpam0g-dev \
        libdbus-1-dev \
        libupower-glib-dev

    # Brightness & display control
    sudo apt-get install -y \
        brightnessctl \
        ddcutil

    # Image & screenshot
    sudo apt-get install -y \
        libmagic-dev \
        libjxl-dev \
        libwebp-dev \
        libjpeg-dev \
        libpng-dev

    # Math library
    sudo apt-get install -y \
        libqalculate-dev \
        qalc

    # Additional tools
    sudo apt-get install -y \
        fish \
        grim \
        slurp \
        wl-clipboard \
        jq \
        swappy \
        notify-osd \
        libnotify-bin

    # Hyprland-specific build deps
    sudo apt-get install -y \
        libhyprlang-dev 2>/dev/null || true  # May not exist yet
    sudo apt-get install -y \
        libre2-dev \
        libxcb-composite0-dev \
        libxcb-dri3-dev \
        libxcb-ewmh-dev \
        libxcb-icccm4-dev \
        libxcb-present-dev \
        libxcb-render-util0-dev \
        libxcb-res0-dev \
        libxcb-xinput-dev \
        libxcb-xkb-dev \
        libxcb-errors-dev \
        libhyprwire-dev \
        hyprwire-scanner \
        xdg-utils \
        libudis86-dev \
        libsdbus-c++-dev \
        libheif-dev \
        libcli11-dev \
        libjemalloc-dev \
        python3-pip \
        python3-pillow \
        papirus-icon-theme \
        hyprland-qtutils \
        sassc
    log_success "APT dependencies installed"
}

# ----------------------------------
# Utility: Clone or update a repo
# ----------------------------------
clone_or_update() {
    local repo="$1"
    local dir="$2"
    local branch="${3:-}"

    if [[ -d "$dir" ]]; then
        log_info "Updating ${dir##*/}..."
        pushd "$dir" >/dev/null
        git fetch --all
        if [[ -n "$branch" ]]; then
            git checkout "$branch"
        fi
        git pull --ff-only || git reset --hard "origin/$(git branch --show-current)"
        git submodule update --init --recursive
        popd >/dev/null
    else
        log_info "Cloning ${dir##*/}..."
        if [[ -n "$branch" ]]; then
            git clone --recursive -b "$branch" "$repo" "$dir"
        else
            git clone --recursive "$repo" "$dir"
        fi
    fi
}

# ----------------------------------
# Utility: CMake build & install
# ----------------------------------
cmake_build_install() {
    local dir="$1"
    shift
    local extra_args=("$@")

    pushd "$dir" >/dev/null
    cmake -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
        -DCMAKE_LIBRARY_PATH="/usr/local/lib;/usr/local/lib/x86_64-linux-gnu" \
        "${extra_args[@]}" 2>&1
    cmake --build build -j "$JOBS" 2>&1
    sudo cmake --install build 2>&1
    popd >/dev/null
}

# ----------------------------------
# Utility: Meson build & install
# ----------------------------------
meson_build_install() {
    local dir="$1"
    shift
    local extra_args=("$@")

    pushd "$dir" >/dev/null
    # Clean previous build if exists
    [[ -d build ]] && rm -rf build
    meson setup build \
        --prefix="$INSTALL_PREFIX" \
        --buildtype=release \
        "${extra_args[@]}" 2>&1
    ninja -C build -j "$JOBS" 2>&1
    sudo ninja -C build install 2>&1
    popd >/dev/null
}

# ----------------------------------
# Step 2: Build Hyprland Ecosystem
# ----------------------------------
build_hyprland_ecosystem() {
    log_step "Step 2/8: Building Hyprland ecosystem from source"

    mkdir -p "$BUILD_DIR"

    # Remove conflicting system Hyprland library packages.
    # We build these from source (newer versions), but the old system .so
    # files cause linker errors if they coexist.
    log_info "Removing conflicting system Hyprland library packages..."
    sudo apt-get remove -y \
        libhyprutils10 libhyprutils-dev \
        libaquamarine9 libaquamarine-dev \
        libhyprgraphics4 libhyprgraphics-dev \
        libhyprcursor0 libhyprcursor-dev \
        libhyprlang2 libhyprlang-dev \
        2>/dev/null || true
    # Reinstall packages we need that may have been cascade-removed
    sudo apt-get install -y libhyprwire-dev libhyprwire3 hyprwire-scanner 2>/dev/null || true
    sudo ldconfig

    # Ensure ldconfig picks up /usr/local/lib
    echo "/usr/local/lib" | sudo tee /etc/ld.so.conf.d/usr-local.conf >/dev/null
    echo "/usr/local/lib/x86_64-linux-gnu" | sudo tee -a /etc/ld.so.conf.d/usr-local.conf >/dev/null

    # Set PKG_CONFIG_PATH so subsequent builds find previous ones
    export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/share/pkgconfig:${PKG_CONFIG_PATH:-}"
    export CMAKE_PREFIX_PATH="/usr/local:${CMAKE_PREFIX_PATH:-}"

    # Ensure linker finds our /usr/local libs first
    export LIBRARY_PATH="/usr/local/lib:/usr/local/lib/x86_64-linux-gnu:${LIBRARY_PATH:-}"
    export LD_LIBRARY_PATH="/usr/local/lib:/usr/local/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

    # 2a. hyprutils
    log_info "Building hyprutils..."
    clone_or_update "$HYPRUTILS_REPO" "$BUILD_DIR/hyprutils"
    cmake_build_install "$BUILD_DIR/hyprutils"
    sudo ldconfig
    log_success "hyprutils installed"

    # 2b. hyprlang
    log_info "Building hyprlang..."
    clone_or_update "$HYPRLANG_REPO" "$BUILD_DIR/hyprlang"
    cmake_build_install "$BUILD_DIR/hyprlang"
    sudo ldconfig
    log_success "hyprlang installed"

    # 2c. hyprwayland-scanner
    log_info "Building hyprwayland-scanner..."
    clone_or_update "$HYPRWAYLAND_SCANNER_REPO" "$BUILD_DIR/hyprwayland-scanner"
    cmake_build_install "$BUILD_DIR/hyprwayland-scanner"
    sudo ldconfig
    log_success "hyprwayland-scanner installed"

    # 2d. hyprland-protocols
    log_info "Building hyprland-protocols..."
    clone_or_update "$HYPRLAND_PROTOCOLS_REPO" "$BUILD_DIR/hyprland-protocols"
    cmake_build_install "$BUILD_DIR/hyprland-protocols"
    sudo ldconfig
    log_success "hyprland-protocols installed"

    # 2e. hyprgraphics
    log_info "Building hyprgraphics..."
    clone_or_update "$HYPRGRAPHICS_REPO" "$BUILD_DIR/hyprgraphics"
    cmake_build_install "$BUILD_DIR/hyprgraphics"
    sudo ldconfig
    log_success "hyprgraphics installed"

    # 2f. hyprcursor
    log_info "Building hyprcursor..."
    clone_or_update "$HYPRCURSOR_REPO" "$BUILD_DIR/hyprcursor"
    cmake_build_install "$BUILD_DIR/hyprcursor"
    sudo ldconfig
    log_success "hyprcursor installed"

    # 2g. aquamarine
    log_info "Building aquamarine..."
    clone_or_update "$AQUAMARINE_REPO" "$BUILD_DIR/aquamarine"
    cmake_build_install "$BUILD_DIR/aquamarine"
    sudo ldconfig
    log_success "aquamarine installed"

    # 2h. Hyprland (the compositor)
    log_info "Building Hyprland (this may take a while)..."
    clone_or_update "$HYPRLAND_REPO" "$BUILD_DIR/Hyprland"
    cmake_build_install "$BUILD_DIR/Hyprland" \
        -DNO_SYSTEMD=OFF
    sudo ldconfig
    log_success "Hyprland installed"

    # 2i. hypridle
    log_info "Building hypridle..."
    clone_or_update "$HYPRIDLE_REPO" "$BUILD_DIR/hypridle"
    cmake_build_install "$BUILD_DIR/hypridle"
    log_success "hypridle installed"

    # 2j. hyprlock
    log_info "Building hyprlock..."
    clone_or_update "$HYPRLOCK_REPO" "$BUILD_DIR/hyprlock"
    cmake_build_install "$BUILD_DIR/hyprlock"
    log_success "hyprlock installed"

    # 2k. hyprtoolkit
    log_info "Building hyprtoolkit..."
    clone_or_update "$HYPRTOOLKIT_REPO" "$BUILD_DIR/hyprtoolkit"
    cmake_build_install "$BUILD_DIR/hyprtoolkit"
    sudo ldconfig
    log_success "hyprtoolkit installed"

    # 2l. hyprpaper
    log_info "Building hyprpaper..."
    clone_or_update "$HYPRPAPER_REPO" "$BUILD_DIR/hyprpaper"
    cmake_build_install "$BUILD_DIR/hyprpaper"
    log_success "hyprpaper installed"
}

# ----------------------------------
# Step 3: Build Quickshell
# ----------------------------------
build_quickshell() {
    log_step "Step 3/8: Building Quickshell (git/master)"

    clone_or_update "$QUICKSHELL_REPO" "$BUILD_DIR/quickshell"

    pushd "$BUILD_DIR/quickshell" >/dev/null
    cmake -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
        -DWAYLAND=ON \
        -DWAYLAND_WLR_LAYERSHELL=ON \
        -DWAYLAND_SESSION_LOCK=ON \
        -DSERVICE_PIPEWIRE=ON \
        -DSERVICE_UPOWER=ON \
        -DSERVICE_BLUETOOTH=ON \
        -DSERVICE_TRAY=ON \
        -DSERVICE_NOTIFICATIONS=ON \
        -DSERVICE_MPRIS=ON \
        -DSERVICE_GREETD=OFF \
        -DSERVICE_PAM=ON \
        -DHYPRLAND=ON \
        -DX11=OFF \
        -DI3=OFF \
        -DCRASH_HANDLER=OFF 2>&1
    cmake --build build -j "$JOBS" 2>&1
    sudo cmake --install build 2>&1
    popd >/dev/null

    sudo ldconfig
    log_success "Quickshell installed"
}

# ----------------------------------
# Step 4: Build caelestia-cli
# ----------------------------------
build_caelestia_cli() {
    log_step "Step 4/8: Building caelestia-cli"

    clone_or_update "$CLI_REPO" "$BUILD_DIR/caelestia-cli"

    pushd "$BUILD_DIR/caelestia-cli" >/dev/null

    # The CLI is a Python project built with hatchling
    if [[ -f "pyproject.toml" ]]; then
        log_info "Building Python-based CLI with pip..."
        sudo pip install --break-system-packages --prefix="$INSTALL_PREFIX" . 2>&1 || \
        pip install --break-system-packages --user . 2>&1
        # Also install the shell helper script
        if [[ -f "bin/caelestia" ]]; then
            # Patch launcher to include QML and lib paths
            cat << 'EOF' > bin/caelestia.new
#!/usr/bin/env sh
export QML2_IMPORT_PATH="/usr/local/lib/qt6/qml:/usr/local/lib/x86_64-linux-gnu/qt6/qml:${QML2_IMPORT_PATH:-}"
export LD_LIBRARY_PATH="/usr/local/lib:/usr/local/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
python3 -m caelestia "$@"
EOF
            chmod +x bin/caelestia.new
            sudo install -Dm755 bin/caelestia.new "$INSTALL_PREFIX/bin/caelestia" 2>/dev/null || true
        fi
        # Install completions
        if [[ -d "completions" ]]; then
            sudo install -Dm644 completions/* "$INSTALL_PREFIX/share/bash-completion/completions/" 2>/dev/null || true
        fi
    elif [[ -f "go.mod" ]]; then
        log_info "Building Go-based CLI..."
        go build -o caelestia ./...  2>&1 || go build -o caelestia . 2>&1
        sudo install -Dm755 caelestia "$INSTALL_PREFIX/bin/caelestia"
    elif [[ -f "Cargo.toml" ]]; then
        log_info "Building Rust-based CLI..."
        if ! command -v cargo &>/dev/null; then
            log_info "Installing Rust toolchain..."
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            source "$HOME/.cargo/env"
        fi
        cargo build --release 2>&1
        sudo install -Dm755 target/release/caelestia "$INSTALL_PREFIX/bin/caelestia" 2>/dev/null || \
        sudo install -Dm755 target/release/caelestia-cli "$INSTALL_PREFIX/bin/caelestia" 2>/dev/null
    elif [[ -f "CMakeLists.txt" ]]; then
        log_info "Building CMake-based CLI..."
        cmake_build_install "$BUILD_DIR/caelestia-cli"
    elif [[ -f "Makefile" ]]; then
        log_info "Building Make-based CLI..."
        make -j "$JOBS" 2>&1
        sudo make install PREFIX="$INSTALL_PREFIX" 2>&1
    else
        log_warn "Could not detect build system for caelestia-cli. Trying meson..."
        meson_build_install "$BUILD_DIR/caelestia-cli"
    fi

    popd >/dev/null 2>/dev/null || true
    log_success "caelestia-cli installed"
}

# ----------------------------------
# Step 5: Build & Install Helper Tools
# ----------------------------------
install_helper_tools() {
    log_step "Step 5/8: Building helper tools"

    # 5a. app2unit
    log_info "Installing app2unit..."
    clone_or_update "$APP2UNIT_REPO" "$BUILD_DIR/app2unit"
    sudo install -Dm755 "$BUILD_DIR/app2unit/app2unit" "$INSTALL_PREFIX/bin/app2unit" 2>/dev/null || {
        pushd "$BUILD_DIR/app2unit" >/dev/null
        if [[ -f "Makefile" ]]; then
            make -j "$JOBS" 2>&1
            sudo make install PREFIX="$INSTALL_PREFIX" 2>&1
        elif [[ -f "install.sh" ]]; then
            sudo ./install.sh 2>&1
        else
            # It's likely a single script
            local script
            script=$(find . -maxdepth 1 -type f -executable -name "app2unit*" | head -1)
            if [[ -n "$script" ]]; then
                sudo install -Dm755 "$script" "$INSTALL_PREFIX/bin/app2unit"
            else
                log_warn "Could not install app2unit automatically. You may need to install it manually."
            fi
        fi
        popd >/dev/null
    }
    log_success "app2unit installed"

    # 5b. libcava (shared library for audio visualiser)
    log_info "Building libcava..."
    clone_or_update "$LIBCAVA_REPO" "$BUILD_DIR/cava"
    pushd "$BUILD_DIR/cava" >/dev/null
    if [[ ! -f configure ]]; then
        ./autogen.sh 2>&1 || {
            autoreconf -fi 2>&1
        }
    fi
    ./configure --prefix="$INSTALL_PREFIX" --enable-shared --disable-static 2>&1 || true
    make -j "$JOBS" 2>&1 || true
    sudo make install 2>&1 || {
        log_warn "libcava build had issues. The audio visualiser may not work."
    }
    popd >/dev/null
    sudo ldconfig
    log_success "libcava installed (or attempted)"
}

# ----------------------------------
# Step 6: Install Fonts
# ----------------------------------
install_fonts() {
    log_step "Step 6/8: Installing fonts"

    local font_dir="$HOME/.local/share/fonts"
    mkdir -p "$font_dir"

    # Material Symbols Rounded
    log_info "Downloading Material Symbols Rounded..."
    curl -fsSL -o "$font_dir/MaterialSymbolsRounded.ttf" \
        "$MATERIAL_SYMBOLS_URL" 2>&1 || {
        log_warn "Failed to download Material Symbols. Trying alternative..."
        # Try the variable font name variant
        curl -fsSL -o "$font_dir/MaterialSymbolsRounded.ttf" \
            "https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf" 2>&1 || \
        log_warn "Could not download Material Symbols font. Install it manually from https://fonts.google.com/icons"
    }

    # CaskaydiaCove Nerd Font
    log_info "Downloading CaskaydiaCove Nerd Font..."
    local nf_tmp
    nf_tmp=$(mktemp -d)
    curl -fsSL -o "$nf_tmp/CascadiaCode.zip" "$NERD_FONTS_URL" 2>&1
    unzip -o "$nf_tmp/CascadiaCode.zip" -d "$font_dir/" '*.ttf' 2>&1 || \
    unzip -o "$nf_tmp/CascadiaCode.zip" -d "$font_dir/" 2>&1
    rm -rf "$nf_tmp"

    # Rubik font (used for clock and sans)
    log_info "Installing Rubik font..."
    sudo apt-get install -y fonts-rubik 2>/dev/null || {
        local rubik_tmp
        rubik_tmp=$(mktemp -d)
        curl -fsSL -o "$rubik_tmp/rubik.zip" \
            "https://fonts.google.com/download?family=Rubik" 2>&1
        unzip -o "$rubik_tmp/rubik.zip" -d "$font_dir/" '*.ttf' 2>&1 || true
        rm -rf "$rubik_tmp"
    }

    # Rebuild font cache
    fc-cache -fv 2>&1
    log_success "Fonts installed"
}

# ----------------------------------
# Step 7: Build caelestia-shell
# ----------------------------------
build_caelestia_shell() {
    log_step "Step 7/8: Building caelestia-shell"

    local shell_dir

    if [[ "${USE_LOCAL_REPO:-false}" == "true" ]]; then
        shell_dir="$SCRIPT_DIR"
        log_info "Building from local repo at: $shell_dir"
    else
        shell_dir="$BUILD_DIR/caelestia-shell"
        clone_or_update "$SHELL_REPO" "$shell_dir"

        # Ensure the plugin submodule is initialized
        pushd "$shell_dir" >/dev/null
        git submodule update --init --recursive 2>&1
        popd >/dev/null
    fi

    # Verify critical directories exist
    local missing=false
    for required_dir in plugin services utils components modules; do
        if [[ ! -d "$shell_dir/$required_dir" ]]; then
            log_error "Missing directory: $shell_dir/$required_dir"
            missing=true
        fi
    done
    if [[ "$missing" == "true" ]]; then
        die "Required directories missing. If using a ZIP download, clone with: git clone --recursive $SHELL_REPO"
    fi
    log_success "All required directories verified (plugin, services, utils, components, modules)"

    # Set up environment for finding Quickshell and Caelestia dependencies
    export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
    export QML2_IMPORT_PATH="/usr/local/lib/qt6/qml:/usr/local/lib/x86_64-linux-gnu/qt6/qml:${QML2_IMPORT_PATH:-}"

    pushd "$shell_dir" >/dev/null

    # Check Qt version at build time (the plugin CMake will fail if < 6.9)
    local qt_version
    qt_version=$(qmake6 -query QT_VERSION 2>/dev/null || echo "unknown")
    log_info "Building with Qt $qt_version"

    # Build with CMake
    cmake -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/ \
        -DINSTALL_LIBDIR="usr/local/lib/caelestia" \
        -DINSTALL_QMLDIR="usr/local/lib/qt6/qml" \
        -DINSTALL_QSCONFDIR="etc/xdg/quickshell/caelestia" \
        -DDISTRIBUTOR="ubuntu-installer" \
        -DENABLE_MODULES="extras;plugin;shell" 2>&1

    cmake --build build -j "$JOBS" 2>&1
    sudo cmake --install build 2>&1
    popd >/dev/null

    sudo ldconfig
    log_success "caelestia-shell installed"
}

# ----------------------------------
# Step 8: Configure System
# ----------------------------------
configure_system() {
    log_step "Step 8/8: Configuring system"

    # 8a. Desktop session file
    log_info "Installing Hyprland desktop session..."
    sudo mkdir -p /usr/share/wayland-sessions
    sudo tee /usr/share/wayland-sessions/caelestia-hyprland.desktop > /dev/null << 'DESKTOP_EOF'
[Desktop Entry]
Name=Caelestia (Hyprland)
Comment=Caelestia desktop shell on Hyprland compositor
Exec=caelestia-session
Type=Application
DesktopNames=Hyprland
DESKTOP_EOF

    # 8b. Session wrapper script
    sudo tee /usr/local/bin/caelestia-session > /dev/null << 'SESSION_EOF'
#!/usr/bin/env bash
# Caelestia session launcher for Ubuntu
# This script starts Hyprland with caelestia-shell auto-loaded

# Ensure caelestia libs are findable
export CAELESTIA_LIB_DIR="${CAELESTIA_LIB_DIR:-/usr/local/lib/caelestia}"
export QML2_IMPORT_PATH="/usr/local/lib/qt6/qml:${QML2_IMPORT_PATH:-}"
export LD_LIBRARY_PATH="/usr/local/lib:/usr/local/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

# XDG defaults
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=Hyprland

# Qt Wayland
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# Start Hyprland
exec Hyprland
SESSION_EOF
    sudo chmod +x /usr/local/bin/caelestia-session

    # 8c. PAM configuration for lock screen
    log_info "Setting up PAM configuration..."
    if [[ ! -f /etc/pam.d/caelestia ]]; then
        sudo tee /etc/pam.d/caelestia > /dev/null << 'PAM_EOF'
#%PAM-1.0

# Ubuntu-adapted PAM config for caelestia lock screen
auth    required        pam_faillock.so     preauth
auth    [success=1 default=bad]     pam_unix.so     nullok
auth    [default=die]   pam_faillock.so     authfail
auth    required        pam_faillock.so     authsucc
PAM_EOF
    fi

    # 8d. Create default Hyprland config that auto-starts the shell
    local hypr_config_dir="$HOME/.config/hypr"
    mkdir -p "$hypr_config_dir"

    if [[ ! -f "$hypr_config_dir/hyprland.conf" ]]; then
        log_info "Creating default Hyprland config..."
        tee "$hypr_config_dir/hyprland.conf" > /dev/null << 'HYPR_EOF'
# ============================================================================
# Hyprland config for caelestia-shell (Ubuntu)
# Generated by caelestia-shell Ubuntu installer
# ============================================================================

# Monitor configuration (auto-detect)
monitor = , preferred, auto, 1

# Auto-start caelestia shell
exec-once = caelestia shell -d

# Input configuration
input {
    kb_layout = us
    follow_mouse = 1
    sensitivity = 0
    touchpad {
        natural_scroll = true
    }
}

# General appearance
general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(9ccbfbee) rgba(d3bfe6ee) 45deg
    col.inactive_border = rgba(595959aa)
    layout = dwindle
}

# Decoration
decoration {
    rounding = 12
    blur {
        enabled = true
        size = 8
        passes = 2
        new_optimizations = true
    }
    shadow {
        enabled = true
        range = 20
        render_power = 3
    }
}

# Animations
animations {
    enabled = true
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 7, myBezier
    animation = windowsOut, 1, 7, default, popin 80%
    animation = border, 1, 10, default
    animation = fade, 1, 7, default
    animation = workspaces, 1, 6, default
}

# Layout
dwindle {
    pseudotile = true
    preserve_split = true
}

# Keybinds for caelestia shell (global shortcuts)
bind = SUPER, RETURN, exec, foot
bind = SUPER, Q, killactive
bind = SUPER, M, exit
bind = SUPER, E, exec, thunar
bind = SUPER, V, togglefloating
bind = SUPER, P, pseudo
bind = SUPER, J, togglesplit

# Move focus
bind = SUPER, left, movefocus, l
bind = SUPER, right, movefocus, r
bind = SUPER, up, movefocus, u
bind = SUPER, down, movefocus, d

# Workspaces
bind = SUPER, 1, workspace, 1
bind = SUPER, 2, workspace, 2
bind = SUPER, 3, workspace, 3
bind = SUPER, 4, workspace, 4
bind = SUPER, 5, workspace, 5
bind = SUPER, 6, workspace, 6
bind = SUPER, 7, workspace, 7
bind = SUPER, 8, workspace, 8
bind = SUPER, 9, workspace, 9
bind = SUPER, 0, workspace, 10

# Move to workspace
bind = SUPER SHIFT, 1, movetoworkspace, 1
bind = SUPER SHIFT, 2, movetoworkspace, 2
bind = SUPER SHIFT, 3, movetoworkspace, 3
bind = SUPER SHIFT, 4, movetoworkspace, 4
bind = SUPER SHIFT, 5, movetoworkspace, 5
bind = SUPER SHIFT, 6, movetoworkspace, 6
bind = SUPER SHIFT, 7, movetoworkspace, 7
bind = SUPER SHIFT, 8, movetoworkspace, 8
bind = SUPER SHIFT, 9, movetoworkspace, 9
bind = SUPER SHIFT, 0, movetoworkspace, 10

# Scroll through workspaces
bind = SUPER, mouse_down, workspace, e+1
bind = SUPER, mouse_up, workspace, e-1

# Move/resize windows
bindm = SUPER, mouse:272, movewindow
bindm = SUPER, mouse:273, resizewindow

# Caelestia global shortcuts
bind = SUPER, D, global, caelestia:launcher
bind = SUPER, A, global, caelestia:dashboard
bind = SUPER SHIFT, A, global, caelestia:showall
bind = SUPER, S, global, caelestia:sidebar
bind = SUPER, N, global, caelestia:utilities
bind = SUPER, ESCAPE, global, caelestia:session
bind = SUPER SHIFT, S, global, caelestia:controlCenter

# Source user overrides
source = ~/.config/caelestia/hypr-user.conf
HYPR_EOF
    else
        log_info "Hyprland config already exists, skipping..."
    fi

    # 8e. Create caelestia config dir
    mkdir -p "$HOME/.config/caelestia"
    mkdir -p "$HOME/Pictures/Wallpapers"

    # 8f. Create user override file (empty)
    touch "$HOME/.config/caelestia/hypr-user.conf" 2>/dev/null || true

    # 8g. Ensure ldconfig is up to date
    sudo ldconfig

    log_success "System configured"
}

# ----------------------------------
# Summary
# ----------------------------------
print_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}============================================================================${NC}"
    echo -e "${GREEN}${BOLD}  caelestia-shell installation complete!${NC}"
    echo -e "${GREEN}${BOLD}============================================================================${NC}"
    echo ""
    echo -e "  ${BOLD}What was installed:${NC}"
    echo -e "    • Hyprland compositor (+ hyprutils, hyprlang, aquamarine, etc.)"
    echo -e "    • Quickshell (Qt6/QML shell framework)"
    echo -e "    • caelestia-cli (command-line interface)"
    echo -e "    • caelestia-shell (the desktop shell)"
    echo -e "    • Fonts: Material Symbols, CaskaydiaCove Nerd, Rubik"
    echo -e "    • Helper tools: app2unit, libcava, etc."
    echo ""
    echo -e "  ${BOLD}How to start:${NC}"
    echo -e "    1. Log out of your current session"
    echo -e "    2. On the login screen, select ${CYAN}\"Caelestia (Hyprland)\"${NC} as the session"
    echo -e "    3. Log in"
    echo ""
    echo -e "  ${BOLD}Configuration:${NC}"
    echo -e "    • Shell config:    ${CYAN}~/.config/caelestia/shell.json${NC}"
    echo -e "    • Hyprland config: ${CYAN}~/.config/hypr/hyprland.conf${NC}"
    echo -e "    • User overrides:  ${CYAN}~/.config/caelestia/hypr-user.conf${NC}"
    echo -e "    • Wallpapers:      ${CYAN}~/Pictures/Wallpapers/${NC}"
    echo ""
    echo -e "  ${BOLD}Build sources saved to:${NC}"
    echo -e "    ${CYAN}${BUILD_DIR}${NC}"
    echo ""
    echo -e "  ${BOLD}To uninstall:${NC}"
    echo -e "    ${CYAN}./uninstall-ubuntu.sh${NC}"
    echo ""
    echo -e "${GREEN}${BOLD}============================================================================${NC}"
}

# ----------------------------------
# Main
# ----------------------------------
main() {
    echo -e "${CYAN}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════════════════╗"
    echo "  ║         caelestia-shell — Ubuntu 26.04 Installer         ║"
    echo "  ╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  This will install Hyprland, Quickshell, and caelestia-shell"
    echo -e "  from source. This process takes ${BOLD}30-60 minutes${NC} depending"
    echo -e "  on your hardware."
    echo ""
    read -rp "  Continue? [Y/n] " yn
    [[ "$yn" =~ ^[Nn]$ ]] && exit 0

    local start_time
    start_time=$(date +%s)

    preflight_checks
    install_apt_deps
    build_hyprland_ecosystem
    build_quickshell
    build_caelestia_cli
    install_helper_tools
    install_fonts
    build_caelestia_shell
    configure_system
    print_summary

    local end_time elapsed_min
    end_time=$(date +%s)
    elapsed_min=$(( (end_time - start_time) / 60 ))
    echo -e "  ${BOLD}Total time: ${elapsed_min} minutes${NC}"
    echo ""
}

main "$@"
