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

/// Události, které mění stav tlačítka. Přechody jsou čistá funkce (`DiagnosticsExportState.next`), aby šly testovat bez UI.
enum DiagnosticsExportEvent: Equatable {
    case panelOpened
    case panelCancelled
    case fileChosen
    case finished(Result<String, DiagnosticsExportError>)  // název uloženého souboru nebo chyba
    case timeout

    static func == (a: Self, b: Self) -> Bool {
        switch (a, b) {
        case (.panelOpened, .panelOpened), (.panelCancelled, .panelCancelled),
             (.fileChosen, .fileChosen), (.timeout, .timeout): return true
        case (.finished(.success(let x)), .finished(.success(let y))): return x == y
        case (.finished(.failure(let x)), .finished(.failure(let y))): return x == y
        default: return false
        }
    }
}

extension DiagnosticsExportState {
    /// choosingFile → generating → saved/failed; zrušení panelu a `timeout` (po `resetDelay`) vrací do .idle.
    /// Událost, která v daném stavu nedává smysl, stav nemění (např. zpožděný `timeout` během nového ukládání).
    func next(_ event: DiagnosticsExportEvent) -> DiagnosticsExportState {
        switch (self, event) {
        case (.idle, .panelOpened), (.saved, .panelOpened), (.failed, .panelOpened): return .choosingFile
        case (.choosingFile, .panelCancelled): return .idle
        case (.choosingFile, .fileChosen): return .generating
        case (.generating, .finished(.success(let name))): return .saved(fileName: name)
        case (.generating, .finished(.failure(let error))): return .failed(message: error.localizedDescription)
        case (.saved, .timeout), (.failed, .timeout): return .idle
        default: return self
        }
    }

    /// Nadpis a text okna s výsledkem; nil u stavů, které se oknem neoznamují.
    var alertContent: (title: String, text: String)? {
        switch self {
        case .saved(let name): return ("Diagnostics saved", name)
        case .failed(let message): return ("Couldn't save the diagnostics", message)
        case .idle, .choosingFile, .generating: return nil
        }
    }
}

/// Oznámení výsledku uživateli. Za protokolem, aby šlo v testu nahradit mockem.
@MainActor
protocol DiagnosticsResultPresenting {
    func present(title: String, text: String, isFailure: Bool)
}

/// NSAlert: viditelný i tehdy, když se transientní popover při otevření NSSavePanel zavřel.
@MainActor
struct AlertDiagnosticsPresenter: DiagnosticsResultPresenting {
    func present(title: String, text: String, isFailure: Bool) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = isFailure ? .warning : .informational
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

/// Spojuje tlačítko, NSSavePanel a generování. Je to singleton, protože transientní popover se při otevření
/// panelu zavře a jeho view zanikne; stav a zápis souboru na něm nesmí záviset.
@MainActor
final class DiagnosticsExporter: ObservableObject {
    /// Za jak dlouho se .saved / .failed vrátí do .idle (zpráva v Nastavení zmizí).
    static let resetDelay: TimeInterval = 10
    typealias Scheduler = (TimeInterval, @escaping @MainActor () -> Void) -> Void

    static let shared = DiagnosticsExporter()
    @Published private(set) var state = DiagnosticsExportState.idle

    private let presenter: DiagnosticsResultPresenting
    private let schedule: Scheduler
    private var generation = 0  // zpožděný reset dřívějšího ukládání nesmí smazat výsledek pozdějšího

    init(presenter: DiagnosticsResultPresenting? = nil,
         schedule: @escaping Scheduler = { delay, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
         }) {
        self.presenter = presenter ?? AlertDiagnosticsPresenter()
        self.schedule = schedule
    }

    /// Použije událost na stav; po dokončení zápisu naplánuje návrat do .idle a oznámí výsledek oknem.
    func apply(_ event: DiagnosticsExportEvent) {
        let new = state.next(event)
        guard new != state else { return }
        state = new
        if case .panelOpened = event { generation += 1 }
        guard case .finished = event, let content = new.alertContent else { return }
        let token = generation
        schedule(Self.resetDelay) { [weak self] in
            guard let self, self.generation == token else { return }
            self.apply(.timeout)
        }
        presenter.present(title: content.title, text: content.text, isFailure: new.isFailure)
    }

    func start(monitor: Monitor) {
        guard !state.isBusy else { return }
        apply(.panelOpened)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = DiagnosticsExport.suggestedFileName(model: Sysctl.string("hw.model"), date: Date())
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.title = "Save diagnostics"
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else {
                self.apply(.panelCancelled)  // zrušeno: nic se neděje
                return
            }
            self.generate(monitor: monitor, to: url)
        }
    }

    private func generate(monitor: Monitor, to url: URL) {
        apply(.fileChosen)
        // diagnostics() běží na vlastní frontě Monitoru (queue.sync), takže je z jakéhokoli vlákna bezpečná.
        nonisolated(unsafe) let monitor = monitor
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<String, DiagnosticsExportError>
            do {
                try DiagnosticsExport.write(monitor.diagnostics(), to: url)
                result = .success(url.lastPathComponent)
            } catch {
                result = .failure(error as? DiagnosticsExportError ?? DiagnosticsExportError(reason: error.localizedDescription))
            }
            DispatchQueue.main.async { self.apply(.finished(result)) }
        }
    }
}
