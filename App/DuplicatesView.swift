import CleanerKit
import SwiftUI

struct DuplicatesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if model.findingDuplicates {
                    ProgressView().controlSize(.small)
                    Text("Comparing file contents…")
                    Button("Stop") { model.cancelDuplicates() }
                } else {
                    Button(model.duplicatesSearched ? "Search Again" : "Find Duplicates") { model.findDuplicates() }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
                if !groups.isEmpty {
                    Text("\(groups.count) groups, wasting \(groups.reduce(Int64(0)) { $0 + $1.wasted }.bytes)")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .padding(12)
            Divider()
            if groups.isEmpty {
                ContentUnavailableView {
                    Label(model.duplicatesSearched ? "No Duplicates" : "Not Searched", systemImage: "doc.on.doc")
                } description: {
                    Text("Compares files of 1 MB or more in the scanned area: same size, same first 64 KB, then same SHA-256.")
                }
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.files.filter { !model.isRemoved($0.path) }) { file in
                                DuplicateRow(file: file)
                            }
                        } header: {
                            HStack {
                                Text("\(group.files.count) copies × \(group.files[0].size.bytes)")
                                Spacer()
                                Text("wasting \(group.wasted.bytes)").monospacedDigit()
                            }
                        }
                    }
                    Section {
                        Text("APFS clones share their data on disk but still appear here, because macOS has no public API to tell them apart; deleting them may not free any space.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                footer
            }
        }
    }

    private var groups: [DuplicateGroup] {
        model.duplicates.filter { $0.files.filter { !model.isRemoved($0.path) }.count > 1 }
    }

    private var footer: some View {
        let selected = groups.flatMap(\.files).filter { model.selectedDuplicates.contains($0.path) }
        return HStack {
            Button("Select Copies (Keep Oldest)") { model.selectDuplicateCopies() }
            Button("Deselect All") { model.selectedDuplicates = [] }.disabled(selected.isEmpty)
            Spacer()
            Text("\(selected.count) files selected, \(selected.reduce(Int64(0)) { $0 + $1.size }.bytes)").monospacedDigit()
            Button("Move to Trash…") { model.confirmTrash(selected) }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty || groups.contains { g in g.files.allSatisfy { model.selectedDuplicates.contains($0.path) } })
                .help("You cannot select every copy in a group")
        }
        .padding(12)
    }
}

struct DuplicateRow: View {
    @Environment(AppModel.self) private var model
    let file: Node

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { model.selectedDuplicates.contains(file.path) },
                set: { on in
                    if on { model.selectedDuplicates.insert(file.path) } else { model.selectedDuplicates.remove(file.path) }
                }))
            .toggleStyle(.checkbox).labelsHidden()
            Text(file.path.tilde).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(file.modified?.formatted(date: .abbreviated, time: .shortened) ?? "").foregroundStyle(.secondary)
        }
        .contextMenu { Button("Show in Finder") { model.reveal(file.path) } }
    }
}
