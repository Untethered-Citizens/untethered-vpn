import Foundation

/// The log the Tunnel Log screen shows: short lines from the app and the
/// tunnel extension, redacted before they're written. Each process writes
/// its own file in the App Group container, so the two never write the same
/// file; the screen merges them. Each file keeps its newest `limit` lines.
final class TunnelLog: @unchecked Sendable {

    enum Source: String, Sendable, CaseIterable {
        case app = "App"
        case tunnel = "Tunnel"
    }

    struct Line: Equatable, Sendable {
        let date: Date
        let source: Source
        let text: String
    }

    static let limit = 500

    private let directory: URL
    private let defaults: UserDefaults?
    private let source: Source
    // Guards `redactor` and the file: the extension logs from several queues
    private let lock = NSLock()
    private var redactor = LogRedactor()

    init(directory: URL, defaults: UserDefaults?, source: Source) {
        self.directory = directory
        self.defaults = defaults
        self.source = source
    }

    /// The log in the App Group container, or nil if this build has no App
    /// Group (an unsigned simulator build).
    convenience init?(configuration: AppConfiguration, source: Source) {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: configuration.appGroupID)
        else { return nil }
        // Library/Application Support, which tvOS doesn't purge like Caches
        let directory = container.appending(path: "Library/Application Support/TunnelLog", directoryHint: .isDirectory)
        self.init(directory: directory, defaults: UserDefaults(suiteName: configuration.appGroupID), source: source)
    }

    /// The server host names to hide from now on.
    func setHosts(_ hosts: [String]) {
        lock.withLock { redactor.hosts = hosts }
    }

    /// Redacts a line and adds it to this process's file.
    func add(_ text: String, date: Date = .now) {
        lock.withLock {
            // One line per entry: tabs and newlines would break the file's format
            let clean = redactor.redact(text)
                .replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            var lines = Self.read(file(for: source)).filter { $0.date > clearedAt }
            lines.append(Line(date: date, source: source, text: clean))
            write(Array(lines.suffix(Self.limit)))
        }
    }

    /// Every source's lines since the last Clear, newest first, at most `limit`.
    func lines() -> [Line] {
        let cutoff = clearedAt
        let all = Source.allCases.flatMap { Self.read(file(for: $0)) }.filter { $0.date > cutoff }
        return Array(all.sorted { $0.date > $1.date }.prefix(Self.limit))
    }

    /// Hides every line written before now. The other process's file is
    /// removed too if possible; either way its old lines are filtered out.
    func clear(now: Date = .now) {
        lock.withLock {
            defaults?.set(now.timeIntervalSinceReferenceDate, forKey: Self.clearedKey)
            for source in Source.allCases {
                try? FileManager.default.removeItem(at: file(for: source))
            }
        }
    }

    // MARK: - Storage

    private static let clearedKey = "tunnelLogClearedAt"

    private var clearedAt: Date {
        Date(timeIntervalSinceReferenceDate: defaults?.double(forKey: Self.clearedKey) ?? 0)
    }

    private func file(for source: Source) -> URL {
        directory.appending(path: "\(source.rawValue.lowercased()).log")
    }

    /// Each line is `<seconds since 2001>\t<text>`.
    private static func read(_ url: URL) -> [Line] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let source = Source.allCases.first { url.lastPathComponent.hasPrefix($0.rawValue.lowercased()) } ?? .app
        return text.split(separator: "\n").compactMap { row in
            let parts = row.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let seconds = Double(parts[0]) else { return nil }
            return Line(date: Date(timeIntervalSinceReferenceDate: seconds), source: source, text: String(parts[1]))
        }
    }

    private func write(_ lines: [Line]) {
        let text = lines.map { "\($0.date.timeIntervalSinceReferenceDate)\t\($0.text)\n" }.joined()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file(for: source), options: .atomic)
        } catch {
            // A log that can't be written mustn't stop the tunnel; the system log still has it
        }
    }
}
