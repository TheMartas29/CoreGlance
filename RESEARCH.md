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

When **Color temperatures at warning / critical levels** is on, a temperature in the menu bar turns orange at the warning level and red at the critical level. Only the value is colored, never the glyph. Other metrics (usage, memory, disk) are never colored. Every level can be changed in Settings → Alerts. The defaults, and where they come from:

| Sensor | Warning | Critical | Basis |
|---|---|---|---|
| CPU | 90 °C | 100 °C | Apple doesn't publish a junction limit. Spec databases list M4 / M4 Pro / M4 Max at **TjMax 100 °C** ([cpu-monkey](https://www.cpu-monkey.com/en/compare_cpu-apple_m4_10_cpu-vs-apple_m4_max_16_cpu_40_gpu), [comparigon](https://comparigon.com/cpus/apple-m4-pro-14-core)). Users report throttling from about 100–107 °C, e.g. a base Mac mini M4 dropping from 4.46 to ~3.8 GHz ([MacRumors](https://forums.macrumors.com/threads/mac-mini-m4-thermals.2442671/)). |
| GPU | 85 °C | 100 °C | Same die and junction limit. The GPU sensors usually read lower, so it warns a little earlier. |
| Battery | 35 °C | 40 °C | See below. |
| SSD | 70 °C | 80 °C | Typical NVMe warning/critical composite temperatures (WCTEMP 70–80 °C, CCTEMP 80–85 °C). The drive starts throttling at WCTEMP ([Netdata NVMe guide](https://www.netdata.cloud/guides/nvme/nvme-thermal-throttling/)). |

### Battery temperature: what is fine and what isn't

- **Up to ~35 °C is fine.** Apple specifies a Mac operating range of **10–35 °C** and warns that heat above 35 °C can permanently reduce battery capacity ([iMore](https://www.imore.com/how-check-and-maintain-optimal-macbook-temperature), [Engadget](https://engadget.com/2242777/using-macbook-outside-consider-these-things/)). Cell makers list **15–35 °C** as the optimal charging range ([CMB spec](https://cmbatteries.com/cmb-lithium-battery-safety-precautions)), and research puts the optimum at 15–35 °C with faster ageing above it ([RRST-EE study](https://journal.iem.pub.ro/rrst-ee/article/download/1210/534/12620)). CleanMyMac treats **35 °C and above** as overheating ([MacPaw](https://macpaw.com/support/cleanmymac/knowledgebase/battery-temperature)), and AlDente's heat protection also stops charging at 35 °C by default ([AlDente](https://apphousekitchen.com/feature-explanation-heat-protection/)).
- **35–40 °C: warning.** The battery still works, but it ages faster, especially while charging. A Mac that is too warm stops charging at 80 % ([iMore](https://www.imore.com/how-check-and-maintain-optimal-macbook-temperature)).
- **40 °C and above: critical.** This is close to the end of the safe Li-ion charging window, which is 0–45 °C ([CMB spec](https://cmbatteries.com/cmb-lithium-battery-safety-precautions), [Elfa / BU-410](https://www.elfa.nl/wp-content/uploads/2023/08/Charging-at-high-and-low-temperatures.pdf)). A MacBook battery controller was observed stopping charging at **44 °C** ([Eclectic Light](https://eclecticlight.co/2021/01/30/why-your-laptop-mac-may-not-be-recharging/)).

Temperature levels are stored in °C and shown in °F when that unit is selected.

## Open issue: Apple M6 / macOS 27.2 (coreglance#2)

`--dump` on an Apple M6 / macOS 27.2 shows `cores: EEEEEEPP????`, `eCluster/pCluster mhz 0.0`, `gpuMHz nil` and `cpuWatts nil`, while `gpuWatts`, the SMC temperatures and `systemWatts` work. This section is derived **from the code paths only**. The `ioreg`/`sysctl` evidence has not been collected yet (see "Evidence needed").

| Symptom | What the code implies | Status |
|---|---|---|
| GHz 0.0 (E and P) and `gpuMHz` nil | `SoCMetrics.sample()` returns `eFreqs.first ?? 0` for an idle cluster. A value of exactly 0 therefore means the E and P tables are **empty**, and `gpuMHz` is nil only when `gpuFreqs` is empty. All three tables are missing at once, so the cause is the `pmgr` lookup or key naming (`voltage-states1-sram`, `5-sram`, `9` absent, a different node/class, or values that are not `Data`), not one cluster's table. It is not IOReport. | Likely, unverified |
| `cpuWatts` nil | IOReport itself works, because `gpuWatts` is 0.036. An entitlement problem would hit every Energy Model counter, not only the CPU one. `cpuWatts` is nil only when no channel named exactly `CPU Energy` exists in the `Energy Model` group, so the CPU channels most likely have a different name on M6 (per-cluster or per-tier). | Likely, unverified |
| 4 cores with unknown type | 6×E and 2×P are detected, so `cluster-type` is read correctly. The `found` flag is already true, so the `hw.perflevel` fallback never runs. The remaining four cores have a `cluster-type` that is neither `"P"` nor `"E"`, which matches the `"M"` tier described in "CPU usage and P/E cores" above. | Likely, unverified |

No code was changed: mapping `"M"` to a core kind or guessing new table keys without seeing the registry would be speculation, and the fail-soft behavior (unknown values shown as "–") must stay intact.

### Evidence needed (run on the M6, strip serial numbers/UUIDs)
- `ioreg -l -w0 -r -n pmgr | grep -oE '"voltage-states[0-9a-z-]*" = <[0-9a-f]{0,48}'` shows which tables exist and their unit (Hz or kHz).
- `ioreg -p IODeviceTree -n cpu0 -r -l -w0 | grep -E 'cluster-type|logical-cpu-id'`, repeated for `cpu0`…`cpu11`, shows the `cluster-type` of each core.
- `sysctl hw.nperflevels hw.perflevel0 hw.perflevel1 hw.perflevel2` shows how many core tiers there are and their sizes.
- The list of `Energy Model` channel names (log the channels from `report.sample()` once) shows what replaced `CPU Energy`.

### Which cause is it? Answer to "missing keys / channel name / entitlement / structure"
- **Entitlement:** unlikely, from the code (GPU energy is read, so the Energy Model counters are not blocked).
- **Missing `pmgr` keys or different structure (GHz, GPU MHz):** most likely, but **cannot be determined without** the `ioreg -r -n pmgr` listing from the M6.
- **Different IOReport channel name (CPU watts):** most likely, but **cannot be determined without** the Energy Model channel names from the M6.
- **Unknown `cluster-type` (cores):** most likely `"M"`, but **cannot be determined without** the `cluster-type` of `cpu0`…`cpu11`.

The agent run that produced this note was denied `ioreg`, `sysctl` and running `CoreGlance --dump` (each returned "requires approval"; `swift build --disable-sandbox` works). A dispatcher config change is needed: allow these read-only commands as standalone calls (no pipes), or have the owner paste the four outputs into the ticket.

### Estimate and split (for the PM)
The fix is small only if the registry shows a plain rename or an `"M"` tier. Estimate: about 60–120 changed lines, three independent slices, each its own ticket:
1. Collect the four outputs on the M6 (no code, 10 minutes).
2. `CPULoad` `"M"` mapping plus a test target with recorded-data fixtures (needs `Package.swift`, which is outside this ticket's allowed files; this is T01).
3. `SoCMetrics` DVFS keys and CPU energy channel names, tested against the recorded fixtures.

### Proposed fix once the evidence is in (small, one PR)
1. `CPULoad.detectKinds`: map `"M"` to `.performance` (or a new kind if the UI should distinguish it).
2. `SoCMetrics.readDVFSTables`: add the table keys for the new clusters and combine the P-tier clusters.
3. `SoCMetrics.sample`: accept the new CPU energy channel names (sum of per-cluster channels).
4. Tests need a test target and a way to feed recorded data. `Package.swift` has no test target (T01), and it is outside this ticket's allowed files.
