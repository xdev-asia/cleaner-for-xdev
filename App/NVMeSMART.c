#include "NVMeSMART.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>
#include <string.h>

kern_return_t xdev_nvme_smart_read(io_service_t service, uint8_t *log) {
    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    kern_return_t kr = IOCreatePlugInInterfaceForService(service, kIONVMeSMARTUserClientTypeID, kIOCFPlugInInterfaceID,
                                                         &plugin, &score);
    if (kr != kIOReturnSuccess || plugin == NULL) return kr ? kr : kIOReturnError;
    IONVMeSMARTInterface **smart = NULL;
    HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID), (LPVOID *)&smart);
    if (hr != S_OK || smart == NULL) {
        IODestroyPlugInInterface(plugin);
        return kIOReturnUnsupported;
    }
    NVMeSMARTData data;
    memset(&data, 0, sizeof data);
    kr = (*smart)->SMARTReadData(smart, &data);
    if (kr == kIOReturnSuccess) memcpy(log, &data, sizeof data < 512 ? sizeof data : 512);
    (*smart)->Release(smart);
    IODestroyPlugInInterface(plugin);
    return kr;
}
