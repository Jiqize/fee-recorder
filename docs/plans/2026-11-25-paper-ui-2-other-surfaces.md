# 纸上手记 · 第二部分：设置、引导、菜单栏面板、实时纪要窗 Implementation Plan

**Goal:** 把主窗口以外的四个界面按 DESIGN.md 的「材质分工」换上纸张风格：设置（中）、引导（完整）、菜单栏面板（低）、实时纪要窗（最低）。
**Architecture:** 先把各界面共用的控件（分段、按钮、输入框、卡片、标签）改成会看 `decor` 环境值的纸面版本，然后每个界面只在根视图设定装饰强度、换背景材质，再做少量布局调整。全部复用第一部分的 `Theme.swift`、`Paper.swift`、`Feebee.swift`。
**Tech Stack:** SwiftUI / AppKit（macOS 14.4+），SwiftPM + Command Line Tools，Swift Testing，Python 3。

**前置条件：** 第一部分（`2026-11-25-paper-ui-1-tokens-and-main-window.md`）全部任务已勾选，`scripts/check-design.py` 已在 `test.sh` 里运行。

## Global Constraints

- 第一部分的 Global Constraints 全部适用（逐条见该文件），以下几条在本部分最常用，重复写出：
  - 规范唯一来源：`DESIGN.md`；只改外观，不改交互和数据。
  - 实时纪要窗仍是 `.nonactivatingPanel`，`sharingType` 仍由「共享屏幕时让对方看到」决定（关 = `.none`，开 = `.readOnly`），换皮肤不改这两点。
  - 字幕条（`Overlay.swift`）不动；`CicadaLogo`、`BrandMark`、应用图标不动（品牌改名另定）。
  - 颜色只经 `Palette`，字体只经 `Font.fee` / `Font.icon`。
  - 改文案后跑 `python3 scripts/strings.py --write` 并补全 en/ja/ko；新文案不出现品牌名。
  - 减少动态效果打开时动画改成直接切换。
- 材质分工（照抄 DESIGN.md）：设置 = 横线纸 + 左侧索引贴，装饰「中」；引导 = 软木板 + 每步一张纸 / 拍立得，「完整」；菜单栏面板 = 素纸（无横线、无纹理），「低」；实时纪要窗 = 素纸、不透明，「最低：只换颜色和字体」，不加横线、纹理、旋转、角色，便利贴只保留颜色，不歪、不加胶带。
- 本部分结束时，`Color.white` / `.white` 在视图层只允许出现在：文字或图标压在深色底（`ink`、`accent`）上的前景色——统一改成 `Palette.paper`；拍立得白卡用 `Palette.polaroid`；其余表面改 `Palette.paper` 或 `Palette.paperShade`。豁免文件同第一部分。

## 文件结构

| 文件 | 职责 |
|---|---|
| Modify `Sources/Cicada/SettingsWindow.swift` | 共用控件 `SettingsCard` `Segments` `PillMenu` `SoftButton` `ShortcutField` 的纸面版；设置窗口布局 |
| Modify `Sources/Cicada/Paper.swift` | 新增 `UnderlineFieldStyle`、`PaperButtonStyle`、`IndexTabs` |
| Modify `Sources/Cicada/Onboarding.swift`、`OnboardingKey.swift` | 引导四步 + 收尾页 |
| Modify `Sources/Cicada/Views.swift`（`MenuPanelView` `:142` 起、`PanelAction` `:786`、`ChoiceRow` `:75`、`DisplayTile` `:703`） | 菜单栏面板 |
| Modify `Sources/Cicada/NotesWindow.swift`（`NotesWindowView` `:218` 起） | 实时纪要窗 |
| Modify 其余设置子页：`AISettings.swift` `LanguageSettings.swift` `WordListSettings.swift` `SpeakerLibraryView.swift` `DiagnosticsView.swift` `VoicePicker.swift` `SpeakTestView.swift` `MicUsersView.swift` `ImportViews.swift` `FolderExportViews.swift` `ShareViews.swift` `FixViews.swift` `AICheckView.swift` `UpdateViews.swift` | 只换表面色（`Color.white` 归类），靠共用控件变样 |
| Modify `scripts/check-design.py` | 增加 `Color.white` / `.white` 检查 |

---

## 2026-11-25 改版：按样稿做

第二部分样稿 `docs/design/mockups/other-surfaces.html` 已确认，DESIGN.md「其余界面」按样稿写好。**各任务需求以 DESIGN.md「其余界面」和样稿为准，下面原文冲突处作废**，主要变化：设置的分段控件改成红铅笔圈词、开关改成手画方框、栏目改成彩色索引贴；引导加步骤清单索引卡；菜单栏面板顶部换成菲比小头像、显示方式改成三张小卡。

