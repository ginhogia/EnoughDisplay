import CoreGraphics
import Foundation
import IOKit

/// Private system functions, resolved at runtime so a missing symbol degrades a feature instead of crashing.
enum PrivateAPI {
    private static let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT

    private static func load<T>(_ name: String, from path: String? = nil, as type: T.Type) -> T? {
        let handle = path.map { dlopen($0, RTLD_LAZY) } ?? defaultHandle
        guard let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    // MARK: Disconnect

    typealias ConfigureDisplayEnabled = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
    static let configureDisplayEnabled =
        load("CGSConfigureDisplayEnabled", as: ConfigureDisplayEnabled.self)
        ?? load("SLSConfigureDisplayEnabled",
                from: "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                as: ConfigureDisplayEnabled.self)

    // MARK: Display names

    typealias DisplayCreateInfoDictionary = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?
    static let displayCreateInfoDictionary = load(
        "CoreDisplay_DisplayCreateInfoDictionary",
        from: "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
        as: DisplayCreateInfoDictionary.self)

    // MARK: Built-in Brightness

    private static let displayServices = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    typealias CanChangeBrightness = @convention(c) (CGDirectDisplayID) -> Bool
    typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    static let canChangeBrightness = load("DisplayServicesCanChangeBrightness", from: displayServices, as: CanChangeBrightness.self)
    static let getBrightness = load("DisplayServicesGetBrightness", from: displayServices, as: GetBrightness.self)
    static let setBrightness = load("DisplayServicesSetBrightness", from: displayServices, as: SetBrightness.self)

    // MARK: Apple Silicon DDC

    typealias AVServiceCreateWithService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias AVServiceI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    static let avServiceCreateWithService = load("IOAVServiceCreateWithService", as: AVServiceCreateWithService.self)
    static let avServiceReadI2C = load("IOAVServiceReadI2C", as: AVServiceI2C.self)
    static let avServiceWriteI2C = load("IOAVServiceWriteI2C", as: AVServiceI2C.self)
}
