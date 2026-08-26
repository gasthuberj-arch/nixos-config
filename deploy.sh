#!/usr/bin/env bash

set -e

# Configuration
HOMELAB_IP="${HOMELAB_IP:-192.168.1.101}"
HOMELAB_USER="johannes"
CONFIG_DIR=$(pwd)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy NixOS configuration to homelab server.

Options:
    -h, --help              Show this help message
    -i, --ip IP_ADDRESS     Homelab IP address (default: $HOMELAB_IP)
    -u, --user USERNAME     SSH username (default: $HOMELAB_USER)
    --dry-run               Show what would be done without executing

Examples:
    # Deploy using default settings
    $0

    # Deploy to specific IP
    $0 --ip 192.168.1.101

    # Deploy with custom user
    $0 --user johannes --ip 192.168.1.101

    # Use environment variable
    HOMELAB_IP=192.168.1.101 $0
EOF
}

# Parse arguments
DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -i|--ip)
            HOMELAB_IP="$2"
            shift 2
            ;;
        -u|--user)
            HOMELAB_USER="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Validate IP is set
if [[ -z "$HOMELAB_IP" ]]; then
    echo -e "${RED}Error: HOMELAB_IP not set!${NC}"
    echo "Set it via environment variable or use --ip flag"
    echo "Example: HOMELAB_IP=192.168.1.101 $0"
    exit 1
fi

# Print configuration
echo -e "${GREEN}=== Deployment Configuration ===${NC}"
echo "Target: ${HOMELAB_USER}@${HOMELAB_IP}"
echo "Config: ${CONFIG_DIR}"
echo "Dry run: ${DRY_RUN}"
echo ""

# Check if config directory exists
if [[ ! -d "$CONFIG_DIR" ]]; then
    echo -e "${RED}Error: Configuration directory '$CONFIG_DIR' not found${NC}"
    exit 1
fi

# Function to run or echo commands
run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
    else
        echo -e "${GREEN}[RUNNING]${NC} $*"
        eval "$@"
    fi
}

# Step 1: Copy configuration
echo -e "${GREEN}Step 1: Copying configuration to homelab...${NC}"
run_cmd "ssh ${HOMELAB_USER}@${HOMELAB_IP} 'mkdir -p /tmp/nixos-config'"
run_cmd "rsync -avz --delete --exclude '.jj' $CONFIG_DIR/ ${HOMELAB_USER}@${HOMELAB_IP}:/tmp/nixos-config/"

# Step 2: Deploy and rebuild
echo -e "${GREEN}Step 2: Deploying configuration and rebuilding system...${NC}"
run_cmd "ssh -t ${HOMELAB_USER}@${HOMELAB_IP} 'sudo mkdir -p /etc/nixos && sudo rsync -av --delete /tmp/nixos-config/ /etc/nixos/ && sudo nixos-rebuild switch --flake /etc/nixos#homelab'"

if [[ "$DRY_RUN" == "false" ]]; then
    echo ""
    echo -e "${GREEN}=== Deployment Complete! ===${NC}"
    echo ""
else
    echo ""
    echo -e "${YELLOW}Dry run complete. No changes were made.${NC}"
fi
