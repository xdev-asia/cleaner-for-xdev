import Foundation
import Testing
@testable import CleanerKit

@Suite struct SandboxTests {
    @Test func sandboxedRulesOnlyMoveFilesToTheTrash() {
        #expect(!Rules.sandboxed.isEmpty)
        for rule in Rules.sandboxed {
            #expect(rule.action == .trashItem || rule.action == .trashContents, "\(rule.id)")
            #expect(rule.match != .docker, "\(rule.id)")
        }
    }

    @Test func sandboxedRulesKeepEveryTrashRule() {
        let trashRules = Rules.standard.filter { $0.action == .trashItem || $0.action == .trashContents }
        #expect(Rules.sandboxed.map(\.id) == trashRules.map(\.id))
        #expect(!Rules.sandboxed.contains { $0.id == "system.trash" })
    }

    @Test func userHomeIsTheAccountHomeOutsideTheSandbox() {
        // Tests do not run sandboxed, so both agree here; inside the sandbox NSHomeDirectory() is the container.
        #expect(UserHome.path == NSHomeDirectory())
    }
}
