import Darwin
import Foundation
import Synchronization

public struct ScanOptions: Sendable {
    /// Files at least this large get their own node.
    public var minNodeFileSize: Int64
    /// Directories that are not entered (exact paths).
    public var skipPaths: Set<String>
    /// Directory depth up to which sub-directories are scanned in parallel.
    public var parallelDepth: Int

    public init(minNodeFileSize: Int64 = 1_048_576, skipPaths: Set<String> = [], parallelDepth: Int = 3) {
        self.minNodeFileSize = minNodeFileSize
        self.skipPaths = skipPaths
        self.parallelDepth = parallelDepth
    }

    /// Paths skipped when scanning the whole startup disk: the sealed system volume, device files,
    /// other volumes and swap. `/System/Volumes/Data` is reached through its firmlinks (`/Users`, `/Applications`...).
    public static let startupDiskSkips: Set<String> = ["/System", "/dev", "/Volumes", "/private/var/vm", "/net", "/home"]
}

public struct ScanProgress: Sendable, Equatable {
    public var filesSeen = 0
    public var bytesSeen: Int64 = 0
    public var currentPath = ""
    public init() {}
}

public struct ScanResult: Sendable {
    public let root: Node
    /// Directories that could not be read (usually missing Full Disk Access).
    public let denied: [String]
    public let duration: Duration
}

/// Walks a directory tree with `lstat`, measuring allocated size. Safe to share between tasks.
public final class DiskScanner: Sendable {
    public let options: ScanOptions
    private let state = Mutex(State())

    private struct State {
        var progress = ScanProgress()
        var seenLinks = Set<FileID>()
        var denied: [String] = []
    }

    public init(options: ScanOptions = .init()) {
        self.options = options
    }

    public var progress: ScanProgress { state.withLock { $0.progress } }

    public func scan(_ rootPath: String) async throws -> ScanResult {
        let start = ContinuousClock.now
        state.withLock { $0 = State() }
        let root = rootPath == "/" ? "/" : URL(fileURLWithPath: rootPath).standardizedFileURL.path
        var skips = options.skipPaths
        var devices = Set<Int32>()
        if let dev = Self.device(of: root) { devices.insert(dev) }
        if root == "/" {
            skips.formUnion(ScanOptions.startupDiskSkips)
            if let data = Self.device(of: "/System/Volumes/Data") { devices.insert(data) }
        }
        let context = Context(skips: skips, devices: devices)
        let node = try await scanDirectory(root, name: root == "/" ? "/" : (root as NSString).lastPathComponent,
                                           depth: 0, context: context)
        let denied = state.withLock { $0.denied.sorted() }
        return ScanResult(root: node, denied: denied, duration: ContinuousClock.now - start)
    }

    private struct Context: Sendable {
        let skips: Set<String>
        let devices: Set<Int32>
    }

    private static func device(of path: String) -> Int32? {
        var st = stat()
        return lstat(path, &st) == 0 ? st.st_dev : nil
    }

    private func scanDirectory(_ path: String, name: String, depth: Int, context: Context) async throws -> Node {
        try Task.checkCancellation()
        var own = stat()
        lstat(path, &own)
        state.withLock { $0.progress.currentPath = path }

        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: path)
        } catch {
            state.withLock { $0.denied.append(path) }
            return Node(path: path, name: name, kind: .directory, size: Int64(own.st_blocks) * 512, fileCount: 0,
                        modified: Self.date(own.st_mtimespec))
        }

        var children: [Node] = []
        var subdirectories: [(String, String)] = []
        var markers = Set<String>()
        var smallSize: Int64 = 0
        var smallCount = 0
        var fileCount = 0
        var bytes: Int64 = 0

        for entry in names {
            let child = path == "/" ? "/" + entry : path + "/" + entry
            var st = stat()
            guard lstat(child, &st) == 0 else { continue }
            let type = st.st_mode & S_IFMT
            if type == S_IFDIR {
                if entry == ".git" { markers.insert(Marker.gitDirectory) }
                if context.skips.contains(child) || !context.devices.contains(st.st_dev) { continue }
                subdirectories.append((child, entry))
                continue
            }
            if type == S_IFREG {
                if entry == ".git" { markers.insert(Marker.gitFile) }
                if Marker.fileNames.contains(entry) { markers.insert(entry) }
            }
            var size = Int64(st.st_blocks) * 512
            let id = FileID(device: st.st_dev, inode: UInt64(st.st_ino))
            if st.st_nlink > 1 && type == S_IFREG {
                let first = state.withLock { $0.seenLinks.insert(id).inserted }
                if !first { size = 0 }
            }
            fileCount += 1
            bytes += size
            if type == S_IFREG && size >= options.minNodeFileSize {
                children.append(Node(path: child, name: entry, kind: .file, size: size, fileCount: 1,
                                     modified: Self.date(st.st_mtimespec), fileID: id))
            } else {
                smallSize += size
                smallCount += 1
            }
        }
        state.withLock {
            $0.progress.filesSeen += fileCount
            $0.progress.bytesSeen += bytes
        }

        if depth < options.parallelDepth && subdirectories.count > 1 {
            children += try await withThrowingTaskGroup(of: Node.self) { group in
                for (child, entry) in subdirectories {
                    group.addTask { try await self.scanDirectory(child, name: entry, depth: depth + 1, context: context) }
                }
                var nodes: [Node] = []
                for try await node in group { nodes.append(node) }
                return nodes
            }
        } else {
            for (child, entry) in subdirectories {
                children.append(try await scanDirectory(child, name: entry, depth: depth + 1, context: context))
            }
        }

        if smallCount > 0 {
            children.append(Node(path: path, name: "", kind: .smallFiles, size: smallSize, fileCount: smallCount,
                                 modified: nil))
        }
        children.sort { $0.size > $1.size }
        let total = children.reduce(Int64(own.st_blocks) * 512) { $0 + $1.size }
        let count = children.reduce(0) { $0 + $1.fileCount }
        return Node(path: path, name: name, kind: .directory, size: total, fileCount: count,
                    modified: Self.date(own.st_mtimespec), children: children, markers: markers)
    }

    private static func date(_ ts: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(ts.tv_sec) + TimeInterval(ts.tv_nsec) / 1e9)
    }
}
