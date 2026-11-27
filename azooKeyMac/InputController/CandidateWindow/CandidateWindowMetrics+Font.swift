import AppKit
import Core

extension CandidateWindowMetrics {
    /// 設定されたファミリーのフォント。見つからなければシステム標準
    func font(ofSize size: Double) -> NSFont {
        guard !self.fontName.isEmpty,
              let font = NSFontManager.shared.font(withFamily: self.fontName, traits: [], weight: 5, size: size) else {
            return .systemFont(ofSize: size)
        }
        return font
    }

    /// 候補本文のフォント
    var candidateFont: NSFont {
        self.font(ofSize: self.fontSize)
    }

    /// 注釈のフォント
    var annotationFont: NSFont {
        self.font(ofSize: self.annotationFontSize)
    }

    /// 行の高さ。行間の広いフォントでも文字が切れないよう、フォントの高さに合わせて広げる
    var effectiveRowHeight: CGFloat {
        let font = self.candidateFont
        let lineHeight = (font.ascender - font.descender + font.leading).rounded(.up)
        // 基準サイズで上下に計8ptの余白
        let padding = (8 * self.fontSize / Self.baseFontSize).rounded()
        return max(self.rowHeight, lineHeight + padding)
    }
}
