# Changelog

## [Nevydáno]

### Opraveno

- Výstražné hodnoty (oranžová, červená) v popoveru jsou ve světlém režimu tmavší a dobře čitelné (kontrast aspoň 4,5:1); v tmavém režimu zůstávají beze změny. (#67)

## [0.3.4] – 2026-11-12

### Přidáno

- `--dump` nově vypíše seznam všech IOReport kanálů (skupina, podskupina, název, jednotka) a typ každého jádra; pomůže opravit údaj o příkonu CPU na nových čipech. Stávající řádky výpisu se nemění. (#55)

## [0.3.3] – 2026-11-12

### Opraveno

- Výpočet paměti aplikací už nespadne, když systém hlásí víc vymazatelné paměti než vnitřní paměti; hodnota se ořízne na nulu. (#53)

## [0.3.2] – 2026-11-12

### Opraveno

- Záporné hodnoty senzorů typu si8 se čtou správně (např. -1 místo 255). (#52)

## [0.3.1] – 2026-11-12

### Opraveno

- Na čipech s třetím typem jader (cluster-type „M“) se jádra už neoznačují „?“, ale počítají se k výkonným (P). Určení typu jádra je oddělené od čtení systému a pokryté testy. (#54)

## [0.3.0] – 2026-11-12

### Opraveno

- Frekvence CPU a GPU se čtou i z tabulek v uzlech `pmgr-child` a jádra „MCPU“ se počítají do výkonného clusteru, takže na Apple M6 nemají být frekvence nulové (ověření na živém M6 zbývá). Na M1–M4 se nic nemění. (#51)

## [0.2.10] – 2026-11-12

### Změněno

- Výpočet rychlosti sítě a využití paměti je oddělený od čtení systému a pokrytý testy; zobrazené hodnoty se nemění. (#38)

## [0.2.9] – 2026-11-12

### Změněno

- Čtení stavu baterie je oddělené od systémových volání a pokryté testy; zobrazení se nemění. (#37)

## [0.2.8] – 2026-11-12

### Změněno

- Vydání verze teď automaticky hlídá, že se tag a nejvyšší sekce CHANGELOGu shodují; poznámky k vydání na GitHubu se berou z CHANGELOGu (#36).

## [0.2.7] – 2026-11-12

### Opraveno

- Číslo verze v aplikaci se bere jen z tagů tvaru `v<číslo>`, úvodní „v“ se ořezává i u ručně zadané verze a nebezpečné hodnoty se odmítnou; skript verze je hlídán testy v CI (#32).

## [0.2.6] – 2026-11-12

### Změněno

- Přepínač v Nastavení se jmenuje „Check for updates automatically“, protože zatím jen hledá nové verze a neinstaluje je. Dříve nalezená nabídka aktualizace už nezmizí, když GitHub vrátí nečitelnou odpověď; odkaz na vydání se ověřuje jako ostatní odkazy a tag s velkým „V“ se zobrazí bez předpony (#30).

## [0.2.5] – 2026-11-11

### Změněno

- Popisek přepínače barvení v Nastavení zmiňuje i tepelný stav; zvýrazněné hodnoty v popoveru jsou tučnější pro lepší čitelnost; README uvádí správný počet metrik (#11).

## [0.2.4] – 2026-11-11

### Opraveno

- Okno O aplikaci a Nastavení ukazují skutečnou verzi. (#28)

## [0.2.3] – 2026-11-11

### Přidáno

- Kontrola nových verzí: CoreGlance při spuštění a pak nejvýše jednou za 24 hodin zkontroluje nové vydání na GitHubu a v Nastavení ukáže „Update available: X.Y.Z“ s odkazem na vydání. Kontrolu vypnete přepínačem „Automatically install updates“ v Nastavení → General (pak aplikace nedělá žádné síťové dotazy). Samotná automatická instalace přijde v další verzi (#18).
- Nová metrika „Tepelný stav“ (Thermal state) v menu baru a v popoveru: ukáže, zda vás macOS kvůli horku zpomaluje (OK / FAIR / HOT / CRIT, v popoveru Nominal / Fair / Serious / Critical). Při Fair se text zbarví oranžově, při Serious a Critical červeně. Ve výchozím nastavení je vypnutá, zapnete ji v Nastavení ve skupině System; stav je i ve výpisu `--dump` (#9).

### Opraveno

- Výpočet zátěže CPU už nespadne při neúplných datech z jádra systému; vrátí 0 % (#6).

### Změněno

- Automatické sestavení na GitHubu teď u každého pull requestu spouští `swift build` (selže při jakémkoli varování) a `swift test`; oprávnění k zápisu má jen krok, který vydává release (#12).
- Přibyla automatická sada testů (`swift test`) pro formátování hodnot, prahy upozornění a čtení senzorů; chování aplikace se nemění (#1).
- Výběr teplotních senzorů a výpočet průměru/maxima teplot je oddělený od hardwaru a pokrytý testy (ARM i Intel, ořez nesmyslných hodnot); chování aplikace se nemění (#14).

## 0.2.2 — 2026-10-22

- Swap and compressed memory show only their glyph (no "SWAP"/"ZIP" label). Swap uses up/down arrows, and network uses the globe glyph.
- Memory, swap, compressed and disk values read "GB" instead of "G".

## 0.2.1 — 2026-10-22

- Fixed a crash: an appearance observer redrew the menu bar in an endless loop until the text system failed.
- Fixed a crash when drawing colored values in SF Mono.
- Alerts now color temperatures only. The battery defaults changed to 35 °C (warning) and 40 °C (critical), based on Apple's 10–35 °C operating range.

## 0.2.0 — 2026-10-22

- Alerts: menu bar values turn orange or red at warning and critical levels. The defaults are researched (see RESEARCH.md) and adjustable in Settings.
- Settings and the menu bar only offer metrics this Mac can actually read (e.g. no fan on a MacBook Air).
- Metrics are ordered and grouped by hardware component.
- CPU, GPU and SSD temperatures use the component's glyph. Frequencies show units ("3.05GHz").

## 0.1.1 — 2026-10-22

- Even spacing between menu bar items: gaps are now measured from the painted pixels, so glyph side space and characters like "°" no longer make some gaps look wider.

## 0.1.0 — 2026-10-22

First public release.

- Menu bar meters with 19 selectable metrics: CPU usage, P/E-core usage, P/E-core frequency, GPU usage and frequency, memory used, memory pressure, compressed memory, swap, free disk space, CPU/GPU/battery/SSD temperature, battery charge, system power, fan speed and network speed.
- Popover with full readout: per-core bars, cluster GHz, temperatures (average and max), memory breakdown, disk, battery health, cycles and power, and component power (CPU, GPU, ANE, DRAM).
- Settings: metric selection, SF Pro / SF Mono font, glyphs, labels, °C/°F, average or hottest temperature, refresh interval, launch at login.
- Apple Silicon M1–M4 support, with automatic handling of the M4 kHz DVFS tables. Best-effort Intel support.
- `--dump` diagnostics and `--snapshot` screenshot rendering.
