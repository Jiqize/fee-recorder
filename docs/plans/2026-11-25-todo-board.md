# 跨会议待办板 Implementation Plan

**Goal:** 待办能跟进（三种状态、截止日、星标、自己加），所有会议的待办汇到主窗口的一块待办板上，AI 重写纪要时不丢你的改动。
**Architecture:** 在 `NoteItem` 上加可选字段（状态、截止日、星标、来源、是否动过、稳定 id），旧记录照常读。纯逻辑放三个新文件：`Todos.swift`（单条待办的改动、跨重写合并、截止日）、`TodoBoard.swift`（汇总、分组、排序、统计）、`TodoInbox.swift`（不属于任何会议的「手记」待办）。`AppModel` 用一个入口 `changeTodo` 把改动送到正确的地方（会议中的纪要引擎 / 已存的会议 / 手记），界面只调它。界面复用纸上手记组件。
**Tech Stack:** Swift 6.2 工具链（Swift 5 语言模式）、SwiftUI / AppKit（macOS 14.4+）、Swift Testing、SwiftPM + Command Line Tools。

Spec：`docs/specs/2026-11-25-todo-board.md`（唯一事实来源）。样稿：`docs/design/mockups/todo-board.html`。

## Global Constraints

- 只做 Mac 版（`Sources/Cicada`）；不改分享网页、其它平台。
- 记录文件新增字段全部可选；旧 `session.json` 不报错，待办都算「没开始」、无截止日（spec › 兼容）。不改已有字段含义。
- 不改正式版 bundle id；实时纪要窗仍不抢焦点、`sharingType` 逻辑不动；AI 调用只走 `LingClient`。
- 颜色只经 `Palette`，字体只经 `Font.fee` / `Font.icon`；`scripts/check-design.py` 要过。
- UI 文案中文是本地化键，用 `L()`；新文案逐条补 en / ja / ko，**只追加**到 `Resources/*.lproj/Localizable.strings` 末尾，不跑 `strings.py --write`（它会重写整个文件）。
- 系统「减少动态效果」打开时，打勾不动画。
- 测试命令：`scripts/test.sh -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays`；开发版：`scripts/build.sh && open build/Cicada.app`，`tools/lsctl --timeout 10 <命令>`；示例会议：`python3 tools/seed-demo-meeting.py`（id `20261120-100000`，会议日 2026-11-20 周五）。
- 提交：英文 Conventional Commits，结尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`；不推送。

## 文件结构

| 文件 | 职责 |
|---|---|
| Modify `Sources/Cicada/Notes.swift` | `NoteItem` 新字段；`MeetingNotes.removedTodos`；解析 `due`；提示词加截止日与会议日期；引擎保存前合并待办；`NotesEngine.updateTodos` |
| Create `Sources/Cicada/Todos.swift` | `TodoState`、`TodoChange`、`MeetingNotes.changingTodo`、`TodoMerge.carry`、`TodoDue` |
| Create `Sources/Cicada/TodoInbox.swift` | 手记待办的存取（`Todos/inbox.json`） |
| Create `Sources/Cicada/TodoBoard.swift` | `TodoRef`、`BoardItem`、`TodoBoard`（汇总 / 我的 / 分组 / 排序 / 统计） |
| Create `Sources/Cicada/TodoViews.swift` | `TodoRow`、`TodoAddLine`、`TodoBoardView` |
| Modify `Sources/Cicada/SessionStore.swift` | `Session.keptTodos`；`restartImport` 前留下动过的待办；Markdown / Word 导出写状态 |
| Modify `Sources/Cicada/RichCopy.swift` | 复制全文写状态 |
| Modify `Sources/Cicada/AppModel.swift` | `todoInbox`、`changeTodo`、`addTodo`、调试命令 |
| Modify `Sources/Cicada/Views.swift` | 左栏「待办」卡、详情页切到待办板、页边栏统计；菜单栏面板的待办行 |
| Modify `Sources/Cicada/Notebook.swift` | 页边栏便利贴用 `TodoRow` |
| Modify `Sources/Cicada/NotesViews.swift` | 纪要页待办行用 `TodoRow`、加一条 |
| Modify `Sources/Cicada/NotesWindow.swift` | 实时纪要窗能勾 |
| Modify `tools/seed-demo-meeting.py` | 示例会议加几条带状态 / 截止日的待办 |
| Test `Tests/CicadaTests/TodoTests.swift` | 改动、合并、截止日 |
| Test `Tests/CicadaTests/TodoBoardTests.swift` | 汇总、分组、排序、统计、手记 |
| Test `Tests/CicadaTests/ExportTests.swift` | 导出写法（追加用例） |

---

### Task 1: 待办的数据与单条改动

**Files:**
- Modify: `Sources/Cicada/Notes.swift:7-75`（`MeetingNotes`、`NoteItem`）
- Create: `Sources/Cicada/Todos.swift`
- Modify: `Sources/Cicada/NotesEditing.swift:31-44`（待办那一支改走 `changingTodo`）、`tools/README.md`（`noteEdit` / `noteSave` 说明）
- Modify: `CLAUDE.md`「改造目标」第 3 条：改成「待办大改（进行中）：spec `docs/specs/2026-11-25-todo-board.md`，可以改 `NoteItem`、提示词和记录格式（只加可选字段）」
- Test: `Tests/CicadaTests/TodoTests.swift`

**Interfaces:**
- Produces:
  - `enum TodoState: String, Codable { case open, doing, done }`
  - `NoteItem` 新可选字段：`uid: String?`（稳定 id）、`state: TodoState?`（nil = open）、`due: String?`（`"yyyy-MM-dd"`）、`starred: Bool?`、`byUser: Bool?`（自己加的）、`touched: Bool?`（用户动过）、`aiText: String?`（被用户改字前 AI 的原文）、`doneAt: Date?`
  - `NoteItem.status: TodoState { state ?? .open }`、`NoteItem.isStarred: Bool`、`NoteItem.key: String { uid ?? text }`；`NoteItem.id` 改为返回 `key`（结论没有 uid，仍等于文字）
  - `struct TodoTombstone: Codable, Equatable { var text: String; var t: Double?; var owner: String? }`
  - `MeetingNotes.removedTodos: [TodoTombstone]?`（删掉的 AI 待办：原文、出处时间、负责人）
  - `enum TodoChange: Equatable { case state(TodoState), star(Bool), due(String?), text(String), owner(String?), delete }`
  - `extension MeetingNotes { func changingTodo(key: String, _ change: TodoChange, now: Date) -> MeetingNotes; func addingTodo(text: String, owner: String?, due: String?) -> MeetingNotes; mutating func assignTodoIDs() }`
  - `NoteItem.toggled(now: Date) -> TodoState`（点方框：open / doing → done；done → open）

**Requirements:**
- 所有新字段可选，编码时 nil 不写出；旧 JSON（只有 text / owner / support / t）解码成功。
- `assignTodoIDs`：没有 `uid` 的待办补一个 8 位小写十六进制随机 id；已有的不变。
- 任何 `TodoChange` 都把该条 `touched` 设为 true。
- `.state(.done)` 写 `doneAt = now`；改成别的状态清空 `doneAt`。
- `.text(t)`：第一次改 AI 待办的文字时，把原文存进 `aiText`；`t` 去掉首尾空白后为空等同 `.delete`。
- `.delete`：AI 待办（`byUser != true`）把 `TodoTombstone(text: aiText ?? text, t: t, owner: owner)` 追加进 `removedTodos`（同文字去重）；自己加的直接删。
- `MeetingNotes.editing(.item(i))` 落在待办上时（含 `noteSave` 调试命令），文字改动转成 `changingTodo(key:, .text(…))`，负责人改动转成 `.owner(…)`，清空转成 `.delete`——旧的编辑入口也会标 `touched`、留墓碑。
- `addingTodo`：新条目 `byUser = true`、`touched = true`、`owner` 默认 `"你"`、带新 `uid`，追加到 `todos` 末尾。
- 找不到 `key` 时原样返回。

**Test cases:**
- 旧 JSON `{"text":"a","support":1}` 解码 → `status == .open`、`due == nil`、`isStarred == false`
- 新字段全 nil 的 `NoteItem` 编码 → JSON 里没有 `state` / `due` / `starred` 键
- `changingTodo(key:, .state(.done), now: D)` → `status == .done`、`doneAt == D`、`touched == true`；再 `.state(.open)` → `doneAt == nil`
- `.text("新字")` 改 AI 待办 → `text == "新字"`、`aiText == 原文`；再改一次 → `aiText` 仍是最初原文
- `.text("  ")` → 该条被删
- `.delete` AI 待办 → `todos` 少一条、`removedTodos == [TodoTombstone(text: 原文, t: 该条 t, owner: 该条 owner)]`；`.delete` 自己加的 → `removedTodos` 不变
- `editing(.item(结论数 + 0), text: "改过")` → 该待办 `touched == true`、`aiText == 原文`；`editing(.item(结论数 + 0), text: "")` → 留下墓碑
- `addingTodo(text: "约摄影师", owner: nil, due: nil)` → 末尾一条，`byUser == true`、`owner == "你"`、`uid` 8 位
- `toggled`：open → done、doing → done、done → open

- [x] **Step 1: 按上述 cases 写 `TodoTests.swift`（数据部分）**
- [x] **Step 2: 运行确认失败**：`… --filter TodoTests` → 编译失败（`TodoState` 未定义）
- [x] **Step 3: 实现**
- [x] **Step 4: 运行确认通过**：`TodoTests` 通过，全量测试无回归（`NotesEditingTests`、`ExportTests`、`ShareTests` 照过）
- [x] **Step 5: Commit** `feat: give to-dos a state, deadline, star and stable id`

> 进展（2026-11-25）：Task 1 完成。`TodoTests` 16 个用例通过，全量 401 个测试通过；页面编辑待办改走 `changingTodo(at:)`（按行号，避免无 uid 同字撞 key），保存未改动的文字不标「动过」。

---

### Task 2: AI 重写纪要时保留你的待办

**Files:**
- Modify: `Sources/Cicada/Todos.swift`
- Modify: `Sources/Cicada/Notes.swift:330-347`（引擎保存前）、`:217`（`applyEdited` 旁加 `updateTodos`）
- Modify: `Sources/Cicada/SessionStore.swift:30-56`（`Session.keptTodos`）、`:394-400`（`restartImport`）
- Modify: `Sources/Cicada/SpeakerID.swift:359`（改说话人名时，`aiText` 和墓碑里的文字、负责人一起换）
- Modify: `Sources/Cicada/AppModel.swift`（调试命令 `notesInject`）
- Test: `Tests/CicadaTests/TodoTests.swift`

**Interfaces:**
- Consumes: Task 1 的字段与 `assignTodoIDs`
- Produces:
  - `enum TodoMerge { static func carry(from latest: MeetingNotes?, kept: [NoteItem], into new: inout MeetingNotes) }`
  - `Session.keptTodos: KeptTodos?`，`struct KeptTodos: Codable, Equatable { var items: [NoteItem]; var removed: [TodoTombstone] }`
  - `TodoMerge.same(_ a: NoteItem, _ b: NoteItem) -> Bool`、`TodoMerge.buried(_ item: NoteItem, in: [TodoTombstone]) -> Bool`
  - `NotesEngine.apply(_ reply: MeetingNotes, id: String, base: MeetingNotes, final: Bool, fresh: Bool, frozen: Int, lines: [TranscriptLine])`：把现在 `generate` 里拿到回复之后、`store.setNotes` 为止的那段抽出来，真回复和调试注入走同一条路
  - 调试命令 `notesInject:<id>=<回复 JSON 文件>[,final][,fresh]`：用 `parse` 读文件，走 `apply`
  - `NotesEngine.updateTodos(id: String, _ transform: (MeetingNotes) -> MeetingNotes)`（会议中改待办：同时改引擎内存里的 `notes` 和 store）

**Requirements:**
- **「同一件事」不能只看文字**：会后完整版只看文字记录、会重新措辞；换语言重写会整句换掉；改说话人名会改文字。所以 `same(a, b)` 为真的条件（任一）：
  - 文字相等（比较 `text` 与对方的 `text` / `aiText`，去首尾空白、不区分大小写）；
  - 出处时间相同（两边 `t` 都有且相差 ≤ 1 秒）**且**负责人相同（都为 nil 也算相同）。
  `buried(item, in:)`：墓碑文字相等，或 `t` 相差 ≤ 1 秒且负责人相同。
- `carry` 规则（spec › AI 重新整理时不丢东西）：
  1. 结果的 `removedTodos` = 旧的 `removedTodos` ∪ `kept` 里带来的。
  2. 保留：`latest.todos` 和 `kept` 中 `touched == true` 或 `byUser == true` 的条目，原样、保持原相对顺序，排在最前。
  3. 新回复里的 AI 待办：与某条保留条目 `same`、或被 `buried` 的，丢掉。
  4. 其余新 AI 待办：与 `latest` 里某条没动过的待办 `same` 时，沿用它的 `uid`，`t` 取更早的；排在保留条目之后，保持回复里的顺序。
  5. 最后 `assignTodoIDs()`。
- 改说话人名（`SpeakerID.swift:359` 那处 `swap`）同样作用于 `aiText`、墓碑的 `text` 和 `owner`。
- 引擎在 `store.setNotes(id, next)` 之前调用 `TodoMerge.carry(from: 当前已存的纪要（id == shownID ? notes : store 里的）, kept: session.keptTodos 的 items, into: &next)`——用**保存前一刻**的纪要，不用请求开始时的 `base`（请求期间用户可能刚勾过）。合并完把 `session.keptTodos` 清掉。
- `restartImport`（重新转写）清空纪要前：把旧纪要里 `touched` / `byUser` 的待办和 `removedTodos` 存进 `keptTodos`。
- `updateTodos`：`id == shownID` 时改 `notes` 并发 `objectWillChange`；总是写 store（`store.setNotes`）。
- `NotesEngine.markFresh` 不把保留条目标成「新」。

**Test cases:**
- latest 有 A（动过、已勾）、B（没动），回复有 A′（A 的原文）、B、C → 结果 = [A（仍已勾）, B（同 uid）, C]
- 用户把 A 改字成「A2」（`aiText` = A），回复仍有 A → 结果只有一条 A2
- `removedTodos` 含 X，回复有 X → 结果没有 X
- 自己加的 U 不在回复里 → 结果仍有 U
- latest 为 nil、kept 有 K（已勾）与 removed [Y]，回复有 K 的原文与 Y → 结果 = [K]，`removedTodos` 含 Y
- 每条结果都有 `uid`
- 换了措辞：latest 有 A「下周三前改尺码表」（已勾，t = 80，owner 你），回复有「周三前完成尺码表改版」（t = 80，owner 你）→ 结果只有 A，仍已勾
- 换了语言：同上，回复是「Redo the size guide by Wednesday」（t = 80，owner 你）→ 只有 A
- 墓碑换措辞：墓碑 {text: X, t: 104, owner: Mia}，回复有 t = 104、owner Mia 的另一种说法 → 被丢掉
- 不是同一件事：t 相同但负责人不同 → 两条都在
- 改说话人名：把「说话人2」改成「Ben」后，墓碑 owner 与 `aiText` 里的「说话人2」都变成「Ben」

- [x] **Step 1: 按上述 cases 追加测试**
- [x] **Step 2: 运行确认失败**：`TodoMerge` 未定义
- [x] **Step 3: 实现 `carry`；把回复后的那段抽成 `apply` 并接上合并；`restartImport`、改说话人名、`updateTodos`、`notesInject`**
- [x] **Step 4: 运行确认通过**；全量测试无回归。再在开发版端到端走一遍（写进备注）：
  - 准备两个回复文件（放 scratchpad）：`live.json`（2 条待办）、`final.json`（同两件事换了措辞 + 1 条新的）。
  - `notesInject:20261120-100000=live.json` → `todoSet:…=done` 勾一条、`todoSet:…=delete` 删一条 → `notesInject:20261120-100000=final.json,final` → `lsctl todoBoard` 与 `notesState`：勾的仍是做完、删的没回来、新的一条出现。
  - 开发版已有用户自己填的 Ling key（2026-11-25 确认）：再用 `notesRegenerate:<id>=mine` 跑一次真实回复，看措辞变化下是否仍匹配。
- [x] **Step 5: Commit** `feat: keep your to-do changes when the notes are rewritten`

> 进展（2026-11-25）：Task 2 完成，全量 414 个测试通过。与计划的出入：
> - `carry` 签名改为 `carry(from:kept: KeptTodos?, names:, into:) -> Outcome`：计划的 `kept: [NoteItem]` 带不进墓碑；`SpeakerLabels.named` 只用于显示、不落盘，存的待办可能仍是「说话人2」而模型拿到的是改过的名字，所以合并时按现在的名字比较、按原样存（有单元测试）。`named` 里也换 `aiText` 和墓碑，供分享和显示。
> - 端到端（开发版）：`todoSet` / `todoBoard` 要到 Task 6 才有，这里用 `noteSave` 改字、删除代替；「勾过的仍是做完」只有单元测试覆盖，开发版检查移到 Task 6。
> - 注入：live.json（2 条）→ 改字 1 条、删 1 条 → final.json（同两件事换措辞 / 换英文 + 1 条新的）：日志 `todos reply=3 kept=1 sameAsKept=1 buried=1 added=1`，改过字的留下、删掉的没回来、新的一条加进来。
> - 真实回复（`notesRegenerate:20261120-100000=mine`）：模型把两条都换了说法（「修改尺码表，下周三前展示」「周五前确认摄影棚预订」），日志 `todos reply=2 kept=1 sameAsKept=1 buried=1 added=0`，都靠「出处时间 + 负责人」认出。之后示例会议已重新种回。

---

### Task 3: 截止日

**Files:**
- Modify: `Sources/Cicada/Notes.swift:572-600`（`format` 里 todos 一行与规则）、`prompt` 开头（会议日期）、`:757-766`（`items` 解析 `due`）
- Modify: `Sources/Cicada/Todos.swift`
- Test: `Tests/CicadaTests/TodoTests.swift`

**Interfaces:**
- Produces:
  - `enum TodoDue { static func date(_ s: String) -> Date?; static func string(_ d: Date) -> String; static func label(_ due: String, today: Date, calendar: Calendar) -> (text: String, overdue: Bool) }`
  - `NotesEngine.prompt(... meetingDate: Date? = nil ...)` 新参数

**Requirements:**
- 提示词：todos 的 JSON 形状加 `"due": "YYYY-MM-DD or null"`；规则加一条：`- A to-do's due is the date it must be done by, only when a time is said ("周五前", "next Wednesday", "3月6日", "月底"), worked out from the meeting date; otherwise null. Never guess.`；提示词开头加一行 `The meeting date is 2026-11-20 (Friday).`（按会议开始时间、用 `en_US_POSIX` 格式化）。`meetingDate` 为 nil 时不加这行。
- 解析：`due` 不是合法的 `yyyy-MM-dd`（`TodoDue.date` 返回 nil）就丢弃；**早于会议当天**的也丢弃（模型算错了日期）。`parse` 加参数 `meetingDate: Date? = nil` 用于这个判断。
- `TodoDue.label`（日历日比较，按 `calendar` 时区）：
  - 等于今天 → `L("今天")`；明天 → `L("明天")`；
  - 今天之后、同一周（`calendar` 的周）内 → 星期几（`dateText(d, "EEE")`）；
  - 更晚 → `dateText(d, "MMMd")`；
  - 早于今天 → `L("逾期 \(n) 天")`、`overdue = true`。
