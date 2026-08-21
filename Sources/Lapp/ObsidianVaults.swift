import Foundation

struct ObsidianVault {
    var name: String
    var path: String
}

/// Vaults come from Obsidian's own config, so the setting is a dropdown rather than
/// something to type.
enum ObsidianVaults {
    private static let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/obsidian/obsidian.json")

    static func all() -> [ObsidianVault] {
        guard let bytes = try? Data(contentsOf: configURL),
              let root = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let vaults = root["vaults"] as? [String: Any] else { return [] }

        return vaults.values
            .compactMap { $0 as? [String: Any] }
            .compactMap { entry -> ObsidianVault? in
                guard let path = entry["path"] as? String,
                      FileManager.default.fileExists(atPath: path) else { return nil }
                return ObsidianVault(name: URL(fileURLWithPath: path).lastPathComponent, path: path)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Folder paths relative to the vault root, "" first for the root itself.
    static func folders(in vaultPath: String, maxDepth: Int = 3) -> [String] {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: vaultPath)
        var found: [String] = [""]

        func walk(_ directory: URL, depth: Int) {
            guard depth <= maxDepth,
                  let entries = try? fm.contentsOfDirectory(at: directory,
                                                            includingPropertiesForKeys: [.isDirectoryKey],
                                                            options: [.skipsHiddenFiles]) else { return }
            for entry in entries {
                let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDirectory, entry.lastPathComponent != ".obsidian" else { continue }
                let relative = entry.path.replacingOccurrences(of: root.path + "/", with: "")
                found.append(relative)
                walk(entry, depth: depth + 1)
            }
        }

        walk(root, depth: 1)
        return found.sorted { a, b in
            if a.isEmpty { return true }
            if b.isEmpty { return false }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }

    /// The configured destination, falling back to the vault Obsidian has open.
    static func destination() -> (vault: ObsidianVault, folder: String)? {
        let vaults = all()
        guard !vaults.isEmpty else { return nil }
        let configured = Settings.shared.data.vaultPath
        let vault = vaults.first { $0.path == configured } ?? vaults[0]
        return (vault, Settings.shared.data.vaultFolder)
    }
}
