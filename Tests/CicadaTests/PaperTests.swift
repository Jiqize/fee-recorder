import AppKit
import SwiftUI
import Testing
@testable import Cicada

/// 横线纸的尺寸规则（DESIGN.md › 纸张）：文字行高补到 24pt 横线，页边栏在 1000pt 以下收起。
@Suite struct PaperTests {
    @Test func lineSpacingFillsTheRule() {
        #expect(PaperMetrics.lineSpacing(lineHeight: 19.5) == 4.5)
        #expect(PaperMetrics.lineSpacing(lineHeight: 30) == 0)
    }

    @Test func heightsSnapToWholeRules() {
        #expect(PaperMetrics.snap(25) == 48)
        #expect(PaperMetrics.snap(24) == 24)
        #expect(PaperMetrics.snap(0) == 0)
    }

    @Test func marginColumnNeedsAWideWindow() {
        #expect(PaperMetrics.showsMarginColumn(windowWidth: 999) == false)
        #expect(PaperMetrics.showsMarginColumn(windowWidth: 1000) == true)
    }

    @Test func decorLevelsOrder() {
        #expect(Decor.minimal < .low && Decor.low < .medium && Decor.medium < .full)
    }

    @Test func bodyTextLinesUpWithTheRule() {
        #expect(abs(PaperMetrics.lineSpacing(.body) + FeeFonts.lineHeight(.body) - 24) < 0.5)
    }
}
