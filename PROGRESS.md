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

## 2026-11-11 — coreglance#14 čistá klasifikace SMC klíčů
- Co: `Thermals.classify(keys:isARM:)` a `Thermals.aggregate(_:valid:)` jako čisté funkce, `init?()` je používá; 4 nové testy (ThermalsTests).
- Výsledek: `swift test --disable-sandbox` 24 testů zelených, build bez varování; testy před změnou nekompilovaly.
- Poznámka: `--dump` v sandboxu vypíše `smc sensors: SMC unavailable`; porovnání před/po na reálném HW ověří QA.
