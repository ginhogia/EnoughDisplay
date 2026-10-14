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

    func applicationWillTerminate(_ notification: Notification) {
        model.prepareForQuit()
    }
}
