<h1 align=center>caelestia-shell — Ubuntu 26.04 Port</h1>

<div align=center>

[![Original Repo](https://img.shields.io/badge/Original-caelestia--dots%2Fshell-9ccbfb?style=for-the-badge&labelColor=101418)](https://github.com/caelestia-dots/shell)
![Ubuntu](https://img.shields.io/badge/Ubuntu-26.04-E95420?style=for-the-badge&logo=ubuntu&logoColor=white&labelColor=101418)
![Hyprland](https://img.shields.io/badge/Hyprland-from%20source-d3bfe6?style=for-the-badge&labelColor=101418)

</div>

<p align=center>
  <strong>A fully automated, one-command installer for the Caelestia Shell (Hyprland) ecosystem on Ubuntu 26.04.</strong>
</p>

---

## 🎥 Preview

https://github.com/user-attachments/assets/0840f496-575c-4ca6-83a8-87bb01a85c5f

## ✨ What is this?

This is an **Ubuntu 26.04 port** of the incredible [Caelestia Shell](https://github.com/caelestia-dots/shell) — a beautiful, feature-rich desktop shell built on [Hyprland](https://hyprland.org) and [Quickshell](https://quickshell.outfoxxed.me).

The original project targets Arch Linux and NixOS. This fork provides a **fully automated build-from-source installer** that handles the entire dependency chain on Ubuntu 26.04, where many Hyprland ecosystem packages are either missing or too old.

## 🧩 Components

| Component | Description |
|-----------|-------------|
| **Hyprland** | Tiling Wayland compositor (built from source) |
| **Quickshell** | Qt6/QML-based shell framework (built from source) |
| **Caelestia Shell** | The actual desktop shell (bar, widgets, launcher, sidebar, notifications) |
| **Caelestia CLI** | Python CLI tool for managing wallpapers, color schemes, screenshots, etc. |
| **12 Hyprland libs** | hyprutils, hyprlang, hyprwayland-scanner, hyprgraphics, hyprcursor, hyprland-protocols, aquamarine, hyprtoolkit, and more |

## 🚀 Quick Install

```bash
git clone https://github.com/StarDust-Git-Code/caelestia-shell-ubuntu_26.git
cd caelestia-shell-ubuntu_26
chmod +x auto-install.sh
./auto-install.sh
```

The installer is **resumable** — if it fails at any step, just run `./auto-install.sh` again and it will pick up where it left off.

## 📋 What the Installer Does

1. **Pre-flight checks** — Verifies Ubuntu version, sudo access, disk space
2. **APT dependencies** — Installs ~80+ build tools and dev libraries
3. **Hyprland ecosystem** — Builds 12 components from source with correct ordering
4. **Quickshell** — Builds the Qt6/QML shell framework (1200+ source files)
5. **caelestia-cli** — Installs the Python management tool
6. **Helper tools** — Builds app2unit, libcava, swappy from source
7. **Fonts** — Installs Material Symbols and CaskaydiaCove Nerd Font
8. **caelestia-shell** — Builds and installs the shell QML modules
9. **System configuration** — Creates desktop session file, PAM config, default Hyprland config

## 🔧 Post-Install Setup

After installation completes:

1. **Log out** of your current session
2. On the login screen, click the **gear icon** ⚙️
3. Select **"Caelestia (Hyprland)"**
4. Log in!

### Recommended post-install steps

```bash
# Add yourself to the video group for brightness control
sudo usermod -aG video $USER

# Install icon theme
sudo apt-get install -y papirus-icon-theme

# Install Hyprland dialog utilities
sudo apt-get install -y hyprland-qtutils

# Install sass compiler (for Discord theming)
sudo apt-get install -y sassc

# Set a wallpaper (generates Material You color scheme)
caelestia wallpaper -r /usr/share/backgrounds/
```

## ⌨️ Default Keybinds

| Key | Action |
|-----|--------|
| `Super + Return` | Open terminal (foot) |
| `Super + D` | App launcher |
| `Super + Q` | Close window |
| `Super + V` | Toggle floating |
| `Super + S` | Sidebar |
| `Super + A` | Dashboard |
| `Super + Escape` | Session menu |
| `Super + 1-9` | Switch workspace |
| `Super + Shift + 1-9` | Move window to workspace |
| `Super + M` | Exit Hyprland |

## 🔨 Technical Details

### Build Strategy

Ubuntu 26.04 ships older versions of Hyprland libraries that conflict with building from source. The installer:

- **Removes conflicting system packages** (`libhyprutils-dev`, `libaquamarine-dev`, etc.) before building
- **Sets custom library paths** (`CMAKE_LIBRARY_PATH`, `LD_LIBRARY_PATH`) to prioritize `/usr/local` builds
- **Builds in dependency order** to ensure each component finds the correct versions
- **Disables unavailable features** (e.g., `CRASH_HANDLER=OFF` for Quickshell, since `cpptrace` isn't available)

### File Locations

| Item | Path |
|------|------|
| Source builds | `~/.local/src/caelestia-build/` |
| Installed binaries | `/usr/local/bin/` |
| Installed libraries | `/usr/local/lib/` |
| Shell QML files | `/etc/xdg/quickshell/caelestia/` |
| QML plugins | `/usr/local/lib/qt6/qml/Caelestia/` |
| Hyprland config | `~/.config/hypr/hyprland.conf` |
| Session file | `/usr/share/wayland-sessions/caelestia.desktop` |

## 🗑️ Uninstall

```bash
./uninstall-ubuntu.sh
```

## 🙏 Credits

### Original Project

**[Caelestia Shell](https://github.com/caelestia-dots/shell)** by the [caelestia-dots](https://github.com/caelestia-dots) team.

All design, QML shell code, services, and the CLI tool are the work of the original Caelestia developers. Please consider supporting them:

- ⭐ [Star the original repo](https://github.com/caelestia-dots/shell)
- ☕ [Donate on Ko-Fi](https://ko-fi.com/soramane)
- 💬 [Join the Discord](https://discord.gg/BGDCFCmMBk)

### Ubuntu 26.04 Port

Ported and maintained by **[StarDust](https://github.com/StarDust-Git-Code)**.

- Wrote the automated Ubuntu build system (`install-ubuntu.sh`, `auto-install.sh`)
- Resolved dependency chains, linker conflicts, and package version mismatches
- Created the resumable, state-aware installation workflow

## 📄 License

Same license as the original [caelestia-shell](https://github.com/caelestia-dots/shell) — see [LICENSE](LICENSE).
