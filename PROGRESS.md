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

## 2026-11-12 — coreglance#38 čistý výpočet rychlosti sítě a přepočet paměti
- Co: `NetworkReader.rate(previous:current:dt:)`, `NetworkReader.isVirtual(_:)`, `MemoryReader.stats(from:pageSize:total:)` jako čisté funkce; `sample()`/`read()` je jen volají. 7 nových testů (NetworkMemoryTests).
- Výsledek: testy před změnou nekompilovaly (chybí `rate`), po ní `swift test --disable-sandbox` zelené, build bez varování; `--dump` vypisuje řádky MemoryStats/NetworkStats ve stejném formátu.

## 2026-11-12 — coreglance#37 čisté parsování baterie
- Co: `BatteryReader.parse(_:)` čistá funkce, `read()` jen volá IORegistry + parse; 11 testů (BatteryParseTests). Prázdný slovník = present false.
- Výsledek: `swift build` bez varování, `swift test --disable-sandbox` zelené; testy na main nekompilují (chybí `parse`).
- Další krok: QA.

## 2026-11-12 — coreglance#36 kontrola shody verze při releasu
- Co: `scripts/check-version.sh` (tag × Info.plist × nejvyšší číselná sekce CHANGELOGu), `scripts/release-notes.sh` (tělo sekce), `scripts/test-check-version.sh`; Info.plist 0.2.5; `build.yml`: kontrola na tagu před buildem, testy skriptů, release s `--notes-file`; sekce Releasing v CONTRIBUTING.
- Výsledek: `sh scripts/test-check-version.sh` samé ok, `sh scripts/check-version.sh 0.2.5` exit 0, `test-apply-version.sh` ok. Na main skripty neexistují, testy tam padají.
- Eskalace (QA kolo 2): puppetd vydává commitem, který mění jen CHANGELOG, Info.plist zaostává → CI na tagu volá `check-version.sh --skip-plist` (tag × CHANGELOG); plist aplikace dostává verzi z tagu přes apply-version.sh. Výchozí režim skriptu zůstal přísný (plist i CHANGELOG). Regresní test „release commit“ padal na předchozí verzi skriptu.
- Další krok: QA; správce: release krok puppetd by mohl zvedat i Info.plist, pak `--skip-plist` z build.yml odstranit.
- Merge main: konflikty CHANGELOG/PROGRESS vyřešeny, Info.plist 0.2.7 (= nejvyšší sekce CHANGELOGu), aby `check-version.sh 0.2.7` na mainu prošel.

## 2026-11-12 — coreglance#32 follow-up QA k verzi v buildu
- Co: `apply-version.sh` bere jen tagy `v<číslo>`, ořezává „v“ i u `$VERSION`, odmítá znaky mimo `[0-9A-Za-z.+-]`, v mělkém klonu varuje; `build-app.sh` přijímá `SWIFT_BUILD_FLAGS`; `test-apply-version.sh` má 11 nových kontrol včetně běhu `build-app.sh` se stubem swiftu (zachytí smazané volání). CI kroky (test skriptu + kontrola verze v sestavené appce) čekají v `.puppet/github/workflows/build.yml` na zkopírování dispečerem.
- Výsledek: `bash scripts/test-apply-version.sh` 18/18 ok; proti základu `main` padá 6 nových kontrol.
- Další krok: QA.

## 2026-11-12 — coreglance#30 follow-up QA k aktualizacím (#18)
- Co: přepínač přejmenován na „Check for updates automatically“ (nic neinstaluje); nečitelná odpověď API nemaže `knownRelease` ani neukládá `lastUpdateCheck`; `html_url` se ověřuje jako stažení (jinak odkaz na latest); tag `V0.3.0` → „0.3.0“; CONTRIBUTING zmiňuje Update/.
- Výsledek: `swift test --disable-sandbox` 60 testů zelených; 3 nové testy před opravou padaly.
- Neřešeno: screenshot Nastavení (QA/grafik); instalace a SHA-256 jsou v navazujícím tiketu; hodinové opakování po chybě (krit. 5) ponecháno záměrně.

## 2026-11-12 — coreglance#54 čisté určení typu jader
- Co: `CPULoad.kinds(entries:count:perflevel:)` čistá funkce („M“ → performance, neznámé → unknown, id mimo rozsah ignorováno, fallback hw.perflevel, Intel unknown); `detectKinds` jen sbírá data; 7 testů (CoreKindsTests). CHANGELOG, poznámka v RESEARCH.md.
- Výsledek: `swift build` bez varování, `swift test --disable-sandbox` zelené; testy na main nekompilují (chybí `kinds`).
- Další krok: QA; samostatný CoreKind pro střední tier až po datech z M6.

## 2026-11-12 — coreglance#51 DVFS tabulky z pmgr-child a MCPUn do P clusteru
- Co: čisté funkce `SoCMetrics.parseDVFS`, `mergeDVFSTables`, `cluster(forChannel:)`; `readDVFSTables` čte `pmgr` i `pmgr-child*` (pmgr první, takže M1–M4 beze změny); `sample()` počítá E→E, P/M→P. Testy nad bajty zaznamenanými na M6 (`DVFSTests`).
- Výsledek: `swift test --disable-sandbox` 86 testů zelených, `swift build` bez varování. Nové testy na base nejdou ani přeložit (funkce neexistují).
- Další krok: ověření na živém M6 (`--dump` ukáže GHz > 0) musí udělat člověk na stroji.
