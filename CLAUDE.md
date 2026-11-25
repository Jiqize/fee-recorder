@AGENTS.md

# Fork 说明（优先于上面的 AGENTS.md）

这是 [wquguru/cicada](https://github.com/wquguru/cicada)（知了）的个人 fork：`Jiqize/fee-recorder`。`AGENTS.md` 是上游文件，**不改它**（它有 6 KB 和固定章节的检查，改了也会让合并上游变难）。本 fork 的差异都写在这里；两者冲突时以本节为准。

## 改造目标

1. **前端升级（当前阶段）**：Mac 版换成「笔记本 + 软木板拼贴」的纸张风格，规范见 [DESIGN.md](DESIGN.md)。
2. **品牌改名（待定）**：产品改叫 Feebee（菲比），吉祥物是小蜜蜂（见 DESIGN.md）。应用里显示的名字、图标、`CicadaLogo` 什么时候换、换到什么程度还没定，动手前问我；正式版 bundle id 规则照旧。
3. **待办功能大改（下一阶段）**：方案未定。前端阶段只换待办的样式（便利贴），不改 `NoteItem` 的数据结构、提示词和记录格式。

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

- **自动更新会覆盖改造版**：`UpdateChecker.swift` 查的是上游 `wquguru/cicada` 的 Releases。自己打的正式版如果点了更新，就会被换回上游原版。要正式自用前，先决定关掉更新检查还是改成指向本 fork（待定，动手前问我）。
- **上游同步**：上游更新频繁（~800 次提交）。界面改动尽量集中在样式层（`Palette`、字体 token、可复用组件），少动视图里的逻辑，方便以后合并。需要时：`git remote add upstream https://github.com/wquguru/cicada.git`。

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
