import SwiftUI

struct PopoverView: View {
    @ObservedObject var monitor: Monitor
    @ObservedObject var prefs: Preferences
    /// Tallest the popover may get on the current screen; the content scrolls beyond it.
    var maxHeight: CGFloat = 700
    /// False when rendered offscreen (--snapshot): AppKit-backed buttons cannot be drawn there.
    var interactive = true
    @State private var showSettings = false
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(showSettings ? "Settings" : monitor.chip).font(.headline)
                Spacer()
                if interactive {
                    Button { showSettings.toggle() } label: {
                        Image(systemName: showSettings ? "chevron.backward" : "gearshape")
                    }
                    .buttonStyle(.borderless)
                    .help(showSettings ? "Back" : "Settings")
                } else {
                    Image(systemName: "gearshape").foregroundStyle(Color.accentColor)
                }
            }
            Divider()
            if interactive {
                ScrollView {
                    page.background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: $0.size.height) })
                }
                .frame(height: min(contentHeight, maxHeight))
                .onPreferenceChange(HeightKey.self) { contentHeight = $0 }
            } else {
                page
            }
            Divider()
            HStack {
                Link(destination: URL(string: "https://github.com/TheMartas29/CoreGlance")!) {
                    Text(appTitle).underline()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Open CoreGlance on GitHub")
                Spacer()
                if interactive {
                    Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless).keyboardShortcut("q")
                } else {
                    Text("Quit").foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    /// "CoreGlance v0.2.2"; the version is missing when run outside the app bundle (swift run).
    private var appTitle: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version.map { "CoreGlance v\($0)" } ?? "CoreGlance"
    }

    @ViewBuilder private var page: some View {
        if showSettings {
            SettingsView(prefs: prefs, snapshot: monitor.snapshot, monitor: monitor)
        } else {
            StatsView(s: monitor.snapshot, histories: monitor.histories, prefs: prefs)
        }
    }
}

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct StatsView: View {
    let s: Snapshot
    let histories: Histories
    let prefs: Preferences

    /// Temperature graph tint follows the same warning/critical levels as the text value.
    private func temperatureTint(_ m: Metric, _ history: History) -> Color {
        switch prefs.colorize ? prefs.severity(m, value: history.samples.last?.value) : .normal {
        case .critical: return WarningPalette.critical
        case .warning: return WarningPalette.warning
        case .normal: return .accentColor
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Section(title: "CPU", symbol: "cpu") {
                Row("Usage", Format.percent(s.cpu))
                if prefs.showHistory { SparklineView(history: histories.cpu, range: Sparkline.percentRange, tint: .accentColor, label: "CPU usage, last 5 minutes") }
                if let p = s.cpuP { Row("P-cores", Format.percent(p) + freq(s.soc?.pCluster)) }
                if let e = s.cpuE { Row("E-cores", Format.percent(e) + freq(s.soc?.eCluster)) }
                if s.soc == nil, let ghz = s.nominalGHz { Row("Base frequency", String(format: "%.2f GHz", ghz)) }
                CoreBars(cores: s.cores)
                Row("Temperature", temps(s.thermals.cpu))
                // The graph always plots the sensor average, even when the bar is set to max (deliberate).
                if prefs.showHistory, s.thermals.cpu != nil {
                    SparklineView(history: histories.cpuTemperature, range: Sparkline.autoRange(histories.cpuTemperature.values),
                                  tint: temperatureTint(.cpuTemperature, histories.cpuTemperature), label: "CPU temperature, last 5 minutes")
                }
                if let w = s.soc?.cpuWatts { Row("Power", Format.watts(w)) }
            }
            Section(title: "GPU", symbol: Metric.gpu.symbol) {
                Row("Usage", Format.percent(s.gpu))
                if prefs.showHistory, s.gpu != nil { SparklineView(history: histories.gpu, range: Sparkline.percentRange, tint: .accentColor, label: "GPU usage, last 5 minutes") }
                if let mhz = s.soc?.gpuMHz { Row("Frequency", Format.mhz(mhz) + (s.soc?.gpuMaxMHz.map { " / \(Int($0))" } ?? "")) }
                Row("Temperature", temps(s.thermals.gpu))
                if let w = s.soc?.gpuWatts { Row("Power", Format.watts(w)) }
            }
            Section(title: "Memory", symbol: "memorychip") {
                Row("Used", "\(Format.gigabytes(s.memory.used)) of \(Format.gigabytes(s.memory.total))")
                Bar(value: s.memory.used / max(s.memory.total, 1), tint: pressureColor)
                if prefs.showHistory { SparklineView(history: histories.memory, range: Sparkline.percentRange, tint: pressureColor, label: "Memory used, last 5 minutes") }
                Row("App / Wired / Compressed", [s.memory.app, s.memory.wired, s.memory.compressed].map { String(format: "%.1f", $0 / 1_073_741_824) }.joined(separator: " / ") + " GB")
                Row("Cached files", Format.gigabytes(s.memory.cached))
                Row("Swap", "\(Format.gigabytes(s.memory.swapUsed)) of \(Format.gigabytes(s.memory.swapTotal))")
                Row("Pressure", s.memory.pressure >= 4 ? "Critical" : s.memory.pressure >= 2 ? "Warning" : "Normal")
            }
            Section(title: "Disk", symbol: "internaldrive") {
                Row("Free", String(format: "%.0f GB of %.0f GB", s.disk.free / 1e9, s.disk.total / 1e9))
                Bar(value: 1 - s.disk.free / max(s.disk.total, 1), tint: s.disk.free < 20e9 ? .orange : .accentColor)
                if let io = s.diskIO { Row("Activity", Format.diskActivity(read: io.read, write: io.write)) }
                if Sparkline.showsRateGraph(showHistory: prefs.showHistory, available: s.diskIO != nil) {
                    let range = Sparkline.rateRange(histories.diskRead.values, histories.diskWrite.values)
                    SparklineView(history: histories.diskRead, range: range, tint: GraphPalette.primary, label: "Disk read speed, last 5 minutes")
                    SparklineView(history: histories.diskWrite, range: range, tint: GraphPalette.secondary, label: "Disk write speed, last 5 minutes")
                }
            }
            let processRows = prefs.showTopProcesses ? ProcessReader.rows(s.topProcesses) : []
            if !processRows.isEmpty {
                Section(title: "Top processes", symbol: "list.number") {
                    ForEach(Array(processRows.enumerated()), id: \.offset) { _, r in Row(r.name, r.value) }
                }
            }
            if s.battery.present {
                Section(title: "Battery", symbol: "battery.75percent") {
                    Row("Charge", Format.percent(s.battery.percent) + " · " + batteryState)
                    Row("Temperature", Format.temperature(s.batteryTemperature)).emphasized(hot: (s.batteryTemperature ?? 0) >= 40)
                    if let h = s.battery.health { Row("Health", Format.percent(h) + (s.battery.cycleCount.map { " · \($0) cycles" } ?? "")) }
                    if let w = s.battery.power, abs(w) >= 0.05 { Row(w >= 0 ? "Charging power" : "Discharge power", Format.watts(abs(w))) }
                }
            }
            Section(title: "Power & sensors", symbol: "bolt") {
                if let w = s.thermals.systemWatts ?? s.battery.systemPowerIn { Row("System power", Format.watts(w)) }
                if let w = s.soc?.aneWatts, w > 0.01 { Row("Neural Engine", Format.watts(w)) }
                if let w = s.soc?.dramWatts { Row("DRAM", Format.watts(w)) }
                if let t = s.thermals.ssd { Row("SSD temperature", Format.temperature(t)) }
                ForEach(Array(s.thermals.fans.enumerated()), id: \.offset) { i, fan in
                    Row("Fan \(i + 1)", "\(Int(fan.rpm)) rpm")
                }
                Row("Thermal state", s.thermalState.fullName).emphasized(severity: s.thermalState.severity)
                Row("Network", "↓ \(Format.rate(s.network.down))/s  ↑ \(Format.rate(s.network.up))/s")
                if Sparkline.showsRateGraph(showHistory: prefs.showHistory, available: true) {
                    let range = Sparkline.rateRange(histories.networkDown.values, histories.networkUp.values)
                    SparklineView(history: histories.networkDown, range: range, tint: GraphPalette.primary, label: "Download speed, last 5 minutes")
                    SparklineView(history: histories.networkUp, range: range, tint: GraphPalette.secondary, label: "Upload speed, last 5 minutes")
                }
            }
        }
    }

    private func freq(_ c: ClusterFrequency?) -> String {
        guard let c, c.mhz > 0 else { return "" }
        return " · " + Format.ghz(c.mhz)
    }

    private func temps(_ r: Reading?) -> String {
        guard let r else { return "–" }
        return "\(Format.temperature(r.average)) avg · \(Format.temperature(r.max)) max"
    }

    private var batteryState: String {
        let b = s.battery
        let time = Format.duration(minutes: b.minutesRemaining)
        if b.charging { return "Charging" + (time.map { ", \($0) to full" } ?? "") }
        if b.pluggedIn { return b.fullyCharged ? "Charged" : "On AC, not charging" }
        return "On battery" + (time.map { ", \($0) left" } ?? "")
    }

    private var pressureColor: Color {
        s.memory.pressure >= 4 ? MemoryPalette.critical : s.memory.pressure >= 2 ? MemoryPalette.warning : MemoryPalette.normal
    }
}

