import Foundation

public protocol Trashing: Sendable {
    func trash(_ path: String) throws
}

public struct FinderTrash: Trashing {
    public init() {}
    public func trash(_ path: String) throws {
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
    }
}

public struct StepResult: Sendable, Identifiable {
    public let id = UUID()
    public let step: CleanupStep
    public let succeeded: Bool
    public let message: String
}

/// Carries out cleanup steps. Files go to the Trash; only the Empty Trash step deletes permanently.
public struct Cleaner: Sendable {
    let safety: SafetyGuard
    let runner: CommandRunning
    let tools: ToolLocator
    let trasher: Trashing
    let home: String

    public init(guard safety: SafetyGuard = SafetyGuard(), runner: CommandRunning = ProcessRunner(),
                tools: ToolLocator = .standard(), trasher: Trashing = FinderTrash()) {
        self.safety = safety
        self.runner = runner
        self.tools = tools
        self.trasher = trasher
        self.home = safety.home
    }

    public func perform(_ steps: [CleanupStep]) async -> [StepResult] {
        var results: [StepResult] = []
        for step in steps {
            if Task.isCancelled { break }
            results.append(await perform(step))
        }
        return results
    }

    public func perform(_ step: CleanupStep) async -> StepResult {
        func done(_ ok: Bool, _ message: String) -> StepResult { StepResult(step: step, succeeded: ok, message: message) }
        switch step {
        case .trash(let path):
            if let refusal = refusal(path) { return done(false, refusal) }
            do { try trasher.trash(path); return done(true, "Moved to Trash") } catch {
                return done(false, error.localizedDescription)
            }
        case .trashContents(let path):
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: path) else {
                return done(false, "Could not read the folder")
            }
            var failures: [String] = []
            for item in items {
                let full = path + "/" + item
                if let refusal = refusal(full) { failures.append("\(item): \(refusal)"); continue }
                do { try trasher.trash(full) } catch { failures.append("\(item): \(error.localizedDescription)") }
            }
            return failures.isEmpty ? done(true, "Moved \(items.count) items to Trash")
                : done(false, failures.prefix(5).joined(separator: "\n"))
        case .emptyTrash(let path):
            guard URL(fileURLWithPath: path).standardizedFileURL.path == home + "/.Trash" else {
                return done(false, "Permanent deletion is only allowed in ~/.Trash")
            }
            let items = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            var failures: [String] = []
            for item in items {
                do { try FileManager.default.removeItem(atPath: path + "/" + item) } catch { failures.append(item) }
            }
            return failures.isEmpty ? done(true, "Permanently deleted \(items.count) items")
                : done(false, "Could not delete: " + failures.prefix(5).joined(separator: ", "))
        case .run(let tool, let arguments):
            guard let executable = tools.locate(tool) else { return done(false, "\(tool) not found") }
            do {
                let out = try await runner.run(executable, arguments, environment: tools.environment)
                return done(out.status == 0, out.output.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                return done(false, error.localizedDescription)
            }
        }
    }

    private func refusal(_ path: String) -> String? {
        if case .refused(let reason) = safety.check(path) { return reason }
        return nil
    }
}
