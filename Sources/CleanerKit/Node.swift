import Foundation

/// Identity of a file on disk, used to count hard links once.
public struct FileID: Hashable, Sendable {
    public let device: Int32
    public let inode: UInt64
}

/// Names of entries the scanner remembers per directory, so rules can recognise project folders.
public enum Marker {
    public static let gitFile = ".git(file)"
    public static let gitDirectory = ".git(dir)"
    static let fileNames: Set<String> = [
        "Cargo.toml", "package.json", "pnpm-lock.yaml", "build.gradle", "build.gradle.kts",
        "settings.gradle", "settings.gradle.kts",
    ]
}

/// One entry of a scan result. Directories and files of at least `ScanOptions.minNodeFileSize` get a node;
/// smaller files are folded into one `.smallFiles` child per directory.
public struct Node: Sendable, Identifiable, Hashable {
    public enum Kind: Sendable, Hashable { case directory, file, smallFiles }

    public let path: String
    public let name: String
    public let kind: Kind
    /// Allocated bytes on disk.
    public let size: Int64
    public let fileCount: Int
    public let modified: Date?
    /// Sorted by size, largest first.
    public let children: [Node]
    public let markers: Set<String>
    public let fileID: FileID?

    public var id: String { kind == .smallFiles ? path + "/\u{0}small" : path }

    public init(path: String, name: String, kind: Kind, size: Int64, fileCount: Int, modified: Date?,
                children: [Node] = [], markers: Set<String> = [], fileID: FileID? = nil) {
        self.path = path
        self.name = name
        self.kind = kind
        self.size = size
        self.fileCount = fileCount
        self.modified = modified
        self.children = children
        self.markers = markers
        self.fileID = fileID
    }

    public static func == (lhs: Node, rhs: Node) -> Bool { lhs.id == rhs.id && lhs.size == rhs.size }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Depth-first visit of this node and every descendant.
    public func forEach(_ body: (Node) throws -> Void) rethrows {
        try body(self)
        for child in children { try child.forEach(body) }
    }

    /// The descendant (or self) at `path`, if it was kept in the tree.
    public func find(_ target: String) -> Node? {
        if path == target { return self }
        guard target.hasPrefix(path == "/" ? "/" : path + "/") else { return nil }
        for child in children where child.kind == .directory || child.path == target {
            if let hit = child.find(target) { return hit }
        }
        return nil
    }
}
