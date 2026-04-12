#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"

[[ $EUID -eq 0 ]] || { echo "error: run as root"; exit 1; }
command -v systemctl >/dev/null 2>&1 || { echo "error: systemctl not found — not a systemd system?"; exit 1; }

HP_HWMON=$(grep -rl "^hp$" /sys/class/hwmon/*/name 2>/dev/null | head -1 | xargs -r dirname)
[[ -d "$HP_HWMON" ]] || {
    echo "error: hp-wmi hwmon not found — patched module not loaded?"
    echo "  lsmod | grep hp_wmi"
    echo "  ls /sys/devices/platform/hp-wmi/hwmon/"
    exit 1
}

install -Dm755 "$SCRIPT_DIR/hp-fan-control"  "$PREFIX/bin/hp-fan-control"
install -Dm755 "$SCRIPT_DIR/hp-fan-curve"   "$PREFIX/bin/hp-fan-curve"

sed "s|HP_FAN_CONTROL_BIN|$PREFIX/bin/hp-fan-control|" \
    "$SCRIPT_DIR/hp-fan-control.service" \
    > /etc/systemd/system/hp-fan-control.service
chmod 644 /etc/systemd/system/hp-fan-control.service

systemctl daemon-reload
systemctl enable --now hp-fan-control
systemctl status hp-fan-control --no-pager || true
