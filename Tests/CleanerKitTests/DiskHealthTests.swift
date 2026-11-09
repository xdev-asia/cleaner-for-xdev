import Testing
@testable import CleanerKit

@Suite struct DiskHealthTests {
    /// A log page with the given little-endian fields set.
    private func log(_ fields: [Int: [UInt8]]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 512)
        for (offset, value) in fields { for (i, b) in value.enumerated() { bytes[offset + i] = b } }
        return bytes
    }

    private func le(_ value: UInt64) -> [UInt8] { (0..<8).map { UInt8((value >> (8 * UInt64($0))) & 0xFF) } }

    private func disk(_ nvme: NVMeHealth? = nil, smart: SMARTStatus = .verified, errors: Int = 0) -> DiskInfo {
        DiskInfo(bsdName: "disk0", model: "APPLE SSD", isInternal: true, interconnect: "Apple Fabric", isSolidState: true,
                 capacity: 500_000_000_000, smartStatus: smart, nvme: nvme, errorsSinceBoot: errors)
    }

    @Test func parsesTheSMARTLogPage() throws {
        let health = try #require(NVMeHealth(log: log([
            0: [0x00], 1: [0x34, 0x01], 3: [100], 4: [99], 5: [9],
            32: le(1000), 48: le(486_579_798), 112: le(998), 128: le(6763), 144: le(337), 160: le(2), 176: le(5),
        ])))
        #expect(health.temperatureKelvin == 308)
        #expect(health.temperatureCelsius == 35)
        #expect(health.availableSpare == 100)
        #expect(health.availableSpareThreshold == 99)
        #expect(health.percentageUsed == 9)
        #expect(health.bytesRead == 512_000_000)
        #expect(health.bytesWritten == 486_579_798 * 512_000)
        #expect(health.powerCycles == 998)
        #expect(health.powerOnHours == 6763)
        #expect(health.unsafeShutdowns == 337)
        #expect(health.mediaErrors == 2)
        #expect(health.errorLogEntries == 5)
    }

    @Test func capsCountersAbove64Bits() throws {
        let health = try #require(NVMeHealth(log: log([48: le(1), 56: [1]])))
        #expect(health.dataUnitsWritten == .max)
        #expect(health.bytesWritten == .max)
        #expect(NVMeHealth(log: [0, 1, 2]) == nil)
    }

    @Test func readsDiskutilSMARTStatus() {
        #expect(SMARTStatus(diskutil: "Verified") == .verified)
        #expect(SMARTStatus(diskutil: "Failing") == .failing)
        #expect(SMARTStatus(diskutil: "Not Supported") == .notSupported)
        #expect(SMARTStatus(diskutil: nil) == .unknown)
    }

    @Test func healthyDriveIsGood() {
        let a = DiskHealth.assess(disk(NVMeHealth(temperatureKelvin: 308, availableSpare: 100, availableSpareThreshold: 99, percentageUsed: 9)))
        #expect(a.level == .good)
        #expect(a.reasons.isEmpty)
    }

    @Test(arguments: [
        (NVMeHealth(percentageUsed: 80), HealthLevel.watch),
        (NVMeHealth(percentageUsed: 100), .replace),
        (NVMeHealth(mediaErrors: 1), .watch),
        (NVMeHealth(temperatureKelvin: 343), .watch),
        (NVMeHealth(availableSpare: 15, availableSpareThreshold: 10), .watch),
        (NVMeHealth(availableSpare: 5, availableSpareThreshold: 10), .replace),
        (NVMeHealth(criticalWarning: 0x02), .watch),
        (NVMeHealth(criticalWarning: 0x04), .replace),
        (NVMeHealth(criticalWarning: 0x08), .replace),
    ])
    func ratesNVMeThresholds(health: NVMeHealth, expected: HealthLevel) {
        let a = DiskHealth.assess(disk(health))
        #expect(a.level == expected)
        #expect(!a.reasons.isEmpty)
    }

    @Test func appleSpareThresholdAt99IsNotAWarning() {
        // Apple SSDs report a 99% threshold while spare is 100%.
        #expect(DiskHealth.assess(disk(NVMeHealth(availableSpare: 100, availableSpareThreshold: 99))).level == .good)
    }

    @Test func nonNVMeDrivesUseTheSMARTStatus() {
        #expect(DiskHealth.assess(disk(smart: .verified)).level == .good)
        #expect(DiskHealth.assess(disk(smart: .failing)).level == .replace)
        #expect(DiskHealth.assess(disk(smart: .notSupported)).level == .unknown)
        #expect(DiskHealth.assess(disk(smart: .unknown)).level == .unknown)
    }

    @Test func errorsSinceBootNeedWatching() {
        let a = DiskHealth.assess(disk(smart: .verified, errors: 3))
        #expect(a.level == .watch)
        #expect(a.reasons.first?.contains("3") == true)
    }

    @Test func replaceReasonsComeFirst() {
        let a = DiskHealth.assess(disk(NVMeHealth(percentageUsed: 85, mediaErrors: 1), smart: .failing))
        #expect(a.level == .replace)
        #expect(a.reasons.first == "The drive reports its SMART status as Failing.")
        #expect(a.reasons.count == 3)
    }

    @Test func briefCarriesTheAppRatingAndFigures() {
        let brief = AIBrief.diskHealth([disk(NVMeHealth(temperatureKelvin: 308, percentageUsed: 85, dataUnitsWritten: 2_000_000,
                                                        powerOnHours: 6763))])
        #expect(brief.contains("rating Watch"))
        #expect(brief.contains("85% of rated write endurance used"))
        #expect(brief.contains("temperature 35 °C"))
        #expect(brief.contains("powered on for 6763 hours"))
        #expect(brief.contains("Reasons for the rating: 85% of the rated write endurance is used."))
        #expect(AIBrief.healthInstructions.contains("never change it"))
    }

    @Test func briefSaysWhenNoDiskCouldBeRead() {
        #expect(AIBrief.diskHealth([]).contains("No disks could be read."))
    }
}
