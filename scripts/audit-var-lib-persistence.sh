#!/usr/bin/env bash
# Dry-run audit and optional migration helper for /var/lib -> /persist/var/lib
# Run on homelab before removing blanket /var/lib persistence and rebooting.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODE="dry-run"
HOST="homelab"
PERSIST_ROOT="/persist"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--dry-run | --migrate] [--host <hostname>] [--persist <path>]

Compares active /var/lib directories against the declared impermanence paths in
flake output .#nixosConfigurations.<host>.config.environment.persistence."/persist".directories
so unmigrated state is caught before rebooting.

Options:
  --dry-run          Report missing or unpersisted directories without copying (default)
  --migrate          Copy missing /var/lib/<dir> state into <persist>/var/lib/<dir> via rsync -aHAX
  --host <name>      NixOS configuration host name (default: homelab)
  --persist <path>   Persistence root mountpoint (default: /persist)
  -h, --help         Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --migrate)
      MODE="migrate"
      shift
      ;;
    --host)
      HOST="$2"
      shift 2
      ;;
    --persist)
      PERSIST_ROOT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$MODE" == "migrate" && $EUID -ne 0 ]]; then
  echo "Error: --migrate requires root privileges (use sudo)." >&2
  exit 1
fi

echo "=== Auditing /var/lib Persistence for host '$HOST' ($MODE) ==="

mapfile -t DECLARED_DIRS < <(
  cd "$REPO_ROOT"
  nix eval --json --apply 'map (d: d.directory)' ".#nixosConfigurations.${HOST}.config.environment.persistence.\"${PERSIST_ROOT}\".directories" \
    | nix run nixpkgs#jq -- -r '.[]' \
    | sort -u
)

if [[ ${#DECLARED_DIRS[@]} -eq 0 ]]; then
  echo "Error: No persistence directories evaluated for host '$HOST'." >&2
  exit 1
fi

declare -A DECLARED_SET=()
for d in "${DECLARED_DIRS[@]}"; do
  DECLARED_SET["$d"]=1
done

echo ""
echo "--- 1. Declared Persistence Directories ---"
unmigrated=0
for d in "${DECLARED_DIRS[@]}"; do
  [[ "$d" == /var/lib/* ]] || continue
  target="${PERSIST_ROOT}${d}"
  if [[ -d "$target" ]]; then
    echo "  [OK]      $d -> $target exists"
  elif [[ -d "$d" ]]; then
    echo "  [MIGRATE] $d exists on live system but $target is missing"
    unmigrated=$((unmigrated + 1))
    if [[ "$MODE" == "migrate" ]]; then
      mkdir -p "$(dirname "$target")"
      rsync -aHAX --numeric-ids "$d/" "$target/"
      echo "            -> Copied $d to $target"
    fi
  else
    echo "  [NEW]     $d not yet created on disk (will initialize at boot)"
  fi
done

echo ""
echo "--- 2. Active /var/lib/* Directories Not Declared in Persistence ---"
undeclared=0
if [[ -d /var/lib ]]; then
  for entry in /var/lib/*; do
    [[ -d "$entry" ]] || continue
    if [[ -z "${DECLARED_SET[$entry]+_}" ]]; then
      echo "  [EPHEMERAL] $entry (will be wiped on reboot unless declared)"
      undeclared=$((undeclared + 1))
    fi
  done
fi

echo ""
echo "Summary: ${#DECLARED_DIRS[@]} declared path(s), $unmigrated pending migration, $undeclared undeclared in /var/lib."
if [[ "$MODE" == "dry-run" && "$unmigrated" -gt 0 ]]; then
  echo "Re-run with --migrate as root before rebooting to copy unmigrated state into ${PERSIST_ROOT}."
fi
