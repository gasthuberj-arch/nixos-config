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

show_help() {
  cat << USAGE
Usage: sudo $0 <action> [device]

Actions:
  full <device>        Complete from-scratch wipe, format, install & bootloader setup
  mount <device>       Unlock LUKS and mount all Btrfs subvolumes to /mnt
  umount               Unmount /mnt and close LUKS container
  bootloader           Re-install systemd-boot & kernel entries to /mnt/boot (must be mounted)
  status <device>      Inspect partition table, mounts, and EFI files on target device

Default device is /dev/sda.

Examples:
  sudo $0 full /dev/sda
  sudo $0 mount /dev/sda
  sudo $0 bootloader
  sudo $0 umount
USAGE
}

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] This script must be run as root (sudo).${NC}"
    exit 1
  fi
}

do_mount() {
  local dev="$1"
  echo -e "${BLUE}⠋ Opening LUKS container on ${dev}2...${NC}"
  if [ ! -e /dev/mapper/crypted ]; then
    cryptsetup open "${dev}2" crypted
  fi

  echo -e "${BLUE}⠋ Mounting subvolumes via Disko...${NC}"
  nix run github:nix-community/disko -- \
    --mode mount \
    ./hosts/laptop/disko-config.nix \
    --arg device "\"$dev\""

  echo -e "${GREEN}✓ Successfully mounted to /mnt:${NC}"
  findmnt -R /mnt
}

do_umount() {
  echo -e "${BLUE}⠋ Unmounting /mnt...${NC}"
  umount -R /mnt 2>/dev/null || true
  if [ -e /dev/mapper/crypted ]; then
    echo -e "${BLUE}⠋ Closing LUKS container crypted...${NC}"
    cryptsetup close crypted || true
  fi
  echo -e "${GREEN}✓ Cleanly unmounted.${NC}"
}

do_bootloader() {
  if ! mountpoint -q /mnt; then
    echo -e "${RED}[ERROR] /mnt is not mounted! Run 'sudo $0 mount <dev>' first.${NC}"
    exit 1
  fi
  if ! mountpoint -q /mnt/boot; then
    echo -e "${RED}[ERROR] /mnt/boot is not mounted!${NC}"
    exit 1
  fi

  echo -e "${BLUE}⠋ [1/3] Installing systemd-boot directly to /mnt/boot...${NC}"
  nix shell nixpkgs#systemd --command \
    bootctl --esp-path=/mnt/boot install --no-variables

  echo -e "${BLUE}⠋ [2/3] Writing kernel, initrd, and generation entries...${NC}"
  nix shell nixpkgs#nixos-install-tools nixpkgs#util-linux nixpkgs#systemd --command \
    nixos-enter --root /mnt -c '/nix/var/nix/profiles/system/bin/switch-to-configuration boot' || true

  echo -e "${BLUE}⠋ [3/3] Ensuring fallback /EFI/BOOT/BOOTX64.EFI exists...${NC}"
  mkdir -p /mnt/boot/EFI/BOOT
  if [ -f /mnt/boot/EFI/systemd/systemd-bootx64.efi ]; then
    cp -fv /mnt/boot/EFI/systemd/systemd-bootx64.efi /mnt/boot/EFI/BOOT/BOOTX64.EFI
  fi

  echo -e "\n${GREEN}✓ Bootloader inspection on /mnt/boot:${NC}"
  ls -laR /mnt/boot/EFI/
  if [ -d /mnt/boot/loader/entries ]; then
    echo -e "${GREEN}✓ Loader entries:${NC}"
    ls -la /mnt/boot/loader/entries/
  fi
}

do_status() {
  local dev="$1"
  echo -e "${BLUE}=== Block Device Status: $dev ===${NC}"
  lsblk "$dev" || true
  echo -e "\n${BLUE}=== Active Mounts under /mnt ===${NC}"
  findmnt -R /mnt 2>/dev/null || echo "(Nothing mounted on /mnt)"
}

do_full() {
  local dev="$1"
  if [ ! -b "$dev" ]; then
    echo -e "${RED}[ERROR] Block device '$dev' not found!${NC}"
    exit 1
  fi

  echo -e "${RED}⚠️  WARNING: ALL DATA ON ${dev} WILL BE PERMANENTLY ERASED!${NC}"
  read -rp "Are you sure you want to flash NixOS to $dev? (type 'yes' to proceed): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
  fi

  echo -e "\n${BLUE}[1/4] Partitioning & Formatting via Disko...${NC}"
  # Clean any active mounts or open dm-crypt containers before wiping
  umount -R /mnt 2>/dev/null || true
  cryptsetup close crypted 2>/dev/null || true

  nix run github:nix-community/disko -- \
    --mode zap_create_mount \
    ./hosts/laptop/disko-config.nix \
    --arg device "\"$dev\""

  echo -e "\n${BLUE}[2/4] Installing NixOS System Closure...${NC}"
  nix shell nixpkgs#nixos-install-tools nixpkgs#util-linux nixpkgs#systemd --command \
    nixos-install --flake .#laptop --no-root-password --no-bootloader

  echo -e "\n${BLUE}[3/4] Installing Bootloader & Kernel Entries...${NC}"
  do_bootloader

  echo -e "\n${BLUE}[4/4] Flushing Buffers and Closing Container...${NC}"
  do_umount

  echo -e "\n${GREEN}✓ Successfully flashed NixOS onto $dev!${NC}"
  echo -e "${GREEN}Run 'sudo ./scripts/test-boot-drive.sh $dev' to test immediately.${NC}\n"
}

# Main Dispatcher
check_root

ACTION="${1:-help}"
DEVICE="${2:-/dev/sda}"

case "$ACTION" in
  full)
    do_full "$DEVICE"
    ;;
  mount)
    do_mount "$DEVICE"
    ;;
  umount|unmount)
    do_umount
    ;;
  bootloader)
    do_bootloader
    ;;
  status)
    do_status "$DEVICE"
    ;;
  help|-h|--help)
    show_help
    ;;
  *)
    echo -e "${RED}[ERROR] Unknown action '$ACTION'${NC}\n"
    show_help
    exit 1
    ;;
esac
