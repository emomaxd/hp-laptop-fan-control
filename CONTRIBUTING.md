# Contributing

## Reporting issues

Include the following in a bug report:

```sh
uname -r
cat /sys/class/dmi/id/board_name
cat /sys/class/dmi/id/product_name
ls /sys/devices/platform/hp-wmi/hwmon/hwmon*/pwm1 2>/dev/null || echo "hwmon not found"
hpf status
journalctl -u hpfand -n 30 --no-pager
```

For hardware compatibility reports (new board, fan behaves wrong), the board name and a description of the symptom is enough.

## Submitting patches

- Keep changes minimal — match the style of the surrounding code.
- One logical change per commit.
- Test with `sudo hpfand --dry-run` before submitting.

Open a pull request against `master`.

## Kernel driver

The underlying `hp_wmi` fixes are landing in **Linux 7.1**. Until then, use `build-module.sh` to build the patched module. Kernel-level issues belong in the [linux fork](https://github.com/emomaxd/linux/tree/hp-wmi-victus-fan-v4), not here.