### Task 1: 共用控件纸面化

**Files:**
- Modify: `Sources/Cicada/Paper.swift`、`Sources/Cicada/SettingsWindow.swift:35-165`
- Test: `Tests/CicadaTests/PaperTests.swift`

**Interfaces:**
- Consumes: `Decor`、`EnvironmentValues.decor`、`Palette.*`、`Font.fee`、`.paperShadow()`
- Produces:
  - `struct PaperButtonStyle: ButtonStyle { enum Kind { case primary, secondary, danger }; init(_ kind: Kind = .secondary) }`
  - `struct UnderlineFieldStyle: TextFieldStyle`
  - `struct IndexTabs<ID: Hashable>: View { init(_ items: [(ID, String)], selection: Binding<ID>, axis: Axis = .horizontal) }`
  - `Segments` 签名不变（`options:value:onChange`），外观按 `decor` 切换

**Requirements:**
- `PaperButtonStyle`：次要 = `paperShade` 底 + 1pt `hairline` 描边 + 向下 1pt 的硬阴影（`hairline`，无模糊）；主要 = `ink` 底 + `paper` 字；危险 = `paperShade` 底 + `error` 字；按下时硬阴影消失、内容下移 1pt；圆角 6；字体 `Font.fee(.bodySecondary, strong: true)`。
- `UnderlineFieldStyle`：无边框、无底色，下方 1pt `hairline`，聚焦时变 1.5pt `inkBlue`；占位文字 `tertiary`。
- `IndexTabs`：选中的贴片 `paper` 色、与下方纸面无分隔线；未选中的 `paperShade`、向内缩 2pt、文字 `secondary`；`axis: .vertical` 时贴片在左侧竖排（给设置用）。
- `Segments`：`decor >= .medium` 时画成 `IndexTabs` 样式；`decor <= .low` 时保持原来的分段外观，只换颜色（选中底 `paper`，轨道 `paperShade`）。
- `SoftButton` 内部改用 `PaperButtonStyle`，现有 `dark` / `onGrey` 参数分别映射到 `.primary` / `.secondary`，调用处不改。
- `SettingsCard`：`paper` 底 + `hairline` 描边 + `paperShadow()`，圆角 8；`decor == .minimal` 时去掉阴影。
- `PillMenu`、`ShortcutField`：底色 `Palette.ground` → `paperShade`（别名已指向，改成显式名字）。

**Test cases:**
- 全量单元测试 → 无回归
- `lsctl paperRender:/tmp/feebee-p2t1.png` 样张里新增一排控件（三种按钮的常态 / 按下、输入框常态 / 聚焦、横竖两种 `IndexTabs`、`Segments` 在 full 和 minimal 下）
- `python3 scripts/check-design.py` → 0

- [ ] **Step 1: 在 `paperRender` 样张里加控件排，先截一张（控件还是旧样式，作为失败对照）**
- [ ] **Step 2: 运行确认现状**
- [ ] **Step 3: 实现**
- [ ] **Step 4: 运行确认通过**：样张截图符合上述要求，全量测试通过
- [ ] **Step 5: Commit** `feat: give buttons, fields and tabs a paper look`

---

### Task 2: 设置窗口

**Files:**
- Modify: `Sources/Cicada/SettingsWindow.swift:413-799`（`SettingsView`，`page` `:428`、`sidebar` `:453`，`:424` 的底色）
- Modify: 文件结构表里列出的各设置子页（只换表面色）

**Interfaces:**
- Consumes: `RuledPaper`、`IndexTabs(axis: .vertical)`、`SettingsCard`、`.decor(.medium)`
- Produces: 无

**Requirements:**
- `SettingsView` 根视图 `.decor(.medium)`；整页是一张 `RuledPaper(holes: false, ruled: false)`（设置页多为输入框和可变高度卡片，按「对不齐就不画线」的规则用素纸，保留红页边线）。
- 左侧栏目导航换成竖排 `IndexTabs`，选中的贴片与纸面连成一体；栏目、顺序、`settings:<栏目>` 调试命令都不变。
- 栏目标题 `Font.fee(.title)`，小节标题用 `SectionTitle`（带 `WavyRule`）。
- 子页里作为表面的 `Color.white` 改 `Palette.paper`；卡片内嵌块改 `paperShade`。
- 开关、选择、快捷键录制等交互不变。

