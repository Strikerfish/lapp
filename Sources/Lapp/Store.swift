import Foundation

struct NoteSummary {
    var url: URL
    var title: String
    var preview: String
    var filed: Date
}

/// One open tab: a draft file in `drafts/` plus the moment it was started. The id is the
/// filename stem, so a tab and its file can never drift apart.
struct DraftTab: Codable, Equatable {
    var id: String
    var created: Date

    init(id: String = UUID().uuidString, created: Date = Date()) {
        self.id = id
        self.created = created
    }
}

/// Notes are plain markdown files with a small YAML front-matter block. If the app ever
/// dies, the notes are just files.
final class Store {
    static let shared = Store()

    private let fm = FileManager.default
    private let stateURL = Paths.root.appendingPathComponent("state.json")

    /// The open tabs, left to right, and which one is on the pad. There is always at
    /// least one -- closing the last tab empties it rather than leaving nothing.
    private(set) var tabs: [DraftTab] = []
    private(set) var activeIndex: Int = 0

    /// Titles of the tabs that aren't on the pad. The active one is drawn from the live
    /// text instead, so this is never read for it and typing costs no disk access.
    private var titleCache: [String: String] = [:]

    var activeTab: DraftTab { tabs[activeIndex] }
    var draftCreated: Date { activeTab.created }

    /// `tabs`/`active` are both optional so a state file written by an older build --
    /// which held a single `created` stamp for `current.md` -- still decodes, and the
    /// migration below turns it into the first tab.
    private struct State: Codable {
        var tabs: [DraftTab]?
        var active: Int?
        var created: Date?
    }

    private init() {
        Paths.ensureRoot()
        let state = (try? Data(contentsOf: stateURL)).flatMap {
            try? Self.decoder.decode(State.self, from: $0)
        }
        tabs = state?.tabs ?? []
        activeIndex = state?.active ?? 0
        // Drop tabs whose file has gone missing, then make sure one is left.
        tabs = tabs.filter { fm.fileExists(atPath: url(forTab: $0).path) }
        if tabs.isEmpty { migrateLegacyDraft(created: state?.created) }
        activeIndex = min(max(activeIndex, 0), tabs.count - 1)
        writeState()
    }

    /// Everything that existed before tabs lived in `current.md`, with its start time in
    /// `state.json`. It becomes tab one, and the old file is removed so there is exactly
    /// one place a draft can be.
    private func migrateLegacyDraft(created: Date?) {
        // `state.json` only existed once something had been filed, so fall back to when
        // `current.md` was created rather than stamping the note as new.
        let legacyCreated = try? Paths.draft.resourceValues(forKeys: [.creationDateKey]).creationDate
        let tab = DraftTab(created: created ?? legacyCreated.flatMap { $0 } ?? Date())
        tabs = [tab]
        activeIndex = 0
        let legacy = (try? String(contentsOf: Paths.draft, encoding: .utf8)) ?? ""
        try? legacy.write(to: url(forTab: tab), atomically: true, encoding: .utf8)
        try? fm.removeItem(at: Paths.draft)
    }

    // MARK: - Tabs

    private func url(forTab tab: DraftTab) -> URL {
        Paths.drafts.appendingPathComponent(tab.id + ".md")
    }

    /// The label for a tab: the note's first real line, or "" for an untouched one.
    func title(ofTabAt index: Int) -> String {
        guard tabs.indices.contains(index) else { return "" }
        let tab = tabs[index]
        if let cached = titleCache[tab.id] { return cached }
        let body = (try? String(contentsOf: url(forTab: tab), encoding: .utf8)) ?? ""
        let title = Self.title(of: body)
        titleCache[tab.id] = title
        return title
    }

    func select(_ index: Int) {
        guard tabs.indices.contains(index), index != activeIndex else { return }
        activeIndex = index
        writeState()
    }

    func step(_ delta: Int) {
        guard tabs.count > 1 else { return }
        let count = tabs.count
        select(((activeIndex + delta) % count + count) % count)
    }

    /// Opens a new tab to the right of the active one and selects it.
    @discardableResult
    func newTab() -> Int {
        Paths.ensureRoot()
        let tab = DraftTab()
        try? "".write(to: url(forTab: tab), atomically: true, encoding: .utf8)
        let index = activeIndex + 1
        tabs.insert(tab, at: min(index, tabs.count))
        activeIndex = min(index, tabs.count - 1)
        writeState()
        return activeIndex
    }

    /// Removes a tab and its draft file. The last tab is never removed -- it is emptied,
    /// so there is always something on the pad.
    func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        if tabs.count == 1 {
            startFreshDraft()
            return
        }
        let tab = tabs.remove(at: index)
        titleCache.removeValue(forKey: tab.id)
        try? fm.removeItem(at: url(forTab: tab))
        if activeIndex >= index { activeIndex = max(0, activeIndex - 1) }
        activeIndex = min(activeIndex, tabs.count - 1)
        writeState()
    }

    // MARK: - Draft

    func loadDraft() -> String {
        let body = (try? String(contentsOf: url(forTab: activeTab), encoding: .utf8)) ?? ""
        titleCache[activeTab.id] = Self.title(of: body)
        return body
    }

    func saveDraft(_ text: String) {
        Paths.ensureRoot()
        titleCache[activeTab.id] = Self.title(of: text)
        try? text.write(to: url(forTab: activeTab), atomically: true, encoding: .utf8)
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func writeState() {
        Paths.ensureRoot()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let bytes = try? encoder.encode(State(tabs: tabs, active: activeIndex, created: nil)) {
            try? bytes.write(to: stateURL, options: .atomic)
        }
    }

    /// Empties the active tab and restarts its clock -- what ✓ and ✕ leave behind.
    private func startFreshDraft() {
        tabs[activeIndex].created = Date()
        titleCache[activeTab.id] = ""
        writeState()
        try? "".write(to: url(forTab: activeTab), atomically: true, encoding: .utf8)
    }

    /// The text of a tab that isn't on the pad -- read straight off disk, since the pad
    /// only ever holds the active one.
    func text(ofTabAt index: Int) -> String {
        guard tabs.indices.contains(index) else { return "" }
        return (try? String(contentsOf: url(forTab: tabs[index]), encoding: .utf8)) ?? ""
    }

    // MARK: - File / discard

    /// Commits the pad to history and empties the tab. Returns the written file, or nil
    /// if there was nothing to file.
    @discardableResult
    func file(_ text: String) -> URL? {
        let url = file(text, createdAt: draftCreated)
        startFreshDraft()
        return url
    }

    /// Writes a note to history without touching the pad -- what closing a tab does with
    /// whatever was on it.
    @discardableResult
    func file(_ text: String, createdAt created: Date) -> URL? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        Paths.ensureRoot()
        let url = uniqueURL(in: Paths.notes, date: created, title: Self.title(of: text))
        let document = Self.frontMatter(created: created, filed: Date()) + text
        try? document.write(to: url, atomically: true, encoding: .utf8)
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

    /// Takes a note off the wall and back onto the pad, into whichever tab is active. It
    /// leaves history so a note can never exist in two places at once; the pad's ✓ puts
    /// it back, ✕ bins it.
    func take(_ note: NoteSummary) -> String {
        let raw = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
        let body = Self.stripFrontMatter(raw)
        tabs[activeIndex].created = Self.createdDate(raw) ?? note.filed
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
