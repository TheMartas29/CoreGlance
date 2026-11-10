# PROGRESS

## 2026-11-10 — coreglance#1 testovací target a unit testy
- Co: `testTarget` CoreGlanceTests (14 testů XCTest), extrakce čistých funkcí `SoCMetrics.megahertz`, `CPULoad.busyFraction`, `SMC.decode`, `Threshold.severity(of:)`.
- Výsledek: `swift test --disable-sandbox` zelené (<1 s testy); mutace prahu Hz/kHz test shodí.
- Poznámka: v sandboxu agenta je nutné `--disable-sandbox` (vnořený sandbox-exec selže).
- Další krok: CI (T02).
