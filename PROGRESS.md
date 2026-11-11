# PROGRESS

## 2026-11-10 — coreglance#1 testovací target a unit testy
- Co: `testTarget` CoreGlanceTests (14 testů XCTest), extrakce čistých funkcí `SoCMetrics.megahertz`, `CPULoad.busyFraction`, `SMC.decode`, `Threshold.severity(of:)`.
- Výsledek: `swift test --disable-sandbox` zelené (<1 s testy); mutace prahu Hz/kHz test shodí.
- Poznámka: v sandboxu agenta je nutné `--disable-sandbox` (vnořený sandbox-exec selže).
- Další krok: CI (T02).

## 2026-11-10 — coreglance#9 metrika tepelného stavu
- Co: `ThermalLevel` (mapování `ProcessInfo.ThermalState` → text/Severity), `Snapshot.thermalState`, injektovatelný zdroj v `Monitor`, `Metric.thermalState` (System, výchozí vypnuto), menu bar, popover, `--dump`; `Preferences.initialMetrics(stored:)` pro testovatelné načtení.
- Výsledek: `swift test --disable-sandbox` 20 testů zelených (6 nových; před změnou nekompilovaly – chyběly typy).
- Nezkoušeno: screenshoty Snapshotter a `--dump` na serveru (`ssh puppet`) – ověří QA.

## 2026-11-11 — coreglance#12 CI: swift build/test a zúžená oprávnění
- Co: `build.yml` má `permissions: contents: read`, kroky `swift build` a `swift test` (bash, tee do logu, selže na `warning:`) před `build-app.sh`; samostatný job `release` (needs build, jen tag `v*`, `contents: write`, download-artifact, `GH_REPO`).
- Výsledek: lokálně `swift build --disable-sandbox` bez varování, `swift test --disable-sandbox` 20 testů zelených. YAML přes ruby v sandboxu agenta nešlo spustit (vyžaduje schválení), ověří QA.
- Další krok: QA.