**Test cases:**
- 六个栏目各渲一张：`lsctl settingsRender:<overlay|language|speak|records|ai|diagnostics>=/tmp/feebee-p2t2-<栏目>.png` → 纸面、竖排索引贴、无截断
- 英文界面同样六张 → 无截断、无重叠
- 全量单元测试通过

- [ ] **Step 1: 先截六张基准图**
- [ ] **Step 2: 运行确认现状**
- [ ] **Step 3: 实现**
- [ ] **Step 4: 运行确认通过**：中英文共 12 张截图符合要求，发给用户
- [ ] **Step 5: Commit** `feat: restyle settings as a notebook with index tabs`

---

### Task 3: 引导

**Files:**
- Modify: `Sources/Cicada/Onboarding.swift`（`OnboardingView` `:350` 起、`SampleCallCard` `:242`、`OnboardingNotesTeaser` `:812`）、`Sources/Cicada/OnboardingKey.swift`

**Interfaces:**
- Consumes: `CorkBoard`、`RuledPaper`、`Polaroid`、`FeebeeView`、`FeebeeMood`、`PaperButtonStyle`、`.tilted`、`.decor(.full)`
- Produces: 无

**Requirements:**
- 根视图 `.decor(.full)`，整窗 `CorkBoard`，每一步的内容放在一张 `RuledPaper(ruled: false)` 上，`paperShadow()`，`tilted(-0.4)`。
- 步骤导航（`stepNames`）画成纸上方的 `IndexTabs`，当前步选中；步骤逻辑、跳转条件、`onboarding:<步骤>` 调试命令不变。
- 每步纸的右上角放一个 `Polaroid`（宽 120）装菲比：第 1 步（系统声音）`.idle`、第 2 步（示例会议）`.listening`、第 3 步（Ling key）`.writing`、第 4 步（说话）`.listening`、收尾页 `.done`；拍立得文字用对应 `mood.caption`。
- `SampleCallCard` 画成一张 `stickyYellow` 便利贴（`tapeGreen`），`OnboardingNotesTeaser` 画成一页横线纸缩样。
- `BrandMark` / `CicadaLogo` 保持原样（品牌改名另定）。
- 主按钮 `PaperButtonStyle(.primary)`，次要按钮 `.secondary`。

**Test cases:**
- `lsctl onboarding:1` … `onboarding:5`、`onboarding:3,skip`、`onboarding:4,ask`、`onboarding:4,setup` 各截一张（`winall <pid>` + `screencapture -l <窗口 ID>`）→ 软木板、纸、拍立得菲比、无截断
- 英文界面重复一遍
- `lsctl samplePlay` 示例会议照常播放，示例纪要出现
- 全量单元测试通过

- [ ] **Step 1: 截八张基准图**
- [ ] **Step 2: 运行确认现状**
- [ ] **Step 3: 实现**
- [ ] **Step 4: 运行确认通过**：中英文共 16 张截图符合要求，发给用户
- [ ] **Step 5: Commit** `feat: put onboarding steps on paper over a corkboard with Feebee`

---

### Task 4: 菜单栏面板

**Files:**
- Modify: `Sources/Cicada/Views.swift:75-815`（`ChoiceRow`、`MenuPanelView`、`PanelImportLine`、`MicButton`、`TalkKeyCap`、`DisplayTile`、`KeyCap`、`PanelAction`）、`Sources/Cicada/ListenPill.swift`（面板里用到的部分）

**Interfaces:**
- Consumes: `Palette.*`、`Font.fee`、`PaperButtonStyle`、`.decor(.low)`
- Produces: 无

**Requirements:**
- 根视图 `.decor(.low)`；底色 `paper`，无横线、无纹理、无旋转、无角色。
- 分组块 `paperShade` 底、`hairline` 分隔；当前选中项 `accentPale`；在听的点 `accent`。
- `DisplayTile` 的 `frameLine`（原 `Views.swift:744`，第一部分已归到 token）保持描边语义。
- 快捷键键帽 `KeyCap` / `TalkKeyCap`：`paperShade` 底 + `hairline` 描边 + 1pt 硬阴影，文字 `Font.fee(.caption)`。
- 所有按钮、开关、菜单行为不变。

**Test cases:**
- `lsctl panelRender:/tmp/feebee-p2t4-panel.png`（不在听）；`lsctl start:user` 后再渲 `/tmp/feebee-p2t4-panel-live.png` → 素纸、在听点为橙色、无截断
- 英文界面两张同样检查
- 全量单元测试通过

