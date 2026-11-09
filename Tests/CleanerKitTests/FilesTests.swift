import Foundation
import Testing
@testable import CleanerKit

@Suite struct LargeFilesTests {
    @Test func listsFilesAboveThresholdLargestFirst() async throws {
        let temp = try TempTree()
        try temp.file("a/big.bin", bytes: 3_000_000)
        try temp.file("b/c/bigger.mov", bytes: 5_000_000)
        try temp.file("small.txt", bytes: 2_000_000)
        let root = try await DiskScanner().scan(temp.root).root

        let files = LargeFiles.list(in: root, minimumSize: 2_500_000)
        #expect(files.map(\.name) == ["bigger.mov", "big.bin"])
    }

    @Test func filtersByKind() async throws {
        let temp = try TempTree()
        try temp.file("x.mov", bytes: 3_000_000)
        try temp.file("y.zip", bytes: 3_000_000)
        let root = try await DiskScanner().scan(temp.root).root
        #expect(LargeFiles.list(in: root, minimumSize: 1, kind: .video).map(\.name) == ["x.mov"])
        #expect(LargeFiles.list(in: root, minimumSize: 1, kind: .archive).map(\.name) == ["y.zip"])
        #expect(FileKind(extension: "MP4") == .video)
        #expect(FileKind(extension: "dmg") == .installer)
    }
}

@Suite struct DuplicateFinderTests {
    @Test func groupsIdenticalFilesOnly() async throws {
        let temp = try TempTree()
        try temp.file("a/one.bin", bytes: 2_000_000, fill: 1)
        try temp.file("b/two.bin", bytes: 2_000_000, fill: 1)
        try temp.file("c/same-size-other.bin", bytes: 2_000_000, fill: 2)
        try temp.file("d/three.bin", bytes: 2_000_000, fill: 1)
        // Same size and same first 64 KB, different tail.
        var tail = Data(repeating: 1, count: 2_000_000)
        tail[1_999_999] = 9
        try temp.dir("e")
        try tail.write(to: URL(fileURLWithPath: temp.path("e/tail.bin")))
        let root = try await DiskScanner().scan(temp.root).root

        let groups = try await DuplicateFinder().groups(in: root)
        #expect(groups.count == 1)
        #expect(groups[0].files.map(\.name).sorted() == ["one.bin", "three.bin", "two.bin"])
        #expect(groups[0].wasted == groups[0].files[0].size * 2)
    }

    @Test func hardLinksAreNotDuplicates() async throws {
        let temp = try TempTree()
        let a = try temp.file("a.bin", bytes: 2_000_000, fill: 3)
        try FileManager.default.linkItem(atPath: a, toPath: temp.path("b.bin"))
        // The scanner keeps one node per inode; build the nodes by hand to cover the finder itself.
        var st = stat()
        lstat(a, &st)
        let id = FileID(device: st.st_dev, inode: st.st_ino)
        let files = [a, temp.path("b.bin")].map {
            Node(path: $0, name: ($0 as NSString).lastPathComponent, kind: .file, size: 2_000_000, fileCount: 1,
                 modified: nil, fileID: id)
        }
        let root = Node(path: temp.root, name: "r", kind: .directory, size: 0, fileCount: 2, modified: nil, children: files)
        let groups = try await DuplicateFinder().groups(in: root)
        #expect(groups.isEmpty)
    }
}

@Suite struct CleanerTests {
    final class RecordingTrash: @unchecked Sendable, Trashing {
        var trashed: [String] = []
        func trash(_ path: String) throws { trashed.append(path) }
    }

    func cleaner(home: String, runner: CommandRunning = FakeRunner(), trash: Trashing) -> Cleaner {
        Cleaner(guard: SafetyGuard(home: home), runner: runner,
                tools: ToolLocator(searchPaths: ["/fake/bin"], fileExists: { _ in true }), trasher: trash)
    }

    @Test func trashesItemAndContents() async throws {
        let temp = try TempTree()
        try temp.file("Library/Developer/Xcode/DerivedData/App-1/x", bytes: 10)
        try temp.file("Library/Developer/Xcode/DerivedData/App-2/y", bytes: 10)
        try temp.file("proj/node_modules/a", bytes: 10)
        let trash = RecordingTrash()
        let c = cleaner(home: temp.root, trash: trash)

        let results = await c.perform([.trashContents(temp.path("Library/Developer/Xcode/DerivedData")),
                                       .trash(temp.path("proj/node_modules"))])
        #expect(results.allSatisfy { $0.succeeded })
        #expect(trash.trashed.sorted() == [temp.path("Library/Developer/Xcode/DerivedData/App-1"),
                                           temp.path("Library/Developer/Xcode/DerivedData/App-2"),
                                           temp.path("proj/node_modules")])
    }

    @Test func refusesForbiddenPaths() async throws {
        let temp = try TempTree()
        let trash = RecordingTrash()
        let results = await cleaner(home: temp.root, trash: trash).perform([.trash(temp.root + "/Documents"), .trash("/usr/lib")])
        #expect(results.allSatisfy { !$0.succeeded })
        #expect(trash.trashed.isEmpty)
    }

    @Test func runsToolWithItsAbsolutePath() async throws {
        let temp = try TempTree()
        let runner = FakeRunner()
        runner.answers["docker builder prune -af"] = CommandOutput(status: 0, output: "Total reclaimed space: 1GB")
        let results = await cleaner(home: temp.root, runner: runner, trash: RecordingTrash())
            .perform([.run(tool: "docker", arguments: ["builder", "prune", "-af"]), .run(tool: "cargo", arguments: ["clean"])])
        #expect(results[0].succeeded)
        #expect(results[0].message.contains("reclaimed"))
        #expect(!results[1].succeeded)
        #expect(runner.calls.first?.first == "/fake/bin/docker")
    }

    @Test func emptiesTrashPermanently() async throws {
        let temp = try TempTree()
        try temp.file(".Trash/old.bin", bytes: 10)
        try temp.file(".Trash/dir/x", bytes: 10)
        let results = await cleaner(home: temp.root, trash: RecordingTrash()).perform([.emptyTrash(temp.path(".Trash"))])
        #expect(results[0].succeeded)
        let left = try FileManager.default.contentsOfDirectory(atPath: temp.path(".Trash"))
        #expect(left.isEmpty)
    }

    @Test func emptyTrashOnlyTouchesTheTrashFolder() async throws {
        let temp = try TempTree()
        try temp.file("proj/a", bytes: 10)
        let results = await cleaner(home: temp.root, trash: RecordingTrash()).perform([.emptyTrash(temp.path("proj"))])
        #expect(!results[0].succeeded)
        #expect(FileManager.default.fileExists(atPath: temp.path("proj/a")))
    }
}
