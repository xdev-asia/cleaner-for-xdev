import CleanerKit
import SwiftUI

struct LargeFilesView: View {
    @Environment(AppModel.self) private var model
    @State private var minimum: Int64 = 100_000_000
    @State private var kind: FileKind?
    @State private var olderThanYear = false
    @State private var selection: Set<Node.ID> = []
    @State private var sortOrder = [KeyPathComparator(\Node.size, order: .reverse)]

    private static let sizes: [Int64] = [10_000_000, 100_000_000, 500_000_000, 1_000_000_000, 5_000_000_000]

    var body: some View {
        let files = filtered
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Picker("At least", selection: $minimum) {
                    ForEach(Self.sizes, id: \.self) { Text($0.bytes).tag($0) }
                }
                .fixedSize()
                Picker("Kind", selection: $kind) {
                    Text("All").tag(FileKind?.none)
                    ForEach(FileKind.allCases, id: \.self) { Text($0.rawValue).tag(FileKind?.some($0)) }
                }
                .fixedSize()
                Toggle("Not modified in a year", isOn: $olderThanYear)
                Spacer()
                Text("\(files.count) file, \(files.reduce(Int64(0)) { $0 + $1.size }.bytes)").monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            Table(files, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { node in
                    Label(node.name, systemImage: "doc.fill").lineLimit(1)
                }
                TableColumn("Folder", value: \.path) { node in
                    Text((node.path as NSString).deletingLastPathComponent.tilde)
                        .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                }
                TableColumn("Modified", value: \.modifiedSortKey) { node in
                    Text(node.modified?.formatted(date: .abbreviated, time: .omitted) ?? "")
                }
                .width(min: 90, ideal: 110)
                TableColumn("Size", value: \.size) { node in
                    Text(node.size.bytes).monospacedDigit()
                }
                .width(min: 80, ideal: 100)
            }
            .contextMenu(forSelectionType: Node.ID.self) { ids in
                menu(files.filter { ids.contains($0.id) })
            } primaryAction: { ids in
                files.filter { ids.contains($0.id) }.forEach { model.reveal($0.path) }
            }
            Divider()
            HStack {
                Text("Only files of 1 MB or more. Double-click to show in Finder.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Move to Trash…") { model.confirmTrash(files.filter { selection.contains($0.id) }) }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection.isEmpty)
            }
            .padding(12)
        }
    }

    private var filtered: [Node] {
        guard let root = model.root else { return [] }
        let cutoff = olderThanYear ? Calendar.current.date(byAdding: .year, value: -1, to: .now) : nil
        return LargeFiles.list(in: root, minimumSize: minimum, kind: kind, modifiedBefore: cutoff)
            .filter { !model.isRemoved($0.path) }
            .sorted(using: sortOrder)
    }

    @ViewBuilder private func menu(_ nodes: [Node]) -> some View {
        if !nodes.isEmpty {
            Button("Show in Finder") { nodes.forEach { model.reveal($0.path) } }
            if nodes.count == 1 { Button("Explain with Apple Intelligence") { model.explain(nodes[0]) } }
            Divider()
            Button("Move to Trash…", role: .destructive) { model.confirmTrash(nodes) }
        }
    }
}

extension Node {
    var modifiedSortKey: Date { modified ?? .distantPast }
}
