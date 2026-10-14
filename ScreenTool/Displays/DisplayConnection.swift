import CoreGraphics
import Foundation

/// Disconnects and Reconnects Displays, remembering which ones it Disconnected (see docs/adr/0001).
///
/// A Disconnected Display may vanish from every system display list, so its ID is the only way back.
/// Remembered IDs are tied to the current boot: a reboot brings every Display back by itself.
final class DisplayConnection {
    struct Remembered: Codable, Equatable {
        let id: CGDirectDisplayID
        let name: String
        let isBuiltin: Bool
        let bootTime: TimeInterval
    }

    private static let defaultsKey = "disconnectedDisplays"
    private let defaults: UserDefaults
    private(set) var remembered: [Remembered]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([Remembered].self, from: $0) } ?? []
        remembered = stored.filter { $0.bootTime == Self.bootTime }
        save()
    }

    var isAvailable: Bool { PrivateAPI.configureDisplayEnabled != nil }

    func disconnect(_ display: Display, activeDisplayCount: Int) throws {
        guard activeDisplayCount > 1 else { throw DisplayError.lastActiveDisplay }
        try setEnabled(display.id, false)
        remembered.removeAll { $0.id == display.id }
        remembered.append(Remembered(id: display.id, name: display.name, isBuiltin: display.isBuiltin, bootTime: Self.bootTime))
        save()
    }

    func reconnect(_ id: CGDirectDisplayID) throws {
        try setEnabled(id, true)
        forget(id)
    }

    /// Best effort: used on quit, where there is no one left to report errors to.
    func reconnectAll() {
        for display in remembered {
            try? reconnect(display.id)
        }
    }

    /// Drops remembered Displays that came back by other means (cable replug, another tool).
    func forgetReturned(activeIDs: Set<CGDirectDisplayID>) {
        let before = remembered
        remembered.removeAll { activeIDs.contains($0.id) }
        if remembered != before { save() }
    }

    private func forget(_ id: CGDirectDisplayID) {
        remembered.removeAll { $0.id == id }
        save()
    }

    private func setEnabled(_ id: CGDirectDisplayID, _ enabled: Bool) throws {
        guard let configureDisplayEnabled = PrivateAPI.configureDisplayEnabled else { throw DisplayError.apiUnavailable }
        try DisplayConfiguration.perform(.forSession) { configureDisplayEnabled($0, id, enabled) }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(remembered), forKey: Self.defaultsKey)
    }

    private static let bootTime: TimeInterval = {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &boot, &size, nil, 0)
        return TimeInterval(boot.tv_sec)
    }()
}
