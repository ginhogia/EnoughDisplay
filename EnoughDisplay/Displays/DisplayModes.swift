import CoreGraphics

/// One Display Mode macOS offers for a Display (see CONTEXT.md).
struct DisplayModeOption: Identifiable, Hashable {
    let mode: CGDisplayMode
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double

    init(_ mode: CGDisplayMode) {
        self.mode = mode
        width = mode.width
        height = mode.height
        pixelWidth = mode.pixelWidth
        pixelHeight = mode.pixelHeight
        refreshRate = mode.refreshRate
    }

    var id: String { "\(width)x\(height)/\(pixelWidth)x\(pixelHeight)@\(refreshRate)" }
    var isHiDPI: Bool { pixelWidth == width * 2 && pixelHeight == height * 2 }
    var resolution: Resolution { Resolution(width: width, height: height, isHiDPI: isHiDPI) }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Display Modes grouped by what the user picks first: logical size and HiDPI.
struct Resolution: Hashable, Comparable, Identifiable {
    let width: Int
    let height: Int
    let isHiDPI: Bool

    var id: String { "\(width)x\(height)\(isHiDPI ? "-hidpi" : "")" }
    var label: String { "\(width) × \(height)\(isHiDPI ? "（HiDPI）" : "")" }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.width, lhs.height, lhs.isHiDPI ? 1 : 0) > (rhs.width, rhs.height, rhs.isHiDPI ? 1 : 0)
    }
}

enum DisplayModes {
    static func options(for id: CGDirectDisplayID) -> [DisplayModeOption] {
        let showAll = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(id, showAll) as? [CGDisplayMode] ?? []
        var seen = Set<String>()
        return modes
            .filter { $0.isUsableForDesktopGUI() }
            .map(DisplayModeOption.init)
            .filter { seen.insert($0.id).inserted }
    }

    static func current(for id: CGDirectDisplayID) -> DisplayModeOption? {
        CGDisplayCopyDisplayMode(id).map(DisplayModeOption.init)
    }

    static func apply(_ mode: CGDisplayMode, to id: CGDirectDisplayID) throws {
        try DisplayConfiguration.perform(.permanently) { CGConfigureDisplayWithDisplayMode($0, id, mode, nil) }
    }

    /// The mode to use when the user picks `resolution`: keep the current refresh rate when possible.
    static func mode(for resolution: Resolution, among options: [DisplayModeOption],
                     preferring refreshRate: Double?) -> DisplayModeOption? {
        let candidates = options.filter { $0.resolution == resolution }
        return candidates.first { $0.refreshRate == refreshRate }
            ?? candidates.max { $0.refreshRate < $1.refreshRate }
    }
}
