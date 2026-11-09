import Foundation
import Testing
@testable import CleanerKit

/// Command runner that answers from a table and records every call.
final class FakeRunner: CommandRunning, @unchecked Sendable {
    var answers: [String: CommandOutput] = [:]
    private(set) var calls: [[String]] = []

    func run(_ executable: String, _ arguments: [String], environment: [String: String]) async throws -> CommandOutput {
        let key = ([(executable as NSString).lastPathComponent] + arguments).joined(separator: " ")
        calls.append([executable] + arguments)
        return answers[key] ?? CommandOutput(status: 1, output: "not found")
    }
}

private func dir(_ path: String, size: Int64 = 0, markers: Set<String> = [], _ children: [Node] = []) -> Node {
    let total = size + children.reduce(0) { $0 + $1.size }
    return Node(path: path, name: (path as NSString).lastPathComponent, kind: .directory, size: total,
                fileCount: children.count, modified: nil, children: children, markers: markers)
}

private func file(_ path: String, size: Int64) -> Node {
    Node(path: path, name: (path as NSString).lastPathComponent, kind: .file, size: size, fileCount: 1, modified: nil)
}

@Suite struct RuleMatcherTests {
    let home = "/Users/t"
    let tools = ToolLocator(searchPaths: [])

    func matcher(_ runner: FakeRunner = FakeRunner()) -> RuleMatcher {
        RuleMatcher(rules: Rules.standard, home: home, runner: runner, tools: ToolLocator(searchPaths: ["/fake/bin"], fileExists: { _ in true }))
    }

    var tree: Node {
        dir("/Users/t", [
            dir("/Users/t/Library", [
                dir("/Users/t/Library/Developer", [
                    dir("/Users/t/Library/Developer/Xcode", [
                        dir("/Users/t/Library/Developer/Xcode/DerivedData", size: 9_000),
                        dir("/Users/t/Library/Developer/Xcode/Archives", size: 5_000),
                    ]),
                ]),
                dir("/Users/t/Library/Caches", size: 6_000),
            ]),
            dir("/Users/t/Work", [
                dir("/Users/t/Work/rs", markers: ["Cargo.toml"], [dir("/Users/t/Work/rs/target", size: 24_000)]),
                dir("/Users/t/Work/web", markers: ["package.json"], [
                    dir("/Users/t/Work/web/node_modules", size: 3_000, [
                        dir("/Users/t/Work/web/node_modules/x", markers: ["package.json"], [
                            dir("/Users/t/Work/web/node_modules/x/node_modules", size: 100),
                        ]),
                    ]),
                ]),
                dir("/Users/t/Work/plain", [dir("/Users/t/Work/plain/target", size: 50)]),
            ]),
            dir("/Users/t/Downloads", [
                file("/Users/t/Downloads/Xcode.dmg", size: 7_000),
                file("/Users/t/Downloads/photo.jpg", size: 2_000),
            ]),
        ])
    }

    @Test func findsPathRulesWithSizes() async {
        let findings = await matcher().findings(in: tree)
        let byRule = Dictionary(grouping: findings, by: \.rule.id)
        #expect(byRule["xcode.derivedData"]?.first?.size == 9_000)
        #expect(byRule["xcode.archives"]?.first?.rule.safety == .review)
        #expect(byRule["system.caches"]?.first?.steps == [.trashContents("/Users/t/Library/Caches")])
    }

    @Test func findsProjectFoldersOnlyNextToTheirManifest() async {
        let findings = await matcher().findings(in: tree)
        let paths = findings.map(\.path)
        #expect(paths.contains("/Users/t/Work/rs/target"))
        #expect(!paths.contains("/Users/t/Work/plain/target"))
        #expect(paths.contains("/Users/t/Work/web/node_modules"))
        #expect(!paths.contains("/Users/t/Work/web/node_modules/x/node_modules"))
        let target = findings.first { $0.path == "/Users/t/Work/rs/target" }
        #expect(target?.steps == [.run(tool: "cargo", arguments: ["clean", "--manifest-path", "/Users/t/Work/rs/Cargo.toml"])])
    }

    @Test func findsInstallersInDownloads() async {
        let findings = await matcher().findings(in: tree)
        #expect(findings.filter { $0.rule.id == "system.installers" }.map(\.path) == ["/Users/t/Downloads/Xcode.dmg"])
    }

    @Test func skipsRulesWhoseToolIsMissing() async {
        let m = RuleMatcher(rules: Rules.standard, home: home, runner: FakeRunner(),
                            tools: ToolLocator(searchPaths: [], fileExists: { _ in false }))
        let findings = await m.findings(in: tree)
        #expect(findings.first { $0.path == "/Users/t/Work/rs/target" }?.toolMissing == true)
    }

    @Test func readsDockerBuildCacheSize() async {
        let runner = FakeRunner()
        runner.answers["docker system df --format {{json .}}"] = CommandOutput(status: 0, output: """
        {"Active":"11","Reclaimable":"932.7MB (3%)","Size":"26.2GB","TotalCount":"21","Type":"Images"}
        {"Active":"0","Reclaimable":"1.522GB","Size":"22.02GB","TotalCount":"71","Type":"Build Cache"}
        """)
        let findings = await matcher(runner).findings(in: tree)
        let docker = findings.first { $0.rule.id == "docker.buildCache" }
        #expect(docker?.size == 22_020_000_000)
        #expect(docker?.steps == [.run(tool: "docker", arguments: ["builder", "prune", "-af"])])
    }

