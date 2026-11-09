import CleanerKit
import SwiftUI

/// One card per physical disk, rated with the app's fixed thresholds, and an on-device explanation of the ratings.
struct DiskHealthView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !model.healthRead {
                        ProgressView("Reading disks…").frame(maxWidth: .infinity, minHeight: 200)
                    } else if model.disks.isEmpty {
                        ContentUnavailableView("No disks could be read", systemImage: "internaldrive",
                                               description: Text("Cleaner for xDev could not read health data from any disk on this Mac."))
                    } else {
                        ForEach(model.disks) { DiskCard(disk: $0) }
                        HealthAICard()
                    }
                }
                .padding(16)
            }
            Divider()
            HStack {
                Text("Ratings come from fixed thresholds: wear, spare capacity, temperature, errors and the drive's own warnings.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { Task { await model.loadHealth() } }
                    .disabled(model.readingHealth)
            }
            .padding(12)
        }
    }
}

struct HealthBadge: View {
    let level: HealthLevel

    var body: some View {
        Text(level.rawValue)
            .font(.callout.bold())
            .padding(.horizontal, 8).padding(.vertical, 2)
            .foregroundStyle(level.color)
            .background(level.color.opacity(0.15), in: Capsule())
    }
}

extension HealthLevel {
    var color: Color {
        switch self {
        case .good: .green
        case .watch: .orange
        case .replace: .red
        case .unknown: .gray
        }
    }
}

private struct DiskCard: View {
    let disk: DiskInfo

    var body: some View {
        let assessment = DiskHealth.assess(disk)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: disk.isInternal ? "internaldrive" : "externaldrive")
                    .font(.system(size: 28)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(disk.model).font(.title3.bold())
                    Text([disk.isInternal ? "Internal" : "External", disk.interconnect, disk.capacity.bytes, disk.bsdName]
                        .joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                HealthBadge(level: assessment.level)
            }
            if let n = disk.nvme {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Life used")
                        Spacer()
                        Text("\(n.percentageUsed)% of rated write endurance").monospacedDigit()
                    }
                    ProgressView(value: Double(min(n.percentageUsed, 100)), total: 100)
                        .tint(n.percentageUsed >= DiskHealth.wearWatch ? .orange : .green)
                }
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    GridRow {
                        metric("Spare capacity", "\(n.availableSpare)% (threshold \(n.availableSpareThreshold)%)")
                        metric("Temperature", n.temperatureCelsius.map { "\($0) °C" } ?? "Not reported")
                    }
                    GridRow {
                        metric("Written", n.bytesWritten.bytes)
                        metric("Read", n.bytesRead.bytes)
                    }
                    GridRow {
                        metric("Power-on hours", n.powerOnHours.formatted())
                        metric("Power cycles", n.powerCycles.formatted())
                    }
                    GridRow {
                        metric("Unsafe shutdowns", n.unsafeShutdowns.formatted())
                        metric("Media errors", n.mediaErrors.formatted())
                    }
                }
            } else {
                Text(disk.smartStatus == .unknown
                     ? "This drive does not share detailed health data with Cleaner for xDev."
                     : "SMART status: \(disk.smartStatus.rawValue)")
                    .foregroundStyle(.secondary)
            }
            if disk.errorsSinceBoot > 0 {
                Label("\(disk.errorsSinceBoot) read or write errors since the Mac started", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if !assessment.reasons.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(assessment.reasons, id: \.self) { Label($0, systemImage: "info.circle").font(.callout) }
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }
}

/// Runs by itself the first time the section opens; the rating stays the app's.
private struct HealthAICard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let assistant = model.healthAdvisor
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Apple Intelligence", systemImage: "sparkles").font(.headline)
                Spacer()
                if assistant.working {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Assess Again") { model.assessHealth() }
                }
            }
            if let error = assistant.error {
                Text(error).foregroundStyle(.secondary)
            } else if !assistant.text.isEmpty {
                AssistantText(text: assistant.text)
                Label("Written on this Mac by Apple Intelligence and may be wrong. The ratings come from the app's fixed thresholds. Keep a backup of anything important.",
                      systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Assessing the disks on this Mac…").foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .task {
            if assistant.request == nil { model.assessHealth() }
        }
    }
}
