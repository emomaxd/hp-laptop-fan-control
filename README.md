# hpfand

`hpfand` is a fan-curve daemon for HP Victus and Omen laptops. It reads CPU and
GPU temperatures from hwmon and writes a single PWM value to the native
`hp_wmi` interface.

```text
$ hpf status
preset:  auto (follow profile)
mode:    manual (daemon active)
profile: balanced
---
cpu:     54°C
fan1:    1200 rpm
fan2:    1200 rpm
pwm:     52/255
```

No GUI, background framework or EC register poking. The daemon is a Bash
process managed by systemd.

## Check support

```sh
ls /sys/devices/platform/hp-wmi/hwmon/hwmon*/pwm1 >/dev/null 2>&1 \
  && echo supported || echo unavailable
```

The interface is available in the upstream kernel on supported boards from
Linux 7.1. Older kernels need the patched module described below. See the
[hardware matrix](docs/hardware.md) for board IDs and verified machines.

## Install

From source:

```sh
git clone https://github.com/emomaxd/hpfand.git
cd hpfand
sudo ./install.sh
```

To let the current user toggle silent mode without root:

```sh
sudo usermod -aG hpfand "$USER"
```

Log out and back in after changing group membership.

## Commands

```text
hpf status              show temperatures, RPM, PWM and active profile
hpf status -w           refresh status every two seconds
hpf toggle              toggle silent mode
hpf presets             list built-in curves
hpf log 50              read daemon logs

sudo hpf set balanced   apply silent, balanced or performance
sudo hpf follow         follow the ACPI platform power profile
sudo hpf edit           edit /etc/hpfand.conf and restart the daemon
sudo hpf pwm 120        stop the daemon and hold a fixed PWM value
```

`hpf pwm` disables the daemon's thermal response. Apply a preset to restore it.

## Control loop

Each poll reads the CPU package temperature and, when active, the discrete GPU
temperature. The higher PWM request wins. Curve points are linearly
interpolated; increases happen immediately subject to `SLEW_UP`, while
decreases wait for the configured hysteresis and follow `SLEW_DOWN`.

The daemon only updates sysfs when the PWM changes. Failed writes are retried.
Three invalid CPU readings force PWM 255. On a clean shutdown, control returns
to firmware mode.

`hpf follow` maps platform profiles as follows:

| platform profile | curve |
|---|---|
| `low-power` | silent |
| `balanced` | balanced |
| `performance` | performance |

## Configuration

`/etc/hpfand.conf` is a restricted numeric data file, not a shell script.

```sh
CT=(40 50 60 72 82)
CP=(0 30 80 170 255)

GPU_CT=(45 55 65 75 85)
GPU_CP=(0 40 100 180 255)

HYST=6
POLL_SEC=2
SLEW_UP=100
SLEW_DOWN=20
MIN_PWM=0

FOLLOW_PLATFORM_PROFILE=0
RPM_STALL_WARN=1
SILENT_OFF_BELOW=0
```

`CT`/`GPU_CT` are degrees Celsius. `CP`/`GPU_CP` are PWM values from 0 to 255.
GPU arrays are optional and default to the CPU curve. `SILENT_OFF_BELOW=0`
uses the second-highest curve point.

If `inotify-tools` is installed, atomic saves reload the file without a service
restart. Inspect curve output without touching PWM:

```sh
sudo hpfand --dry-run
```

## Kernels before 7.1

Install headers for the running kernel, then build the reviewed `hp_wmi`
backport:

```sh
sudo ./build-module.sh
sudo ./install.sh
```

The script verifies the driver source against a pinned SHA-256 before compiling
or loading it. The module must be rebuilt after a kernel update.

The upstream driver work is tracked in
[`hp-wmi-victus-fan-v4`](https://github.com/emomaxd/linux/commits/hp-wmi-victus-fan-v4).

## Troubleshooting

- `hp-wmi hwmon not found`: the running kernel does not expose the interface,
  or the board is not supported.
- Fan speed does not change: check `hpf status` and `hpf log 50`; mode must be
  `manual (daemon active)`.
- GPU temperature is absent: a discrete GPU in D3cold has no active hwmon
  sensor. It is detected when the GPU wakes.
- Kernel updated and PWM disappeared: rebuild the backported module.

For new hardware, open a
[compatibility report](https://github.com/emomaxd/hpfand/issues/new?template=hardware.yml).

## Uninstall

```sh
sudo ./uninstall.sh
```

Licensed under GPL-2.0-only.
