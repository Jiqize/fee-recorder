# 纸上手记 · 第一部分：Token 与主窗口 Implementation Plan

**Goal:** 把 Mac 版的颜色和字体整体换成 DESIGN.md 的纸张风格，并把主窗口（会议记录）做成「软木板 + 横线笔记本 + 页边栏菲比」的完整样子。
**Architecture:** 先在新文件 `Theme.swift` 里换颜色 token 和字体 token，用一个能反复运行的脚本把全应用约 600 处 `.system(size:)` 换成字体 token，让整个应用一次变样。装饰（横线纸、胶带、图钉、便利贴、拍立得、波浪线）集中在 `Paper.swift`，由环境值 `decor` 控制强度，浮窗默认最弱。最后主窗口逐块组合这些组件。
**Tech Stack:** SwiftUI / AppKit（macOS 14.4+），SwiftPM + Command Line Tools，Swift Testing，Python 3（迁移与检查脚本），CoreText 注册字体。

第二部分（设置、引导、菜单栏面板、实时纪要窗）见 `2026-11-25-paper-ui-2-other-surfaces.md`，在本部分全部完成后执行。

## Global Constraints

- 规范唯一来源：`DESIGN.md`（已含下方修订）。
- 只改外观，不改交互和数据；不改 `NoteItem`、提示词、记录格式；不改 bundle id。
- 实时纪要窗仍是不抢焦点、`sharingType = .none` 的 panel。
- 字幕条（`Overlay.swift`）一行不动；`DockIcon.swift`、`DMGBackground.swift`、`AboutPanel.swift`、`Sources/CicadaIcon`、`CicadaLogo` 本阶段不动（品牌改名另定）。
- 强调色 `accent` 仍是 `#E8552B`，只表示「正在进行」，不用于文字。
- 字体：`LXGWWenKaiLite-Regular`、`LXGWWenKaiLite-Medium`（PostScript 名，已从 TTF 读出），回退 PingFang SC；数字用 SF Mono（`.monospaced` 设计），回退 Menlo。
- 横线间距 24pt；红页边线距纸左 64pt、1pt；打孔 3 个、直径 14pt；纸阴影 `y 2 / blur 8 / 12% #3A2A18`；纸纹不透明度 ≤ 4%。
- 最小字号 11；文字对比度以 `paper` 为底 ≥ 4.5:1。
- UI 文案中文是本地化键，用 `L()`；改文案后跑 `python3 scripts/strings.py --write` 并补全 en/ja/ko。
- 新增 UI 文案不出现「知了」「Cicada」「菲比」「Feebee」（品牌改名未定）。
- 系统「减少动态效果」打开时，所有动画改成直接切换。
- 提交信息：英文 Conventional Commits，结尾带 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`；不推送。
- 测试命令（本机）：`scripts/test.sh -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays`
- 开发版截图（无需录屏权限）：`scripts/build.sh && open build/Cicada.app`，然后 `tools/lsctl --timeout 10 <命令>`（`lsctl` 用 `swiftc -O tools/lsctl.swift -o tools/lsctl` 编译）。

## 对 DESIGN.md 的修订（2026-11-25 用户已确认，已写进 DESIGN.md）

1. **待办只有 ☐ 一种状态**：`NoteItem` 没有「完成 / 进行中」字段，☑、▸ 和打勾动画需要改数据，移到下一阶段「待办大改」。本阶段便利贴上的待办只画 ☐。
2. **新增字体 token `label`（12 / 文楷 Regular）**：原来 10–11pt 的中文小标签有 140+ 处。`caption` / `meta` 是等宽字体，SF Mono 没有中文字形，中文会落到苹方。所以等宽 token 只用于数字、时间、快捷键，中文小字用 `label`。
3. **加粗统一为 Medium**：文楷精简版只有 Regular 和 Medium。原来的 semibold / bold / heavy 都映射到同一 token 的 Medium（`strong: true`）。
4. **SF Symbols 图标保留系统字体**：图标尺寸走 `Font.icon(_:weight:)`，不算违反「不写 `.system(size:)`」。
5. **在听指示用现有 `BreathingDot`**（`ListenPill.swift`），DESIGN.md 里名字写对了，无需改；`LiveDot`（`NotesViews.swift`）保持原用途。

## 文件结构

| 文件 | 职责 |
|---|---|
| Create `Sources/Cicada/Theme.swift` | `Palette`（从 `Views.swift` 挪来并换值）、`Contrast`、`TypeRole` 与 `Font.fee` / `Font.icon`、`FeeFonts.register` |
| Create `Sources/Cicada/Paper.swift` | 装饰组件与 `Decor` 环境值、`PaperMetrics`；界面只组合它们 |
| Create `Sources/Cicada/Feebee.swift` | `FeebeeMood`（状态推导）、`FeebeeView`（加载插画） |
| Create `scripts/restyle-fonts.py` | 可重复运行的字号迁移脚本（合并上游后再跑一次） |
| Create `scripts/check-design.py` | 字面量检查：视图层不得有 `.system(size:` 和 `Color(red:` |
| Create `Resources/illustrations/feebee-{idle,listening,writing,done,error}{,@2x}.png` | 160 / 320px 插画 |
| Modify `Sources/Cicada/Views.swift` | 删除 `Palette`（挪走）；`MainWindowView` 主窗口外框、侧栏、详情页 |
| Modify `Sources/Cicada/NotesViews.swift` | `DocumentNotesView` 纸面版；`SectionTitle`、`Tag`、`TermChips`、`FishboneView` 支持 `decor` |
| Modify `Sources/Cicada/SpeakerViews.swift:8-9` | 说话人颜色改用 `Palette.speakers` |
| Modify `Sources/Cicada/AppModel.swift` | 启动时注册字体；调试渲染的白底改 `Palette.paper` |
| Modify `scripts/build.sh` | 拷贝 `Resources/fonts/*.ttf`、`OFL.txt`、`Resources/illustrations/` |
| Modify `scripts/test.sh` | 在 `check-agents.py` 后跑 `check-design.py` |
| Modify 全部视图文件 | 由 `restyle-fonts.py` 批量改字号；散落的 `Color(red:)` 手工归到 token |
| Test `Tests/CicadaTests/ThemeTests.swift` | 色值、对比度、字体规格、行距 |
| Test `Tests/CicadaTests/PaperTests.swift` | `PaperMetrics` 断点与对齐计算、`Decor` 规则 |
| Test `Tests/CicadaTests/FeebeeTests.swift` | `FeebeeMood.of` 映射 |

---

### Task 1: 颜色 token

**Files:**
- Create: `Sources/Cicada/Theme.swift`
- Modify: `Sources/Cicada/Views.swift:4-32`（删除 `Palette`）、`Views.swift:44`、`:744`、`:949-950`
- Modify: `Sources/Cicada/SpeakerViews.swift:8-9`、`NotesViews.swift:1358`、`:1404-1405`，以及 `DiagnosticsView` `Onboarding` `ListenPill` `SettingsWindow` `AICheckView` `SpeakerLibraryView` `FixViews` 里的 `Color(red:)`
- Test: `Tests/CicadaTests/ThemeTests.swift`

**Interfaces:**
- Produces:
  - `enum Palette` 的静态 `Color`：`paper paperShade rule margin hairline grid cork corkDeep kraft hole ink body secondary tertiary placeholder inkBlue link accent accentInk accentPale accentWash mark ok okPale error errorPale warn warnPale stickyPink stickyYellow stickyGreen tapeKraft tapePink tapeGreen polaroid paperShadow`
  - 兼容别名（保留，减少与上游冲突）：`Palette.ground = paper`、`line = hairline`、`fill = paperShade`、`raised = paperShade`
  - `Palette.speakers: [Color]`（4 色）、`Palette.you: Color`（= `inkBlue`）
  - `Palette.hex(_ rgb: UInt32, opacity: Double = 1) -> Color`
  - `enum Contrast { static func ratio(_ a: Color, _ b: Color) -> Double }`（WCAG 2.x 相对亮度公式，sRGB）

**Requirements:**
- 色值逐项照抄 DESIGN.md「颜色」各表；`polaroid = #FFFFFF`；`paperShadow = #3A2A18 @ 12%`；`tapeKraft = #D9C79B @ 70%`、`tapePink = #F2B8C6 @ 70%`、`tapeGreen = #B9D9A8 @ 70%`。
- `Palette.speakers = [#17685F, #5B45A6, #9C3468, #7E5300]`，替换 `SpeakerViews.swift` 里的 `inks`。
- `MainWindowView.hairline` → `Palette.hairline`；`MainWindowView.listTint` → `Palette.paperShade`；`StatusLine.waitingDot` 保留 `#C98A00`（6pt 圆点用，非文字），改写为 `Palette.hex(0xC98A00)`。
- 其他散落的 `Color(red:)` 按「最接近用途」归到上表 token；找不到对应的，停下列出给用户，不擅自加 token。
- `Overlay.swift`、`DockIcon.swift`、`DMGBackground.swift`、`AboutPanel.swift`、`Onboarding.swift:163`（图标 NSColor）不动。
- 主窗口暂时仍是白底，本任务只换 token 值；视觉上应已是暖色纸调。

**Test cases:**
- `Palette.paper` 的 sRGB 分量 → `0xFA/255, 0xF7/255, 0xEF/255`（容差 0.002），`ink`、`accent`、`inkBlue`、`link`、`cork` 同样逐个核对
- `Contrast.ratio(.black, .white)` → `21.0 ± 0.01`
- 每个文字 token（`ink body secondary tertiary inkBlue link accentInk ok error warn` 与 `speakers` 四色）对 `paper` → `≥ 4.5`
- `ink`、`body` 对 `stickyPink`、`stickyYellow`、`stickyGreen` → `≥ 4.5`
- `Palette.speakers.count` → `4`

- [x] **Step 1: 按上述 cases 写 `ThemeTests.swift`**
- [x] **Step 2: 运行确认失败**：`scripts/test.sh -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays --filter ThemeTests` → 编译失败（`Contrast` 未定义）
- [x] **Step 3: 建 `Theme.swift`，挪 `Palette` 并换值，清理散落色值**
- [x] **Step 4: 运行确认通过**：同上命令 → `ThemeTests` 全部通过；再跑全量测试无回归；`scripts/build.sh` 成功，`lsctl open` + `lsctl mainRender:/tmp/feebee-t1-main.png` 看到暖色
- [x] **Step 5: Commit** `refactor: move Palette into Theme.swift with the paper colours`
  - 进展：Palette 挪到 Theme.swift 并换成纸色，旧名保留为别名；`Color(white:)` 也一并归到 token；引导里模拟深色会议软件的插图色另设 `mock*` 五个 token。369 个测试通过，开发版侧栏已是暖纸色。

---

### Task 2: 字体 token 与注册

**Files:**
- Modify: `Sources/Cicada/Theme.swift`
- Modify: `Sources/Cicada/AppModel.swift`（`applicationDidFinishLaunching` 附近，约 `:2643` 设置 `.aqua` 处）
- Modify: `scripts/build.sh:19-28`
- Test: `Tests/CicadaTests/ThemeTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `Theme.swift`
- Produces:
  - `enum TypeRole: CaseIterable { case display, title, section, body, bodySecondary, label, meta, caption }`
  - `TypeRole.size: CGFloat`、`TypeRole.medium: Bool`、`TypeRole.mono: Bool`
  - `extension Font { static func fee(_ role: TypeRole, strong: Bool = false) -> Font; static func icon(_ size: CGFloat, weight: Font.Weight = .regular) -> Font }`
  - `enum FeeFonts { static func register(in bundle: Bundle = .main) -> Bool; static var registered: Bool { get }; static let regular = "LXGWWenKaiLite-Regular"; static let medium = "LXGWWenKaiLite-Medium" }`
  - `FeeFonts.lineHeight(_ role: TypeRole) -> CGFloat`（用 `NSLayoutManager.defaultLineHeight(for:)` 量实际字体；未注册时量回退字体）

**Requirements:**
- 规格：`display` 26 Medium、`title` 18 Medium、`section` 15 Medium、`body` 14 Regular、`bodySecondary` 13 Regular、`label` 12 Regular、`meta` 12 Mono、`caption` 11 Mono。
- `strong: true` 时文楷 token 用 Medium，等宽 token 用 `.semibold`。
- 文楷 token 用 `Font.custom(<PostScript 名>, fixedSize:)`；`FeeFonts.registered == false` 时返回 `.system(size:weight:)`（苹方）。
- 等宽 token：`.system(size:weight:design: .monospaced)`。
- `register` 用 `CTFontManagerRegisterFontsForURL(_, .process, _)` 注册 bundle 里 `fonts/` 下两个 ttf；失败写 `debugLog("fonts: register failed …")` 并返回 false，不弹窗。
- 启动时在设置 `.aqua` 之前调用一次。
- `build.sh` 把 `Resources/fonts/*.ttf` 和 `OFL.txt` 拷到 `Contents/Resources/fonts/`。
- 日志写一行 `fonts: registered=<true|false>`。

**Test cases:**
- `TypeRole.body.size` → `14`，`.medium` → `false`，`.mono` → `false`；8 个 role 逐个核对规格表
- `TypeRole.allCases.map(\.size).min()` → `11`
- `FeeFonts.register(in: <不含字体的 bundle>)` → `false`，且不崩溃
- 测试进程里 `FeeFonts.lineHeight(.body)` → `> 14` 且 `< 24`

- [ ] **Step 1: 按上述 cases 扩充 `ThemeTests.swift`**
- [ ] **Step 2: 运行确认失败**：`… --filter ThemeTests` → `TypeRole` 未定义
- [ ] **Step 3: 实现 token、注册与 build.sh 拷贝**
- [ ] **Step 4: 运行确认通过**：`ThemeTests` 通过；`scripts/build.sh && ls build/Cicada.app/Contents/Resources/fonts` 列出两个 ttf 和 OFL.txt；启动后 `grep "fonts: registered=true" /tmp/livesubs-dev-debug.log` 命中
- [ ] **Step 5: Commit** `feat: bundle LXGW WenKai Lite and add type tokens`

---

### Task 3: 字号批量迁移与字面量检查

**Files:**
- Create: `scripts/restyle-fonts.py`、`scripts/check-design.py`
- Modify: `scripts/test.sh`（`check-agents.py` 之后一行）
- Modify: `Sources/Cicada/*.swift`（脚本改写；`Overlay.swift`、`DMGBackground.swift`、`DockIcon.swift`、`AboutPanel.swift` 除外）
- Modify: `CLAUDE.md`「已知风险 › 上游同步」加一句：合并上游后先跑 `python3 scripts/restyle-fonts.py`

**Interfaces:**
- Consumes: `Font.fee(_:strong:)`、`Font.icon(_:weight:)`
- Produces:
  - `python3 scripts/restyle-fonts.py [--check]`：改写文件；`--check` 只报告不写，有待改项时退出码 1
  - `python3 scripts/check-design.py`：在豁免文件之外发现 `.system(size:` 或 `Color(red:` 时打印 `file:line` 并退出码 1

**Requirements:**
- 映射表（按顺序匹配，第一条命中即用）：
  | 原写法 | 新写法 |
  |---|---|
  | 同一行有 `Image(systemName:` | `.icon(<原字号>, weight: <原字重>)` |
  | `design: .monospaced`，或紧跟 `.monospacedDigit()` | 字号 ≥ 12 → `.fee(.meta)`，否则 `.fee(.caption)`；原字重 ≥ medium 加 `strong: true` |
  | 字号 ≥ 24 | `.fee(.display)` |
  | 17–23 且字重 ≥ semibold | `.fee(.title)` |
  | 15–17 且字重 < medium | `.fee(.body)` |
  | 15–16 且字重 ≥ medium | `.fee(.section)` |
  | 13–14 | `.fee(.body)` |
  | 12 | `.fee(.bodySecondary)` |
  | 10–11 | `.fee(.label)` |
  | 8–9 | `.fee(.caption)` |
  | 上面任一行原字重为 medium / semibold / bold / heavy（`.icon` 除外） | 加 `strong: true` |
- 字号或字重是变量 / 三元表达式的（当前 6 处，如 `compact ? 13 : 14`、`weight: on ? .semibold : .regular`）脚本不改，打印出来手工改成 `.fee(cond ? .x : .y, strong: …)`。
- 脚本幂等：对已迁移的文件再跑一次，不产生任何改动。
- 豁免文件：`Overlay.swift`、`DMGBackground.swift`、`DockIcon.swift`、`AboutPanel.swift`、`Theme.swift`（定义处）。
- `scripts/test.sh` 跑 `check-design.py`，不通过则测试失败。

**Test cases:**
- `python3 scripts/restyle-fonts.py --check` 在迁移前 → 退出码 1，列出约 600 处
- 迁移后 `python3 scripts/restyle-fonts.py --check` → 退出码 0
- 迁移后再跑 `restyle-fonts.py` → `git diff --stat` 无变化
- `grep -n "system(size:" Sources/Cicada/*.swift`（排除豁免文件）→ 无输出
- `python3 scripts/check-design.py` → 退出码 0；手工在 `Views.swift` 临时加一行 `Color(red: 0, green: 0, blue: 0)` → 退出码 1 并打印该行

- [ ] **Step 1: 写两个脚本，先跑 `--check` 确认报告约 600 处、退出码 1**
- [ ] **Step 2: 跑 `check-design.py` 确认失败（列出 `.system(size:`）**
- [ ] **Step 3: 跑 `restyle-fonts.py`，手工改完打印出的动态写法；`test.sh` 接上检查**
- [ ] **Step 4: 运行确认通过**：`python3 scripts/check-design.py` → 0；全量测试通过；`scripts/build.sh` 成功；`lsctl mainRender:/tmp/feebee-t3-main.png`、`lsctl settingsRender:ai=/tmp/feebee-t3-ai.png`、`lsctl panelRender:/tmp/feebee-t3-panel.png` 截图看文楷生效、无明显截断（截断记下，在对应界面任务修）
- [ ] **Step 5: Commit** `refactor: replace literal font sizes with type tokens`（脚本与生成的改动同一个提交，方便以后对照重跑）

---

### Task 4: 纸张与装饰组件

**Files:**
- Create: `Sources/Cicada/Paper.swift`
- Test: `Tests/CicadaTests/PaperTests.swift`

**Interfaces:**
- Consumes: `Palette.*`、`Font.fee`、`FeeFonts.lineHeight`
- Produces:
  - `enum Decor: Int, Comparable { case minimal, low, medium, full }`；`EnvironmentValues.decor: Decor`（默认 `.minimal`）；`View.decor(_ level: Decor) -> some View`
  - `enum PaperMetrics { static let pitch: CGFloat = 24; static let marginX: CGFloat = 64; static let holeDiameter: CGFloat = 14; static let holeCount = 3; static let corkInset: CGFloat = 16; static let sidebarWidth: CGFloat = 232; static let marginColumnWidth: CGFloat = 220; static let marginColumnBreakpoint: CGFloat = 1000; static let gridPitch: CGFloat = 12 }`
  - `PaperMetrics.lineSpacing(lineHeight: CGFloat, pitch: CGFloat = 24) -> CGFloat`、`PaperMetrics.lineSpacing(_ role: TypeRole) -> CGFloat`
  - `PaperMetrics.snap(_ height: CGFloat) -> CGFloat`（向上取到 24 的整数倍）
  - `PaperMetrics.showsMarginColumn(windowWidth: CGFloat) -> Bool`
  - `View.ruledText(_ role: TypeRole) -> some View`（字体 + 对齐行距）
  - 视图：`RuledPaper(holes: Bool = false, ruled: Bool = true)`、`CorkBoard()`、`GridPaper()`、`Tape(_ style: TapeStyle)`（`enum TapeStyle { case kraft, pinkDots, greenCheck }`）、`Pin(active: Bool)`、`StickyNote<Content>(color: Color, tape: TapeStyle?, tilt: Double, content:)`、`Polaroid<Content>(caption: String, content:)`、`WavyRule(width: CGFloat)`、`Highlighter`（ViewModifier，`View.highlighted() -> some View`）、`TallyMark(count: Int)`、`KraftTag(text: String)`、`View.paperShadow() -> some View`、`View.tilted(_ degrees: Double) -> some View`

**Requirements:**
- `lineSpacing(lineHeight:pitch:) = max(0, pitch - lineHeight)`；行高超过 pitch 时返回 0。
- `showsMarginColumn` 为 `windowWidth >= 1000`。
- `RuledPaper`：底色 `paper`；横线 1pt `rule`，从顶部 `pitch` 开始每 24pt 一条；红线在 x=64，1pt `margin`；`holes` 时左侧 x=32 处竖排 3 个直径 14 的 `hole` 圆（上、中、下各一），带内阴影；`ruled: false` 只画素纸（留红线）。
- `CorkBoard`：`cork` 底 + 程序生成的 `corkDeep` 斑点（固定随机种子，每次绘制一样），不用图片。
- 纸纹：`RuledPaper` 在 `decor >= .medium` 时叠一层 ≤ 4% 不透明度的浅色噪点（固定种子）；不允许深色噪点。
- `decor == .minimal` 时：`StickyNote` 不画胶带、`tilt` 视为 0、不画卷角；`RuledPaper` 只画 `paper` 底；`Pin`、`Tape`、`Polaroid`、纸纹不画。
- `decor <= .low` 时不画横线、纸纹、旋转、打孔。
- `tilted` 在 `decor < .full` 时不旋转；旋转只是静态角度，不加动画。
- `StickyNote` 卷角：右下角 14pt 三角阴影，`paperShadow`。
- `Polaroid`：`polaroid` 白卡、四周 8pt 留白、底部 32pt 留白放 `caption`（`Font.fee(.label)`，`ink`），顶部居中一条 `kraft` 胶带，`paperShadow()`。
- `WavyRule`：`Path` 画正弦波，振幅 2pt、波长 12pt、线宽 1.2pt、`tertiary`。
- `TallyMark`：每 5 个一组，前 4 竖 + 1 斜，`link` 色，1.5pt。
- `KraftTag`：`kraft` 底、左侧直径 5pt 的孔、文字 `Font.fee(.label)` `ink`、内边距 8×3。
- `paperShadow()`：`shadow(color: Palette.paperShadow, radius: 4, x: 0, y: 2)`（blur 8 ≈ radius 4）。
- 对齐检查（本任务的通过 / 不通过标准）：用 `RuledPaper` 叠一段 `ruledText(.body)` 的中英混排三行文字，`ImageRenderer` 渲到 PNG，人工放大看：每行基线落在横线上方 4–7pt 的同一位置。**不通过**时：把文字区改用 `ruled: false`（素纸），在 DESIGN.md 记一条，并告诉用户。

**Test cases:**
- `lineSpacing(lineHeight: 19.5)` → `4.5`；`lineSpacing(lineHeight: 30)` → `0`
- `snap(25)` → `48`；`snap(24)` → `24`；`snap(0)` → `0`
- `showsMarginColumn(windowWidth: 999)` → `false`；`1000` → `true`
- `Decor.minimal < .full` → `true`
- `PaperMetrics.lineSpacing(.body) + FeeFonts.lineHeight(.body)` → `24 ± 0.5`

- [ ] **Step 1: 按上述 cases 写 `PaperTests.swift`**
- [ ] **Step 2: 运行确认失败**：`… --filter PaperTests` → `PaperMetrics` 未定义
- [ ] **Step 3: 实现 `Paper.swift`；加调试命令 `paperRender:<png>`（在 `AppModel.debugCommand` 里，渲一张全部组件的样张：横线纸 + 文字、软木板、三种便利贴、拍立得、波浪线、划记、吊牌，`decor` 分别为 full 和 minimal 两排）**
- [ ] **Step 4: 运行确认通过**：`PaperTests` 通过；`lsctl paperRender:/tmp/feebee-t4-paper.png` 出图并按上面的对齐标准检查，结论写进进展备注；同步在 `tools/README.md` 的「渲染」里加 `paperRender:<png>`
- [ ] **Step 5: Commit** `feat: add paper, cork and sticky-note decorations`

---

### Task 5: 主窗口外框与会议列表

**Files:**
- Modify: `Sources/Cicada/Views.swift`（`MainWindowView.body` `:887-951`、`sidebar` `:954-1112`、`sessionRow` `:1033`、`detail` `:1116`、`tabButton` `:1292`、`header` `:1337`、`pinnedBar` `:1311`）
- Modify: `Sources/Cicada/ListenPill.swift`（工具栏在听按钮）

**Interfaces:**
- Consumes: `CorkBoard`、`RuledPaper`、`Pin`、`KraftTag`、`.tilted`、`.paperShadow()`、`PaperMetrics.corkInset/sidebarWidth`、`.decor(_:)`、`BreathingDot`
- Produces: `MainWindowView` 根视图带 `.decor(.full)`；详情页容器 `NotebookPage<Content>(holes: Bool, content:)`（放进 `Paper.swift`）

**Requirements:**
- 整窗 `CorkBoard`，四周留 16pt；左栏 232pt；右侧详情是一张 `NotebookPage(holes: true)`，带 `paperShadow()`。
- 会议列表每场一张白卡（`paper` 底），按序号交替 `tilted(+0.6)` / `tilted(-0.6)`，顶部居中一颗 `Pin`；标题 `Font.fee(.body, strong: true)`、日期 `Font.fee(.meta)` `tertiary`。
- 选中卡片：`Pin(active: true)`（`accent`）、旋转归零、阴影加深（radius 8），过渡 0.15s；减少动态效果时直接切换。
- 正在进行的会议：卡片左上角 `BreathingDot(size: 6)`（保留现有逻辑）。
- 顶部搜索框：牛皮纸标签样式（`kraft` 底、只有文字和放大镜，无边框），`Font.fee(.bodySecondary)`；⌘F、上下切换命中等行为不变。
- 详情页页眉：日期 `Font.fee(.meta)`、会议标题 `Font.fee(.display)`，「纪要 / 文字记录」两个索引贴：选中的贴片用 `paper` 色和纸面连成一体，未选中的用 `paperShade`、向后缩 2pt。
- 吸顶条 `pinnedBar` 换成 `paper` 底 + 底边 `hairline`，不加横线。
- 工具栏在听按钮：牛皮纸标签样式，在听时左侧 `accent` 圆点；`ListenPill` 的行为和快捷键不变。
- 无会议时的欢迎页放在一张纸上（横线 `ruled: false`）。
- 拖拽导入、右键菜单、分享、搜索、播放等全部交互不变。

**Test cases:**
- 全量单元测试 → 无回归
- `lsctl open` → `lsctl mainWindow:80,80,1280,820` → `lsctl mainShow:<一场有纪要的会议 id>` → `lsctl mainRender:/tmp/feebee-t5-main.png`：看到软木板、钉住的卡片、选中卡片图钉为橙色、横线纸详情页、两个索引贴
- `lsctl mainSearch:<该会议标题里的词>` → 日志 `main search:` 的命中数与改造前一致
- 把窗口拉到 `mainWindow:80,80,900,700` 再截图 → 无重叠、无截断

- [ ] **Step 1: 改造前先截基准图 `/tmp/feebee-t5-before.png`，记下 `mainSearch` 的日志结果**
- [ ] **Step 2: 运行确认现状**：基准图是白纸样式（作为「失败」对照）
- [ ] **Step 3: 实现外框、卡片列表、页眉、索引贴、工具栏按钮**
- [ ] **Step 4: 运行确认通过**：上面四条 cases 全部满足，截图发给用户
- [ ] **Step 5: Commit** `feat: show meeting records as pinned cards on a corkboard`

---

### Task 6: 纪要页（横线纸版）

**Files:**
- Modify: `Sources/Cicada/NotesViews.swift`（`DocumentNotesView` `:147` 起、`conclusion` `:346`、`itemEditor` `:262`、`SectionTitle` `:1203`、`Tag` `:1211`、`TermChips` `:1229`、`FishboneView` `:570`、`SkeletonBar` `:1398`）
- Modify: `Sources/Cicada/AppModel.swift:2368`、`:2324`、`:2336`（调试渲染底色改 `Palette.paper`，`mainRender` 的整页渲染加 `.decor(.full)`）

**Interfaces:**
- Consumes: `RuledPaper`、`WavyRule`、`StickyNote`、`KraftTag`、`GridPaper`、`.highlighted()`、`.ruledText(_:)`、`EnvironmentValues.decor`、`PaperMetrics.marginX`
- Produces: `NotesContentView` 与（private 的）`DocumentNotesView` 都加参数 `todosInMargin: Bool = false`，前者原样传给后者；为 true 时正文不画待办，交给 Task 8 的页边栏；`TodoSticky(item: NoteItem, index: Int, editing: NotesEditHooks?)`（单张待办便利贴，Task 8 复用）

**Requirements:**
- 顺序：摘要 → 话题（`SectionTitle` = `Font.fee(.section)` + 右侧 `WavyRule`）→ 结论（编号在红线左侧页边，`Font.fee(.meta)` `link`）→ 术语 `KraftTag` → 鱼骨图画在 `GridPaper`（12pt 格、`grid` 色、线条 `secondary`）。
- 摘要、话题正文、结论用 `.ruledText(.body)`，段落间距为 24 的整数倍；鱼骨图、编辑框、骨架占位区域下面 `ruled: false`。
- 结论里的数字、日期高亮用 `.highlighted()`（`mark`），替代原来的高亮实现，命中规则不变。
- 待办：每条一张 `TodoSticky`：`stickyPink` + `tapePink`、`tilted(±1)` 交替；前面 ☐（`Image(systemName: "square")`，`Font.icon(13)`，`body` 色）；文字 `ink`，负责人 `Font.fee(.label)` `secondary`。**不画 ☑ / ▸，不加打勾动画**（见修订 1）。
- 编辑：`noteEdit` / `noteSave` 的编号规则不变（先结论后待办，从 1 数）；`itemEditor` 在便利贴里原地编辑，输入框只有一条下划线，聚焦时变 `inkBlue`。
- `Tag`、`SectionTitle`、`TermChips` 在 `decor == .minimal` 时保持原来的扁平样式（只换颜色和字体），给浮窗用。
- `TimeLink` 仍用 `link` 色，跳转行为不变。

**Test cases:**
- `NotesEditingTests` 全部通过（编辑编号规则不变）
- `lsctl mainShow:<id>` + `lsctl mainRender:/tmp/feebee-t6-main.png`：整页渲染图里有波浪线小标题、页边编号、粉色便利贴、吊牌、方格纸鱼骨图
- `lsctl noteEdit:<id>=<结论数+1>` → 第一张待办便利贴进入编辑；`lsctl noteSave:<id>=<结论数+1>|测试待办` → 保存后文字改变；再 `noteSave` 原文字恢复
- 整页渲染放大检查：正文行基线与横线对齐（标准同 Task 4）
- `lsctl notesRender:/tmp/feebee-t6-notes.png`（浮窗版）→ 无横线、无胶带、无旋转

- [ ] **Step 1: 截基准整页图，记录 `noteEdit`/`noteSave` 往返结果**
- [ ] **Step 2: 运行确认现状**：基准图为旧样式
- [ ] **Step 3: 实现纸面纪要与 `TodoSticky`**
- [ ] **Step 4: 运行确认通过**：上述 cases 全部满足，截图发给用户
- [ ] **Step 5: Commit** `feat: lay out meeting notes on ruled paper with to-dos as sticky notes`

---

### Task 7: 文字记录页

**Files:**
- Modify: `Sources/Cicada/Views.swift`（`transcript` `:1447` 起、`quotes` `:1380`、`quoteRow` `:1420`）
- Modify: `Sources/Cicada/NotesViews.swift`（`TranscriptListView` `:672`、`LivePartialRow` `:1093`、`TranscriptWaitingView` `:1133`）

**Interfaces:**
- Consumes: `RuledPaper`、`.ruledText(_:)`、`PaperMetrics.marginX`、`PaperMetrics.snap`、`Palette.speakers`、`Palette.you`、`Palette.accentWash`
- Produces: 无新增公开接口

**Requirements:**
- 时间戳放在红线左侧页边（右对齐到红线左 8pt），`Font.fee(.meta)` `tertiary`，可点跳转行为不变。
- 说话人名用 `Palette.speakers` 循环色，「你」用 `Palette.you`；名字 `Font.fee(.label, strong: true)`。
- 双语：原文 `.ruledText(.bodySecondary)` `secondary`，译文 `.ruledText(.body)` `ink`，各占整行；行与行之间的间距是 24 的整数倍。
- 正在进行的那一行底色 `accentWash`；当前播放 / 搜索命中行 `accentPale`；搜索命中词 `.highlighted()`。
- 对齐检查不通过（换行后错位）时：文字记录页整页改用 `RuledPaper(ruled: false)`（保留红线和页边时间戳），在进展备注写明并告诉用户。
- 双语 / 原文 / 译文切换（`Segments`）、改这句、指定说话人、播放联动都不变。

**Test cases:**
- `TranscriptSearchTests`、`SpeakerTests` 通过
- `lsctl mainShow:<id>,transcript` + `lsctl mainRender:/tmp/feebee-t7-tr.png`：时间戳在红线左侧、说话人颜色、双语两行
- `lsctl mainShow:<id>,transcript,src` 与 `,dst` 各截一张 → 单语模式也对齐
- `lsctl mainSearch:<词>` + `mainSearchStep:1` → 命中行高亮、日志命中数与改造前一致

- [ ] **Step 1: 截基准图并记录搜索日志**
- [ ] **Step 2: 运行确认现状**
- [ ] **Step 3: 实现**
- [ ] **Step 4: 运行确认通过**：上述 cases 满足，对齐结论写进备注
- [ ] **Step 5: Commit** `feat: put transcript times in the page margin with speaker inks`

---

### Task 8: 页边栏与菲比

**Files:**
- Create: `Sources/Cicada/Feebee.swift`
- Create: `Resources/illustrations/feebee-{idle,listening,writing,done,error}.png`（160px）与 `@2x.png`（320px）
- Modify: `scripts/build.sh`（拷贝 `Resources/illustrations/`）
- Modify: `Sources/Cicada/Views.swift`（`SessionNotesView` `:1673` 起、详情页布局）
- Modify: `Resources/{en,ja,ko}.lproj/Localizable.strings`（经 `scripts/strings.py --write`）
- Test: `Tests/CicadaTests/FeebeeTests.swift`

**Interfaces:**
- Consumes: `Polaroid`、`TallyMark`、`TodoSticky`、`NotesContentView(todosInMargin:)`、`PaperMetrics.showsMarginColumn`、`PaperMetrics.marginColumnWidth`、`NotesEngine.State`
- Produces:
  - `enum FeebeeMood: String, CaseIterable { case idle, listening, writing, done, error }`
  - `static func FeebeeMood.of(live: Bool, notesState: NotesEngine.State, hasNotes: Bool, final: Bool) -> FeebeeMood`
  - `FeebeeMood.caption: String`（已 `L()`）、`FeebeeMood.imageName: String`（`"feebee-<rawValue>"`）
  - `FeebeeView(mood: FeebeeMood, size: CGFloat = 160)`：从 `Bundle.main` 的 `illustrations/` 读 PNG；读不到时显示 `paperShade` 圆形占位，不崩溃

**Requirements:**
- 插画：用 `sips -Z 160` / `-Z 320` 从 `docs/design/mascot/feebee-*.png` 缩出，不重新出图。
- 状态推导（按顺序）：
  1. `live` 且 `notesState ∈ {noKey, invalidKey, rateLimited, unreachable, failed}` → `error`
  2. `notesState == .updating` → `writing`
  3. `live` → `listening`
  4. `hasNotes && final` → `done`
  5. 其他 → `idle`
- 文案（中文键 → en / ja / ko）：
  - `在打盹` → `Napping` / `お昼寝中` / `낮잠 중`
  - `正在听` → `Listening` / `聞いています` / `듣는 중`
  - `正在写纪要` → `Writing notes` / `メモを作成中` / `회의록 작성 중`
  - `纪要写好了` → `Notes ready` / `メモができました` / `회의록 완성`
  - `出了点问题` → `Something went wrong` / `問題が発生しました` / `문제가 생겼어요`
  - `本场` → `This meeting` / `この会議` / `이번 회의`
- 页边栏（`showsMarginColumn` 为真，宽 220pt，用竖向 `hairline` 与正文隔开），从上到下：`Polaroid(caption: mood.caption) { FeebeeView(mood:) }` → 「本场」统计（发言人数、待办数、时长，`TallyMark` + 数字 `Font.fee(.meta)` `link`；时长只写数字不划记）→ 待办 `TodoSticky` 列表（此时 `NotesContentView(…, document: true, todosInMargin: true)`）。
- 窗口宽 < 1000pt：页边栏收起，待办回到正文，拍立得和统计不显示。
- 与现有「双语对照栏」（`showQuotes`，`detailWidth >= 940`）并存规则：双语对照栏打开时页边栏不显示（三栏太挤）。
- 待办的编辑与编号规则不变（Task 6）。

**Test cases:**
- `of(live: true, notesState: .failed, hasNotes: true, final: false)` → `.error`
- `of(live: true, notesState: .updating, hasNotes: false, final: false)` → `.writing`
- `of(live: true, notesState: .idle, hasNotes: false, final: false)` → `.listening`
- `of(live: false, notesState: .idle, hasNotes: true, final: true)` → `.done`
- `of(live: false, notesState: .updating, hasNotes: true, final: true)` → `.writing`
- `of(live: false, notesState: .failed, hasNotes: false, final: false)` → `.idle`
- `FeebeeMood.allCases.map(\.imageName)` → 五个名字，且对应文件都在 `Resources/illustrations/`（测试里按仓库路径检查 @1x 和 @2x 都存在）
- 开发版：`mainWindow:80,80,1280,820` 截图有页边栏；`mainWindow:80,80,960,820` 截图无页边栏、待办在正文
- 开发版实际走一遍：`lsctl start:user` + `afplay Resources/sample/sample.m4a` 期间截图 → 拍立得显示「正在听」或「正在写纪要」；结束后 → 「纪要写好了」
- `python3 scripts/strings.py` → 无缺失

- [ ] **Step 1: 按上述 cases 写 `FeebeeTests.swift`**
- [ ] **Step 2: 运行确认失败**：`… --filter FeebeeTests` → `FeebeeMood` 未定义
- [ ] **Step 3: 缩图、实现 `Feebee.swift`、页边栏布局、文案**
- [ ] **Step 4: 运行确认通过**：单元测试与开发版 cases 全部满足，截图发给用户
- [ ] **Step 5: Commit** `feat: add a margin column with Feebee's status, meeting tallies and to-dos`

---

### Task 9: 第一部分验收

**Files:**
- Modify: `docs/plans/2026-11-25-paper-ui-1-tokens-and-main-window.md`（勾选与备注）
- Modify: `PROJECT.md`

**Interfaces:**
- Consumes: 前面全部任务

**Requirements:**
- 主窗口在中文与英文界面各截一套：纪要、文字记录、窄窗、宽窗。英文界面用 `defaults write com.wquguru.cicada.dev AppleLanguages '("en")'` 后重启开发版，验收完恢复。
- 检查项：无截断、无重叠；横线对齐（或已按规则退回素纸并记录）；时间戳在红线左侧；待办为粉色便利贴；宽窗显示页边栏；卡片选中态清楚。
- 实时纪要窗（还没做第二部分）至少不比改造前差：`notesRender` 截图可读。
- `python3 scripts/check-design.py` 退出码 0；全量测试通过。

**Test cases:**
- `scripts/test.sh -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays` → 全部通过（含 `check-design.py`）
- 两种语言的 8 张截图发给用户确认

- [ ] **Step 1: 跑全量测试与检查脚本**
- [ ] **Step 2: 两种语言截图并逐项对照检查项**
- [ ] **Step 3: 修掉发现的问题（每个问题单独提交）**
- [ ] **Step 4: 再跑一遍测试，展示输出**
- [ ] **Step 5: 更新 PROJECT.md，Commit** `docs: finish part one of the paper redesign`
