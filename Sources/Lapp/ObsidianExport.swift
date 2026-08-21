import AppKit

enum ObsidianExport {
    enum Result {
        case sent(String)       // the path shown back to the user
        case noVault
        case empty
        case failed(String)
    }

    /// Writes markdown into the designated vault folder and opens it in Obsidian.
    static func send(body: String, created: Date) -> Result {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
        guard let (vault, folder) = ObsidianVaults.destination() else { return .noVault }

        let directory = folder.isEmpty
            ? URL(fileURLWithPath: vault.path)
            : URL(fileURLWithPath: vault.path).appendingPathComponent(folder)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return .failed(error.localizedDescription)
        }

        let title = Store.title(of: body)
        let base = title.isEmpty ? stamp(created) : sanitised(title)
        var url = directory.appendingPathComponent(base + ".md")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base) \(counter).md")
            counter += 1
        }

        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return .failed(error.localizedDescription)
        }

        open(vault: vault, fileURL: url)
        let shown = folder.isEmpty ? url.lastPathComponent : "\(folder)/\(url.lastPathComponent)"
        return .sent(shown)
    }

    private static func open(vault: ObsidianVault, fileURL: URL) {
        let relative = fileURL.path.replacingOccurrences(of: vault.path + "/", with: "")
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "vault", value: vault.name),
            URLQueryItem(name: "file", value: relative)
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    /// Obsidian note names can hold most things; these are the ones that break paths or links.
    private static func sanitised(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:|#^[]")
        let cleaned = String(title.unicodeScalars.filter { !forbidden.contains($0) })
        return String(cleaned.trimmingCharacters(in: .whitespaces).prefix(60))
    }

    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
