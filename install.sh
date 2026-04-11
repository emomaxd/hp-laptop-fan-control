#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Verify hp-wmi hwmon is present
HP_HWMON=/sys/devices/platform/hp-wmi/hwmon/hwmon4
[[ -d "$HP_HWMON" ]] || {
    echo "error: hp-wmi hwmon not found. Make sure the patched hp-wmi module is loaded."
    echo "  Check: lsmod | grep hp_wmi"
    exit 1
}

install -Dm755 "$SCRIPT_DIR/hp-fan-control"       /usr/local/bin/hp-fan-control
install -Dm755 "$SCRIPT_DIR/hp-fan-toggle-silent" /usr/local/bin/hp-fan-toggle-silent
install -Dm644 "$SCRIPT_DIR/hp-fan-control.service" /etc/systemd/system/hp-fan-control.service

systemctl daemon-reload
systemctl enable --now hp-fan-control

echo "installed. status:"
systemctl status hp-fan-control --no-pager
