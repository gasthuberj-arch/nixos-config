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

## 3. Essential Hyprland Keybindings & Drill Routines

The `SUPER` key is the Windows / Command key.

### Quick Reference Table

| Category | Shortcut | Action |
| :--- | :--- | :--- |
| **Launchers** | `Super + Enter` | Open Terminal (**Kitty**) |
| | `Super + Space` | Open Application Menu (**Wofi**) |
| | `Super + V` | Clipboard History (**Cliphist**) |
| **Window State** | `Super + Q` | Close / Kill focused window |
| | `Super + F` | Toggle Fullscreen |
| | `Super + Shift + Space` | Toggle Floating window |
| | `Super + M` | Exit Hyprland session |
| **Focus (Vim & Arrows)** | `Super + H / J / K / L` | Move focus Left / Down / Up / Right |
| | `Super + Left/Down/Up/Right`| Move focus Left / Down / Up / Right |
| **Window Movement** | `Super + Shift + H / J / K / L`| Swap window with neighbor |
| | `Super + Shift + Arrows` | Swap window with neighbor |
| **Workspaces** | `Super + 1 .. 9` | Switch to Workspace `1` through `9` |
| | `Super + Shift + 1 .. 9` | Send focused window to Workspace `1` through `9` |
| **Lock & Media** | `Super + L` | Lock Screen (**hyprlock**) |
| | `Super + Shift + S` / `Print` | Interactive Screenshot to Clipboard |
| | `Fn + Vol Up / Down / Mute` | Adjust volume via PipeWire (`wpctl`) |
| | `Fn + Brightness Up / Down` | Adjust backlight brightness (`brightnessctl`) |

---

## 4. Hyprland & Neovim Muscle Memory Drills

To build high-speed efficiency before Day 1, practice these 3 drill sequences:

### Drill 1: Window Management & Tiling (5 minutes)
1. Open 3 terminals: `Super + Enter` 3 times.
2. Focus between them using `Super + H`, `Super + J`, `Super + K`, `Super + L`.
3. Swap positions: press `Super + Shift + H` or `Super + Shift + L` to reorder columns.
4. Pop one into fullscreen with `Super + F`, inspect it, and un-fullscreen with `Super + F`.
5. Close them all: `Super + Q` 3 times.

### Drill 2: Workspaces & Multi-Tasking (5 minutes)
1. On Workspace 1 (`Super + 1`), open Kitty (`Super + Enter`).
2. Move to Workspace 2 (`Super + 2`), open Firefox via `Super + Space` -> type `firefox` -> `Enter`.
3. Move to Workspace 3 (`Super + 3`), open Google Chrome via `Super + Space` -> type `google-chrome` -> `Enter`.
4. Switch rapidly between your editor, documentation, and browser using `Super + 1`, `Super + 2`, `Super + 3`.
5. Send a window to Workspace 4: on that window press `Super + Shift + 4`, then jump to `Super + 4` to verify.

### Drill 3: Core Neovim Motions & CLI Flow (10 minutes)
1. In Kitty, launch `nvim test.txt`.
2. **Basic Navigation**: Use `h`, `j`, `k`, `l` (no arrow keys).
3. **Word Jumping**: `w` (next word start), `b` (prev word start), `e` (word end).
4. **Line Navigation**: `0` (start of line), `$` (end of line), `gg` (top of file), `G` (bottom of file).
5. **Editing Actions**:
   - `i` (insert before cursor), `a` (append after cursor), `o` (open new line below).
   - `ciw` (change inside word: deletes word and enters insert mode).
   - `dd` (delete line), `yy` (yank/copy line), `p` (paste line).
   - `u` (undo), `<Ctrl-r>` (redo).
6. **Save & Exit**: `:w` (save), `:q` (quit), `:wq` (save and quit).

---

## 5. Developer Tooling & Antigravity (agy)

### Installed Tooling Overview
- **CLI Utilities**: `ripgrep` (`rg`), `fd`, `fzf`, `bat`, `btop`, `eza` (aliased to `ls` / `ll`), `lazygit` (`lg`), `gh`, `zoxide` (`z <dir>`).
- **DevOps**: `kubectl` (`k`), `helm`, `k9s` (Kubernetes TUI), `stern`, `kubectx`.
- **Containers**: Docker daemon is active (`docker ps`, `docker compose`).
- **Environment Automation**: `direnv` + `nix-direnv` is active; dropping into a directory with `.envrc` automatically provisions the environment.

### Antigravity (`agy`) Binary Setup
`nix-ld` is enabled on the system, which allows pre-built dynamically linked x86_64 ELF binaries to run natively on NixOS.
- Ensure the `agy` binary is present in `~/.local/bin/agy`:
  ```bash
  mkdir -p ~/.local/bin
  # Copy agy or download to ~/.local/bin/agy
  chmod +x ~/.local/bin/agy
  ```
- Because `~/.local/bin` is in `$PATH`, run `agy` directly from any terminal.

---

## 6. Rebuilding & Modifying Configuration

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
- **System Services, Docker, Nix-LD, Fonts:** [`hosts/laptop/configuration.nix`](file:///home/johannes/code/nixos-config/hosts/laptop/configuration.nix)
- **User Tools, Neovim, Hyprland Bindings:** [`hosts/laptop/home.nix`](file:///home/johannes/code/nixos-config/hosts/laptop/home.nix)
- **Disk & Btrfs Subvolume Layout:** [`hosts/laptop/disko-config.nix`](file:///home/johannes/code/nixos-config/hosts/laptop/disko-config.nix)
- **Hardware Drivers & Kernel Modules:** [`hosts/laptop/hardware-configuration.nix`](file:///home/johannes/code/nixos-config/hosts/laptop/hardware-configuration.nix)
