import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var confirmation: ModeConfirmation
    @ObservedObject private var localization = Localization.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.displays) { display in
                DisplaySectionView(model: model, display: display, isConfirmingMode: confirmation.pending != nil)
                Divider()
            }

            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(L("menu.launchAtLogin"), isOn: Binding(
                get: { model.launchesAtLogin },
                set: { model.setLaunchesAtLogin($0) }))
                .toggleStyle(.checkbox)

            HStack {
                Picker(L("menu.language"), selection: Binding(
                    get: { localization.language },
                    set: {
                        localization.language = $0
                        // Messages are worded when they occur; drop the one in the old language.
                        model.errorMessage = nil
                    })) {
                    ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help(L("menu.language"))
                Spacer()
                Button(L("menu.quit")) { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 340)
        .overlay(alignment: .topTrailing) {
            Text(model.versionLabel)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(.top, 3).padding(.trailing, 6)
                .allowsHitTesting(false)
        }
        .onAppear { model.reloadSystemBrightness() }
    }
}

struct DisplaySectionView: View {
    @ObservedObject var model: AppModel
    let display: Display
    let isConfirmingMode: Bool
    @ObservedObject private var localization = Localization.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            switch display.state {
            case .active:
                modeControls
                brightnessControl
            case .disconnected:
                Button(L("display.reconnect")) { model.reconnect(display) }
            case .asleep:
                Text(L("display.asleep")).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                .foregroundStyle(display.state == .active ? .primary : .secondary)
            Text(display.name).font(.headline).lineLimit(1)
            ForEach(badges, id: \.self) { badge in
                Text(badge)
                    .font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
            if display.state == .active {
                Button(L("display.disconnect")) { model.disconnect(display) }
                    .controlSize(.small)
                    .disabled(model.activeDisplayCount <= 1 || isConfirmingMode)
                    .help(model.activeDisplayCount <= 1 ? L("display.disconnect.keepOne") : L("display.disconnect.help"))
            }
        }
    }

    private var badges: [String] {
        var badges: [String] = []
        if display.isMain { badges.append(L("display.badge.main")) }
        if display.isMirrorSetMember { badges.append(L("display.badge.mirrored")) }
        if display.state == .disconnected { badges.append(L("display.badge.disconnected")) }
        return badges
    }

    // MARK: Display Mode

    @ViewBuilder
    private var modeControls: some View {
        if display.offersDisplayModes, let current = model.currentModes[display.id] {
            let options = model.modeOptions[display.id] ?? []
            let resolutions = Array(Set(options.map(\.resolution))).sorted()
            let refreshOptions = options
                .filter { $0.resolution == current.resolution }
                .sorted { $0.refreshRate > $1.refreshRate }

            Picker(L("mode.resolution"), selection: Binding(
                get: { current.resolution },
                set: { model.select($0, for: display.id) })) {
                ForEach(resolutions) { Text($0.label).tag($0) }
            }
            .disabled(isConfirmingMode)

            if refreshOptions.count > 1 {
                Picker(L("mode.refreshRate"), selection: Binding(
                    get: { current },
                    set: { model.select($0, for: display.id) })) {
                    ForEach(refreshOptions) { Text(refreshLabel($0)).tag($0) }
                }
                .disabled(isConfirmingMode)
            }
        } else if let primary = display.mirrorsDisplay {
            Text(L("mode.mirroring", model.name(of: primary)))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func refreshLabel(_ option: DisplayModeOption) -> String {
        let pixels = "\(option.pixelWidth)×\(option.pixelHeight)"
        guard option.refreshRate > 0 else { return L("mode.refresh.default", pixels) }
        return L("mode.refresh.hz", option.refreshRate, pixels)
    }

    // MARK: Brightness

    @ViewBuilder
    private var brightnessControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.max").foregroundStyle(.secondary)
            switch model.brightness[display.id] {
            case .supported(let value, let kind):
                Slider(value: Binding(
                    get: { value },
                    set: { model.setBrightness($0, for: display.id) }), in: 0...1)
                Text(L("brightness.kind.\(kind)")).font(.caption2).foregroundStyle(.secondary)
            case .probing, nil:
                ProgressView().controlSize(.small)
                Text(L("brightness.probing")).font(.callout).foregroundStyle(.secondary)
            case .unsupported:
                Slider(value: .constant(0)).disabled(true)
                Text(L("brightness.unsupported")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
