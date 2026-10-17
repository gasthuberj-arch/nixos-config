#!/usr/bin/env bash
set -euo pipefail

# Check GPU power, temperatures, and active processes on homelab remotely
# Usage: ./scripts/check-gpu-power.sh [HOST]

HOMELAB_HOST="${1:-${HOMELAB_IP:-192.168.1.101}}"
HOMELAB_USER="${HOMELAB_USER:-johannes}"

echo "Connecting to homelab ($HOMELAB_HOST) to inspect GPU status..."
ssh -t -o ConnectTimeout=5 "${HOMELAB_USER}@${HOMELAB_HOST}" "sudo check-gpu-power"
