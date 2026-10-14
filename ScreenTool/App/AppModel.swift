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
    @Published private(set) var launchesAtLogin = LoginItem.isEnabled

    let confirmation = ModeConfirmation()
    let connection = DisplayConnection()
    private var writers: [CGDirectDisplayID: BrightnessWriter] = [:]
    private var refreshScheduled = false

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
        displays.first { $0.id == id }?.name ?? "顯示器 \(id)"
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

    func disconnect(_ display: Display) {
        do {
            try connection.disconnect(display, activeDisplayCount: activeDisplayCount)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func reconnect(_ display: Display) {
        do {
            try connection.reconnect(display.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
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
            errorMessage = "無法變更開機啟動：\(error.localizedDescription)"
        }
        launchesAtLogin = LoginItem.isEnabled
    }

    /// Never leave a Display Disconnected or an unconfirmed Display Mode behind.
    func prepareForQuit() {
        confirmation.revert()
        connection.reconnectAll()
    }
}
