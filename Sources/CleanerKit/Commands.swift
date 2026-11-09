import Foundation

public struct CommandOutput: Sendable, Equatable {
    public let status: Int32
    public let output: String

    public init(status: Int32, output: String) {
        self.status = status
        self.output = output
    }
}

public protocol CommandRunning: Sendable {
    /// Runs `executable` (absolute path) and returns its exit status with stdout and stderr combined.
    func run(_ executable: String, _ arguments: [String], environment: [String: String]) async throws -> CommandOutput
}

public struct ProcessRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, _ arguments: [String], environment: [String: String]) async throws -> CommandOutput {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            var env = ProcessInfo.processInfo.environment
            env.merge(environment) { _, new in new }
            process.environment = env
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            try process.run()
            let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            return CommandOutput(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
        }.value
    }
}

/// Finds command-line tools. Apps opened from Finder do not get the shell's PATH, so the usual install
/// locations are searched explicitly.
public struct ToolLocator: Sendable {
    public let searchPaths: [String]
    private let fileExists: @Sendable (String) -> Bool

    public init(searchPaths: [String], fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) {
        self.searchPaths = searchPaths
        self.fileExists = fileExists
    }

    public static func standard(home: String = UserHome.path) -> ToolLocator {
        var paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                     home + "/.rd/bin", "/Applications/Docker.app/Contents/Resources/bin",
                     home + "/.orbstack/bin", home + "/.cargo/bin", home + "/Library/pnpm",
                     home + "/.local/bin", home + "/.volta/bin", home + "/.bun/bin"]
        let nvm = home + "/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            paths += versions.sorted().reversed().map { nvm + "/" + $0 + "/bin" }
        }
        return ToolLocator(searchPaths: paths)
    }

    public func locate(_ tool: String) -> String? {
        searchPaths.lazy.map { $0 + "/" + tool }.first(where: fileExists)
    }

    /// Environment for child processes, so tools can find each other (pnpm needs node, docker its plugins).
    public var environment: [String: String] {
        ["PATH": searchPaths.joined(separator: ":")]
    }
}
