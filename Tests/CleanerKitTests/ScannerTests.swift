import Foundation
import Testing
@testable import CleanerKit

@Suite struct ScannerTests {
    @Test func sumsAllocatedSizesAndKeepsBigFilesAsNodes() async throws {
        let tree = try TempTree()
        let big = try tree.file("a/big.bin", bytes: 3 * 1_048_576)
        var smallTotal: Int64 = 0
        for i in 0..<10 { smallTotal += TempTree.allocated(try tree.file("a/small\(i).txt", bytes: 1000)) }

        let result = try await DiskScanner().scan(tree.root)
        let a = try #require(result.root.children.first { $0.name == "a" })

        #expect(a.kind == .directory)
        #expect(a.fileCount == 11)
        let bigNode = try #require(a.children.first { $0.name == "big.bin" })
        #expect(bigNode.kind == .file)
        #expect(bigNode.size == TempTree.allocated(big))
        let small = try #require(a.children.first { $0.kind == .smallFiles })
        #expect(small.fileCount == 10)
        #expect(small.size == smallTotal)
        #expect(a.size >= bigNode.size + smallTotal)
        #expect(result.root.size >= a.size)
        #expect(a.children.map(\.size) == a.children.map(\.size).sorted(by: >))
    }

    @Test func countsHardLinkedFilesOnce() async throws {
        let tree = try TempTree()
        let big = try tree.file("x/big.bin", bytes: 2 * 1_048_576)
        try FileManager.default.createDirectory(atPath: tree.path("y"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(atPath: big, toPath: tree.path("y/link.bin"))

        let result = try await DiskScanner().scan(tree.root)
        #expect(result.root.size < 2 * TempTree.allocated(big))
        #expect(result.root.fileCount == 2)
    }

    @Test func doesNotFollowSymlinks() async throws {
        let outside = try TempTree()
        try outside.file("huge.bin", bytes: 4 * 1_048_576)
        let tree = try TempTree()
        try FileManager.default.createSymbolicLink(atPath: tree.path("link"), withDestinationPath: outside.root)

        let result = try await DiskScanner().scan(tree.root)
        #expect(result.root.size < 1_048_576)
    }

    @Test func reportsDeniedDirectories() async throws {
        let tree = try TempTree()
        let locked = try tree.dir("locked")
        try tree.file("locked/secret.bin", bytes: 10)
        chmod(locked, 0)

        let result = try await DiskScanner().scan(tree.root)
        #expect(result.denied == [locked])
    }

    @Test func recordsMarkers() async throws {
        let tree = try TempTree()
        try tree.file("rust/Cargo.toml", bytes: 10)
        try tree.file("wt/.git", bytes: 30)
        try tree.dir("repo/.git")

        let result = try await DiskScanner().scan(tree.root)
        let byName = Dictionary(uniqueKeysWithValues: result.root.children.map { ($0.name, $0) })
        #expect(byName["rust"]?.markers == ["Cargo.toml"])
        #expect(byName["wt"]?.markers == [Marker.gitFile])
        #expect(byName["repo"]?.markers == [Marker.gitDirectory])
    }

    @Test func skipsConfiguredPaths() async throws {
        let tree = try TempTree()
        try tree.file("keep/a.bin", bytes: 2 * 1_048_576)
        try tree.file("skip/b.bin", bytes: 2 * 1_048_576)

        let result = try await DiskScanner(options: .init(skipPaths: [tree.path("skip")])).scan(tree.root)
        #expect(result.root.children.map(\.name) == ["keep"])
    }

    @Test func stopsWhenCancelled() async throws {
        let tree = try TempTree()
        try tree.file("a/b.bin", bytes: 10)
        let task = Task { () async throws -> ScanResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await DiskScanner().scan(tree.root)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func reportsProgress() async throws {
        let tree = try TempTree()
        for i in 0..<5 { try tree.file("f\(i)", bytes: 100) }
        let scanner = DiskScanner()
        _ = try await scanner.scan(tree.root)
        #expect(scanner.progress.filesSeen == 5)
    }
}
