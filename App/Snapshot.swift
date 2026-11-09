import AppKit
import CleanerKit

/// `--snapshot <dir>`: after the launch scan, renders each section of the main window to PNG and quits.
/// Used to check the UI and make README screenshots without Screen Recording permission.
@MainActor
enum Snapshot {
    static var directory: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func run(_ model: AppModel) {
        guard let directory else { return }
        Task {
            while model.scanning || model.analysing || model.result == nil { try? await Task.sleep(for: .milliseconds(200)) }
            model.findDuplicates()
            while model.findingDuplicates { try? await Task.sleep(for: .milliseconds(200)) }
            for section in SidebarSection.allCases {
                model.section = section
                try? await Task.sleep(for: .seconds(1))
                guard let view = NSApp.windows.first(where: \.isVisible)?.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: directory + "/\(section.rawValue).png"))
            }
            var report = "scanned \(model.result?.root.size ?? 0) files \(model.result?.root.fileCount ?? 0) denied \(model.result?.denied.count ?? 0)\n"
            for f in model.findings {
                report += "finding \(f.rule.id) \(f.path.tilde) \(f.size) selected=\(model.selectedFindings.contains(f.id)) toolMissing=\(f.toolMissing) \(f.steps)\n"
            }
            if let root = model.root {
                for file in LargeFiles.list(in: root, minimumSize: 10_000_000) { report += "large \(file.path.tilde) \(file.size)\n" }
            }
            for group in model.duplicates { report += "dup \(group.files.map(\.name)) wasted \(group.wasted)\n" }
            if CommandLine.arguments.contains("--clean-selected") {
                model.confirmFindings()
                model.runPending()
                try? await Task.sleep(for: .milliseconds(300))
                while model.cleaning { try? await Task.sleep(for: .milliseconds(200)) }
                for r in model.results { report += "result \(r.id) ok=\(r.succeeded) \(r.message.prefix(200))\n" }
            }
            try? report.write(toFile: directory + "/report.txt", atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }
}
