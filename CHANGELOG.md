# OpenKE Release Changelog

## [1.0.0] - 2026-09-28
### Added
- Native SWUpdate dual-slot A/B streaming upgrade system with hardware compatibility and print safety interlocks.
- GuppyScreen system update panel supporting offline USB auto-discovery and online OTA updates.
- Modular printer configuration layout (`hardware/`, `macros/`) and dedicated `user.cfg` for immutable user overrides.
- Non-destructive configuration migration engine (`S04openke-migrate`) preserving calibration data (`SAVE_CONFIG`), PID tunes, and user overrides across updates.
- Official Mainsail macro suite integration across all supported printer profiles (Ender-3 V3 KE, V3 SE, S1, V2 Neo, V2, Pro, Base).
- Kernel display backlight device wrapper (`/sys/class/backlight`) and dropbear-compatible SFTP server.
- WebCam streaming optimization via `ustreamer` with TCP_NODELAY and WiFi SDIO IRQ priority elevation (`SCHED_FIFO 60`).
- OpenKE Power-Loss Recovery (PLR) dual-generation state machine with atomic sidecar checkpointing.

### Changed
- Standardized kernel baseline on Linux 6.6.157 PREEMPT.
- Upgraded Buildroot base system to 2026.02 LTS.

### Removed
- Standalone SWUpdate Mongoose web server on port 8080 to prevent port collisions with `ustreamer`.
- Obsolete rootfs ext2 generation in favor of streamlined SquashFS rootfs.
- Legacy RT memory tuning overrides and obsolete vendor test scripts.
