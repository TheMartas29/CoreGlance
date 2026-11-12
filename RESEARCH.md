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

## Apple M6 / macOS 27.2: why `--dump` shows GHz 0, no CPU watts and four untyped cores (coreglance#2)

`--dump` on an Apple M6 / macOS 27.2 shows `cores: EEEEEEPP????`, `eCluster/pCluster mhz 0.0`, `gpuMHz nil` and `cpuWatts nil`, while `gpuWatts`, the SMC temperatures and `systemWatts` work. Evidence below was collected on the M6 with `ioreg` (output trimmed, no serial numbers or UUIDs).

| Symptom | Cause | Status |
|---|---|---|
| GHz 0.0 (E and P) and `gpuMHz` nil | **Different structure.** The `pmgr` node no longer holds the DVFS tables; they moved to a sibling node `pmgr-child@700000`. `readDVFSTables` only reads the node named exactly `pmgr`, so all three tables are empty. | Confirmed |
| 4 cores without type | **Different value.** Cores 8–11 have `cluster-type` `"M"` (and the P cores 6–7 `"P"`). `detectKinds` only knows `"P"` and `"E"`. | Confirmed |
| `cpuWatts` nil | **Not an entitlement problem**, and not visible in the registry. No `CPU Energy` channel is registered in any `Energy Model` legend (only `GPU Energy`, PCIe ports, `apciec*`), so the CPU channel(s) are published some other way or under another name. | Cause not determined, needs live IOReport |

### Evidence

**1. DVFS tables are in `pmgr-child@700000`, not in `pmgr`.**

`ioreg -l -w0 -r -n pmgr` lists the whole `pmgr` node. Its own properties are only `pmp`, `compatible = "pmgr2,arch"`, `AAPL,phandle`, `pmc-ltr-ka`, `clpc`, `pmgr-ver`, `chiplet-count`, `pmc`, `device_type`, `name`, `pmc-pmgr`. There is no `voltage-states*` property. Children: `ApplePMGRv2` → `clpc@C840000`, `pmgrtools`, `ppm`.

`ioreg -l -w0 -r -n pmgr-child@700000` (class `AppleARMIODevice`, `compatible = "pmgr2,t8152"`) has the tables, with the same key names CoreGlance already looks for:

```
"voltage-states1-sram" = <e0d40e00 ee020000 00941100 ee020000 802b1800 f8020000 60361e00 02030000 ...>
"voltage-states5-sram" = <00f91500 ee020000 005e1a00 f8020000 c0201f00 0c030000 a0b42300 39030000 ...>
"voltage-states9"      = <00000000 7d000000 80e9eb1d a8020000 4021e027 c6020000 80d4b531 d5020000 ...>
"voltage-states9-sram", "voltage-states0/1/2/5/8/11/29" are present too.
```

Decoded with the unit rule from "CPU and GPU frequency": `voltage-states1-sram` starts at 0x000ED4E0 = 972 000 kHz (972 MHz, E cluster), `voltage-states5-sram` at 0x0015F900 = 1 440 000 kHz (1440 MHz, P cluster), `voltage-states9` has the 0 Hz "off" entry first, then 0x1DEBE980 = 502 000 000 Hz (502 MHz, GPU). Layout and units are the same as on M4, so only the node lookup is wrong.

`ioreg -l -w0 | grep -oE '"voltage-states[0-9a-z-]*"'` finds these keys only in `pmgr-child@700000`; no other node carries them. On the M4 the same keys were on `pmgr` itself (see "CPU and GPU frequency").

**2. `cluster-type` is `"M"` for the third tier, and P and M share one DVFS cluster.**

`ioreg -p IODeviceTree -n cpu6 -r -l -w0` → `"cluster-type" = <"P">`, `"logical-cpu-id" = 6`, `"logical-cluster-id" = 1`, `compatible = "apple,everest"`.
`ioreg -p IODeviceTree -n cpu8 -r -l -w0` → `"cluster-type" = <"M">`, `"logical-cpu-id" = 8`, `"logical-cluster-id" = 1`, `compatible = "apple,sawtooth"`.

Because `cluster-type` is read for every core, `found` is true and the `hw.perflevel` fallback never runs, so cores 8–11 stay `.unknown`. The CLPC node confirms only two DVFS clusters: `#cpu-num-clusters = 2`, `#cpu-core-mask-cluster-0 = 63` (cores 0–5) and `#cpu-core-mask-cluster-1 = 4032` (cores 6–11, so P and M cores). That is why there is one P table (`voltage-states5-sram`) and none for M. I did not read cores 0–5 and 7, 9–11 individually; their `cluster-type` follows from `--dump` (`EEEEEEPP????`) and the cluster masks.

**3. IOReport residency channels include an M tier.**

The `CPU Stats` legends in the registry list these channels: `EACC_ECPU0`…`EACC_ECPU5`, `PACC0_PCPU0`, `PACC0_PCPU1`, `PACC0_MCPU2`…`PACC0_MCPU5`. `SoCMetrics.sample()` sums channels whose name starts with `E` or `P`, so `MCPUn` residency would be ignored once the P table is found, and the P-cluster frequency would be computed from the two P cores only. The legend names carry an `ACC` prefix; the exact names in the `CPU Core Performance States` subgroup (`ECPUn`/`PCPUn`/`MCPUn`) could not be read here, see below.

**4. `cpuWatts`.**

`gpuWatts` works, so the `Energy Model` group is readable and an entitlement problem is unlikely (it would block all counters). The `Energy Model` legends in the registry contain only `GPU Energy`, `PCIe Port 0/2 Energy` and `apciec0/1/3 Energy`. No `CPU Energy` (or per-cluster CPU energy) channel is registered there, so the registry does not say what the CPU channel is called on M6, or whether it is exposed at all.

### What could not be determined, and why
- **The live IOReport channel list** (exact `Energy Model` CPU channel names, and the `CPU Core Performance States` channel names). In the agent sandbox `--dump` prints `ioreport: unavailable` (and `SMC unavailable`), so no channels can be listed there. It needs `CoreGlance` to log `report.sample()` channel group, subgroup, name and unit once on the M6, outside the sandbox.
- **`hw.perflevel*`.** `sysctl` is refused in the sandbox (`sysctl: sysctl fmt -1 1024 1: Operation not permitted`), so the number of performance levels and their sizes were not read. They are not needed for the fixes below.

### Proposed fixes (small, tested once a test target exists)
1. **DONE (#51, verification on a live M6 — `--dump` shows GHz > 0 — still pending, needs a human at the machine).** `SoCMetrics.readDVFSTables`: read nodes whose name is `pmgr` **or starts with `pmgr-child`**, keeping the first value found per key so the M4 behavior (tables on `pmgr`) does not change.
2. `CPULoad.detectKinds`: map `"M"` to `.performance` (M cores run on the P-cluster DVFS table, evidence 2). **Done in #54** as the pure `CPULoad.kinds(entries:count:perflevel:)` with unit tests; a separate `CoreKind` for the middle tier is deferred until data from the M6.
3. **DONE (#51, live M6 verification pending).** `SoCMetrics.sample`: also sum `MCPUn` residency into the P cluster.
4. `cpuWatts`: log the live Energy Model channel list on the M6, then accept the real name (probably a sum of per-cluster channels).

Estimate: about 40–80 changed lines for 1–3, plus tests. Tests need a test target and a way to feed recorded data (`Package.swift` has none, T01, outside this ticket's allowed files), so the fixes are left to follow-up tickets. Fail-soft stays: missing tables keep showing "–".
