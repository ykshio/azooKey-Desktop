import Foundation

protocol IntConfigItem: ConfigItem<Int> {
    static var `default`: Int { get }
}

extension IntConfigItem {
    public var value: Int {
        get {
            if let value = Config.object(forKey: Self.key) {
                value as? Int ?? Self.default
            } else {
                Self.default
            }
        }
        nonmutating set {
            Config.set(newValue, forKey: Self.key)
        }
    }
}

extension Config {
    public struct ZenzaiInferenceLimit: IntConfigItem {
        public init() {}
        static let `default` = 5
        public static let key = "dev.ensan.inputmethod.azooKeyMac.preference.zenzaiInferenceLimit"
    }
}

extension Config {
    /// 変換候補ウィンドウの文字サイズ（pt）
    public struct CandidateFontSize: IntConfigItem {
        public init() {}
        /// 従来の見た目と同じ値
        public static let `default` = 18
        public static let range: ClosedRange<Int> = 12 ... 32
        public static let key = "dev.ensan.inputmethod.azooKeyMac.preference.candidateFontSize"
    }
}
