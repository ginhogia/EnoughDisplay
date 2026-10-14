import CoreGraphics
import Foundation

/// A screen currently known to macOS (see CONTEXT.md).
struct Display: Identifiable, Equatable {
    enum State: Equatable {
        case active
        case disconnected
        case asleep
    }

    let id: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool
    let isMain: Bool
    let state: State
    /// The primary Display of the Mirror Set this Display belongs to, when it is not that primary itself.
    let mirrorsDisplay: CGDirectDisplayID?

    var isMirrorSetMember: Bool { state == .active && CGDisplayIsInMirrorSet(id) != 0 }
    /// Only a Mirror Set's primary Display offers Display Mode choices.
    var offersDisplayModes: Bool { state == .active && mirrorsDisplay == nil }
}

enum DisplayError: LocalizedError {
    case apiUnavailable
    case lastActiveDisplay
    case system(CGError)

    var errorDescription: String? {
        switch self {
        case .apiUnavailable:
            return "這個 macOS 版本不支援斷開顯示器。"
        case .lastActiveDisplay:
            return "至少要保留一個顯示器。"
        case .system(let error) where error.rawValue == 1014:
            return "系統拒絕變更（錯誤 1014），可能有顯示器正在睡眠。請喚醒所有顯示器後再試。"
        case .system(let error):
            return "系統拒絕變更（錯誤 \(error.rawValue)）。"
        }
    }
}
