#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"

[[ $EUID -eq 0 ]] || { echo "error: run as root"; exit 1; }

install -Dm755 "$SCRIPT_DIR/hp-fan-control" "$PREFIX/bin/hp-fan-control"
install -Dm755 "$SCRIPT_DIR/hp-fan-curve"   "$PREFIX/bin/hp-fan-curve"

systemctl restart hp-fan-control
echo "updated to $(git -C "$SCRIPT_DIR" describe --tags 2>/dev/null || git -C "$SCRIPT_DIR" rev-parse --short HEAD)"
