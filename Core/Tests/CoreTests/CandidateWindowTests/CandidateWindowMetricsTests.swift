@testable import Core
import Testing

@Test func candidateWindowMetricsKeepsLegacyValuesAtDefaultSize() {
    let metrics = CandidateWindowMetrics(fontSize: Config.CandidateFontSize.default)
    #expect(metrics.fontSize == 18)
    #expect(metrics.annotationFontSize == 12)
    #expect(metrics.indexFontSize == 8)
    #expect(metrics.indexBaselineOffset == 2)
    #expect(metrics.prefixSymbolSize == 12)
    #expect(metrics.prefixTabStop == 24)
    #expect(metrics.rowHeight == 32)
    #expect(metrics.indexedHorizontalPadding == 48)
    #expect(metrics.annotationWidth == 56)
}

@Test func candidateWindowMetricsScalesWithFontSize() {
    let metrics = CandidateWindowMetrics(fontSize: 27)
    #expect(metrics.fontSize == 27)
    #expect(metrics.annotationFontSize == 18)
    #expect(metrics.indexFontSize == 12)
    #expect(metrics.rowHeight == 48)
}

@Test func candidateWindowMetricsClampsOutOfRangeValues() {
    #expect(CandidateWindowMetrics(fontSize: 1).fontSize == Double(Config.CandidateFontSize.range.lowerBound))
    #expect(CandidateWindowMetrics(fontSize: 1000).fontSize == Double(Config.CandidateFontSize.range.upperBound))
}

@Test func candidateWindowMetricsDetectsFontChange() {
    // フォントだけ変えても、候補ウィンドウが寸法を更新するよう別物として扱う
    #expect(CandidateWindowMetrics(fontSize: 18) == CandidateWindowMetrics(fontSize: 18, fontName: ""))
    #expect(CandidateWindowMetrics(fontSize: 18) != CandidateWindowMetrics(fontSize: 18, fontName: "Hiragino Mincho ProN"))
}
