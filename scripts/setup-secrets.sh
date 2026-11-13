#!/usr/bin/env bash
# Setup script for runtime service secrets and SOPS age key enrollment.
# Run on the target host before deploying or enrolling into .sops.yaml.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ "${1:-}" == "--enroll-age-key" ]]; then
  SSH_PUB=""
  for candidate in /persist/etc/ssh/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ed25519_key.pub; do
    if [[ -f "$candidate" ]]; then
      SSH_PUB="$candidate"
      break
    fi
  done

  if [[ -z "$SSH_PUB" ]]; then
    echo -e "${RED}Error: No ssh_host_ed25519_key.pub found in /persist/etc/ssh or /etc/ssh${NC}" >&2
    exit 1
  fi

  echo -e "${GREEN}Host SSH public key:${NC} $SSH_PUB"
  AGE_PUB=$(nix run nixpkgs#ssh-to-age -- -i "$SSH_PUB")
  echo -e "${GREEN}Derived SOPS age recipient:${NC} $AGE_PUB"
  echo "Add this recipient to .sops.yaml for $(hostname), then run: nix run nixpkgs#sops -- updatekeys secrets/*.yaml"
  exit 0
fi

echo -e "${GREEN}=== Homelab Runtime Secrets Setup Script ===${NC}\n"

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Error: This script must be run as root or with sudo${NC}"
  exit 1
fi

SECRETS_DIR="/persist/secrets"
echo -e "${YELLOW}Creating secrets directory...${NC}"
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"
echo -e "${GREEN}✓ Secrets directory created: $SECRETS_DIR${NC}\n"

create_password_file() {
  local service=$1
  local file_path=$2

  echo -e "${YELLOW}Setting up password for $service...${NC}"
  mkdir -p "$(dirname "$file_path")"
  chmod 700 "$(dirname "$file_path")"

  if [[ -f "$file_path" ]]; then
    echo -e "${YELLOW}Password file already exists: $file_path${NC}"
    read -p "Do you want to replace it? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo -e "${GREEN}✓ Keeping existing password${NC}\n"
      return
    fi
  fi

  echo "Choose an option:"
  echo "  1) Generate random password"
  echo "  2) Enter password manually"
  read -p "Choice [1/2]: " -n 1 -r choice
  echo

  if [[ $choice == "1" ]]; then
    openssl rand -base64 32 >"$file_path"
    chmod 600 "$file_path"
    echo -e "${GREEN}✓ Random password generated and saved to: $file_path${NC}\n"
  elif [[ $choice == "2" ]]; then
    read -s -p "Enter password for $service: " password
    echo
    printf '%s\n' "$password" >"$file_path"
    chmod 600 "$file_path"
    echo -e "${GREEN}✓ Password saved to: $file_path${NC}\n"
  else
    echo -e "${RED}Invalid choice, skipping $service${NC}\n"
  fi
}

create_password_file "Nextcloud" "$SECRETS_DIR/nextcloud/admin-password"
create_password_file "Paperless-ngx" "$SECRETS_DIR/paperless/admin-password"
echo -e "${GREEN}Done. Run '$0 --enroll-age-key' to print this host's SOPS age recipient.${NC}"
