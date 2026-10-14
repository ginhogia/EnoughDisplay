import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var confirmation: ModeConfirmation

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

            Toggle("開機時啟動", isOn: Binding(
                get: { model.launchesAtLogin },
                set: { model.setLaunchesAtLogin($0) }))
                .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("結束 ScreenTool") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { model.reloadSystemBrightness() }
    }
}

struct DisplaySectionView: View {
    @ObservedObject var model: AppModel
    let display: Display
    let isConfirmingMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            switch display.state {
            case .active:
                modeControls
                brightnessControl
            case .disconnected:
                Button("重新連接") { model.reconnect(display) }
            case .asleep:
                Text("顯示器睡眠中").font(.callout).foregroundStyle(.secondary)
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
                Button("斷開") { model.disconnect(display) }
                    .controlSize(.small)
                    .disabled(model.activeDisplayCount <= 1 || isConfirmingMode)
                    .help(model.activeDisplayCount <= 1 ? "至少要保留一個顯示器" : "讓 macOS 停止輸出畫面到這個顯示器")
            }
        }
    }

    private var badges: [String] {
        var badges: [String] = []
        if display.isMain { badges.append("主要") }
        if display.isMirrorSetMember { badges.append("鏡像中") }
        if display.state == .disconnected { badges.append("已斷開") }
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

            Picker("解析度", selection: Binding(
                get: { current.resolution },
                set: { model.select($0, for: display.id) })) {
                ForEach(resolutions) { Text($0.label).tag($0) }
            }
            .disabled(isConfirmingMode)

            if refreshOptions.count > 1 {
                Picker("更新率", selection: Binding(
                    get: { current },
                    set: { model.select($0, for: display.id) })) {
                    ForEach(refreshOptions) { Text(refreshLabel($0)).tag($0) }
                }
                .disabled(isConfirmingMode)
            }
        } else if let primary = display.mirrorsDisplay {
            Text("鏡像中：解析度跟隨「\(model.name(of: primary))」")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func refreshLabel(_ option: DisplayModeOption) -> String {
        let pixels = "\(option.pixelWidth)×\(option.pixelHeight)"
        guard option.refreshRate > 0 else { return "預設（\(pixels)）" }
        return String(format: "%g Hz（%@）", option.refreshRate, pixels)
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
                Text(kind).font(.caption2).foregroundStyle(.secondary)
            case .probing, nil:
                ProgressView().controlSize(.small)
                Text("偵測亮度控制…").font(.callout).foregroundStyle(.secondary)
            case .unsupported:
                Slider(value: .constant(0)).disabled(true)
                Text("不支援").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
