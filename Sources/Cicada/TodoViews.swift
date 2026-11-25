import SwiftUI

// MARK: - 一条待办

/// 角色栏里的状态：☐ 手画方框 / ▸ 红铅笔 / ☑ 绿勾（勾 0.2 秒画出来，减少动态效果时直接出现）。
struct TodoBox: View {
    let state: TodoState
    var size: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 1

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if state == .doing {
                Text("▸").font(.fee(.body, strong: true)).foregroundStyle(Palette.link)
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(state == .done ? Palette.tertiary : Palette.body, lineWidth: 1.5)
                    .frame(width: size, height: size).rotationEffect(.degrees(-3))
                TickShape().trim(from: 0, to: state == .done ? drawn : 0)
                    .stroke(Palette.ok, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .frame(width: size - 1, height: size + 1).offset(x: 2, y: -1)
            }
        }
        .frame(width: size + 4, height: size + 4)
        .onChange(of: state) { old, new in
            guard new == .done, old != .done, !reduceMotion else { drawn = 1; return }
            drawn = 0
            withAnimation(.easeOut(duration: 0.2)) { drawn = 1 }
        }
    }
}

/// 一笔铅笔勾。
private struct TickShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.05, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.35, y: r.maxY - 1))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + 1))
        return p
    }
}

/// 一条待办：方框、文字和负责人、行尾的截止日 / 来源会议 / 星标。点方框打勾，点文字原地改，
/// 右键改状态、星标、截止日、负责人或删除。所有改动都交给 `change`（AppModel.changeTodo）。
struct TodoRow: View {
    let item: NoteItem
    /// 来源会议名（待办板上），点了调 `openSource`；手记写 L("手记")。
    var meeting: String? = nil
    var showOwner = true
    /// 便利贴、实时纪要窗：横排紧凑，不显示来源，不能改截止日。
    var compact = false
    /// 实时纪要窗：只能勾，不显示星标，不能改字、不弹菜单。
    var tickOnly = false
    let change: (TodoChange) -> Void
    var openSource: (() -> Void)? = nil

    @State private var editing = false
    @State private var draft = ""
    @State private var pickingDue = false
    @State private var due = Date()
    @State private var editingOwner = false
    @State private var ownerDraft = ""
    @FocusState private var focused: Bool

    private var done: Bool { item.status == .done }

    var body: some View {
        Group {
            if compact { compactRow } else { ruledRow }
        }
        .contextMenu { if !tickOnly { menu } }
        .popover(isPresented: $pickingDue, arrowEdge: .bottom) { duePicker }
        .popover(isPresented: $editingOwner, arrowEdge: .bottom) { ownerEditor }
    }

    // MARK: 两种排法

    private var ruledRow: some View {
        GutterRow(gutter: {
            box.frame(height: PaperMetrics.pitch).padding(.trailing, 10)
        }, content: {
            if editing { editor } else { words.ruledText(.body).fixedSize(horizontal: false, vertical: true).onTapGesture(perform: startEditing) }
        }, trailing: {
            HStack(spacing: 14) {
                dueLabel.font(.fee(.bodySecondary))
                if let meeting { source(meeting) }
                if !tickOnly { star }
            }
            .frame(height: PaperMetrics.pitch)
        })
    }

