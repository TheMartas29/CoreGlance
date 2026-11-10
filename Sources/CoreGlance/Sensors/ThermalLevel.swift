import Foundation

/// System thermal state from the public `ProcessInfo.thermalState` (no privileges needed).
/// `unknown` covers "not read yet" and values added by future macOS versions.
enum ThermalLevel: Equatable {
    case nominal, fair, serious, critical, unknown

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .unknown
        }
    }

    /// Short text for the menu bar.
    var shortText: String {
        switch self {
        case .nominal: return "OK"
        case .fair: return "FAIR"
        case .serious: return "HOT"
        case .critical: return "CRIT"
        case .unknown: return "–"
        }
    }

    /// Full name for the popover.
    var fullName: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        case .unknown: return "–"
        }
    }

    /// The state is discrete, so it has fixed levels instead of user thresholds.
    var severity: Severity {
        switch self {
        case .nominal, .unknown: return .normal
        case .fair: return .warning
        case .serious, .critical: return .critical
        }
    }
}
