import Foundation

extension AIBrief {
    public static let healthInstructions = """
    You are the assistant inside Cleaner for xDev, a macOS app. You explain the health of the Mac's disks \
    in plain English for a developer.
    Rules:
    - Use only the figures given and general knowledge of SSDs and hard drives.
    - Each disk comes with a rating decided by the app: Good, Watch, Replace or Unknown. Copy it exactly as given; \
    never change it or rate a disk yourself.
    - Rated write endurance is an estimate from the drive maker; drives often keep working past 100%.
    - Never suggest Terminal commands or third-party repair tools. Always recommend keeping a backup, such as Time Machine.
    """

    /// Asks for an assessment of every disk.
    public static func diskHealth(_ disks: [DiskInfo]) -> String {
        var lines: [String] = []
        for disk in disks {
            let assessment = DiskHealth.assess(disk)
            var facts = ["\(disk.model) (\(disk.isInternal ? "internal" : "external"), \(disk.interconnect), "
                + "\(disk.isSolidState ? "SSD" : "hard drive"), \(bytes(disk.capacity)))",
                         "rating \(assessment.level.rawValue)"]
            if disk.smartStatus != .unknown { facts.append("SMART status \(disk.smartStatus.rawValue)") }
            if let n = disk.nvme {
                facts.append("\(n.percentageUsed)% of rated write endurance used")
                facts.append("spare \(n.availableSpare)% (threshold \(n.availableSpareThreshold)%)")
                if let t = n.temperatureCelsius { facts.append("temperature \(t) °C") }
                facts.append("\(bytes(n.bytesWritten)) written, \(bytes(n.bytesRead)) read")
                facts.append("\(n.powerOnHours) power-on hours, \(n.powerCycles) power cycles, \(n.unsafeShutdowns) unsafe shutdowns")
                facts.append("\(n.mediaErrors) media errors")
            }
            facts.append("\(disk.errorsSinceBoot) read/write errors since startup")
            lines.append("- " + facts.joined(separator: "; ") + ".")
            if !assessment.reasons.isEmpty { lines.append("  Reasons for the rating: " + assessment.reasons.joined(separator: " ")) }
        }
        if disks.isEmpty { lines.append("No disks could be read.") }
        lines.append("For each disk write one short paragraph: its rating, what the figures mean in everyday terms "
            + "(for SSDs, roughly how much of its write life is left), and what to do now.")
        return (["Disks on this Mac:"] + lines).joined(separator: "\n")
    }
}
