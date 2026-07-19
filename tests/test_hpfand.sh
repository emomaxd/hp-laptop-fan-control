#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/hpfand"

failures=0
check() {
    local expected=$1 actual=$2 label=$3
    if [[ "$actual" != "$expected" ]]; then
        echo "not ok - $label (expected=$expected actual=$actual)" >&2
        failures=$(( failures + 1 ))
    else
        echo "ok - $label"
    fi
}

check_contains() {
    local pattern=$1 file=$2 label=$3
    if grep -q -- "$pattern" "$file"; then
        echo "ok - $label"
    else
        echo "not ok - $label (missing: $pattern)" >&2
        failures=$(( failures + 1 ))
    fi
}

check_fails() {
    local label=$1
    shift
    if ( "$@" ) > /dev/null 2>&1; then
        echo "not ok - $label (unexpected success)" >&2
        failures=$(( failures + 1 ))
    else
        echo "ok - $label"
    fi
}

set_defaults
check 1 "$FOLLOW_PLATFORM_PROFILE" "clean install follows the platform profile by default"
check '0 30 80 170 255' "${CP[*]}" "missing platform profile falls back to balanced defaults"

CT=(40000 50000 60000); CP=(10 100 220)
check 10 "$(pwm_for_temp CT CP 30000)" "lower endpoint honors CP"
check 220 "$(pwm_for_temp CT CP 70000)" "upper endpoint honors CP"
check 55 "$(pwm_for_temp CT CP 45000)" "curve interpolation"

SLEW_UP=100; SLEW_DOWN=20
check 200 "$(next_pwm 30 200 1)" "startup blocks sudden PWM decrease"
check 180 "$(next_pwm 30 200 0)" "normal decrease observes SLEW_DOWN"
check 150 "$(next_pwm 250 50 0)" "increase observes SLEW_UP"

desired_pwm=180; last_up_temp=70000; HYST_MC=6000
update_desired_pwm 80 65000
check 180 "$desired_pwm" "hysteresis blocks an early decrease"
update_desired_pwm 80 64000
check 80 "$desired_pwm" "hysteresis allows a cooled decrease"
update_desired_pwm 220 68000
check 220 "$desired_pwm" "increases bypass hysteresis"
check 68000 "$last_up_temp" "increase records its effective temperature"

SILENT_OFF_BELOW=0
profile_to_curves performance
check 30 "${CP[0]}" "platform profile updates the active curve"
check 1 "$POLL_SEC" "platform profile updates polling interval"
profile_to_curves low-power
check '0 20 60 150 255' "${CP[*]}" "low-power profile selects the silent curve"
profile_to_curves balanced
check '0 30 80 170 255' "${CP[*]}" "balanced profile selects the default curve"
curve_before_unknown=${CP[*]}
profile_to_curves unsupported
check "$curve_before_unknown" "${CP[*]}" "unknown platform profile preserves the active curve"
check 70000 "$(control_temp 70000 50000)" "raw temperature wins immediately while rising"
check 70000 "$(control_temp 50000 70000)" "EMA smooths temperature decreases"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CONF="$TMP/hpfand.conf"
printf '%s\n' 'CT=(030 050 080)' 'CP=(0 100 255)' 'SLEW_DOWN=015' 'EMERGENCY_TEMP=100' > "$CONF"
set_defaults
parse_conf
check 15 "$SLEW_DOWN" "allowlisted config scalar"
check 100 "$EMERGENCY_TEMP" "allowlisted emergency threshold"
check '30 50 80' "${CT[*]}" "allowlisted config array"

printf '%s\n' 'CT=(30 50)' 'CP=(0 255)' "EVIL=\$(id)" > "$CONF"
set_defaults
if parse_conf 2>/dev/null; then
    echo "not ok - rejects executable config" >&2
    failures=$(( failures + 1 ))
else
    echo "ok - rejects executable config"
fi

conf_safe() { return 0; }
printf '%s\n' 'CT=(40 50 60)' 'CP=(0 100 255)' 'EMERGENCY_TEMP=95' > "$CONF"
CONFIG_LOADED=0
load_conf
good_curve=${CT[*]}
printf '%s\n' 'CT=(40 50)' 'CP=(0 255)' 'EMERGENCY_TEMP=110' > "$CONF"
if load_conf 2> "$TMP/reload.log"; then
    echo "not ok - invalid reload returns an error" >&2
    failures=$(( failures + 1 ))
