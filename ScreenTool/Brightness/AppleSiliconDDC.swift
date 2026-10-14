#if arch(arm64)
import CoreGraphics
import Foundation
import IOKit

/// DDC/CI over Apple Silicon's IOAVService (one DCPAVServiceProxy per external display port).
enum AppleSiliconDDC {
    static func control(for id: CGDirectDisplayID) -> BrightnessControl? {
        guard let service = avService(for: id) else { return nil }
        return DDCBrightness { message, replyLength in transfer(service, message, replyLength) }
    }

    private static func transfer(_ service: CFTypeRef, _ message: [UInt8], _ replyLength: Int) -> [UInt8]? {
        guard let write = PrivateAPI.avServiceWriteI2C, let read = PrivateAPI.avServiceReadI2C else { return nil }
        let chipAddress = UInt32(DDC.monitorAddress >> 1)
        // IOAVService takes the host address byte as its data address.
        var payload = Array(message.dropFirst())
        let written = write(service, chipAddress, UInt32(DDC.hostAddress), &payload, UInt32(payload.count))
        guard written == kIOReturnSuccess else {
            DDCTrace.log?("write failed: \(String(written, radix: 16))")
            return nil
        }
        guard replyLength > 0 else { return [] }
        Thread.sleep(forTimeInterval: 0.05)
        var reply = [UInt8](repeating: 0, count: replyLength)
        guard read(service, chipAddress, 0, &reply, UInt32(replyLength)) == kIOReturnSuccess else { return nil }
        return reply
    }

    // MARK: Matching a CGDirectDisplayID to its IOAVService

    private struct Candidate {
        let service: CFTypeRef
        let vendor: UInt32?
        let product: UInt32?
        let serial: UInt32?
    }

    private static func avService(for id: CGDirectDisplayID) -> CFTypeRef? {
        let candidates = externalServices()
        DDCTrace.log?("external AV services: \(candidates.count)")
        let scored = candidates.map { candidate -> (score: Int, service: CFTypeRef) in
            var score = 0
            if candidate.vendor == CGDisplayVendorNumber(id) { score += 1 }
            if candidate.product == CGDisplayModelNumber(id) { score += 1 }
            if let serial = candidate.serial, serial != 0, serial == CGDisplaySerialNumber(id) { score += 1 }
            return (score, candidate.service)
        }
        if let best = scored.max(by: { $0.score < $1.score }), best.score >= 2 {
            return best.service
        }
        // One external monitor and one external transport must belong together.
        let externalDisplays = DisplayCatalog.activeIDs().filter { CGDisplayIsBuiltin($0) == 0 }
        if candidates.count == 1, externalDisplays == [id] {
            return candidates[0].service
        }
        return nil
    }

    /// Walks the registry in order: each DCPAVServiceProxy follows the framebuffer whose display it drives.
    private static func externalServices() -> [Candidate] {
        guard let create = PrivateAPI.avServiceCreateWithService else { return [] }
        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(
            IORegistryGetRootEntry(kIOMainPortDefault), kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var attributes: [String: Any]?
        var candidates: [Candidate] = []
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            let className = IOObjectCopyClass(entry)?.takeRetainedValue() as String?
            if className == "AppleCLCD2" || className == "IOMobileFramebufferShim" {
                let displayAttributes = property(entry, "DisplayAttributes") as? [String: Any]
                attributes = displayAttributes?["ProductAttributes"] as? [String: Any]
            } else if className == "DCPAVServiceProxy",
                      property(entry, "Location") as? String == "External",
                      let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue() {
                candidates.append(Candidate(
                    service: service,
                    vendor: (attributes?["LegacyManufacturerID"] as? NSNumber)?.uint32Value,
                    product: (attributes?["ProductID"] as? NSNumber)?.uint32Value,
                    serial: (attributes?["SerialNumber"] as? NSNumber)?.uint32Value))
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return candidates
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
#endif
