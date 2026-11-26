import Foundation

/// 候補ウィンドウの文字サイズから、注釈・番号の文字サイズや行の高さなどを決める。
///
/// 基準サイズ（18pt）のときに従来の固定値と一致するよう、各値を基準からの比率で拡大縮小する。
public struct CandidateWindowMetrics: Sendable, Equatable {
    public static let baseFontSize: Double = 18

    /// 候補本文の文字サイズ
    public let fontSize: Double

    public init(fontSize: Int) {
        let range = Config.CandidateFontSize.range
        self.fontSize = Double(min(max(fontSize, range.lowerBound), range.upperBound))
    }

    /// 設定値から作る
    public static var current: Self {
        .init(fontSize: Config.CandidateFontSize().value)
    }

    private var scale: Double {
        self.fontSize / Self.baseFontSize
    }

    private func scaled(_ value: Double) -> Double {
        (value * self.scale).rounded()
    }

    /// 注釈の文字サイズ（基準: 12）
    public var annotationFontSize: Double {
        self.scaled(12)
    }

    /// 候補番号の文字サイズ（基準: 8）
    public var indexFontSize: Double {
        self.scaled(8)
    }

    /// 候補番号のベースライン調整（基準: 2）
    public var indexBaselineOffset: Double {
        self.scaled(2)
    }

    /// 予測候補の先頭アイコンのサイズ（基準: 12）
    public var prefixSymbolSize: Double {
        self.scaled(12)
    }

    /// 予測候補の先頭アイコンの後ろのタブ位置（基準: 24）
    public var prefixTabStop: Double {
        self.scaled(24)
    }

    /// 行の高さ（基準: 32）
    public var rowHeight: Double {
        self.scaled(32)
    }

    /// 候補番号を表示するときの左右の余白（基準: 48）
    public var indexedHorizontalPadding: Double {
        self.scaled(48)
    }

    /// 注釈を表示するときに追加する幅（基準: 56）
    public var annotationWidth: Double {
        self.scaled(56)
    }
}