else
    echo "ok - invalid reload returns an error"
fi
check "$good_curve" "${CT[*]}" "invalid reload preserves last-known-good curve"
check_contains 'keeping last-known-good' "$TMP/reload.log" "invalid reload decision is logged"

printf '%s\n' 'CT=(40 50 60)' 'CP=(0 100 255)' 'EMERGENCY_TEMP=95' > "$CONF"
check_config > "$TMP/check.log"
check_contains 'configuration valid' "$TMP/check.log" "explicit config validation accepts a safe file"
printf '%s\n' 'CT=(40 50)' 'CP=(255 0)' > "$CONF"
if check_config > /dev/null 2> "$TMP/check-invalid.log"; then
    echo "not ok - explicit config validation rejects an unsafe curve" >&2
    failures=$(( failures + 1 ))
else
    echo "ok - explicit config validation rejects an unsafe curve"
fi

printf '%s\n' 'CT=(40 50 60)' 'CP=(0 255)' > "$CONF"
check_fails "rejects mismatched CPU curve lengths" check_config
printf '%s\n' 'CT=(40 40 60)' 'CP=(0 100 255)' > "$CONF"
check_fails "rejects non-increasing CPU temperatures" check_config
printf '%s\n' 'CT=(40 50 60)' 'CP=(0 200 100)' > "$CONF"
check_fails "rejects decreasing CPU PWM points" check_config
printf '%s\n' 'CT=(40 50 60)' 'CP=(0 100 256)' > "$CONF"
check_fails "rejects CPU PWM above 255" check_config
printf '%s\n' 'CT=(40 50)' 'CP=(0 255)' 'POLL_SEC=0' > "$CONF"
check_fails "rejects zero poll interval" check_config
printf '%s\n' 'CT=(40 50)' 'CP=(0 255)' 'FOLLOW_PLATFORM_PROFILE=2' > "$CONF"
check_fails "rejects invalid follow flag" check_config
printf '%s\n' 'CT=(40 50)' 'CP=(0 255)' 'EMERGENCY_TEMP=69' > "$CONF"
check_fails "rejects unsafe emergency threshold" check_config
printf '%s\n' 'CT=(40 50)' 'CP=(0 255)' 'GPU_CP=(0 255)' > "$CONF"
check_fails "rejects GPU PWM curve without temperatures" check_config

set_defaults
GPU_CT=(45 65 85); GPU_CP=(20 140 255)
normalize_conf
custom_gpu_curve=${GPU_CT[*]}
check 50000 "$SILENT_OFF_BELOW_MC" "default silent cutoff uses the second curve point"
profile_to_curves performance
check "$custom_gpu_curve" "${GPU_CT[*]}" "profile changes preserve a custom GPU curve"

SYSFS_ROOT="$TMP/sys"
HP="$SYSFS_ROOT/class/hwmon/hwmon0"
CPU="$SYSFS_ROOT/class/hwmon/hwmon1"
GPU1="$SYSFS_ROOT/class/hwmon/hwmon2"
GPU2="$SYSFS_ROOT/class/hwmon/hwmon3"
mkdir -p "$HP" "$CPU" "$GPU1" "$GPU2"
printf 'hp\n' > "$HP/name"
printf '10\n' > "$HP/pwm1"
printf '2\n' > "$HP/pwm1_enable"
printf '1200\n' > "$HP/fan1_input"
printf '1300\n' > "$HP/fan2_input"
printf 'k10temp\n' > "$CPU/name"
printf '50000\n' > "$CPU/temp1_input"
printf 'amdgpu\n' > "$GPU1/name"
printf '55000\n' > "$GPU1/temp1_input"
printf '72000\n' > "$GPU1/temp2_input"
printf 'nvidia\n' > "$GPU2/name"
printf '68000\n' > "$GPU2/temp1_input"

mapfile -t gpu_paths < <(find_gpu_temps)
check 72000 "$(read_max_temp "${gpu_paths[@]}")" "hottest sensor across all GPUs wins"
HP_HWMON="$HP"
mapfile -t fan_paths < <(find_fan_inputs)
check 2 "${#fan_paths[@]}" "all fan tachometers discovered"

