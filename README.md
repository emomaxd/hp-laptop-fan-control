# hpfand

Fan curve daemon for HP Victus/Omen laptops on Linux. The firmware resets fan settings periodically and ramps aggressively. This daemon re-applies a configurable PWM curve every poll cycle to keep fans under control.

## Does it work on my machine?

```sh
ls /sys/devices/platform/hp-wmi/hwmon/hwmon*/pwm1 2>/dev/null \
  && echo "supported" || echo "pwm1 not found — see Getting the module"
```

Supported boards (`cat /sys/class/dmi/id/board_name`):

| Board | Series |
|-------|--------|
| 8BBE, 8BD4, 8BD5, 8C99, 8C9C, 8D41 | HP Victus |
| 8BAB, 8BCA, 8BCD, 8C76, 8C78, 8A4D | HP Omen |

**Linux ≥ 7.1:** fully supported, skip to [Install](#install).

**Older kernels, `pwm1` found:** the daemon works, but the stock driver has known bugs (dropped fan writes, keep-alive races, wrong GPU delta). Building the patched module is recommended for reliable operation — see [Getting the module](#getting-the-module).

**Older kernels, `pwm1` not found:** the patched module must be loaded first or `install.sh` will fail — see [Getting the module](#getting-the-module).

---

## Install

```sh
git clone https://github.com/emomaxd/hpfand
cd hpfand
sudo ./install.sh
```

This installs the daemon as a systemd service and starts it immediately.

---

## Usage

`hpf` is the CLI companion to `hpfand`.

```sh
hpf status              # cpu/gpu temp, fan rpm, pwm, active preset
hpf status -w           # watch mode — refresh every 2s
hpf status -w 1         # watch mode — refresh every 1s
hpf presets             # list available presets
hpf toggle              # toggle silent mode on/off — no root needed, persists across reboots
hpf log                 # show last 50 journal entries
hpf log 100
```

```sh
sudo hpf set balanced     # apply a preset
sudo hpf set silent
sudo hpf set performance
sudo hpf follow           # auto-track system power profile
sudo hpf pwm 120          # lock fans at fixed pwm — stops daemon, no thermal protection
sudo hpf edit             # edit /etc/hpfand.conf in $EDITOR
```

Example output of `hpf status`:

```
preset:  auto (follow profile)
mode:    manual (daemon active)
profile: balanced
---
cpu:     61°C
gpu:     43°C
fan1:    2900 rpm
fan2:    2900 rpm
pwm:     110/255
```

---

## Presets

| preset | fans off until | max speed at | hysteresis | poll |
|--------|----------------|--------------|------------|------|
| silent | 50°C | 90°C | 8°C | 4s |
| balanced | 40°C | 82°C | 6°C | 2s |
| performance | 35°C | 78°C | 4°C | 1s |

---

## Power profile tracking

```sh
sudo hpf follow
```

Automatically maps the active system power profile to the matching preset. Works with `power-profiles-daemon`, `TLP`, `auto-cpufreq`, or anything that writes `/sys/firmware/acpi/platform_profile`:

| platform profile | preset |
|------------------|--------|
| `low-power` | silent |
| `balanced` | balanced |
| `performance` | performance |

Switch back to a fixed preset at any time with `sudo hpf set <preset>`.

---

## Custom curve

`/etc/hpfand.conf`:

```sh
CT=(40 50 60 72 82)    # CPU temp thresholds in °C
CP=(0  30 80 170 240)  # PWM values (0–255) at each threshold

HYST=6                 # ramp-down hysteresis in °C
POLL_SEC=2

# Optional: separate GPU curve (defaults to CPU curve if omitted)
GPU_CT=(45 55 65 75 85)
GPU_CP=(0  40 100 180 255)

FOLLOW_PLATFORM_PROFILE=0  # set to 1 to auto-track power profile
RPM_STALL_WARN=1           # warn in journal if fan stalls at high PWM
```

The daemon uses `max(cpu_pwm, gpu_pwm)` each cycle — whichever sensor is hotter drives the fans. Points are linearly interpolated. Ramp-up is immediate; ramp-down waits until temp drops `HYST` degrees below the last ramp-up point.

If `inotify-tools` is installed, the conf reloads automatically on save — no restart needed.

Test changes without writing to hardware:

```sh
sudo hpfand --dry-run
```

---

<details>
<summary><h2>Getting the module</h2></summary>

The `pwm1` hwmon interface is in the in-tree `hp_wmi` driver. The required fixes landed in **Linux 7.1** ([Phoronix](https://www.phoronix.com/news/Linux-7.1-x86-Platform-Drivers), [kernel.org](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=da6b5aae84beb0917ecb0c9fbc71169d145397ff)).

**Linux ≥ 7.1:** already supported — run the check at the top to confirm.

**Older kernels:** use `build-module.sh` to build and load the patched driver automatically.

### Requirements

Before running the script, install kernel headers for your running kernel:

| Distro | Command |
|--------|---------|
| Arch / Manjaro | `sudo pacman -S linux-headers` |
| Ubuntu / Debian | `sudo apt install linux-headers-$(uname -r)` |
| Fedora | `sudo dnf install kernel-devel` |

Also make sure `git` and `make` are installed (`base-devel` / `build-essential` cover both).

### Build and load

```sh
sudo ./build-module.sh
```

This sparse-clones only the driver file from the patched branch, builds the module, loads it, and installs it so it survives reboots (until the next kernel update). Then run `sudo ./install.sh` as usual.

> The module only persists for the current kernel version. After a kernel update, run `build-module.sh` again — or upgrade to Linux 7.1.

<details>
<summary>Manual steps (if the script doesn't work)</summary>

```sh
git clone https://github.com/emomaxd/linux -b hp-wmi-fixes --depth=1
cd linux
mkdir /tmp/hp-wmi-build
cp drivers/platform/x86/hp/hp-wmi.c /tmp/hp-wmi-build/
echo 'obj-m += hp-wmi.o' > /tmp/hp-wmi-build/Makefile
make -C /lib/modules/$(uname -r)/build M=/tmp/hp-wmi-build modules
sudo rmmod hp_wmi
sudo insmod /tmp/hp-wmi-build/hp-wmi.ko
# persist until next kernel update:
sudo cp /tmp/hp-wmi-build/hp-wmi.ko /lib/modules/$(uname -r)/updates/hp-wmi.ko
sudo depmod -a
```

</details>

Patches included in the fixes branch:

- `platform/x86: hp-wmi: fix ignored return values in fan settings`
- `platform/x86: hp-wmi: avoid cancel_delayed_work_sync from work handler`
- `platform/x86: hp-wmi: use mod_delayed_work to reset keep-alive timer`
- `platform/x86: hp-wmi: fix u8 underflow in gpu_delta calculation`
- `platform/x86: hp-wmi: add locking for concurrent hwmon access`

</details>

---

## AUR packages

For Arch-based distros, AUR packages are available:

| Package | Description |
|---------|-------------|
| [`hpfand`](https://aur.archlinux.org/packages/hpfand) | daemon + CLI |
| [`hp-wmi-dkms`](https://aur.archlinux.org/packages/hp-wmi-dkms) | patched module, auto-rebuilt on kernel updates (pre-7.1 only) |

```sh
yay -S hpfand          # Linux >= 7.1
yay -S hpfand hp-wmi-dkms  # older kernels
```

---

## Troubleshooting

**Daemon not starting — `hp-wmi hwmon not found`**

The kernel module isn't loaded. Check:
```sh
lsmod | grep hp_wmi
ls /sys/devices/platform/hp-wmi/hwmon/
```
If empty, see [Getting the module](#getting-the-module).

---

**Fan speed doesn't change**

Check that the daemon is running in manual mode:
```sh
hpf status       # mode should say "manual (daemon active)"
hpf log 20       # look for errors
```
If mode is `auto`, the daemon failed to set `pwm1_enable`. Check journal with `hpf log`.

---

**`build-module.sh` fails at `make`**

Kernel headers are missing. Install them for your current kernel:
```sh
# Arch:
pacman -S linux-headers

# Ubuntu/Debian:
apt install linux-headers-$(uname -r)
```
Then re-run `sudo ./build-module.sh`.

---

**Module loaded but fans still behave wrong after kernel update**

The module only persists for the kernel version it was built for. After a kernel update, rebuild:
```sh
sudo ./build-module.sh
```
Or use `hp-wmi-dkms` (AUR) to handle this automatically.

---

**GPU temperature not shown in `hpf status`**

Normal — the dGPU is off (D3cold). It will appear automatically once the GPU becomes active (e.g. when a game starts).

---

## Uninstall

```sh
sudo ./uninstall.sh
```
