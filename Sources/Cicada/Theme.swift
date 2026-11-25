import AppKit
import SwiftUI

/// 纸张风格的颜色（DESIGN.md › 颜色）。视图里只用这里的名字，不写字面量颜色。
/// 只有浅色模式（应用强制 `.aqua`），所以每个 token 只有一个值。
enum Palette {
    static func hex(_ rgb: UInt32, opacity: Double = 1) -> Color {
        Color(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
              blue: Double(rgb & 0xFF) / 255, opacity: opacity)
    }

    // MARK: 纸与板

    static let paper = hex(0xFAF7EF)
    /// 纸上的控件、输入框、强调块。
    static let paperShade = hex(0xF3EFE4)
    /// 横线。
    static let rule = hex(0xD5E1EC)
    /// 红色页边竖线。
    static let margin = hex(0xE4A29A)
    static let hairline = hex(0xE4DED1)
    /// 方格纸（鱼骨图底）。
    static let grid = hex(0xDDE6EE)
    static let cork = hex(0xB07A45)
    static let corkDeep = hex(0x8E5E33)
    static let kraft = hex(0xD9C79B)
    static let hole = hex(0x3A3632)
    /// 拍立得白卡。
    static let polaroid = hex(0xFFFFFF)
    static let paperShadow = hex(0x3A2A18, opacity: 0.12)

    // MARK: 墨水

    static let ink = hex(0x23211E)
    static let body = hex(0x3A3733)
    static let secondary = hex(0x635E55)
    static let tertiary = hex(0x6B655A)
    /// 只用于占位形状和中性的小圆点、虚线框，不用于文字。
    static let placeholder = hex(0xBDB6A8)
    /// 「你」说的话、用户自己写或改的内容，像蓝色圆珠笔。
    static let inkBlue = hex(0x2F4C9A)
    /// 可点的时间、结论编号：红铅笔。
    static let link = hex(0xB23E17)

    // MARK: 状态

    /// 只表示「正在进行」，不用于文字。
    static let accent = hex(0xE8552B)
    static let accentInk = hex(0xB23E17)
    static let accentPale = hex(0xFBE3D8)
    static let accentWash = hex(0xFFF4EC)
    /// 荧光笔：结论里的数字、日期，搜索命中。
    static let mark = hex(0xFBE58A)
    static let ok = hex(0x2F6B3A)
    static let okPale = hex(0xE1EED8)
    static let error = hex(0xA8321F)
    static let errorPale = hex(0xF7DED8)
    /// 等待、可自行恢复。
    static let warn = hex(0x8A5A00)
    static let warnPale = hex(0xFBEFC8)

    // MARK: 便利贴与胶带

    static let stickyPink = hex(0xF4D5D3)
    static let stickyYellow = hex(0xF7EBB4)
    static let stickyGreen = hex(0xDCEAC9)
    static let tapeKraft = hex(0xD9C79B, opacity: 0.7)
    static let tapePink = hex(0xF2B8C6, opacity: 0.7)
    static let tapeGreen = hex(0xB9D9A8, opacity: 0.7)

    // MARK: 说话人

    /// 说话人 1、2、3…，四色循环，在纸上都 ≥ 6:1。
    static let speakers: [Color] = [hex(0x17685F), hex(0x5B45A6), hex(0x9C3468), hex(0x7E5300)]
    static let you = inkBlue

    // MARK: 示例会议画面（引导里模拟的深色会议软件，只是插图）

    static let mockScreen = hex(0x1A1C21)
    static let mockTile = hex(0x262930)
    static let mockTileEdge = hex(0x2E3038)
    static let mockAvatarA = hex(0x5C6378)
    static let mockAvatarB = hex(0x6B5C4F)

    // MARK: 旧名字（保留，减少和上游合并时的冲突）

    static let ground = paper
    static let line = hairline
    static let fill = paperShade
    static let raised = paperShade
}

/// WCAG 2.x 对比度，用来在测试里守住「文字 ≥ 4.5:1」。
enum Contrast {
    static func ratio(_ a: Color, _ b: Color) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func luminance(_ c: Color) -> Double {
        guard let n = NSColor(c).usingColorSpace(.sRGB) else { return 0 }
        func lin(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(n.redComponent) + 0.7152 * lin(n.greenComponent) + 0.0722 * lin(n.blueComponent)
    }
}
