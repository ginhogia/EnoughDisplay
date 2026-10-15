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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(displaysDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(displaysDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        model.prepareForSleep()
    }

    /// Lets the wake-time display reconfiguration settle before Disconnecting again.
    @objc private func displaysDidWake(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [model] in
            model.restoreAfterWake()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.prepareForQuit()
    }
}