printf 'invalid\n' > "$GPU1/temp1_input"
printf '160000\n' > "$GPU1/temp2_input"
check 68000 "$(read_max_temp "${gpu_paths[@]}")" "invalid GPU temperatures are ignored"
printf '55000\n' > "$GPU1/temp1_input"
printf '72000\n' > "$GPU1/temp2_input"

DISCOVERY_ROOT="$TMP/discovery"
mkdir -p "$DISCOVERY_ROOT/class/hwmon/hwmon0" "$DISCOVERY_ROOT/class/hwmon/hwmon1"
printf 'hp\n' > "$DISCOVERY_ROOT/class/hwmon/hwmon0/name"
printf 'hp\n' > "$DISCOVERY_ROOT/class/hwmon/hwmon1/name"
touch "$DISCOVERY_ROOT/class/hwmon/hwmon1/pwm1" "$DISCOVERY_ROOT/class/hwmon/hwmon1/pwm1_enable"
old_sysfs_root=$SYSFS_ROOT
SYSFS_ROOT=$DISCOVERY_ROOT
check "$DISCOVERY_ROOT/class/hwmon/hwmon1" "$(find_hwmon)" "hwmon discovery skips incomplete hp interfaces"
rm -f "$DISCOVERY_ROOT/class/hwmon/hwmon1/pwm1_enable"
check '' "$(find_hwmon)" "hwmon discovery rejects missing PWM controls"

INTEL="$DISCOVERY_ROOT/devices/platform/coretemp.0/hwmon/hwmon2"
mkdir -p "$INTEL"
printf 'Core 0\n' > "$INTEL/temp1_label"
printf '45000\n' > "$INTEL/temp1_input"
printf 'Package id 0\n' > "$INTEL/temp2_label"
printf '52000\n' > "$INTEL/temp2_input"
check "$INTEL/temp2_input" "$(find_cpu_temp)" "Intel discovery prefers package temperature"
rm -rf "$DISCOVERY_ROOT/devices"
mkdir -p "$DISCOVERY_ROOT/class/hwmon/hwmon2"
printf 'k10temp\n' > "$DISCOVERY_ROOT/class/hwmon/hwmon2/name"
printf 'Tctl\n' > "$DISCOVERY_ROOT/class/hwmon/hwmon2/temp1_label"
printf '60000\n' > "$DISCOVERY_ROOT/class/hwmon/hwmon2/temp1_input"
printf 'Tdie\n' > "$DISCOVERY_ROOT/class/hwmon/hwmon2/temp2_label"
printf '50000\n' > "$DISCOVERY_ROOT/class/hwmon/hwmon2/temp2_input"
check "$DISCOVERY_ROOT/class/hwmon/hwmon2/temp2_input" "$(find_cpu_temp)" "AMD discovery prefers Tdie temperature"

EMPTY_SYSFS="$TMP/empty-sysfs"
mkdir -p "$EMPTY_SYSFS/class/hwmon"
if CONF="$TMP/missing.conf" SYSFS_ROOT="$EMPTY_SYSFS" LOCK_FILE="$TMP/no-hwmon.lock" \
    "$ROOT/hpfand" --dry-run > /dev/null 2> "$TMP/no-hwmon.log"; then
    echo "not ok - daemon rejects systems without hp-wmi (unexpected success)" >&2
    failures=$(( failures + 1 ))
else
    echo "ok - daemon rejects systems without hp-wmi"
fi
check_contains 'hp-wmi hwmon not found' "$TMP/no-hwmon.log" "missing hp-wmi error is actionable"

rm -rf "$DISCOVERY_ROOT/class/hwmon/hwmon2"
touch "$DISCOVERY_ROOT/class/hwmon/hwmon1/pwm1_enable"
if CONF="$TMP/missing.conf" SYSFS_ROOT="$DISCOVERY_ROOT" LOCK_FILE="$TMP/no-cpu.lock" \
    "$ROOT/hpfand" --dry-run > /dev/null 2> "$TMP/no-cpu.log"; then
    echo "not ok - daemon rejects systems without a CPU sensor (unexpected success)" >&2
    failures=$(( failures + 1 ))
else
    echo "ok - daemon rejects systems without a CPU sensor"
