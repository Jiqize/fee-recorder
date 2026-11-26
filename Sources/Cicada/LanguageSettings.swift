import SwiftUI

/// Settings › 语言: every language choice in one place — what the other side speaks, whether and
/// into what it is translated, what the notes are written in, and the speak-back pair — under a
/// line that reads the whole route.
struct LanguageSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: PaperMetrics.pitch) {
            route
            group(L("听对方")) {
                SettingsRow(title: L("对方说的语言"), detail: heardDetail) {
                    PillMenu(value: heardValue, options: [("auto", L("自动识别"))] + sourceLanguages.map { ($0.locale, $0.name) }) {
                        model.sourceSelection = $0
                    }
                }
                SettingsRow(title: L("字幕"), detail: L("只看原文时不翻译，也不用 Ling 额度")) {
                    Segments(options: subtitleOptions, value: settings.subtitles) { model.setSubtitles($0) }
                }
                SettingsRow(title: L("翻译成"), detail: targetDetail, divider: false) {
                    PillMenu(value: settings.target == "system" ? L("跟随系统（\(targetName(model.listen.resolvedTarget))）")
                                                                : targetName(settings.target),
                             options: [("system", L("跟随系统"))] + targetLanguages.map { ($0.code, $0.name) }) {
                        model.targetSelection = $0
                    }
                }
            }
            group(L("纪要")) {
                SettingsRow(title: L("纪要语言"), detail: L("实时纪要和完整版同一种语言"), divider: false) {
                    Segments(options: [("mine", L("我的语言 · \(targetName(settings.myLanguage))")), ("source", sourceTitle)],
                             value: settings.notesLanguage) { model.setNotesLanguage($0) }
                }
            }
            group(L("同声传译")) {
                SettingsRow(title: L("我说"), detail: settings.speakEnabled ? nil : L("同声传译还没打开")) {
                    PillMenu(value: settings.speakFromLang.name, options: sourceLanguages.map { ($0.locale, $0.name) }) {
                        settings.speakFrom = $0
                        model.speakFromChanged()
                    }
                }
                SettingsRow(title: L("对方听到"), detail: L("跟随对方时，对方说什么语言就翻成什么"), divider: false) {
                    PillMenu(value: settings.speakTo == "room" ? L("跟随对方（\(targetName(model.speak.targetCode))）") : targetName(settings.speakTo),
                             options: [("room", L("跟随对方"))] + targetLanguages.map { ($0.code, $0.name) }) {
                        settings.speakTo = $0
                        model.objectWillChange.send()
                    }
                }
            }
        }
    }

    // MARK: The route

    /// 对方说 English → 字幕 简体中文 · 纪要 简体中文 / 你说 中文 → 对方听到 English
    private var route: some View {
        VStack(alignment: .leading, spacing: 10) {
            // English runs wider than the card: the notes get a line of their own.
            if uiIsChinese {
                HStack(spacing: 8) {
                    heardRoute
                    Text("·").foregroundStyle(Palette.tertiary)
                    notesRoute
                }
            } else {
                HStack(spacing: 8) { heardRoute }
                HStack(spacing: 8) { label(""); notesRoute }
            }
            HStack(spacing: 8) {
                label(L("你说"))
                chip(settings.speakFromLang.name, accent: false)
                arrow
                Text("对方听到").font(.fee(.body)).foregroundStyle(Palette.ink)
                chip(targetName(model.speak.targetCode), accent: false)
                if !settings.speakEnabled {
                    Text("（同声传译未开）").font(.fee(.bodySecondary)).foregroundStyle(Palette.tertiary)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 整条路线写在一张黄便签上（原来是墨色圆角卡）
        .slipBackground(.note)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var heardRoute: some View {
        label(L("对方说"))
        chip(heardNow, accent: false)
        arrow
        Text("字幕").font(.fee(.body)).foregroundStyle(Palette.ink)
        chip(settings.subtitles == "original" ? L("原文") : targetName(model.listen.resolvedTarget), accent: true)
    }

    @ViewBuilder private var notesRoute: some View {
        Text("纪要").font(.fee(.body)).foregroundStyle(Palette.ink)
        chip(notesNow, accent: true)
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.fee(.body)).foregroundStyle(Palette.secondary).frame(width: uiIsChinese ? 46 : 64, alignment: .leading)
    }

    private func chip(_ t: String, accent: Bool) -> some View {
        // 小橡皮章：字幕、纪要用的语言是红章
        StampLabel(text: t, color: accent ? Palette.accentInk : Palette.ink, role: .body)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right").font(.icon(11, weight: .bold)).foregroundStyle(Palette.link)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        // 小节标题 + 波浪线，下面的设置项直接写在纸上（同其他栏目）
        VStack(alignment: .leading, spacing: 0) {
            NotebookHeading(title: title)
            SettingsCard { content() }
        }
    }

    // MARK: Words

    private var heardValue: String {
        if case .fixed(let l) = settings.sourceMode { return l.name }
        return L("自动识别")
    }

    private var heardNow: String {
        if case .fixed(let l) = settings.sourceMode { return l.name }
        return model.listen.activeLang?.name ?? L("自动识别")
    }

    private var heardDetail: String {
        if case .fixed = settings.sourceMode { return L("只按这种语言识别") }
        let fallback = Recognition.cloudOnly ? L("说话后自动听出是哪种语言") : L("从已安装的语音模型里挑最有把握的")
        return model.listen.activeLang.map { L("现在听出是 \($0.name)") } ?? fallback
    }

    private var targetDetail: String {
        settings.target == "system" ? L("对方说的正是系统语言时，翻成系统里的另一种") : L("对方说的就是这种语言时不翻译")
    }

    private var sourceTitle: String {
        model.listen.activeLang.map { L("会议原文 · \($0.name)") } ?? L("会议原文")
    }

    private var notesNow: String {
        if settings.notesLanguage == "source" { return model.listen.activeLang?.name ?? L("会议原文") }
        return targetName(settings.myLanguage)
    }
}
