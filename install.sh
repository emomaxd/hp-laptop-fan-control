#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"

[[ $EUID -eq 0 ]] || { echo "error: run as root"; exit 1; }
command -v systemctl >/dev/null 2>&1 || { echo "error: systemctl not found — not a systemd system?"; exit 1; }
getent group hpfand >/dev/null || groupadd --system hpfand

HP_HWMON=
for f in /sys/class/hwmon/*/name; do
    [[ -f "$f" && "$(<"$f")" == hp ]] || continue
    dir=$(dirname "$f")
    [[ -e "$dir/pwm1" && -e "$dir/pwm1_enable" ]] && HP_HWMON=$dir && break
done
[[ -d "$HP_HWMON" ]] || {
    echo "error: hp-wmi hwmon not found — patched module not loaded?"
    echo "  lsmod | grep hp_wmi"
    echo "  ls /sys/devices/platform/hp-wmi/hwmon/"
    exit 1
}

install -Dm755 "$SCRIPT_DIR/hpfand" "$PREFIX/bin/hpfand"
install -Dm755 "$SCRIPT_DIR/hpf"   "$PREFIX/bin/hpf"

install -d -o root -g hpfand -m 0770 /var/lib/hpfand

sed "s|HPFAND_BIN|$PREFIX/bin/hpfand|" \
    "$SCRIPT_DIR/hpfand.service" \
    > /etc/systemd/system/hpfand.service
chmod 644 /etc/systemd/system/hpfand.service

systemctl daemon-reload
systemctl enable hpfand
systemctl restart hpfand
systemctl status hpfand --no-pager || true
