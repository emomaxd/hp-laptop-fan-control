# hp-victus-fan-control

Fan curve daemon for HP Victus S laptops on Linux. Fixes the firmware burst problem and gives you smooth, interpolated fan control via the `hp_wmi` hwmon interface.

## The problem

HP firmware resets manual fan settings after ~120s. The stock out-of-tree `hp-wmi` driver has no keep-alive, so fans revert to the firmware's aggressive auto curve and spike unpredictably. Additionally, a `u8` underflow in `gpu_delta` calculation causes the GPU fan to clamp at 100% whenever GPU target RPM < CPU target RPM.

This daemon pairs with a patched `hp_wmi` kernel module that fixes both issues.

## Requirements

**Kernel module:** The in-tree `hp_wmi` driver from Linux ≥7.0-rc7 (or backported). The relevant fixes:

- `platform/x86: hp-wmi: fix u8 underflow in gpu_delta calculation`
- `platform/x86: hp-wmi: use mod_delayed_work to reset keep-alive timer`
- `platform/x86: hp-wmi: avoid cancel_delayed_work_sync from work handler`
- `platform/x86: hp-wmi: add locking for concurrent hwmon access`

The module exposes `/sys/devices/platform/hp-wmi/hwmon/hwmon*/pwm1` and `pwm1_enable` for Victus S boards. Without these fixes the keep-alive fires at the wrong time or deadlocks.

**Supported boards** (DMI board name):

| Board | Models |
|-------|--------|
| 8BBE  | HP Victus 16-s |
| 8BD4  | HP Victus 16-s |
| 8BD5  | HP Victus 16-s |
| 8C99  | HP Victus 16-r1xxx |
| 8C9C  | HP Victus 16-s1xxx |
| 8D41  | HP Victus 16 |
| 8BAB, 8BCA, 8BCD, 8C76, 8C78, 8A4D | HP Omen variants |

Check yours: `cat /sys/class/dmi/id/board_name`

## Fan curve

Linear interpolation between control points. No step jumps.

```
< 40°C   →   0 PWM    fan stop
  50°C   →  30 PWM    ~700 RPM
  60°C   →  80 PWM    ~1900 RPM
  72°C   → 170 PWM    ~3600 RPM
  82°C   → 240 PWM    ~4800 RPM
> 82°C   → 255 PWM    max
```

Ramp-up is immediate. Ramp-down requires temp to drop 6°C below the last ramp-up point (hysteresis), preventing hunting.

## Install

```sh
git clone https://github.com/emomaxd/hp-victus-fan-control
cd hp-victus-fan-control
sudo ./install.sh
```

## Silent mode

Toggle fans off (library, low-load):

```sh
hp-fan-toggle-silent   # off
hp-fan-toggle-silent   # back to curve
```

Bind to a key in your DE/WM. The daemon detects `/tmp/hp-fan-silent` and resumes the curve when it's removed.

## Tuning the curve

Edit the two arrays in `hp-fan-control`:

```bash
CT=(40000  50000  60000  72000  82000)   # millidegrees
CP=(0      30     80     170    240)     # PWM 0-255
```

Points must be strictly increasing. The daemon interpolates linearly between them and clamps to 255 above the last point.

## How it works

1. Reads CPU Package temperature from coretemp (`temp1_input`)
2. Writes `pwm1_enable=1` (manual) + interpolated `pwm1` every 2s
3. The kernel driver's keep-alive re-applies the last value every 90s, so firmware never gets the 120s window to reset

Polling at 2s is enough because the system's thermal time constant is ~15-20s. Faster polling wastes cycles without meaningful benefit.
