# Laptop Setup & Quickstart Guide

This document covers credentials, first-boot workflow, Hyprland desktop shortcuts, and maintenance for the `laptop` NixOS configuration.

---

## 1. System Credentials & Access

| Resource | Value / Setting | Notes |
| :--- | :--- | :--- |
| **LUKS Encryption Passphrase** | *(Set during Disko step)* | Required on every cold boot / reboot to unlock Btrfs container. |
| **Primary User** | `johannes` | Defined in [`modules/core/base.nix`](file:///home/johannes/code/nixos-config/modules/core/base.nix). |
| **Default Password** | `changeme` | Initial password. **Change immediately after first login** with `passwd`. |
| **Sudo Privileges** | Passwordless | `security.sudo.wheelNeedsPassword = false` is active. |
| **Root User** | Passwordless / Locked | Use `sudo -s` or `sudo <command>` from the `johannes` account. |
| **SSH Access** | Port `22` | Preloaded with your SSH public keys from `modules/core/base.nix`. |

---

## 2. First Boot Checklist

1. **Boot & Unlock Storage**
   - Power on the machine with the NVMe SSD installed.
   - At the `systemd-cryptsetup` prompt, type your **LUKS encryption passphrase**.

2. **Log In (tuigreet)**
   - Enter username: `johannes`
   - Enter password: `changeme` (or the password you provided during installation).
   - Press **Enter** to launch the Hyprland Wayland session.

3. **Change Default Password**
   - Open a terminal (`Super + Enter`).
   - Run:
     ```bash
     passwd
     ```

4. **Connect to Wi-Fi**
   - Using terminal CLI:
     ```bash
     nmcli dev wifi list
     nmcli dev wifi connect "<SSID>" password "<PASSWORD>"
     ```
   - Or launch the interactive TUI:
     ```bash
     nmtui
     ```

5. **Hardware Driver Check**
   - Inspect detected hardware against default kernel modules:
     ```bash
     nixos-generate-config --show-hardware-config
     ```
   - If any missing proprietary/vendor drivers are reported (e.g., specific WiFi/Bluetooth firmware), add them to [`hosts/laptop/hardware-configuration.nix`](file:///home/johannes/code/nixos-config/hosts/laptop/hardware-configuration.nix).

---

## 3. Essential Hyprland Keybindings

The `SUPER` key is the Windows / Command key.

### Window Management & Launchers
- `Super + Enter` : Open Terminal (**Kitty**)
- `Super + Space` : Open Application Launcher (**Wofi**)
- `Super + Q` : Close / Kill active window
- `Super + F` : Toggle Fullscreen
- `Super + V` : Toggle Floating window
- `Super + M` : Exit Hyprland session (back to login screen)

### Navigation & Workspaces
- `Super + Left / Right / Up / Down` : Move focus between windows
- `Super + 1 .. 9` : Switch to Workspace `1` through `9`
- `Super + Shift + 1 .. 9` : Move focused window to Workspace `1` through `9`
- `Super + Left Mouse Drag` : Move window
- `Super + Right Mouse Drag` : Resize window

---

## 4. Rebuilding & Modifying Configuration

The system is managed declaratively via Flakes and Home-Manager.

### Applying Changes
After making edits to `/home/johannes/code/nixos-config/`:

```bash
# Using the pre-configured alias:
rebuild

# Or standard NixOS command:
sudo nixos-rebuild switch --flake /home/johannes/code/nixos-config#laptop
```

### Key Configuration Files
- **System Services, Boot, Display Manager:** [`hosts/laptop/configuration.nix`](file:///home/johannes/code/nixos-config/hosts/laptop/configuration.nix)
- **User Config, Shell, Hyprland Dotfiles:** [`hosts/laptop/home.nix`](file:///home/johannes/code/nixos-config/hosts/laptop/home.nix)
- **Disk & Btrfs Subvolume Layout:** [`hosts/laptop/disko-config.nix`](file:///home/johannes/code/nixos-config/hosts/laptop/disko-config.nix)
- **Hardware Drivers & Kernel Modules:** [`hosts/laptop/hardware-configuration.nix`](file:///home/johannes/code/nixos-config/hosts/laptop/hardware-configuration.nix)
