import CleanerKit
import Foundation
import IOKit

/// Lists the physical disks from the IORegistry and reads what it can about their health: the NVMe SMART log
/// through NVMeSMARTLib, errors since startup from the storage driver, and (DMG edition only) the SMART status
/// that `diskutil` reports for other drives.
enum DiskHealthReader {
    static func read() async -> [DiskInfo] {
        var disks = await Task.detached { readRegistry() }.value
        #if !APP_STORE
        for i in disks.indices { disks[i].smartStatus = await diskutilStatus(disks[i].bsdName) }
        #endif
        return disks
    }

    private static func readRegistry() -> [DiskInfo] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDevice"), &iterator)
                == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var bySerial: [String: DiskInfo] = [:]
        var order: [String] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let device = property(service, "Device Characteristics") as? [String: Any] ?? [:]
            let proto = property(service, "Protocol Characteristics") as? [String: Any] ?? [:]
            let interconnect = (proto["Physical Interconnect"] as? String ?? "Unknown").trimmed
            let location = proto["Physical Interconnect Location"] as? String ?? ""
            // Disk images and other virtual devices have no health to report.
            guard location != "File", interconnect != "Virtual Interface",
                  let media = wholeMedia(under: service) else { continue }
            let vendor = (device["Vendor Name"] as? String ?? "").trimmed
            let product = (device["Product Name"] as? String ?? "").trimmed
            let model = [vendor, product].filter { !$0.isEmpty }.joined(separator: " ")
            var nvme: NVMeHealth?
            if property(service, "NVMe SMART Capable") as? Bool == true {
                var log = [UInt8](repeating: 0, count: 512)
                if xdev_nvme_smart_read(service, &log) == KERN_SUCCESS { nvme = NVMeHealth(log: log) }
            }
            let stats = search(service, "Statistics") as? [String: Any] ?? [:]
            let errors = (stats["Errors (Read)"] as? Int ?? 0) + (stats["Errors (Write)"] as? Int ?? 0)
            let disk = DiskInfo(bsdName: media.bsd, model: model.isEmpty ? media.bsd : model,
                                isInternal: location == "Internal", interconnect: interconnect,
                                isSolidState: (device["Medium Type"] as? String) == "Solid State" || nvme != nil,
                                capacity: media.size, nvme: nvme, errorsSinceBoot: errors)
            // An Apple SSD shows up once per NVMe namespace; keep the largest one.
            let key = (device["Serial Number"] as? String)?.trimmed ?? media.bsd
            if let existing = bySerial[key] {
                if disk.capacity > existing.capacity { bySerial[key] = disk }
            } else {
                bySerial[key] = disk
                order.append(key)
            }
        }
        return order.compactMap { bySerial[$0] }
    }

    /// The whole-disk IOMedia below a block storage device.
    private static func wholeMedia(under service: io_service_t) -> (bsd: String, size: Int64)? {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(service, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator)
                == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard IOObjectConformsTo(entry, "IOMedia") != 0, property(entry, "Whole") as? Bool == true,
                  let bsd = property(entry, "BSD Name") as? String else { continue }
            return (bsd, (property(entry, "Size") as? NSNumber)?.int64Value ?? 0)
        }
        return nil
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func search(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                        IOOptionBits(kIORegistryIterateRecursively))
    }

    #if !APP_STORE
    private static func diskutilStatus(_ bsd: String) async -> SMARTStatus {
        guard let output = try? await ProcessRunner().run("/usr/sbin/diskutil", ["info", "-plist", bsd], environment: [:]),
              output.status == 0,
              let plist = try? PropertyListSerialization.propertyList(from: Data(output.output.utf8), format: nil) as? [String: Any]
        else { return .unknown }
        return SMARTStatus(diskutil: plist["SMARTStatus"] as? String)
    }
    #endif
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
