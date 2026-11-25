# 第二轮前端：手帐主窗口 · Plan

依据：DESIGN.md › 主窗口（第二轮 · 手帐）、样稿 `docs/design/mockups/round2-planner.html`（2026-11-25 用户确认）。
只改主窗口；设置、引导、面板、实时纪要窗不动。新组件放 `Sources/Cicada/Planner.swift`，`Views.swift` 只改 `body`、左栏、页眉和工具。

## 定下的取舍

- 中缝：两页共用一个画布画纸和横线，中缝什么都不画；右页滚动按 24pt 停（`ScrollTargetBehavior`），停下来时横线和左页对齐。
- 工具栏去掉：开始听 = 笔插里的笔；正在听 / 倒计时的标签放到皮面上沿右侧，设置齿轮在它右边。⌘R 仍由应用菜单负责。
- 左页看哪一周：跟着选中的会议走（`mainShow`、待办来源跳转都会翻到那一周）；没有选中时看今天。周一开头，日历固定为公历 + firstWeekday 2（`PlannerCalendar`，纯函数，可注入日期）。
- 分隔页：本周 / 当月 / 更早 决定左页时间线的范围；有搜索词时左页列出所有匹配，不受分隔页限制。
- 右页工具：分享、导出是右下角印章；双语 / 原文 / 译文、原话、重新转写留在页眉虚线字。页边栏只在右页 ≥ 900pt 时出现（统计「待办 1/2」、录音铅笔在里面）；窄时待办回正文。
- 窗口最小 940×600；左页窄于 1100pt 窗宽时 280pt。
- 待办页：左页是统计 + 七天格 + 菲比 + 搜索；右页 `TodoBoardView(planner: true)`：不画自己的页眉、拍立得、页脚搜索，「我的 / 别人的」挪到上沿索引贴。
- 竖排字：中文逐字竖排，其他语言整体转 90°。

## 任务

- [x] 1. `Palette.leather/leatherDeep/stitch`；`PlannerCalendar`（周、月、按天分组）+ 单元测试
- [x] 2. `Planner.swift`：`LeatherCover`、`SpreadPaper`、`PageTabs`、`DividerTabs`、`PenLoop`、`VerticalLabel`；调试命令 `plannerRender:<png>` 按 1280×800 画整窗（不滚动），和样稿截图对照
- [x] 3. 主窗口接上：去工具栏，左页 `WeekPage`（时间线、搜索、右键菜单），右页上沿索引贴、菲比涂鸦、印章、单行页脚
- [x] 4. 待办页：`TodoWeekPage` + `TodoBoardView(planner:)`
- [x] 5. 右页滚动按 24pt 停；页脚、固定条高度取 24 的倍数
- [x] 6. 文案（中文键 + en/ja/ko 手动追加）、英文界面、`scripts/test.sh`、整窗渲染交用户在真机看（含滚动时中缝的横线）

## 进展

- 2026-11-25：1–6 完成。444 个测试通过；中英文、空闲 / 在听、本周 / 当月 / 更早 / 搜索 / 待办、940×600 都用 `mainRender` 截图看过。待用户实机确认：顶部 28pt 里的点击（索引贴、结束、齿轮）、中缝滚动时横线是否对齐。原先计划的 `plannerRender` 整窗渲染没留下（`mainRender` 已能画出滚动区）。
- 2026-11-25：用户实机确认（上沿点击、滚动对齐都正常）。
