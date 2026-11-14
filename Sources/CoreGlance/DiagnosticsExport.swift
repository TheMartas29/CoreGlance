import Foundation
import AppKit

/// Stav tlačítka „Save diagnostics…“. Čistá logika, aby šla testovat bez UI.
enum DiagnosticsExportState: Equatable {
    case idle
    /// Otevřený NSSavePanel.
    case choosingFile
    /// Diagnostika se generuje na pozadí (trvá ~1 s kvůli dvěma vzorkům).
    case generating
    case saved(fileName: String)
    case failed(message: String)

    /// Tlačítko je neaktivní, dokud běží panel nebo generování.
    var isBusy: Bool { self == .choosingFile || self == .generating }

    /// Krátké potvrzení nebo chyba pod tlačítkem; nil, když není co ukázat.
    var message: String? {
        switch self {
        case .saved(let name): return "Saved \(name)"
        case .failed(let message): return message
        case .idle, .choosingFile, .generating: return nil
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

struct DiagnosticsExportError: LocalizedError, Equatable {
    let reason: String
    var errorDescription: String? { "Couldn't save the diagnostics: \(reason)" }
}

enum DiagnosticsExport {
    /// `CoreGlance-diagnostics-MacBookPro18-3-2026-11-14.txt`. Model (`hw.model`) bez znaků mimo [A-Za-z0-9._-],
    /// aby název nebyl cestou ani nezpůsobil potíže na cizím souborovém systému.
    static func suggestedFileName(model: String?, date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return "CoreGlance-diagnostics-\(sanitizedModel(model))-\(day).txt"
    }

    /// Nepovolené znaky (i celé jejich řady) se nahradí jedním „-“; prázdný výsledek je „Mac“.
    static func sanitizedModel(_ model: String?) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        var out = ""
        for scalar in (model ?? "").unicodeScalars {
            if allowed.contains(scalar) {
                out.unicodeScalars.append(scalar)
            } else if !out.hasSuffix("-") {
                out.append("-")
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return trimmed.isEmpty ? "Mac" : trimmed
    }

    /// Zapíše text atomicky (dočasný soubor + přejmenování), takže po chybě nezůstane napůl zapsaný výpis.
    static func write(_ text: String, to url: URL) throws {
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            throw DiagnosticsExportError(reason: (error as NSError).localizedFailureReason
                ?? error.localizedDescription)
        }
    }
}

/// Spojuje tlačítko, NSSavePanel a generování. Je to singleton, protože transientní popover se při otevření
/// panelu zavře a jeho view zanikne; stav a zápis souboru na něm nesmí záviset.
@MainActor
final class DiagnosticsExporter: ObservableObject {
    static let shared = DiagnosticsExporter()
    @Published private(set) var state = DiagnosticsExportState.idle

    func start(monitor: Monitor) {
        guard !state.isBusy else { return }
        state = .choosingFile
        let panel = NSSavePanel()
        panel.nameFieldStringValue = DiagnosticsExport.suggestedFileName(model: Sysctl.string("hw.model"), date: Date())
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.title = "Save diagnostics"
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else {
                self.state = .idle  // zrušeno: nic se neděje
                return
            }
            self.generate(monitor: monitor, to: url)
        }
    }

    private func generate(monitor: Monitor, to url: URL) {
        state = .generating
        // diagnostics() běží na vlastní frontě Monitoru (queue.sync), takže je z jakéhokoli vlákna bezpečná.
        nonisolated(unsafe) let monitor = monitor
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<Void, Error>
            do { try DiagnosticsExport.write(monitor.diagnostics(), to: url); result = .success(()) }
            catch { result = .failure(error) }
            DispatchQueue.main.async {
                switch result {
                case .success: self.state = .saved(fileName: url.lastPathComponent)
                case .failure(let error): self.state = .failed(message: error.localizedDescription)
                }
            }
        }
    }
}
