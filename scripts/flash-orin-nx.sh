#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_DIR"

FLASH_BIN="./result-flash/bin/initrd-flash-orin-nx-devkit"
if [ ! -x "$FLASH_BIN" ]; then
    FLASH_BIN=$(find ./result-flash/bin -name 'initrd-flash*' 2>/dev/null | head -n 1 || true)
fi

if [ -z "${FLASH_BIN:-}" ] || [ ! -x "$FLASH_BIN" ]; then
    echo "[$(date)] Flash script not found! Rebuilding..."
    nix build .#nixosConfigurations.orin-nx.config.system.build.flashScript --out-link result-flash
    FLASH_BIN="./result-flash/bin/initrd-flash-orin-nx-devkit"
fi

echo "[$(date)] Using flash script: $FLASH_BIN"

echo "[$(date)] Checking USB recovery device..."
if ! lsusb | grep -iE '0955:7323|0955:7023|0955:7223' > /dev/null; then
    echo "[$(date)] Warning: Jetson APX device not found in lsusb. Please ensure device is in recovery mode."
fi

echo "[$(date)] Executing flash script..."
sudo "$FLASH_BIN"

echo "[$(date)] Flash process complete!"