- `date` / `string` 用 `en_US_POSIX`、公历、`calendar` 的时区。

**Test cases:**
- `date("2026-11-25")` 非 nil；`date("下周三")` → nil；`string(date("2026-11-25")!) == "2026-11-25"`
- today = 2026-11-25（周三，`firstWeekday = 2`）：`label("2026-11-25")` → 今天、非逾期；`"2026-11-26"` → 明天；`"2026-11-28"` → 周六的 `EEE`；`"2026-12-06"` → `MMMd`；`"2026-11-23"` → `逾期 2 天`、`overdue == true`
- `prompt(..., meetingDate: 2026-11-20)` 含 `The meeting date is 2026-11-20 (Friday).`；不传时不含 `The meeting date`
- 解析 `{"todos":[{"text":"a","due":"2026-11-25","evidence":["L1"]}]}` → `due == "2026-11-25"`；`"due":"next week"` → nil；`meetingDate` = 2026-11-20 时 `"due":"2026-11-19"` → nil
- 端到端（日期算得对不对，spec 验收 4）：开发版已有 Ling key，示例会议「下周三前给大家看」用 `notesRegenerate:20261120-100000=mine` 重新生成后 `due == "2026-11-25"`

- [x] **Step 1: 按上述 cases 追加测试**
- [x] **Step 2: 运行确认失败**
- [x] **Step 3: 实现；引擎调用 `prompt` / `longFinal` 时传 `session.startedAt`**
- [x] **Step 4: 运行确认通过**
- [x] **Step 5: Commit** `feat: work out to-do deadlines from what was said`

