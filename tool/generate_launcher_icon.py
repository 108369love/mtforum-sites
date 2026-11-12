#!/usr/bin/env python3
"""从 tool/assets/icon_source.png 生成启动图标资源。

源图是一张画好的 1024px 图标（圆角底 + 气泡 + 字标）。自适应图标要把
背景和前景拆成两层，所以这里做三件事：

1. 用「行填充」把气泡（连同里面的字标）抠成一块实心形状，边缘的
   抗锯齿像素按它与背景的混合比例还原成 alpha；
2. 拟合出底色的线性渐变，把气泡盖住的那块重新填平，得到干净的背景；
3. 前景按安全区缩放，保证圆形 / 圆角遮罩下都不会被裁。
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tool" / "assets" / "icon_source.png"

CANVAS = 1024
CORNERS = 24             # 1024 坐标系下的外边距
CORNER_RADIUS = 210
FOREGROUND_SCALE = 0.74  # 自适应前景缩放，收进 72dp 安全区
WHITE_THRESHOLD = 200    # 判定「气泡白」的通道下限


def load_source():
    img = Image.open(SOURCE).convert("RGBA")
    if img.size != (CANVAS, CANVAS):
        img = img.resize((CANVAS, CANVAS), Image.LANCZOS)
    return img


# ---------------------------------------------------------------- 背景拟合

def solve3(m, v):
    """3x3 线性方程组，高斯消元。"""
    a = [row[:] + [v[i]] for i, row in enumerate(m)]
    for i in range(3):
        p = max(range(i, 3), key=lambda r: abs(a[r][i]))
        a[i], a[p] = a[p], a[i]
        for r in range(i + 1, 3):
            f = a[r][i] / a[i][i]
            for c in range(i, 4):
                a[r][c] -= f * a[i][c]
    out = [0.0] * 3
    for i in range(2, -1, -1):
        s = a[i][3] - sum(a[i][c] * out[c] for c in range(i + 1, 3))
        out[i] = s / a[i][i]
    return out


def fit_plane(samples):
    """拟合 value = c0 + c1*x + c2*y。"""
    n = len(samples)
    sx = sum(s[0] for s in samples)
    sy = sum(s[1] for s in samples)
    sxx = sum(s[0] * s[0] for s in samples)
    syy = sum(s[1] * s[1] for s in samples)
    sxy = sum(s[0] * s[1] for s in samples)
    sv = sum(s[2] for s in samples)
    sxv = sum(s[0] * s[2] for s in samples)
    syv = sum(s[1] * s[2] for s in samples)
    mat = [[n, sx, sy], [sx, sxx, sxy], [sy, sxy, syy]]
    return solve3(mat, [sv, sxv, syv])


def build_background_model(px, white_box):
    """采样气泡以外的像素，稳健地拟合底色渐变。"""
    x0, y0, x1, y1 = white_box
    pad = 12
    samples = []
    for y in range(CORNERS + 4, CANVAS - CORNERS - 4, 6):
        for x in range(CORNERS + 4, CANVAS - CORNERS - 4, 6):
            if x0 - pad <= x <= x1 + pad and y0 - pad <= y <= y1 + pad:
                continue
            r, g, b, a = px[x, y]
            if a > 250:
                samples.append((x, y, r, g, b))

    planes = []
    for channel in range(3):
        data = samples
        plane = None
        for _ in range(3):
            plane = fit_plane([(s[0], s[1], s[2 + channel]) for s in data])
            keep = [s for s in data
                    if abs(plane[0] + plane[1] * s[0] + plane[2] * s[1] - s[2 + channel]) < 12]
            if len(keep) == len(data):
                break
            data = keep
        planes.append(plane)
    return planes


def bg_color(planes, x, y):
    return (planes[0][0] + planes[0][1] * x + planes[0][2] * y,
            planes[1][0] + planes[1][1] * x + planes[1][2] * y,
            planes[2][0] + planes[2][1] * x + planes[2][2] * y)


# ---------------------------------------------------------------- 气泡抠图

def white_bbox(px, w, h):
    xs, ys = [], []
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 200 and r > WHITE_THRESHOLD and g > WHITE_THRESHOLD and b > WHITE_THRESHOLD:
                xs.append(x)
                ys.append(y)
    return (min(xs), min(ys), max(xs), max(ys))


def bubble_solid(px, box):
    """每行取白色像素的最小/最大横坐标并填满，字标造成的空洞会被一并补上。"""
    x0, y0, x1, y1 = box
    solid = Image.new("L", (CANVAS, CANVAS), 0)
    sp = solid.load()
    for y in range(y0, min(y1 + 3, CANVAS)):
        idx = [x for x in range(x0, min(x1 + 3, CANVAS))
               if px[x, y][0] > WHITE_THRESHOLD and px[x, y][1] > WHITE_THRESHOLD]
        if not idx:
            continue
        for x in range(min(idx), max(idx) + 1):
            sp[x, y] = 255
    return solid


def bubble_alpha(src, solid, planes):
    """实心区内部 alpha=1，边缘按「与底色的混合比例」还原。"""
    px = src.load()
    core = solid.filter(ImageFilter.MinFilter(5))
    grown = solid.filter(ImageFilter.MaxFilter(9))
    cp = core.load()
    gp = grown.load()

    alpha = Image.new("L", (CANVAS, CANVAS), 0)
    ap = alpha.load()
    for y in range(CANVAS):
        for x in range(CANVAS):
            if not gp[x, y]:
                continue
            if cp[x, y]:
                ap[x, y] = 255
                continue
            r, g, b, a = px[x, y]
            if a < 8:
                continue
            br, bgc, _ = bg_color(planes, x, y)
            denom = 253.0 - br
            if denom < 4:
                continue
            value = max(0.0, min(1.0, (r - br) / denom))
            ap[x, y] = int(round(value * 255))
    return alpha


# ---------------------------------------------------------------- 输出

def scale_about_center(image, scale):
    if scale == 1.0:
        return image
    size = int(CANVAS * scale)
    small = image.resize((size, size), Image.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    pad = (CANVAS - size) // 2
    canvas.paste(small, (pad, pad), small)
    return canvas


def save(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)


def sizes_for(base):
    return {
        "mdpi": base,
        "hdpi": round(base * 1.5),
        "xhdpi": base * 2,
        "xxhdpi": base * 3,
        "xxxhdpi": base * 4,
    }


def main():
    src = load_source()
    px = src.load()

    box = white_bbox(px, CANVAS, CANVAS)
    planes = build_background_model(px, box)
    solid = bubble_solid(px, box)
    alpha = bubble_alpha(src, solid, planes)

    foreground = src.copy()
    foreground.putalpha(alpha)

    background = src.copy()
    bp = background.load()
    grown = solid.filter(ImageFilter.MaxFilter(5))
    gp = grown.load()
    for y in range(CANVAS):
        for x in range(CANVAS):
            if gp[x, y]:
                r, g, b = bg_color(planes, x, y)
                bp[x, y] = (int(round(max(0, min(255, r)))),
                            int(round(max(0, min(255, g)))),
                            int(round(max(0, min(255, b)))), 255)

    save(src, ROOT / "icon_1024.png")

    res = ROOT / "android/app/src/main/res"
    for density, size in sizes_for(48).items():
        save(src.resize((size, size), Image.LANCZOS), res / f"mipmap-{density}/ic_launcher.png")
    for density, size in sizes_for(108).items():
        save(background.resize((size, size), Image.LANCZOS),
             res / f"mipmap-{density}/ic_launcher_background.png")
        save(scale_about_center(foreground, FOREGROUND_SCALE).resize((size, size), Image.LANCZOS),
             res / f"mipmap-{density}/ic_launcher_foreground.png")
    print(f"Generated launcher icons from {SOURCE.name}.")


if __name__ == "__main__":
    main()
