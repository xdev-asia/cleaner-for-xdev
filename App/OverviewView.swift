import CleanerKit
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                volumes
                scanButtons
                if let error = model.scanError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                if let result = model.result { summary(result) }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private var volumes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Disks").font(.headline)
            ForEach(model.volumes) { volume in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: volume.path == "/" ? "internaldrive.fill" : "externaldrive.fill")
                        Text(volume.name).bold()
                        Spacer()
                        Text("\(volume.available.bytes) free of \(volume.total.bytes)")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(volume.used), total: Double(volume.total))
                        .tint(Double(volume.available) / Double(volume.total) < 0.1 ? .red : .accentColor)
                }
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var scanButtons: some View {
        #if APP_STORE
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.chooseFolderAndScan()
            } label: {
                Label("Choose Folder to Scan…", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.scanning)
            Text("Cleaner for xDev scans the folders you choose, such as your Home folder or a projects folder, and moves what you confirm to the Trash.")
                .foregroundStyle(.secondary)
            Link("Open source on GitHub", destination: URL(string: "https://github.com/xdev-asia/cleaner-for-xdev")!)
        }
        #else
        HStack(spacing: 12) {
            Button {
                model.scan("/")
            } label: {
                Label("Scan Macintosh HD", systemImage: "internaldrive")
            }
            .buttonStyle(.borderedProminent)
            Button {
                model.scan(AppHome.path)
            } label: {
                Label("Scan Home Folder", systemImage: "house")
            }
            Button {
                model.chooseFolderAndScan()
            } label: {
                Label("Choose Folder…", systemImage: "folder")
            }
        }
        .controlSize(.large)
        .disabled(model.scanning)
        #endif
    }

    @ViewBuilder private func summary(_ result: ScanResult) -> some View {
        let reclaimable = model.findings.reduce(Int64(0)) { $0 + $1.size }
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                stat("Scanned", result.root.size.bytes, "\(result.root.fileCount.formatted()) files in \(result.root.path.tilde)")
                stat("Cleanable", model.analysing ? "…" : reclaimable.bytes, "\(model.findings.count) items")
                stat("Duration", result.duration.formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated)),
                     result.denied.isEmpty ? "Every folder was readable" : "\(result.denied.count) folders could not be read")
            }
            if !model.findings.isEmpty {
                Button("View Cleanable Items") { model.section = .cleanable }
            }
            if !model.analysing { AISummaryCard() }
            Text("Largest Items").font(.headline)
            let top = result.root.children.filter { $0.kind != .smallFiles }.prefix(10)
            ForEach(Array(top)) { node in
                HStack {
                    Image(systemName: node.kind == .directory ? "folder.fill" : "doc.fill").foregroundStyle(.secondary)
                    Text(node.name)
                    Spacer()
                    Text(node.size.bytes).monospacedDigit()
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if node.kind == .directory {
                        model.focusPath = node.path
                        model.section = .folders
                    }
                }
                .contextMenu {
                    Button("Show in Finder") { model.reveal(node.path) }
                    Button("Explain with Apple Intelligence") { model.explain(node) }
                }
                Divider()
            }
            if !result.denied.isEmpty {
                DisclosureGroup("\(result.denied.count) folders could not be read") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(result.denied.prefix(200), id: \.self) { Text($0.tilde).font(.caption.monospaced()) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value).font(.title.weight(.semibold)).monospacedDigit()
            Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Advice on the whole scan from Apple Intelligence, written on this Mac.
struct AISummaryCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let assistant = model.summariser
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Apple Intelligence", systemImage: "sparkles").font(.headline)
                Spacer()
                if assistant.working {
                    ProgressView().controlSize(.small)
                } else {
                    Button(assistant.request == nil ? "Summarise This Scan" : "Summarise Again") { model.summarise() }
                }
            }
            if let error = assistant.error {
                Text(error).foregroundStyle(.secondary)
            } else if !assistant.text.isEmpty {
                AssistantText(text: assistant.text)
                AssistantNote()
            } else if assistant.request == nil {
                Text("Get a short, private summary of where the space goes and what to clean first. It runs on this Mac; nothing is sent anywhere.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
