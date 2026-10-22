import Foundation

/// Thin wrapper around Apple's private libIOReport (the same source powermetrics,
/// macmon and MX Power Gadget use). Loaded with dlopen so the app still launches —
/// just without these metrics — if the library or a symbol ever disappears.
final class IOReport {
    private typealias CopyChannels = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private typealias MergeChannels = @convention(c) (CFMutableDictionary, CFMutableDictionary, CFTypeRef?) -> Void
    private typealias CreateSubscription = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?) -> OpaquePointer?
    private typealias CreateSamples = @convention(c) (OpaquePointer, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias GetString = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias GetInt = @convention(c) (CFDictionary, Int32) -> Int64
    private typealias GetCount = @convention(c) (CFDictionary) -> Int32
    private typealias GetStateName = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?

    private let createSamples: CreateSamples
    private let createDelta: CreateDelta
    private let getGroup: GetString
    private let getSubGroup: GetString
    private let getChannel: GetString
    private let getUnit: GetString
    private let simpleValue: GetInt
    private let stateCount: GetCount
    private let stateName: GetStateName
    private let stateResidency: GetInt

    private let subscription: OpaquePointer
    private let channels: CFMutableDictionary
    private var previous: (sample: CFDictionary, time: Date)?

    struct Channel {
        let group: String, subGroup: String, name: String, unit: String
        let raw: CFDictionary
    }

    init?(groups: [(String, String?)]) {
        guard let lib = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else { return nil }
        func sym<T>(_ name: String, _: T.Type) -> T? {
            dlsym(lib, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard let copy = sym("IOReportCopyChannelsInGroup", CopyChannels.self),
              let merge = sym("IOReportMergeChannels", MergeChannels.self),
              let subscribe = sym("IOReportCreateSubscription", CreateSubscription.self),
              let samples = sym("IOReportCreateSamples", CreateSamples.self),
              let delta = sym("IOReportCreateSamplesDelta", CreateDelta.self),
              let group = sym("IOReportChannelGetGroup", GetString.self),
              let subGroup = sym("IOReportChannelGetSubGroup", GetString.self),
              let channel = sym("IOReportChannelGetChannelName", GetString.self),
              let unit = sym("IOReportChannelGetUnitLabel", GetString.self),
              let simple = sym("IOReportSimpleGetIntegerValue", GetInt.self),
              let count = sym("IOReportStateGetCount", GetCount.self),
              let name = sym("IOReportStateGetNameForIndex", GetStateName.self),
              let residency = sym("IOReportStateGetResidency", GetInt.self)
        else { return nil }

        var merged: CFMutableDictionary?
        for (g, sg) in groups {
            guard let chans = copy(g as CFString, sg as CFString?, 0, 0, 0)?.takeRetainedValue() else { continue }
            if let m = merged { merge(m, chans, nil) } else { merged = chans }
        }
        guard let desired = merged else { return nil }
        let mutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, CFDictionaryGetCount(desired), desired)!
        var subbed: Unmanaged<CFMutableDictionary>?
        guard let sub = subscribe(nil, mutable, &subbed, 0, nil), let subbedChannels = subbed?.takeRetainedValue() else { return nil }

        subscription = sub
        channels = subbedChannels
        createSamples = samples; createDelta = delta
        getGroup = group; getSubGroup = subGroup; getChannel = channel; getUnit = unit
        simpleValue = simple; stateCount = count; stateName = name; stateResidency = residency
    }

    /// Returns the channels accumulated since the previous call plus the elapsed time.
    func sample() -> (channels: [Channel], seconds: Double)? {
        guard let current = createSamples(subscription, channels, nil)?.takeRetainedValue() else { return nil }
        let now = Date()
        defer { previous = (current, now) }
        guard let prev = previous,
              let delta = createDelta(prev.sample, current, nil)?.takeRetainedValue(),
              let items = (delta as NSDictionary)["IOReportChannels"] as? [NSDictionary]
        else { return nil }

        let result = items.map { item -> Channel in
            let d = item as CFDictionary
            return Channel(group: getGroup(d)?.takeUnretainedValue() as String? ?? "",
                           subGroup: getSubGroup(d)?.takeUnretainedValue() as String? ?? "",
                           name: getChannel(d)?.takeUnretainedValue() as String? ?? "",
                           unit: getUnit(d)?.takeUnretainedValue() as String? ?? "",
                           raw: d)
        }
        return (result, now.timeIntervalSince(prev.time))
    }

    func integer(_ c: Channel) -> Int64 { simpleValue(c.raw, 0) }

    func states(_ c: Channel) -> [(name: String, residency: Int64)] {
        (0..<max(0, stateCount(c.raw))).map { i in
            (stateName(c.raw, i)?.takeUnretainedValue() as String? ?? "", stateResidency(c.raw, i))
        }
    }
}
