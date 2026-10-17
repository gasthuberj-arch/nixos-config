#!/usr/bin/env bash
set -euo pipefail

# Kill GPU tasks and emulators on homelab remotely
# Usage: ./scripts/kill-gpu-tasks.sh [OPTIONS] [HOST]
# Examples:
#   ./scripts/kill-gpu-tasks.sh
#   ./scripts/kill-gpu-tasks.sh --dry-run
#   ./scripts/kill-gpu-tasks.sh --include-sunshine

HOMELAB_HOST="${HOMELAB_IP:-192.168.1.101}"
HOMELAB_USER="${HOMELAB_USER:-johannes}"
SCRIPT_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --dry-run|-n|--include-sunshine|-s|--help|-h)
      SCRIPT_ARGS+=("$arg")
      ;;
    *)
      HOMELAB_HOST="$arg"
      ;;
  esac
done

echo "Connecting to homelab ($HOMELAB_HOST) to kill GPU tasks..."
ssh -t -o ConnectTimeout=5 "${HOMELAB_USER}@${HOMELAB_HOST}" "sudo kill-gpu-tasks ${SCRIPT_ARGS[*]:-}"
