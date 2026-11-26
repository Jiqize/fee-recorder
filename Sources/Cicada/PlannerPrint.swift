import AppKit
import PDFKit
import SwiftUI

/// 打印纸（第七轮样稿 ④）：默认 A5，隐藏设置 `printPaper` = "a4" 换 A4。尺寸是 72 dpi 的点。
enum PrintPaper: String {
    case a5, a4
    static let key = "printPaper"
    static var current: PrintPaper { PrintPaper(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .a5 }

    var size: CGSize { self == .a5 ? CGSize(width: 420, height: 595) : CGSize(width: 595, height: 842) }
}

extension Notification.Name {
    /// 菜单「打印…」（⌘P）：主窗口打印它正在显示的会议（选中的会议只有主窗口知道）。
    static let printShownMeeting = Notification.Name("cicada.printShownMeeting")
}

/// 一场会议排成手帐页：横线纸、红页边线、三个打孔位、右上角菲比、摘要 / 议题 / 结论 / 待办，
/// 最后一页盖「菲比记」。排版先算成 24pt 一行的「行」，再分页，画的时候一行一个 `Text`，
/// 所以量出来的高度就是画出来的高度。
enum PlannerPrint {
    static let line: CGFloat = 24
    static let left: CGFloat = 62
    static let right: CGFloat = 28
    /// 第一行的上沿；内容到页脚上方为止。
    static let top: CGFloat = 24
    static let bottom: CGFloat = 36
    /// 待办方框、结论 ✓、议题序号占的宽度，续行按这个缩进。
    static let marker: CGFloat = 16
    /// 第一页标题和元信息给右上角的菲比让出的宽度。
    static let feebeeRoom: CGFloat = 72

    struct Row: Equatable {
        enum Kind: Equatable { case title, meta, head, text, topic, conclusion, todo, term, blank }
        var kind: Kind
        var text = ""
        /// 条目的第一行带记号（序号、✓、方框），续行只缩进。
        var marker: String?
        var done = false
        /// 占几行横线（标题 2 行）。
        var span = 1
        /// 这一行字（含记号）占的宽度，用来给印章找空位。
        var width: CGFloat = 0
    }

    struct Page: Equatable {
        var rows: [Row]
        var number: Int
        var count: Int
        /// 最后一页「菲比记」印章从第几行横线开始盖（占 3 行），其余页 nil。
        var stampRow: Int?
    }

    static func rowsPerPage(_ paper: PrintPaper) -> Int {
        Int((paper.size.height - top - bottom) / line)
    }

    static func contentWidth(_ paper: PrintPaper) -> CGFloat { paper.size.width - left - right }

    // MARK: 字体（和 `Font.fee` 同一款，用来量宽度）

    static func role(_ kind: Row.Kind) -> (TypeRole, Bool) {
        switch kind {
        case .title: (.title, false)
        case .meta: (.caption, false)
        case .head: (.bodySecondary, true)
        default: (.label, false)
        }
    }

    static func nsFont(_ role: TypeRole, strong: Bool) -> NSFont {
        let medium = role.medium || strong
        if FeeFonts.registered, let f = NSFont(name: medium ? FeeFonts.medium : FeeFonts.regular, size: role.size) { return f }
        return role.mono ? .monospacedSystemFont(ofSize: role.size, weight: strong ? .semibold : .regular)
                         : .systemFont(ofSize: role.size, weight: medium ? .medium : .regular)
    }

    /// 按宽度断行（Core Text），段落里的换行照留。留几点余量，免得画的时候差一点被截断。
    static func wrap(_ text: String, _ kind: Row.Kind, width: CGFloat) -> [String] {
        let (r, strong) = role(kind)
        let font = nsFont(r, strong: strong)
        var out: [String] = []
        for para in text.components(separatedBy: .newlines) {
            let ns = para as NSString
            guard ns.length > 0 else { continue }
            let typesetter = CTTypesetterCreateWithAttributedString(NSAttributedString(string: para, attributes: [.font: font]))
            var start = 0
            while start < ns.length {
                let n = CTTypesetterSuggestLineBreak(typesetter, start, Double(width - 6))
                guard n > 0 else { break }
                let piece = ns.substring(with: NSRange(location: start, length: n)).trimmingCharacters(in: .whitespaces)
                if !piece.isEmpty { out.append(piece) }
                start += n
            }
        }
        return out
    }

