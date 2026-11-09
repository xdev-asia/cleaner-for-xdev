import AppKit
import CleanerKit
import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview, folders, cleanable, large, duplicates
    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .folders: "Folders"
        case .cleanable: "Cleanable"
        case .large: "Large Files"
        case .duplicates: "Duplicates"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "internaldrive"
        case .folders: "square.grid.3x3.square"
        case .cleanable: "sparkles"
        case .large: "doc.badge.ellipsis"
        case .duplicates: "doc.on.doc"
        }
    }
}

struct VolumeInfo: Identifiable {
    let path: String
    let name: String
    let total: Int64
    let available: Int64
    var id: String { path }
    var used: Int64 { total - available }
}

/// A set of cleanup actions waiting for the user's confirmation.
struct PendingCleanup: Identifiable {
    struct Item: Identifiable {
        let id: String
        let title: String
        let path: String
        let size: Int64
        let steps: [CleanupStep]
    }

    let id = UUID()
    let title: String
    let items: [Item]
    var total: Int64 { items.reduce(0) { $0 + $1.size } }
    var deletesPermanently: Bool {
        items.contains { $0.steps.contains { if case .emptyTrash = $0 { true } else { false } } }
    }
    var movesToTrash: Bool {
        items.contains { $0.steps.contains {
            switch $0 { case .trash, .trashContents: true; default: false }
        } }
    }
}

struct ItemResult: Identifiable {
    let id: String
    let title: String
    let succeeded: Bool
    let message: String
}

@Observable @MainActor
final class AppModel {
    var section: SidebarSection = .overview
    var volumes: [VolumeInfo] = []
    #if APP_STORE
    /// The sandboxed edition only sees folders the user picks, so Full Disk Access does not apply.
    var hasFullDiskAccess = true
    static let rules = Rules.sandboxed
    #else
    var hasFullDiskAccess = AppModel.checkFullDiskAccess()
    static let rules = Rules.standard
    #endif

    // Scan
    var scanning = false
    var progress = ScanProgress()
    var scanRoot: String?
    var result: ScanResult?
    var scanError: String?
    private var scanTask: Task<Void, Never>?

    // Rules
    var analysing = false
    var findings: [Finding] = []
    var selectedFindings: Set<String> = []

    // Duplicates
    var findingDuplicates = false
    var duplicatesSearched = false
    var duplicates: [DuplicateGroup] = []
    var selectedDuplicates: Set<String> = []
    private var duplicateTask: Task<Void, Never>?

    // Folders
    var focusPath: String?

    // Apple Intelligence
    let explainer = Assistant()
    let summariser = Assistant()

    // Cleanup
    var pending: PendingCleanup?
    var cleaning = false
    var results: [ItemResult] = []
    /// Paths removed since the last scan; hidden from every list.
    var removedPaths: Set<String> = []

    init() {
        refreshVolumes()
        // `--scan <path> [--section cleanable]` starts a scan at launch (used for testing and screenshots).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--scan"), i + 1 < args.count { scan(args[i + 1]) }
        if let i = args.firstIndex(of: "--section"), i + 1 < args.count, let s = SidebarSection(rawValue: args[i + 1]) {
            section = s
        }
        Snapshot.run(self)
    }

    // MARK: Volumes and permissions

