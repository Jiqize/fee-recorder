@AGENTS.md

# Fork 说明（优先于上面的 AGENTS.md）

这是 [wquguru/cicada](https://github.com/wquguru/cicada)（知了）的个人 fork：`Jiqize/fee-recorder`。`AGENTS.md` 是上游文件，**不改它**（它有 6 KB 和固定章节的检查，改了也会让合并上游变难）。本 fork 的差异都写在这里；两者冲突时以本节为准。

## 改造目标

1. **前端升级**：Mac 版换成纸张风格，规范见 [DESIGN.md](DESIGN.md)。第一轮「笔记本 + 软木板」已完成；第二轮（当前）主窗口换成皮面手帐（plan `docs/plans/2026-11-25-planner-ui.md`）。
2. **品牌改名（已完成，2026-11-25）**：应用名和界面文案改成「菲比 / Feebee」（日文 フィービー、韩文 피비）；应用图标是纸色方块上菲比的脸（`Resources/icon/feebee-face.png`，`CicadaIcon --art`），菜单栏是代码画的单色小蜜蜂（`FeebeeGlyph`），应用内标志同图标。**不改**：bundle id、`Cicada.app` 文件名和可执行文件名、记录目录 `LiveSubs`、导出文件夹名 Cicada、网络请求头；正式版装上会替换掉已装的知了，权限、设置、会议记录沿用。DMG 背景（不打包）和官网仍是知了。
3. **待办大改（已完成，2026-11-25）**：跨会议待办板，spec `docs/specs/2026-11-25-todo-board.md`，plan `docs/plans/2026-11-25-todo-board.md`。可以改 `NoteItem`、提示词和记录格式，但只加可选字段，旧记录要能照常打开。

## 范围

- **只做 Mac 版**（`Sources/Cicada`）。`windows/`、`linux/`、`android/`、`ios/`、`site/`、`server/` 不动，也不需要跟进。
- 上游规则里「Mac 是参考实现，各端跟进」「每次发版四个平台一起发」在本 fork 不适用。

## 被替换的上游规则

- **设计**：`AGENTS.md › Design` 第一条（`#F3F4F6` 底、白卡片、白纸主窗口）和「claude.ai 设计画布是唯一依据」作废，以 `DESIGN.md` 为准。其余设计规则照旧：中文是本地化键、UI 文案用 `L()`、改文案后跑 `python3 scripts/strings.py`、检查英文界面。
- **不用跑的上游流程**：`scripts/release.sh`、`scripts/package.sh`、`scripts/deploy-site.sh`（发布到上游的域名和 GitHub）；`site/changelog.json` 和四种语言 README 的同步也不做。
- **依赖例外**：「不加第三方依赖」仍然成立，但**开源字体（OFL）和自绘插画作为资源文件打包**不算依赖，许可证文件随字体一起放进仓库。

## 仍然必须遵守的上游硬规则

- 实时纪要窗是不抢焦点的 panel，`sharingType = .none`；换皮肤不能改变这两点。
- UI 和引擎状态在 `@MainActor`；AI 调用只走 `LingClient`；Key 只放 0600 文件。
- 不改正式版 bundle id `com.wquguru.cicada`。开发版用 `com.wquguru.cicada.dev`，设置和日志与本机已装的正式版分开，可以放心并存。

## 已知风险

- **自动更新**：已改成只查本 fork `Jiqize/fee-recorder` 的发布版本（`UpdateChecker.repo`，2026-11-25 用户决定）。fork 现在没有发布版本，所以不会装任何东西；以后要在应用内更新，就在本 fork 发 release：附 `Cicada-<版本>-macOS-AppleSilicon.zip`（前缀必须是 `Cicada-`，`UpdateChecker.newestMac` 按它找）和 `checksums.txt`，版本号要比 `VERSION` 新。合并上游时注意别把这两个地址改回去。
- **待办状态存在会议记录里**（`session.json` 的新可选字段）：上游原版打开这些记录后再保存，会把新字段丢掉。不要装上游原版的更新。
- **上游同步**：上游更新频繁（~800 次提交）。界面改动尽量集中在样式层（`Palette`、字体 token、可复用组件），少动视图里的逻辑，方便以后合并。需要时：`git remote add upstream https://github.com/wquguru/cicada.git`。合并上游后先跑 `python3 scripts/restyle-fonts.py` 把新进来的写死字号换成字体 token，再跑 `python3 scripts/check-design.py`。

- **本机工具链（Command Line Tools，Swift 6.2.4）**：上游有几处长表达式在这个版本会「类型检查超时」，已在 `AICheck.swift`、`NotesTests.swift`、`SpeakerTests.swift` 拆开修好；合并上游后如果又报这个错，同样拆开即可。本机 CLT 的 `_Testing_Foundation` 没有模块文件，跑测试要加参数关掉 cross-import（见下方命令）。

## 目录

- `知了大改造/`（上一级）不是 git 仓库；仓库在 `知了大改造/fee-recorder/`。
- 设计参考图：`docs/design/reference/`（原图在上一级 `设计参考/`）。
- 项目状态：`PROJECT.md`（仓库根目录）。

## 常用

```bash
scripts/build.sh && open build/Cicada.app   # 开发版，可与已装的正式版并存
scripts/test.sh -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays   # AGENTS.md 检查 + 单元测试（本机需带这串参数）
```

前端改动的验证：跑起开发版，截图检查主窗口（纪要 / 文字记录两个标签）、设置、引导、实时纪要窗；英文界面也看一遍。用 `tools/lsctl` 驱动开发版，`afplay Resources/sample/sample.m4a` 当输入。

验证时的坑（2026-11-25 记下）：
- 开发版的 Ling key 已由用户自己填好（2026-11-25，`lsctl aiState` 显示 `hasKey=true`、检查全通过），可以用 `notesRegenerate:<id>=mine` 跑真实纪要；可重复的检查仍优先用 `notesInject`（待办 plan 里加）。**不要**从正式版拷 key 文件。
- `python3 scripts/strings.py --write` 会重写整个 `Localizable.strings`；新文案只往文件末尾追加，`strings.py` 只用来检查。
- `lsctl windowsRender:<目录>` 要求目录已存在；`mainRender` 的窗口截图现在能画出滚动区（手帐版，2026-11-25 实测），只画当前可见的部分；`plannerRange:<week|month|earlier|todo>` 切分隔页；应用启动就会开始听，要看空闲状态先 `stop`，终端没有录屏权限，`screencapture` 不可用。
- 示例数据：`python3 tools/seed-demo-meeting.py`，然后 `mainShow:20261120-100000`。