    /// 一个条目（议题、结论、待办、术语）断成几行：第一行带记号，续行缩进。
    static func item(_ kind: Row.Kind, _ text: String, marker: String, done: Bool = false, width: CGFloat) -> [Row] {
        wrap(text, kind, width: width - self.marker).enumerated().map { i, t in
            Row(kind: kind, text: t, marker: i == 0 ? marker : nil, done: done)
        }
    }

    /// 印章（直径 62）右边离纸边 30pt。
    static let stampSize: CGFloat = 62
    static func stampLeft(_ paper: PrintPaper) -> CGFloat { paper.size.width - 30 - stampSize }

    /// 印章盖在哪：默认最后三行的右下角；那里的字会被压住时，往上找连续三行右边是空的位置
    /// （第一页跳过标题和菲比）。都找不到就还盖在右下角，像真的印章那样压在字上。
    static func stampRow(_ rows: [Row], page: Int, paper: PrintPaper) -> Int {
        let cap = rowsPerPage(paper)
        var reach = [CGFloat](repeating: 0, count: cap + 3)
        var y = 0
        for r in rows {
            for k in y..<min(y + r.span, reach.count) { reach[k] = max(reach[k], r.width) }
            y += r.span
        }
        let room = stampLeft(paper) - left - 4
        let lowest = page == 1 ? 4 : 0
        for start in stride(from: cap - 3, through: lowest, by: -1) where (start..<start + 3).allSatisfy({ reach[$0] <= room }) {
            return start
        }
        return cap - 3
    }

