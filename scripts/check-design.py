#!/usr/bin/env python3
"""视图层不写字面量颜色和字号（DESIGN.md › 实施规则 1）：发现就打印 file:line 并退出码 1。

颜色只经 `Palette`（Theme.swift），字号只经 `Font.fee` / `Font.icon`。
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources" / "Cicada"
# 字幕条、Dock 图标、DMG 背景、关于面板不在本次改造范围；Theme.swift 是定义处
EXEMPT = {"Overlay.swift", "DMGBackground.swift", "DockIcon.swift", "AboutPanel.swift", "Theme.swift"}
RULES = [
    (re.compile(r"\.system\(size:"), "写死的字号，改用 Font.fee / Font.icon（可跑 scripts/restyle-fonts.py）"),
    (re.compile(r"\bColor\((?:red|white):"), "写死的颜色，改用 Palette 里的 token"),
]


def main() -> int:
    bad = []
    for path in sorted(SRC.glob("*.swift")):
        if path.name in EXEMPT:
            continue
        for n, line in enumerate(path.read_text().split("\n"), 1):
            for rule, why in RULES:
                if rule.search(line):
                    bad.append(f"{path.relative_to(ROOT)}:{n}: {why}\n    {line.strip()}")
    for b in bad:
        print(b)
    if bad:
        print(f"check-design: {len(bad)} 处不合规")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