fi
check_contains 'cpu temp sensor not found' "$TMP/no-cpu.log" "missing CPU sensor error is actionable"
SYSFS_ROOT=$old_sysfs_root

DRY_RUN=0
chmod 0400 "$HP/pwm1"
if apply 90 50000 0 2>/dev/null; then
    echo "not ok - failed daemon PWM write returns an error" >&2
    failures=$(( failures + 1 ))
else
    echo "ok - failed daemon PWM write returns an error"
fi
chmod 0600 "$HP/pwm1"
apply 90 50000 0
check 90 "$(<"$HP/pwm1")" "daemon PWM write succeeds on retry"
check 90 "$APPLIED_PWM" "daemon records the applied PWM value"

if pwm_readback_valid 154 149; then
    echo "ok - hardware PWM quantization is accepted"
else
    echo "not ok - hardware PWM quantization is accepted" >&2
    failures=$(( failures + 1 ))
fi
if pwm_readback_valid 154 100; then
    echo "not ok - large PWM readback mismatch is rejected" >&2
    failures=$(( failures + 1 ))
else
    echo "ok - large PWM readback mismatch is rejected"
fi
check_fails "non-numeric PWM readback is rejected" pwm_readback_valid 100 invalid
check_fails "out-of-range PWM readback is rejected" pwm_readback_valid 255 256

DRY_RUN=1
printf '33\n' > "$HP/pwm1"
apply 177 50000 0
check 33 "$(<"$HP/pwm1")" "dry-run does not write PWM hardware"
check 177 "$APPLIED_PWM" "dry-run records simulated PWM"
DRY_RUN=0

run_daemon() {
    local loops=$1 log=$2
    CONF="$TMP/missing.conf" SYSFS_ROOT="$SYSFS_ROOT" HPFAND_TEST_LOOPS="$loops" \
        HPFAND_TEST_NO_SLEEP=1 LOCK_FILE="$TMP/daemon.lock" "$ROOT/hpfand" 2> "$log"
}

run_daemon_realtime() {
    local loops=$1 log=$2 lock=$3
    CONF="$TMP/missing.conf" SYSFS_ROOT="$SYSFS_ROOT" HPFAND_TEST_LOOPS="$loops" \
        LOCK_FILE="$lock" "$ROOT/hpfand" 2> "$log"
}

wait_for_log() {
    local pattern=$1 log=$2 pid=$3
    local i
    for (( i=0; i<500; i++ )); do
        grep -q "$pattern" "$log" 2>/dev/null && return 0
        kill -0 "$pid" 2>/dev/null || return 1
        sleep 0.02
    done
    return 1
}

exec {held_lock}> "$TMP/held.lock"
flock "$held_lock"
if (DRY_RUN=0; LOCK_FILE="$TMP/held.lock"; acquire_lock) 2> "$TMP/lock.log"; then
    echo "not ok - singleton lock rejects a second daemon" >&2
    failures=$(( failures + 1 ))
else
    echo "ok - singleton lock rejects a second daemon"
fi
flock -u "$held_lock"
check_contains 'already running' "$TMP/lock.log" "singleton lock failure is actionable"

printf '%s\n' '#!/bin/sh' "printf '%s\\n' \"\$*\" >> \"\$WATCHDOG_LOG\"" > "$TMP/systemd-notify"
chmod +x "$TMP/systemd-notify"
WATCHDOG_LOG="$TMP/watchdog.log"
export WATCHDOG_LOG
PATH="$TMP:$PATH" NOTIFY_SOCKET=test notify_systemd --ready
PATH="$TMP:$PATH" NOTIFY_SOCKET=test notify_systemd WATCHDOG=1
check_contains '^--ready$' "$WATCHDOG_LOG" "daemon announces readiness to systemd"
check_contains '^WATCHDOG=1$' "$WATCHDOG_LOG" "daemon emits watchdog heartbeat"

printf '100000\n' > "$CPU/temp1_input"
printf '10\n' > "$HP/pwm1"
run_daemon 1 "$TMP/emergency.log"
check 255 "$(<"$HP/pwm1")" "raw CPU emergency bypasses smoothing and slew"
check 2 "$(<"$HP/pwm1_enable")" "clean exit returns control to firmware"
check_contains 'emergency CPU temperature' "$TMP/emergency.log" "CPU emergency is logged"

