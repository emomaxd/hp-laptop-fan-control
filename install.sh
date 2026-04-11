#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"

[[ $EUID -eq 0 ]] || { echo "error: run as root"; exit 1; }

HP_HWMON=$(grep -rl "^hp$" /sys/class/hwmon/*/name 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
[[ -d "$HP_HWMON" ]] || {
    echo "error: hp-wmi hwmon not found — patched module not loaded?"
    echo "  lsmod | grep hp_wmi"
    echo "  ls /sys/devices/platform/hp-wmi/hwmon/"
    exit 1
}

install -Dm755 "$SCRIPT_DIR/hp-fan-control"         "$PREFIX/bin/hp-fan-control"
install -Dm755 "$SCRIPT_DIR/hp-fan-curve"            "$PREFIX/bin/hp-fan-curve"
install -Dm644 "$SCRIPT_DIR/hp-fan-control.service"  /etc/systemd/system/hp-fan-control.service

systemctl daemon-reload
systemctl enable --now hp-fan-control
systemctl status hp-fan-control --no-pager
