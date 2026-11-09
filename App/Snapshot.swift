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

    /// `--screenshot <section>`: sizes the window to 1440×900 for App Store screenshots, opens the section, and with
    /// `--ai` writes the scan summary or, with `--explain`, opens the explanation of the largest cleanable item.
    static func screenshot(_ model: AppModel) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--screenshot"), i + 1 < args.count,
              let section = SidebarSection(rawValue: args[i + 1]) else { return }
        Task {
            while model.scanning || model.analysing || model.result == nil { try? await Task.sleep(for: .milliseconds(200)) }
            if section == .duplicates { model.findDuplicates() }
            model.section = section
            if let window = NSApp.windows.first(where: \.isVisible), let screen = window.screen {
                let size = NSSize(width: 1440, height: 900)
                window.setFrame(NSRect(origin: NSPoint(x: screen.visibleFrame.midX - size.width / 2,
                                                       y: screen.visibleFrame.midY - size.height / 2), size: size),
                                display: true)
            }
            if args.contains("--ai") { model.summarise() }
            if args.contains("--explain"), let finding = model.findings.max(by: { $0.size < $1.size }) { model.explain(finding) }
        }
    }

    static func run(_ model: AppModel) {
        screenshot(model)
        guard let directory else { return }
        Task {
            while model.scanning || model.analysing || model.result == nil { try? await Task.sleep(for: .milliseconds(200)) }
            model.findDuplicates()
            while model.findingDuplicates { try? await Task.sleep(for: .milliseconds(200)) }
            var ai = ""
            if CommandLine.arguments.contains("--ai") {
                model.summarise()
                while model.summariser.working { try? await Task.sleep(for: .milliseconds(200)) }
                ai += "summary: \(model.summariser.error ?? model.summariser.text)\n"
                if let finding = model.findings.first {
                    model.explain(finding)
                    while model.explainer.working { try? await Task.sleep(for: .milliseconds(200)) }
                    ai += "explain \(finding.rule.id): \(model.explainer.error ?? model.explainer.text)\n"
                    model.explainer.request = nil
                }
            }
            for section in SidebarSection.allCases {
                model.section = section
                try? await Task.sleep(for: .seconds(1))
                guard let view = NSApp.windows.first(where: \.isVisible)?.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: directory + "/\(section.rawValue).png"))
            }
            // Every view must fit the window; a view taller than the window gets centred and looks blank.
            var report = ai
            if let content = NSApp.windows.first(where: \.isVisible)?.contentView {
                let tallest = content.subviews.map(\.frame.height).max() ?? 0
                report += tallest > content.bounds.height + 1 ? "layout overflow \(tallest) > \(content.bounds.height)\n" : "layout ok\n"
            }
            report += "scanned \(model.result?.root.size ?? 0) files \(model.result?.root.fileCount ?? 0) denied \(model.result?.denied.count ?? 0)\n"
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
