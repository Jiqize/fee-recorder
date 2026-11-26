import AppKit
import SwiftUI

/// Onboarding step 3: connect a Ling key. Notes, Ling translation and Ming voices all need it, but it
/// comes after the sample video, once people have seen what the app does. Skipping is allowed: "先不接"
/// first shows what still works and what waits for a key (the notes window asks again later).
/// Ling is the whole path; "用不了 Ling？" opens another service as a way out, saying what it lacks.
struct OnboardingKeyStep: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ling: LingClient
    @ObservedObject var settings: AppSettings
    /// "先不接" was clicked: the card shows what skipping leaves out until 回去接上 or 好，先这样.
    @Binding var skipping: Bool
    @State private var draft = ""
    @State private var clipboardEmpty = false
    /// A pasted key that belongs elsewhere: what it is, and (for another service's key) where it fits.
    @State private var keyHint: (text: String, service: AIProvider.Kind?, key: String)?
    /// Showing another service instead of Ling: follows the setting, so a change made in Settings
    /// while this step is open (or a reused window) never leaves the Ling title over another service.
    private var other: Bool { settings.provider.id != .ling }

    private static let others: [AIProvider] = [.openrouter, .zenmux, .openai]

    static let platform = URL(string: "https://chat.ant-ling.com/platform/api")!

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if other && !skipping {
                VStack(alignment: .leading, spacing: 8) {
                    Text("用其他服务").font(.fee(.display)).foregroundStyle(Palette.ink)
                    Text("纪要和翻译都能用，模型已经选好。").font(.fee(.body)).foregroundStyle(Palette.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("接上 Ling，一个 key 用上全部功能").font(.fee(.display)).foregroundStyle(Palette.ink)
                    // 放不下（英文）就换行：橡皮章不折字
                    FlowLayout(spacing: 8) {
                        let items = Recognition.cloudOnly
                            ? [L("实时翻译字幕"), L("实时纪要"), L("自然的同传声音"), L("用你自己的声音")]
                            : [L("实时纪要"), L("更准的翻译"), L("自然的同传声音"), L("用你自己的声音")]
                        // 绿色小橡皮章
                        ForEach(items, id: \.self) { item in
                            StampLabel(text: "✓ " + item, color: Palette.ok, role: .bodySecondary)
                        }
                    }
                }
            }
            if case .ok = ling.keyState { connected } else if skipping { withoutKey } else if other { otherEntry } else { entry }
            if !skipping, !isConnected {
                HStack(spacing: 10) {
                    if other {
                        Button(L("‹ 还是用 Ling")) { switchTo(.ling) }.buttonStyle(.plain)
                            .font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                    } else {
                        StampLabel(text: L("Ling 每月赠送 ¥10 额度"), color: Palette.accentInk, role: .bodySecondary)
                        Text("约够 10–50 小时会议")
                            .font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                        Spacer()
                        if !Recognition.cloudOnly {
                            Button(L("用不了 Ling？")) { switchTo(.openrouter) }.buttonStyle(.plain)
                                .font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary).underline()
                        }
                    }
                }
            }
        }
    }

    private var isConnected: Bool { if case .ok = ling.keyState { true } else { false } }

    private func switchTo(_ p: AIProvider) {
        draft = ""
        clipboardEmpty = false
        keyHint = nil
        guard settings.aiProvider != p.id.rawValue else { return }
        settings.aiProvider = p.id.rawValue
        model.applyAIService()
    }

    // MARK: Another service

    private var otherEntry: some View {
        let p = settings.provider
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Segments(options: Self.others.map { ($0.id.rawValue, $0.name) }, value: p.id.rawValue) { id in
                    switchTo(AIProvider.named(id))
                }
                Spacer()
                if let site = p.site {
                    SoftButton(L("打开 \(p.name)"), icon: "arrow.up.right") { NSWorkspace.shared.open(site) }
                }
            }
            keyField(placeholder: L("粘贴 \(p.name) 的 key"))
            status
            HStack(spacing: 4) {
                Text("少了：").foregroundStyle(Palette.secondary)
                Text(p.hasVoices ? L("用你自己的声音") : L("自然的同传声音、你自己的声音")).fontWeight(.semibold).foregroundStyle(Palette.ink)
                Text("（只有 Ling 支持）").foregroundStyle(Palette.secondary)
            }
            .font(.fee(.bodySecondary))
            .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            .slipBackground(.note)
            .padding(.top, 6)
        }
        .padding(.top, 4)
        .card()
    }

    // MARK: Not connected yet

    private var entry: some View {
        // 样稿 round4 ⑧：索引卡，红铅笔编号 + 方框，最后一步在下划线上粘贴
        StepIndexCard(title: L("接上 Ling 写纪要")) {
            HStack(alignment: .top, spacing: 10) {
                PencilNumber(n: 1).frame(height: 22)
                PaperCheck(mark: .open).frame(height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("在 Ling 开放平台创建 key").font(.fee(.body, strong: true)).foregroundStyle(Palette.ink)
                        .frame(minHeight: 22)
                    Text("国内直接注册，不用代理；登录后点“创建令牌”").font(.fee(.bodySecondary)).foregroundStyle(Palette.tertiary)
                }
                Spacer()
                SoftButton(L("打开 Ling 开放平台"), icon: "arrow.up.right") { NSWorkspace.shared.open(Self.platform) }
            }
            .padding(.top, 10)
            HStack(alignment: .top, spacing: 10) {
                PencilNumber(n: 2).frame(height: 22)
                PaperCheck(mark: .open).frame(height: 22)
                VStack(alignment: .leading, spacing: 10) {
                    Text("复制 sk- 开头的 key，回来粘贴").font(.fee(.body, strong: true)).foregroundStyle(Palette.ink)
                        .frame(minHeight: 22)
                    keyField(placeholder: "sk-…")
                    status
                }
            }
            .padding(.top, 16)
        }
    }

    @ViewBuilder private var status: some View {
        if let hint = keyHint {
            HStack(spacing: 8) {
                line(Palette.error, hint.text, Palette.accentInk)
                Spacer()
                if let other = hint.service {
                    SoftButton(L("改用 \(AIProvider.named(other.rawValue).name)"), dark: true) {
                        let k = hint.key
                        keyHint = nil
                        model.switchService(other, key: k)
                    }
                }
            }
        } else if ling.hasKey, ling.aiCheck.running || ling.aiCheck.failure != nil {
            // Where it broke and the one thing that fixes it, as in the settings.
            AICheckSteps(model: model, ling: ling) { draft = "" }
        } else {
            switch ling.keyState {
            case .checking, .unchecked:
                line(Palette.accent, L("正在检查…"), Palette.secondary)
            default: idleStatus
            }
        }
    }

    @ViewBuilder private var idleStatus: some View {
        switch ling.keyState {
        case .invalid:
            line(Palette.error, L("这个 key 无效，请检查是否复制完整，或重新创建一个"), Palette.accentInk)
        case .unreachable(let why):
            line(Palette.error, why, Palette.accentInk)
        default:
            if clipboardEmpty {
                line(Palette.error, other ? L("剪贴板里没有 sk- 开头的 key，请先去 \(settings.provider.name) 复制。")
                                          : L("剪贴板里没有 sk- 开头的 key，先在 Ling 开放平台复制。"), Palette.accentInk)
            } else {
                Label(L("只保存在这台 Mac 上，只发给 \(settings.provider.name)"), systemImage: "lock")
                    .font(.fee(.bodySecondary)).foregroundStyle(Palette.tertiary)
            }
        }
    }

    // MARK: Connected

    private var connected: some View {
        StepIndexCard(title: L("已连接"), note: connectedNote, mark: .done,
                      accessory: ling.key.map { AnyView(Text(AIKey.masked($0)).font(.fee(.meta)).foregroundStyle(Palette.secondary)) }) {
            Text("现在可以用了").font(.fee(.bodySecondary, strong: true)).foregroundStyle(Palette.secondary)
                .frame(height: 22).padding(.top, 10)
            HStack(alignment: .top, spacing: 10) {
                if Recognition.cloudOnly {
                    benefit(L("实时翻译字幕"), L("识别和翻译一步完成"))
                } else {
                    benefit(L("更准的翻译"), L("人名、术语前后一致"))
                }
                benefit(L("实时纪要"), L("会中每 45 秒更新"))
                if ling.speaks { benefit(L("自然人声"), L("同传约 2 秒出声")) }
            }
            Text("开会时，纪要会跟着字幕一起更新。").font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                .frame(minHeight: 22).padding(.top, 8)
        }
    }

    private var connectedNote: String? {
        guard case .ok(let s) = ling.keyState else { return nil }
        return L("\(settings.textModel) · 响应约 \(String(format: "%.1f", s)) 秒")
    }

    // MARK: Skipping

    /// Honest about both sides, so skipping is a choice rather than a dead end.
    private var withoutKey: some View {
        VStack(alignment: .leading, spacing: 16) {
            if Recognition.cloudOnly {
                Text("Intel 版 Mac 需要接上 Ling 才能识别语音").font(.fee(.section)).foregroundStyle(Palette.ink)
                HStack(alignment: .top, spacing: 10) {
                    column(L("现在可用"), [L("查看以往的会议记录")],
                           head: Palette.secondary, fill: Palette.ground, check: true)
                    column(L("接上 Ling 才有"), [L("实时翻译字幕和双语记录"), L("实时纪要和会后总结"), L("同声传译")],
                           head: Palette.accentInk, fill: Palette.accentPale, check: false)
                }
                Text("可以先进入应用，开会前在设置 › AI 服务里填上 Ling key 即可。")
                    .font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
            } else {
                Text("先不接也行，基础功能照常能用").font(.fee(.section)).foregroundStyle(Palette.ink)
                HStack(alignment: .top, spacing: 10) {
                    column(L("现在可用"), [L("实时翻译字幕"), L("双语文字记录"), L("同声传译（系统语音）")],
                           head: Palette.secondary, fill: Palette.ground, check: true)
                    column(L("接上 Ling 才有"), [L("实时纪要和会后总结"), L("人名、术语前后一致"), L("自然人声，约 2 秒出声")],
                           head: Palette.accentInk, fill: Palette.accentPale, check: false)
                }
                Text("随时可在纪要窗口或设置里接上，开完的会也能补出纪要。")
                    .font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
            }
        }
        .padding(.top, 4)
        .card()
    }

    private func column(_ title: String, _ items: [String], head: Color, fill: Color, check: Bool) -> some View {
        // 不再垫色块：能用的打勾，要接上才有的是空方框（`fill` 留着，和上游的写法对得上）
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.fee(.bodySecondary, strong: true)).foregroundStyle(head)
            ForEach(items, id: \.self) { item in
                HStack(spacing: 6) {
                    PaperCheck(mark: check ? .done : .open, size: 12)
                    Text(item).font(.fee(.body)).foregroundStyle(Palette.ink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private func keyField(placeholder: String) -> some View {
        // 只有一条下划线的输入框，右边一块墨色纸方块
        HStack(spacing: 10) {
            SecureField(placeholder, text: $draft)
                .textFieldStyle(.paper).font(.fee(.meta))
                .onSubmit { save(draft) }
            SoftButton(draft.isEmpty ? L("粘贴并检查") : L("保存并检查"), dark: true, icon: "doc.on.clipboard", action: pasteAndCheck)
        }
    }

    // MARK: Pieces

    private func line(_ dot: Color, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(text).font(.fee(.bodySecondary)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func benefit(_ title: String, _ detail: String) -> some View {
        // 打了勾的一项，直接写在卡上
        HStack(alignment: .top, spacing: 6) {
            PaperCheck(mark: .done, size: 12).frame(height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.fee(.body, strong: true)).foregroundStyle(Palette.ink).frame(minHeight: 22)
                Text(detail).font(.fee(.bodySecondary)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Reads the clipboard only when the button is clicked (a deliberate paste, so macOS's paste
    /// privacy prompt, if any, makes sense to the user); a typed key is checked as typed.
    private func pasteAndCheck() {
        if !draft.isEmpty { save(draft); return }
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard text.hasPrefix("sk-"), !text.contains(where: \.isWhitespace) else { clipboardEmpty = true; return }
        save(text)
    }

    private func save(_ raw: String) {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        clipboardEmpty = false
        keyHint = nil
        // The prefix says whose key it is (AISettingsView.save does the same).
        if let owner = AICheck.owner(ofKey: k) {
            if owner.management {
                keyHint = (L("这是 ZenMux 的管理 key，不能用来调用模型。请粘贴 sk-payg 开头的 key。"), nil, "")
                return
            }
            if owner.service != settings.provider.id {
                keyHint = (L("这是 \(AIProvider.named(owner.service.rawValue).name) 的 key。"), owner.service, k)
                return
            }
        }
        draft = ""
        Task { await ling.setKey(k) }
    }
}

private extension View {
    /// 没有标题格的白卡（另选服务、先不接）：方角，顶上胶带。
    func card() -> some View { StepIndexCard { self } }
}
