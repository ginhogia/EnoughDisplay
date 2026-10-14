import AppKit
import CoreGraphics
import SwiftUI

/// The countdown after a Display Mode change; without confirmation the Display reverts (see CONTEXT.md).
@MainActor
final class ModeConfirmation: ObservableObject {
    static let duration = 15

    struct Pending {
        let displayID: CGDirectDisplayID
        let previous: CGDisplayMode
        var secondsLeft: Int
    }

    @Published private(set) var pending: Pending?
    var onRevertFailure: ((Error) -> Void)?

    private var countdown: Task<Void, Never>?
    private var panels: [NSPanel] = []

    func apply(_ mode: CGDisplayMode, to id: CGDirectDisplayID) throws {
        guard pending == nil, let previous = CGDisplayCopyDisplayMode(id) else { return }
        try DisplayModes.apply(mode, to: id)
        pending = Pending(displayID: id, previous: previous, secondsLeft: Self.duration)
        countdown = Task { [weak self] in
            // Let the screens settle in their new mode before placing the panels on them.
            try? await Task.sleep(nanoseconds: 700_000_000)
            self?.showPanels()
            while let self, let pending = self.pending, pending.secondsLeft > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                self.pending?.secondsLeft -= 1
            }
            self?.revert()
        }
    }

    func confirm() {
        finish()
    }

    func revert() {
        guard let pending else { return }
        do {
            try DisplayModes.apply(pending.previous, to: pending.displayID)
        } catch {
            onRevertFailure?(error)
        }
        finish()
    }

    private func finish() {
        countdown?.cancel()
        countdown = nil
        pending = nil
        panels.forEach { $0.close() }
        panels = []
    }

    /// One panel per screen, so the user can confirm even if the changed Display went black.
    private func showPanels() {
        guard pending != nil else { return }
        panels = NSScreen.screens.map { screen in
            let panel = ConfirmationPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 150),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.contentView = NSHostingView(rootView: ModeConfirmationView(confirmation: self))
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - 190, y: frame.midY - 75))
            panel.orderFrontRegardless()
            return panel
        }
    }
}

private final class ConfirmationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct ModeConfirmationView: View {
    @ObservedObject var confirmation: ModeConfirmation

    var body: some View {
        VStack(spacing: 14) {
            Text("要保留這個顯示模式嗎？")
                .font(.headline)
            Text("\(confirmation.pending?.secondsLeft ?? 0) 秒後自動還原")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("還原") { confirmation.revert() }
                    .keyboardShortcut(.cancelAction)
                Button("保留") { confirmation.confirm() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380, height: 150)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
