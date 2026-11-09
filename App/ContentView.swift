import CleanerKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $model.section) { section in
                Label(section.title, systemImage: section.symbol)
                    .badge(badge(for: section))
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                if !model.hasFullDiskAccess { AccessBanner() }
                if model.scanning { ScanProgressBar() }
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(model.section.title)
        }
        .sheet(item: $model.pending) { pending in
            ConfirmSheet(pending: pending)
        }
        .sheet(item: Binding(get: { model.explainer.request }, set: { model.explainer.request = $0 })) { request in
            ExplainSheet(request: request)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.recheckAccess()
        }
    }

    private func badge(for section: SidebarSection) -> Text? {
        switch section {
        case .cleanable where !model.findings.isEmpty:
            Text(model.findings.reduce(Int64(0)) { $0 + $1.size }.bytes)
        case .duplicates where !model.duplicates.isEmpty:
            Text("\(model.duplicates.count)")
        default:
            nil
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .overview: OverviewView()
        case .folders: NeedsScan { FoldersView() }
        case .cleanable: NeedsScan { CleanableView() }
        case .large: NeedsScan { LargeFilesView() }
        case .duplicates: NeedsScan { DuplicatesView() }
        }
    }
}

/// Shows its content once a scan has finished, otherwise a hint to scan.
struct NeedsScan<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var content: Content

    var body: some View {
        if model.result != nil {
            content
        } else if model.scanning {
            ProgressView("Scanning…")
        } else {
            ContentUnavailableView {
                Label("Not Scanned", systemImage: "magnifyingglass")
            } description: {
                Text("Choose a disk or folder to scan in Overview.")
            } actions: {
                Button("Go to Overview") { model.section = .overview }
            }
        }
    }
}

struct AccessBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Full Disk Access is off").bold()
                Text("Some folders (Mail, Safari, Trash…) cannot be read. Turn on Cleaner for xDev in System Settings › Privacy & Security › Full Disk Access, then scan again.")
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer()
            Button("Open Settings") { model.openFullDiskAccessSettings() }
            Button("Check Again") { model.recheckAccess() }
        }
        .padding(12)
        .background(.orange.opacity(0.12))
    }
}

struct ScanProgressBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Scanning: \(model.progress.filesSeen.formatted()) files, \(model.progress.bytesSeen.bytes)")
                .monospacedDigit()
            Text(model.progress.currentPath.tilde)
                .lineLimit(1).truncationMode(.middle)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Stop") { model.cancelScan() }
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }
}

struct SafetyBadge: View {
    let safety: Safety

    var body: some View {
        Text(safety == .safe ? "Safe" : "Review")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((safety == .safe ? Color.green : Color.orange).opacity(0.18), in: Capsule())
            .foregroundStyle(safety == .safe ? .green : .orange)
    }
}
