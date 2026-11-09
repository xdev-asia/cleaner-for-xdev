import Foundation

/// Applies rules to a scanned tree and asks tools (Docker, git) for what the tree cannot tell.
public struct RuleMatcher: Sendable {
    public let rules: [Rule]
    public let home: String
    public let runner: CommandRunning
    public let tools: ToolLocator

    public init(rules: [Rule] = Rules.standard, home: String = NSHomeDirectory(),
                runner: CommandRunning = ProcessRunner(), tools: ToolLocator = .standard()) {
        self.rules = rules
        self.home = home
        self.runner = runner
        self.tools = tools
    }

    func expand(_ path: String) -> String {
        path == "~" ? home : path.hasPrefix("~/") ? home + path.dropFirst() : path
    }

    public func findings(in root: Node) async -> [Finding] {
        var raw: [(Rule, Node)] = []
        for rule in rules {
            switch rule.match {
            case .path(let path):
                if let node = root.find(expand(path)), node.size > 0 { raw.append((rule, node)) }
            case .files(let directory, let extensions):
                if let node = root.find(expand(directory)) {
                    for child in node.children where child.kind == .file
                        && extensions.contains((child.name as NSString).pathExtension.lowercased()) {
                        raw.append((rule, child))
                    }
                }
            case .directoryNamed, .directoryWithMarker, .docker:
                break
            }
        }
        collectProjectFolders(root, parent: nil, into: &raw)

        var findings: [Finding] = []
        for (rule, node) in raw {
            if let finding = await finding(rule, node) { findings.append(finding) }
        }
        if let rule = rules.first(where: { $0.match == .docker }), let docker = await DockerProbe(runner: runner, tools: tools).buildCache(), docker > 0 {
            findings.append(make(rule, path: "", size: docker))
        }
        return Self.removingNested(findings)
    }

    private func collectProjectFolders(_ node: Node, parent: Node?, into raw: inout [(Rule, Node)]) {
        guard node.kind == .directory else { return }
        for rule in rules {
            switch rule.match {
            case .directoryNamed(let name, let markers) where node.name == name:
                if let parent, !parent.markers.isDisjoint(with: markers) {
                    raw.append((rule, node))
                    return
                }
            case .directoryWithMarker(let marker) where node.markers.contains(marker):
                raw.append((rule, node))
                return
            default:
                continue
            }
        }
        for child in node.children { collectProjectFolders(child, parent: node, into: &raw) }
    }

    private func finding(_ rule: Rule, _ node: Node) async -> Finding? {
        guard rule.action == .gitWorktreeRemove else { return make(rule, path: node.path, size: node.size) }
        guard let main = GitWorktreeProbe.mainRepository(of: node.path) else { return nil }
        var blocked: String?
        if let git = tools.locate("git") {
            let status = try? await runner.run(git, ["-C", node.path, "status", "--porcelain", "--ignore-submodules=none"],
                                               environment: tools.environment)
            if status?.status != 0 {
                blocked = "Could not read git status"
            } else if let output = status?.output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocked = "Has uncommitted changes"
            }
        }
        let step = CleanupStep.run(tool: "git", arguments: ["-C", main, "worktree", "remove", "--force", node.path])
        return Finding(rule: rule, path: node.path, size: node.size, steps: [step], blockedReason: blocked,
                       toolMissing: tools.locate("git") == nil)
    }

    private func make(_ rule: Rule, path: String, size: Int64) -> Finding {
        let parent = (path as NSString).deletingLastPathComponent
        let step: CleanupStep
        switch rule.action {
        case .trashItem: step = .trash(path)
        case .trashContents: step = .trashContents(path)
        case .emptyTrash: step = .emptyTrash(path)
        case .command(let tool, let arguments):
            step = .run(tool: tool, arguments: arguments.map {
                $0.replacingOccurrences(of: "{path}", with: path).replacingOccurrences(of: "{parent}", with: parent)
            })
        case .gitWorktreeRemove: step = .run(tool: "git", arguments: [])
        }
        var missing = false
        if case .run(let tool, _) = step { missing = tools.locate(tool) == nil }
        return Finding(rule: rule, path: path, size: size, steps: [step], blockedReason: nil, toolMissing: missing)
    }

    /// Drops findings that sit inside another finding, so nothing is counted twice.
    static func removingNested(_ findings: [Finding]) -> [Finding] {
        var kept: [Finding] = []
        for finding in findings.sorted(by: { $0.path < $1.path }) {
            if !finding.path.isEmpty, kept.contains(where: { !$0.path.isEmpty && finding.path.hasPrefix($0.path + "/") }) {
                continue
            }
            kept.append(finding)
        }
        return kept.sorted { $0.size > $1.size }
    }
}

public enum GitWorktreeProbe {
    /// The main repository of a linked worktree, read from its `.git` file; nil for submodules and plain repos.
    public static func mainRepository(of worktree: String) -> String? {
        guard let text = try? String(contentsOfFile: worktree + "/.git", encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
        var gitdir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        if !gitdir.hasPrefix("/") { gitdir = URL(fileURLWithPath: worktree + "/" + gitdir).standardizedFileURL.path }
        guard let range = gitdir.range(of: "/.git/worktrees/") else { return nil }
        return String(gitdir[..<range.lowerBound])
    }
}

public struct DockerProbe: Sendable {
    let runner: CommandRunning
    let tools: ToolLocator

    /// Size of the Docker build cache in bytes, or nil when Docker is missing or not running.
    public func buildCache() async -> Int64? {
        guard let docker = tools.locate("docker"),
              let out = try? await runner.run(docker, ["system", "df", "--format", "{{json .}}"], environment: tools.environment),
              out.status == 0 else { return nil }
        for line in out.output.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let row = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  row["Type"] == "Build Cache", let size = row["Size"] else { continue }
            return Self.bytes(size)
        }
        return nil
    }

    /// Parses Docker's decimal sizes ("22.02GB", "1.5kB", "0B").
    public static func bytes(_ text: String) -> Int64? {
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("B", 1)]
        for (suffix, factor) in units where text.hasSuffix(suffix) {
            guard let value = Double(text.dropLast(suffix.count)) else { return nil }
            return Int64((value * factor).rounded())
        }
        return nil
    }
}
