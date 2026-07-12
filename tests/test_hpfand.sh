#!/bin/bash
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

CT=(40000 50000 60000); CP=(10 100 220)
check 10 "$(pwm_for_temp CT CP 30000)" "lower endpoint honors CP"
check 220 "$(pwm_for_temp CT CP 70000)" "upper endpoint honors CP"
check 55 "$(pwm_for_temp CT CP 45000)" "curve interpolation"

SLEW_UP=100; SLEW_DOWN=20
check 200 "$(next_pwm 30 200 1)" "startup blocks sudden PWM decrease"
check 180 "$(next_pwm 30 200 0)" "normal decrease observes SLEW_DOWN"
check 150 "$(next_pwm 250 50 0)" "increase observes SLEW_UP"

CONF=$(mktemp)
trap 'rm -f "$CONF"' EXIT
printf '%s\n' 'CT=(030 050 080)' 'CP=(0 100 255)' 'SLEW_DOWN=015' > "$CONF"
set_defaults
parse_conf
check 15 "$SLEW_DOWN" "allowlisted config scalar"
check '30 50 80' "${CT[*]}" "allowlisted config array"

HP_HWMON=$(mktemp -d)
chmod 500 "$HP_HWMON"
if apply 100 0 0 2>/dev/null; then
    echo "not ok - reports failed PWM write" >&2
    failures=$(( failures + 1 ))
else
    echo "ok - reports failed PWM write"
fi
chmod 700 "$HP_HWMON"
rmdir "$HP_HWMON"

printf '%s\n' 'CT=(30 50)' 'CP=(0 255)' 'EVIL=$(id)' > "$CONF"
set_defaults
if parse_conf 2>/dev/null; then
    echo "not ok - rejects executable config" >&2
    failures=$(( failures + 1 ))
else
    echo "ok - rejects executable config"
fi

(( failures == 0 ))
