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
            return L("error.disconnectUnavailable")
        case .lastActiveDisplay:
            return L("error.lastActiveDisplay")
        case .system(let error) where error.rawValue == 1014:
            return L("error.displayAsleep")
        case .system(let error):
            return L("error.system", error.rawValue)
        }
    }
}
