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
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

TARGET_DEVICE="${1:-/dev/sda}"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[ERROR] This script must be run as root (sudo).${NC}"
  exit 1
fi

if [ ! -b "$TARGET_DEVICE" ]; then
  echo -e "${RED}[ERROR] Target block device '$TARGET_DEVICE' not found!${NC}"
  echo "Usage: sudo $0 /dev/sdX"
  exit 1
fi

echo -e "${RED}⚠️  WARNING: ALL DATA ON ${TARGET_DEVICE} WILL BE PERMANENTLY ERASED!${NC}"
read -rp "Are you sure you want to flash NixOS to $TARGET_DEVICE? (type 'yes' to proceed): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

echo -e "\n${BLUE}[1/4] Partitioning & Formatting via Disko...${NC}"
nix run github:nix-community/disko -- \
  --mode zap_create_mount \
  ./hosts/laptop/disko-config.nix \
  --arg device "\"$TARGET_DEVICE\""

echo -e "\n${BLUE}[2/4] Installing NixOS System Closure...${NC}"
nix shell nixpkgs#nixos-install-tools nixpkgs#util-linux nixpkgs#systemd --command \
  nixos-install --flake .#laptop --no-root-password

echo -e "\n${BLUE}[3/4] Activating Bootloader & UEFI Fallback Entry...${NC}"
nix shell nixpkgs#nixos-install-tools nixpkgs#util-linux nixpkgs#systemd --command \
  nixos-enter --root /mnt -c '/nix/var/nix/profiles/system/bin/switch-to-configuration boot'

# Ensure fallback EFI exists unconditionally
mkdir -p /mnt/boot/EFI/BOOT
if [ -f /mnt/boot/EFI/systemd/systemd-bootx64.efi ]; then
  cp -f /mnt/boot/EFI/systemd/systemd-bootx64.efi /mnt/boot/EFI/BOOT/BOOTX64.EFI
fi

echo -e "\n${BLUE}[4/4] Flushing Buffers and Closing Crypt Container...${NC}"
umount -R /mnt
cryptsetup close crypted || true

echo -e "\n${GREEN}✓ Successfully flashed NixOS onto $TARGET_DEVICE!${NC}"
echo -e "${GREEN}The drive is fully encrypted, configured with user 'johannes' (password: changeme), and ready to boot.${NC}\n"
