import Testing
@testable import CleanerKit

@Suite struct SafetyGuardTests {
    let guardian = SafetyGuard(home: "/Users/tester")

    @Test(arguments: [
        "/Users/tester/Library/Developer/Xcode/DerivedData",
        "/Users/tester/Library/Caches/com.example",
        "/Users/tester/Work/app/node_modules",
        "/Users/tester/Downloads/big.dmg",
        "/Applications/Old.app",
    ])
    func allowsCleanablePaths(path: String) {
        #expect(guardian.check(path) == .allowed)
    }

    @Test(arguments: [
        "/", "/System", "/System/Library/Kernels", "/usr/lib", "/bin/ls", "/sbin",
        "/Library/Caches", "/private/etc/hosts", "/etc", "/dev/disk0",
        "/Users", "/Users/tester", "/Users/tester/Library", "/Users/tester/Library/Caches",
        "/Users/tester/Documents", "/Users/tester/Desktop", "/Users/tester/Downloads",
        "/Users/tester/.ssh/id_ed25519", "/Users/tester/Library/Keychains/login.keychain-db",
        "/Applications", "/Volumes",
    ])
    func refusesProtectedPaths(path: String) {
        #expect(guardian.check(path) != .allowed)
    }

    @Test func refusesRelativeAndDotDotEscapes() {
        #expect(guardian.check("Work/app") != .allowed)
        #expect(guardian.check("/Users/tester/Work/../Library") != .allowed)
        #expect(guardian.check("/Users/tester/Library/Caches/..") != .allowed)
    }

    @Test func refusesAncestorsOfProtectedPaths() {
        #expect(guardian.check("/Users/tester/Library/..") != .allowed)
        #expect(guardian.check("/private") != .allowed)
    }
}