    static func measure(_ row: Row) -> CGFloat {
        guard !row.text.isEmpty else { return 0 }
        let (r, strong) = role(row.kind)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: row.text, attributes: [.font: nsFont(r, strong: strong)]))
        let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        return w + ([.topic, .conclusion, .todo, .term].contains(row.kind) ? marker : 0)
    }

    static func circled(_ i: Int) -> String {
        i < 20 ? String(UnicodeScalar(0x2460 + UInt32(i))!) : "\(i + 1)."
    }

    // MARK: 分页

    /// 一块内容：`units` 是不能拆开的几组行；`splits` 的块（摘要）可以一行一行续到下一页。
    private struct Block {
        var head: Row?
        var units: [[Row]]
        var splits = false
    }

    static func paginate(_ s: Session, paper: PrintPaper) -> [Page] {
        let width = contentWidth(paper)
        let cap = rowsPerPage(paper)
        let notes = s.notes

        // 第一页页眉：标题（窄一点，给菲比让位）、元信息、空一行
        var header: [Row] = []
        let titleLines = wrap(s.displayTitle, .title, width: width - feebeeRoom)
        for (i, t) in titleLines.enumerated() { header.append(Row(kind: .title, text: t, span: i == 0 ? 2 : 1)) }
        let people = TranscriptExport.participants(s)
        let meta = TranscriptExport.header(s) + (people.isEmpty ? "" : " · " + people.joined(separator: "、"))
        header += wrap(meta, .meta, width: width - feebeeRoom).map { Row(kind: .meta, text: $0) }

        var blocks: [Block] = []
        if let n = notes, !n.summary.isEmpty {
            blocks.append(Block(head: Row(kind: .head, text: L("摘要")),
                                units: wrap(n.summary, .text, width: width).map { [Row(kind: .text, text: $0)] }, splits: true))
        }
        if let n = notes, !n.topics.isEmpty {
            // 一个议题一行：标题 · 第一个要点，太长就截断
            let units = n.topics.enumerated().map { i, t -> [Row] in
                let text = t.points.first.map { "\(t.title) · \($0)" } ?? t.title
                var rows = item(.topic, text, marker: circled(i), width: width)
                if rows.count > 1 { rows = [rows[0]]; rows[0].text = String(rows[0].text.dropLast()) + "…" }
                return rows
            }
            blocks.append(Block(head: Row(kind: .head, text: L("议题")), units: units))
        }
        if let n = notes, !n.conclusions.isEmpty {
            blocks.append(Block(head: Row(kind: .head, text: L("结论")),
                                units: n.conclusions.map { item(.conclusion, $0.text, marker: "✓", width: width) }))
        }
        if let n = notes, !n.todos.isEmpty {
            let units = n.todos.map { t -> [Row] in
                var parts = [t.text]
                if let o = t.ownerShown { parts.append(o) }
                if let d = t.due.flatMap({ TodoDue.date($0) }) { parts.append(dateText(d, "MMMd")) }
                return item(.todo, parts.joined(separator: " · "), marker: "□", done: t.status == .done, width: width)
            }
            blocks.append(Block(head: Row(kind: .head, text: L("待办")), units: units))
        }

        var pages: [[Row]] = [header]
        var used = header.reduce(0) { $0 + $1.span }
        func newPage() { pages.append([]); used = 0 }
        func place(_ unit: [Row]) {
            // 一页放不下的单个条目只好一行一行放
            if unit.count > cap { unit.forEach { place([$0]) }; return }
            if used + unit.count > cap, !(pages.last?.isEmpty ?? true) { newPage() }
            pages[pages.count - 1] += unit
            used += unit.reduce(0) { $0 + $1.span }
        }
        func gap() { if used > 0, used < cap { pages[pages.count - 1].append(Row(kind: .blank)); used += 1 } }

        for b in blocks {
            gap()
            var units = b.units
            if b.splits {
                // 小标题至少带两行正文，其余逐行续页
                let lead = units.prefix(2).flatMap { $0 }
                units = Array(units.dropFirst(2))
                place((b.head.map { [$0] } ?? []) + lead)
                units.forEach { place($0) }
            } else if let first = units.first {
                place((b.head.map { [$0] } ?? []) + first)
                units.dropFirst().forEach { place($0) }
            }
        }

        // 人名和术语：最后一页还放得下才印
        if let n = notes, !n.terms.isEmpty {
            let rows = [Row(kind: .blank), Row(kind: .head, text: L("人名和术语"))]
                + n.terms.flatMap { item(.term, $0.note.isEmpty ? $0.name : "\($0.name) · \($0.note)", marker: "·", width: width) }
            if used + rows.count <= cap { pages[pages.count - 1] += rows }
        }

        // 页尾的空行没有意义
        for i in pages.indices {
            while pages[i].last?.kind == .blank { pages[i].removeLast() }
            for j in pages[i].indices { pages[i][j].width = measure(pages[i][j]) }
        }
        let count = pages.count
        return pages.enumerated().map { i, rows in
            Page(rows: rows, number: i + 1, count: count,
                 stampRow: i + 1 == count ? stampRow(rows, page: i + 1, paper: paper) : nil)
        }
    }

    // MARK: PDF 与打印

    /// 所有页画进一份矢量 PDF（导出、打印、调试命令共用）。总是白天的纸色，台灯模式开着也一样。
    @MainActor static func pdfData(_ s: Session, paper: PrintPaper = .current) -> Data {
        let pages = paginate(s, paper: paper)
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: paper.size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        let title = s.displayTitle
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            for p in pages {
                let r = ImageRenderer(content: PlannerPrintPage(page: p, paper: paper, title: title))
                r.proposedSize = ProposedViewSize(paper.size)
                r.render { _, draw in
                    ctx.beginPDFPage(nil)
                    draw(ctx)
                    ctx.endPDFPage()
                }
            }
        }
        ctx.closePDF()
        return data as Data
    }

    /// 会议记录主窗口（菜单「打印…」只在它在最前时可用）。
    @MainActor static var mainWindow: NSWindow? { NSApp.windows.first { $0.contentView is NSHostingView<MainWindowView> } }

    /// 系统打印对话框（⌘P）：打印的就是导出 PDF 的那几页。
    @MainActor static func print(_ s: Session, in window: NSWindow?) {
        let paper = PrintPaper.current
        guard let doc = PDFDocument(data: pdfData(s, paper: paper)) else { return }
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        info.paperSize = paper.size
        info.orientation = .portrait
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        guard let op = doc.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: false) else { return }
        op.jobTitle = s.displayTitle
        debugLog("print: \(s.id) \(doc.pageCount) pages \(paper.rawValue)")
        if let window { op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil) } else { op.run() }
    }
}

