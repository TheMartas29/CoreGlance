import AppKit

if CommandLine.arguments.contains("--dump") {
    print(Monitor().diagnostics())
    exit(0)
}

// Development aid: renders the menu bar item, popover and settings to PNGs in the given folder.
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated { Snapshotter.render(into: URL(fileURLWithPath: CommandLine.arguments[i + 1])) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
app.run()
