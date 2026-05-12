#!/bin/bash
set -e

PREFIX="${PREFIX:-/usr/local}"

[[ $EUID -eq 0 ]] || { echo "error: run as root"; exit 1; }

systemctl disable --now hpfand 2>/dev/null || true
rm -f /etc/systemd/system/hpfand.service
rm -f "$PREFIX/bin/hpfand"
rm -f "$PREFIX/bin/hpf"
if [[ -f /etc/hpfand.conf ]]; then
    echo "leaving /etc/hpfand.conf in place — remove manually if not needed"
fi
rm -rf /var/lib/hpfand
systemctl daemon-reload
echo "uninstalled"
