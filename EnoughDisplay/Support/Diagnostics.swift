import AppKit
import CoreGraphics

/// `EnoughDisplay --diagnose [--ddc]`: prints what the app sees, for checking a machine from the terminal.
/// DDC talks to monitors over I²C and has frozen an Intel Mac, so it only runs with `--ddc`.
enum Diagnostics {
    static func run() {
        let probeDDC = CommandLine.arguments.contains("--ddc")
        _ = NSApplication.shared  // NSScreen needs a connection to the window server
        print("arch: \(arch)  Disconnect API: \(PrivateAPI.configureDisplayEnabled != nil ? "found" : "MISSING")")
        DDCTrace.log = { print("    ddc: \($0)") }
        let connection = DisplayConnection()
        for display in DisplayCatalog.displays(remembered: connection.remembered) {
            print("\n[\(display.id)] \(display.name)  builtin=\(display.isBuiltin) main=\(display.isMain) state=\(display.state)"
                  + (display.mirrorsDisplay.map { " mirrors=\($0)" } ?? ""))
            print("  vendor=\(CGDisplayVendorNumber(display.id)) model=\(CGDisplayModelNumber(display.id)) serial=\(CGDisplaySerialNumber(display.id))")
            guard display.state == .active else { continue }
            if display.offersDisplayModes {
                let options = DisplayModes.options(for: display.id)
                let current = DisplayModes.current(for: display.id)
                print("  modes: \(options.count) (\(Set(options.map(\.resolution)).count) resolutions)  current: \(current.map(describe) ?? "-")")
            }
            #if arch(x86_64)
            if display.isBuiltin {
                print("  IODisplay brightness: \(IntelDDC.ioDisplayBrightness(for: display.id).map { String(format: "%.2f", $0) } ?? "unavailable")")
            }
            #endif
            let started = Date()
            if let control = Brightness.control(for: display, allowDDC: probeDDC) {
                let value = control.read().map { String(format: "%.2f", $0) } ?? "unreadable"
                print("  brightness: \(control.kind) = \(value)  (\(milliseconds(since: started)) ms)")
            } else {
                print("  brightness: unsupported  (\(milliseconds(since: started)) ms)"
                      + (probeDDC || display.isBuiltin ? "" : "  — DDC not probed, add --ddc"))
            }
        }
    }

    private static func describe(_ option: DisplayModeOption) -> String {
        "\(option.width)x\(option.height) px \(option.pixelWidth)x\(option.pixelHeight) @\(option.refreshRate)Hz"
            + (option.isHiDPI ? " HiDPI" : "")
    }

    private static func milliseconds(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }

    private static var arch: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}
