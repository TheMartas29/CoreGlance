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

## 2026-11-11 — coreglance#18 automatická aktualizace z GitHub Releases
- Co: `Update/` (UpdateLogic = semver, parsování `releases/latest`, plán 24 h; UpdateInstaller = ditto → kontrola bundle id + verze → záloha a výměna přejmenováním; Updater = síť přes protokol, fail-soft), `Preferences.autoUpdate` (výchozí zapnuto) + `init(defaults:)`, přepínač a „Update available“ v Nastavení, README, CHANGELOG.
- Výsledek: `swift test --disable-sandbox` 38 testů zelených (18 nových; před změnou nekompilovaly), `--dump` beze změny, jediný síťový cíl je api.github.com.
- Nezkoušeno: screenshot Nastavení a skutečný restart po instalaci (GUI) – ověří QA.

## 2026-11-11 — coreglance#18 kolo 2: zúžení na první řez
- QA: PR > 500 řádků. Řez 1 = přepínač, plánování, kontrola GitHub API, „Update available“ v Nastavení. Instalace (UpdateInstaller + restart) odložena do navazujícího tiketu; kód je v commitu bfcd448 (`git show bfcd448:Sources/CoreGlance/Update/UpdateInstaller.swift`).
- Výsledek: `swift test --disable-sandbox` 35 testů zelených (20 → 35).
