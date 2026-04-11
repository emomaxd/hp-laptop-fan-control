# hp-victus-fan-control

HP Victus/Omen fans on Linux burst unpredictably because the firmware resets fan settings every ~120s and the out-of-tree `hp_wmi` driver has no mechanism to fight it. The in-tree driver (Linux ≥7.0) fixes this with a keep-alive that re-applies settings every 90s. This daemon sits on top of that and gives you a smooth, interpolated fan curve instead of the firmware's aggressive default.

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
sudo hp-fan-curve set silent     # fan stop up to 50°C — library/idle
sudo hp-fan-curve set performance
sudo hp-fan-curve edit           # edit /etc/hp-fan-control.conf in $EDITOR
hp-fan-curve toggle              # toggle silent on/off — no root, bind to a key
```

## Presets

| preset | fan stop until | max speed at | hysteresis |
|--------|----------------|--------------|------------|
| silent | 50°C | 90°C | 8°C |
| balanced | 40°C | 82°C | 6°C |
| performance | 35°C | 78°C | 4°C |

## Custom curve

`/etc/hp-fan-control.conf`:

```sh
CT=(40000 50000 60000 72000 82000)  # millidegrees
CP=(0     30    80    170   240)    # PWM 0-255
HYST_MC=6000
POLL_SEC=2
```

Points are linearly interpolated. Ramp-up is immediate. Ramp-down waits until temp drops `HYST_MC` below the last ramp-up point — this prevents rapid toggling at threshold boundaries.

## Getting the module

The `pwm1` hwmon interface for Victus S boards landed in the in-tree `hp_wmi` driver in Linux 7.0. While investigating the burst issue on my own machine I found and fixed several bugs in the driver:

- `u8` underflow in `gpu_delta` — GPU fan clamps at 100% when its target RPM is lower than the CPU fan's
- keep-alive timer not reset on user interaction — fires 5s after a manual speed change instead of 90s later
- `cancel_delayed_work_sync` called from within the work handler — deadlock under concurrent sysfs writes
- missing mutex in hwmon read/write paths

These are in Linux 7.0. The branch linked below contains them if you're on an older kernel.

**Linux ≥ 7.0:** already included. Run the check at the top.

**Older kernels:**

```sh
git clone https://github.com/emomaxd/linux -b hp-wmi-fixes --depth=1
cd linux
make -C /lib/modules/$(uname -r)/build M=$(pwd)/drivers/platform/x86/hp modules
sudo insmod drivers/platform/x86/hp/hp-wmi.ko
```

To persist across reboots:

```sh
sudo cp drivers/platform/x86/hp/hp-wmi.ko /lib/modules/$(uname -r)/updates/hp-wmi.ko
sudo depmod -a
```

## Uninstall

```sh
sudo ./uninstall.sh
```
