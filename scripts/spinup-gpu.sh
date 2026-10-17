#!/usr/bin/env bash
set -euo pipefail

# Spin up homelab GPU remotely for gaming/dynamic performance
# Usage: ./scripts/spinup-gpu.sh [HOST]

HOMELAB_HOST="${1:-${HOMELAB_IP:-192.168.1.101}}"
HOMELAB_USER="${HOMELAB_USER:-johannes}"

echo "Connecting to homelab ($HOMELAB_HOST) to spin up GPU..."
ssh -t -o ConnectTimeout=5 "${HOMELAB_USER}@${HOMELAB_HOST}" "sudo spinup-gpu"
