import Foundation

public enum Safety: Sendable, Hashable {
    /// Rebuilt automatically; selected by default.
    case safe
    /// Rebuildable but costly or personal (archives, simulators, node_modules); never selected by default.
    case review
}

public enum RuleCategory: String, Sendable, CaseIterable, Hashable {
    case xcode = "Xcode"
    case android = "Android"
    case node = "Node.js"
    case rust = "Rust"
    case docker = "Docker"
    case git = "Git"
    case system = "System"
}

/// What a rule looks for. Paths may start with `~`.
public enum Match: Sendable, Hashable {
    case path(String)
    /// A directory called `name` whose parent has one of `parentMarkers`.
    case directoryNamed(String, parentMarkers: Set<String>)
    /// A directory that itself has `marker`.
    case directoryWithMarker(String)
    /// Files of at least 1 MB in `directory` with one of `extensions`.
    case files(in: String, extensions: Set<String>)
    /// Size comes from a tool, not the file tree.
    case docker
}

/// How a rule cleans. Arguments may contain `{path}` and `{parent}`.
public enum Action: Sendable, Hashable {
    case trashItem
    case trashContents
    case emptyTrash
    case command(tool: String, arguments: [String])
    case gitWorktreeRemove
}

public enum CleanupStep: Sendable, Hashable {
    case trash(String)
    case trashContents(String)
    /// Permanently deletes everything in the Trash folder.
    case emptyTrash(String)
    case run(tool: String, arguments: [String])
}

public struct Rule: Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let category: RuleCategory
    public let safety: Safety
    public let explanation: String
    public let match: Match
    public let action: Action

    public static func == (lhs: Rule, rhs: Rule) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public enum Rules {
    public static let standard: [Rule] = [
        Rule(id: "xcode.derivedData", title: "Xcode DerivedData", category: .xcode, safety: .safe,
             explanation: "Intermediate Xcode build products. Xcode recreates them on the next build.",
             match: .path("~/Library/Developer/Xcode/DerivedData"), action: .trashContents),
        Rule(id: "xcode.archives", title: "Xcode Archives", category: .xcode, safety: .review,
             explanation: "Built archives. Keep the ones you uploaded to the App Store or TestFlight so you can symbolicate crash logs.",
             match: .path("~/Library/Developer/Xcode/Archives"), action: .trashContents),
        Rule(id: "xcode.deviceSupport", title: "iOS DeviceSupport", category: .xcode, safety: .safe,
             explanation: "Debug symbols for each iOS version. Xcode downloads them again when a device is connected.",
             match: .path("~/Library/Developer/Xcode/iOS DeviceSupport"), action: .trashContents),
        Rule(id: "xcode.simulators", title: "Unavailable simulators", category: .xcode, safety: .review,
             explanation: "Deletes simulators whose runtime is no longer installed. The size shown is the whole simulator folder; the space actually freed is usually smaller.",
             match: .path("~/Library/Developer/CoreSimulator/Devices"),
             action: .command(tool: "xcrun", arguments: ["simctl", "delete", "unavailable"])),
        Rule(id: "android.gradleCaches", title: "Gradle caches", category: .android, safety: .safe,
             explanation: "Downloaded libraries and Gradle build outputs. Gradle downloads them again when needed.",
             match: .path("~/.gradle/caches"), action: .trashItem),
        Rule(id: "android.avd", title: "Android emulator (AVD)", category: .android, safety: .review,
             explanation: "Disks of the Android virtual devices. Removing them erases the data inside each emulator.",
             match: .path("~/.android/avd"), action: .trashContents),
        Rule(id: "android.build", title: "Gradle build folders", category: .android, safety: .safe,
             explanation: "Build outputs of Android projects. Gradle recreates them on the next build.",
             match: .directoryNamed("build", parentMarkers: ["build.gradle", "build.gradle.kts"]), action: .trashItem),
        Rule(id: "node.npmCache", title: "npm cache", category: .node, safety: .safe,
             explanation: "Downloaded npm packages. npm downloads them again when needed.",
             match: .path("~/.npm/_cacache"), action: .trashItem),
        Rule(id: "node.pnpmStore", title: "pnpm store", category: .node, safety: .safe,
             explanation: "Runs `pnpm store prune`, which only removes packages no project uses, so less space is freed than shown.",
             match: .path("~/Library/pnpm/store"), action: .command(tool: "pnpm", arguments: ["store", "prune"])),
        Rule(id: "node.nodeModules", title: "node_modules", category: .node, safety: .review,
             explanation: "Packages installed for each project. Reinstall with npm/pnpm install.",
             match: .directoryNamed("node_modules", parentMarkers: ["package.json"]), action: .trashItem),
        Rule(id: "rust.target", title: "Rust target", category: .rust, safety: .safe,
             explanation: "Cargo build outputs. Runs `cargo clean`.",
             match: .directoryNamed("target", parentMarkers: ["Cargo.toml"]),
             action: .command(tool: "cargo", arguments: ["clean", "--manifest-path", "{parent}/Cargo.toml"])),
        Rule(id: "docker.buildCache", title: "Docker build cache", category: .docker, safety: .safe,
             explanation: "Runs `docker builder prune -af`. The next image build will be slower. Docker runs in a VM, so the VM disk file may not shrink by itself.",
             match: .docker, action: .command(tool: "docker", arguments: ["builder", "prune", "-af"])),
        Rule(id: "git.worktree", title: "Git worktree", category: .git, safety: .review,
             explanation: "Runs `git worktree remove`. Branches and commits stay in the main repository. Worktrees with uncommitted changes are left alone.",
             match: .directoryWithMarker(Marker.gitFile), action: .gitWorktreeRemove),
        Rule(id: "system.caches", title: "App caches", category: .system, safety: .review,
             explanation: "~/Library/Caches. Apps recreate them; quit open apps before cleaning.",
             match: .path("~/Library/Caches"), action: .trashContents),
        Rule(id: "system.logs", title: "Logs", category: .system, safety: .safe,
             explanation: "~/Library/Logs.", match: .path("~/Library/Logs"), action: .trashContents),
        Rule(id: "system.installers", title: "Installers in Downloads", category: .system, safety: .review,
             explanation: "Downloaded .dmg, .pkg and .xip files.",
             match: .files(in: "~/Downloads", extensions: ["dmg", "pkg", "xip"]), action: .trashItem),
        Rule(id: "system.trash", title: "Trash", category: .system, safety: .review,
             explanation: "Permanently deletes everything in the Trash. Items moved to the Trash only free their space after this step.",
             match: .path("~/.Trash"), action: .emptyTrash),
    ]
}

public struct Finding: Sendable, Identifiable, Hashable {
    public let rule: Rule
    /// Matched path; empty for findings that do not come from the file tree.
    public let path: String
    public let size: Int64
    public let steps: [CleanupStep]
    /// Set when the finding must not be cleaned (for example a worktree with uncommitted changes).
    public let blockedReason: String?
    /// True when a step needs a tool that was not found.
    public let toolMissing: Bool

    public var id: String { rule.id + ":" + path }
}
