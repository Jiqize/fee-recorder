import SwiftUI

/// 改这句… in the meeting record: the line as shown, to rewrite. What changed becomes the user's
/// own fix (`LiveFixes.edit`), on every line heard the same way or only this one.
struct LineEditor: View {
    let line: TranscriptLine
    let session: String
    @ObservedObject var fixes: LiveFixes
    let start: String
    let onDone: () -> Void
    @State private var text = ""
    @State private var everywhere = true
    @State private var keep = true
    @FocusState private var focused: Bool

    var body: some View {
        let same = fixes.sameHeard(lineID: line.id, in: session, edited: text)
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("改这句"), text: $text, axis: .vertical)
                // 改这句：原地一张黄便签，蓝圆珠笔字，下面一道蓝线（第四轮样稿 ⑤）
                .textFieldStyle(.plain).font(.fee(.body)).lineSpacing(2).foregroundStyle(Palette.inkBlue)
                .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 7)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.inkBlue).frame(height: 1.4).padding(.horizontal, 10).padding(.bottom, 4) }
                .slipBackground(.note)
                .focused($focused)
                .onSubmit(apply)
                .onExitCommand(perform: onDone)
            if let same {
                HStack(spacing: 6) {
                    Text("听成").foregroundStyle(Palette.tertiary)
                    Text(same.heard)
                }
                .font(.fee(.bodySecondary))
                if same.count > 1 {
                    Picker("", selection: $everywhere) {
                        Text("整场听成 \(same.heard) 的 \(same.count) 处都改").tag(true)
                        Text("只改这一处").tag(false)
                    }
                    .pickerStyle(.radioGroup).labelsHidden().font(.fee(.bodySecondary))
                }
                // Only a word for a word can teach the list: an added or dropped word can't.
                if same.swap {
                    Toggle("记进词表，以后自动改", isOn: $keep)
                        .toggleStyle(.checkbox).font(.fee(.bodySecondary))
                        .disabled(same.count > 1 && !everywhere)
                }
            }
            HStack(spacing: 8) {
                Text("回车 改成 · esc 取消").font(.fee(.label)).foregroundStyle(Palette.tertiary)
                Spacer()
                SoftButton(L("取消"), action: onDone)
                SoftButton(L("改成"), dark: true, action: apply)
            }
        }
        .padding(.vertical, 2)
        .onAppear { text = start; focused = true }
    }

    private func apply() {
        guard let same = fixes.sameHeard(lineID: line.id, in: session, edited: text) else { onDone(); return }
        let all = same.count > 1 ? everywhere : true
        fixes.edit(lineID: line.id, in: session, to: text, everywhere: all, remember: keep && all)
        onDone()
    }
}

/// Above a finished meeting's transcript: how many words were fixed, and the ones waiting for the
/// user, one at a time (对 / 不对 / 改成…). Nothing once there was nothing to fix.
struct FixReviewBanner: View {
    @ObservedObject var fixes: LiveFixes
    let session: Session
    let onShow: (String) -> Void
    let onEdit: (TranscriptLine, String) -> Void

    var body: some View {
        let waiting = fixes.pending(in: session.id)
        let fixedCount = session.lines.reduce(0) { $0 + ($1.fixes ?? []).filter(\.applied).count }
        if let first = waiting.first {
            let c = Correction.label(first.fix)
            HStack(spacing: 10) {
                Button { onShow(first.line.id) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("改了 \(fixedCount) 处听错的词，\(waiting.count) 处等你确认").font(.fee(.body, strong: true))
                            .foregroundStyle(Palette.ink)
                        (Text("\(c.from) → \(c.to)？") + Text(" · \(TranscriptExport.clock(first.line.t))").foregroundStyle(Palette.tertiary))
                            .font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                SoftButton(L("对"), dark: true) { fixes.answer(first.fix, yes: true, in: session.id) }
                SoftButton(L("不对"), onGrey: true) { fixes.answer(first.fix, yes: false, in: session.id) }
                SoftButton(L("改成…"), onGrey: true) {
                    onEdit(first.line, Correction.apply((first.line.fixes ?? []).filter { $0.applied }, to: first.line.src).text)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .slipBackground(.attention)
            .onAppear { onShow(first.line.id) }
        } else if fixedCount > 0 {
            Text("改了 \(fixedCount) 处听错的词").font(.fee(.bodySecondary)).foregroundStyle(Palette.tertiary)
        }
    }
}

/// The last fix decision said back for a few seconds, with 撤销.
struct FixToast: View {
    @ObservedObject var fixes: LiveFixes

    var body: some View {
        if let t = fixes.toast {
            // 挂在纸边的牛皮纸吊牌（第四轮样稿 ⑥）
            KraftLabel {
                Text(t.text).lineLimit(1)
                if fixes.canUndo {
                    Button(L("撤销")) { fixes.undo() }
                        .buttonStyle(.plain).font(.fee(.bodySecondary, strong: true))
                        .foregroundStyle(Palette.link)
                }
            }
            .transition(.opacity)
            .id(t.id)
        }
    }
}
