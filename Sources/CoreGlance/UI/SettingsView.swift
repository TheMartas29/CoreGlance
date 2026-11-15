import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    /// Latest readings; only metrics this Mac can deliver are offered.
    let snapshot: Snapshot
    /// Source of the diagnostics saved by "Save diagnostics…".
    let monitor: Monitor
    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var exporter = DiagnosticsExporter.shared
    @State private var notificationsDenied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Show in menu bar").font(.subheadline.weight(.semibold))
            ForEach(MetricGroup.allCases.filter { !metrics(in: $0).isEmpty }, id: \.self) { group in
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.rawValue.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(metrics(in: group)) { metric in
                        Toggle(isOn: Binding(get: { prefs.isEnabled(metric) }, set: { prefs.set(metric, $0) })) {
                            Label(metric.title, systemImage: metric.symbol)
                        }
                    }
                }
            }

            Divider()
            Text("Appearance").font(.subheadline.weight(.semibold))
            Picker("Font", selection: $prefs.font) {
                Text("SF Pro").tag(BarFont.system)
                Text("SF Mono").tag(BarFont.monospaced)
            }
            .pickerStyle(.segmented)
            Toggle("Show glyphs", isOn: $prefs.showGlyphs)
            Toggle("Show labels (CPU, GPU, SSD…)", isOn: $prefs.showCaptions)
            Toggle("Memory as percent", isOn: $prefs.memoryAsPercent)
            Toggle("Show history graphs", isOn: $prefs.showHistory)
            Toggle("Show top processes", isOn: $prefs.showTopProcesses)

            Divider()
            Text("Temperatures").font(.subheadline.weight(.semibold))
            Picker("Unit", selection: $prefs.unit) {
                Text("°C").tag(TemperatureUnit.celsius)
                Text("°F").tag(TemperatureUnit.fahrenheit)
            }
            .pickerStyle(.segmented)
            Picker("CPU/GPU value", selection: $prefs.temperatureMode) {
                Text("Average").tag(TemperatureMode.average)
                Text("Hottest").tag(TemperatureMode.hottest)
            }
            .pickerStyle(.segmented)

            Divider()
            Text("Alerts").font(.subheadline.weight(.semibold))
            Toggle("Color temperatures and thermal state at warning / critical levels", isOn: $prefs.colorize)
            Toggle("Notify when a temperature or memory pressure is critical", isOn: Binding(
                get: { prefs.notifyOnCritical },
                set: { on in
                    prefs.notifyOnCritical = on
                    notificationsDenied = false
                    if on {
                        SystemAlertNotifier.shared.requestAuthorization { granted in
                            notificationsDenied = !granted
                        }
                    }
                }
            ))
            if prefs.notifyOnCritical && notificationsDenied {
                HStack(spacing: 6) {
                    Text("Notifications are blocked.").font(.caption).foregroundStyle(.secondary)
                    Link("Open System Settings", destination: URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        .font(.caption)
                }
            }
            if prefs.colorize {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Metric.allCases.filter { $0.defaultThreshold != nil && $0.isAvailable(in: snapshot) }) { metric in
                        ThresholdRow(metric: metric, prefs: prefs)
                    }
                    Button("Reset to defaults") { prefs.resetThresholds() }
                        .disabled(prefs.customThresholds.isEmpty)
                }
            }

            Divider()
            Text("General").font(.subheadline.weight(.semibold))
            Picker("Refresh every", selection: $prefs.interval) {
                ForEach([1.0, 2, 3, 5, 10], id: \.self) { Text("\(Int($0)) s").tag($0) }
            }
            Toggle("Launch at login", isOn: Binding(get: { prefs.launchAtLogin }, set: { prefs.launchAtLogin = $0 }))
            Toggle("Check for updates automatically", isOn: $prefs.autoUpdate)
            let blocker = UpdateLogic.autoInstallBlocker(autoUpdate: prefs.autoUpdate, canReplaceSelf: updater.canReplaceSelf)
            Toggle("Install updates automatically", isOn: $prefs.autoInstall)
                .disabled(blocker != nil)
                .padding(.leading, 18)
            Text(blocker ?? "Downloads the new version, checks its SHA-256 and restarts the app. A checksum does not protect against a compromised GitHub account.")
                .font(.caption).foregroundColor(.secondary).padding(.leading, 18)
            HStack(spacing: 6) {
                Button(exporter.state == .generating ? "Saving…" : "Save diagnostics…") { exporter.start(monitor: monitor) }
                    .disabled(exporter.state.isBusy)
                    .help("Saves what CoreGlance sees on this Mac to a file you can attach to a compatibility report. Nothing is sent anywhere.")
                if let message = exporter.state.message {
                    Text(message).font(.caption).foregroundColor(exporter.state.isFailure ? .red : .secondary)
                }
            }
            if let update = updater.availableUpdate {
                HStack(spacing: 6) {
                    Text("Update available: \(update.version)").font(.caption)
                    if updater.canInstall(update) {
                        Button(updater.installState == .installing ? "Installing…" : "Install and restart") {
                            Task { await updater.installAvailable() }
                        }
                        .font(.caption)
                        .disabled(updater.installState == .installing)
                    }
                    Link("Release page", destination: update.pageURL).font(.caption)
                }
                if case .failed(let message) = updater.installState {
                    Text(message).font(.caption).foregroundColor(.red)
                }
            }
        }
        .toggleStyle(.checkbox)
        .font(.callout)
    }

    private func metrics(in group: MetricGroup) -> [Metric] {
        Metric.allCases.filter { $0.group == group && $0.isAvailable(in: snapshot) }
    }
}

/// Warning and critical temperature for one sensor, stored in °C and shown in the chosen unit.
private struct ThresholdRow: View {
    let metric: Metric
    @ObservedObject var prefs: Preferences

    private var fahrenheit: Bool { prefs.unit == .fahrenheit }
    private var unit: String { fahrenheit ? "°F" : "°C" }

    private func shown(_ c: Double) -> Double { fahrenheit ? c * 9 / 5 + 32 : c }
    private func stored(_ v: Double) -> Double { fahrenheit ? (v - 32) * 5 / 9 : v }

    private func binding(_ key: WritableKeyPath<Threshold, Double>) -> Binding<Double> {
        Binding(
            get: { shown(prefs.threshold(metric)?[keyPath: key] ?? 0) },
            set: { value in
                guard var t = prefs.threshold(metric) else { return }
                t[keyPath: key] = min(max(stored(value), 20), 130)
                prefs.setThreshold(metric, t)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.title)
            HStack(spacing: 14) {
                level("Warning", .orange, binding(\.warning))
                level("Critical", .red, binding(\.critical))
            }
        }
    }

    private func level(_ title: String, _ color: Color, _ value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(Int(value.wrappedValue.rounded())) \(unit)").monospacedDigit().frame(minWidth: 52, alignment: .leading)
            Stepper(title, value: value, step: 1).labelsHidden().controlSize(.small)
        }
        .help(title)
    }
}