    private var compactRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            box.alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            if editing {
                editor
            } else {
                words.font(.fee(.bodySecondary)).fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading).onTapGesture(perform: startEditing)
            }
            Spacer(minLength: 4)
            dueLabel.font(.fee(.label)).fixedSize()
            if !tickOnly, item.isStarred { star }
        }
    }

    // MARK: 零件

    private var box: some View {
        Button { change(.state(item.toggled(now: Date()))) } label: { TodoBox(state: item.status, size: compact ? 12 : 14) }
            .buttonStyle(.plain)
            .help(done ? L("标成没做完") : L("标成做完了"))
            .accessibilityLabel(done ? L("标成没做完") : L("标成做完了"))
    }

    /// 文字 + 灰字负责人；做完了划线变浅；自己加的是黄纸条蓝字。
    private var words: some View {
        let ink: Color = done ? Palette.tertiary : (item.byUser == true ? Palette.inkBlue : Palette.ink)
        var t = Text(item.text).foregroundStyle(ink).strikethrough(done, color: Palette.tertiary)
        if showOwner {
            if item.owner == nil || item.owner == "未识别" {
                t = t + Text(" · " + L("未认领")).font(.fee(.label)).foregroundStyle(Palette.placeholder)
            } else if let o = item.ownerShown {
                t = t + Text(" · " + o).font(.fee(.label)).foregroundStyle(Palette.secondary)
            }
        }
        return t
            .padding(.horizontal, item.byUser == true ? 6 : 0)
            .background(item.byUser == true ? Palette.stickyYellow : .clear)
            .help(tickOnly ? "" : L("点一下修改"))
    }

    @ViewBuilder
    private var dueLabel: some View {
        if let d = item.due {
            let l = TodoDue.label(d, today: Date())
            Text(l.text).foregroundStyle(done ? Palette.tertiary : (l.overdue ? Palette.error : Palette.secondary))
        }
    }

    private func source(_ name: String) -> some View {
        Button { openSource?() } label: {
            Text(name).font(.fee(.label)).foregroundStyle(item.byUser == true && openSource == nil ? Palette.secondary : Palette.link)
                .lineLimit(1).truncationMode(.tail).frame(maxWidth: 140, alignment: .trailing)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Palette.link.opacity(0.4)).frame(height: 1).offset(y: 1).opacity(openSource == nil ? 0 : 1)
                }
        }
        .buttonStyle(.plain).disabled(openSource == nil)
        .help(openSource == nil ? "" : L("打开这句话"))
    }

    private var star: some View {
        Button { change(.star(!item.isStarred)) } label: {
            Text(item.isStarred ? "★" : "☆").font(.fee(.body)).foregroundStyle(item.isStarred ? Palette.star : Palette.placeholder)
        }
        .buttonStyle(.plain).disabled(tickOnly)
        .help(item.isStarred ? L("去星") : L("加星"))
    }

    @ViewBuilder
    private var menu: some View {
        Button(L("没开始")) { change(.state(.open)) }.disabled(item.status == .open)
        Button(L("进行中")) { change(.state(.doing)) }.disabled(item.status == .doing)
        Button(L("做完了")) { change(.state(.done)) }.disabled(done)
        Divider()
        Button(item.isStarred ? L("去星") : L("加星")) { change(.star(!item.isStarred)) }
        if !compact {
            Button(L("设截止日…")) {
                due = item.due.flatMap { TodoDue.date($0) } ?? Date()
                pickingDue = true
            }
        }
        if item.due != nil { Button(L("清除截止日")) { change(.due(nil)) } }
        Button(L("改负责人…")) { ownerDraft = item.owner ?? ""; editingOwner = true }
        Divider()
        Button(L("删除")) { change(.delete) }
    }

    // MARK: 原地改

    private func startEditing() {
        guard !tickOnly else { return }
        draft = item.text
        editing = true
        DispatchQueue.main.async { focused = true }
    }

    private var editor: some View {
        TextField(L("待办"), text: $draft, axis: .vertical)
            .textFieldStyle(.plain).focusEffectDisabled()
            .font(.fee(compact ? .bodySecondary : .body)).lineLimit(1...4)
            .focused($focused)
            .overlay(alignment: .bottom) {
                Rectangle().fill(focused ? Palette.inkBlue : Palette.hairline).frame(height: focused ? 1.5 : 1).offset(y: 2)
            }
            .onSubmit {
                // 清空即删除（.text 的空白规则）
                if draft != item.text { change(.text(draft)) }
                editing = false
            }
            .onExitCommand { editing = false }
            .help(L("⏎ 保存 · esc 取消"))
    }

    private var duePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker("", selection: $due, displayedComponents: .date)
                .datePickerStyle(.graphical).labelsHidden()
            HStack {
                Button(L("清除")) { change(.due(nil)); pickingDue = false }
                    .buttonStyle(.plain).foregroundStyle(Palette.secondary)
                Spacer()
                Button(L("确定")) { change(.due(TodoDue.string(due))); pickingDue = false }
                    .buttonStyle(.plain).foregroundStyle(Palette.accentInk)
                    .keyboardShortcut(.defaultAction)
            }
            .font(.fee(.bodySecondary))
        }
        .padding(12)
    }

    private var ownerEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("负责人"), text: $ownerDraft)
                .textFieldStyle(.plain).font(.fee(.body)).frame(width: 160)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1).offset(y: 2) }
                .onSubmit { saveOwner() }
            Text("⏎ 保存 · esc 取消").font(.fee(.label)).foregroundStyle(Palette.tertiary)
        }
        .padding(12)
    }

    private func saveOwner() {
        let o = ownerDraft.trimmingCharacters(in: .whitespaces)
        change(.owner(o.isEmpty ? nil : o))
        editingOwner = false
    }
}

// MARK: - 加一条

/// 「＋ 加一条」：点开成下划线输入框，⏎ 加上（可以接着加），esc 收起。
struct TodoAddLine: View {
    let add: (String) -> Void
    var compact = false
    @State private var open = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if open {
                TextField(L("要做的事"), text: $draft)
                    .textFieldStyle(.plain).focusEffectDisabled()
                    .font(.fee(compact ? .bodySecondary : .body)).foregroundStyle(Palette.inkBlue)
                    .focused($focused)
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.inkBlue).frame(height: 1.5).offset(y: 2) }
                    .onSubmit {
                        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if t.isEmpty { open = false } else { add(t); draft = "" }
                    }
                    .onExitCommand { open = false; draft = "" }
                    .onAppear { DispatchQueue.main.async { focused = true } }
            } else {
                Button { open = true } label: {
                    (Text("＋ ").foregroundStyle(Palette.link).fontWeight(.semibold) + Text("加一条").foregroundStyle(Palette.secondary))
                        .font(.fee(compact ? .bodySecondary : .body))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: compact ? nil : PaperMetrics.pitch)
    }
}
