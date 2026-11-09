#ifndef NVMESMART_H
#define NVMESMART_H
#include <IOKit/IOKitLib.h>
#include <stdint.h>

/// Reads the 512-byte NVMe SMART / Health Information log of a service that has "NVMe SMART Capable".
/// Returns kIOReturnSuccess and fills `log`, or an IOKit error (for example when the sandbox blocks the user client).
kern_return_t xdev_nvme_smart_read(io_service_t service, uint8_t *log);
#endif