> 进展（2026-11-25）：Task 3 完成，全量 418 个测试通过。`TodoDue.date` / `string` / `label` 多了可选 `calendar` 参数（默认 `.current`）；会议日期也写进长会议的分段与合并提示词。真实回复（`notesRegenerate:20261120-100000=mine`）：「下周三前给大家看」→ `due 2026-11-25`，「周五前把影棚定下来」→ `2026-11-27`（验收 4 前半）；之后示例会议已重新种回。

---

### Task 4: 手记待办（不属于任何会议）

**Files:**
- Create: `Sources/Cicada/TodoInbox.swift`
- Test: `Tests/CicadaTests/TodoBoardTests.swift`

**Interfaces:**
- Consumes: `NoteItem`、`TodoChange`
- Produces:
  - `@MainActor final class TodoInbox: ObservableObject { @Published private(set) var items: [NoteItem]; init(file: URL? = nil); func add(text: String, owner: String?, due: String?); func change(key: String, _ change: TodoChange, now: Date) }`
  - 默认文件：`~/Library/Application Support/<DevBuild.supportFolder>/Todos/inbox.json`

**Requirements:**
- `add`：同 `addingTodo` 的规则（`byUser`、`touched`、默认负责人「你」、新 uid）。
- `change`：同 `changingTodo` 的规则；`.delete` 直接删（手记都是自己加的）。
- 每次改动后整体写文件（原子写）；读不到或格式坏时从空开始，并写日志 `todos: inbox unreadable, starting empty`，不覆盖坏文件（另存为 `inbox.bad-<时间>.json`）。

