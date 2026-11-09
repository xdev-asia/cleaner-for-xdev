import Foundation
import Testing
@testable import CleanerKit

@Suite struct AIBriefTests {
    let home = "/Users/t"
    let now = Date(timeIntervalSince1970: 1_000_000_000)

    func derivedData() -> (Node, Finding) {
        let child = Node(path: "/Users/t/Library/Developer/Xcode/DerivedData/App-abc", name: "App-abc", kind: .directory,
                         size: 6_000_000_000, fileCount: 900, modified: nil)
        let node = Node(path: "/Users/t/Library/Developer/Xcode/DerivedData", name: "DerivedData", kind: .directory,
                        size: 9_000_000_000, fileCount: 1_200, modified: now.addingTimeInterval(-2 * 86_400), children: [child])
        let rule = Rules.standard.first { $0.id == "xcode.derivedData" }!
        return (node, Finding(rule: rule, path: node.path, size: node.size, steps: [.trashContents(node.path)],
                              blockedReason: nil, toolMissing: false))
    }

    @Test func explainCarriesTheAppRatingAndFacts() {
        let (node, finding) = derivedData()
        let prompt = AIBrief.explain(node, finding: finding, now: now, home: home)
        #expect(prompt.contains("folder ~/Library/Developer/Xcode/DerivedData"))
        #expect(prompt.contains("Rating: Safe"))
        #expect(prompt.contains(finding.rule.explanation))
        #expect(prompt.contains("last modified 2 days ago"))
        #expect(prompt.contains("App-abc"))
    }

    @Test func explainWithoutRuleSaysSo() {
        let file = Node(path: "/Users/t/Movies/trip.mov", name: "trip.mov", kind: .file, size: 4_000_000_000,
                        fileCount: 1, modified: nil)
        let prompt = AIBrief.explain(file, finding: nil, now: now, home: home)
        #expect(prompt.contains("file ~/Movies/trip.mov"))
        #expect(prompt.contains("App rule: none"))
        #expect(!prompt.contains("Rating:"))
    }

    @Test func instructionsForbidContradictingTheRating() {
        #expect(AIBrief.instructions.contains("never change it"))
        #expect(AIBrief.instructions.contains("Never suggest Terminal commands"))
    }

    @Test func summaryGroupsFindingsByTheAppRating() {
        let (node, finding) = derivedData()
        let small = Finding(rule: Rules.standard.first { $0.id == "xcode.archives" }!, path: "/Users/t/Library/Developer/Xcode/Archives",
                            size: 1_000, steps: [], blockedReason: nil, toolMissing: false)
        let root = Node(path: home, name: "t", kind: .directory, size: 10_000_000_000, fileCount: 5_000, modified: nil,
                        children: [node])
        let prompt = AIBrief.summary(root: root, findings: [small, finding], largeFiles: [], deniedCount: 3, home: home)
        let lines = prompt.split(separator: "\n").map(String.init)
        let safeHeader = lines.firstIndex { $0.hasPrefix("Rated Safe") }!
        let reviewHeader = lines.firstIndex { $0.hasPrefix("Rated Review") }!
        #expect(lines[safeHeader + 1].contains("Xcode DerivedData"))
        #expect(lines[reviewHeader + 1].contains("Xcode Archives"))
        #expect(prompt.hasPrefix("Scanned ~:"))
        #expect(prompt.contains("3 folders could not be read"))
    }
}
