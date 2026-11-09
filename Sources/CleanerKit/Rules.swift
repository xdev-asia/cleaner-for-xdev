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
    case system = "Hệ thống"
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
             explanation: "Kết quả build trung gian của Xcode. Xcode tự tạo lại ở lần build sau.",
             match: .path("~/Library/Developer/Xcode/DerivedData"), action: .trashContents),
        Rule(id: "xcode.archives", title: "Xcode Archives", category: .xcode, safety: .review,
             explanation: "Các bản archive đã build. Cần giữ bản đã gửi lên App Store/TestFlight để đọc crash log.",
             match: .path("~/Library/Developer/Xcode/Archives"), action: .trashContents),
        Rule(id: "xcode.deviceSupport", title: "iOS DeviceSupport", category: .xcode, safety: .safe,
             explanation: "Ký hiệu debug cho từng phiên bản iOS. Xcode tải lại khi cắm thiết bị.",
             match: .path("~/Library/Developer/Xcode/iOS DeviceSupport"), action: .trashContents),
        Rule(id: "xcode.simulators", title: "Simulator không còn dùng được", category: .xcode, safety: .review,
             explanation: "Xoá các simulator của runtime đã gỡ. Dung lượng hiển thị là toàn bộ thư mục simulator; số thu về thực tế thường nhỏ hơn.",
             match: .path("~/Library/Developer/CoreSimulator/Devices"),
             action: .command(tool: "xcrun", arguments: ["simctl", "delete", "unavailable"])),
        Rule(id: "android.gradleCaches", title: "Gradle caches", category: .android, safety: .safe,
             explanation: "Thư viện và kết quả build Gradle tải về. Gradle tải lại khi cần.",
             match: .path("~/.gradle/caches"), action: .trashItem),
        Rule(id: "android.avd", title: "Android emulator (AVD)", category: .android, safety: .review,
             explanation: "Ổ đĩa của các máy ảo Android. Xoá thì mất dữ liệu trong emulator.",
             match: .path("~/.android/avd"), action: .trashContents),
        Rule(id: "android.build", title: "Thư mục build Gradle", category: .android, safety: .safe,
             explanation: "Kết quả build của project Android. Gradle tạo lại ở lần build sau.",
             match: .directoryNamed("build", parentMarkers: ["build.gradle", "build.gradle.kts"]), action: .trashItem),
        Rule(id: "node.npmCache", title: "npm cache", category: .node, safety: .safe,
             explanation: "Gói npm đã tải. npm tải lại khi cần.",
             match: .path("~/.npm/_cacache"), action: .trashItem),
        Rule(id: "node.pnpmStore", title: "pnpm store", category: .node, safety: .safe,
             explanation: "Chạy `pnpm store prune`: chỉ xoá các gói không project nào dùng, nên số thu về nhỏ hơn dung lượng hiển thị.",
             match: .path("~/Library/pnpm/store"), action: .command(tool: "pnpm", arguments: ["store", "prune"])),
        Rule(id: "node.nodeModules", title: "node_modules", category: .node, safety: .review,
             explanation: "Gói cài cho từng project. Cài lại bằng npm/pnpm install.",
             match: .directoryNamed("node_modules", parentMarkers: ["package.json"]), action: .trashItem),
        Rule(id: "rust.target", title: "Rust target", category: .rust, safety: .safe,
             explanation: "Kết quả build Cargo. Chạy `cargo clean`.",
             match: .directoryNamed("target", parentMarkers: ["Cargo.toml"]),
             action: .command(tool: "cargo", arguments: ["clean", "--manifest-path", "{parent}/Cargo.toml"])),
        Rule(id: "docker.buildCache", title: "Docker build cache", category: .docker, safety: .safe,
             explanation: "Chạy `docker builder prune -af`. Lần build image sau sẽ chậm hơn. Docker chạy trong VM nên file đĩa của VM có thể không tự co lại.",
             match: .docker, action: .command(tool: "docker", arguments: ["builder", "prune", "-af"])),
        Rule(id: "git.worktree", title: "Git worktree", category: .git, safety: .review,
             explanation: "Chạy `git worktree remove`. Nhánh và commit vẫn giữ trong repo chính. Worktree còn thay đổi chưa commit thì không dọn.",
             match: .directoryWithMarker(Marker.gitFile), action: .gitWorktreeRemove),
        Rule(id: "system.caches", title: "Cache của ứng dụng", category: .system, safety: .review,
             explanation: "~/Library/Caches. Ứng dụng tự tạo lại; nên thoát các ứng dụng đang mở trước khi dọn.",
             match: .path("~/Library/Caches"), action: .trashContents),
        Rule(id: "system.logs", title: "Log", category: .system, safety: .safe,
             explanation: "~/Library/Logs.", match: .path("~/Library/Logs"), action: .trashContents),
        Rule(id: "system.installers", title: "File cài đặt trong Downloads", category: .system, safety: .review,
             explanation: "File .dmg, .pkg, .xip đã tải về.",
             match: .files(in: "~/Downloads", extensions: ["dmg", "pkg", "xip"]), action: .trashItem),
        Rule(id: "system.trash", title: "Thùng rác", category: .system, safety: .review,
             explanation: "Xoá vĩnh viễn mọi thứ trong Thùng rác. Đồ đã chuyển vào Thùng rác chỉ trả lại dung lượng sau bước này.",
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
