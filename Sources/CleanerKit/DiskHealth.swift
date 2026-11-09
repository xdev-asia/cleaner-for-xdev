import Foundation

/// The NVMe SMART / Health Information log page (NVM Express base specification, log page 02h).
public struct NVMeHealth: Sendable, Hashable {
    public var criticalWarning: UInt8
    /// Composite temperature in kelvin.
    public var temperatureKelvin: Int
    /// Remaining spare capacity, percent.
    public var availableSpare: Int
    public var availableSpareThreshold: Int
    /// Estimate of the rated life used, percent. May exceed 100.
    public var percentageUsed: Int
    /// Units of 1000 × 512 bytes.
    public var dataUnitsRead: UInt64
    public var dataUnitsWritten: UInt64
    public var powerCycles: UInt64
    public var powerOnHours: UInt64
    public var unsafeShutdowns: UInt64
    public var mediaErrors: UInt64
    public var errorLogEntries: UInt64

    public init(criticalWarning: UInt8 = 0, temperatureKelvin: Int = 0, availableSpare: Int = 100,
                availableSpareThreshold: Int = 10, percentageUsed: Int = 0, dataUnitsRead: UInt64 = 0,
                dataUnitsWritten: UInt64 = 0, powerCycles: UInt64 = 0, powerOnHours: UInt64 = 0,
                unsafeShutdowns: UInt64 = 0, mediaErrors: UInt64 = 0, errorLogEntries: UInt64 = 0) {
        self.criticalWarning = criticalWarning
        self.temperatureKelvin = temperatureKelvin
        self.availableSpare = availableSpare
        self.availableSpareThreshold = availableSpareThreshold
        self.percentageUsed = percentageUsed
        self.dataUnitsRead = dataUnitsRead
        self.dataUnitsWritten = dataUnitsWritten
        self.powerCycles = powerCycles
        self.powerOnHours = powerOnHours
        self.unsafeShutdowns = unsafeShutdowns
        self.mediaErrors = mediaErrors
        self.errorLogEntries = errorLogEntries
    }

    /// Parses the 512-byte log. Counters are 128-bit little-endian; values above 2^64 are capped.
    public init?(log: [UInt8]) {
        guard log.count >= 192 else { return nil }
        func u16(_ at: Int) -> Int { Int(log[at]) | Int(log[at + 1]) << 8 }
        func u128(_ at: Int) -> UInt64 {
            if log[(at + 8)..<(at + 16)].contains(where: { $0 != 0 }) { return .max }
            return (0..<8).reduce(UInt64(0)) { $0 | UInt64(log[at + $1]) << (8 * UInt64($1)) }
        }
        self.init(criticalWarning: log[0], temperatureKelvin: u16(1), availableSpare: Int(log[3]),
                  availableSpareThreshold: Int(log[4]), percentageUsed: Int(log[5]), dataUnitsRead: u128(32),
                  dataUnitsWritten: u128(48), powerCycles: u128(112), powerOnHours: u128(128),
                  unsafeShutdowns: u128(144), mediaErrors: u128(160), errorLogEntries: u128(176))
    }

    public var temperatureCelsius: Int? { temperatureKelvin > 0 ? temperatureKelvin - 273 : nil }
    public var bytesRead: Int64 { Self.bytes(dataUnitsRead) }
    public var bytesWritten: Int64 { Self.bytes(dataUnitsWritten) }

    static func bytes(_ units: UInt64) -> Int64 {
        let (value, overflow) = units.multipliedReportingOverflow(by: 512_000)
        return overflow || value > UInt64(Int64.max) ? .max : Int64(value)
    }
}

/// The drive's own SMART verdict, as `diskutil` reports it.
public enum SMARTStatus: String, Sendable, Hashable {
    case verified = "Verified"
    case failing = "Failing"
    case notSupported = "Not Supported"
    case unknown = "Unknown"

    public init(diskutil value: String?) {
        switch value?.lowercased() {
        case "verified": self = .verified
        case "failing": self = .failing
        case "not supported": self = .notSupported
        default: self = .unknown
        }
    }
}

