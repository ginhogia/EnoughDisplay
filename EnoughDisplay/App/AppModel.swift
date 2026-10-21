import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum BrightnessState: Equatable {
        case probing
        case unsupported
        case supported(Double, kind: String)
    }

    @Published private(set) var displays: [Display] = []
    @Published private(set) var modeOptions: [CGDirectDisplayID: [DisplayModeOption]] = [:]
    @Published private(set) var currentModes: [CGDirectDisplayID: DisplayModeOption] = [:]
    @Published private(set) var brightness: [CGDirectDisplayID: BrightnessState] = [:]
    @Published var errorMessage: String?
    let versionLabel = "v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
    @Published private(set) var launchesAtLogin = LoginItem.isEnabled

    let confirmation = ModeConfirmation()
    let connection = DisplayConnection()
    private var writers: [CGDirectDisplayID: BrightnessWriter] = [:]
    private var refreshScheduled = false
    private var isReconfiguring = false
    /// Displays Disconnected before the last system sleep, waiting to be Disconnected again after wake.
    private var disconnectedBeforeSleep: [CGDirectDisplayID] = []
    /// Called after every Display list refresh.
    var onDisplaysChanged: (() -> Void)?

    init() {
        confirmation.onRevertFailure = { [weak self] in self?.errorMessage = $0.localizedDescription }
        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
            let model = Unmanaged<AppModel>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { model.scheduleRefresh() }
        }, Unmanaged.passUnretained(self).toOpaque())
        refresh()
    }

    var activeDisplayCount: Int { displays.filter { $0.state == .active }.count }

    func name(of id: CGDirectDisplayID) -> String {
        displays.first { $0.id == id }?.name ?? L("display.name.fallback", id)
    }

    // MARK: Display list

    /// Reconfiguration callbacks arrive in bursts; refresh once per burst.
    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }

    func refresh() {
        connection.forgetReturned(activeIDs: DisplayCatalog.activeIDs())
        let previousIDs = Set(displays.filter { $0.state == .active }.map(\.id))
        displays = DisplayCatalog.displays(remembered: connection.remembered)

        var options: [CGDirectDisplayID: [DisplayModeOption]] = [:]
        var current: [CGDirectDisplayID: DisplayModeOption] = [:]
        for display in displays where display.offersDisplayModes {
            options[display.id] = DisplayModes.options(for: display.id)
            current[display.id] = DisplayModes.current(for: display.id)
        }
        modeOptions = options
        currentModes = current

        let activeIDs = Set(displays.filter { $0.state == .active }.map(\.id))
        writers = writers.filter { activeIDs.contains($0.key) }
        brightness = brightness.filter { activeIDs.contains($0.key) }
        for display in displays where display.state == .active && !previousIDs.contains(display.id) {
            probeBrightness(display)
        }
        onDisplaysChanged?()
    }

    // MARK: Display Mode

    func select(_ option: DisplayModeOption, for id: CGDirectDisplayID) {
        guard option != currentModes[id] else { return }
        do {
            try confirmation.apply(option.mode, to: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ resolution: Resolution, for id: CGDirectDisplayID) {
        let options = modeOptions[id] ?? []
        if let option = DisplayModes.mode(for: resolution, among: options, preferring: currentModes[id]?.refreshRate) {
            select(option, for: id)
        }
    }

    // MARK: Disconnect

    /// The menu bar window is closed first and the configuration runs off the main thread: reconfiguring Displays
    /// under an open MenuBarExtra window left the menu bar beachballing until the user clicked elsewhere.
    func disconnect(_ display: Display) {
        reconfigure {
            try await self.connection.disconnectOffMain(display, activeDisplayCount: self.activeDisplayCount)
        }
    }

    func reconnect(_ display: Display) {
        reconfigure { try await self.connection.reconnectOffMain(display.id) }
    }

    private func reconfigure(_ change: @escaping () async throws -> Void) {
        guard !isReconfiguring else { return }
        isReconfiguring = true
        MenuBarWindow.toggle()
        Task {
            // Let the window finish closing before the Displays change.
            try? await Task.sleep(nanoseconds: 150_000_000)
            do {
                try await change()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            refresh()
            isReconfiguring = false
        }
    }

    // MARK: Brightness

    private func probeBrightness(_ display: Display) {
        brightness[display.id] = .probing
        Task.detached(priority: .userInitiated) {
            let control = Brightness.control(for: display)
            let value = control?.read()
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let control, let value {
                    self.writers[display.id] = BrightnessWriter(control: control)
                    self.brightness[display.id] = .supported(value, kind: control.kind)
                } else {
                    self.brightness[display.id] = .unsupported
                }
            }
        }
    }

    func setBrightness(_ value: Double, for id: CGDirectDisplayID) {
        guard let writer = writers[id], case .supported(_, let kind) = brightness[id] else { return }
        brightness[id] = .supported(value, kind: kind)
        writer.submit(value)
    }

    /// Picks up changes made elsewhere (keyboard brightness keys) for Displays that are cheap to read.
    func reloadSystemBrightness() {
        for (id, writer) in writers where writer.control is DisplayServicesBrightness {
            if let value = writer.control.read(), case .supported(_, let kind) = brightness[id] {
                brightness[id] = .supported(value, kind: kind)
            }
        }
    }

    // MARK: App

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
        } catch {
            errorMessage = L("error.loginItem", error.localizedDescription)
        }
        launchesAtLogin = LoginItem.isEnabled
    }

    // MARK: Sleep

    /// A Display left Disconnected across system sleep can crash WindowServer on wake (seen on Intel, macOS 15),
    /// so every Display is Reconnected before sleep and Disconnected again after wake (see docs/adr/0001).
    func prepareForSleep() {
        // Keep an unrestored list if the Mac sleeps again before the last wake finished restoring it.
        if !connection.remembered.isEmpty {
            disconnectedBeforeSleep = connection.remembered.map(\.id)
        }
        connection.reconnectAll()
        refresh()
    }

    /// True once no Display is left Disconnected. A Display that is asleep cannot be Reconnected, so waiting
    /// for it would only stall sleep.
    func isReadyForSleep() -> Bool {
        connection.forgetReturned(activeIDs: DisplayCatalog.activeIDs())
        return connection.remembered.isEmpty || DisplayCatalog.isAnyAsleep()
    }

    /// Disconnects again what was Disconnected before sleep, unless only built-in Displays remain.
    /// Disconnect fails while Displays sleep, so this waits for a call made once every Display is awake.
    /// Returns false when a Display is still asleep and the caller should try again later.
    @discardableResult
    func restoreAfterWake() -> Bool {
        guard !disconnectedBeforeSleep.isEmpty else { return true }
        guard !DisplayCatalog.isAnyAsleep() else { return false }
        let ids = disconnectedBeforeSleep
        disconnectedBeforeSleep = []
        refresh()
        guard displays.contains(where: { $0.state == .active && !$0.isBuiltin }) else { return true }
        for id in ids {
            guard let display = displays.first(where: { $0.id == id && $0.state == .active }) else { continue }
            do {
                try connection.disconnect(display, activeDisplayCount: activeDisplayCount)
            } catch {
                errorMessage = error.localizedDescription
            }
            refresh()
        }
        return true
    }

    /// Never leave a Display Disconnected or an unconfirmed Display Mode behind.
    func prepareForQuit() {
        confirmation.revert()
        connection.reconnectAll()
    }
}
