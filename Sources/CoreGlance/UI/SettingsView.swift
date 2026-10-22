import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Show in menu bar").font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Metric.allCases) { metric in
                    Toggle(isOn: Binding(get: { prefs.isEnabled(metric) }, set: { prefs.set(metric, $0) })) {
                        Label(metric.title, systemImage: metric.symbol)
                    }
                }
            }
            Divider()
            Toggle("Show glyphs", isOn: $prefs.showGlyphs)
            Toggle("Label CPU/GPU temperatures", isOn: $prefs.captionTemperatures)
            Toggle("Memory as percent", isOn: $prefs.memoryAsPercent)
            Picker("Temperature", selection: $prefs.unit) {
                Text("°C").tag(TemperatureUnit.celsius)
                Text("°F").tag(TemperatureUnit.fahrenheit)
            }
            .pickerStyle(.segmented)
            Picker("Refresh every", selection: $prefs.interval) {
                ForEach([1.0, 2, 3, 5, 10], id: \.self) { Text("\(Int($0)) s").tag($0) }
            }
            Toggle("Launch at login", isOn: Binding(get: { prefs.launchAtLogin }, set: { prefs.launchAtLogin = $0 }))
        }
        .toggleStyle(.checkbox)
        .font(.callout)
    }
}
