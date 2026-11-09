import CleanerKit
import SwiftUI

struct CleanableView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if model.analysing {
                ProgressView("Analysing…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.findings.isEmpty {
                ContentUnavailableView("Nothing to clean", systemImage: "checkmark.seal",
                                       description: Text("No caches or build outputs were found in the scanned area."))
            } else {
                list
                Divider()
                footer
            }
        }
    }

    private var list: some View {
        List {
            ForEach(RuleCategory.allCases, id: \.self) { category in
                let items = model.findings.filter { $0.rule.category == category }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { FindingRow(finding: $0) }
                    } header: {
                        HStack {
                            Text(category.rawValue)
                            Spacer()
                            Text(items.reduce(Int64(0)) { $0 + $1.size }.bytes).monospacedDigit()
                        }
                    }
                }
            }
            Section {
                Text("\"Review\" items are not selected by default. Files moved to the Trash only free their space once the Trash is emptied.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        let selected = model.findings.filter { model.selectedFindings.contains($0.id) && $0.blockedReason == nil && !$0.toolMissing }
        return HStack {
            Text("\(selected.count) items selected, \(selected.reduce(Int64(0)) { $0 + $1.size }.bytes)").monospacedDigit()
            Spacer()
            Button("Deselect All") { model.selectedFindings = [] }.disabled(selected.isEmpty)
            Button("Clean Selected…") { model.confirmFindings() }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
        }
        .padding(12)
    }
}

struct FindingRow: View {
    @Environment(AppModel.self) private var model
    let finding: Finding

    var body: some View {
        let disabled = finding.blockedReason != nil || finding.toolMissing
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { model.selectedFindings.contains(finding.id) },
                set: { on in
                    if on { model.selectedFindings.insert(finding.id) } else { model.selectedFindings.remove(finding.id) }
                }))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(disabled)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(finding.rule.title).bold()
                    SafetyBadge(safety: finding.rule.safety)
                }
                if !finding.path.isEmpty {
                    Text(finding.path.tilde).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Text(finding.rule.explanation).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason = finding.blockedReason {
                    Label(reason, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                if finding.toolMissing {
                    Label("Required command-line tool not found", systemImage: "wrench.and.screwdriver")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(finding.size.bytes).monospacedDigit().bold()
            Button {
                model.explain(finding)
            } label: {
                Image(systemName: "sparkles")
            }
            .buttonStyle(.borderless)
            .help("Explain with Apple Intelligence")
        }
        .opacity(disabled ? 0.6 : 1)
        .contextMenu {
            if !finding.path.isEmpty { Button("Show in Finder") { model.reveal(finding.path) } }
            Button("Explain with Apple Intelligence") { model.explain(finding) }
        }
    }
}
