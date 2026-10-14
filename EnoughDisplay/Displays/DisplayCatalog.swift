import AppKit
import CoreGraphics

/// Builds the current list of Displays from the system plus the Displays this app Disconnected.
enum DisplayCatalog {
    static func displays(remembered: [DisplayConnection.Remembered]) -> [Display] {
        let online = list(CGGetOnlineDisplayList)
        let active = Set(list(CGGetActiveDisplayList))
        let rememberedIDs = Set(remembered.map(\.id))

        var displays = online.map { id -> Display in
            Display(
                id: id,
                name: name(of: id),
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                isMain: CGDisplayIsMain(id) != 0,
                state: state(of: id, active: active, remembered: rememberedIDs),
                mirrorsDisplay: mirrorPrimary(of: id))
        }
        // On Apple Silicon a Disconnected Display leaves the online list entirely.
        for display in remembered where !online.contains(display.id) {
            displays.append(Display(
                id: display.id, name: display.name, isBuiltin: display.isBuiltin,
                isMain: false, state: .disconnected, mirrorsDisplay: nil))
        }
        return displays.sorted { ($0.isBuiltin ? 0 : 1, $0.id) < ($1.isBuiltin ? 0 : 1, $1.id) }
    }

    static func activeIDs() -> Set<CGDirectDisplayID> {
        Set(list(CGGetActiveDisplayList))
    }

    private static func state(of id: CGDirectDisplayID, active: Set<CGDirectDisplayID>,
                              remembered: Set<CGDirectDisplayID>) -> Display.State {
        if active.contains(id) || CGDisplayIsInMirrorSet(id) != 0 { return .active }
        if CGDisplayIsAsleep(id) != 0 { return .asleep }
        // Online but neither active nor asleep: Disconnected, by this app or another tool.
        return .disconnected
    }

    private static func mirrorPrimary(of id: CGDirectDisplayID) -> CGDirectDisplayID? {
        let primary = CGDisplayMirrorsDisplay(id)
        return primary == kCGNullDirectDisplay ? nil : primary
    }

    private static func name(of id: CGDirectDisplayID) -> String {
        if let screen = NSScreen.screens.first(where: { $0.displayID == id }) {
            return screen.localizedName
        }
        if let info = PrivateAPI.displayCreateInfoDictionary?(id)?.takeRetainedValue() as? [String: Any],
           let names = info["DisplayProductName"] as? [String: String],
           let name = names[Locale.current.identifier] ?? names["en_US"] ?? names.values.first {
            return name
        }
        return CGDisplayIsBuiltin(id) != 0 ? L("display.name.builtin") : L("display.name.fallback", id)
    }

    private static func list(
        _ query: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError
    ) -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard query(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
