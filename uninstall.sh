#!/bin/bash
set -e

PREFIX="${PREFIX:-/usr/local}"

[[ $EUID -eq 0 ]] || { echo "error: run as root"; exit 1; }

systemctl disable --now hp-fan-control 2>/dev/null || true
rm -f /etc/systemd/system/hp-fan-control.service
rm -f "$PREFIX/bin/hp-fan-control"
rm -f "$PREFIX/bin/hp-fan-curve"
if [[ -f /etc/hp-fan-control.conf ]]; then
    echo "leaving /etc/hp-fan-control.conf in place — remove manually if not needed"
fi
systemctl daemon-reload
echo "uninstalled"
