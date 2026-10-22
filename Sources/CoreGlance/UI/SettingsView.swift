import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Show in menu bar").font(.subheadline.weight(.semibold))
            ForEach(MetricGroup.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.rawValue.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Metric.allCases.filter { $0.group == group }) { metric in
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
            Text("General").font(.subheadline.weight(.semibold))
            Picker("Refresh every", selection: $prefs.interval) {
                ForEach([1.0, 2, 3, 5, 10], id: \.self) { Text("\(Int($0)) s").tag($0) }
            }
            Toggle("Launch at login", isOn: Binding(get: { prefs.launchAtLogin }, set: { prefs.launchAtLogin = $0 }))
        }
        .toggleStyle(.checkbox)
        .font(.callout)
    }
}