**Test cases:**
- 用临时目录：`add("约摄影师")` → 新建实例从同一文件读回 1 条，`owner == "你"`
- `change(key:, .state(.done))` → 读回 `status == .done`
- 写入非 JSON 内容的文件 → `items` 为空，原文件被改名为 `inbox.bad-*.json`

- [x] **Step 1: 写测试**
- [x] **Step 2: 运行确认失败**
- [x] **Step 3: 实现**
- [x] **Step 4: 运行确认通过**
- [x] **Step 5: Commit** `feat: keep to-dos that belong to no meeting`

> 进展（2026-11-25）：Task 4 完成，全量 421 个测试通过（`TodoInboxTests` 3 个）。手记复用 `MeetingNotes.addingTodo` / `changingTodo` 的规则；内容没变时不写文件。

---

### Task 5: 待办板的汇总、分组与统计

**Files:**
- Create: `Sources/Cicada/TodoBoard.swift`
- Test: `Tests/CicadaTests/TodoBoardTests.swift`

**Interfaces:**
- Consumes: `Session`、`NoteItem`、`TodoDue`
- Produces:
  - `enum TodoRef: Hashable { case meeting(session: String, key: String), inbox(key: String) }`
  - `struct BoardItem: Identifiable, Equatable { let ref: TodoRef; let item: NoteItem; let meeting: String?（会议标题，手记为 nil）; let meetingDate: Date?; var id: TodoRef { ref } }`
  - `enum TodoGroup: CaseIterable { case overdue, today, thisWeek, later, noDate, done }`
  - `enum TodoBoard`：
    - `static func items(sessions: [Session], inbox: [NoteItem]) -> [BoardItem]`
    - `static func isMine(_ item: NoteItem) -> Bool`
    - `static func groups(_ items: [BoardItem], today: Date, calendar: Calendar) -> [(TodoGroup, [BoardItem])]`（只返回非空组）
    - `static func byOwner(_ items: [BoardItem]) -> [(owner: String, items: [BoardItem])]`
    - `static func counts(_ items: [BoardItem], today: Date, calendar: Calendar) -> (open: Int, overdue: Int, dueToday: Int, thisWeek: Int)`
    - `static func filter(_ items: [BoardItem], meeting: String?, owner: String?, query: String) -> [BoardItem]`

