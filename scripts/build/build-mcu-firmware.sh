#!/bin/sh
# Build and stage the Ender-3 V3 KE printer-MCU firmware.
#
# The source repository is deliberately thin: it fetches the exact upstream
# Klipper revision it owns, applies its explicit GD32F303 patch queue, builds
# twice, packs the raw image into Creality's format, and validates the result.
# This stage then copies only the resulting artifacts and the repository's
# safety-gated tools into the rootfs overlay. No MCU write is ever performed
# by the build.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
MANIFEST="$REPO_ROOT/manifests/dependencies.conf"
. "$MANIFEST"

VENDOR="$REPO_ROOT/vendor"
MCU_REPO_DIR="$VENDOR/nebulaos-klipper-mcu"
BUILDROOT_DIR="$VENDOR/system/buildroot"
OVERLAY="$BUILDROOT_DIR/board/halley5-nebulaos-overlay"
WORK="$REPO_ROOT/build-work/nebulaos-klipper-mcu"
MCU_BUILD="$WORK/klipper-src"
ARTIFACT_REL="artifacts/nebulaos-firmware"
GENERATED_ARTIFACTS="$MCU_REPO_DIR/$ARTIFACT_REL"
MCU_CACHE="$WORK/cache"
MCU_CACHE_FINGERPRINT="$MCU_CACHE/fingerprint"
TOOLCHAIN_ROOT="$WORK/arm-gnu-toolchain"
TOOLCHAIN_CACHE="$REPO_ROOT/vendor-downloads"

[ -d "$MCU_REPO_DIR/.git" ] || {
	echo "FATAL: vendor/nebulaos-klipper-mcu is missing - run 00-fetch-vendor-sources.sh first" >&2
	exit 1
}
[ "$(git -C "$MCU_REPO_DIR" rev-parse HEAD)" = "$MCU_PIN" ] || {
	echo "FATAL: vendor/nebulaos-klipper-mcu is not at pinned commit $MCU_PIN" >&2
	exit 1
}

mkdir -p "$WORK" "$TOOLCHAIN_CACHE"
TOOLCHAIN_BIN=$(TOOLCHAIN_CACHE_DIR="$TOOLCHAIN_CACHE" \
	"$MCU_REPO_DIR/scripts/install-toolchain.sh" "$TOOLCHAIN_ROOT")
export PATH="$TOOLCHAIN_BIN:$PATH"

MCU_UPSTREAM_SHA=$(sed -n 's/^KLIPPER_SHA=//p' "$MCU_REPO_DIR/upstream.lock")
[ -n "$MCU_UPSTREAM_SHA" ] || {
	echo "FATAL: vendor MCU upstream.lock does not define KLIPPER_SHA" >&2
	exit 1
}

# The vendor repository is pinned, but keep the build inputs explicit so a
# build-script, patch, toolchain, or packaging-policy change cannot reuse an
# old firmware image accidentally.
MCU_FINGERPRINT=$(
	{
		echo "mcu_pin=$MCU_PIN"
		echo "upstream_klipper_sha=$MCU_UPSTREAM_SHA"
		echo "metadata_version=$MCU_METADATA_VERSION"
		echo "expected_hw_id=$MCU_EXPECTED_HW_ID"
	sha256sum "$SCRIPT_DIR/build-mcu-firmware.sh" "$MCU_REPO_DIR/upstream.lock" \
		"$MCU_REPO_DIR/configs/ender3-v3-ke.defconfig" \
		"$MCU_REPO_DIR/patches/series"
	find "$MCU_REPO_DIR/scripts" "$MCU_REPO_DIR/patches" -type f -print | sort |
		while IFS= read -r file; do sha256sum "$file"; done
	sha256sum "$TOOLCHAIN_BIN/arm-none-eabi-gcc"
	} | sha256sum | awk '{print $1}'
)

ARTIFACTS="$GENERATED_ARTIFACTS"
MCU_REBUILD=1
if [ -f "$MCU_CACHE_FINGERPRINT" ] && [ "$(cat "$MCU_CACHE_FINGERPRINT")" = "$MCU_FINGERPRINT" ] \
	&& [ -s "$MCU_CACHE/klipper.bin" ] \
	&& [ -s "$MCU_CACHE/klipper-creality.bin" ] \
	&& [ -s "$MCU_CACHE/klipper.elf" ] \
	&& [ -s "$MCU_CACHE/klipper.config" ] \
	&& [ -s "$MCU_CACHE/validator-report.txt" ]; then
	ARTIFACTS="$MCU_CACHE"
	MCU_REBUILD=0
	echo "== reusing printer MCU firmware from matching build cache =="
fi

