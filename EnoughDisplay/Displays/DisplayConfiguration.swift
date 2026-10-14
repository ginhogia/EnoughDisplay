import CoreGraphics

/// Runs one CoreGraphics display configuration transaction.
enum DisplayConfiguration {
    static func perform(_ option: CGConfigureOption, _ change: (CGDisplayConfigRef) -> CGError) throws {
        var config: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&config))
        guard let config else { throw DisplayError.system(.failure) }
        let error = change(config)
        guard error == .success else {
            CGCancelDisplayConfiguration(config)
            throw DisplayError.system(error)
        }
        try check(CGCompleteDisplayConfiguration(config, option))
    }

    private static func check(_ error: CGError) throws {
        if error != .success { throw DisplayError.system(error) }
    }
}
