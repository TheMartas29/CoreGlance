# Changelog

## 0.1.0 — 2026-10-22

First public release.

- Menu bar meters with 19 selectable metrics: CPU usage, P/E-core usage, P/E-core frequency, GPU usage and frequency, memory used, memory pressure, compressed memory, swap, free disk space, CPU/GPU/battery/SSD temperature, battery charge, system power, fan speed and network speed.
- Popover with full readout: per-core bars, cluster GHz, temperatures (average and max), memory breakdown, disk, battery health, cycles and power, and component power (CPU, GPU, ANE, DRAM).
- Settings: metric selection, SF Pro / SF Mono font, glyphs, labels, °C/°F, average or hottest temperature, refresh interval, launch at login.
- Apple Silicon M1–M4 support, with automatic handling of the M4 kHz DVFS tables. Best-effort Intel support.
- `--dump` diagnostics and `--snapshot` screenshot rendering.