    func refreshVolumes() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                      .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        volumes = urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.volumeIsBrowsable != false,
                  let total = v.volumeTotalCapacity, total > 0 else { return nil }
            return VolumeInfo(path: url.path, name: v.volumeName ?? url.lastPathComponent, total: Int64(total),
                              available: v.volumeAvailableCapacityForImportantUsage ?? 0)
        }
    }

    /// The TCC database can only be read with Full Disk Access.
    static func checkFullDiskAccess() -> Bool {
        let fd = open(NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }

    func recheckAccess() {
        #if !APP_STORE
        hasFullDiskAccess = Self.checkFullDiskAccess()
        #endif
        refreshVolumes()
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Scan

    func chooseFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.directoryURL = URL(fileURLWithPath: AppHome.path)
        if panel.runModal() == .OK, let url = panel.url { scan(url.path) }
    }

    func scan(_ path: String) {
        scanTask?.cancel()
        duplicateTask?.cancel()
        scanRoot = path
        scanning = true
        scanError = nil
        result = nil
        findings = []
        selectedFindings = []
        duplicates = []
        selectedDuplicates = []
        duplicatesSearched = false
        removedPaths = []
        focusPath = nil
        summariser.cancel()
        summariser.request = nil
        progress = ScanProgress()
        let scanner = DiskScanner()
        scanTask = Task {
            let poll = Task {
                while !Task.isCancelled {
                    self.progress = scanner.progress
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            defer { poll.cancel() }
            do {
                let scanned = try await scanner.scan(path)
                result = scanned
                scanning = false
                await analyse(scanned.root)
            } catch is CancellationError {
                scanning = false
            } catch {
                scanning = false
                scanError = error.localizedDescription
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanning = false
    }

    private func analyse(_ root: Node) async {
        analysing = true
        let found = await RuleMatcher(rules: Self.rules, home: AppHome.path).findings(in: root)
        findings = found
        selectedFindings = Set(found.filter { $0.rule.safety == .safe && $0.blockedReason == nil && !$0.toolMissing }.map(\.id))
        analysing = false
    }

    var root: Node? { result?.root }

    var focusNode: Node? {
        guard let root else { return nil }
        if let focusPath, let node = root.find(focusPath) { return node }
        return root
    }

    func isRemoved(_ path: String) -> Bool {
        removedPaths.contains(path) || removedPaths.contains { path.hasPrefix($0 + "/") }
    }

    // MARK: Duplicates

    func findDuplicates() {
        guard let root else { return }
        duplicateTask?.cancel()
        findingDuplicates = true
        duplicateTask = Task {
            let groups = (try? await DuplicateFinder().groups(in: root)) ?? []
            if !Task.isCancelled {
                duplicates = groups
                duplicatesSearched = true
            }
            findingDuplicates = false
        }
    }

    func cancelDuplicates() {
        duplicateTask?.cancel()
        findingDuplicates = false
    }

    /// Selects every copy except the oldest in each group.
    func selectDuplicateCopies() {
        var selection = Set<String>()
        for group in duplicates {
            let files = group.files.filter { !isRemoved($0.path) }
            let keep = files.min { ($0.modified ?? .distantFuture, $0.path) < ($1.modified ?? .distantFuture, $1.path) }
            for file in files where file.path != keep?.path { selection.insert(file.path) }
        }
        selectedDuplicates = selection
    }

    // MARK: Cleanup

    func confirmFindings() {
        let items = findings.filter { selectedFindings.contains($0.id) && $0.blockedReason == nil && !$0.toolMissing }.map {
            PendingCleanup.Item(id: $0.id, title: $0.rule.title, path: $0.path, size: $0.size, steps: $0.steps)
        }
        guard !items.isEmpty else { return }
        results = []
        pending = PendingCleanup(title: "Clean \(items.count) items", items: items)
    }

    func confirmTrash(_ nodes: [Node]) {
        let items = nodes.map {
            PendingCleanup.Item(id: $0.path, title: $0.name, path: $0.path, size: $0.size, steps: [.trash($0.path)])
        }
        guard !items.isEmpty else { return }
        results = []
        pending = PendingCleanup(title: "Move \(items.count) items to Trash", items: items)
    }

    func runPending() {
        guard let pending else { return }
        cleaning = true
        Task {
            let cleaner = Cleaner()
            var collected: [ItemResult] = []
            for item in pending.items {
                let stepResults = await cleaner.perform(item.steps)
                let ok = !stepResults.isEmpty && stepResults.allSatisfy(\.succeeded)
                collected.append(ItemResult(id: item.id, title: item.title, succeeded: ok,
                                            message: stepResults.map(\.message).joined(separator: "\n")))
                if ok {
                    findings.removeAll { $0.id == item.id }
                    selectedFindings.remove(item.id)
                    selectedDuplicates.remove(item.path)
                    if !item.path.isEmpty, item.steps.contains(where: { if case .trash = $0 { true } else { false } }) {
                        removedPaths.insert(item.path)
                    }
                }
                results = collected
            }
            cleaning = false
            refreshVolumes()
        }
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
