#!/usr/bin/env python3
"""把视图里写死的 `.system(size: N[, weight: .w][, design: .d])` 换成字体 token（DESIGN.md › 字号）。

可以反复运行：合并上游后再跑一次，新进来的字面量字号会被换掉，已经换过的不动。
  python3 scripts/restyle-fonts.py          改写文件
  python3 scripts/restyle-fonts.py --check  只报告，有待改项时退出码 1

字号或字重是变量 / 三元表达式的写法脚本不改，打印出来手工改。
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources" / "Cicada"
# 字幕条、Dock 图标、DMG 背景、关于面板不在本次改造范围；Theme.swift 是定义处
EXEMPT = {"Overlay.swift", "DMGBackground.swift", "DockIcon.swift", "AboutPanel.swift", "Theme.swift"}

LITERAL = re.compile(
    r"\.system\(size: (?P<size>\d+(?:\.\d+)?)"
    r"(?:, weight: \.(?P<weight>\w+))?"
    r"(?:, design: \.(?P<design>\w+))?\)"
    r"(?P<digits>\.monospacedDigit\(\))?"
)
ANY = re.compile(r"\.system\(size:")
STRONG = {"medium", "semibold", "bold", "heavy", "black"}


def token(size: float, weight: str | None, design: str | None, digits: bool, icon: bool) -> str:
    if icon:
        w = f", weight: .{weight}" if weight else ""
        return f".icon({size:g}{w})"
    strong = weight in STRONG
    if design == "monospaced" or digits:
        role = "meta" if size >= 12 else "caption"
    elif size >= 24:
        role = "display"
    elif size >= 17 and strong:
        role = "title"
    elif size >= 15 and not strong:
        role = "body"
    elif size >= 15:
        role = "section"
    elif size >= 13:
        role = "body"
    elif size >= 12:
        role = "bodySecondary"
    elif size >= 10:
        role = "label"
    else:
        role = "caption"
    # display / title / section 本身就是 Medium，不用再加 strong
    if strong and role not in ("display", "title", "section"):
        return f".fee(.{role}, strong: true)"
    return f".fee(.{role})"


def restyle(text: str) -> tuple[str, int, list[tuple[int, str]]]:
    out, count, manual = [], 0, []
    for n, line in enumerate(text.split("\n"), 1):
        icon = "Image(systemName:" in line

        def sub(m: re.Match) -> str:
            nonlocal count
            count += 1
            return token(float(m["size"]), m["weight"], m["design"], bool(m["digits"]), icon)

        line = LITERAL.sub(sub, line)
        if ANY.search(line):
            manual.append((n, line.strip()))
        out.append(line)
    return "\n".join(out), count, manual


def main() -> int:
    check = "--check" in sys.argv
    total, manual_all = 0, []
    for path in sorted(SRC.glob("*.swift")):
        if path.name in EXEMPT:
            continue
        text = path.read_text()
        new, count, manual = restyle(text)
        total += count
        manual_all += [(path.name, n, l) for n, l in manual]
        if count and not check:
            path.write_text(new)
    verb = "待改" if check else "已改"
    print(f"{verb} {total} 处")
    for name, n, l in manual_all:
        print(f"  需手工改 {name}:{n}: {l}")
    return 1 if check and (total or manual_all) else 0


if __name__ == "__main__":
    sys.exit(main())
