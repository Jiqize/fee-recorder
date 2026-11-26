import AppKit
import SwiftUI

/// 纸张风格的颜色（DESIGN.md › 颜色）。视图里只用这里的名字，不写字面量颜色。
/// 每个 token 有白天、台灯（夜里）两个值，跟着应用的外观（`NSApp.appearance`，见 `LampMode`）自动换；
/// 皮面三色另外跟着「封皮」设置（`CoverTheme`）。
enum Palette {
    static func hex(_ rgb: UInt32, opacity: Double = 1) -> Color {
        Color(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
              blue: Double(rgb & 0xFF) / 255, opacity: opacity)
    }

    static func ns(_ rgb: UInt32, _ opacity: Double = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: CGFloat(opacity))
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// 白天一个值、台灯一个值。
    static func pair(_ light: UInt32, _ dark: UInt32, opacity: Double = 1, darkOpacity: Double? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { ap in
            isDark(ap) ? ns(dark, darkOpacity ?? opacity) : ns(light, opacity)
        })
    }

    // MARK: 纸与板

    static let paper = pair(0xFAF7EF, 0x2C2823)
    /// 纸上的控件、输入框、强调块。
    static let paperShade = pair(0xF3EFE4, 0x36312B)
    /// 横线。
    static let rule = pair(0xD5E1EC, 0x3D3933)
    /// 红色页边竖线。
    static let margin = pair(0xE4A29A, 0x7A4A44)
    static let hairline = pair(0xE4DED1, 0x403A34)
    /// 方格纸（鱼骨图底）。
    static let grid = pair(0xDDE6EE, 0x3A3630)
    static let cork = pair(0xB07A45, 0x5C4024)
    static let corkDeep = pair(0x8E5E33, 0x3A2816)
    /// 手帐皮面：浅、中、深三色，跟着「封皮」设置和台灯模式。
    static let leather = CoverTheme.color(\.mid)
    static let leatherLight = CoverTheme.color(\.light)
    static let leatherDeep = CoverTheme.color(\.deep)
    static let stitch = hex(0xFAF0DC, opacity: 0.35)
    /// 写在皮面上的字（面板顶带、纪要窗书脊、皮面上的齿轮）：白天夜里都是浅色，皮面本身是深的。
    static let onLeather = hex(0xFAF7EF)
    /// 笔是实物：黑笔身、浅黄字，台灯下也不变色。
    static let penBlack = hex(0x23211E)
    static let penGrey = hex(0x3A3733)
    static let penLabel = hex(0xF7EBB4)
    /// 设置第六张分隔页（AI）的淡紫。
    static let stickyLilac = pair(0xEBD9F0, 0x4A3D55)
    /// 纸底边露出的几层纸。
    static let paperEdge = pair(0xE3DCCB, 0x24201C)
    static let paperEdgeLight = pair(0xEFE9DB, 0x332E28)
    static let leatherShadow = pair(0x3C230F, 0x000000, opacity: 0.35, darkOpacity: 0.6)
    /// 没选中的索引贴（浅蓝）。
    static let tabBack = pair(0xCFE0E8, 0x3A4A55)
    static let kraft = pair(0xD9C79B, 0x6C5C3E)
    static let hole = pair(0x3A3632, 0x14120F)
    /// 拍立得白卡。
    static let polaroid = pair(0xFFFFFF, 0x3A3530)
    static let paperShadow = pair(0x3A2A18, 0x000000, opacity: 0.12, darkOpacity: 0.4)

    // MARK: 墨水

    static let ink = pair(0x23211E, 0xEDE6D8)
    static let body = pair(0x3A3733, 0xDCD4C6)
    static let secondary = pair(0x635E55, 0xB0A798)
    static let tertiary = pair(0x6B655A, 0x9E9586)
    /// 只用于占位形状和中性的小圆点、虚线框，不用于文字。
    static let placeholder = pair(0xBDB6A8, 0x6B6458)
    /// 「你」说的话、用户自己写或改的内容，像蓝色圆珠笔。
    static let inkBlue = pair(0x2F4C9A, 0x93ABE3)
    /// 可点的时间、结论编号：红铅笔。
    static let link = pair(0xB23E17, 0xE88E6A)

    // MARK: 状态

    /// 只表示「正在进行」，不用于文字。
    static let accent = pair(0xE8552B, 0xF07A50)
    static let accentInk = pair(0xB23E17, 0xF09272)
    static let accentPale = pair(0xFBE3D8, 0x4A2E25)
    static let accentWash = pair(0xFFF4EC, 0x3A2A22)
    /// 荧光笔：结论里的数字、日期，搜索命中。
    static let mark = pair(0xFBE58A, 0xB08A2A, darkOpacity: 0.45)
    static let ok = pair(0x2F6B3A, 0x8CC48E)
    static let okPale = pair(0xE1EED8, 0x2F3E2C)
    static let error = pair(0xA8321F, 0xEE7D66)
    static let errorPale = pair(0xF7DED8, 0x4A2A25)
    /// 等待、可自行恢复。
    static let warn = pair(0x8A5A00, 0xE0B050)
    static let warnPale = pair(0xFBEFC8, 0x4A3E22)
    /// 待办的星标（开）。
    static let star = pair(0xE0A800, 0xF0C040)

    // MARK: 便利贴与胶带

    static let stickyPink = pair(0xF4D5D3, 0x5B3B39)
    static let stickyYellow = pair(0xF7EBB4, 0x5A5132)
    static let stickyGreen = pair(0xDCEAC9, 0x3F4F35)
    static let stickySky = pair(0xD8E3F0, 0x34465C)
    static let tapeKraft = pair(0xD9C79B, 0x8A7A58, opacity: 0.7)
    static let tapePink = pair(0xF2B8C6, 0x8A5A66, opacity: 0.7)
    static let tapeGreen = pair(0xB9D9A8, 0x5A7A50, opacity: 0.7)

    // MARK: 说话人

    /// 说话人 1、2、3…，四色循环，在纸上都 ≥ 6:1（台灯下换成亮一档的同色）。
    static let speakers: [Color] = [pair(0x17685F, 0x5FC4B8), pair(0x5B45A6, 0xA898F0), pair(0x9C3468, 0xE888B8), pair(0x7E5300, 0xD8A860)]
    static let you = inkBlue

    // MARK: 旧名字（保留，减少和上游合并时的冲突）

    static let ground = paper
    static let line = hairline
    static let fill = paperShade
    static let raised = paperShade
}

