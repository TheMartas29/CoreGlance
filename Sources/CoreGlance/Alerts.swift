import Foundation
import UserNotifications

/// What an alert is about: one of the four temperatures or the system thermal state.
enum AlertSubject: Hashable {
    case temperature(Metric)
    case thermalState
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
}

/// Pure decision logic: which notifications to send for a stream of readings. No system calls,
/// the time is passed in, so everything is testable.
struct AlertTracker {
    /// Minimum gap between two notifications of the same subject.
    static let cooldown: TimeInterval = 10 * 60

    private var wasCritical: [Metric: Bool] = [:]
    private var lastSent: [AlertSubject: Date] = [:]
    private var thermalRank = 0

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
    mutating func update(temperatures: [TemperatureReading], thermalState: ThermalLevel, now: Date) -> [AlertEvent] {
        var events: [AlertEvent] = []
        for metric in Metric.allCases where metric.isTemperature {
            let reading = temperatures.first { $0.metric == metric }
            let critical = reading?.severity == .critical
            if critical, wasCritical[metric] != true, let reading, cooledDown(.temperature(metric), now) {
                events.append(.temperatureCritical(metric, celsius: reading.celsius))
                lastSent[.temperature(metric)] = now
            }
            wasCritical[metric] = critical
        }
        let rank = Self.rank(thermalState)
        if rank > thermalRank {
            // Serious → Critical is an escalation and always goes out; a fresh rise obeys the cooldown.
            if thermalRank > 0 || cooledDown(.thermalState, now) {
                events.append(.thermalState(thermalState))
                lastSent[.thermalState] = now
            }
        }
        thermalRank = rank
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
        guard prefs.notifyOnCritical, s.sampled else { return }
        let readings: [TemperatureReading] = Metric.allCases.filter(\.isTemperature).compactMap { metric in
            guard let c = StatusBarRenderer.temperatureValue(for: metric, in: s, prefs: prefs) else { return nil }
            return TemperatureReading(metric: metric, celsius: c, severity: prefs.severity(metric, value: c))
        }
        for event in tracker.update(temperatures: readings, thermalState: s.thermalState, now: now) {
            let m = AlertMessage.make(event, unit: prefs.unit)
            notifier.deliver(title: m.title, body: m.body)
        }
    }
}
