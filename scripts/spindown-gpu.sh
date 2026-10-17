#!/usr/bin/env bash
set -euo pipefail

# Spin down homelab GPU remotely to save energy
# Usage: ./scripts/spindown-gpu.sh [OPTIONS] [HOST]
# Examples:
#   ./scripts/spindown-gpu.sh
#   ./scripts/spindown-gpu.sh --include-sunshine
#   ./scripts/spindown-gpu.sh --no-kill

HOMELAB_HOST="${HOMELAB_IP:-192.168.1.101}"
HOMELAB_USER="${HOMELAB_USER:-johannes}"
SCRIPT_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --no-kill|--include-sunshine|-s|--help|-h)
      SCRIPT_ARGS+=("$arg")
      ;;
    *)
      # Treat non-flag argument as host/IP
      HOMELAB_HOST="$arg"
      ;;
  esac
done

echo "Connecting to homelab ($HOMELAB_HOST) to spin down GPU..."
ssh -t -o ConnectTimeout=5 "${HOMELAB_USER}@${HOMELAB_HOST}" "sudo spindown-gpu ${SCRIPT_ARGS[*]:-}"
