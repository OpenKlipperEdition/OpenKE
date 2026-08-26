# NebulaOS build environment

Source definition for `ghcr.io/openklipperedition/openke-build`, the single container `build.sh` runs the
whole `scripts/build/00-06` pipeline inside.

## What's in here

```
build-env/
├── Dockerfile           the image itself
├── versions.env         every pinned identity (base image digest, HelixScreen K1 toolchain)
├── verify-environment.sh   run inside a built image to sanity-check its tooling
└── toolchains/README.md    what toolchain(s) this image bundles and why
```

## What this image contains

Every host-level build tool `scripts/build/*.sh` actually invokes (gcc/g++, make, cmake, python3,
git, bison/flex, autotools, `dtc`, `mksquashfs`, `e2fsprogs`, ...) — see the Dockerfile's own
comment block for the exact package list and which stage script needs each one. Also retains
HelixScreen's pinned Bootlin mips32el-musl cross-toolchain for compatibility and diagnostics
(see below); production K1 builds use Buildroot's target toolchain after Stage 03.

## What this image does NOT contain

- **Project source.** `NebulaOS-firmware`, the full `OpenKlipperEdition/System` checkout,
  `prestonbrown/helixscreen`, Klipper, and Moonraker — all fetched fresh by
  `00-fetch-vendor-sources.sh` at build time; moving branches and immutable pins are configured in
  `manifests/dependencies.conf`. The image is the factory; `dependencies.conf` is the material list.
- **The kernel/rootfs/native-app target compiler.** That's Buildroot's own
  `mipsel-buildroot-linux-gnu-*` toolchain, self-bootstrapped from source during Stage 03 from the
  moving OKE System `buildroot/` subtree; the fetched System commit is recorded in
  `build-manifest.txt`. This image supplies the *host* tools Buildroot needs to build
  that toolchain, not the toolchain itself.

## Migration A vs. Migration B

This image is **Migration A**: replace the two nested containers
(`pellcorp/k1-bash-build` and the former standalone UI builder) with one NebulaOS-owned image. The
Bootlin SDK remains pinned here for compatibility, while production HelixScreen K1 builds use
Buildroot's own target toolchain after Stage 03 so the statically linked UI matches the firmware's
actual libc and target libraries.

## Building it yourself

```sh
docker build -t nebulaos-build:local build-env/
```

## Why Ubuntu 22.04, not 20.04 (pellcorp's base)

Nothing in the actual build scripts is 20.04-specific — the packages baked in here (Task 2's
inventory) are all available, at compatible-enough versions, on 22.04. Standardizing on 22.04 means
one fewer variable while proving Migration A: it's already the exact base
the existing audited Ubuntu 22.04 build base used, so the HelixScreen toolchain remains directly
reproducible from the pinned Bootlin archive.
