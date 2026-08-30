#!/usr/bin/env bash
set -euo pipefail

# Ensure Nix binary is in PATH under sudo
export PATH="/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:$PATH"
if [ -n "${SUDO_USER:-}" ]; then
  SUDO_HOME=$(eval echo "~$SUDO_USER")
  export PATH="$SUDO_HOME/.nix-profile/bin:$PATH"
fi

# ANSI color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

TARGET_DEVICE="${1:-/dev/sda}"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[ERROR] This script must be run with sudo for raw disk access.${NC}"
  echo "Usage: sudo $0 /dev/sdX"
  exit 1
fi

if [ ! -b "$TARGET_DEVICE" ]; then
  echo -e "${RED}[ERROR] Block device '$TARGET_DEVICE' not found!${NC}"
  exit 1
fi

# Safety check: Warn if partitions on the drive are currently mounted
if grep -qs "$TARGET_DEVICE" /proc/mounts; then
  echo -e "${RED}⚠️  WARNING: Partitions on $TARGET_DEVICE are currently mounted!${NC}"
  echo "Unmounting $TARGET_DEVICE partitions first to prevent filesystem corruption..."
  umount -R /mnt 2>/dev/null || true
  cryptsetup close crypted 2>/dev/null || true
fi

echo -e "${BLUE}⠋ Resolving OVMF UEFI firmware...${NC}"
OVMF_PATH=$(nix build nixpkgs#OVMF.fd --no-link --print-out-paths)

echo -e "${GREEN}✓ Launching UEFI QEMU Virtual Machine for $TARGET_DEVICE...${NC}"
echo -e "Press ${BLUE}Ctrl+Alt+G${NC} to release mouse/keyboard from the VM window, or close the window to exit.\n"

nix shell nixpkgs#qemu --command \
  qemu-system-x86_64 \
    -enable-kvm \
    -m 4G \
    -smp 4 \
    -cpu host \
    -bios "$OVMF_PATH/FV/OVMF.fd" \
    -drive file="$TARGET_DEVICE",format=raw
