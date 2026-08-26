#!/bin/sh
# Structural/offline checks for the HelixScreen K1 integration.
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
MANIFEST="$REPO_ROOT/manifests/dependencies.conf"
BUILD="$REPO_ROOT/scripts/build/04-cross-compile-app-stack.sh"
SERVICE="$REPO_ROOT/scripts/build/overlay/etc/init.d/S58helixscreen"
VERIFY="$REPO_ROOT/scripts/build/06-verify.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
contains() {
	grep -Fq -- "$2" "$1" && pass || fail "$1 is missing: $2"
}

for script in "$BUILD" "$VERIFY" "$SERVICE"; do
	sh -n "$script" && pass || fail "shell syntax failed: $script"
done

contains "$MANIFEST" 'HELIXSCREEN_REPO=https://github.com/prestonbrown/helixscreen.git'
contains "$MANIFEST" 'HELIXSCREEN_PIN=ca9e5ecf9a7d6418cbf79b68f28bf87dbf14c0ff'
contains "$MANIFEST" 'HELIXSCREEN_TARGET=k1'
contains "$BUILD" 'HELIXSCREEN_CROSS_COMPILE="${HELIXSCREEN_CROSS_COMPILE:-mipsel-buildroot-linux-gnu-}"'
contains "$BUILD" 'HELIXSCREEN_ZLIB_LIB_DIR="${HELIXSCREEN_ZLIB_LIB_DIR:-}"'
contains "$BUILD" "find \"\$BUILDROOT_DIR/output/build\" -type f -path '*/libzlib-*/libz.a'"
contains "$BUILD" 'TARGET_LDFLAGS="$HELIXSCREEN_TARGET_LDFLAGS"'
contains "$BUILD" 'make PLATFORM_TARGET="$HELIXSCREEN_TARGET" CROSS_COMPILE="$HELIXSCREEN_CROSS_COMPILE"'
contains "$BUILD" 'export LD_LIBRARY_PATH="$TOOLCHAIN_HOST/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"'
contains "$BUILD" 'install DESTDIR="$HELIXSCREEN_STAGE"'
contains "$BUILD" 'opt/helixscreen/bin/helix-screen'
contains "$BUILD" 'scripts/helix-launcher.sh'
contains "$SERVICE" 'HELIX_CONFIG_DIR="$CONFIG_DIR"'
contains "$SERVICE" 'HELIX_DISPLAY_BACKEND=fbdev'
contains "$SERVICE" 'MOONRAKER_PORT=7125'
contains "$VERIFY" 'check /opt/helixscreen/bin/helix-screen'
contains "$VERIFY" 'check /etc/init.d/S58helixscreen'

if [ "$FAIL" -eq 0 ]; then
	echo "PASS: $PASS HelixScreen K1 checks"
	exit 0
fi
echo "FAIL: $FAIL of $((PASS + FAIL)) HelixScreen K1 checks"
exit 1
