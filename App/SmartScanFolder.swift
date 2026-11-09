#if APP_STORE
import AppKit

/// The folder Smart Scan may read in the sandboxed edition. The user picks it once (the panel opens at Home) and the
/// app keeps a security-scoped bookmark, so later Smart Scans need no panel.
@MainActor
enum SmartScanFolder {
    private static let key = "smartScanBookmark"
    private static var accessed: URL?

    /// Path of the remembered folder, without starting access.
    static var rememberedPath: String? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        return (try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil,
                         bookmarkDataIsStale: &stale))?.path
    }

    /// The remembered folder with access started, or nil when there is none or it no longer resolves.
    static func resolve() -> URL? {
        if let accessed { return accessed }
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
                                 bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        if stale { save(url) }
        accessed = url
        return url
    }

    /// Asks for the folder, starting at Home, and remembers it. Nil when the user cancels.
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Allow"
        panel.message = "Smart Scan looks for caches and build folders in your Home folder. Choose it once and Cleaner for xDev remembers it."
        panel.directoryURL = URL(fileURLWithPath: AppHome.path)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        accessed?.stopAccessingSecurityScopedResource()
        accessed = nil
        save(url)
        return resolve() ?? url
    }

    private static func save(_ url: URL) {
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
#endif
