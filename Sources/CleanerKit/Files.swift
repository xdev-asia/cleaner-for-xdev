import CryptoKit
import Foundation

public enum FileKind: String, Sendable, CaseIterable, Hashable {
    case video = "Video"
    case image = "Ảnh"
    case audio = "Âm thanh"
    case archive = "File nén"
    case installer = "Bộ cài"
    case disk = "Ổ đĩa ảo"
    case other = "Khác"

    static let extensions: [FileKind: Set<String>] = [
        .video: ["mov", "mp4", "m4v", "mkv", "avi", "webm"],
        .image: ["jpg", "jpeg", "png", "heic", "tif", "tiff", "psd", "raw", "dng", "webp"],
        .audio: ["mp3", "m4a", "wav", "aiff", "flac", "aac"],
        .archive: ["zip", "tar", "gz", "tgz", "xz", "bz2", "7z", "rar", "zst"],
        .installer: ["dmg", "pkg", "xip", "ipa", "apk", "aab", "iso"],
        .disk: ["img", "raw-img", "qcow2", "vmdk", "vdi", "sparseimage", "sparsebundle"],
    ]

    public init(extension ext: String) {
        let ext = ext.lowercased()
        self = Self.extensions.first { $0.value.contains(ext) }?.key ?? .other
    }
}

public enum LargeFiles {
    /// Files in the tree of at least `minimumSize` bytes, largest first. The tree only holds files of 1 MB and up.
    public static func list(in root: Node, minimumSize: Int64, kind: FileKind? = nil, modifiedBefore: Date? = nil) -> [Node] {
        var result: [Node] = []
        root.forEach { node in
            guard node.kind == .file, node.size >= minimumSize else { return }
            if let kind, FileKind(extension: (node.name as NSString).pathExtension) != kind { return }
            if let modifiedBefore, let modified = node.modified, modified >= modifiedBefore { return }
            result.append(node)
        }
        return result.sorted { $0.size > $1.size }
    }
}

public struct DuplicateGroup: Sendable, Identifiable, Hashable {
    public let hash: String
    public let files: [Node]
    public var id: String { hash }
    /// Space taken by every copy except one.
    public var wasted: Int64 { (files.first?.size ?? 0) * Int64(files.count - 1) }
}

/// Finds files with identical content: same size, then same first 64 KB, then same SHA-256.
/// APFS clones share blocks but are reported too, since nothing public tells them apart.
public struct DuplicateFinder: Sendable {
    public let minimumSize: Int64
    public init(minimumSize: Int64 = 1_048_576) { self.minimumSize = minimumSize }

    public func groups(in root: Node) async throws -> [DuplicateGroup] {
        var bySize: [Int64: [Node]] = [:]
        root.forEach { node in
            if node.kind == .file, node.size >= minimumSize { bySize[node.size, default: []].append(node) }
        }
        var result: [DuplicateGroup] = []
        for (_, nodes) in bySize where nodes.count > 1 {
            let unique = Self.distinctInodes(nodes)
            guard unique.count > 1 else { continue }
            for (_, sameHead) in try await bucket(unique, by: { try Self.hash($0, limit: 65_536) }) where sameHead.count > 1 {
                for (hash, same) in try await bucket(sameHead, by: { try Self.hash($0, limit: nil) }) where same.count > 1 {
                    result.append(DuplicateGroup(hash: hash, files: same.sorted { $0.path < $1.path }))
                }
            }
        }
        return result.sorted { $0.wasted > $1.wasted }
    }

    static func distinctInodes(_ nodes: [Node]) -> [Node] {
        var seen = Set<FileID>()
        return nodes.filter { node in
            guard let id = node.fileID else { return true }
            return seen.insert(id).inserted
        }
    }

    private func bucket(_ nodes: [Node], by hash: @escaping @Sendable (String) throws -> String) async throws -> [String: [Node]] {
        var buckets: [String: [Node]] = [:]
        for node in nodes {
            try Task.checkCancellation()
            guard let key = try? await Task.detached(operation: { try hash(node.path) }).value else { continue }
            buckets[key, default: []].append(node)
        }
        return buckets
    }

    /// SHA-256 of the first `limit` bytes, or of the whole file.
    static func hash(_ path: String, limit: Int?) throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? .max
        while remaining > 0, let chunk = try handle.read(upToCount: min(1 << 20, remaining)), !chunk.isEmpty {
            hasher.update(data: chunk)
            remaining -= chunk.count
            if limit == nil { try Task.checkCancellation() }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
