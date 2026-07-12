# Changelog

## [2.4.0] - 2026-07-12

- Make PWM writes transactional and retry failed sysfs writes.
- Keep fail-safe state synchronized after CPU sensor failures and debounce GPU sensor loss.
- Fix startup down-slew and hysteresis behavior; honor configured curve endpoints.
- Replace root-level config sourcing with a strict numeric parser and full validation.
- Watch the config directory so atomic editor saves reload correctly.
- Restrict silent-mode access to the `hpfand` group and harden the systemd service.
- Verify downloaded hp-wmi source before building/loading the kernel module.
- Add regression tests for curves, slew limiting, and config parsing.
- Fix initial/sysfs reads that incorrectly combined Bash's optimized file read with stderr redirection.
- Ensure reinstalling restarts an already-running daemon.

## [2.0.0] - 2026-05-12

Project renamed from `hp-laptop-fan-control` to `hpfand`. Breaking change for existing installs — run `sudo ./uninstall.sh` then `sudo ./install.sh`.

### Breaking changes
- Daemon binary: `hp-fan-control` → `hpfand`
- CLI: `hp-fan-curve` → `hpf`
- Config: `/etc/hp-fan-control.conf` → `/etc/hpfand.conf`
- State dir: `/var/lib/hp-fan-control/` → `/var/lib/hpfand/`
- Service: `hp-fan-control.service` → `hpfand.service`

### Added
- AUR packages: `hpfand` and `hp-wmi-dkms` (DKMS, auto-rebuilds on kernel update)
- `build-module.sh` — one-command module builder for pre-7.1 kernels; sparse-clones only the driver file
- `CONTRIBUTING.md`, troubleshooting section, `hpf status` example in README

### Fixed
- GPU hwmon re-detected each poll cycle — dGPU powered on after daemon start (Optimus/PRIME) now tracked correctly
- Signal traps (USR1/SIGTERM) fire immediately — sleep is now interruptible

---

## [1.2.0] - 2026-04-17

### Added
- Separate GPU fan curve — `GPU_CT`/`GPU_CP` config vars for an independent GPU curve; daemon uses `max(cpu_pwm, gpu_pwm)` each cycle; defaults to CPU curve if unset
- inotify conf reload — changes to `/etc/hpfand.conf` apply instantly without daemon restart (requires `inotify-tools`; graceful fallback without it)
- `hpf log [N]` — show last N journal entries (default 50)
- Earlier service startup — `After=systemd-modules-load.service`

### Fixed
- Silent mode now persists across reboots — flag moved from `/tmp` to `/var/lib/hpfand/silent`
- Cold start fix — correct PWM applied immediately on startup, no more one-cycle blast at full speed

---

## [1.1.0] - 2026-04-17

### Added
- `update.sh` — in-place script update without full reinstall
- GPU temperature tracking — fan curve driven by `max(cpu_temp, gpu_temp)`
- `--dry-run` mode — prints calculated PWM values without writing to hardware
- `hpf follow` — auto-track system power profile (`low-power` → silent, `balanced` → balanced, `performance` → performance)
- RPM stall warning — logs to journal if fan RPM stays below 200 while PWM is high
- Watch mode — `hpf status -w [N]`
- Per-preset poll interval (silent: 4s, balanced: 2s, performance: 1s)

---

## [1.0.0] - 2026-04-12

- Initial release: daemon, `hpf` CLI, systemd service, install/uninstall scripts
- Config file support (`/etc/hpfand.conf`)
- `hpf` commands: `status`, `set`, `pwm`, `presets`
- Three presets: silent, balanced, performance
- Linear PWM interpolation with configurable hysteresis
