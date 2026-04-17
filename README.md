# hp-laptop-fan-control

Fan curve daemon for HP Victus/Omen laptops on Linux. The firmware resets fan settings periodically and ramps aggressively. This daemon re-applies a configurable PWM curve every poll cycle to keep fans under control.

Requires the in-tree `hp_wmi` driver with hwmon fan support — see [Getting the module](#getting-the-module) if you don't have it.

## Does it work on my machine?

```sh
ls /sys/devices/platform/hp-wmi/hwmon/hwmon*/pwm1 2>/dev/null \
  && echo "supported" || echo "need patched module — see below"
```

Supported boards (`cat /sys/class/dmi/id/board_name`):

| Board | Series |
|-------|--------|
| 8BBE, 8BD4, 8BD5, 8C99, 8C9C, 8D41 | HP Victus S |
| 8BAB, 8BCA, 8BCD, 8C76, 8C78, 8A4D | HP Omen |

## Install

```sh
git clone https://github.com/emomaxd/hp-laptop-fan-control
cd hp-laptop-fan-control
sudo ./install.sh
```

If the check above failed, get the patched module first — see [Getting the module](#getting-the-module).

## Usage

```sh
hp-fan-curve status              # live: cpu/gpu temp, fan rpm, pwm, active preset
hp-fan-curve status -w           # watch mode — refresh every 2s
hp-fan-curve status -w 1         # watch mode — refresh every 1s
hp-fan-curve presets             # list presets
sudo hp-fan-curve set balanced   # default
sudo hp-fan-curve set silent     # minimum speed up to 50°C — library/idle
sudo hp-fan-curve set performance
sudo hp-fan-curve follow         # auto-track system power profile (power-profiles-daemon / TLP)
sudo hp-fan-curve pwm 120        # lock fans at fixed pwm (stops daemon, no thermal protection)
sudo hp-fan-curve edit           # edit /etc/hp-fan-control.conf in $EDITOR
hp-fan-curve toggle              # toggle silent on/off — no root, bind to a key
```

## Presets

| preset | min speed until | max speed at | hysteresis | poll |
|--------|-----------------|--------------|------------|------|
| silent | 50°C | 90°C | 8°C | 4s |
| balanced | 40°C | 82°C | 6°C | 2s |
| performance | 35°C | 78°C | 4°C | 1s |

## Power profile tracking

```sh
sudo hp-fan-curve follow
```

Automatically maps the system's active power profile to the matching fan preset. Works with `power-profiles-daemon`, `TLP`, `auto-cpufreq`, or anything that writes `/sys/firmware/acpi/platform_profile`:

| platform profile | fan preset used |
|------------------|-----------------|
| `low-power` | silent |
| `balanced` | balanced |
| `performance` | performance |

Switching back to a fixed preset (`hp-fan-curve set <preset>`) disables follow mode.

## Custom curve

`/etc/hp-fan-control.conf`:

```sh
CT=(40 50 60 72 82)  # °C
CP=(0  30 80 170 240)  # PWM 0-255
HYST=6               # °C — ramp-down hysteresis
POLL_SEC=2
FOLLOW_PLATFORM_PROFILE=0  # set to 1 to auto-track power profile
RPM_STALL_WARN=1           # warn in journal if fan stalls at high PWM
```

Pass `--dry-run` to the daemon to print calculated PWM values without writing:

```sh
sudo hp-fan-control --dry-run
```

Points are linearly interpolated. Ramp-up is immediate. Ramp-down waits until temp drops `HYST` degrees below the last ramp-up point — prevents rapid toggling at threshold boundaries.

## Getting the module

The `pwm1` hwmon interface for Victus S boards is in the in-tree `hp_wmi` driver. While working on this I submitted several fixes to the driver, currently queued in `platform-drivers-x86/review-ilpo-next` and expected to reach linux-next and land in 7.0–7.1:

- `platform/x86: hp-wmi: fix ignored return values in fan settings`
- `platform/x86: hp-wmi: avoid cancel_delayed_work_sync from work handler`
- `platform/x86: hp-wmi: use mod_delayed_work to reset keep-alive timer`
- `platform/x86: hp-wmi: fix u8 underflow in gpu_delta calculation`
- `platform/x86: hp-wmi: add locking for concurrent hwmon access`

**Linux ≥ 7.0 (once merged):** run the check at the top to verify.

**Older kernels:** build the module from the branch below and load it on top of your running kernel.

Make sure the kernel headers for your running kernel are installed.

```sh
git clone https://github.com/emomaxd/linux -b hp-wmi-fixes --depth=1
cd linux
mkdir /tmp/hp-wmi-build
cp drivers/platform/x86/hp/hp-wmi.c /tmp/hp-wmi-build/
echo 'obj-m += hp-wmi.o' > /tmp/hp-wmi-build/Makefile
make -C /lib/modules/$(uname -r)/build M=/tmp/hp-wmi-build modules
sudo rmmod hp_wmi
sudo insmod /tmp/hp-wmi-build/hp-wmi.ko
```

To survive reboots (until next kernel update):

```sh
sudo cp /tmp/hp-wmi-build/hp-wmi.ko /lib/modules/$(uname -r)/updates/hp-wmi.ko
sudo depmod -a
```

> This only persists for the current kernel version. After a kernel update, rebuild the module.

## Uninstall

```sh
sudo ./uninstall.sh
```
