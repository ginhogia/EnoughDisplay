#if arch(x86_64)
import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics
import IOKit.i2c

/// DDC/CI over the Intel framebuffer's I²C buses.
enum IntelDDC {
    static func control(for id: CGDirectDisplayID) -> BrightnessControl? {
        let key = HangGuard.key(for: id)
        guard !HangGuard.isDisabled(key) else {
            DDCTrace.log?("disabled for this Display: an earlier I2C request froze the Mac")
            return nil
        }
        guard let framebuffer = framebuffer(for: id) else { return nil }
        return DDCBrightness { message, replyLength in
            HangGuard.during(key) { send(framebuffer.service, message, replyLength) }
        }
    }

    /// A hung I²C request takes the whole Mac down, so every request is bracketed by an on-disk marker.
    /// A marker that survives to the next launch means the request never returned: DDC stays off for that Display.
    /// Re-enable with `defaults delete com.tengjau.EnoughDisplay intelDDCDisabledDisplays`.
    private enum HangGuard {
        private static let defaultsKey = "intelDDCDisabledDisplays"
        private static let marker: URL = {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("EnoughDisplay", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent("intel-ddc-in-flight")
        }()
        private static let lock = NSLock()

        static func key(for id: CGDirectDisplayID) -> String {
            "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
        }

        static func isDisabled(_ key: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if let hung = try? String(contentsOf: marker, encoding: .utf8) {
                let disabled = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
                UserDefaults.standard.set(Array(Set(disabled + [hung])), forKey: defaultsKey)
                try? FileManager.default.removeItem(at: marker)
            }
            return UserDefaults.standard.stringArray(forKey: defaultsKey)?.contains(key) ?? false
        }

        static func during<T>(_ key: String, _ body: () -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            writeDurably(key)
            defer { unlink(marker.path) }
            return body()
        }

        /// Must reach the disk before the request starts: a frozen Mac never flushes anything later.
        private static func writeDurably(_ contents: String) {
            let fd = open(marker.path, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
            guard fd >= 0 else { return }
            _ = contents.withCString { write(fd, $0, strlen($0)) }
            fsync(fd)
            close(fd)
        }
    }

    /// Keeps the framebuffer service alive for as long as a control uses it.
    private final class Framebuffer {
        let service: io_service_t
        init(_ service: io_service_t) { self.service = service }
        deinit { IOObjectRelease(service) }
    }

    private static func framebuffer(for id: CGDirectDisplayID) -> Framebuffer? {
        guard let connect = displayConnect(for: id) else {
            DDCTrace.log?("no IODisplayConnect matches vendor/model/serial")
            return nil
        }
        defer { IOObjectRelease(connect) }
        var service = io_service_t()
        guard IORegistryEntryGetParentEntry(connect, kIOServicePlane, &service) == KERN_SUCCESS else {
            DDCTrace.log?("IODisplayConnect has no parent framebuffer")
            return nil
        }
        DDCTrace.log?("framebuffer: \(IOObjectCopyClass(service)?.takeRetainedValue() as String? ?? "?")")
        return Framebuffer(service)
    }

    /// The IODisplayConnect whose EDID identity matches `id`. The caller releases it.
    private static func displayConnect(for id: CGDirectDisplayID) -> io_service_t? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator)
                == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            let info = IODisplayCreateInfoDictionary(entry, IOOptionBits(kIODisplayOnlyPreferredName))
                .takeRetainedValue() as NSDictionary
            let vendor = (info["DisplayVendorID"] as? NSNumber)?.uint32Value
            let product = (info["DisplayProductID"] as? NSNumber)?.uint32Value
            let serial = (info["DisplaySerialNumber"] as? NSNumber)?.uint32Value ?? 0
            if vendor == CGDisplayVendorNumber(id), product == CGDisplayModelNumber(id),
               serial == 0 || serial == CGDisplaySerialNumber(id) {
                return entry
            }
            IOObjectRelease(entry)
        }
        return nil
    }

    /// The legacy IODisplay brightness parameter, for comparing against DisplayServices in diagnostics.
    static func ioDisplayBrightness(for id: CGDirectDisplayID) -> Float? {
        guard let connect = displayConnect(for: id) else { return nil }
        defer { IOObjectRelease(connect) }
        var value: Float = 0
        let result = IODisplayGetFloatParameter(connect, 0, kIODisplayBrightnessKey as CFString, &value)
        return result == KERN_SUCCESS ? value : nil
    }

    private static func send(_ framebuffer: io_service_t, _ message: [UInt8], _ replyLength: Int) -> [UInt8]? {
        var busCount: IOItemCount = 0
        let countResult = IOFBGetI2CInterfaceCount(framebuffer, &busCount)
        DDCTrace.log?("I2C buses: \(busCount) (result \(countResult))")
        guard countResult == KERN_SUCCESS else { return nil }
        for bus in 0..<busCount {
            var interface = io_service_t()
            guard IOFBCopyI2CInterfaceForBus(framebuffer, IOOptionBits(bus), &interface) == KERN_SUCCESS else {
                DDCTrace.log?("bus \(bus): cannot copy interface")
                continue
            }
            defer { IOObjectRelease(interface) }
            let replyType = replyTransactionType(of: interface)
            var connect: IOI2CConnectRef?
            guard IOI2CInterfaceOpen(interface, 0, &connect) == KERN_SUCCESS, let connect else {
                DDCTrace.log?("bus \(bus): cannot open interface")
                continue
            }
            defer { IOI2CInterfaceClose(connect, 0) }
            if let reply = request(connect, message, replyLength, replyType: replyType) { return reply }
            DDCTrace.log?("bus \(bus): request failed")
        }
        return nil
    }

    /// Some Intel framebuffers reject DDC/CI reply transactions (kIOReturnUnsupportedMode) and only read plainly.
    private static func replyTransactionType(of interface: io_service_t) -> IOOptionBits {
        let supported = (IORegistryEntryCreateCFProperty(interface, kIOI2CTransactionTypesKey as CFString,
                                                         kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber)?.uint32Value ?? 0
        let type = supported & (1 << kIOI2CDDCciReplyTransactionType) != 0
            ? kIOI2CDDCciReplyTransactionType : kIOI2CSimpleTransactionType
        DDCTrace.log?("transaction types: 0x\(String(supported, radix: 16)) -> reply type \(type)")
        return IOOptionBits(type)
    }

    private static func request(_ connect: IOI2CConnectRef, _ message: [UInt8], _ replyLength: Int,
                                replyType: IOOptionBits) -> [UInt8]? {
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
                    request.replyTransactionType = replyType
                    request.replyBuffer = vm_address_t(bitPattern: receive.baseAddress)
                    request.replyBytes = UInt32(replyLength)
                    // The value ddcctl and MonitorControl have shipped for years on Intel framebuffers.
                    // 30_000_000 (meant as 30 ms in ns) froze an AppleIntelFramebuffer Mac outright.
                    request.minReplyDelay = 10
                } else {
                    request.replyTransactionType = IOOptionBits(kIOI2CNoTransactionType)
                }
                let sent = IOI2CSendRequest(connect, 0, &request)
                if sent != KERN_SUCCESS || request.result != kIOReturnSuccess {
                    DDCTrace.log?("  send=0x\(String(UInt32(bitPattern: sent), radix: 16)) result=0x\(String(UInt32(bitPattern: request.result), radix: 16))")
                }
                return sent == KERN_SUCCESS && request.result == kIOReturnSuccess
            }
        }
        return succeeded ? reply : nil
    }
}
#endif