if [ "$MCU_REBUILD" -eq 1 ]; then
	rm -rf "$MCU_BUILD" "$GENERATED_ARTIFACTS"
	mkdir -p "$GENERATED_ARTIFACTS/pass1" "$GENERATED_ARTIFACTS/pass2"

	echo "== fetching pinned upstream Klipper for printer MCU =="
	"$MCU_REPO_DIR/scripts/fetch-upstream.sh" "$MCU_BUILD"
	echo "== applying pinned printer MCU patch queue =="
	"$MCU_REPO_DIR/scripts/apply-patches.sh" "$MCU_BUILD"

	echo "== building printer MCU candidate twice =="
	"$MCU_REPO_DIR/scripts/build.sh" "$MCU_BUILD" "$ARTIFACT_REL/pass1"
	"$MCU_REPO_DIR/scripts/build.sh" "$MCU_BUILD" "$ARTIFACT_REL/pass2"
	cmp -s "$GENERATED_ARTIFACTS/pass1/klipper.bin" "$GENERATED_ARTIFACTS/pass2/klipper.bin" || {
		echo "FATAL: printer MCU raw klipper.bin is not reproducible across two builds" >&2
		exit 1
	}

	cp "$GENERATED_ARTIFACTS/pass2/klipper.bin" "$GENERATED_ARTIFACTS/klipper.bin"
	cp "$GENERATED_ARTIFACTS/pass2/klipper-creality.bin" "$GENERATED_ARTIFACTS/klipper-creality.bin"
	cp "$GENERATED_ARTIFACTS/pass2/klipper.elf" "$GENERATED_ARTIFACTS/klipper.elf"
	cp "$GENERATED_ARTIFACTS/pass2/klipper.config" "$GENERATED_ARTIFACTS/klipper.config"
fi

echo "== validating packaged printer MCU candidate =="
python3 "$MCU_REPO_DIR/tools/creality_validator.py" target \
	"$ARTIFACTS/klipper-creality.bin" \
	"$ARTIFACTS/klipper.elf" \
	"$ARTIFACTS/klipper.config" \
	> "$ARTIFACTS/validator-report.txt.tmp"
mv "$ARTIFACTS/validator-report.txt.tmp" "$ARTIFACTS/validator-report.txt"
cat "$ARTIFACTS/validator-report.txt"

# build.sh currently owns the packer's metadata version. Assert that the
# generated image agrees with the top-level manifest rather than merely
# recording a value that could drift from the actual bytes.
INSPECTED_VERSION=$(python3 "$MCU_REPO_DIR/tools/creality_flash.py" inspect \
	"$ARTIFACTS/klipper-creality.bin" |
	sed -n "s/^type=b'mcu0' version=b'\\([0-9][0-9][0-9]\\)'.*/\\1/p")
[ "$INSPECTED_VERSION" = "$MCU_METADATA_VERSION" ] || {
	echo "FATAL: packaged MCU metadata version is '$INSPECTED_VERSION', expected '$MCU_METADATA_VERSION'" >&2
	exit 1
}

# Keep the runtime identity gate coupled to the configured hardware target.
# The upstream flasher has an exact default allow-list; fail the build if a
# future pinned repository changes that default without a manifest review.
python3 - "$MCU_REPO_DIR/tools/creality_flash.py" "$MCU_EXPECTED_HW_ID" <<'PY'
import re
import sys

source = open(sys.argv[1], encoding="utf-8").read()
expected = sys.argv[2]
match = re.search(r'DEFAULT_ALLOWED_HW_IDS\s*=\s*\(([^)]*)\)', source)
if not match or re.findall(r'"([^"]+)"', match.group(1)) != [expected]:
    raise SystemExit("FATAL: upstream flasher default hardware allow-list does not match MCU_EXPECTED_HW_ID")
PY

if [ "$MCU_REBUILD" -eq 1 ]; then
	rm -rf "$MCU_CACHE"
	mkdir -p "$MCU_CACHE"
	for artifact in klipper.bin klipper-creality.bin klipper.elf klipper.config validator-report.txt; do
		cp "$GENERATED_ARTIFACTS/$artifact" "$MCU_CACHE/$artifact"
	done
	printf '%s\n' "$MCU_FINGERPRINT" > "$MCU_CACHE_FINGERPRINT"
fi

MCU_DEST="$OVERLAY/opt/nebulaos/mcu"
rm -rf "$MCU_DEST"
mkdir -p "$MCU_DEST/tools"
cp "$ARTIFACTS/klipper-creality.bin" "$MCU_DEST/"
cp "$ARTIFACTS/klipper.bin" "$MCU_DEST/"
cp "$ARTIFACTS/klipper.elf" "$MCU_DEST/"
cp "$ARTIFACTS/klipper.config" "$MCU_DEST/"
cp "$ARTIFACTS/validator-report.txt" "$MCU_DEST/"
for tool in creality_flash.py creality_validator.py creality_packer.py \
	stage4_first_flash.py; do
	cp "$MCU_REPO_DIR/tools/$tool" "$MCU_DEST/tools/$tool"
done
find "$MCU_DEST" -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true

MCU_IMAGE_SHA256=$(sha256sum "$MCU_DEST/klipper-creality.bin" | awk '{print $1}')
MCU_SOURCE_COMMIT=$(git -C "$MCU_REPO_DIR" rev-parse HEAD)
{
	echo "image=klipper-creality.bin"
	echo "image_sha256=$MCU_IMAGE_SHA256"
	echo "metadata_version=$MCU_METADATA_VERSION"
	echo "expected_hw_id=$MCU_EXPECTED_HW_ID"
	echo "repository=$MCU_REPO"
	echo "repository_commit=$MCU_SOURCE_COMMIT"
	echo "upstream_klipper_sha=$MCU_UPSTREAM_SHA"
} > "$MCU_DEST/manifest.env"

echo "== printer MCU artifacts staged at $MCU_DEST (sha256 $MCU_IMAGE_SHA256) =="
