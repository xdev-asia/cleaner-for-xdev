import Foundation
import Darwin

/// A throwaway directory tree under the system temp folder, removed on deinit.
final class TempTree {
    let root: String

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("cleanerkit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = URL(fileURLWithPath: base.path).resolvingSymlinksInPath().path
    }

    deinit {
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root)
        restorePermissions(root)
        try? FileManager.default.removeItem(atPath: root)
    }

    private func restorePermissions(_ dir: String) {
        let items = (try? FileManager.default.subpathsOfDirectory(atPath: dir)) ?? []
        for item in items { chmod(dir + "/" + item, 0o755) }
    }

    func path(_ relative: String) -> String { root + "/" + relative }

    @discardableResult
    func dir(_ relative: String) throws -> String {
        try FileManager.default.createDirectory(atPath: path(relative), withIntermediateDirectories: true)
        return path(relative)
    }

    @discardableResult
    func file(_ relative: String, bytes: Int, fill: UInt8 = 0x41) throws -> String {
        let full = path(relative)
        try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: full, contents: Data(repeating: fill, count: bytes)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return full
    }

    static func allocated(_ path: String) -> Int64 {
        var st = stat()
        lstat(path, &st)
        return Int64(st.st_blocks) * 512
    }
}