private struct Section<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
            content
        }
    }
}

private struct Row: View {
    let label: String
    let value: String
    var hot = false
    var critical = false

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    func emphasized(hot: Bool) -> Row {
        var r = self
        r.hot = hot
        return r
    }

    func emphasized(severity: Severity) -> Row {
        var r = self
        r.hot = severity == .warning
        r.critical = severity == .critical
        return r
    }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(critical ? WarningPalette.critical : hot ? WarningPalette.warning : .primary)
                .fontWeight(critical || hot ? .semibold : .regular)
        }
        .font(.callout)
    }
}

private struct Bar: View {
    let value: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 5)
    }
}

/// Line chart of the last five minutes; drawn only from two samples on. Width follows the parent (no fixed width).
private struct SparklineView: View {
    let history: History
    let range: ClosedRange<Double>
    let tint: Color
    let label: String

    var body: some View {
        if let now = history.samples.last?.time, history.samples.count >= 2 {
            let pts = Sparkline.points(history.samples, now: now, range: range)
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                    Path { path in
                        for (i, p) in pts.enumerated() {
                            let point = CGPoint(x: p.x * geo.size.width, y: (1 - p.y) * geo.size.height)
                            i == 0 ? path.move(to: point) : path.addLine(to: point)
                        }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }
            .frame(height: 24)
            .accessibilityLabel(label)
        }
    }
}

/// One small vertical bar per logical core; P-cores in blue, E-cores in green.
private struct CoreBars: View {
    let cores: [(kind: CoreKind, load: Double)]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(cores.enumerated()), id: \.offset) { _, core in
                VStack(spacing: 2) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(.quaternary)
                        RoundedRectangle(cornerRadius: 2).fill(core.kind == .efficiency ? Color.green : Color.blue)
                            .frame(height: 28 * min(max(core.load, 0), 1))
                    }
                    .frame(height: 28)
                    Text(core.kind.rawValue).font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
