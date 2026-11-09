import CleanerKit
import SwiftUI

/// Physical disk health, rated with fixed thresholds and explained on device.
struct DiskHealthView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !model.healthRead {
                        ProgressView("Reading disks…")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if model.disks.isEmpty {
                        ContentUnavailableView("No disks could be read", systemImage: "internaldrive",
                                               description: Text("Cleaner for xDev could not read health data from any disk on this Mac."))
                    } else {
                        ForEach(model.disks) { DiskCard(disk: $0) }
                        HealthAICard()
                    }
                }
                .frame(maxWidth: 900)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: 16) {
                // No fixedSize here: a narrow width proposal would make the footer taller than the window.
                Text("Ratings come from fixed thresholds: wear, spare capacity, temperature, errors and the drive's own warnings.")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button("Refresh") { Task { await model.loadHealth() } }
                    .disabled(model.readingHealth)
            }
            .padding(16)
        }
    }
}

struct HealthBadge: View {
    let level: HealthLevel

    private var symbol: String {
        switch level {
        case .good: "checkmark.seal.fill"
        case .watch: "exclamationmark.triangle.fill"
        case .replace: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var body: some View {
        Label(level.rawValue, systemImage: symbol)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(level.color)
            .background(level.color.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(level.color.opacity(0.16)))
            .accessibilityLabel("Health: \(level.rawValue)")
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
        VStack(alignment: .leading, spacing: 20) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    driveVisual(level: assessment.level)
                    driveDetails(level: assessment.level).frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 20) {
                    driveVisual(level: assessment.level)
                    driveDetails(level: assessment.level)
                }
            }
            if let n = disk.nvme {
                Divider()
                DiskMetrics(health: n)
            } else {
                Text(disk.smartStatus == .unknown
                     ? "This drive does not share detailed health data with Cleaner for xDev."
                     : "SMART status: \(disk.smartStatus.rawValue)")
                    .foregroundStyle(.secondary)
            }
            if disk.errorsSinceBoot > 0 {
                Label("\(disk.errorsSinceBoot) read or write errors since the Mac started", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if !assessment.reasons.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(assessment.reasons, id: \.self) {
                        Label($0, systemImage: "info.circle")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(20)
        .healthCard()
    }

    @ViewBuilder
    private func driveVisual(level: HealthLevel) -> some View {
        if let n = disk.nvme {
            LifeGauge(percentageUsed: n.percentageUsed, level: level)
        } else {
            Image(systemName: disk.isInternal ? "internaldrive" : "externaldrive")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(level.color)
                .frame(width: 100, height: 100)
                .background(level.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private func driveDetails(level: HealthLevel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(disk.model).font(.title2.bold()).textSelection(.enabled)
            Text([disk.isInternal ? "Internal" : "External", disk.interconnect, disk.capacity.bytes, disk.bsdName]
                .joined(separator: " · "))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HealthBadge(level: level)
            if let n = disk.nvme {
                Text("\(n.percentageUsed)% of rated write endurance")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

private struct LifeGauge: View {
    let percentageUsed: Int
    let level: HealthLevel

    private var remaining: Int { 100 - min(max(percentageUsed, 0), 100) }

    var body: some View {
        ZStack {
            Circle().stroke(level.color.opacity(0.12), lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(remaining) / 100)
                .stroke(level.color.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(remaining)%")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("life left").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .frame(width: 140, height: 140)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated remaining drive life")
        .accessibilityValue("\(remaining) percent, \(level.rawValue)")
    }
}

private struct DiskMetrics: View {
    let health: NVMeHealth

    private var uptime: String {
        let days = Double(health.powerOnHours) / 24
        return days >= 365
            ? "\((days / 365).formatted(.number.precision(.fractionLength(1)))) years"
            : "\(days.formatted(.number.precision(.fractionLength(1)))) days"
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            MetricTile(title: "Temperature", value: health.temperatureCelsius.map { "\($0) °C" } ?? "Not reported",
                       symbol: "thermometer", tint: (health.temperatureCelsius ?? 0) >= DiskHealth.hotCelsius ? .orange : .accentColor)
            MetricTile(title: "Spare capacity", value: "\(health.availableSpare)%", symbol: "externaldrive.badge.checkmark",
                       tint: health.availableSpare < health.availableSpareThreshold ? .red : .green,
                       detail: "threshold \(health.availableSpareThreshold)%")
            MetricTile(title: "Data written", value: health.bytesWritten.bytes, symbol: "square.and.arrow.down")
            MetricTile(title: "Data read", value: health.bytesRead.bytes, symbol: "square.and.arrow.up")
            MetricTile(title: "Power-on hours", value: health.powerOnHours.formatted(), symbol: "clock", detail: uptime)
            MetricTile(title: "Power cycles", value: health.powerCycles.formatted(), symbol: "power")
            MetricTile(title: "Unsafe shutdowns", value: health.unsafeShutdowns.formatted(), symbol: "bolt.slash")
            MetricTile(title: "Media errors", value: health.mediaErrors.formatted(), symbol: "exclamationmark.shield",
                       tint: health.mediaErrors > 0 ? .red : .accentColor)
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = .accentColor
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                Text(detail ?? " ").font(.caption).foregroundStyle(.secondary)
                    .accessibilityHidden(detail == nil)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.35)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([value, detail].compactMap { $0 }.joined(separator: ", "))
    }
}

/// Runs by itself the first time the section opens; the rating stays the app's.
private struct HealthAICard: View {
    @Environment(AppModel.self) private var model
    private let accent = LinearGradient(colors: [.blue, .purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        let assistant = model.healthAdvisor
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                Text("Apple Intelligence").font(.headline)
                Spacer()
                if assistant.working {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Assessing the disks on this Mac…")
                } else {
                    Button("Assess Again") { model.assessHealth() }
                }
            }
            if let error = assistant.error {
                Text(error).foregroundStyle(.secondary)
            } else if !assistant.text.isEmpty {
                AssistantText(text: assistant.text)
                    .lineSpacing(4)
                Divider()
                Label("Written on this Mac by Apple Intelligence and may be wrong. The ratings come from the app's fixed thresholds. Keep a backup of anything important.",
                      systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Assessing the disks on this Mac…").foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .healthCard()
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(accent.opacity(0.25)))
        .task {
            if assistant.request == nil { model.assessHealth() }
        }
    }
}

private extension View {
    func healthCard() -> some View {
        background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }
}
