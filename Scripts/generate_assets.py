#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成青龙助手（QingLong iOS）所需的图片资源。

用法：
    python Scripts/generate_assets.py

产物：
    QingLong/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
    docs/icon.png

依赖：Pillow
"""

from __future__ import annotations

import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:  # pragma: no cover
    sys.exit("需要 Pillow：pip install pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_ICON = os.path.join(
    ROOT, "QingLong", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png"
)
OUT_DOC = os.path.join(ROOT, "docs", "icon.png")

SIZE = 1024
SS = 4  # 超采样倍数，用于抗锯齿

TOP_LEFT = (0x1F, 0xD2, 0xB4)     # #1FD2B4
BOTTOM_RIGHT = (0x0A, 0x7E, 0x93)  # #0A7E93
HIGHLIGHT = (0x6F, 0xED, 0xD6)     # #6FEDD6

# 闪电多边形（单位坐标 0..1），按顺序闭合
BOLT = [
    (0.585, 0.045),
    (0.215, 0.560),
    (0.450, 0.560),
    (0.360, 0.955),
    (0.785, 0.420),
    (0.530, 0.420),
]


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def diagonal_gradient(size: int) -> Image.Image:
    """左上 -> 右下的线性渐变（沿主对角线插值）。"""
    img = Image.new("RGB", (size, size))
    px = img.load()
    denom = (size - 1) * 2
    for y in range(size):
        for x in range(size):
            t = (x + y) / denom
            px[x, y] = (
                int(round(lerp(TOP_LEFT[0], BOTTOM_RIGHT[0], t))),
                int(round(lerp(TOP_LEFT[1], BOTTOM_RIGHT[1], t))),
                int(round(lerp(TOP_LEFT[2], BOTTOM_RIGHT[2], t))),
            )
    return img


def radial_highlight(size: int) -> Image.Image:
    """左上角柔和高光，叠加后用 screen 混合，增加质感。"""
    layer = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(layer)
    cx, cy = size * 0.26, size * 0.20
    r = size * 0.62
    steps = 64
    for i in range(steps, 0, -1):
        t = i / steps
        radius = r * t
        value = int(120 * (1 - t) ** 2.0)
        draw.ellipse(
            [cx - radius, cy - radius, cx + radius, cy + radius],
            fill=value,
        )
    layer = layer.filter(ImageFilter.GaussianBlur(size * 0.05))
    return layer


def bolt_mask(size: int) -> Image.Image:
    """闪电形状的 alpha 蒙版（含超采样）。"""
    big = size * SS
    mask = Image.new("L", (big, big), 0)
    draw = ImageDraw.Draw(mask)
    points = [(x * big, y * big) for x, y in BOLT]
    draw.polygon(points, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def build_icon() -> Image.Image:
    base = diagonal_gradient(SIZE)

    highlight = radial_highlight(SIZE)
    glow = Image.new("RGB", (SIZE, SIZE), HIGHLIGHT)
    base = Image.composite(glow, base, highlight.point(lambda v: int(v * 0.55)))
    # 用 55% 强度的高光色与原图混合已由 composite 完成，这里再压一层以柔和过渡
    base = Image.blend(diagonal_gradient(SIZE), base, 0.9)

    # 闪电阴影
    shadow_mask = bolt_mask(SIZE).filter(ImageFilter.GaussianBlur(SIZE * 0.018))
    shadow = Image.new("RGB", (SIZE, SIZE), (0x05, 0x3E, 0x4A))
    base = Image.composite(shadow, base, shadow_mask.point(lambda v: int(v * 0.32)))

    # 闪电本体（白色）
    white = Image.new("RGB", (SIZE, SIZE), (0xFF, 0xFF, 0xFF))
    base = Image.composite(white, base, bolt_mask(SIZE))

    return base


def main() -> int:
    icon = build_icon()

    os.makedirs(os.path.dirname(OUT_ICON), exist_ok=True)
    icon.save(OUT_ICON, "PNG", optimize=True)
    print("written", os.path.relpath(OUT_ICON, ROOT))

    os.makedirs(os.path.dirname(OUT_DOC), exist_ok=True)
    icon.resize((512, 512), Image.LANCZOS).save(OUT_DOC, "PNG", optimize=True)
    print("written", os.path.relpath(OUT_DOC, ROOT))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