/// One physical disk and what could be read about its health.
public struct DiskInfo: Sendable, Hashable, Identifiable {
    public var bsdName: String
    public var model: String
    public var isInternal: Bool
    /// For example "Apple Fabric", "PCI-Express", "USB".
    public var interconnect: String
    public var isSolidState: Bool
    public var capacity: Int64
    public var smartStatus: SMARTStatus
    public var nvme: NVMeHealth?
    /// Read and write errors since the Mac started, from the storage driver's statistics.
    public var errorsSinceBoot: Int

    public var id: String { bsdName }

    public init(bsdName: String, model: String, isInternal: Bool, interconnect: String, isSolidState: Bool,
                capacity: Int64, smartStatus: SMARTStatus = .unknown, nvme: NVMeHealth? = nil, errorsSinceBoot: Int = 0) {
        self.bsdName = bsdName
        self.model = model
        self.isInternal = isInternal
        self.interconnect = interconnect
        self.isSolidState = isSolidState
        self.capacity = capacity
        self.smartStatus = smartStatus
        self.nvme = nvme
        self.errorsSinceBoot = errorsSinceBoot
    }
}

public enum HealthLevel: String, Sendable, Hashable, Comparable {
    case good = "Good"
    case watch = "Watch"
    case replace = "Replace"
    case unknown = "Unknown"

    private var order: Int { switch self { case .good: 0; case .unknown: 1; case .watch: 2; case .replace: 3 } }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }
}

public struct HealthAssessment: Sendable, Hashable {
    public let level: HealthLevel
    /// Why the level is not Good, most serious first.
    public let reasons: [String]
}

/// Rates a disk with fixed thresholds. The rating is the app's; the on-device model only explains it.
public enum DiskHealth {
    public static let wearWatch = 80
    public static let hotCelsius = 70

    public static func assess(_ disk: DiskInfo) -> HealthAssessment {
        var replace: [String] = []
        var watch: [String] = []
        if disk.smartStatus == .failing { replace.append("The drive reports its SMART status as Failing.") }
        if disk.errorsSinceBoot > 0 { watch.append("\(disk.errorsSinceBoot) read or write errors since the Mac started.") }
        if let n = disk.nvme {
            let w = n.criticalWarning
            if w & 0x01 != 0 { replace.append("Critical warning: spare capacity is below the safe threshold.") }
            if w & 0x04 != 0 { replace.append("Critical warning: drive reliability is degraded.") }
            if w & 0x08 != 0 { replace.append("Critical warning: the drive is now read-only.") }
            if w & 0x10 != 0 { replace.append("Critical warning: the volatile memory backup has failed.") }
            if w & 0x02 != 0 { watch.append("Critical warning: temperature is outside the safe range.") }
            if n.availableSpareThreshold > 0, n.availableSpare < n.availableSpareThreshold, w & 0x01 == 0 {
                replace.append("Spare capacity \(n.availableSpare)% is below the drive's threshold of \(n.availableSpareThreshold)%.")
            } else if n.availableSpareThreshold > 0, n.availableSpare <= n.availableSpareThreshold + 10, n.availableSpare < 100 {
                watch.append("Spare capacity \(n.availableSpare)% is close to the drive's threshold of \(n.availableSpareThreshold)%.")
            }
            if n.percentageUsed >= 100 {
                replace.append("\(n.percentageUsed)% of the rated write endurance is used.")
            } else if n.percentageUsed >= wearWatch {
                watch.append("\(n.percentageUsed)% of the rated write endurance is used.")
            }
            if n.mediaErrors > 0 { watch.append("\(n.mediaErrors) media errors recorded.") }
            if let t = n.temperatureCelsius, t >= hotCelsius, w & 0x02 == 0 { watch.append("Temperature is \(t) °C.") }
        }
        if !replace.isEmpty { return HealthAssessment(level: .replace, reasons: replace + watch) }
        if !watch.isEmpty { return HealthAssessment(level: .watch, reasons: watch) }
        if disk.nvme == nil && disk.smartStatus != .verified {
            return HealthAssessment(level: .unknown, reasons: ["The drive's health data cannot be read."])
        }
        return HealthAssessment(level: .good, reasons: [])
    }
}
