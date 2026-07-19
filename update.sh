#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"

[[ $EUID -eq 0 ]] || { echo "error: run as root"; exit 1; }
[[ "$PREFIX" =~ ^/[A-Za-z0-9_./:+-]+$ ]] || { echo "error: PREFIX must be an absolute path without whitespace"; exit 1; }
command -v systemctl >/dev/null 2>&1 || { echo "error: systemctl not found"; exit 1; }
command -v systemd-notify >/dev/null 2>&1 || { echo "error: systemd-notify not found"; exit 1; }
command -v udevadm >/dev/null 2>&1 || { echo "error: udevadm not found"; exit 1; }
command -v flock >/dev/null 2>&1 || { echo "error: flock not found (install util-linux)"; exit 1; }
getent group hpfand >/dev/null || groupadd --system hpfand
id -u hpfand >/dev/null 2>&1 || useradd --system --gid hpfand --home-dir /var/lib/hpfand --shell /usr/sbin/nologin hpfand
[[ "$(id -gn hpfand)" == hpfand ]] || { echo "error: existing hpfand user does not use the hpfand group"; exit 1; }

install -Dm755 "$SCRIPT_DIR/hpfand" "$PREFIX/bin/hpfand"
install -Dm755 "$SCRIPT_DIR/hpf"   "$PREFIX/bin/hpf"
install -Dm644 "$SCRIPT_DIR/90-hpfand.rules" /etc/udev/rules.d/90-hpfand.rules
install -d -o hpfand -g hpfand -m 0770 /var/lib/hpfand
udevadm control --reload-rules
udevadm trigger --subsystem-match=hwmon --action=change
udevadm settle
SERVICE_TMP=$(mktemp)
trap 'rm -f "$SERVICE_TMP"' EXIT
sed "s|HPFAND_BIN|$PREFIX/bin/hpfand|" "$SCRIPT_DIR/hpfand.service" > "$SERVICE_TMP"
install -Dm644 "$SERVICE_TMP" /etc/systemd/system/hpfand.service
systemctl daemon-reload
systemctl restart hpfand
echo "updated to $(git -C "$SCRIPT_DIR" describe --tags 2>/dev/null || git -C "$SCRIPT_DIR" rev-parse --short HEAD)"
