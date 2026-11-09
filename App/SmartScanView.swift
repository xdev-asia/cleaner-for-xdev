import CleanerKit
import SwiftUI

/// One button: scan the Home folder, show Safe items selected and Review items unselected, clean after confirmation.
struct SmartScanView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.scanning {
            scanning
        } else if model.result == nil {
            idle
        } else if model.analysing {
            ProgressView("Analysing…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            results(SmartScanSummary(findings: model.findings))
        }
    }

    // MARK: Idle

    private var idle: some View {
        VStack(spacing: 18) {
            Image(systemName: "wand.and.sparkles").font(.system(size: 56)).foregroundStyle(.tint)
            Text("Smart Scan").font(.largeTitle.bold())
            Text("Finds caches and build outputs in your Home folder: Xcode, Android, Node.js, project build folders and app caches. Safe items are selected for you; nothing is removed until you confirm, and everything goes to the Trash.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)
            Button {
                model.smartScan()
            } label: {
                Label("Start Smart Scan", systemImage: "magnifyingglass").padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            folderNote
            if let error = model.scanError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var folderNote: some View {
        #if APP_STORE
        if let folder = model.smartScanFolder {
            HStack(spacing: 8) {
                Text("Folder: \(folder.tilde)").foregroundStyle(.secondary)
                Button("Change Folder…") { model.changeSmartScanFolder() }.buttonStyle(.link)
            }
            .font(.callout)
        } else {
            Text("The first time, choose your Home folder so Cleaner for xDev can read it. You are asked only once.")
                .font(.callout).foregroundStyle(.secondary)
        }
        #endif
    }

    // MARK: Scanning

    private var scanning: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Scanning \(model.scanRoot?.tilde ?? "")…").font(.title3)
            Text("\(model.progress.filesSeen.formatted()) files, \(model.progress.bytesSeen.bytes)")
                .monospacedDigit().foregroundStyle(.secondary)
            Button("Stop") { model.cancelScan() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Results

    @ViewBuilder private func results(_ summary: SmartScanSummary) -> some View {
        VStack(spacing: 0) {
            header(summary)
            Divider()
            if summary.isEmpty {
                ContentUnavailableView("Nothing to clean", systemImage: "checkmark.seal",
                                       description: Text(model.freedBytes > 0
                                           ? "Everything Smart Scan found has been moved to the Trash."
                                           : "No caches or build outputs were found in \(model.scanRoot?.tilde ?? "the scanned folder")."))
            } else {
                List {
                    if !summary.safe.isEmpty {
                        Section {
                            ForEach(summary.safe) { FindingRow(finding: $0) }
                        } header: {
                            sectionHeader("Safe: rebuilt automatically, selected", summary.safeTotal)
                        }
                    }
                    if !summary.review.isEmpty {
                        Section {
                            ForEach(summary.review) { FindingRow(finding: $0) }
                        } header: {
                            sectionHeader("Review: check before cleaning, not selected", summary.reviewTotal)
                        }
                    }
                    Section { AISummaryCard() }
                }
            }
            Divider()
            footer(summary)
        }
    }

    private func header(_ summary: SmartScanSummary) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "wand.and.sparkles").font(.system(size: 30)).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(summary.safeTotal.bytes) can be freed safely").font(.title2.bold()).monospacedDigit()
                Text(summary.reviewTotal > 0
                     ? "Another \(summary.reviewTotal.bytes) to review. Scanned \(model.scanRoot?.tilde ?? "")."
                     : "Scanned \(model.scanRoot?.tilde ?? "").")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            if model.freedBytes > 0 {
                Label("Freed \(model.freedBytes.bytes). Empty the Trash to get the space back.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 300, alignment: .trailing)
            }
        }
        .padding(16)
    }

    private func sectionHeader(_ title: String, _ total: Int64) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(total.bytes).monospacedDigit()
        }
    }

    private func footer(_ summary: SmartScanSummary) -> some View {
        let total = summary.selectedTotal(model.selectedFindings)
        return HStack {
            Button("Scan Again") { model.smartScan() }
            #if APP_STORE
            Button("Change Folder…") { model.changeSmartScanFolder() }
            #endif
            Spacer()
            if !summary.isEmpty {
                Button("Select Safe Items") { model.selectedFindings = summary.defaultSelection }
                Button("Clean \(total.bytes)…") { model.confirmFindings() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(total == 0)
            }
        }
        .padding(12)
    }
}