- [ ] **Step 1: 截基准图**
- [ ] **Step 2: 运行确认现状**
- [ ] **Step 3: 实现**
- [ ] **Step 4: 运行确认通过**：四张截图符合要求
- [ ] **Step 5: Commit** `feat: restyle the menu bar panel on plain paper`

---

### Task 5: 实时纪要窗

**Files:**
- Modify: `Sources/Cicada/NotesWindow.swift:218-1044`（`NotesWindowView`：`:296` 底色、`:401` `:461` `:481` `:566` `:600` `:635` `:731` `:774` `:790` 各处表面）

**Interfaces:**
- Consumes: `Palette.*`、`Font.fee`、`Decor.minimal`（默认值，无需显式设置；根视图仍显式写 `.decor(.minimal)` 防止上层改默认）
- Produces: 无

**Requirements:**
- 底色 `paper`，不透明；不加横线、纹理、旋转、胶带、角色、打孔、阴影。
- 待办便利贴只保留 `stickyPink` 底色，不歪、不加胶带、不卷角（`StickyNote` 在 minimal 下已如此）。
- 标签页（纪要 / 文字记录）用 `Segments` 的 minimal 外观；搜索框 `paperShade` 底。
- 「共享屏幕时让对方看到」徽标（`:436`，`ink` 胶囊）文字改 `Palette.paper`。
- `NotesWindow.swift:52` 的 `styleMask`（含 `.nonactivatingPanel`）和 `:68`、`:193` 的 `sharingType` 逻辑一字不改。
- 可读性：浮窗盖在白色、深色、花哨三种背景上都清楚（底不透明，靠 `paper` + 窗口阴影）。

**Test cases:**
- `NotesWindowTests` 全部通过
- `lsctl notesWindow` + `lsctl notesRender:/tmp/feebee-p2t5-notes.png` → 素纸、无装饰
- 可读性：`lsctl notesCapturable` 后分别把浮窗放在白色网页、深色终端、一张彩色壁纸上方，`screencapture -l` 截三张 → 文字都清楚；验完 `lsctl notesCapturable:off`
- 焦点：在 TextEdit 里输入文字时用 `lsctl notesWindow` 打开浮窗，继续输入 → 文字仍进 TextEdit（浮窗不抢焦点）
- 录屏不可见：`notesCapturable:off` 时 `screencapture` 全屏截图里看不到浮窗
- `git diff` 中 `NotesWindow.swift:40-200` 无改动

- [ ] **Step 1: 截基准图，记录焦点和录屏行为**
- [ ] **Step 2: 运行确认现状**
- [ ] **Step 3: 实现**
- [ ] **Step 4: 运行确认通过**：上述 cases 全部满足
- [ ] **Step 5: Commit** `feat: restyle the live notes window with paper colours and type`

---

### Task 6: `.white` 收尾与整体验收

**Files:**
- Modify: `scripts/check-design.py`
- Modify: 仍有 `Color.white` / `.white` 的视图文件
- Modify: `docs/plans/2026-11-25-paper-ui-2-other-surfaces.md`、`PROJECT.md`、`DESIGN.md`（只在验收中发现规范需改时，先问用户）

**Interfaces:**
- Consumes: 全部

**Requirements:**
- `check-design.py` 新增：豁免文件之外出现 `Color.white`、`.fill(.white`、`.background(.white`、`foregroundStyle(.white` → 退出码 1。
- 按 Global Constraints 的归类规则把剩余的 `.white` 全部替换。
- 逐条核对 DESIGN.md「验收标准」：五个界面换色换字；详情页对齐、时间戳在红线左、待办便利贴、宽窗页边栏；会议卡片选中态；纪要窗三种背景可读、不抢焦点、录屏不可见；文字对比度 ≥ 4.5（`ThemeTests` 已覆盖 token，界面上新组合的颜色逐个补进测试）；中英文无截断和重叠；`scripts/test.sh` 通过。

**Test cases:**
- `python3 scripts/check-design.py` → 退出码 0
- `scripts/test.sh -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays` → 全部通过，展示输出
- 中英文全部界面截图汇总成一张总览图发给用户

- [ ] **Step 1: 扩展检查脚本，运行确认失败（列出剩余 `.white`）**
- [ ] **Step 2: 替换**
- [ ] **Step 3: 运行确认检查通过、全量测试通过**
- [ ] **Step 4: 截图总览并逐条核对验收标准，结论写进备注**
- [ ] **Step 5: 更新 PROJECT.md，Commit** `docs: finish the paper redesign`