    @Test func emptyDockerBuildCacheIsNotAFinding() async {
        let runner = FakeRunner()
        runner.answers["docker system df --format {{json .}}"] = CommandOutput(status: 0, output: """
        {"Active":"0","Reclaimable":"0B","Size":"0B","TotalCount":"0","Type":"Build Cache"}
        """)
        let findings = await matcher(runner).findings(in: tree)
        #expect(!findings.contains { $0.rule.id == "docker.buildCache" })
    }

    @Test func parsesDockerSizes() {
        #expect(DockerProbe.bytes("1.5kB") == 1_500)
        #expect(DockerProbe.bytes("0B") == 0)
        #expect(DockerProbe.bytes("3.2MB") == 3_200_000)
        #expect(DockerProbe.bytes("1TB") == 1_000_000_000_000)
        #expect(DockerProbe.bytes("junk") == nil)
    }
}

@Suite struct GitWorktreeTests {
    @Test func cleanWorktreeIsRemovedThroughItsMainRepo() async throws {
        let temp = try TempTree()
        try temp.file("repo/.git/worktrees/wt1/HEAD", bytes: 1)
        try "gitdir: \(temp.path("repo/.git/worktrees/wt1"))\n".write(toFile: try temp.file("wt1/.git", bytes: 0), atomically: true, encoding: .utf8)
        let node = Node(path: temp.path("wt1"), name: "wt1", kind: .directory, size: 2_000, fileCount: 1,
                        modified: nil, markers: [Marker.gitFile])
        let runner = FakeRunner()
        runner.answers["git -C \(temp.path("wt1")) status --porcelain --ignore-submodules=none"] = CommandOutput(status: 0, output: "")
        let m = RuleMatcher(rules: Rules.standard, home: "/nowhere", runner: runner,
                            tools: ToolLocator(searchPaths: ["/fake/bin"], fileExists: { _ in true }))

        let finding = try #require(await m.findings(in: node).first)
        #expect(finding.rule.id == "git.worktree")
        #expect(finding.blockedReason == nil)
        #expect(finding.steps == [.run(tool: "git", arguments: ["-C", temp.path("repo"), "worktree", "remove", "--force", temp.path("wt1")])])
    }

    @Test func dirtyWorktreeIsBlocked() async throws {
        let temp = try TempTree()
        try "gitdir: \(temp.path("repo/.git/worktrees/wt1"))\n".write(toFile: try temp.file("wt1/.git", bytes: 0), atomically: true, encoding: .utf8)
        let node = Node(path: temp.path("wt1"), name: "wt1", kind: .directory, size: 2_000, fileCount: 1,
                        modified: nil, markers: [Marker.gitFile])
        let runner = FakeRunner()
        runner.answers["git -C \(temp.path("wt1")) status --porcelain --ignore-submodules=none"] = CommandOutput(status: 0, output: " M a.swift\n")
        let m = RuleMatcher(rules: Rules.standard, home: "/nowhere", runner: runner,
                            tools: ToolLocator(searchPaths: ["/fake/bin"], fileExists: { _ in true }))

        let finding = try #require(await m.findings(in: node).first)
        #expect(finding.blockedReason != nil)
    }

    @Test func submoduleCheckoutIsNotAWorktree() async throws {
        let temp = try TempTree()
        try "gitdir: ../../.git/modules/ui\n".write(toFile: try temp.file("vendor/ui/.git", bytes: 0), atomically: true, encoding: .utf8)
        let node = Node(path: temp.path("vendor/ui"), name: "ui", kind: .directory, size: 2_000, fileCount: 1,
                        modified: nil, markers: [Marker.gitFile])
        let m = RuleMatcher(rules: Rules.standard, home: "/nowhere", runner: FakeRunner(),
                            tools: ToolLocator(searchPaths: ["/fake/bin"], fileExists: { _ in true }))
        #expect(await m.findings(in: node).isEmpty)
    }
}

@Suite struct CommandTests {
    @Test func locatorFindsFirstExecutable() throws {
        let temp = try TempTree()
        let tool = try temp.file("b/mytool", bytes: 10)
        chmod(tool, 0o755)
        let locator = ToolLocator(searchPaths: [temp.path("a"), temp.path("b")])
        #expect(locator.locate("mytool") == tool)
        #expect(locator.locate("absent") == nil)
        #expect(locator.environment["PATH"] == "\(temp.path("a")):\(temp.path("b"))")
    }

    @Test func processRunnerCapturesOutputAndStatus() async throws {
        let out = try await ProcessRunner().run("/bin/sh", ["-c", "echo hi; echo err >&2; exit 3"], environment: [:])
        #expect(out.status == 3)
        #expect(out.output.contains("hi"))
        #expect(out.output.contains("err"))
    }
}
