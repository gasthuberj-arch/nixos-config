#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="/tmp/authelia-check"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Authelia Configuration Checker ===${NC}\n"

mkdir -p "$TMP_DIR"

echo -e "${BLUE}[1/4]${NC} Rendering Authelia config from Nix..."
cd "$PROJECT_DIR"
nix eval .#nixosConfigurations.homelab.config.services.authelia.instances.main.settings --json | \
  nix run nixpkgs#yj -- -jy > "$TMP_DIR/authelia.yml"
echo -e "${GREEN}✓${NC} Config rendered\n"

echo -e "${BLUE}[2/4]${NC} Generating mock RSA key..."
nix run nixpkgs#openssl -- genrsa -out "$TMP_DIR/rsa_key.pem" 2048 2>&1 > /dev/null
echo -e "${GREEN}✓${NC} RSA key generated\n"

echo -e "${BLUE}[3/4]${NC} Adding mock secrets for validation..."

# Create mock users file
echo 'users:' > "$TMP_DIR/users.yml"

# Update paths and add secrets using yq (secrets must be 20+ chars)
nix run nixpkgs#yq-go -- eval -i "
  .authentication_backend.file.path = \"$TMP_DIR/users.yml\" |
  .identity_validation.reset_password.jwt_secret = \"mock_jwt_secret_1234567890\" |
  .storage.encryption_key = \"mock_encryption_key_1234567890\" |
  .identity_providers.oidc.jwks[0].key.path = \"$TMP_DIR/rsa_key.pem\"
" "$TMP_DIR/authelia.yml"

echo -e "${GREEN}✓${NC} Mock secrets added\n"

echo -e "${BLUE}[4/4]${NC} Validating configuration with authelia...\n"

if nix run nixpkgs#authelia -- validate-config --config "$TMP_DIR/authelia.yml" 2>&1; then
    echo ""
    echo -e "${GREEN}✅ Configuration is VALID!${NC}\n"
    echo -e "${YELLOW}Config:${NC} $TMP_DIR/authelia.yml"
    exit 0
else
    echo ""
    echo -e "${RED}❌ Configuration has ERRORS!${NC}\n"
    echo -e "${YELLOW}Debug:${NC} cat $TMP_DIR/authelia.yml"
    exit 1
fi
