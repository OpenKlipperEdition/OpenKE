#!/bin/sh
#
# Builds a self-contained, verified SWUpdate package (.swu) for OpenKE / NebulaOS.
#
# Generates a libconfig-formatted sw-description with SHA256 digests, bundles
# the kernel image (xImage -> /dev/mmcblk0p6), rootfs image (rootfs.squashfs
# -> /dev/mmcblk0p8), and post-install boot-marker script into a compliant CPIO
# archive where sw-description is strictly the first member.
#
# Usage: sh scripts/build/package-swu.sh [output-dir] [version]
#

set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
ARTIFACT_DIR="$REPO_ROOT/artifacts/buildroot-halley5-v30-image"

OUTPUT_DIR="${1:-$ARTIFACT_DIR}"
VERSION="${2:-}"

if [ -z "$VERSION" ]; then
	if [ -f "$ARTIFACT_DIR/build-manifest.txt" ]; then
		VERSION=$(grep -E "^openke_commit=" "$ARTIFACT_DIR/build-manifest.txt" | cut -d= -f2 | cut -c1-8 || true)
	fi
	if [ -z "$VERSION" ]; then
		VERSION=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "1.0.0")
	fi
fi

KERNEL_IMAGE="${KERNEL_IMAGE:-$ARTIFACT_DIR/xImage}"
ROOTFS_IMAGE="${ROOTFS_IMAGE:-$ARTIFACT_DIR/rootfs.squashfs}"

if [ ! -f "$KERNEL_IMAGE" ]; then
	echo "FATAL: kernel image not found at $KERNEL_IMAGE" >&2
	exit 1
fi

if [ ! -f "$ROOTFS_IMAGE" ]; then
	echo "FATAL: rootfs image not found at $ROOTFS_IMAGE" >&2
	exit 1
fi

mkdir -p "$OUTPUT_DIR"
WORK_DIR=$(mktemp -d "/tmp/openke-swu-build.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

echo "== Packaging OpenKE SWUpdate (.swu) v${VERSION} =="

cp "$KERNEL_IMAGE" "$WORK_DIR/xImage"
cp "$ROOTFS_IMAGE" "$WORK_DIR/rootfs.squashfs"

cat > "$WORK_DIR/postinstall.sh" <<'EOF'
#!/bin/sh
# OpenKE SWUpdate post-installation script
# Arms boot slot 2 (ota:kernel2) for the next reboot

set -e

echo "OpenKE SWUpdate post-install: setting next boot target to Slot 2 (ota:kernel2)..."

if [ -f /etc/ota_marker.sh ]; then
	. /etc/ota_marker.sh
	write_ota_marker "ota:kernel2"
elif [ -e /dev/mmcblk0p1 ]; then
	printf 'ota:kernel2\0' > /dev/mmcblk0p1
fi

echo "OpenKE SWUpdate post-install: boot target set to Slot 2."
exit 0
EOF
chmod +x "$WORK_DIR/postinstall.sh"

KERNEL_SHA=$(sha256sum "$WORK_DIR/xImage" | awk '{print $1}')
ROOTFS_SHA=$(sha256sum "$WORK_DIR/rootfs.squashfs" | awk '{print $1}')
POSTINSTALL_SHA=$(sha256sum "$WORK_DIR/postinstall.sh" | awk '{print $1}')

cat > "$WORK_DIR/sw-description" <<EOF
software =
{
	version = "${VERSION}";
	description = "OpenKE System Firmware Update";

	nebula-pad = {
		hardware-compatibility: [ "1.0" ];

		images: (
			{
				filename = "xImage";
				device = "/dev/mmcblk0p6";
				type = "raw";
				sha256 = "${KERNEL_SHA}";
			},
			{
				filename = "rootfs.squashfs";
				device = "/dev/mmcblk0p8";
				type = "raw";
				sha256 = "${ROOTFS_SHA}";
			}
		);

		scripts: (
			{
				filename = "postinstall.sh";
				type = "shellscript";
				sha256 = "${POSTINSTALL_SHA}";
			}
		);
	};
}
EOF

SWU_NAME="openke-update-${VERSION}.swu"
SWU_OUTPUT="$OUTPUT_DIR/$SWU_NAME"

(
	cd "$WORK_DIR"
	for f in sw-description xImage rootfs.squashfs postinstall.sh; do
		echo "$f"
	done | cpio -ov -H crc > "$SWU_OUTPUT"
)

# Integrity checks on the generated SWU
FIRST_MEMBER=$(cpio -it < "$SWU_OUTPUT" 2>/dev/null | head -n1)
if [ "$FIRST_MEMBER" != "sw-description" ]; then
	echo "FATAL: sw-description is not the first member of $SWU_OUTPUT (found $FIRST_MEMBER)" >&2
	exit 1
fi

SWU_SHA=$(sha256sum "$SWU_OUTPUT" | awk '{print $1}')
echo "OK   Created $SWU_OUTPUT (${SWU_SHA})"
echo "${SWU_SHA}  ${SWU_NAME}" > "$OUTPUT_DIR/${SWU_NAME}.sha256"
EOF
