# hp-victus-fan-control

Fan curve daemon for HP Victus/Omen laptops on Linux.

## Requirements

The `hp_wmi` driver must expose `pwm1`/`pwm1_enable` via hwmon. This landed in Linux 7.0 with fixes for:

- `u8` underflow in `gpu_delta` — GPU fan clamps at 100% when its target RPM is less than CPU's
- premature keep-alive timer firing after user interaction
- deadlock when keep-alive fires concurrently with a sysfs write
- missing mutex in hwmon read/write paths

Patches authored by [Emre Cecanpunar](https://github.com/emomaxd), available at [emomaxd/linux](https://github.com/emomaxd/linux).

**Check if your kernel already has it:**

```sh
ls /sys/devices/platform/hp-wmi/hwmon/hwmon*/pwm1 2>/dev/null \
  && echo "supported" || echo "need patched module"
```

**Supported boards** (`cat /sys/class/dmi/id/board_name`):

| Board | Series |
|-------|--------|
| 8BBE, 8BD4, 8BD5, 8C99, 8C9C, 8D41 | HP Victus S |
| 8BAB, 8BCA, 8BCD, 8C76, 8C78, 8A4D | HP Omen |

## Getting the patched module

### Distros shipping Linux ≥ 7.0

Nothing to do. Verify with the check above.

### Older kernels — build the module

```sh
git clone https://github.com/emomaxd/linux -b hp-wmi-fixes --depth=1
cd linux
make -C /lib/modules/$(uname -r)/build M=$(pwd)/drivers/platform/x86/hp modules
sudo insmod drivers/platform/x86/hp/hp-wmi.ko
```

To persist across reboots, copy to the dkms directory and run `depmod`:

```sh
sudo cp drivers/platform/x86/hp/hp-wmi.ko \
  /lib/modules/$(uname -r)/updates/hp-wmi.ko
sudo depmod -a
```

## Install

```sh
git clone https://github.com/emomaxd/hp-victus-fan-control
cd hp-victus-fan-control
sudo ./install.sh
# custom prefix: sudo PREFIX=/usr ./install.sh
```

## Usage

```sh
hp-fan-curve status              # live temp, rpm, pwm, active preset
hp-fan-curve presets             # list presets
sudo hp-fan-curve set balanced   # default
sudo hp-fan-curve set silent     # fan stop up to 50°C
sudo hp-fan-curve set performance
sudo hp-fan-curve edit           # edit /etc/hp-fan-control.conf in $EDITOR
hp-fan-curve toggle              # toggle silent on/off — bind to a key
```

## Presets

| preset | fan stop | max speed at | hysteresis |
|--------|----------|--------------|------------|
| silent | 50°C | 90°C | 8°C |
| balanced | 40°C | 82°C | 6°C |
| performance | 35°C | 78°C | 4°C |

## Custom curve

```sh
sudo hp-fan-curve edit
```

`/etc/hp-fan-control.conf` format:

```sh
CT=(40000 50000 60000 72000 82000)  # control point temps, millidegrees
CP=(0     30    80    170   240)    # PWM values, 0-255
HYST_MC=6000                        # ramp-down hysteresis, millidegrees
POLL_SEC=2
```

Points are linearly interpolated. Ramp-up is immediate; ramp-down waits until temp drops `HYST_MC` below the last ramp-up temperature.

## Uninstall

```sh
sudo ./uninstall.sh
```
