# NebulaOS printer-MCU automatic upgrade

The firmware build now fetches the pinned `coreflake1/NebulaOS-klipper-mcu`
repository at `MCU_PIN`, builds its patched official Klipper checkout twice,
checks that the raw images match, runs the repository target validator, and
stages the resulting bundle at `/opt/nebulaos/mcu`.

The immutable bundle contains:

- `klipper-creality.bin` — the Creality-format GD32F303 firmware image;
- `klipper.elf` and `klipper.config` — build evidence for offline validation;
- `manifest.env` — source identity, target metadata, and the image SHA256;
- `tools/creality_validator.py`, `creality_flash.py`, and
  `creality_packer.py`, and `stage4_first_flash.py` — the upstream project’s
  validation, packing, and identity-gated flashing tools.

`S57nebulaos-mcu-upgrade` runs after Klipper and Moonraker have started. On
first boot, it uses the stock-to-NebulaOS first-flash sequence because stock
firmware lacks the serial bootloader-request path. On a later build whose image
SHA differs from the persistent state, it stops the host services and uses the
normal serial flasher. The service records success only after the tool reports
both a completed transfer and application start, so a failed attempt is not
silently treated as complete.

The service is enabled by default. To prevent an automatic MCU write before a
hardware qualification session, create this persistent marker before boot:

```sh
touch /usr/data/nebulaos/system/mcu-auto-upgrade.disabled
```

The external project currently labels the image offline-validated but not
hardware-qualified. The first real-device flash must therefore be treated as a
hardware qualification step, with a recovery path available.

The offline structural coverage is in
`tests/mcu-auto-upgrade-tests.sh`; it checks the build/verification wiring and
the real lexicographic boot order without opening a serial port.
