# hp-victus-fan-control

Fan curve daemon for HP Victus/Omen laptops on Linux. Requires a patched `hp_wmi` kernel module that exposes `pwm1`/`pwm1_enable` via hwmon for Victus S boards.

## Background

HP firmware resets manual fan settings after ~120s. The `hp_wmi` driver in Linux ≥7.0 implements a keep-alive that re-applies settings every 90s to prevent this. Several bugs in that implementation are fixed by patches authored by [Emre Cecanpunar](https://github.com/emomaxd):

- `u8` underflow in `gpu_delta` — GPU fan clamps at 100% when its target RPM < CPU target RPM
- `schedule_delayed_work` instead of `mod_delayed_work` — keep-alive timer not reset on user interaction, fires prematurely
- `cancel_delayed_work_sync` called from within the work handler — deadlock under concurrent sysfs writes
- Missing mutex in hwmon read/write paths — race condition

Without these fixes, the daemon still works but you may see GPU fan spikes and occasional bursts when the keep-alive fires at the wrong time.

## Supported boards

Check yours: `cat /sys/class/dmi/id/board_name`

| Board | Series |
|-------|--------|
| 8BBE, 8BD4, 8BD5, 8C99, 8C9C, 8D41 | HP Victus S |
| 8BAB, 8BCA, 8BCD, 8C76, 8C78, 8A4D | HP Omen |

## Kernel module

### Option A — build from source (recommended)

```sh
git clone https://github.com/torvalds/linux   # or your distro's tree
cd linux
# apply the patches below if your kernel is < 7.0
make menuconfig   # enable CONFIG_HP_WMI=m, CONFIG_HWMON=m
make -j$(nproc) M=drivers/platform/x86/hp
sudo insmod drivers/platform/x86/hp/hp-wmi.ko
```

Patches (in order) if on an older kernel:

```
platform/x86: hp-wmi: fix ignored return values in fan settings
platform/x86: hp-wmi: avoid cancel_delayed_work_sync from work handler
platform/x86: hp-wmi: use mod_delayed_work to reset keep-alive timer
platform/x86: hp-wmi: fix u8 underflow in gpu_delta calculation
platform/x86: hp-wmi: add locking for concurrent hwmon access
```

Available at: https://github.com/emomaxd/linux (branch with hp-wmi fixes)

### Option B — DKMS (easiest for existing kernels)

```sh
sudo cp -r . /usr/src/hp-victus-fan-control-1.0
sudo dkms add hp-victus-fan-control/1.0
sudo dkms build hp-victus-fan-control/1.0
sudo dkms install hp-victus-fan-control/1.0
```

> Note: DKMS option requires a `dkms.conf` — coming soon.

### Verify

```sh
ls /sys/devices/platform/hp-wmi/hwmon/hwmon*/pwm1
```

If the file exists, the module is loaded correctly.

## Install

```sh
git clone https://github.com/emomaxd/hp-victus-fan-control
cd hp-victus-fan-control
sudo ./install.sh
```

## Usage

```sh
hp-fan-curve show              # current curve
hp-fan-curve presets           # list presets
sudo hp-fan-curve set silent   # library/idle
sudo hp-fan-curve set balanced # default
sudo hp-fan-curve set performance
sudo hp-fan-curve edit         # manual edit in $EDITOR
hp-fan-toggle-silent           # toggle fans off/on (bind to a key)
```

## Monitor

```sh
watch -n2 'echo "cpu: $(( $(cat /sys/devices/platform/coretemp.0/hwmon/hwmon*/temp1_input | head -1) / 1000 ))°C  fan: $(cat /sys/devices/platform/hp-wmi/hwmon/hwmon*/fan1_input)rpm  pwm: $(cat /sys/devices/platform/hp-wmi/hwmon/hwmon*/pwm1)"'
```

## Curve

Default (balanced preset):

```
< 40°C    0 PWM    fan stop
  50°C   30 PWM    ~700 RPM
  60°C   80 PWM    ~1900 RPM
  72°C  170 PWM    ~3600 RPM
  82°C  240 PWM    ~4800 RPM
> 82°C  255 PWM    max
```

Ramp-up is immediate. Ramp-down requires temp to drop 6°C below the last ramp-up point. Edit via `hp-fan-curve edit` or by writing `/etc/hp-fan-control.conf` directly — see `conf/` for examples.
