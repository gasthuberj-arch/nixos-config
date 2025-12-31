# Gaming Setup - Quick Start

## What Was Added

Your NixOS homelab configuration now includes:

### 1. Sunshine Game Streaming Server
- **Purpose**: Stream games from your homelab to any device running Moonlight
- **Web UI**: https://homelab.lan:47984 (after enabling)
- **Status**: Enabled and configured
- **Firewall**: Automatically configured with all required ports

### 2. Gaming Emulators
The following emulators are now installed:

| Emulator | System | Status |
|----------|--------|--------|
| RetroArch | Multi-system (NES, SNES, GB, GBA, etc.) | ✅ Enabled |
| Dolphin | GameCube / Wii | ✅ Enabled |
| PCSX2 | PlayStation 2 | ✅ Enabled |
| RPCS3 | PlayStation 3 | ✅ Enabled |
| Cemu | Wii U | ✅ Enabled |
| Ryubing | Nintendo Switch | ✅ Enabled |
| PPSSPP | PSP | ✅ Enabled |
| DuckStation | PlayStation 1 | ❌ Disabled (license) |

### 3. Performance Optimizations
- **GameMode**: Automatically optimizes CPU/GPU performance for gaming
- **Hardware Acceleration**: 32-bit OpenGL/Vulkan drivers enabled
- **Persistence**: All emulator configs and save data persisted across reboots

## Files Created

1. **`modules/services/gaming.nix`** - Gaming module configuration
2. **`docs/GAMING.md`** - Comprehensive gaming documentation
3. **`GAMING_SETUP.md`** - This quick start guide

## Files Modified

1. **`hosts/homelab/configuration.nix`** - Added gaming module import and configuration
2. **`flake.nix`** - Added allowUnfreePredicate for emulator packages

## How to Deploy

### Option 1: Rebuild on the homelab server
```bash
cd /path/to/nixos-config
sudo nixos-rebuild switch --flake .#homelab
```

### Option 2: Use the deploy script
```bash
./deploy.sh
```

## First Steps After Deployment

### 1. Set Up Sunshine
1. Open browser to `https://homelab.lan:47984`
2. Create admin account
3. Configure streaming settings (resolution, codec, bitrate)
4. Add applications/games you want to stream

### 2. Install Moonlight Client
On your gaming device:
- **PC**: https://github.com/moonlight-stream/moonlight-qt/releases
- **Android**: Google Play Store
- **iOS**: App Store
- **Steam Deck**: Discover store

### 3. Set Up Emulators
Launch emulators from GNOME Applications menu:
- Configure controller/keyboard mappings
- Add BIOS files where required (PS1, PS2, PS3)
- Point to your ROM directories

## Recommended ROM Storage

Create organized ROM directories on your ZFS media pool:

```bash
sudo mkdir -p /media/games/{roms,bios,saves}
sudo mkdir -p /media/games/roms/{nes,snes,gba,ps1,ps2,ps3,gamecube,wii,wiiu,switch,psp}
sudo chown -R johannes:users /media/games
```

## Configuration Locations

All configuration stored under `/persist` (survives reboots):

- **Sunshine**: `/persist/var/lib/sunshine`
- **RetroArch**: `~/.config/retroarch`
- **Dolphin**: `~/.config/dolphin-emu`
- **PCSX2**: `~/.config/PCSX2`
- **RPCS3**: `~/.config/rpcs3`
- **Cemu**: `~/.config/Cemu`
- **Ryubing**: `~/.config/Ryubing`
- **PPSSPP**: `~/.config/ppsspp`

## Customization

### Disable Specific Emulators

Edit `hosts/homelab/configuration.nix`:

```nix
services.gaming.emulators = {
  enable = true;
  retroarch = true;
  dolphin = true;
  pcsx2 = false;    # Disable PS2 emulator
  rpcs3 = false;    # Disable PS3 emulator
  # ... etc
};
```

### Disable Sunshine

```nix
services.gaming.sunshine.enable = false;
```

### Disable All Gaming Features

```nix
services.gaming.enable = false;
```

## Network Ports

Sunshine uses the following ports (automatically opened):

- **47984/TCP**: HTTPS Web UI
- **47989/TCP**: HTTP Web UI
- **47990/TCP**: RTSP
- **48010/TCP**: Video stream
- **47998/UDP**: Video
- **47999/UDP**: Control
- **48000/UDP**: Audio
- **48002/UDP**: Control

## Troubleshooting

### Sunshine won't start
```bash
# Check service status
systemctl status sunshine

# View logs
journalctl -u sunshine -f
```

### Emulator won't launch
```bash
# Launch from terminal to see errors
dolphin-emu
pcsx2
rpcs3
# etc.
```

### Performance issues
```bash
# Manually enable GameMode
gamemoderun <emulator-command>

# Check GPU drivers
glxinfo | grep "OpenGL renderer"
```

## Security Notes

- Sunshine web UI is accessible on your local network
- Set a strong admin password in Sunshine settings
- For external access, use VPN (Tailscale/WireGuard) instead of port forwarding
- Consider enabling authentication in Sunshine for added security

## Further Documentation

See `docs/GAMING.md` for comprehensive documentation including:
- Detailed emulator setup guides
- BIOS/firmware requirements
- Advanced Sunshine configuration
- Storage recommendations
- Complete troubleshooting guide

## Quick Reference Links

- [Sunshine Documentation](https://docs.lizardbyte.dev/projects/sunshine/)
- [Moonlight](https://moonlight-stream.org/)
- [RetroArch](https://www.retroarch.com/)
- [Emulation Wiki](https://emulation.gametechwiki.com/)