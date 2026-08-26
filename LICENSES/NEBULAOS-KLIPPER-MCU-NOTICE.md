# NebulaOS Klipper MCU tooling notice

The printer-MCU firmware and the bundled Python pack/validation/flashing tools
are built from the pinned `coreflake1/NebulaOS-klipper-mcu` repository:

<https://github.com/coreflake1/NebulaOS-klipper-mcu>

That repository’s `LICENSE` and `NOTICE.md` apply to the copied tools and
patched Klipper-derived MCU firmware. The build pins the repository commit in
`manifests/dependencies.conf` and records the actual source identity in the
firmware bundle’s `manifest.env` and the final build manifest.