/// 封皮颜色（设置 › 显示 › 封皮，第七轮样稿 ①）。皮面三色在画的时候才从设置里读，换了马上生效；
/// 台灯模式下整体压暗。
enum CoverTheme: String, CaseIterable {
    case caramel, green, navy, rose, black
    static let key = "coverColor"

    var light: UInt32 { switch self { case .caramel: 0xC39669; case .green: 0x4E6D55; case .navy: 0x3B4D72; case .rose: 0xD6A3A0; case .black: 0x3A3633 } }
    var mid: UInt32 { switch self { case .caramel: 0xB88A5A; case .green: 0x3F5A46; case .navy: 0x2E3D5C; case .rose: 0xC98E8C; case .black: 0x2B2826 } }
    var deep: UInt32 { switch self { case .caramel: 0x9C6E40; case .green: 0x2F4636; case .navy: 0x222E47; case .rose: 0xB57775; case .black: 0x1E1C1A } }

    var name: String {
        switch self {
        case .caramel: L("焦糖")
        case .green: L("墨绿")
        case .navy: L("藏青")
        case .rose: L("樱粉")
        case .black: L("黑")
        }
    }

    static var current: CoverTheme {
        CoverTheme(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .caramel
    }

    static func color(_ tone: KeyPath<CoverTheme, UInt32>) -> Color {
        Color(nsColor: NSColor(name: nil) { ap in
            let rgb = current[keyPath: tone]
            let c = Palette.ns(rgb)
            // 台灯下皮面压暗约三分之一
            return Palette.isDark(ap) ? (c.blended(withFraction: 0.38, of: .black) ?? c) : c
        })
    }
}

/// 内页的纸：横线 / 方格 / 点阵（设置 › 显示 › 内页）。字都按 24pt 一行排，方格、点阵 12pt 一格。
enum PaperPattern: String, CaseIterable {
    case ruled, grid, dot
    static let key = "paperPattern"
    static var current: PaperPattern { PaperPattern(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .ruled }

    /// 在画布上画内页的线 / 点（不含底色和红页边线）。
    func draw(_ ctx: GraphicsContext, _ size: CGSize, pitch: CGFloat = 24, origin: CGFloat = 0) {
        switch self {
        case .ruled:
            var y = pitch + origin
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y - 0.5, width: size.width, height: 1)), with: .color(Palette.rule))
                y += pitch
            }
        case .grid:
            let step = pitch / 2
            var y = step + origin
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y - 0.25, width: size.width, height: 0.5)), with: .color(Palette.rule))
                y += step
            }
            var x = step
            while x < size.width {
                ctx.fill(Path(CGRect(x: x - 0.25, y: 0, width: 0.5, height: size.height)), with: .color(Palette.rule))
                x += step
            }
        case .dot:
            let step = pitch / 2
            var y = step + origin
            while y < size.height {
                var x = step
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)), with: .color(Palette.rule))
                    x += step
                }
                y += step
            }
        }
    }
}

