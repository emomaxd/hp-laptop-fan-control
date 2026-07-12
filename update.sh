#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"

[[ $EUID -eq 0 ]] || { echo "error: run as root"; exit 1; }
getent group hpfand >/dev/null || groupadd --system hpfand

install -Dm755 "$SCRIPT_DIR/hpfand" "$PREFIX/bin/hpfand"
install -Dm755 "$SCRIPT_DIR/hpf"   "$PREFIX/bin/hpf"
install -d -o root -g hpfand -m 0770 /var/lib/hpfand
sed "s|HPFAND_BIN|$PREFIX/bin/hpfand|" "$SCRIPT_DIR/hpfand.service" > /etc/systemd/system/hpfand.service
chmod 644 /etc/systemd/system/hpfand.service
systemctl daemon-reload
systemctl restart hpfand
echo "updated to $(git -C "$SCRIPT_DIR" describe --tags 2>/dev/null || git -C "$SCRIPT_DIR" rev-parse --short HEAD)"
