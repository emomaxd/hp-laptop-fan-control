#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"

[[ $EUID -eq 0 ]] || { echo "error: run as root"; exit 1; }
[[ "$PREFIX" =~ ^/[A-Za-z0-9_./:+-]+$ ]] || { echo "error: PREFIX must be an absolute path without whitespace"; exit 1; }
command -v systemctl >/dev/null 2>&1 || { echo "error: systemctl not found — not a systemd system?"; exit 1; }
command -v udevadm >/dev/null 2>&1 || { echo "error: udevadm not found"; exit 1; }
command -v flock >/dev/null 2>&1 || { echo "error: flock not found (install util-linux)"; exit 1; }
getent group hpfand >/dev/null || groupadd --system hpfand
id -u hpfand >/dev/null 2>&1 || useradd --system --gid hpfand --home-dir /var/lib/hpfand --shell /usr/sbin/nologin hpfand
[[ "$(id -gn hpfand)" == hpfand ]] || { echo "error: existing hpfand user does not use the hpfand group"; exit 1; }

HP_HWMON=
for f in /sys/class/hwmon/*/name; do
    [[ -f "$f" && "$(<"$f")" == hp ]] || continue
    dir=$(dirname "$f")
    [[ -e "$dir/pwm1" && -e "$dir/pwm1_enable" ]] && HP_HWMON=$dir && break
done
[[ -d "$HP_HWMON" ]] || {
    echo "error: supported hp-wmi PWM interface not found"
    echo "  ls /sys/class/hwmon/*/pwm1 2>/dev/null"
    exit 1
}

install -Dm755 "$SCRIPT_DIR/hpfand" "$PREFIX/bin/hpfand"
install -Dm755 "$SCRIPT_DIR/hpf"   "$PREFIX/bin/hpf"
install -Dm644 "$SCRIPT_DIR/90-hpfand.rules" /etc/udev/rules.d/90-hpfand.rules

install -d -o hpfand -g hpfand -m 0770 /var/lib/hpfand
chgrp hpfand "$HP_HWMON/pwm1" "$HP_HWMON/pwm1_enable"
chmod 0660 "$HP_HWMON/pwm1" "$HP_HWMON/pwm1_enable"
udevadm control --reload-rules
udevadm trigger --subsystem-match=hwmon --action=change
udevadm settle

SERVICE_TMP=$(mktemp)
trap 'rm -f "$SERVICE_TMP"' EXIT
sed "s|HPFAND_BIN|$PREFIX/bin/hpfand|" "$SCRIPT_DIR/hpfand.service" > "$SERVICE_TMP"
install -Dm644 "$SERVICE_TMP" /etc/systemd/system/hpfand.service

systemctl daemon-reload
systemctl enable hpfand
systemctl restart hpfand
systemctl status hpfand --no-pager || true