printf '50000\n' > "$CPU/temp1_input"
printf '101000\n' > "$GPU2/temp1_input"
printf '10\n' > "$HP/pwm1"
run_daemon 1 "$TMP/gpu-emergency.log"
check 255 "$(<"$HP/pwm1")" "raw GPU emergency bypasses smoothing and slew"
check_contains 'emergency GPU temperature' "$TMP/gpu-emergency.log" "GPU emergency is logged"

mkdir -p "$SYSFS_ROOT/firmware/acpi"
printf 'performance\n' > "$SYSFS_ROOT/firmware/acpi/platform_profile"
printf '50000\n' > "$CPU/temp1_input"
printf '50000\n' > "$GPU2/temp1_input"
run_daemon_realtime 2 "$TMP/emergency-recovery.log" "$TMP/emergency-recovery.lock" &
recovery_pid=$!
wait_for_log 'info: started' "$TMP/emergency-recovery.log" "$recovery_pid"
printf '100000\n' > "$CPU/temp1_input"
wait_for_log 'emergency CPU temperature' "$TMP/emergency-recovery.log" "$recovery_pid"
printf '50000\n' > "$CPU/temp1_input"
wait "$recovery_pid"
check_contains 'temperatures below emergency threshold' "$TMP/emergency-recovery.log" \
    "daemon resumes its curve after an emergency"

printf '50000\n' > "$CPU/temp1_input"
printf '50000\n' > "$GPU2/temp1_input"
printf '100\n' > "$HP/pwm1"
CONF="$TMP/missing.conf" SYSFS_ROOT="$SYSFS_ROOT" LOCK_FILE="$TMP/signal.lock" \
    "$ROOT/hpfand" 2> "$TMP/signal.log" &
daemon_pid=$!
for (( i=0; i<50; i++ )); do
    grep -q 'info: started' "$TMP/signal.log" && break
    sleep 0.02
done
kill -USR1 "$daemon_pid"
for (( i=0; i<50; i++ )); do
    grep -q 'reloading conf' "$TMP/signal.log" && break
    sleep 0.02
done
kill -TERM "$daemon_pid"
wait "$daemon_pid"
check_contains 'reloading conf' "$TMP/signal.log" "USR1 reload is handled during sleep"
check 2 "$(<"$HP/pwm1_enable")" "SIGTERM performs verified firmware handoff"

printf 'invalid\n' > "$CPU/temp1_input"
printf '50000\n' > "$GPU2/temp1_input"
printf '40\n' > "$HP/pwm1"
run_daemon 3 "$TMP/sensor.log"
check 255 "$(<"$HP/pwm1")" "three CPU sensor failures force full speed"
check_contains 'cpu temp unreadable' "$TMP/sensor.log" "sensor fail-safe is logged"

printf '60000\n' > "$CPU/temp1_input"
printf '50000\n' > "$GPU1/temp1_input"
printf '50000\n' > "$GPU1/temp2_input"
printf '50000\n' > "$GPU2/temp1_input"
printf '100\n' > "$HP/pwm1"
printf '100\n' > "$HP/fan1_input"
printf '150\n' > "$HP/fan2_input"
run_daemon 10 "$TMP/stall.log"
check 255 "$(<"$HP/pwm1")" "fan stall forces full speed"
check_contains 'fan1 may be stalled' "$TMP/stall.log" "fan1 stall is identified"
check_contains 'fan2 may be stalled' "$TMP/stall.log" "fan2 stall is identified"
check 2 "$(grep -c 'may be stalled' "$TMP/stall.log")" "persistent stall warnings are rate-limited"

printf '60000\n' > "$CPU/temp1_input"
printf '100\n' > "$HP/pwm1"
printf '100\n' > "$HP/fan1_input"
printf '150\n' > "$HP/fan2_input"
run_daemon_realtime 7 "$TMP/stall-recovery.log" "$TMP/stall-recovery.lock" &
stall_pid=$!
wait_for_log 'may be stalled' "$TMP/stall-recovery.log" "$stall_pid"
printf '1200\n' > "$HP/fan1_input"
printf '1300\n' > "$HP/fan2_input"
wait "$stall_pid"
check_contains 'fan RPM recovered' "$TMP/stall-recovery.log" "daemon clears a recovered fan stall"
rm -f "$SYSFS_ROOT/firmware/acpi/platform_profile"

