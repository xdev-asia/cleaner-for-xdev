import CleanerKit
import SwiftUI

struct ConfirmSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let pending: PendingCleanup

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(pending.title).font(.title2.bold())
            if model.results.isEmpty && !model.cleaning { preview } else { outcome }
        }
        .padding(20)
        .frame(width: 620, height: 480)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(pending.items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(item.title).bold()
                        Spacer()
                        Text(item.size.bytes).monospacedDigit()
                    }
                    ForEach(Array(item.steps.enumerated()), id: \.offset) { _, step in
                        Text(describe(step)).font(.caption.monospaced())
                            .foregroundStyle(isPermanent(step) ? .red : .secondary)
                            .lineLimit(2).truncationMode(.middle)
                    }
                }
            }
            .listStyle(.bordered)
            if pending.deletesPermanently {
                Label("The Trash will be emptied permanently. This cannot be undone.", systemImage: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red).bold()
            }
            if pending.movesToTrash {
                Text("Files moved to the Trash keep using space until the Trash is emptied.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Text("Total: \(pending.total.bytes)").bold().monospacedDigit()
                Spacer()
                Button("Cancel", role: .cancel) { model.pending = nil }
                    .keyboardShortcut(.cancelAction)
                Button(pending.deletesPermanently ? "Delete Permanently" : "Clean", role: .destructive) { model.runPending() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
    }

    private var outcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(model.results) { result in
                HStack(alignment: .top) {
                    Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(result.succeeded ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title).bold()
                        if !result.message.isEmpty {
                            Text(result.message).font(.caption.monospaced()).foregroundStyle(.secondary)
                                .lineLimit(6).textSelection(.enabled)
                        }
                    }
                }
            }
            .listStyle(.bordered)
            HStack {
                if model.cleaning {
                    ProgressView().controlSize(.small)
                    Text("Cleaning \(model.results.count + 1) of \(pending.items.count)…")
                } else {
                    let ok = model.results.filter(\.succeeded).count
                    Text("Done: \(ok) of \(pending.items.count) items.")
                }
                Spacer()
                Button("Close") { model.pending = nil }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.cleaning)
            }
        }
    }

    private func isPermanent(_ step: CleanupStep) -> Bool {
        if case .emptyTrash = step { true } else { false }
    }

    private func describe(_ step: CleanupStep) -> String {
        switch step {
        case .trash(let path): "Move to Trash: \(path.tilde)"
        case .trashContents(let path): "Move contents to Trash: \(path.tilde)/*"
        case .emptyTrash(let path): "XOÁ VĨNH VIỄN: \(path.tilde)/*"
        case .run(let tool, let arguments): "Run: \(([tool] + arguments).joined(separator: " "))"
        }
    }
}
