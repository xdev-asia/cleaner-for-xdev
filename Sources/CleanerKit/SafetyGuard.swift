import Foundation

/// Refuses paths that must never be moved to the Trash or handed to a cleanup command.
public struct SafetyGuard: Sendable {
    public enum Verdict: Equatable, Sendable {
        case allowed
        case refused(String)
    }

    public let home: String

    public init(home: String = UserHome.path) {
        self.home = home
    }

    /// Paths under these prefixes are refused, the prefix itself included.
    var forbiddenTrees: [String] {
        ["/System", "/usr", "/bin", "/sbin", "/Library", "/dev", "/etc", "/private/etc", "/private/var/db",
         home + "/.ssh", home + "/.gnupg", home + "/Library/Keychains"]
    }

    /// These paths and every ancestor of them are refused; their contents may be allowed.
    var protectedRoots: [String] {
        ["/", "/Users", "/Applications", "/Volumes", "/private", "/private/var", "/opt", home]
            + ["Library", "Library/Caches", "Library/Logs", "Library/Application Support", "Documents",
               "Desktop", "Downloads", "Pictures", "Movies", "Music", ".Trash"].map { home + "/" + $0 }
    }

    public func check(_ path: String) -> Verdict {
        guard path.hasPrefix("/") else { return .refused("Path is not absolute") }
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        for tree in forbiddenTrees where normalized == tree || normalized.hasPrefix(tree + "/") {
            return .refused("Inside a protected area: \(tree)")
        }
        for root in protectedRoots {
            if normalized == root || normalized == "/" || root.hasPrefix(normalized + "/") {
                return .refused("Protected folder: \(root)")
            }
        }
        return .allowed
    }
}
