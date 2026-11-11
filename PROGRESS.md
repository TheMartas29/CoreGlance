# PROGRESS

## 2026-11-10 — coreglance#1 testovací target a unit testy
- Co: `testTarget` CoreGlanceTests (14 testů XCTest), extrakce čistých funkcí `SoCMetrics.megahertz`, `CPULoad.busyFraction`, `SMC.decode`, `Threshold.severity(of:)`.
- Výsledek: `swift test --disable-sandbox` zelené (<1 s testy); mutace prahu Hz/kHz test shodí.
- Poznámka: v sandboxu agenta je nutné `--disable-sandbox` (vnořený sandbox-exec selže).
- Další krok: CI (T02).

## 2026-11-11 — coreglance#6 follow-up QA k #1
- Co: komentář vrácen nad `readDVFSTables`; testy `SMC.decode` (ui8/si8/ui32, krátký vstup); `busyFraction` vrací 0 místo pádu při <4 tickách; poznámka o `--disable-sandbox` v CONTRIBUTING.
- Výsledek: nový test `testBusyFractionIgnoresMalformedSnapshots` před změnou padal (Index out of range), po ní zelený.

## 2026-11-10 — coreglance#9 metrika tepelného stavu
- Co: `ThermalLevel` (mapování `ProcessInfo.ThermalState` → text/Severity), `Snapshot.thermalState`, injektovatelný zdroj v `Monitor`, `Metric.thermalState` (System, výchozí vypnuto), menu bar, popover, `--dump`; `Preferences.initialMetrics(stored:)` pro testovatelné načtení.
- Výsledek: `swift test --disable-sandbox` 20 testů zelených (6 nových; před změnou nekompilovaly – chyběly typy).
- Nezkoušeno: screenshoty Snapshotter a `--dump` na serveru (`ssh puppet`) – ověří QA.

## 2026-11-11 — coreglance#12 CI: swift build/test a zúžená oprávnění
- Co: `build.yml` má `permissions: contents: read`, kroky `swift build` a `swift test` (bash, tee do logu, selže na `warning:`) před `build-app.sh`; samostatný job `release` (needs build, jen tag `v*`, `contents: write`, download-artifact, `GH_REPO`).
- Výsledek: lokálně `swift build --disable-sandbox` bez varování, `swift test --disable-sandbox` 20 testů zelených. YAML přes ruby v sandboxu agenta nešlo spustit (vyžaduje schválení), ověří QA.
- Další krok: QA.

## 2026-11-11 — coreglance#28 Skutečná verze v buildu
- Co: nový `scripts/apply-version.sh` (volá ho `build-app.sh` na kopii plistu): `CFBundleShortVersionString` z `$VERSION` → tag na HEAD → hodnota z plistu; `CFBundleVersion` = `GITHUB_RUN_NUMBER` nebo počet commitů, nejméně hodnota z plistu. `Resources/Info.plist` 0.2.3. `build.yml`: `fetch-depth: 0` a na tagu `VERSION=${GITHUB_REF_NAME#v}`.
- Výsledek: `bash scripts/test-apply-version.sh` 7/7 ok; `swift build --disable-sandbox` bez chyb. Celý `build-app.sh` v sandboxu agenta nejde (SwiftPM manifest sandbox-exec), ověří QA.
- Další krok: QA; vydání v0.2.4 mimo tiket.
