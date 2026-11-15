import Foundation
import UserNotifications

/// What an alert is about: one of the four temperatures or one level (rank) of the system thermal state.
enum AlertSubject: Hashable {
    case temperature(Metric)
    case thermalState(Int)
    case memoryPressure
}

/// One temperature reading (°C) together with its severity against the user's thresholds.
struct TemperatureReading: Equatable {
    var metric: Metric
    var celsius: Double
    var severity: Severity
}

/// A notification the tracker decided to send.
enum AlertEvent: Equatable {
    case temperatureCritical(Metric, celsius: Double)
    case thermalState(ThermalLevel)
    /// macOS memory pressure turned critical; bytes in use and installed, for the message.
    case memoryPressureCritical(used: Double, total: Double)
}

/// Pure decision logic: which notifications to send for a stream of readings. No system calls,
/// the time is passed in, so everything is testable.
struct AlertTracker {
    /// Minimum gap between two notifications of the same subject.
    static let cooldown: TimeInterval = 10 * 60

    private var wasCritical: [Metric: Bool] = [:]
    private var lastSent: [AlertSubject: Date] = [:]
    private var thermalRank = 0
    private var memoryWasCritical = false

    private func cooledDown(_ subject: AlertSubject, _ now: Date) -> Bool {
        guard let last = lastSent[subject] else { return true }
        return now.timeIntervalSince(last) >= Self.cooldown
    }

    private static func rank(_ level: ThermalLevel) -> Int {
        switch level {
        case .nominal, .fair, .unknown: return 0
        case .serious: return 1
        case .critical: return 2
        }
    }

    /// Feed one snapshot. A metric absent from `temperatures` counts as not critical.
    /// With `silent` the tracker only follows the current state (used while notifications are off):
    /// it returns nothing and starts no cooldown, so later rises are judged against the real state.
    mutating func update(temperatures: [TemperatureReading], thermalState: ThermalLevel, memoryPressure: Int = 1, memoryUsed: Double = 0, memoryTotal: Double = 0, now: Date, silent: Bool = false) -> [AlertEvent] {
        var events: [AlertEvent] = []
        for metric in Metric.allCases where metric.isTemperature {
            let reading = temperatures.first { $0.metric == metric }
            let critical = reading?.severity == .critical
            if !silent, critical, wasCritical[metric] != true, let reading, cooledDown(.temperature(metric), now) {
                events.append(.temperatureCritical(metric, celsius: reading.celsius))
                lastSent[.temperature(metric)] = now
            }
            wasCritical[metric] = critical
        }
        let rank = Self.rank(thermalState)
        // Cooldown is kept per level (Serious, Critical), so flapping between them cannot repeat a level.
        if !silent, rank > thermalRank, cooledDown(.thermalState(rank), now) {
            events.append(.thermalState(thermalState))
            lastSent[.thermalState(rank)] = now
        }
        thermalRank = rank
        // Memory pressure: only the step into critical (4) counts; warning (2) is not announced.
        let memoryCritical = memoryPressure >= 4
        if !silent, memoryCritical, !memoryWasCritical, cooledDown(.memoryPressure, now) {
            events.append(.memoryPressureCritical(used: memoryUsed, total: memoryTotal))
            lastSent[.memoryPressure] = now
        }
        memoryWasCritical = memoryCritical
        return events
    }
}

/// Notification text (pure function, no system calls).
enum AlertMessage {
    static func make(_ event: AlertEvent, unit: TemperatureUnit) -> (title: String, body: String) {
        switch event {
        case let .temperatureCritical(metric, celsius):
            let value = unit == .celsius ? celsius : celsius * 9 / 5 + 32
            let shown = "\(Int(value.rounded())) \(unit == .celsius ? "°C" : "°F")"
            return ("\(metric.title) is critical", "\(metric.title) reached \(shown) (critical level).")
        case let .memoryPressureCritical(used, total):
            let gb = 1_073_741_824.0
            let percent = total > 0 ? Int((used / total * 100).rounded()) : 0
            return ("Memory pressure is critical",
                    String(format: "macOS reports critical memory pressure: %.1f of %.1f GB in use (%d %%). Close apps you don't need.", used / gb, total / gb, percent))
        case let .thermalState(level):
            return ("Thermal state: \(level.fullName)", "macOS reports a \(level.fullName.lowercased()) thermal state; the Mac may slow down to cool off.")
        }
    }
}

/// Delivery boundary; tests use a fake.
protocol AlertNotifier {
    func requestAuthorization(completion: @escaping (Bool) -> Void)
    func deliver(title: String, body: String)
}

/// Local macOS notifications. Without a bundle identifier (`swift run`) UNUserNotificationCenter
/// would crash, so delivery is silently off.
struct SystemAlertNotifier: AlertNotifier {
    static let shared = SystemAlertNotifier()
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard available else { completion(true); return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func deliver(title: String, body: String) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

/// Connects snapshots to the tracker and the notifier; does nothing while the switch is off.
final class AlertCoordinator {
    private var tracker = AlertTracker()
    private let notifier: AlertNotifier

    init(notifier: AlertNotifier = SystemAlertNotifier.shared) { self.notifier = notifier }

    func process(_ s: Snapshot, prefs: Preferences, now: Date = Date()) {
        guard s.sampled else { return }
        let enabled = prefs.notifyOnCritical
        let readings: [TemperatureReading] = Metric.allCases.filter(\.isTemperature).compactMap { metric in
            guard let c = StatusBarRenderer.temperatureValue(for: metric, in: s, prefs: prefs) else { return nil }
            return TemperatureReading(metric: metric, celsius: c, severity: prefs.severity(metric, value: c))
        }
        // While the switch is off the tracker still follows the state, but silently.
        for event in tracker.update(temperatures: readings, thermalState: s.thermalState, memoryPressure: s.memory.pressure, memoryUsed: s.memory.used, memoryTotal: s.memory.total, now: now, silent: !enabled) {
            let m = AlertMessage.make(event, unit: prefs.unit)
            notifier.deliver(title: m.title, body: m.body)
        }
    }
}
