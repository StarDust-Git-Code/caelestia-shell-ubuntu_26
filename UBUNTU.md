# Installing caelestia-shell on Ubuntu 26.04

This guide explains how to install caelestia-shell on Ubuntu 26.04 using the automated install script.

> [!WARNING]
> caelestia-shell is designed for the **Hyprland** Wayland compositor. Installing it will build Hyprland and its entire ecosystem from source. You will need to select the "Caelestia (Hyprland)" session at your login screen to use the shell. Your default GNOME/Ubuntu desktop will remain available.

## Quick Start

```bash
# Clone the full repository (with submodules!)
git clone --recursive https://github.com/caelestia-dots/shell.git
cd shell

# Make the installer executable and run it
chmod +x install-ubuntu.sh
./install-ubuntu.sh
```

The script takes **30-60 minutes** depending on your hardware. It will:

1. Install all build dependencies via `apt`
2. Build the Hyprland compositor and its libraries from source
3. Build Quickshell (the Qt6/QML shell framework)
4. Build the caelestia CLI tool
5. Build helper tools (app2unit, libcava)
6. Install required fonts (Material Symbols, CaskaydiaCove Nerd, Rubik)
7. Build and install caelestia-shell
8. Create a desktop session and default configuration

## Requirements

- **Ubuntu 26.04** (Noble Numbat or later)
- **~5 GB** free disk space (for build sources and compiled output)
- **Internet connection** (for downloading source code and fonts)
- **sudo** access
- A GPU with **Vulkan** and **OpenGL ES** support

## After Installation

1. **Log out** of your current session
2. Click the **gear icon** on the login screen
3. Select **"Caelestia (Hyprland)"**
4. Log in

### Default Keybinds

| Keybind | Action |
|---------|--------|
| `Super + Return` | Open terminal (foot) |
| `Super + Q` | Close window |
| `Super + D` | Open launcher |
| `Super + A` | Toggle dashboard |
| `Super + S` | Toggle sidebar |
| `Super + N` | Toggle utilities panel |
| `Super + Escape` | Session menu (logout/shutdown) |
| `Super + Shift + S` | Open control center |
| `Super + 1-0` | Switch workspace |
| `Super + Shift + 1-0` | Move window to workspace |

## Configuration

Configuration is done via JSON files:

| File | Purpose |
|------|---------|
| `~/.config/caelestia/shell.json` | Shell settings (create manually) |
| `~/.config/hypr/hyprland.conf` | Hyprland compositor settings |
| `~/.config/caelestia/hypr-user.conf` | Your custom Hyprland overrides |

See the main [README.md](README.md#configuring) for the full list of shell configuration options.

### Wallpapers

Place wallpapers in `~/Pictures/Wallpapers/` and they will appear in the launcher's wallpaper picker.

### Profile Picture

Copy your profile picture to `~/.face`:
```bash
cp /path/to/your/photo.jpg ~/.face
```

## Troubleshooting

### "Hyprland crashes on startup"

Ensure your GPU drivers support Vulkan:
```bash
vulkaninfo | head -20
```

If using NVIDIA, install the proprietary drivers:
```bash
sudo apt install nvidia-driver-560   # or latest available
```

### "Quickshell fails to find QML modules"

Ensure the import path is set:
```bash
export QML2_IMPORT_PATH="/usr/local/lib/qt6/qml:$QML2_IMPORT_PATH"
```

This should be set automatically by the session script, but you can add it to `~/.bashrc` as a fallback.

### "Fonts look wrong / icons are missing"

Rebuild the font cache:
```bash
fc-cache -fv
```

Verify Material Symbols is installed:
```bash
fc-list | grep -i "material"
```

### "Build fails with missing library"

If a build step fails because a library can't be found, try:
```bash
sudo ldconfig
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib/x86_64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH"
```

Then re-run `./install-ubuntu.sh` — it will skip already-built components.

## Updating

To update to the latest version:
```bash
cd ~/.local/src/caelestia-build/caelestia-shell
git pull --recurse-submodules
./install-ubuntu.sh  # Re-run from the shell repo
```

## Uninstalling

```bash
chmod +x uninstall-ubuntu.sh
./uninstall-ubuntu.sh
```

This removes all from-source installations but keeps APT packages (as they may be used by other software). It will optionally remove user configs and build sources.

## Known Limitations on Ubuntu

- **No AUR package**: Ubuntu doesn't have the Arch User Repository. All dependencies are built from source.
- **Library version mismatches**: Ubuntu may ship older versions of some libraries. The installer builds everything from source under `/usr/local/` to avoid conflicts.
- **Nix alternative**: If you prefer sandboxed installation, you can install the [Nix package manager](https://nixos.org/download.html) and run `nix run github:caelestia-dots/shell` instead. This still requires Hyprland to be running.
