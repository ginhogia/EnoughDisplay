import Foundation
import IOKit
import IOKit.pwr_mgt

/// Holds system sleep until the app has finished its pre-sleep work, using the IOKit power handshake.
///
/// `NSWorkspace.willSleepNotification` gives no way to delay sleep, so Displays could still be mid-Reconnect
/// when the system went down. Here the acknowledgement is withheld until `isReady` reports true or `timeout` passes.
@MainActor
final class SleepGate {
    // iokit_common_msg(...) values from IOKit/IOMessage.h; the macros are not imported into Swift.
    private static let canSystemSleep: UInt32 = 0xE000_0270
    private static let systemWillSleep: UInt32 = 0xE000_0280

    private let prepare: () -> Void
    private let isReady: () -> Bool
    private let timeout: TimeInterval
    private var rootPort: io_connect_t = 0
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0

    init(timeout: TimeInterval = 10, prepare: @escaping () -> Void, isReady: @escaping () -> Bool) {
        self.timeout = timeout
        self.prepare = prepare
        self.isReady = isReady
    }

    func start() {
        guard rootPort == 0 else { return }
        rootPort = IORegisterForSystemPower(Unmanaged.passUnretained(self).toOpaque(), &notifyPort, { refCon, _, message, argument in
            guard let refCon else { return }
            let gate = Unmanaged<SleepGate>.fromOpaque(refCon).takeUnretainedValue()
            let token = Int(bitPattern: argument)
            MainActor.assumeIsolated { gate.handle(message, token: token) }
        }, &notifier)
        guard rootPort != 0, let notifyPort else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(), .commonModes)
    }

    private func handle(_ message: UInt32, token: Int) {
        switch message {
        case Self.canSystemSleep:
            IOAllowPowerChange(rootPort, token)
        case Self.systemWillSleep:
            prepare()
            waitUntilReady(token: token, deadline: Date().addingTimeInterval(timeout))
        default:
            break
        }
    }

    /// Polls on the main run loop, which the Display reconfiguration needs to keep running.
    private func waitUntilReady(token: Int, deadline: Date) {
        if isReady() || Date() >= deadline {
            IOAllowPowerChange(rootPort, token)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitUntilReady(token: token, deadline: deadline)
        }
    }
}
