import Foundation
import IOKit

/// Minimal reader for the System Management Controller (AppleSMC user client).
/// Works without root on Intel and Apple Silicon. The kernel struct is handled as a raw
/// 80-byte buffer with explicit C offsets so Swift struct layout can never break it.
final class SMC {
    private var connection: io_connect_t = 0

    // SMCKeyData_t offsets (C layout, 80 bytes total)
    private enum Off {
        static let key = 0, dataSize = 28, dataType = 32, result = 40, data8 = 42, data32 = 44, bytes = 48
    }
    private enum Cmd: UInt8 { case readKey = 5, readIndex = 8, readKeyInfo = 9 }
    private static let structSize = 80

    struct KeyInfo { let size: UInt32; let type: String }
    private var infoCache: [String: KeyInfo] = [:]

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit { if connection != 0 { IOServiceClose(connection) } }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: Self.structSize)
        var outSize = Self.structSize
        let kr = input.withUnsafeBytes { inPtr in
            output.withUnsafeMutableBytes { outPtr in
                IOConnectCallStructMethod(connection, 2, inPtr.baseAddress, Self.structSize, outPtr.baseAddress, &outSize)
            }
        }
        guard kr == kIOReturnSuccess, output[Off.result] == 0 else { return nil }
        return output
    }

    private static func fourCC(_ s: String) -> UInt32 {
        s.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func string(_ v: UInt32) -> String {
        String(bytes: [UInt8(v >> 24 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)], encoding: .ascii) ?? "????"
    }

    private static func put32(_ v: UInt32, _ buf: inout [UInt8], at o: Int) {
        withUnsafeBytes(of: v) { for i in 0..<4 { buf[o + i] = $0[i] } }  // native endian, like the C struct
    }

    private static func get32(_ buf: [UInt8], at o: Int) -> UInt32 {
        buf[o..<o + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }

    func keyInfo(_ key: String) -> KeyInfo? {
        if let cached = infoCache[key] { return cached }
        var input = [UInt8](repeating: 0, count: Self.structSize)
        Self.put32(Self.fourCC(key), &input, at: Off.key)
        input[Off.data8] = Cmd.readKeyInfo.rawValue
        guard let out = call(input) else { return nil }
        let info = KeyInfo(size: Self.get32(out, at: Off.dataSize), type: Self.string(Self.get32(out, at: Off.dataType)))
        infoCache[key] = info
        return info
    }

    func bytes(_ key: String) -> (KeyInfo, [UInt8])? {
        guard let info = keyInfo(key), info.size > 0, info.size <= 32 else { return nil }
        var input = [UInt8](repeating: 0, count: Self.structSize)
        Self.put32(Self.fourCC(key), &input, at: Off.key)
        Self.put32(info.size, &input, at: Off.dataSize)
        input[Off.data8] = Cmd.readKey.rawValue
        guard let out = call(input) else { return nil }
        return (info, Array(out[Off.bytes..<Off.bytes + Int(info.size)]))
    }

    /// Decodes the common numeric SMC data types into a Double.
    func value(_ key: String) -> Double? {
        guard let (info, b) = bytes(key) else { return nil }
        switch info.type {
        case "flt " where b.count >= 4:
            return Double(b.withUnsafeBytes { $0.loadUnaligned(as: Float32.self) })
        case "sp78" where b.count >= 2:
            return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256
        case "fpe2" where b.count >= 2:
            return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4
        case "ui8 ", "si8 ":
            return b.first.map { Double($0) }
        case "ui16" where b.count >= 2:
            return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case "ui32" where b.count >= 4:
            return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        default:
            return nil
        }
    }

    /// Enumerates every key the SMC exposes (used once at startup for sensor discovery).
    func allKeys() -> [String] {
        guard let count = value("#KEY"), count > 0 else { return [] }
        var keys: [String] = []
        keys.reserveCapacity(Int(count))
        for i in 0..<UInt32(count) {
            var input = [UInt8](repeating: 0, count: Self.structSize)
            input[Off.data8] = Cmd.readIndex.rawValue
            Self.put32(i, &input, at: Off.data32)
            if let out = call(input) { keys.append(Self.string(Self.get32(out, at: Off.key))) }
        }
        return keys
    }
}
