import CoreGraphics
import Foundation

/// Hardware control of one Display's Brightness, on a 0...1 scale. Calls may block; never use from the main thread.
protocol BrightnessControl: AnyObject {
    var kind: String { get }
    var minimumWriteInterval: TimeInterval { get }
    func read() -> Double?
    func write(_ value: Double) -> Bool
}

enum Brightness {
    /// The hardware control for `display`, or nil when its backlight cannot be controlled (it has no Brightness).
    /// Blocking: DDC probing talks to the monitor.
    static func control(for display: Display, allowDDC: Bool = true) -> BrightnessControl? {
        if let builtIn = DisplayServicesBrightness(displayID: display.id) {
            return builtIn
        }
        guard !display.isBuiltin, allowDDC else { return nil }
        #if arch(arm64)
        return AppleSiliconDDC.control(for: display.id)
        #else
        return IntelDDC.control(for: display.id)
        #endif
    }
}

/// Sends Brightness writes one at a time, dropping intermediate values while a slider is dragged.
final class BrightnessWriter {
    let control: BrightnessControl
    private let queue = DispatchQueue(label: "ScreenTool.BrightnessWriter")
    private let lock = NSLock()
    private var latest: Double?
    private var draining = false

    init(control: BrightnessControl) {
        self.control = control
    }

    func submit(_ value: Double) {
        lock.lock()
        latest = value
        let shouldStart = !draining
        draining = true
        lock.unlock()
        if shouldStart { queue.async { self.drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let value = latest else {
                draining = false
                lock.unlock()
                return
            }
            latest = nil
            lock.unlock()
            _ = control.write(value)
            Thread.sleep(forTimeInterval: control.minimumWriteInterval)
        }
    }
}

/// Brightness through macOS's own backlight control: built-in panels and Apple displays.
final class DisplayServicesBrightness: BrightnessControl {
    let displayID: CGDirectDisplayID
    let kind = "系統"
    let minimumWriteInterval: TimeInterval = 0.01

    init?(displayID: CGDirectDisplayID) {
        guard let canChange = PrivateAPI.canChangeBrightness, canChange(displayID),
              PrivateAPI.getBrightness != nil, PrivateAPI.setBrightness != nil else { return nil }
        self.displayID = displayID
    }

    func read() -> Double? {
        var value: Float = 0
        guard PrivateAPI.getBrightness?(displayID, &value) == 0 else { return nil }
        return Double(value)
    }

    func write(_ value: Double) -> Bool {
        PrivateAPI.setBrightness?(displayID, Float(value)) == 0
    }
}
