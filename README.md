# hp-victus-fan-control

HP Victus/Omen fans on Linux burst unpredictably because the firmware resets fan settings every ~120s and the out-of-tree `hp_wmi` driver has no mechanism to fight it. The in-tree driver has a keep-alive that re-applies settings every 90s, but it had several bugs of its own — a deadlock, a GPU fan spike, and a timer that misfired. Those are fixed in patches currently queued in `platform-drivers-x86/review-ilpo-next`. This daemon sits on top of that and gives you a smooth, interpolated fan curve instead of the firmware's aggressive default.

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
git clone https://github.com/emomaxd/hp-victus-fan-control
cd hp-victus-fan-control
sudo ./install.sh
```

If the check above failed, get the patched module first — see [Getting the module](#getting-the-module).

## Usage

```sh
hp-fan-curve status              # live: temp, fan rpm, pwm, active preset
hp-fan-curve presets             # list presets
sudo hp-fan-curve set balanced   # default
sudo hp-fan-curve set silent     # minimum speed up to 50°C — library/idle
sudo hp-fan-curve set performance
sudo hp-fan-curve edit           # edit /etc/hp-fan-control.conf in $EDITOR
hp-fan-curve toggle              # toggle silent on/off — no root, bind to a key
```

## Presets

| preset | min speed until | max speed at | hysteresis |
|--------|-----------------|--------------|------------|
| silent | 50°C | 90°C | 8°C |
| balanced | 40°C | 82°C | 6°C |
| performance | 35°C | 78°C | 4°C |

## Custom curve

`/etc/hp-fan-control.conf`:

```sh
CT=(40 50 60 72 82)  # °C
CP=(0  30 80 170 240)  # PWM 0-255
HYST=6               # °C — ramp-down hysteresis
POLL_SEC=2
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

```sh
git clone https://github.com/emomaxd/linux -b hp-wmi-fixes --depth=1
cd linux
make -C /lib/modules/$(uname -r)/build M=$(pwd)/drivers/platform/x86/hp modules
sudo rmmod hp_wmi 2>/dev/null; sudo insmod drivers/platform/x86/hp/hp-wmi.ko
```

To survive reboots (until next kernel update):

```sh
sudo cp drivers/platform/x86/hp/hp-wmi.ko /lib/modules/$(uname -r)/updates/hp-wmi.ko
sudo depmod -a
```

> This only persists for the current kernel version. After a kernel update, rebuild the module.

## Uninstall

```sh
sudo ./uninstall.sh
```
