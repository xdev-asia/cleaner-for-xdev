import Foundation

/// Prompts for the on-device language model. They carry scan facts only (names, paths, sizes, dates and the
/// app's own rule), never file contents, so nothing private beyond what the app already shows goes into them.
public enum AIBrief {
    public static let instructions = """
    You are the assistant inside Cleaner for xDev, a macOS app that frees disk space on developer Macs. \
    Answer in plain English for a developer.
    Rules:
    - Use only the facts given and general knowledge of macOS, apps and developer tools.
    - Every item the app can clean comes with a rating, Safe or Review, decided by the app. Copy the rating exactly \
    as given; never change it or rate an item yourself.
    - When the app has no rule for an item, say that the app cannot tell whether it is safe to remove, \
    and that the user should check it first.
    - Cleaner for xDev never creates files. Name the app or tool that usually creates the item, or say you do not know.
    - Cleaning only moves items to the Trash; nothing is deleted until the Trash is emptied.
    - Never suggest Terminal commands. Do not invent file contents.
    """

    /// Asks what an item is and what cleaning it would do.
    public static func explain(_ node: Node, finding: Finding?, now: Date = Date(), home: String = UserHome.path) -> String {
        var lines = ["Item: \(describe(node, now: now, home: home))."]
        lines.append(rating(finding))
        let contents = node.children.filter { $0.kind != .smallFiles }.prefix(5)
        if !contents.isEmpty {
            lines.append("Largest contents: " + contents.map { "\($0.name) (\(bytes($0.size)))" }.joined(separator: ", ") + ".")
        }
        lines.append("In at most four short sentences: what is this item and which app or tool most likely made it, "
            + "will it come back if removed, and what does the app's rating mean for it?")
        return lines.joined(separator: "\n")
    }

    /// Asks for advice on a whole scan.
    public static func summary(root: Node, findings: [Finding], largeFiles: [Node], deniedCount: Int,
                               home: String = UserHome.path) -> String {
        var lines = ["Scanned \(tilde(root.path, home: home)): \(bytes(root.size)) in \(root.fileCount) files."]
        let top = root.children.filter { $0.kind != .smallFiles }.prefix(8)
        if !top.isEmpty {
            lines.append("Largest items: " + top.map { "\($0.name) (\(bytes($0.size)))" }.joined(separator: ", ") + ".")
        }
        let ranked = findings.sorted { $0.size > $1.size }
        let safe = ranked.filter { $0.rule.safety == .safe }.prefix(6)
        let review = ranked.filter { $0.rule.safety == .review }.prefix(6)
        if findings.isEmpty { lines.append("The app found nothing it knows how to clean.") }
        if !safe.isEmpty {
            lines.append("Rated Safe (rebuilt automatically, fine to clean):")
            lines += safe.map { "- \(item($0, home: home))" }
        }
        if !review.isEmpty {
            lines.append("Rated Review (check before cleaning):")
            lines += review.map { "- \(item($0, home: home))" }
        }
        if !largeFiles.isEmpty {
            lines.append("Large files: " + largeFiles.prefix(5).map { "\(tilde($0.path, home: home)) (\(bytes($0.size)))" }
                .joined(separator: ", ") + ".")
        }
        if deniedCount > 0 { lines.append("\(deniedCount) folders could not be read.") }
        lines.append("Write three short bullet points: where the space goes; what to clean first, naming only items "
            + "rated Safe, or saying there are none; and what to check before removing, naming items rated Review and large files.")
        return lines.joined(separator: "\n")
    }

    static func item(_ f: Finding, home: String) -> String {
        f.rule.title + (f.path.isEmpty ? "" : " at \(tilde(f.path, home: home))") + ", \(bytes(f.size))"
    }

    static func rating(_ finding: Finding?) -> String {
        guard let finding else { return "App rule: none. The app has no rule for this item." }
        let rating = finding.rule.safety == .safe ? "Safe" : "Review"
        return "App rule: \"\(finding.rule.title)\". Rating: \(rating). Rule note: \(finding.rule.explanation)"
    }

    static func describe(_ node: Node, now: Date, home: String) -> String {
        var text = "\(node.kind == .file ? "file" : "folder") \(tilde(node.path, home: home)), \(bytes(node.size))"
        if node.kind == .directory { text += ", \(node.fileCount) files" }
        if let modified = node.modified {
            let days = max(0, Int(now.timeIntervalSince(modified) / 86_400))
            text += ", last modified \(days == 0 ? "today" : "\(days) days ago")"
        }
        return text
    }

    static func tilde(_ path: String, home: String) -> String {
        path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    static func bytes(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
