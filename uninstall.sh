#!/bin/bash
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"

[[ $EUID -eq 0 ]] || { echo "error: run as root"; exit 1; }
[[ "$PREFIX" =~ ^/[A-Za-z0-9_./:+-]+$ ]] || { echo "error: PREFIX must be an absolute path without whitespace"; exit 1; }

systemctl disable --now hpfand 2>/dev/null || true
for name_file in /sys/class/hwmon/*/name; do
    [[ -f "$name_file" && "$(<"$name_file")" == hp ]] || continue
    hwmon_dir=$(dirname "$name_file")
    chgrp root "$hwmon_dir/pwm1" "$hwmon_dir/pwm1_enable" 2>/dev/null || true
    chmod 0644 "$hwmon_dir/pwm1" "$hwmon_dir/pwm1_enable" 2>/dev/null || true
done
rm -f /etc/systemd/system/hpfand.service
rm -f /etc/udev/rules.d/90-hpfand.rules
rm -f "$PREFIX/bin/hpfand"
rm -f "$PREFIX/bin/hpf"
if [[ -f /etc/hpfand.conf ]]; then
    echo "leaving /etc/hpfand.conf in place — remove manually if not needed"
fi
rm -rf /var/lib/hpfand
udevadm control --reload-rules
id -u hpfand >/dev/null 2>&1 && userdel hpfand || true
systemctl daemon-reload
echo "uninstalled"
