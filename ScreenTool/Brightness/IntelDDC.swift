#if arch(x86_64)
import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics
import IOKit.i2c

/// DDC/CI over the Intel framebuffer's I²C buses.
enum IntelDDC {
    static func control(for id: CGDirectDisplayID) -> BrightnessControl? {
        guard let framebuffer = framebuffer(for: id) else { return nil }
        return DDCBrightness { message, replyLength in send(framebuffer.service, message, replyLength) }
    }

    /// Keeps the framebuffer service alive for as long as a control uses it.
    private final class Framebuffer {
        let service: io_service_t
        init(_ service: io_service_t) { self.service = service }
        deinit { IOObjectRelease(service) }
    }

    private static func framebuffer(for id: CGDirectDisplayID) -> Framebuffer? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator)
                == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer { entry = IOIteratorNext(iterator) }
            defer { IOObjectRelease(entry) }
            let info = IODisplayCreateInfoDictionary(entry, IOOptionBits(kIODisplayOnlyPreferredName))
                .takeRetainedValue() as NSDictionary
            let vendor = (info["DisplayVendorID"] as? NSNumber)?.uint32Value
            let product = (info["DisplayProductID"] as? NSNumber)?.uint32Value
            let serial = (info["DisplaySerialNumber"] as? NSNumber)?.uint32Value ?? 0
            guard vendor == CGDisplayVendorNumber(id), product == CGDisplayModelNumber(id),
                  serial == 0 || serial == CGDisplaySerialNumber(id) else { continue }
            var service = io_service_t()
            if IORegistryEntryGetParentEntry(entry, kIOServicePlane, &service) == KERN_SUCCESS {
                return Framebuffer(service)
            }
        }
        return nil
    }

    private static func send(_ framebuffer: io_service_t, _ message: [UInt8], _ replyLength: Int) -> [UInt8]? {
        var busCount: IOItemCount = 0
        guard IOFBGetI2CInterfaceCount(framebuffer, &busCount) == KERN_SUCCESS else { return nil }
        for bus in 0..<busCount {
            var interface = io_service_t()
            guard IOFBCopyI2CInterfaceForBus(framebuffer, IOOptionBits(bus), &interface) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(interface) }
            var connect: IOI2CConnectRef?
            guard IOI2CInterfaceOpen(interface, 0, &connect) == KERN_SUCCESS, let connect else { continue }
            defer { IOI2CInterfaceClose(connect, 0) }
            if let reply = request(connect, message, replyLength) { return reply }
        }
        return nil
    }

    private static func request(_ connect: IOI2CConnectRef, _ message: [UInt8], _ replyLength: Int) -> [UInt8]? {
        var outgoing = message
        var reply = [UInt8](repeating: 0, count: replyLength)
        let succeeded = outgoing.withUnsafeMutableBufferPointer { send in
            reply.withUnsafeMutableBufferPointer { receive in
                var request = IOI2CRequest()
                request.sendAddress = UInt32(DDC.monitorAddress)
                request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
                request.sendBuffer = vm_address_t(bitPattern: send.baseAddress)
                request.sendBytes = UInt32(send.count)
                if replyLength > 0 {
                    request.replyAddress = UInt32(DDC.monitorAddress | 1)
                    request.replySubAddress = DDC.hostAddress
                    request.replyTransactionType = IOOptionBits(kIOI2CDDCciReplyTransactionType)
                    request.replyBuffer = vm_address_t(bitPattern: receive.baseAddress)
                    request.replyBytes = UInt32(replyLength)
                    request.minReplyDelay = 30_000_000  // ns
                } else {
                    request.replyTransactionType = IOOptionBits(kIOI2CNoTransactionType)
                }
                return IOI2CSendRequest(connect, 0, &request) == KERN_SUCCESS && request.result == kIOReturnSuccess
            }
        }
        return succeeded ? reply : nil
    }
}
#endif
