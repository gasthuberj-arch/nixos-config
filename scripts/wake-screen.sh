#!/usr/bin/env bash

# Wake the homelab screen remotely
# Usage: ./wake-screen.sh [IP_ADDRESS]

HOMELAB_IP="${1:-homelab.local}"
HOMELAB_USER="johannes"

echo "Waking screen on ${HOMELAB_IP}..."

# Try multiple methods to wake the screen
ssh "${HOMELAB_USER}@${HOMELAB_IP}" 'bash -s' << 'EOF'
# Get the user's display session
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

# Method 1: Use gdbus to inhibit screensaver momentarily
gdbus call --session \
  --dest org.gnome.ScreenSaver \
  --object-path /org/gnome/ScreenSaver \
  --method org.gnome.ScreenSaver.SetActive false 2>/dev/null && echo "Method 1: Screen saver deactivated"

# Method 2: Simulate user activity via systemd-logind
loginctl unlock-sessions 2>/dev/null && echo "Method 2: Sessions unlocked"

# Method 3: Use ydotool to simulate a key press (if available)
if command -v ydotool &> /dev/null; then
  ydotool key 29:1 29:0 2>/dev/null && echo "Method 3: Simulated key press"
fi

# Method 4: Touch a file that Sunshine monitors (creates activity)
touch ~/.config/sunshine/sunshine_state.json 2>/dev/null

echo "Screen wake commands sent"
EOF

echo "Done!"
