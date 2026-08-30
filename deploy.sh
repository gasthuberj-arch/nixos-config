#!/usr/bin/env bash

set -euo pipefail

# Default configuration
HOST="${1:-homelab}"
if [[ "$HOST" == -* ]]; then
  HOST="homelab"
else
  shift 1 || true
fi

DEFAULT_IP=""
case "$HOST" in
  homelab) DEFAULT_IP="192.168.1.101" ;;
  rpi5)    DEFAULT_IP="192.168.1.128" ;;
  orin)    DEFAULT_IP="orin.lan" ;;
  *)       DEFAULT_IP="${HOST}.lan" ;;
esac

TARGET_IP="${DEPLOY_IP:-$DEFAULT_IP}"
TARGET_USER="${DEPLOY_USER:-johannes}"
ACTION="switch"
EXTRA_ARGS=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat << EOF
Usage: $0 [HOST] [OPTIONS]

Deploy NixOS configuration to any host in the flake.

Hosts:
    homelab (default)       x86_64 homelab server (default IP: 192.168.1.101)
    rpi5                    Raspberry Pi 5 node (default: rpi5.lan)
    <any-flake-host>        Any host defined in nixosConfigurations.<host>

Options:
    -h, --help              Show this help message
    -i, --ip IP_OR_HOST     Target IP address or hostname (default: $DEFAULT_IP)
    -u, --user USERNAME     SSH username (default: $TARGET_USER)
    --test                  Build and activate without adding to bootloader menu
    --boot                  Build and add to bootloader without switching immediately
    --build                 Only build the system closure, do not activate
    --dry-run               Show the command without executing
    --show-trace            Pass --show-trace to Nix evaluation

Examples:
    $0                      # Deploy homelab
    $0 rpi5                 # Deploy rpi5
    $0 homelab --ip 192.168.1.101
    $0 rpi5 --test
EOF
}

DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -i|--ip)
            TARGET_IP="$2"
            shift 2
            ;;
        -u|--user)
            TARGET_USER="$2"
            shift 2
            ;;
        --test)
            ACTION="test"
            shift
            ;;
        --boot)
            ACTION="boot"
            shift
            ;;
        --build)
            ACTION="build"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --show-trace)
            EXTRA_ARGS+=("--show-trace")
            shift
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            usage
            exit 1
            ;;
    esac
done

TARGET_DEST="${TARGET_USER}@${TARGET_IP}"

echo -e "${BLUE}=== Multi-Host NixOS Deployment ===${NC}"
echo -e "Host:       ${GREEN}${HOST}${NC}"
echo -e "Target:     ${GREEN}${TARGET_DEST}${NC}"
echo -e "Action:     ${GREEN}${ACTION}${NC}"
echo ""

# Find nixos-rebuild (system or via nix run)
if command -v nixos-rebuild &>/dev/null; then
    REBUILD_CMD=(nixos-rebuild)
else
    REBUILD_CMD=(nix run nixpkgs#nixos-rebuild --)
fi

CMD=(
    "${REBUILD_CMD[@]}"
    "$ACTION"
    --flake ".#${HOST}"
    --target-host "$TARGET_DEST"
    --build-host "$TARGET_DEST"
    --use-remote-sudo
    --accept-flake-config
    "${EXTRA_ARGS[@]}"
)

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}[DRY-RUN] Would execute:${NC}"
    echo "  ${CMD[*]}"
    exit 0
fi

echo -e "${GREEN}[DEPLOYING] Executing native remote deployment...${NC}"
"${CMD[@]}"

echo ""
echo -e "${GREEN}=== Deployment to ${HOST} Complete! ===${NC}"
