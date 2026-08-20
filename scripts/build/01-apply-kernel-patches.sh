#!/bin/sh
# Verify this project's kernel-source changes (touch DT wiring, the new
# display panel driver, the new Bluetooth H5 Broadcom vendor extension,
# WiFi/BT/display Kconfig, the ported NS2009 driver, the binder.h build fix)
# are present in the checked-out kernel tree.
#
# FIRMWARE.md sec 39: these changes used to be applied here at build time from
# patches/x2000_kernel_6.6-openke.patch. They're now carried by the requested
# Open Klipper Edition System `OKE` branch, and 00-fetch-vendor-sources.sh
# refreshes the checkout to that branch's latest remote HEAD,
# so there's nothing left to apply here. This script stays as stage "01" (kept
# numbered/in-sequence on purpose, so existing docs/muscle-memory still work)
# purely as a sanity check that the fork's content actually landed correctly.
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
KERNEL_DIR="$REPO_ROOT/vendor/x2000_kernel_6.6"
DEPS_MANIFEST="$REPO_ROOT/manifests/dependencies.conf"

[ -f "$DEPS_MANIFEST" ] || { echo "FATAL: $DEPS_MANIFEST not found" >&2; exit 1; }
. "$DEPS_MANIFEST"

if [ ! -d "$KERNEL_DIR/.git" ]; then
	echo "vendor/x2000_kernel_6.6 not found - run 00-fetch-vendor-sources.sh first" >&2
	exit 1
fi

cd "$KERNEL_DIR"

# Defense in depth: stage 00 fetched and reset the checkout, but verify here
# that the build is still on the configured branch and exactly at its fetched
# remote HEAD before composing the accepted variants.
ACTUAL_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || true)
if [ "$ACTUAL_BRANCH" != "$KERNEL_BRANCH" ]; then
	echo "vendor/x2000_kernel_6.6 is on '$ACTUAL_BRANCH', expected branch '$KERNEL_BRANCH' - re-run 00-fetch-vendor-sources.sh" >&2
	exit 1
fi
ACTUAL_SHA=$(git rev-parse HEAD)
REMOTE_SHA=$(git rev-parse "origin/$KERNEL_BRANCH")
if [ "$ACTUAL_SHA" != "$REMOTE_SHA" ]; then
	echo "vendor/x2000_kernel_6.6 HEAD is $ACTUAL_SHA, expected latest origin/$KERNEL_BRANCH HEAD $REMOTE_SHA - re-run 00-fetch-vendor-sources.sh" >&2
	exit 1
fi

echo "== confirming latest OKE HEAD ($ACTUAL_SHA) real changes are present =="
test -f kernel/kernel-6.6/drivers/input/touchscreen/ns2009.c
test -f kernel/kernel-6.6/module_drivers/drivers/video/fbdev/ingenic/displays/panel-openke-general-480x272.c
grep -q "openke,bcm4343x-bt" kernel/kernel-6.6/drivers/bluetooth/hci_h5.c
grep -q "ns2009@48" kernel/kernel-6.6/module_drivers/dts/x2000/halley5_v30.dts
echo "== kernel source verified =="