/// 一张手帐页（打印、导出 PDF 用）。
struct PlannerPrintPage: View {
    let page: PlannerPrint.Page
    let paper: PrintPaper
    let title: String

    private var size: CGSize { paper.size }
    private typealias P = PlannerPrint

    var body: some View {
        ZStack(alignment: .topLeading) {
            Palette.paper
            // 横线：每 24pt 一条，到页脚上方
            Path { p in
                var y = P.top + P.line
                while y <= size.height - P.bottom + 0.5 {
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                    y += P.line
                }
            }
            .stroke(Palette.rule, lineWidth: 1)
            // 红页边线
            Path { p in p.move(to: CGPoint(x: 46, y: 0)); p.addLine(to: CGPoint(x: 46, y: size.height)) }
                .stroke(Palette.margin, lineWidth: 1)
            // 三个打孔位（纯填色，不用阴影，免得整页变成位图）
            ForEach([0.15, 0.49, 0.82], id: \.self) { f in
                Circle().fill(Palette.paperEdge).overlay(Circle().stroke(Palette.hairline, lineWidth: 1))
                    .frame(width: 12, height: 12)
                    .offset(x: 14, y: size.height * f)
            }
            if page.number == 1 {
                FeebeeView(mood: .done, size: 64, animated: false).rotationEffect(.degrees(6))
                    .offset(x: size.width - 18 - 64, y: 14)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(page.rows.enumerated()), id: \.offset) { _, row in rowView(row) }
            }
            .frame(width: P.contentWidth(paper), alignment: .topLeading)
            .offset(x: P.left, y: P.top)
            if let row = page.stampRow {
                InkStamp(text: L("菲比记"), color: Palette.error, tilt: -10)
                    .offset(x: P.stampLeft(paper), y: P.top + CGFloat(row) * P.line + (3 * P.line - P.stampSize) / 2)
            }
            HStack {
                Text(title).lineLimit(1)
                Spacer(minLength: 12)
                Text("\(page.number) / \(page.count)")
            }
            .font(.fee(.caption)).foregroundStyle(Palette.tertiary)
            .frame(width: P.contentWidth(paper))
            .offset(x: P.left, y: size.height - 14 - 14)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private func rowView(_ row: PlannerPrint.Row) -> some View {
        let (role, strong) = P.role(row.kind)
        let color: Color = switch row.kind {
        case .title, .head: Palette.ink
        case .meta: Palette.tertiary
        default: Palette.body
        }
        HStack(alignment: .center, spacing: 0) {
            if [.topic, .conclusion, .todo, .term].contains(row.kind) {
                marker(row).frame(width: P.marker, alignment: .leading)
            }
            Text(row.text).font(.fee(role, strong: strong)).foregroundStyle(color)
                .lineLimit(1).fixedSize()
        }
        .padding(.bottom, row.kind == .title ? 8 : 5)
        .frame(height: P.line * CGFloat(row.span), alignment: .bottomLeading)
    }

    @ViewBuilder
    private func marker(_ row: PlannerPrint.Row) -> some View {
        if let m = row.marker {
            switch row.kind {
            case .todo:
                // 空方框，打印出来手写打勾；已做完的画好勾
                RoundedRectangle(cornerRadius: 1.5).stroke(Palette.secondary, lineWidth: 1)
                    .frame(width: 9, height: 9)
                    .overlay { if row.done { Text("✓").font(.fee(.caption)).foregroundStyle(Palette.ok) } }
            case .conclusion:
                Text(m).font(.fee(.label, strong: true)).foregroundStyle(Palette.ok)
            default:
                Text(m).font(.fee(.label)).foregroundStyle(Palette.secondary)
            }
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }
}
