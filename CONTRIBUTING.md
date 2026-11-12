# Contributing to CoreGlance

Thanks for helping! CoreGlance aims to stay **small, native and dependency-free**, so please keep that in mind when proposing changes.

## Ground rules

- No third-party dependencies. Use Apple frameworks only (AppKit, SwiftUI, IOKit, Foundation).
- No root, helper tools or kernel extensions. Every value must be readable by a normal user process.
- Fail soft. If a sensor is missing on some Mac, show "–" instead of crashing or hiding the whole app.
- Prefer runtime discovery (enumerate SMC keys, read IORegistry tables) over per-chip hard-coded lists.

## Development

```sh
swift build                         # debug build
.build/debug/CoreGlance             # run the menu bar app from the terminal
.build/debug/CoreGlance --dump      # print every sensor reading
.build/debug/CoreGlance --snapshot docs   # regenerate README screenshots
scripts/build-app.sh                # universal .app in ./build
swift scripts/make-icon.swift       # regenerate the app icon
```

Code layout:

- `Sources/CoreGlance/Sensors/` holds one file per data source. Each reader returns a plain struct.
- `Sources/CoreGlance/Update/` checks GitHub Releases: `UpdateLogic.swift` is pure (versions, JSON parsing, schedule), `Updater.swift` does the timer and network.
- `Monitor.swift` polls the readers on a background queue and publishes a `Snapshot`.
- `UI/StatusBarRenderer.swift` draws the menu bar item; `UI/PopoverView.swift` and `UI/SettingsView.swift` are the SwiftUI popover.

## Adding a menu bar metric

1. Add a case to `Metric` in `Preferences.swift` (title, symbol, caption, group).
2. Return its value in `StatusBarRenderer.value(for:in:prefs:)`.
3. If it needs new data, add a reader under `Sensors/` and a field to `Snapshot`.

## Compatibility reports

These are the most valuable contribution. Open a *Compatibility report* issue with your Mac model and the full output of `CoreGlance --dump`. It includes the per-core `cluster-type` lines and the list of IOReport channels, which we need to fix power readings on new chips, so please don't trim it.

## Pull requests

- Keep PRs focused. Match the existing style: small types, comments explaining *why*.
- Make sure `swift build` and `scripts/build-app.sh` succeed with no warnings.
- CI runs `swift build` (failing on any warning) and `swift test` on every push and PR.
- Describe which Mac(s) you tested on.
- Run unit tests with `swift test`. Inside an already sandboxed environment (e.g. an automated agent) use
  `swift test --disable-sandbox`, because SwiftPM's nested `sandbox-exec` fails there.

## Releasing

1. Set `CFBundleShortVersionString` in `Resources/Info.plist` to the new version `X.Y.Z`.
2. Rename `## [Nevydáno]` content into a new top section `## [X.Y.Z] – YYYY-MM-DD` in `CHANGELOG.md` (keep an empty `## [Nevydáno]` above it).
3. Commit, run `sh scripts/check-version.sh X.Y.Z` (tag, Info.plist and CHANGELOG must agree), then tag `vX.Y.Z` and push the tag.
4. CI fails the tag build if the tag and the top CHANGELOG section differ (`check-version.sh --skip-plist`: automated releases bump only the CHANGELOG; the app's Info.plist gets the tag version at build time).
5. On success the release job publishes `CoreGlance.zip` with the CHANGELOG section as notes (`scripts/release-notes.sh`).
