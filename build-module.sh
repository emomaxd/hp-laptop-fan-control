#!/bin/bash
set -e

[[ $EUID -eq 0 ]] || { echo "error: run as root"; exit 1; }

KVER=$(uname -r)
BUILD_BASE="/lib/modules/$KVER/build"

if [[ ! -d "$BUILD_BASE" ]]; then
    echo "error: kernel headers not found for $KVER"
    echo ""
    echo "Install them first:"
    echo "  Arch / Manjaro:   pacman -S linux-headers"
    echo "  Ubuntu / Debian:  apt install linux-headers-$KVER"
    echo "  Fedora:           dnf install kernel-devel"
    echo ""
    echo "If you use a custom kernel, install the matching headers package."
    exit 1
fi

command -v git  >/dev/null 2>&1 || { echo "error: git not found — install git and retry"; exit 1; }
command -v make >/dev/null 2>&1 || { echo "error: make not found — install make/base-devel and retry"; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "error: sha256sum not found"; exit 1; }

# Keep this in sync with aur/hp-wmi-dkms/PKGBUILD. Refuse to load code if the
# mutable upstream branch no longer contains the reviewed source.
HP_WMI_SHA256=b78469d1ebe5ce82f64a8998f80b1b0480918412c4bf80171e6b7ff78653eb0f

BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "Fetching hp-wmi source (sparse clone, kernel source not downloaded)..."
git clone --depth=1 --filter=blob:none --no-checkout \
    https://github.com/emomaxd/linux -b hp-wmi-victus-fan-v4 \
    "$BUILD_DIR/linux" 2>&1 | grep -v "^$"
cd "$BUILD_DIR/linux"
git sparse-checkout init --cone
git sparse-checkout set drivers/platform/x86/hp
git checkout -q

mkdir "$BUILD_DIR/mod"
cp drivers/platform/x86/hp/hp-wmi.c "$BUILD_DIR/mod/"
echo "$HP_WMI_SHA256  $BUILD_DIR/mod/hp-wmi.c" | sha256sum -c -
printf 'obj-m += hp-wmi.o\n' > "$BUILD_DIR/mod/Makefile"

echo "Building module for $KVER..."
make -C "$BUILD_BASE" M="$BUILD_DIR/mod" modules 2>&1 | tail -3

echo "Loading module..."
rmmod hp_wmi 2>/dev/null || true
insmod "$BUILD_DIR/mod/hp-wmi.ko"

echo "Installing module (persists until next kernel update)..."
install -Dm644 "$BUILD_DIR/mod/hp-wmi.ko" "/lib/modules/$KVER/updates/hp-wmi.ko"
depmod -a

echo ""
echo "Done. Run: sudo ./install.sh"
echo "Note: rebuild after a kernel update — or wait for Linux 7.1 where this is in-tree."
