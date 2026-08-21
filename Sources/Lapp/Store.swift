import Foundation

struct NoteSummary {
    var url: URL
    var title: String
    var preview: String
    var filed: Date
}

/// Notes are plain markdown files with a small YAML front-matter block. If the app ever
/// dies, the notes are just files.
final class Store {
    static let shared = Store()

    private let fm = FileManager.default
    private let stateURL = Paths.root.appendingPathComponent("state.json")
    private(set) var draftCreated: Date

    private struct State: Codable { var created: Date }

    private init() {
        Paths.ensureRoot()
        if let bytes = try? Data(contentsOf: stateURL),
           let state = try? JSONDecoder().decode(State.self, from: bytes) {
            draftCreated = state.created
        } else {
            draftCreated = Date()
        }
    }

    // MARK: - Draft

    func loadDraft() -> String {
        (try? String(contentsOf: Paths.draft, encoding: .utf8)) ?? ""
    }

    func saveDraft(_ text: String) {
        Paths.ensureRoot()
        try? text.write(to: Paths.draft, atomically: true, encoding: .utf8)
    }

    private func writeState() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let bytes = try? encoder.encode(State(created: draftCreated)) {
            try? bytes.write(to: stateURL, options: .atomic)
        }
    }

    private func startFreshDraft() {
        draftCreated = Date()
        writeState()
        try? "".write(to: Paths.draft, atomically: true, encoding: .utf8)
    }

    // MARK: - File / discard

    /// Commits the pad to history. Returns the written file, or nil if there was nothing to file.
    @discardableResult
    func file(_ text: String) -> URL? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            startFreshDraft()
            return nil
        }
        Paths.ensureRoot()
        let url = uniqueURL(in: Paths.notes, date: draftCreated, title: Self.title(of: text))
        let document = Self.frontMatter(created: draftCreated, filed: Date()) + text
        try? document.write(to: url, atomically: true, encoding: .utf8)
        startFreshDraft()
        return url
    }

    /// Throws the pad away. It lands in trash/ for 30 days -- no UI, just a safety net.
    func discard(_ text: String) {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Paths.ensureRoot()
            let url = uniqueURL(in: Paths.trash, date: draftCreated, title: Self.title(of: text))
            let document = Self.frontMatter(created: draftCreated, filed: Date()) + text
            try? document.write(to: url, atomically: true, encoding: .utf8)
        }
        startFreshDraft()
    }

    // MARK: - History

    func notes() -> [NoteSummary] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let urls = try? fm.contentsOfDirectory(at: Paths.notes,
                                                     includingPropertiesForKeys: keys,
                                                     options: [.skipsHiddenFiles]) else { return [] }
        return urls
            .filter { $0.pathExtension == "md" }
            .map { url in
                let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                let body = Self.stripFrontMatter(raw)
                let modified = (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? Date.distantPast
                return NoteSummary(url: url,
                                   title: Self.title(of: body),
                                   preview: Self.preview(of: body),
                                   filed: Self.filedDate(raw) ?? modified)
            }
            .sorted { $0.filed > $1.filed }
    }

    /// Takes a note off the wall and back onto the pad. It leaves history so a note can
    /// never exist in two places at once; the pad's ✓ puts it back, ✕ bins it.
    func take(_ note: NoteSummary) -> String {
        let raw = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
        let body = Self.stripFrontMatter(raw)
        draftCreated = Self.createdDate(raw) ?? note.filed
        writeState()
        saveDraft(body)
        try? fm.removeItem(at: note.url)
        return body
    }

    func delete(_ note: NoteSummary) {
        Paths.ensureRoot()
        let destination = uniqueURL(in: Paths.trash, date: note.filed, title: note.title)
        if (try? fm.moveItem(at: note.url, to: destination)) == nil {
            try? fm.removeItem(at: note.url)
            return
        }
        // A move preserves the modification date, so a note filed months ago would land in
        // trash already older than the cutoff and be purged at the next launch. The 30 days
        // are counted from the moment it was binned.
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
    }

    /// Run once at launch -- no timer.
    func purgeTrash() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        guard let urls = try? fm.contentsOfDirectory(at: Paths.trash,
                                                     includingPropertiesForKeys: [.contentModificationDateKey],
                                                     options: [.skipsHiddenFiles]) else { return }
        for url in urls {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            if modified < cutoff { try? fm.removeItem(at: url) }
        }
    }

    // MARK: - Naming and front matter

    private func uniqueURL(in directory: URL, date: Date, title: String) -> URL {
        let stamp = Self.stampFormatter.string(from: date)
        let slug = Self.slug(title)
        let base = slug.isEmpty ? stamp : "\(stamp)-\(slug)"
        var candidate = directory.appendingPathComponent(base + ".md")
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(counter).md")
            counter += 1
        }
        return candidate
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func slug(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let folded = title.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US"))
        let dashed = folded.lowercased().replacingOccurrences(of: " ", with: "-")
        let cleaned = String(dashed.unicodeScalars.filter { allowed.contains($0) })
        let collapsed = cleaned.split(separator: "-").joined(separator: "-")
        return String(collapsed.prefix(40))
    }

    static func title(of body: String) -> String {
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let stripped = line.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#-*>+ "))
            if !stripped.isEmpty { return String(stripped.prefix(80)) }
        }
        return ""
    }

    static func preview(of body: String) -> String {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count > 1 else { return "" }
        return String(lines.dropFirst().joined(separator: " ").prefix(120))
    }

    private static func frontMatter(created: Date, filed: Date) -> String {
        "---\ncreated: \(iso.string(from: created))\nfiled: \(iso.string(from: filed))\n---\n\n"
    }

    static func stripFrontMatter(_ raw: String) -> String {
        guard raw.hasPrefix("---\n") else { return raw }
        let rest = raw.dropFirst(4)
        guard let end = rest.range(of: "\n---\n") else { return raw }
        var body = String(rest[end.upperBound...])
        while body.hasPrefix("\n") { body.removeFirst() }
        return body
    }

    private static func frontMatterValue(_ raw: String, key: String) -> Date? {
        guard raw.hasPrefix("---\n") else { return nil }
        let rest = raw.dropFirst(4)
        guard let end = rest.range(of: "\n---\n") else { return nil }
        for line in rest[..<end.lowerBound].split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == key else { continue }
            return iso.date(from: parts[1].trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    static func createdDate(_ raw: String) -> Date? { frontMatterValue(raw, key: "created") }
    static func filedDate(_ raw: String) -> Date? { frontMatterValue(raw, key: "filed") }
}
