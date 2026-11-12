import Foundation
import IOKit

/// Řádky sekce `--dump` s metadaty IOReport kanálů a typy jader. Čisté funkce, aby šly testovat bez hardwaru.
enum DumpFormat {
    /// `ioreport channel: group="Energy Model" subgroup="" name="GPU Energy" unit="mJ"`
    static func channelLine(group: String, subGroup: String, name: String, unit: String) -> String {
        "ioreport channel: group=\"\(group)\" subgroup=\"\(subGroup)\" name=\"\(name)\" unit=\"\(unit)\""
    }

    /// `cpu8 cluster-type=M logical-cpu-id=8`; chybějící hodnota se vypíše jako „?“.
    static func coreLine(id: Int?, clusterType: String?) -> String {
        let i = id.map(String.init) ?? "?"
        let t = (clusterType?.isEmpty ?? true) ? "?" : clusterType!
        return "cpu\(i) cluster-type=\(t) logical-cpu-id=\(i)"
    }

    /// Řádky pro všechna jádra z device tree (`IODeviceTree:/cpus`); prázdné pole, když strom chybí (Intel, sandbox).
    static func coreLines() -> [String] {
        var lines: [String] = []
        var iterator: io_iterator_t = 0
        let root = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard root != 0 else { return [] }
        defer { IOObjectRelease(root) }
        guard IORegistryEntryGetChildIterator(root, kIODeviceTreePlane, &iterator) == kIOReturnSuccess else { return [] }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let type = IORegistry.data(entry, "cluster-type").flatMap { String(bytes: $0.prefix { $0 != 0 }, encoding: .ascii) }
            lines.append(coreLine(id: IORegistry.int(entry, "logical-cpu-id"), clusterType: type))
        }
        return lines
    }
}
