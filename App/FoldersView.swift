import CleanerKit
import SwiftUI

struct FoldersView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<Node.ID> = []

    var body: some View {
        if let node = model.focusNode {
            let children = node.children.filter { !model.isRemoved($0.path) }
            VStack(spacing: 0) {
                breadcrumb(node)
                Divider()
                HSplitView {
                    TreemapView(nodes: children) { open($0) }
                        .padding(8)
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                    table(children, parent: node)
                        .frame(minWidth: 340, idealWidth: 420)
                }
            }
        }
    }

    private func open(_ node: Node) {
        if node.kind == .directory {
            selection = []
            model.focusPath = node.path
        }
    }

    private func breadcrumb(_ node: Node) -> some View {
        let rootPath = model.root?.path ?? "/"
        var trail: [String] = [rootPath]
        if node.path != rootPath {
            let relative = node.path.dropFirst(rootPath == "/" ? 1 : rootPath.count + 1)
            var current = rootPath == "/" ? "" : rootPath
            for part in relative.split(separator: "/") {
                current += "/" + part
                trail.append(current)
            }
        }
        return HStack(spacing: 4) {
            Button {
                if let parent = trail.dropLast().last { model.focusPath = parent }
            } label: { Image(systemName: "chevron.left") }
            .disabled(trail.count < 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(trail, id: \.self) { path in
                        if path != trail.first { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                        Button(path == rootPath ? rootPath.tilde : (path as NSString).lastPathComponent) {
                            model.focusPath = path
                        }
                        .buttonStyle(.borderless)
                        .fontWeight(path == node.path ? .semibold : .regular)
                    }
                }
            }
            Spacer()
            Text(node.size.bytes).monospacedDigit().foregroundStyle(.secondary)
            Button { model.reveal(node.path) } label: { Image(systemName: "magnifyingglass") }
                .help("Show in Finder")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func table(_ children: [Node], parent: Node) -> some View {
        Table(children, selection: $selection) {
            TableColumn("Name") { node in
                Label {
                    Text(node.kind == .smallFiles ? "Small files (\(node.fileCount.formatted()))" : node.name).lineLimit(1)
                } icon: {
                    Image(systemName: node.kind == .directory ? "folder.fill" : node.kind == .file ? "doc.fill" : "square.stack.3d.up")
                        .foregroundStyle(node.kind == .directory ? Color.accentColor : .secondary)
                }
            }
            TableColumn("Size") { node in
                HStack {
                    ProgressView(value: Double(node.size), total: Double(max(parent.size, 1)))
                        .frame(width: 50)
                    Text(node.size.bytes).monospacedDigit()
                }
            }
            .width(min: 130, ideal: 150)
        }
        .contextMenu(forSelectionType: Node.ID.self) { ids in
            let nodes = children.filter { ids.contains($0.id) && $0.kind != .smallFiles }
            if !nodes.isEmpty {
                Button("Show in Finder") { nodes.forEach { model.reveal($0.path) } }
                Divider()
                Button("Move to Trash…", role: .destructive) { model.confirmTrash(nodes) }
            }
        } primaryAction: { ids in
            if let node = children.first(where: { ids.contains($0.id) }) { open(node) }
        }
    }
}

/// Squarified treemap of one level. Click a folder to open it.
struct TreemapView: View {
    let nodes: [Node]
    var onOpen: (Node) -> Void
    @State private var hovered: Int?

    private static let palette: [Color] = [.blue, .teal, .indigo, .purple, .cyan, .mint, .pink, .orange, .green, .brown]

    var body: some View {
        GeometryReader { geo in
            let items = Array(nodes.filter { $0.size > 0 }.prefix(400))
            let rects = Treemap.layout(items.map { Double($0.size) }, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .bottomLeading) {
                Canvas { context, _ in
                    for (index, node) in items.enumerated() {
                        let rect = rects[index].insetBy(dx: 1, dy: 1)
                        guard rect.width > 1, rect.height > 1 else { continue }
                        let shape = Path(roundedRect: rect, cornerRadius: min(4, rect.width / 4, rect.height / 4))
                        context.fill(shape, with: .color(color(node, index).opacity(hovered == index ? 1 : 0.78)))
                        if hovered == index { context.stroke(shape, with: .color(.white), lineWidth: 2) }
                        if rect.width > 56, rect.height > 30 {
                            let label = Text("\(node.kind == .smallFiles ? "Small files" : node.name)\n\(node.size.bytes)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                            context.draw(context.resolve(label), in: rect.insetBy(dx: 5, dy: 4))
                        }
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active(let point) = phase {
                        hovered = rects.firstIndex { $0.contains(point) }
                    } else {
                        hovered = nil
                    }
                }
                .onTapGesture { location in
                    if let index = rects.firstIndex(where: { $0.contains(location) }) { onOpen(items[index]) }
                }
                if let hovered, hovered < items.count {
                    let node = items[hovered]
                    Text("\(node.path.tilde) · \(node.size.bytes)")
                        .font(.caption).lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if items.isEmpty { ContentUnavailableView("Empty Folder", systemImage: "folder") }
            }
        }
    }

    private func color(_ node: Node, _ index: Int) -> Color {
        switch node.kind {
        case .smallFiles: .gray
        case .file: .secondary
        case .directory: Self.palette[index % Self.palette.count]
        }
    }
}
