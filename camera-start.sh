#!/usr/bin/env bash
# Start PipeWire/WirePlumber and the IPU6 camera bridge for Zoom Desktop / Chrome.
set -euo pipefail

UNIT="$HOME/.config/systemd/user/ipu6-bridge.service"
[[ -s "$UNIT" ]] || { echo "Missing or empty $UNIT" >&2; exit 1; }

systemctl --user daemon-reload
systemctl --user restart wireplumber pipewire
systemctl --user enable --now ipu6-bridge.service
systemctl --user --no-pager status ipu6-bridge.service | head -n 5
