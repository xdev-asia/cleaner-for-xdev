import Testing
@testable import CleanerKit

@Suite struct SmartScanTests {
    private func finding(_ ruleID: String, _ path: String, _ size: Int64, blocked: String? = nil, toolMissing: Bool = false) -> Finding {
        Finding(rule: Rules.standard.first { $0.id == ruleID }!, path: path, size: size, steps: [.trash(path)],
                blockedReason: blocked, toolMissing: toolMissing)
    }

    @Test func splitsCleanableFindingsBySafetyLargestFirst() {
        let summary = SmartScanSummary(findings: [
            finding("xcode.derivedData", "/h/DerivedData", 100),
            finding("node.nodeModules", "/h/a/node_modules", 300),
            finding("android.gradleCaches", "/h/.gradle/caches", 500),
            finding("node.nodeModules", "/h/b/node_modules", 50),
        ])
        #expect(summary.safe.map(\.path) == ["/h/.gradle/caches", "/h/DerivedData"])
        #expect(summary.review.map(\.path) == ["/h/a/node_modules", "/h/b/node_modules"])
        #expect(summary.safeTotal == 600)
        #expect(summary.reviewTotal == 350)
    }

    @Test func leavesOutBlockedAndToolMissingFindings() {
        let summary = SmartScanSummary(findings: [
            finding("xcode.derivedData", "/h/DerivedData", 100, blocked: "in use"),
            finding("node.npmCache", "/h/.npm", 200, toolMissing: true),
            finding("system.logs", "/h/Library/Logs", 10),
        ])
        #expect(summary.safe.map(\.path) == ["/h/Library/Logs"])
        #expect(summary.review.isEmpty)
        #expect(!summary.isEmpty)
        #expect(SmartScanSummary(findings: []).isEmpty)
    }

    @Test func defaultSelectionIsEverySafeItem() {
        let safe = finding("xcode.derivedData", "/h/DerivedData", 100)
        let review = finding("xcode.archives", "/h/Archives", 900)
        let summary = SmartScanSummary(findings: [safe, review])
        #expect(summary.defaultSelection == [safe.id])
    }

    @Test func selectedTotalCountsOnlyCleanableSelectedItems() {
        let safe = finding("xcode.derivedData", "/h/DerivedData", 100)
        let review = finding("xcode.archives", "/h/Archives", 900)
        let blocked = finding("system.logs", "/h/Library/Logs", 40, blocked: "in use")
        let summary = SmartScanSummary(findings: [safe, review, blocked])
        #expect(summary.selectedTotal([safe.id, review.id, blocked.id, "missing"]) == 1000)
        #expect(summary.selectedTotal([]) == 0)
    }
}
