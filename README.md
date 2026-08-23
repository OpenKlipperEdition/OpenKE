# NebulaOS Firmware

This is where NebulaOS actually gets built. NebulaOS is a custom Linux + Klipper stack for the
Creality Ender-3 V3 KE — real mainline-ish kernel, real Klipper, a proper touchscreen UI, none of
the stock firmware's binary blobs where we could avoid them.

If you want to build the whole OS, this is the repo you want. The full OpenKlipperEdition/System
OKE checkout supplies both the kernel and Buildroot; official upstream Klipper and the
OpenKlipperEdition/GuppyScreen OKE branch supply the application stack. The build refreshes moving
sources, verifies immutable inputs, and puts the whole thing together into something you can flash.

```
OpenKlipperEdition/System ─┐
Klipper upstream ─────────┼─►  NebulaOS-firmware  ─►  final rootfs + kernel + firmware image
GuppyScreen (OKE) ───────┘   (this repo)
```

- [`OpenKlipperEdition/System`](https://github.com/OpenKlipperEdition/System) — full OKE checkout providing Linux 6.6 (`kernel/kernel-6.6`) and Buildroot (`buildroot/`)
- [`Klipper`](https://github.com/Klipper3d/klipper) — official upstream Klipper runtime (`master` branch)
- [`GuppyScreen`](https://github.com/OpenKlipperEdition/GuppyScreen) — touchscreen UI (`OKE` branch)
- [`NebulaOS`](https://github.com/coreflake1/NebulaOS) — releases live here, not source

The build records every external input in `manifests/dependencies.conf`. Immutable sources are
pinned by exact commit, tag, archive hash, or container digest. The kernel and Buildroot follow the latest remote HEAD of OpenKlipperEdition/System's `OKE` branch, while Klipper follows official upstream `master` and GuppyScreen follows
OpenKlipperEdition/GuppyScreen's `OKE` branch. The exact fetched commits are recorded in
`build-manifest.txt`. The build always refreshes those moving checkouts and does not use
unrelated local clones sitting next to this repo.

## Building it

```sh
git clone https://github.com/coreflake1/NebulaOS-firmware.git
cd NebulaOS-firmware
./build.sh
```

That's genuinely it. `build.sh` pulls one build container
(`ghcr.io/coreflake1/nebulaos-build`, digest-pinned) and runs the whole pipeline inside it —
fetches every dependency, applies the 8 accepted kernel variants, builds the kernel/rootfs/app
stack, and checks the result actually looks right. You need Docker or Podman and not much else —
no `apt-get install` beforehand, no nested containers, nothing weird.

Budget ~15GB of disk and a few hours on a normal machine. It needs the network the whole time,
since everything gets fetched and hash-checked as it goes.

NebulaOS uses official upstream Klipper directly. NebulaOS-specific printer behavior is kept in the
tracked overlay configuration (`printer.cfg`, `frontend-controls.cfg`, and `moonraker.conf`); there is
no vendor-specific configuration bundle. The webcam pipeline remains the pinned
[`pellcorp/k1-ustreamer`](https://github.com/pellcorp/k1-ustreamer) integration.

If you want to see what's actually happening under the hood, `build.sh` runs these in order
(details in `scripts/build/README.md`):

```sh
cd scripts/build
./00-fetch-vendor-sources.sh
./01-apply-kernel-patches.sh
./02-configure-buildroot.sh
./03-build-kernel-and-rootfs.sh
./04-cross-compile-app-stack.sh
./05-final-build.sh
./06-verify.sh
```

When it's done, you'll have `xImage`, `rootfs.ext2`, and `rootfs.squashfs` in
`artifacts/buildroot-halley5-v30-image/`, plus `build-manifest.txt` (records exactly what went
into this build) and `kernel.config`. `rootfs.ext2` is configured as a 500 MiB filesystem so the
complete application stack fits reliably; `rootfs.squashfs` is the compressed deployment image.
GuppyScreen's compiled binary shows up separately in
`artifacts/guppyscreen-mips/`. The last stage sanity-checks that everything is real, correctly
architected MIPS32 output — it's not claiming byte-for-byte reproducibility between two separate
builds (timestamps and a few build-path strings will differ), just that the same code went in and
came out right.

## Don't build the other three repos on their own

Cloning the kernel, Klipper, or GuppyScreen repository by itself and trying to build it will not
produce a working printer image — none of those repositories contains the complete board image. This
repo fetches the kernel, official upstream Klipper, GuppyScreen, Moonraker, the retained
`k1-ustreamer` webcam stack, Buildroot, and the tracked NebulaOS overlay, then assembles the
flashable result.

## How reproducible is this, really

Immutable inputs in `manifests/dependencies.conf` are exact commits, tags, archive hashes, or
digests and are checked on every run. The kernel's and Klipper's moving-branch commits are recorded
in `build-manifest.txt` instead. The 8
kernel variants we build on top of the OKE branch (PREEMPT_RT,
a WiFi SDIO IRQ priority fix, VSYNC-gated display panning, a pinctrl ownership fix, the final
backlight controller, PWM state readback, the final touch driver, and disabling WiFi roaming) live
as small, order-independent scripts under `scripts/build/`, applied by
`scripts/build/apply-qualified-baseline.sh`.

## Wait, is this the same thing as OpenKE?

No, and it's a fair question since they're related. [OpenKE](https://github.com/coreflake1/guppyscreen)
is a separate project — its own installer for stock Creality firmware, its own releases — that
shares an author and some history with NebulaOS, but they're not the same project anymore.
The kernel source now comes from the `OKE` branch of
[`OpenKlipperEdition/System`](https://github.com/OpenKlipperEdition/System); that repository is
separate from the OpenKE installer project.

## If you're setting one of these up yourself

Beyond just building, this repo is also where we keep the docs for installing, updating, and
recovering an actual device — written for developers who already have SSH/root on their printer,
not as a polished installer walkthrough:

- [`docs/A_B_SLOT_MODEL.md`](docs/A_B_SLOT_MODEL.md) — how the stock/custom partition layout works
- [`docs/DEVELOPER_INSTALL_FROM_STOCK.md`](docs/DEVELOPER_INSTALL_FROM_STOCK.md) — putting NebulaOS on a printer for the first time
- [`docs/DEVELOPER_UPDATE.md`](docs/DEVELOPER_UPDATE.md) — updating a printer that's already running NebulaOS
- [`docs/DEVELOPER_RECOVERY.md`](docs/DEVELOPER_RECOVERY.md) — what to do if something goes wrong
- [`docs/HOW_TO_SWITCH_STOCK_AND_CUSTOM.md`](docs/HOW_TO_SWITCH_STOCK_AND_CUSTOM.md) — flipping between stock and custom day to day
- [`docs/BUILD_PROVENANCE.md`](docs/BUILD_PROVENANCE.md) — figuring out exactly what produced a given build
- [`docs/NEBULAOS_FRONTEND_PRINT_CONTROLS.md`](docs/NEBULAOS_FRONTEND_PRINT_CONTROLS.md) — the upstream-Klipper frontend configuration closure
- [`docs/NEBULAOS_BUILD_ENVIRONMENT.md`](docs/NEBULAOS_BUILD_ENVIRONMENT.md) — what's actually in the build container
- [`ACKNOWLEDGEMENTS.md`](ACKNOWLEDGEMENTS.md) — the upstream projects and prior work this stands on

The other repos (kernel, Klipper, GuppyScreen, and the [`NebulaOS`](https://github.com/coreflake1/NebulaOS)
release repo) all link back here instead of keeping their own copies of this stuff — this is the
one place it's kept up to date.

## History

This repo used to be a broader research workspace called `ke-mainline-klipper`. That history —
hardware bring-up notes, root-cause writeups, the mission-by-mission log — is still here, in
[`docs/HISTORY.md`](docs/HISTORY.md) and the rest of `docs/`. `FIRMWARE.md` is the long-form
technical reference for the build internals, if you want the deep version of any of this.

## License

See [`LICENSES/`](LICENSES/) for this project's own code and everything it vendors or fetches.