/// 台灯模式（设置 › 显示 › 台灯模式）：跟随系统 / 总是开 / 关。决定 `NSApp.appearance`。
enum LampMode: String, CaseIterable {
    case system, on, off
    static let key = "lampMode"
    static var current: LampMode { LampMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system }

    @MainActor static func apply() {
        switch current {
        case .system: NSApp.appearance = nil
        case .on: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .off: NSApp.appearance = NSAppearance(named: .aqua)
        }
    }
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

/// 字号 token（DESIGN.md › 字号）。视图里不写 `.system(size:)`，统一用 `Font.fee(_:strong:)`。
enum TypeRole: CaseIterable {
    case display, title, section, body, bodySecondary, label, meta, caption

    var size: CGFloat {
        switch self {
        case .display: 26
        case .title: 18
        case .section: 15
        case .body: 14
        case .bodySecondary: 13
        case .label, .meta: 12
        case .caption: 11
        }
    }

    /// 默认就是 Medium 的几档（标题类）。
    var medium: Bool { self == .display || self == .title || self == .section }
    /// 数字、时间、快捷键那几档（字体同样是文楷等宽版，2026-11-25 起不再用 SF Mono）。
    var mono: Bool { self == .meta || self == .caption }
}

extension Font {
    /// 全部用霞鹜文楷等宽版（中英文都像打字机加手写，样稿同款）；`strong` 用 Medium。
    /// 没注册上时：数字类回退 SF Mono，其余回退苹方。
    static func fee(_ role: TypeRole, strong: Bool = false) -> Font {
        let medium = role.medium || strong
        guard FeeFonts.registered else {
            return role.mono ? .system(size: role.size, weight: strong ? .semibold : .regular, design: .monospaced)
                             : .system(size: role.size, weight: medium ? .medium : .regular)
        }
        return .custom(medium ? FeeFonts.medium : FeeFonts.regular, fixedSize: role.size)
    }

    /// 手帐左页的大号日期这类不在字号表里的大字（只给数字和两三个字的标题用）。
    static func feeHero(_ size: CGFloat) -> Font {
        FeeFonts.registered ? .custom(FeeFonts.medium, fixedSize: size) : .system(size: size, weight: .medium)
    }

    /// SF Symbols 图标的尺寸：图标留在系统字体里。
    static func icon(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
}

/// 霞鹜文楷等宽版精简版（SIL OFL 1.1，`Resources/fonts/`）。启动时注册到本进程；失败就用系统字体。
enum FeeFonts {
    static let regular = "LXGWWenKaiMonoLite-Regular"
    static let medium = "LXGWWenKaiMonoLite-Medium"
    /// 启动时写一次，之后只读。
    nonisolated(unsafe) private(set) static var registered = false

    @discardableResult
    static func register(in bundle: Bundle = .main) -> Bool {
        let urls = [regular, medium].compactMap { bundle.url(forResource: $0, withExtension: "ttf", subdirectory: "fonts") }
        guard urls.count == 2 else {
            debugLog("fonts: register failed, files missing in \(bundle.bundlePath)")
            return false
        }
        for url in urls {
            var error: Unmanaged<CFError>?
            // 已注册过（重复调用）也算成功
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error),
               let e = error?.takeRetainedValue(), CFErrorGetCode(e) != CTFontManagerError.alreadyRegistered.rawValue {
                debugLog("fonts: register failed for \(url.lastPathComponent): \(e)")
                return false
            }
        }
        registered = true
        return true
    }

    /// 一行字实际占的高度，用来把行距补到横线间距。
    static func lineHeight(_ role: TypeRole) -> CGFloat {
        let size = role.size
        let font: NSFont
        if registered, let f = NSFont(name: role.medium ? medium : regular, size: size) {
            font = f
        } else if role.mono {
            font = .monospacedSystemFont(ofSize: size, weight: .regular)
        } else {
            font = .systemFont(ofSize: size, weight: role.medium ? .medium : .regular)
        }
        return NSLayoutManager().defaultLineHeight(for: font)
    }
}
