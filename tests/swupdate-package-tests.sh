#!/bin/sh
#
# Offline tests for OpenKE SWUpdate package generation and configuration.
# Validates sw-description structure, hardware compatibility tags, CPIO member
# order, SHA256 hash correctness, and configuration files (/etc/hwrevision, /etc/swupdate.cfg).
#
# Usage: sh tests/swupdate-package-tests.sh
#

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
PACKAGE_SWU_SCRIPT="$REPO_ROOT/scripts/build/package-swu.sh"
HWREVISION_FILE="$REPO_ROOT/scripts/build/overlay/etc/hwrevision"
SWUPDATE_CFG_FILE="$REPO_ROOT/scripts/build/overlay/etc/swupdate.cfg"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/swupdate-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

PASS=0
FAIL=0
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }

echo "=== Test 1: Config and Identity Files ==="

if [ -f "$HWREVISION_FILE" ]; then
    pass "/etc/hwrevision exists in overlay"
    if grep -q "^nebula-pad[[:space:]]\+1\.0" "$HWREVISION_FILE"; then
        pass "/etc/hwrevision specifies nebula-pad 1.0"
    else
        fail "/etc/hwrevision does not match expected format 'nebula-pad 1.0'"
    fi
else
    fail "/etc/hwrevision missing at $HWREVISION_FILE"
fi

if [ -f "$SWUPDATE_CFG_FILE" ]; then
    pass "/etc/swupdate.cfg exists in overlay"
    if grep -q 'nebula-pad = "1.0"' "$SWUPDATE_CFG_FILE"; then
        pass "/etc/swupdate.cfg matches board identifier"
    else
        fail "/etc/swupdate.cfg missing board identifier"
    fi
else
    fail "/etc/swupdate.cfg missing at $SWUPDATE_CFG_FILE"
fi

echo "=== Test 2: Package Generation with Mock Fixtures ==="

MOCK_KERNEL="$WORK/mock_xImage"
MOCK_ROOTFS="$WORK/mock_rootfs.squashfs"
OUT_DIR="$WORK/out"

echo "MOCK_KERNEL_DATA_12345" > "$MOCK_KERNEL"
echo "MOCK_ROOTFS_DATA_67890" > "$MOCK_ROOTFS"

KERNEL_IMAGE="$MOCK_KERNEL" ROOTFS_IMAGE="$MOCK_ROOTFS" \
    sh "$PACKAGE_SWU_SCRIPT" "$OUT_DIR" "test-1.2.3" > "$WORK/build.log" 2>&1

SWU_FILE="$OUT_DIR/openke-update-test-1.2.3.swu"

if [ -f "$SWU_FILE" ]; then
    pass "package-swu.sh generated $SWU_FILE"
else
    fail "package-swu.sh failed to generate .swu package ($(cat "$WORK/build.log"))"
fi

echo "=== Test 3: CPIO Archive Structure & Member Order ==="

MEMBERS=$(cpio -it < "$SWU_FILE" 2>/dev/null)
FIRST_MEMBER=$(echo "$MEMBERS" | head -n1)

if [ "$FIRST_MEMBER" = "sw-description" ]; then
    pass "sw-description is strictly the first member in CPIO archive"
else
    fail "sw-description is not the first member (found: $FIRST_MEMBER)"
fi

for expected in "sw-description" "xImage" "rootfs.squashfs" "postinstall.sh"; do
    if echo "$MEMBERS" | grep -q "^${expected}$"; then
        pass "CPIO archive contains $expected"
    else
        fail "CPIO archive missing member $expected"
    fi
done

echo "=== Test 4: sw-description Content & Checksums ==="

EXTRACT_DIR="$WORK/extracted"
mkdir -p "$EXTRACT_DIR"
(cd "$EXTRACT_DIR" && cpio -id < "$SWU_FILE" 2>/dev/null)

SW_DESC="$EXTRACT_DIR/sw-description"

if [ -f "$SW_DESC" ]; then
    pass "sw-description extracted successfully"

    if grep -q 'hardware-compatibility:[[:space:]]*\[[[:space:]]*"1\.0"[[:space:]]*\];' "$SW_DESC"; then
        pass "sw-description declares hardware-compatibility 1.0"
    else
        fail "sw-description missing expected hardware-compatibility"
    fi

    if grep -q 'device = "/dev/mmcblk0p6";' "$SW_DESC" && grep -q 'device = "/dev/mmcblk0p8";' "$SW_DESC"; then
        pass "sw-description targets /dev/mmcblk0p6 (kernel2) and /dev/mmcblk0p8 (rootfs2)"
    else
        fail "sw-description target partitions incorrect"
    fi

    EXPECTED_KERNEL_SHA=$(sha256sum "$MOCK_KERNEL" | awk '{print $1}')
    EXPECTED_ROOTFS_SHA=$(sha256sum "$MOCK_ROOTFS" | awk '{print $1}')
    EXPECTED_POSTINSTALL_SHA=$(sha256sum "$EXTRACT_DIR/postinstall.sh" | awk '{print $1}')

    if grep -q "$EXPECTED_KERNEL_SHA" "$SW_DESC"; then
        pass "sw-description contains correct kernel SHA256"
    else
        fail "sw-description kernel SHA256 mismatch"
    fi

    if grep -q "$EXPECTED_ROOTFS_SHA" "$SW_DESC"; then
        pass "sw-description contains correct rootfs SHA256"
    else
        fail "sw-description rootfs SHA256 mismatch"
    fi

    if grep -q "$EXPECTED_POSTINSTALL_SHA" "$SW_DESC"; then
        pass "sw-description contains correct postinstall.sh SHA256"
    else
        fail "sw-description postinstall.sh SHA256 mismatch"
    fi
else
    fail "failed to extract sw-description from .swu archive"
fi

echo "=== Test 5: Post-Install Script Target ==="

if [ -f "$EXTRACT_DIR/postinstall.sh" ]; then
    if grep -q 'write_ota_marker "ota:kernel2"' "$EXTRACT_DIR/postinstall.sh" || \
       grep -q 'ota:kernel2' "$EXTRACT_DIR/postinstall.sh"; then
        pass "postinstall.sh sets next boot target to ota:kernel2"
    else
        fail "postinstall.sh does not set boot marker to ota:kernel2"
    fi
else
    fail "postinstall.sh missing from archive"
fi

echo ""
echo "=========================================="
echo "SWUpdate Tests: $PASS passed, $FAIL failed"
echo "=========================================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
