#!/usr/bin/env bash
# Stop the IPU6 camera bridge and PipeWire/WirePlumber when done with Zoom / Chrome.
set -euo pipefail

systemctl --user stop ipu6-bridge.service wireplumber pipewire
