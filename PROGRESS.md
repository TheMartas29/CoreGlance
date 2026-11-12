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

## 2026-11-11 — coreglance#18 automatická aktualizace z GitHub Releases
- Co: `Update/` (UpdateLogic = semver, parsování `releases/latest`, plán 24 h; UpdateInstaller = ditto → kontrola bundle id + verze → záloha a výměna přejmenováním; Updater = síť přes protokol, fail-soft), `Preferences.autoUpdate` (výchozí zapnuto) + `init(defaults:)`, přepínač a „Update available“ v Nastavení, README, CHANGELOG.
- Výsledek: `swift test --disable-sandbox` 38 testů zelených (18 nových; před změnou nekompilovaly), `--dump` beze změny, jediný síťový cíl je api.github.com.
- Nezkoušeno: screenshot Nastavení a skutečný restart po instalaci (GUI) – ověří QA.

## 2026-11-11 — coreglance#18 kolo 2: zúžení na první řez
- QA: PR > 500 řádků. Řez 1 = přepínač, plánování, kontrola GitHub API, „Update available“ v Nastavení. Instalace (UpdateInstaller + restart) odložena do navazujícího tiketu; kód je v commitu bfcd448 (`git show bfcd448:Sources/CoreGlance/Update/UpdateInstaller.swift`).
- Výsledek: `swift test --disable-sandbox` 35 testů zelených (20 → 35).

## 2026-11-11 — coreglance#12 CI: swift build/test a zúžená oprávnění
- Co: `build.yml` má `permissions: contents: read`, kroky `swift build` a `swift test` (bash, tee do logu, selže na `warning:`) před `build-app.sh`; samostatný job `release` (needs build, jen tag `v*`, `contents: write`, download-artifact, `GH_REPO`).
- Výsledek: lokálně `swift build --disable-sandbox` bez varování, `swift test --disable-sandbox` 20 testů zelených. YAML přes ruby v sandboxu agenta nešlo spustit (vyžaduje schválení), ověří QA.
- Další krok: QA.

## 2026-11-11 — coreglance#28 Skutečná verze v buildu
- Co: nový `scripts/apply-version.sh` (volá ho `build-app.sh` na kopii plistu): `CFBundleShortVersionString` z `$VERSION` → tag na HEAD → hodnota z plistu; `CFBundleVersion` = `GITHUB_RUN_NUMBER` nebo počet commitů, nejméně hodnota z plistu. `Resources/Info.plist` 0.2.3. `build.yml`: `fetch-depth: 0` a na tagu `VERSION=${GITHUB_REF_NAME#v}`.
- Výsledek: `bash scripts/test-apply-version.sh` 7/7 ok; `swift build --disable-sandbox` bez chyb. Celý `build-app.sh` v sandboxu agenta nejde (SwiftPM manifest sandbox-exec), ověří QA.
- Další krok: QA; vydání v0.2.4 mimo tiket.

## 2026-11-11 — coreglance#14 čistá klasifikace SMC klíčů
- Co: `Thermals.classify(keys:isARM:)` a `Thermals.aggregate(_:valid:)` jako čisté funkce, `init?()` je používá; 4 nové testy (ThermalsTests).
- Výsledek: `swift test --disable-sandbox` zelené, build bez varování; testy před změnou nekompilovaly.
- Poznámka: `--dump` v sandboxu vypíše `smc sensors: SMC unavailable`; porovnání před/po na reálném HW ověří QA.

## 2026-11-12 — coreglance#32 follow-up QA k verzi v buildu
- Co: `apply-version.sh` bere jen tagy `v<číslo>`, ořezává „v“ i u `$VERSION`, odmítá znaky mimo `[0-9A-Za-z.+-]`, v mělkém klonu varuje; `build-app.sh` přijímá `SWIFT_BUILD_FLAGS`; `test-apply-version.sh` má 11 nových kontrol včetně běhu `build-app.sh` se stubem swiftu (zachytí smazané volání). CI kroky (test skriptu + kontrola verze v sestavené appce) čekají v `.puppet/github/workflows/build.yml` na zkopírování dispečerem.
- Výsledek: `bash scripts/test-apply-version.sh` 18/18 ok; proti základu `main` padá 6 nových kontrol.
- Další krok: QA.