**Requirements:**
- `items`：每场会议的 `notes?.todos`（会议中的那场用存储里的版本即可）+ 手记；会议标题用 `RecordList.listTitle`。
- `isMine`：`owner == nil || owner == "你" || owner == "未识别"` 为我的（nil 和「未识别」就是 spec 里的「没人认领」，行里标「未认领」）；其余（含「对方」和各人名）算别人的。
- 分组（日历日）：做完了 → `done`（只收 `doneAt` 在最近 30 天内的）；有截止日且早于今天 → `overdue`；等于今天 → `today`；同一周内 → `thisWeek`；更晚 → `later`；没有截止日 → `noDate`。
- 每组排序：星标在前 → 截止日升序（无日期在后）→ 会议日期降序 → `t` 升序；`done` 组按 `doneAt` 降序。
- `byOwner`：负责人显示名（`ownerShown`）分组，组按名字排序；组内同上排序、不含 done。
- `counts`：只算没做完的；`thisWeek` 含今天。
- `filter`：`query` 对 `text` 做不区分大小写包含；`meeting` 比较会议 id；`owner` 比较原始 owner。

**Test cases:**
- 两场会议各 2 条 + 手记 1 条 → `items.count == 5`，手记的 `meeting == nil`
- `isMine`：nil / "你" / "未识别" → true；"Mia" / "对方" → false
- today = 2026-11-25：due 2026-11-23 → overdue；11-25 → today；11-27 → thisWeek；12-06 → later；无 → noDate；done 且 doneAt 10 天前 → done；done 且 doneAt 40 天前 → 不出现
- 同组两条，后者星标 → 星标在前
- `counts` 对上一组数据 → open 5、overdue 1、dueToday 1、thisWeek 2
- `filter(query: "影棚")` 只剩含「影棚」的

- [x] **Step 1: 写测试**
- [x] **Step 2: 运行确认失败**
- [x] **Step 3: 实现**
- [x] **Step 4: 运行确认通过**
- [x] **Step 5: Commit** `feat: group and sort to-dos across meetings`

> 进展（2026-11-25）：Task 5 完成，全量 429 个测试通过（`TodoBoardTests` 8 个，含 Task 6 计划的 `TodoRef` 相等测试）。做完了的没有 `doneAt` 时不进「做完了」组；`BoardItem` 多了 `sessionID` 便于筛选。

