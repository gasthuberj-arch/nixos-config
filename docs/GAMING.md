# Gaming Setup Guide

This document describes the gaming and game streaming configuration for the homelab server.

## Overview

The gaming module provides:
- **Sunshine**: Game streaming server (compatible with Moonlight clients)
- **Emulators**: Collection of gaming console emulators
- **Performance optimizations**: GameMode and hardware acceleration

## Sunshine Game Streaming

Sunshine is a self-hosted game streaming server that works with Moonlight clients.

### Configuration

Located in `modules/services/gaming.nix`:

```nix
services.gaming.sunshine = {
  enable = true;
  openFirewall = true;
};
```

### Web Interface

After enabling, access the Sunshine web UI at:
- HTTPS: `https://homelab.lan:47984`
- HTTP: `http://homelab.lan:47989`

### First-Time Setup

1. Access the web UI
2. Create an admin account
3. Configure your streaming settings:
   - Resolution and FPS
   - Video codec (H.264, HEVC, AV1)
   - Bitrate
4. Add games/applications to stream

### Client Setup

Install Moonlight on your client device:
- **Windows/Mac/Linux**: [Moonlight PC](https://github.com/moonlight-stream/moonlight-qt)
- **Android**: Moonlight from Google Play Store
- **iOS**: Moonlight from App Store
- **Steam Deck**: Available in Discover

### Firewall Ports

The following ports are opened automatically:
- **47984**: HTTPS Web UI
- **47989**: HTTP Web UI
- **47990**: RTSP
- **48010**: Video stream
- **47998/UDP**: Video
- **47999/UDP**: Control
- **48000/UDP**: Audio
- **48002/UDP**: Control

### Data Persistence

Sunshine configuration is persisted at:
- `/persist/var/lib/sunshine`

This survives reboots thanks to impermanence.

## Emulators

The following emulators are installed and configured:

### RetroArch
- **Systems**: NES, SNES, Genesis, Game Boy, GBA, and many more
- **Config**: `~/.config/retroarch`
- **Saves**: `~/.config/retroarch/saves`
- Launch from GNOME applications menu

### Dolphin
- **Systems**: GameCube, Wii
- **Config**: `~/.config/dolphin-emu`
- **Saves**: `~/.local/share/dolphin-emu`

### PCSX2
- **System**: PlayStation 2
- **Config**: `~/.config/PCSX2`
- **Saves**: `~/.local/share/PCSX2`
- **BIOS Required**: Place PS2 BIOS files in the BIOS directory

### RPCS3
- **System**: PlayStation 3
- **Config**: `~/.config/rpcs3`
- **Saves**: `~/.local/share/rpcs3`
- **Firmware Required**: Install PS3 firmware through the emulator

### DuckStation
- **System**: PlayStation 1
- **Config**: `~/.config/duckstation`
- **Saves**: `~/.local/share/duckstation`
- **BIOS Required**: Place PS1 BIOS files in the BIOS directory
- **⚠️ License Note**: DuckStation has a non-commercial license (CC BY-NC-ND 4.0) and is **disabled by default**
- **Alternatives**: Consider using `mednafen`, `epsxe`, or the RetroArch beetle-psx core for PS1 emulation

### Cemu
- **System**: Wii U
- **Config**: `~/.config/Cemu`
- **Note**: Requires Wii U game dumps and updates

### Ryubing
- **System**: Nintendo Switch
- **Config**: `~/.config/Ryubing`
- **Saves**: `~/.local/share/Ryubing`
- **Keys Required**: Requires prod.keys and title.keys
- **Note**: Formerly known as Ryujinx

### PPSSPP
- **System**: PlayStation Portable (PSP)
- **Config**: `~/.config/ppsspp`

## Customization

### Enable/Disable Individual Emulators

Edit `hosts/homelab/configuration.nix`:

```nix
services.gaming.emulators = {
  enable = true;
  retroarch = true;     # Set to false to disable
  dolphin = true;
  pcsx2 = true;
  rpcs3 = true;
  duckstation = false;  # Disabled by default - see license note
  cemu = true;
  ryubing = true;
  ppsspp = true;
};
```

### Disable Game Streaming

```nix
services.gaming.sunshine.enable = false;
```

### Disable All Gaming Features

```nix
services.gaming.enable = false;
```

## Performance Optimization

### GameMode

GameMode is automatically enabled when emulators are active. It optimizes system performance for gaming by:
- Adjusting CPU governor
- Setting process priorities
- Disabling screen savers

Games will automatically use GameMode when launched.

### Hardware Acceleration

32-bit graphics drivers are enabled for compatibility with older games and emulators:

```nix
hardware.graphics = {
  enable = true;
  enable32Bit = true;
};
```

## Storage Recommendations

### ROM Storage

Consider storing ROMs on the ZFS media pool for:
- Large storage capacity
- Data integrity
- Easy backups

Suggested structure:
```
/media/games/
├── roms/
│   ├── nes/
│   ├── snes/
│   ├── gba/
│   ├── ps1/
│   ├── ps2/
│   ├── gamecube/
│   ├── wii/
│   └── switch/
└── bios/
```

### Save Data

Emulator saves and configuration are automatically persisted to `/persist` via impermanence, so they survive reboots.

## Troubleshooting

### Sunshine Won't Start

1. Check the service status:
   ```bash
   systemctl status sunshine
   ```

2. View logs:
   ```bash
   journalctl -u sunshine -f
   ```

3. Ensure X11 session is running (required for capturing)

### Emulator Performance Issues

1. Enable GameMode manually:
   ```bash
   gamemoderun <emulator-command>
   ```

2. Check GPU drivers:
   ```bash
   glxinfo | grep "OpenGL renderer"
   vulkaninfo | grep "deviceName"
   ```

3. Monitor system resources:
   ```bash
   htop
   ```

### Can't Connect to Sunshine

1. Verify firewall ports are open:
   ```bash
   sudo nix-shell -p nmap --run "nmap -p 47984,47989 localhost"
   ```

2. Check if Sunshine is listening:
   ```bash
   sudo netstat -tlnp | grep sunshine
   ```

3. Try accessing via IP instead of hostname

## Security Considerations

### Sunshine Access

- Sunshine web UI is accessible on your local network
- Consider setting up authentication in Sunshine settings
- For external access, use a VPN or reverse proxy with authentication

### Firewall

- Gaming ports are only opened on the local network
- For internet access, configure port forwarding carefully
- Consider using Tailscale or WireGuard for secure remote gaming

### DuckStation License

DuckStation uses a Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 International license, which:
- Prohibits commercial use
- Prohibits creating derivative works
- Is more restrictive than typical "unfree" software

If you wish to use DuckStation, you must:
1. Understand and accept the license terms
2. Enable it explicitly in your configuration:
   ```nix
   services.gaming.emulators.duckstation = true;
   ```

**Recommended alternatives for PS1 emulation:**
- **Mednafen**: Accurate, open-source, supports many systems
- **RetroArch with Beetle PSX core**: Part of the RetroArch suite (already enabled)
- **EPSXE**: Popular PS1 emulator (may need manual installation)

## Rebuilding After Changes

After modifying the gaming configuration:

```bash
sudo nixos-rebuild switch --flake .#homelab
```

Or use the deployment script:

```bash
./deploy.sh
```

## Further Reading

- [Sunshine Documentation](https://docs.lizardbyte.dev/projects/sunshine/en/latest/)
- [Moonlight Documentation](https://github.com/moonlight-stream/moonlight-docs/wiki)
- [RetroArch Documentation](https://docs.libretro.com/)
- [Emulation Wiki](https://emulation.gametechwiki.com/)