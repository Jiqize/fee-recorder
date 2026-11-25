import SwiftUI

// 第三轮：设置（目录页）和引导（第一页）共用的手帐外壳和纸上小部件（样稿 round3-surfaces.html ①②）。
// 外壳的拼法同主窗口 `MainWindowView.body`：皮面 → 压在纸下的分隔页 → 一张横线纸摊开两页。

/// 一本摊开的手帐：皮面、右边伸出的分隔页、两页一张纸。两页的内容由调用方给。
struct PlannerBook<Left: View, Right: View>: View {
    /// 两页的位置和宽度，从窗口左上角（含透明标题栏）量起。
    let spread: CGRect
    /// 两页下面至少留的皮面；两页的高度按窗口实际高度取 24 的整数倍（窗口比内容区多一截标题栏）。
    var bottom: CGFloat = 30
    let leftWidth: CGFloat
    let tabs: [DividerTabs.Item]
    let selected: String
    /// 第一张分隔页离纸上沿的距离。
    var tabsTop: CGFloat = 24
    let pick: (String) -> Void
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    var body: some View {
        GeometryReader { g in
            let height = max(spread.height, ((g.size.height - spread.minY - bottom) / PaperMetrics.pitch).rounded(.down) * PaperMetrics.pitch)
            ZStack(alignment: .topLeading) {
                LeatherCover()
                // 分隔页画在纸下面，左边一截压进纸里
                DividerTabs(items: tabs, selected: selected, pick: pick)
                    .padding(.leading, spread.maxX - DividerTabs.tucked)
                    .padding(.top, spread.minY + tabsTop)
                HStack(spacing: 0) {
                    left.frame(width: leftWidth, height: height, alignment: .topLeading)
                    right.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(width: spread.width, height: height)
                .background(SpreadPaper(leftWidth: leftWidth))
                .padding(.leading, spread.minX).padding(.top, spread.minY)
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
    }
}

/// 目录里的一行：栏目 ······ 页码。当前那一项划荧光笔、加粗，页码红色。占一格。
struct PlannerTOCLine<Extra: View>: View {
    let title: String
    let page: Int
    let on: Bool
    let action: () -> Void
    @ViewBuilder var extra: Extra

    var body: some View {
        Button(action: action) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(title).font(.fee(.body, strong: on)).foregroundStyle(on ? Palette.ink : Palette.body)
                    .lineLimit(1).fixedSize()
                    .highlighter(on)
                extra
                // 点线引导：从栏目名一直点到页码
                DottedLeader().stroke(Palette.placeholder, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 4]))
                    .frame(height: 2).offset(y: -3)
                Text("\(page)").font(.fee(.label, strong: on)).foregroundStyle(on ? Palette.link : Palette.tertiary)
            }
            .frame(height: PaperMetrics.pitch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

extension PlannerTOCLine where Extra == EmptyView {
    init(title: String, page: Int, on: Bool, action: @escaping () -> Void) {
        self.init(title: title, page: page, on: on, action: action, extra: { EmptyView() })
    }
}

private struct DottedLeader: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}

extension View {
    /// 荧光笔划在字的下半截（同主窗口时间线里选中的标题）。
    @ViewBuilder func highlighter(_ on: Bool = true) -> some View {
        if on {
            background(alignment: .leading) {
                Rectangle().fill(Palette.mark.opacity(0.8)).frame(height: 9).offset(y: 4).padding(.horizontal, -2)
            }
        } else {
            self
        }
    }
}

/// 墨水印章按钮：字短就是一枚圆章（`InkStamp`），放不下就压成椭圆章，样式相同。回车也按它。
struct StampButton: View {
    let text: String
    var color: Color = Palette.accent
    let action: () -> Void

    /// 圆章里放得下：按 14pt 字估宽，中日韩字一格、其他半格。
    private var fitsCircle: Bool {
        let width = text.reduce(0.0) { $0 + ($1.unicodeScalars.first.map { $0.value >= 0x2E80 } == true ? 14 : 7.5) }
        return width <= 50
    }

    var body: some View {
        Button(action: action) {
            if fitsCircle {
                InkStamp(text: text, color: color, tilt: -8)
            } else {
                Text(text).font(.fee(.body, strong: true)).foregroundStyle(color).lineLimit(1).fixedSize()
                    .padding(.horizontal, 22).frame(height: 48)
                    .overlay(Ellipse().stroke(color, lineWidth: 2.2))
                    .overlay(Ellipse().stroke(color, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).padding(5))
                    .rotationEffect(.degrees(-5))
                    .opacity(0.86)
                    .contentShape(Ellipse())
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel(text)
    }
}

/// 次要的动作：一行字，下面一道铅笔虚线。
struct DashedWordButton: View {
    let text: String
    let action: () -> Void
    init(_ text: String, action: @escaping () -> Void) {
        self.text = text
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(text).font(.fee(.body)).foregroundStyle(Palette.secondary).lineLimit(1).fixedSize()
                .padding(.bottom, 2)
                .overlay(alignment: .bottom) {
                    DottedLeader().stroke(Palette.placeholder, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(height: 1)
                }
                .frame(height: PaperMetrics.pitch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
