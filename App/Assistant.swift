import CleanerKit
import FoundationModels
import SwiftUI

/// Apple Intelligence on this Mac: explains items and summarises a scan. Prompts carry names, paths and sizes only,
/// and the model runs on device, so nothing leaves the Mac.
@Observable @MainActor
final class Assistant {
    struct Request: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let prompt: String
    }

    var request: Request?
    var text = ""
    var working = false
    var error: String?
    private var task: Task<Void, Never>?

    /// Why the model cannot answer on this Mac, or nil when it can.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "This Mac does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in System Settings › Apple Intelligence & Siri to use this."
        case .unavailable(.modelNotReady): "Apple Intelligence is still getting ready. Try again in a few minutes."
        case .unavailable: "Apple Intelligence is not available right now."
        }
    }

    func ask(_ title: String, subtitle: String = "", prompt: String) {
        task?.cancel()
        request = Request(title: title, subtitle: subtitle, prompt: prompt)
        text = ""
        error = Self.unavailableReason
        guard error == nil else { return }
        working = true
        task = Task {
            defer { working = false }
            do {
                // A new session per request, so one answer cannot leak into the next.
                let session = LanguageModelSession(instructions: AIBrief.instructions)
                for try await snapshot in session.streamResponse(to: prompt, options: GenerationOptions(temperature: 0.2)) {
                    text = snapshot.content
                }
            } catch is CancellationError {
            } catch {
                self.error = "Apple Intelligence could not answer: \(error.localizedDescription)"
            }
        }
    }

    func cancel() {
        task?.cancel()
        working = false
    }
}

extension AppModel {
    func explain(_ node: Node) {
        let finding = findings.first { $0.path == node.path }
        explainer.ask(node.name, subtitle: node.path.tilde, prompt: AIBrief.explain(node, finding: finding, home: AppHome.path))
    }

    func explain(_ finding: Finding) {
        let node = root?.find(finding.path)
            ?? Node(path: finding.path, name: (finding.path as NSString).lastPathComponent, kind: .directory,
                    size: finding.size, fileCount: 0, modified: nil)
        explainer.ask(finding.rule.title, subtitle: finding.path.tilde, prompt: AIBrief.explain(node, finding: finding, home: AppHome.path))
    }

    func summarise() {
        guard let root else { return }
        summariser.ask("Scan Summary", prompt: AIBrief.summary(
            root: root, findings: findings, largeFiles: LargeFiles.list(in: root, minimumSize: 500_000_000),
            deniedCount: result?.denied.count ?? 0, home: AppHome.path))
    }
}

/// The model's answer, with markdown such as **bold** and bullet lists.
struct AssistantText: View {
    let text: String

    var body: some View {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        Text((try? AttributedString(markdown: text, options: options)) ?? AttributedString(text))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AssistantNote: View {
    var body: some View {
        Label("Written on this Mac by Apple Intelligence and may be wrong. The Safe and Review ratings come from the app's own rules.",
              systemImage: "sparkles")
            .font(.caption).foregroundStyle(.secondary)
    }
}

struct ExplainSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: Assistant.Request

    var body: some View {
        let assistant = model.explainer
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Label(request.title, systemImage: "sparkles").font(.title2.bold())
                if !request.subtitle.isEmpty {
                    Text(request.subtitle).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            ScrollView {
                if let error = assistant.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if assistant.text.isEmpty {
                    ProgressView("Thinking…").frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    AssistantText(text: assistant.text)
                }
            }
            Spacer(minLength: 0)
            AssistantNote()
            HStack {
                Spacer()
                Button("Done") {
                    assistant.cancel()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 340)
    }
}