---

### Task 6: 改待办的统一入口与调试命令

**Files:**
- Modify: `Sources/Cicada/AppModel.swift`（属性、`debugCommand`）、`Sources/Cicada/NotesEditing.swift`
- Modify: `tools/README.md`、`tools/seed-demo-meeting.py`

**Interfaces:**
- Consumes: `TodoRef`、`TodoChange`、`TodoInbox`、`NotesEngine.updateTodos`、`MeetingNotes.changingTodo` / `addingTodo`
- Produces:
  - `AppModel.todoInbox: TodoInbox`
  - `AppModel.changeTodo(_ ref: TodoRef, _ change: TodoChange)`
  - `AppModel.addTodo(to session: String?, text: String, owner: String?, due: String?)`（nil = 手记）
  - `AppModel.todoBoardShown: Bool`（`@Published`，主窗口详情页是否在待办板）
  - 调试命令：`todoSet:<session|inbox>/<key>=<open|doing|done|star|unstar|due:YYYY-MM-DD|due:none|delete>`、`todoAdd:<session|inbox>=<文字>`、`todoBoard`（日志 `todos: open=… overdue=… today=… week=… done=…`）、`todoBoardShow`

**Requirements:**
- `changeTodo` 路由：会议中的那场（`store.liveID`）→ `notes.updateTodos`；其他会议 → `store.setNotes` + `notes.applyEdited`；手记 → `todoInbox.change`。
- **会议进行中也能改待办**（只限待办；摘要和结论的编辑规则不变：`canEditNotes` 不改）。
- 每次改动写日志 `todos: <ref> <change>`。
- `seed-demo-meeting.py`：示例会议的两条待办加 `uid`、一条 `due: "2026-11-25"`、一条 `state: "doing"` + `starred: true`；另写第二场示例会议（id `20261118-153000`「面料供应商周会」，2 条待办：一条负责人「你」截止 2026-11-23，一条负责人「Ben」）。

**Test cases:**
- 单元：`TodoRef` 的 Hashable / 相等（同 session 同 key 相等）
- 开发版：`seed` 后重启 → `lsctl todoBoard` 日志里 open / overdue 数与示例数据一致；`lsctl todoSet:20261120-100000/<uid>=done` 后再 `todoBoard` → open 少 1；重启开发版后状态仍在
- 开发版：开始听（`lsctl start:user`），`todoAdd:<liveID>=测试待办` → `todoBoard` 的 open 数 +1，`lsctl notesState` 后日志里该会议的待办数 +1（重写后仍保留由 Task 2 的单元测试保证；开发版没有 Ling key，不跑真实重写）

- [x] **Step 1: 写 `TodoRef` 单元测试，运行确认失败**
- [x] **Step 2: 实现入口与调试命令，改种子脚本**
- [x] **Step 3: 跑开发版按上面的 cases 验证，日志贴进进展备注**
- [x] **Step 4: 全量测试通过**
- [x] **Step 5: Commit** `feat: one way to change a to-do from anywhere, with debug commands`

> 进展（2026-11-25）：Task 6 完成，全量 429 个测试通过（`TodoRef` 测试已在 Task 5 加）。`changeTodo` 对会议中和已存的会议都走 `notes.updateTodos`（同时写 store、更新引擎里显示的那份，等于计划的 setNotes + applyEdited）。开发版日志：种子后 `todos: open=2 overdue=1 today=1 week=1 done=0 others=2` → `todoSet:20261120-100000/a1b2c301=done` 后 `open=1 … done=1` → 重启后仍 `open=1 … done=1`；补 Task 2：勾过的再经 `notesInject …final.json,final` 仍是 `a1b2c301:done`；`start:user` 后 `todoAdd:20261125-171555=测试待办` → open 2；`todoAdd:inbox=约摄影师` 写入 `Todos/inbox.json`。已知：会议中加了待办但整场没人说话，停止时整场记录照旧被丢掉，待办随之消失。`tools/seed-demo-meeting.py` 被 .gitignore（`tools/*`）忽略、从未入库，改动只在本机。

---

### Task 7: 会议里的待办（便利贴、纪要页、实时纪要窗）

**Files:**
- Create: `Sources/Cicada/TodoViews.swift`（`TodoRow`、`TodoAddLine`）
- Modify: `Sources/Cicada/Notebook.swift`（`NotebookMarginColumn` 的便利贴）、`Sources/Cicada/Views.swift`（`marginColumn`、`stats`）、`Sources/Cicada/NotesViews.swift`（`DocumentNotesView` 待办小节、`NotesContentView` 卡片版待办）、`Sources/Cicada/NotesWindow.swift`

**Interfaces:**
- Consumes: `AppModel.changeTodo`、`AppModel.addTodo`、`TodoDue.label`、`BoardItem`
- Produces:
  - `struct TodoRow: View { init(item: NoteItem, meeting: String? = nil, showOwner: Bool = true, compact: Bool = false, change: @escaping (TodoChange) -> Void, openSource: (() -> Void)? = nil) }`
  - `struct TodoAddLine: View { init(add: @escaping (String) -> Void) }`

