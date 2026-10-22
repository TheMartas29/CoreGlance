# How CoreGlance reads each value

This file summarizes the research behind the implementation. Every value comes from an interface that works **without root**. Each path was verified live on a MacBook Air M4 (Mac16,12) running macOS 26.5. The reference implementations studied were [macmon](https://github.com/vladkens/macmon), [Stats](https://github.com/exelban/stats), [eul](https://github.com/gao-sun/eul), [Hot](https://github.com/macmade/hot), [asitop](https://github.com/tlkh/asitop) and [socpowerbud](https://github.com/dehydratedpotato/socpowerbud).

## CPU usage and P/E cores
- `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` returns per-core tick counters. Usage is the delta of (user + system + nice) / (that + idle). The counters are 32-bit and wrap, so deltas use wrapping subtraction.
- The core kind comes from the device tree: `IODeviceTree:/cpus/cpuN` has `cluster-type` = `"E"` or `"P"`, and `logical-cpu-id` matches the `host_processor_info` index. If that lookup fails, the app falls back to `hw.perflevel0/1.logicalcpu`, where E cores enumerate first.
  - On M5 and newer, `cluster-type` can also be `"M"`. That label means the middle tier: Apple reuses "P"/"M" for "Super"/"Performance". It is shown as unknown for now.

## CPU and GPU frequency (MX Power Gadget–style)
- **DVFS tables:** the `AppleARMIODevice` named `pmgr` holds the frequency tables as 8-byte records (`u32 freq`, `u32 voltage`):
  - `voltage-states1-sram` is the E-cluster table.
  - `voltage-states5-sram` is the P-cluster table.
  - `voltage-states9` is the GPU table. Its first entry is 0 Hz (off), and it is not monotonic.
- **Units:** M1–M3 store CPU frequencies in Hz. M4 stores them in **kHz**, because 4.4 GHz no longer fits in a u32. CoreGlance detects the unit by magnitude (≥ 1e8 means Hz), so it doesn't need a chip-name list. GPU frequencies are still in Hz on M4.
- **Residencies:** `libIOReport` (private, loaded with `dlopen`) provides them:
  - CPU: group `CPU Stats`, subgroup `CPU Core Performance States`, channels `ECPUn` and `PCPUn`. States are `IDLE, V0P7 … V7P0`. Inactive states (`IDLE`, `DOWN`, `OFF`) are skipped, and the remaining states map index-for-index onto the DVFS table.
  - GPU: group `GPU Stats`, subgroup `GPU Performance States`, channel `GPUPH`, with states `OFF, P1…P15`.
- **Reported frequency:** Σ(residency × freq) / Σ active residency, summed over all cores of a cluster. That is the average clock while the cluster is running, which is what MX Power Gadget shows.
- **Power:** IOReport `Energy Model` channels `CPU Energy` (mJ), `GPU Energy` (nJ), `ANE*` and `DRAM*`. The unit is taken from `IOReportChannelGetUnitLabel`.
- **Known risk:** macmon reports that from macOS 27 the Energy Model counters can stop updating without a private entitlement. Residencies are unaffected. If that happens, the CPU/GPU watts stop updating; frequencies keep working.

## Temperatures
- **SMC:** read through the `AppleSMC` user client (`IOConnectCallStructMethod`, selector 2). The 80-byte `SMCKeyData_t` is handled as a raw buffer with C offsets: Swift struct layout would otherwise misplace `result`, which is why Stats needs a padding field.
- **Sensor discovery:** CoreGlance enumerates all SMC keys at startup (`#KEY`, 2129 on the M4) rather than keeping per-chip lists, which change every generation:
  - Apple Silicon: CPU = `Tp*` + `Te*`, GPU = `Tg*`, all type `flt ` (little-endian float).
  - Intel: CPU = `TC0P/TC0D/TC0E/TC0F/TCnC`, GPU = `TG0P/TG0D`, type `sp78`.
- **Filtering:** only keys that read a plausible value at startup are kept. CPU values are clamped to 10–120 °C, the same filter Stats uses, because some M2 sensors report garbage.
- **HID:** the alternative sensor source (`IOHIDEventSystemClient`, usage page 0xff00) has **no CPU/GPU die sensors on M4 / macOS 26**, so it is not used.

## Battery
- AppleSmartBattery (IORegistry):
  - `Temperature` is in **centi-°C** (3051 = 30.5 °C), the same value Stats shows.
  - SMC `TB0T/TB1T/TB2T` is the fallback.
  - `CurrentCapacity` is a percentage on Apple Silicon (`MaxCapacity` == 100) and mAh on Intel.
  - Health = `AppleRawMaxCapacity / DesignCapacity`.
  - `Voltage` (mV) × `Amperage` (mA, two's complement) gives charge or discharge power.
  - `PowerTelemetryData.SystemPowerIn` gives adapter power.

## GPU usage
- `IOAccelerator` → `PerformanceStatistics` → `Device Utilization %` (with `GPU Activity(%)` as the AMD fallback). This is what Activity Monitor uses.

## Memory
- Used = App + Wired + Compressed, with App = `internal − purgeable` pages, from `host_statistics64(HOST_VM_INFO64)`. This matches Activity Monitor and equals the formula Stats uses.
- Pressure comes from `kern.memorystatus_vm_pressure_level` (1/2/4), swap from `vm.swapusage`.

## System power, fans
- SMC `PSTR` gives whole-system power in watts. The fallback is the battery's `SystemPowerIn`.
- Fans: `FNum`, `FnAc`, `FnMx`, in `flt` on AS and `fpe2` on Intel. Fanless Macs report no `FNum`.

## Not used, and why
- `powermetrics`: requires sudo.
- Intel Power Gadget: discontinued, needs a kext.
- Third-party SMC libraries: unnecessary, since the SMC reader here is about 100 lines.

## Alert thresholds

When **Color values at warning / critical levels** is on, a menu bar value turns orange at the warning level and red at the critical level. Only the value is colored, never the glyph. Every level can be changed in Settings → Alerts. The defaults, and where they come from:

| Metric | Warning | Critical | Basis |
|---|---|---|---|
| CPU temperature | 90 °C | 100 °C | Apple doesn't publish a junction limit. Spec databases list M4 / M4 Pro / M4 Max at **TjMax 100 °C** ([cpu-monkey](https://www.cpu-monkey.com/en/compare_cpu-apple_m4_10_cpu-vs-apple_m4_max_16_cpu_40_gpu), [comparigon](https://comparigon.com/cpus/apple-m4-pro-14-core)). Users report throttling from about 100–107 °C, e.g. a base Mac mini M4 dropping from 4.46 to ~3.8 GHz ([MacRumors](https://forums.macrumors.com/threads/mac-mini-m4-thermals.2442671/)). |
| GPU temperature | 85 °C | 100 °C | Same die and junction limit as the CPU. The GPU sensors usually read lower, so it warns a little earlier. |
| Battery temperature | 40 °C | 44 °C | Apple advises against ambient temperatures above 35 °C. A battery controller was observed stopping charging when the gas-gauge sensor reached **44 °C** ([Eclectic Light](https://eclecticlight.co/2021/01/30/why-your-laptop-mac-may-not-be-recharging/)). AlDente's "Heat Protection" defaults to 35 °C ([AlDente](https://apphousekitchen.com/feature-explanation-heat-protection/)). Li-ion ageing speeds up noticeably above ~40 °C. |
| SSD temperature | 70 °C | 80 °C | Typical NVMe warning/critical composite temperatures (WCTEMP 70–80 °C, CCTEMP 80–85 °C). The drive starts throttling at WCTEMP ([Netdata NVMe guide](https://www.netdata.cloud/guides/nvme/nvme-thermal-throttling/)). |
| Free disk space | < 50 GB | < 20 GB | A macOS upgrade needs roughly 26–44 GB free (Apple's "empty space requirements"), and ~50 GB is the usual recommendation ([Apple Community](https://discussions.apple.com/thread/254167993)). Swap and updates fail when the disk is nearly full. |
| CPU / GPU usage | 80 % | 95 % | Convention: sustained load near saturation. |
| Swap used | 4 GB | 10 GB | Heuristic: a few GB of swap is normal on macOS, while double-digit GB means RAM is heavily oversubscribed. |
| Battery charge | < 20 % | < 10 % | Matches the common low-battery and Low Power Mode prompts. Only applied while on battery. |
| Memory used / pressure / compressed | — | — | Not a fixed number. These metrics use the kernel's own memory pressure level (`kern.memorystatus_vm_pressure_level`: 2 = warning, 4 = critical), the same signal Activity Monitor's pressure graph shows. |

Temperature levels are stored in °C and shown in °F when that unit is selected.
