#!/usr/bin/env bash
# Setup script for Nextcloud and Paperless secrets
# Run this on the homelab server before deploying the configuration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Nextcloud and Paperless Setup Script ===${NC}\n"

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root or with sudo${NC}"
   exit 1
fi

# Create secrets directory
SECRETS_DIR="/persist/secrets"
echo -e "${YELLOW}Creating secrets directory...${NC}"
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"
echo -e "${GREEN}✓ Secrets directory created: $SECRETS_DIR${NC}\n"

# Function to create password file
create_password_file() {
    local service=$1
    local file_path=$2
    
    echo -e "${YELLOW}Setting up password for $service...${NC}"
    
    if [[ -f "$file_path" ]]; then
        echo -e "${YELLOW}Password file already exists: $file_path${NC}"
        read -p "Do you want to replace it? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}✓ Keeping existing password${NC}\n"
            return
        fi
    fi
    
    # Generate a random password or let user input one
    echo "Choose an option:"
    echo "  1) Generate random password"
    echo "  2) Enter password manually"
    read -p "Choice [1/2]: " -n 1 -r choice
    echo
    
    if [[ $choice == "1" ]]; then
        # Generate random password
        password=$(openssl rand -base64 32)
        echo "$password" > "$file_path"
        chmod 600 "$file_path"
        echo -e "${GREEN}✓ Random password generated and saved to: $file_path${NC}"
        echo -e "${