import Foundation

/// The language of the app's own UI, chosen in the menu independently of the system language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    /// Always shown in its own language, so it can be found whatever the current language is.
    var nativeName: String {
        switch self {
        case .english: return "English"
        case .traditionalChinese: return "中文"
        }
    }

    /// Until the user picks one, Chinese system languages get Chinese and everything else English.
    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .traditionalChinese : .english
    }
}

/// `language` is changed on the main thread; strings are looked up from any thread.
final class Localization: ObservableObject, @unchecked Sendable {
    static let shared = Localization()
    private static let defaultsKey = "AppLanguage"

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
            let bundle = Self.bundle(for: language)
            lock.withLock { self.bundle = bundle }
        }
    }

    private let lock = NSLock()
    private var bundle: Bundle

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey).flatMap(AppLanguage.init(rawValue:))
        language = stored ?? .systemDefault
        bundle = Self.bundle(for: stored ?? .systemDefault)
    }

    func string(_ key: String) -> String {
        lock.withLock { bundle }.localizedString(forKey: key, value: nil, table: nil)
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        Bundle.main.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }
}

/// The UI string for `key` in the app's current language, formatted with `arguments` when given.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = Localization.shared.string(key)
    return arguments.isEmpty ? format : String(format: format, arguments: arguments)
}
