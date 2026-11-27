import AppKit
import SwiftUI
import Testing
@testable import Cicada

/// 纸张风格的颜色 token（DESIGN.md › 颜色）：色值照抄规范，文字色在纸上都要够清楚。
@Suite struct ThemeTests {
    private func rgb(_ c: Color) -> (Double, Double, Double) {
        let n = NSColor(c).usingColorSpace(.sRGB)!
        return (Double(n.redComponent), Double(n.greenComponent), Double(n.blueComponent))
    }

    private func expect(_ c: Color, _ hex: UInt32, _ name: String) {
        let (r, g, b) = rgb(c)
        let want = (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
        #expect(abs(r - want.0) < 0.002 && abs(g - want.1) < 0.002 && abs(b - want.2) < 0.002, "\(name)")
    }

    @Test func tokensMatchTheSpec() {
        expect(Palette.paper, 0xFAF7EF, "paper")
        expect(Palette.paperShade, 0xF3EFE4, "paperShade")
        expect(Palette.rule, 0xD5E1EC, "rule")
        expect(Palette.margin, 0xE4A29A, "margin")
        expect(Palette.hairline, 0xE4DED1, "hairline")
        expect(Palette.cork, 0xB07A45, "cork")
        expect(Palette.kraft, 0xD9C79B, "kraft")
        expect(Palette.ink, 0x23211E, "ink")
        expect(Palette.body, 0x3A3733, "body")
        expect(Palette.secondary, 0x635E55, "secondary")
        expect(Palette.tertiary, 0x6B655A, "tertiary")
        expect(Palette.inkBlue, 0x2F4C9A, "inkBlue")
        expect(Palette.link, 0xB23E17, "link")
        expect(Palette.accent, 0xE8552B, "accent")
        expect(Palette.mark, 0xFBE58A, "mark")
        expect(Palette.stickyPink, 0xF4D5D3, "stickyPink")
        expect(Palette.polaroid, 0xFFFFFF, "polaroid")
    }

    @Test func oldNamesPointAtTheNewTokens() {
        expect(Palette.ground, 0xFAF7EF, "ground")
        expect(Palette.line, 0xE4DED1, "line")
        expect(Palette.fill, 0xF3EFE4, "fill")
        expect(Palette.raised, 0xF3EFE4, "raised")
    }

    @Test func contrastFormula() {
        #expect(abs(Contrast.ratio(.black, .white) - 21) < 0.01)
        #expect(abs(Contrast.ratio(.white, .white) - 1) < 0.01)
    }

    @Test func textIsReadableOnPaper() {
        let inks: [(String, Color)] = [("ink", Palette.ink), ("body", Palette.body), ("secondary", Palette.secondary),
                                       ("tertiary", Palette.tertiary), ("inkBlue", Palette.inkBlue), ("link", Palette.link),
                                       ("accentInk", Palette.accentInk), ("ok", Palette.ok), ("error", Palette.error),
                                       ("warn", Palette.warn)]
            + Palette.speakers.enumerated().map { ("speaker\($0.offset + 1)", $0.element) }
        for (name, c) in inks {
            #expect(Contrast.ratio(c, Palette.paper) >= 4.5, "\(name)")
        }
    }

    @Test func stickyNotesKeepInkReadable() {
        for note in [Palette.stickyPink, Palette.stickyYellow, Palette.stickyGreen] {
            #expect(Contrast.ratio(Palette.ink, note) >= 4.5)
            #expect(Contrast.ratio(Palette.body, note) >= 4.5)
        }
    }

    /// 自己写的待办是黄纸条蓝字：白天和台灯模式下都要 ≥ 4.5:1。
    @Test func handwrittenTodoIsReadableDayAndNight() {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                #expect(Contrast.ratio(Palette.inkBlue, Palette.stickyYellow) >= 4.5, "\(name.rawValue)")
            }
        }
    }

    @Test func fourSpeakerInks() {
        #expect(Palette.speakers.count == 4)
        expect(Palette.speakers[0], 0x17685F, "speaker1")
        expect(Palette.you, 0x2F4C9A, "you")
    }

    @Test func typeScaleMatchesTheSpec() {
        let spec: [TypeRole: (CGFloat, Bool, Bool)] = [
            .display: (26, true, false), .title: (18, true, false), .section: (15, true, false), .body: (14, false, false),
            .bodySecondary: (13, false, false), .label: (12, false, false), .meta: (12, false, true), .caption: (11, false, true),
        ]
        #expect(spec.count == TypeRole.allCases.count)
        for role in TypeRole.allCases {
            let want = spec[role]!
            #expect(role.size == want.0 && role.medium == want.1 && role.mono == want.2, "\(role)")
        }
        #expect(TypeRole.allCases.map(\.size).min() == 11)
    }

    @Test func registeringFromABundleWithoutFontsFails() {
        #expect(FeeFonts.register(in: Bundle(for: NSObject.self)) == false)
    }

    @Test func bodyLineFitsOneRule() {
        let h = FeeFonts.lineHeight(.body)
        #expect(h > 14 && h < 24)
    }
}