**Requirements:**
- `TodoRow`（DESIGN.md 待办项 + spec › 一条待办）：
  - 角色栏：☐ 手画方框 / ▸ 红铅笔 / ☑ 绿勾；点方框 = `.state(item.toggled(...))`；打勾时绿勾按路径描出来 0.2 s（`trim` 动画），减少动态效果时直接出现。
  - 正文：文字（做完了：划线 + `tertiary`）；自己加的用黄纸条蓝字（`stickyYellow` + `inkBlue`）；`showOwner` 时后接灰字「· 负责人」，没人认领写「· 未认领」（`placeholder` 色）。
  - 行尾：截止日（`TodoDue.label`，逾期用 `error` 色）、来源会议名（`link` 色，点了调 `openSource`）、星标（手画星，开 = `hex(0xE0A800)`，关 = `placeholder`）。
  - 点文字原地编辑（下划线输入框，⏎ 保存、esc 取消、清空即删）；右键菜单：没开始 / 进行中 / 做完了、加星 / 去星、设截止日…（弹出一个 `DatePicker(.graphical)` 的小 popover + 「清除」）、改负责人…、删除。
  - `compact`（实时纪要窗、便利贴窄）：不显示来源和截止日编辑入口，只显示截止日文字。
- 页边栏便利贴、窄窗正文「待办」小节都用 `TodoRow`，末尾放 `TodoAddLine`（「＋ 加一条」，⏎ 加到这场会议）。
- 页边栏「本场」统计的待办行显示 `做完/总数`（如 `1/3`），划记数按做完的数。
- 实时纪要窗：待办行用 `TodoRow(compact: true)`，最低装饰（无胶带、不歪），能勾；不加「加一条」。
- 编号规则：纪要编辑的 `.item(i)` 仍按结论在前、待办在后计；待办的改动不再走 `NotesEditHooks`，改走 `changeTodo`（`NotesEditingTests` 里关于待办的用例改成对 `changingTodo` 的断言，结论的用例不动）。

**Test cases:**
- 全量单元测试通过（含改过的 `NotesEditingTests`）
- 开发版：`mainShow:20261120-100000` → `mainRender` 的页边栏截图里便利贴显示 ☐ / ▸ / 截止日 / 星标；`todoSet:…=done` 后再截图 → 该条划线、绿勾、统计 `1/2`
- `notesShow:20261120-100000` + `notesCapturable` + `windowsRender` → 实时纪要窗里待办有方框、无胶带；之后 `notesCapturable:off`
- 减少动态效果：代码读 `@Environment(\.accessibilityReduceMotion)`；`lsctl` 不能模拟这项系统设置，由用户在「系统设置 › 辅助功能 › 显示 › 减少动态效果」打开后目检打勾无动画（结论写进备注）

- [x] **Step 1: 截基准图**
- [x] **Step 2: 改 `NotesEditingTests` 的待办用例，运行确认失败**
- [x] **Step 3: 实现 `TodoRow` / `TodoAddLine` 并接进三处**
- [x] **Step 4: 运行测试与开发版截图确认**
- [x] **Step 5: Commit** `feat: tick, star and date to-dos inside a meeting`

> 进展（2026-11-25）：Task 7 完成，全量 429 个测试通过，check-design 通过。与计划的出入：`TodoRow` 多一个 `tickOnly`（实时纪要窗只能勾、不显示星标、不能改字，因为它是不抢焦点的面板）；`TodoAddLine` 多一个 `compact`；`NotesEditingTests` 没改——`editing(.item)` 的待办分支仍给 `noteSave` 调试命令用（已走 `changingTodo`），页面上的待办改走 `TodoRow` → `changeTodo`。加载记录时给旧待办补 uid（`SessionStore.load`），否则显示用的 `SpeakerLabels.named` 换了说话人名后，以文字为 key 找不回存的那条。`mainRender` 的 `.notes.png` 改成按窄窗把待办画在正文。截图（`build/shots/todo/`）：`t7-before.png`（便利贴 ☐ / ▸ / 今天 / ★ / ＋ 加一条，统计 0/2）、`t7-done-margin.png`（`todoSet …=done` 后绿勾、划线、统计 1/2）、`t7-done-notes-todos.png`（窄窗正文待办行）、`t7-notes-window-todos.png`（实时纪要窗：方框、无星标、无胶带）。减少动态效果：代码读 `accessibilityReduceMotion`，开着时不画勾动画；需用户在系统设置里打开后目检。

---

### Task 8: 待办板

**Files:**
- Modify: `Sources/Cicada/TodoViews.swift`（`TodoBoardView`）
- Modify: `Sources/Cicada/Views.swift`（左栏「待办」卡、`detail` 切换、`footer`）
- Modify: `Sources/Cicada/AppModel.swift`（`mainRender` 加待办板整页渲染 `<png>.todos.png`）

**Interfaces:**
- Consumes: `TodoBoard.*`、`TodoRow`、`TodoAddLine`、`AppModel.changeTodo` / `addTodo` / `todoBoardShown`、`GutterRow`、`NotebookHeading`、`NotebookTab`、`NotebookWord`、`NotebookFooter`、`FeebeeView`、`.notebookColumn()`
- Produces: `struct TodoBoardView: View { init(model: AppModel, store: SessionStore, inbox: TodoInbox, openMeeting: @escaping (String, Double?) -> Void) }`

