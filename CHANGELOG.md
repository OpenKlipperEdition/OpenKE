# OpenKE Release Changelog

## [1.0.0] - 2026-09-20
### Added
- Native SWUpdate dual-slot A/B streaming upgrade system with hardware compatibility safety interlocks.
- GuppyScreen system update panel supporting offline USB auto-discovery and online OTA updates.
- Full OpenKE Power-Loss Recovery (PLR) integration with dual-slot atomic sidecar checkpointing (5s cadence) inherited from NebulaOS.
- Linux PREEMPT_RT memory reclaim resilience (`vm.min_free_kbytes = 8192`, dirty page pacing).
- Hung task watchdog and panic timeout recovery configurations.
- Dual-generation state machine to guarantee zero-corruption gcode resume.

### Removed
- Legacy Creality PLR file format and fallback code in GuppyScreen.
