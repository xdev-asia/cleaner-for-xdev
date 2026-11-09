import Foundation

/// What Smart Scan shows after a scan: cleanable findings split into Safe (selected by default) and Review
/// (shown, never selected by default), largest first. Blocked findings and findings that need a missing tool are
/// left out; they stay visible in the full Cleanable list.
public struct SmartScanSummary: Sendable {
    public let safe: [Finding]
    public let review: [Finding]

    public init(findings: [Finding]) {
        let cleanable = findings.filter { $0.blockedReason == nil && !$0.toolMissing }
            .sorted { ($0.size, $1.path) > ($1.size, $0.path) }
        safe = cleanable.filter { $0.rule.safety == .safe }
        review = cleanable.filter { $0.rule.safety == .review }
    }

    public var isEmpty: Bool { safe.isEmpty && review.isEmpty }
    public var safeTotal: Int64 { safe.reduce(0) { $0 + $1.size } }
    public var reviewTotal: Int64 { review.reduce(0) { $0 + $1.size } }

    /// Every Safe item.
    public var defaultSelection: Set<String> { Set(safe.map(\.id)) }

    /// Size of the selected items that Smart Scan shows.
    public func selectedTotal(_ selection: Set<String>) -> Int64 {
        (safe + review).filter { selection.contains($0.id) }.reduce(0) { $0 + $1.size }
    }
}