DRY_RUN=0
HP_HWMON="$HP"
printf '1\n' > "$HP/pwm1_enable"
set_firmware_control
check 2 "$(<"$HP/pwm1_enable")" "firmware handoff is verified"

source "$ROOT/hpf"
HPFAND_BIN="$ROOT/hpfand"
SYSTEMCTL_LOG="$TMP/systemctl.log"
export SYSTEMCTL_LOG
SYSTEMCTL="$TMP/systemctl"
printf '%s\n' '#!/bin/sh' "printf \"%s\\n\" \"\$*\" >> \"\$SYSTEMCTL_LOG\"" \
    "[ \"\$1\" = is-active ] && exit 0" 'exit 0' > "$SYSTEMCTL"
chmod +x "$SYSTEMCTL"

need_root() { :; }
CONF="$TMP/cli.conf"
SILENT_FLAG="$TMP/state/silent"
mkdir -p "$(dirname "$SILENT_FLAG")"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$TMP/chown"
chmod +x "$TMP/chown"

PATH="$TMP:$PATH" cmd_set balanced > "$TMP/set.log"
check_contains '^# preset: balanced$' "$CONF" "set command writes preset metadata"
check_contains '^FOLLOW_PLATFORM_PROFILE=0$' "$CONF" "set command disables profile following"
check 644 "$(stat -c '%a' "$CONF")" "set command writes a non-executable config"
check_contains '^restart hpfand$' "$SYSTEMCTL_LOG" "set command restarts the daemon"
check_fails "set command rejects unknown presets" cmd_set unknown

rm -f "$SYSFS_ROOT/firmware/acpi/platform_profile"
check_fails "follow command rejects a missing platform profile" cmd_follow
mkdir -p "$SYSFS_ROOT/firmware/acpi"
printf 'performance\n' > "$SYSFS_ROOT/firmware/acpi/platform_profile"
PATH="$TMP:$PATH" cmd_follow > "$TMP/follow.log"
check_contains '^FOLLOW_PLATFORM_PROFILE=1$' "$CONF" "follow command enables profile tracking"
check_contains 'performance' "$TMP/follow.log" "follow command reports the active profile"

check_fails "log command rejects zero lines" cmd_log 0
check_fails "log command rejects non-numeric lines" cmd_log many
check_fails "PWM command rejects values above 255" cmd_pwm 256
check_fails "PWM command rejects non-numeric values" cmd_pwm fast

cmd_toggle > /dev/null
check 1 "$([[ -f "$SILENT_FLAG" ]] && echo 1 || echo 0)" "toggle command enables persistent silent mode"
cmd_toggle > /dev/null
check 0 "$([[ -f "$SILENT_FLAG" ]] && echo 1 || echo 0)" "toggle command disables persistent silent mode"

printf '2\n' > "$HP/pwm1_enable"
printf '50\n' > "$HP/pwm1"
lock_pwm "$HP" 140
check 1 "$(<"$HP/pwm1_enable")" "fixed PWM enables manual control"
check 140 "$(<"$HP/pwm1")" "fixed PWM write is verified"

printf '2\n' > "$HP/pwm1_enable"
printf '50\n' > "$HP/pwm1"
chmod 0400 "$HP/pwm1"
if lock_pwm "$HP" 160 2> "$TMP/rollback.log"; then
    echo "not ok - failed PWM lock returns an error" >&2
    failures=$(( failures + 1 ))
else
    echo "ok - failed PWM lock returns an error"
fi
chmod 0600 "$HP/pwm1"
check 2 "$(<"$HP/pwm1_enable")" "failed PWM lock restores firmware control"
check_contains '^start hpfand$' "$SYSTEMCTL_LOG" "failed PWM lock restarts active daemon"

status_output=$(SYSFS_ROOT="$SYSFS_ROOT" CONF="$TMP/missing.conf" SILENT_FLAG="$TMP/silent" print_status)
check_contains '^fan1:' <(printf '%s\n' "$status_output") "status lists fan1 dynamically"
check_contains '^fan2:' <(printf '%s\n' "$status_output") "status lists fan2 dynamically"

(( failures == 0 ))
