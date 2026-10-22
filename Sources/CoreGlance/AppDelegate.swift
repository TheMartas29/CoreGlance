import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = Monitor()
    private let prefs = Preferences.shared
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.behavior = .removalAllowed

        popover.behavior = .transient
        popover.animates = false

        monitor.$snapshot.receive(on: RunLoop.main).sink { [weak self] _ in self?.render() }.store(in: &cancellables)
        prefs.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            // objectWillChange fires before the value is stored; render on the next pass.
            DispatchQueue.main.async { self?.render() }
        }.store(in: &cancellables)
        prefs.$interval.removeDuplicates().sink { [weak self] in self?.monitor.start(interval: $0) }.store(in: &cancellables)
        render()
    }

    private func render() {
        guard let button = statusItem.button else { return }
        if let image = StatusBarRenderer.image(for: monitor.snapshot, prefs: prefs) {
            button.image = image
            button.title = ""
        } else {
            // Nothing selected: keep a small icon so the popover stays reachable.
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "CoreGlance")
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Rebuilt on every open so the height cap matches the screen the menu bar is on.
            let screen = button.window?.screen ?? NSScreen.main
            let maxHeight = (screen?.visibleFrame.height ?? 800) - 110  // header, footer, padding
            let host = NSHostingController(rootView: PopoverView(monitor: monitor, prefs: prefs, maxHeight: maxHeight))
            host.sizingOptions = .preferredContentSize
            popover.contentViewController = host
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