**Requirements（样稿 `todo-board.html`，spec › 待办板）：**
- 左栏搜索框下钉一张粉色索引卡（`stickyPink`，图钉 `accent`）：标题「待办」（`link` 色）、一行「我的 N 条没做完」，有逾期时接红字「· M 条逾期」；点它 `todoBoardShown = true`，再点任一会议卡片回到会议。待办板显示时这张卡摆正、阴影加深。
- 待办板占详情页（同一张横线纸、页边栏不显示），右上角钉一张拍立得：菲比（有逾期 = `.error`，全部做完 = `.done`，否则 `.writing`），下面写「还有 N 条要做」或「都做完了」。
- 页眉：菲比 46pt + 标题「待办」+「没做完 N · 逾期 M · 本周到期 K」（逾期红字）。
- 标签：「我的 N」「别人的 N」（`NotebookTab`），右边工具字「按会议」「按人」（下拉菜单）「＋ 加一条」。选了筛选时标题下出现牛皮纸条「只看：<会议名 / 人名> ×」。
- 「我的」：`TodoBoard.groups` 的各组，小节标题 = 逾期（`error` 色）/ 今天 / 这周 / 以后 / 没有截止日；「做完了」折叠成一行「做完了 N 条 ›」，点开列出、标题变「做完了」。「没有截止日」组末尾放 `TodoAddLine`（加进手记）。
- 「别人的」：`TodoBoard.byOwner`，小节标题 = 说话人头像（`SpeakerAvatar`，按名字在来源会议里的编号找图，找不到用圆圈）+ 人名。
- 每行 `TodoRow(item:, meeting: 会议标题或 L("手记"), showOwner: 在「我的」里只对未认领显示)`；`openSource` → 打开那场会议的文字记录并跳到 `item.t`（复用现有 `mainShow` / `jumpTo` 路径）。
- 页脚：`NotebookFooter`，状态「都做完了」（✓）或「还有 N 条 · M 条逾期」（*），搜索行 placeholder `L("在待办里找…")`、只搜待办。
- 空状态：一条也没有时，纸上写「还没有待办」+ 灰字「开会时说到要做的事，会自动记在这里」+ `TodoAddLine`。

**Test cases:**
- 开发版（两场示例会议 + 手记 1 条）：`todoBoardShow` → `mainRender:/tmp/todo.png` 的 `.todos.png` 整页渲染与样稿结构一致：分组、星标在前、逾期红字、来源会议名、拍立得
- `todoSet` 把最后一条没做完的勾掉 → 页脚「都做完了」、菲比换成写好了
- 点来源会议名：`lsctl` 无点击命令时，用户目检（写进备注）
- 英文界面同一张截图：无截断
- 全量单元测试通过

- [ ] **Step 1: 截基准（左栏无待办卡）**
- [ ] **Step 2: 实现左栏卡与详情页切换，截图确认卡片**
- [ ] **Step 3: 实现 `TodoBoardView`**
- [ ] **Step 4: 截图对照样稿、英文检查、测试通过**
- [ ] **Step 5: Commit** `feat: add a to-do board that gathers every meeting's to-dos`

---

### Task 9: 菜单栏、导出与验收

**Files:**
- Modify: `Sources/Cicada/Views.swift`（`MenuPanelView`）
- Modify: `Sources/Cicada/SessionStore.swift:562-563`（Markdown）、`:635-637`（Word）、`Sources/Cicada/RichCopy.swift:36`
- Modify: `Resources/{en,ja,ko,zh-Hans}.lproj/Localizable.strings`（只追加）
- Modify: `DESIGN.md`（「待办项」组件一行改成已实现的样子，去掉「本阶段只有方框」）、`docs/plans/2026-11-25-todo-board.md`、`PROJECT.md`
- Test: `Tests/CicadaTests/ExportTests.swift`

**Interfaces:**
- Consumes: `TodoBoard.counts`、`TodoDue`、`NoteItem.status` / `isStarred` / `due`
- Produces: `enum TodoText { static func markdown(_ item: NoteItem) -> String; static func plain(_ item: NoteItem) -> String }`（放 `Todos.swift`）

**Requirements:**
- 菜单栏面板「显示方式」下方：有今天到期或逾期的「我的」待办时显示一行「待办：今天到期 N 条 · 逾期 M 条 ›」（为 0 的那半句不写），点了打开主窗口并 `todoBoardShown = true`；都为 0 时不显示。
- `TodoText.markdown`：`- [ ] ` / `- [x] ` / `- [ ] ▸ `，星标在文字前加 `★ `，有截止日在末尾加 `L("（截止 \(MMMd)）")`，负责人沿用 `withOwner`。
- `TodoText.plain`：`☐ ` / `▸ ` / `☑ ` 开头，其余同上；Word 和复制全文都用它。
- 分享（`ShareProjection`）不改。
- 文案追加 en / ja / ko（Task 7、8 新增的也在此汇总补齐），`python3 scripts/strings.py` 报 0 missing（116 unused 维持原样）。
- 逐条核对 spec「验收标准」1–13，结果写进本文件末尾。

**Test cases:**
- `markdown`：open → `- [ ] 文字（你）`；done → `- [x] …`；doing+星标+截止 2026-11-25 → `- [ ] ▸ ★ 文字（你）（截止 11月25日）`（中文环境）
- `plain`：done → `☑ …`
- 旧记录（无新字段）导出 → 与改动前输出一致（现有 `ExportTests` 不改即通过）
- 菜单栏：`panelRender` 截图在示例数据下显示该行；把逾期和今天的都勾掉后不显示
- `scripts/test.sh …` 全部通过（含 `check-design.py`）

- [ ] **Step 1: 写导出测试，运行确认失败**
- [ ] **Step 2: 实现 `TodoText` 与三处导出，测试通过**
- [ ] **Step 3: 菜单栏行，截图确认**
- [ ] **Step 4: 文案、英文检查、spec 验收逐条核对**
- [ ] **Step 5: 更新 DESIGN.md / PROJECT.md，Commit** `feat: show due to-dos in the menu bar and export their state`
