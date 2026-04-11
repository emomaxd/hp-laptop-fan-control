#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HP_HWMON=$(ls -d /sys/devices/platform/hp-wmi/hwmon/hwmon* 2>/dev/null | head -1)
[[ -d "$HP_HWMON" ]] || {
    echo "error: hp-wmi hwmon not found — is the patched module loaded?"
    echo "  lsmod | grep hp_wmi"
    echo "  ls /sys/devices/platform/hp-wmi/hwmon/"
    exit 1
}

install -Dm755 "$SCRIPT_DIR/hp-fan-control"        /usr/local/bin/hp-fan-control
install -Dm755 "$SCRIPT_DIR/hp-fan-toggle-silent"  /usr/local/bin/hp-fan-toggle-silent
install -Dm755 "$SCRIPT_DIR/hp-fan-curve"          /usr/local/bin/hp-fan-curve
install -Dm644 "$SCRIPT_DIR/hp-fan-control.service" /etc/systemd/system/hp-fan-control.service

systemctl daemon-reload
systemctl enable --now hp-fan-control
systemctl status hp-fan-control --no-pager
