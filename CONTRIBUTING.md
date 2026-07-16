# Contributing

Hardware reports are as useful as code. Use the compatibility issue template
for a machine that is not yet listed in `docs/hardware.md`.

## Before opening an issue

Run:

```sh
uname -r
cat /sys/class/dmi/id/board_name
cat /sys/class/dmi/id/product_name
ls /sys/devices/platform/hp-wmi/hwmon/hwmon*/pwm1 2>/dev/null
hpf status
journalctl -u hpfand -n 50 --no-pager
```

Remove serial numbers, UUIDs and unrelated journal output.

## Patches

Keep changes small and preserve the fail-safe behavior. Run:

```sh
bash -n hpfand hpf install.sh update.sh uninstall.sh tests/test_hpfand.sh
shellcheck -x -e SC1090 hpfand hpf install.sh update.sh uninstall.sh tests/test_hpfand.sh
tests/test_hpfand.sh
udevadm verify 90-hpfand.rules
git diff --check
```

Test control-loop changes with the simulated hwmon fixtures and with
`sudo hpfand --dry-run` before writing to hardware. Kernel driver development is
outside this repository's scope.
