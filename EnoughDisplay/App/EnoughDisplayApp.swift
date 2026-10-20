import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            Diagnostics.run()
            return
        }
        EnoughDisplayApp.main()
    }
}

struct EnoughDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("EnoughDisplay", systemImage: "display.2") {
            MenuContentView(model: appDelegate.model, confirmation: appDelegate.model.confirmation)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    private lazy var sleepGate = SleepGate(
        prepare: { [model] in model.prepareForSleep() },
        isReady: { [model] in model.isReadyForSleep() })
    private var wakeSettle: DispatchWorkItem?

    /// Disconnecting again waits this long after the last display change following wake.
    private static let wakeQuietPeriod: TimeInterval = 8

    func applicationDidFinishLaunching(_ notification: Notification) {
        sleepGate.start()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(screensDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        model.onDisplaysChanged = { [weak self] in self?.rearmWakeSettle() }
    }

    /// Cancels a pending restore: the Mac is going back to sleep.
    @objc private func systemWillSleep(_ notification: Notification) {
        wakeSettle?.cancel()
        wakeSettle = nil
    }

    @objc private func screensDidWake(_ notification: Notification) {
        scheduleWakeSettle()
    }

    private func rearmWakeSettle() {
        if wakeSettle != nil { scheduleWakeSettle() }
    }

    /// Debounced: every display change after wake restarts the quiet period, so the private Disconnect call
    /// only runs once CoreDisplay has stopped reconfiguring.
    private func scheduleWakeSettle() {
        wakeSettle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.wakeSettle = nil
            if !self.model.restoreAfterWake() { self.scheduleWakeSettle() }
        }
        wakeSettle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.wakeQuietPeriod, execute: work)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.prepareForQuit()
    }
}
