#!/usr/bin/env python3
"""Generate Madrassa 360 Windows branding assets with PIL.

Outputs (repo-relative, run from repo root):
  windows/runner/resources/app_icon.ico   (16/32/48/256 multi-res)
  windows/runner/resources/splash.bmp     (600x400 24-bit)
  android/.../mipmap-*/ic_launcher.png    (48/72/96/144/192 px)
  tool/branding_preview.png               (QA preview sheet, not shipped)

Palette: deep emerald/teal + gold — Islamic geometric 8-point star (khatam).
"""
import math, os
from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.abspath(__file__)) + "/.."
EMERALD_DK = (6, 78, 66)      # deep emerald
EMERALD    = (13, 122, 102)   # emerald
TEAL       = (20, 160, 140)   # teal highlight
GOLD       = (212, 175, 55)    # gold
GOLD_LT    = (240, 205, 110)  # light gold
INK        = (4, 40, 36)      # near-black green for text


def vgrad(size, top, bottom):
    w, h = size
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        px_col = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = px_col
    return img


def star8_points(cx, cy, r_out, r_in, rot=0.0):
    pts = []
    for i in range(16):
        r = r_out if i % 2 == 0 else r_in
        a = rot + math.pi * i / 8 - math.pi / 2
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def draw_khatam(draw, cx, cy, r, gold=GOLD, gold_lt=GOLD_LT, ink=EMERALD_DK):
    """8-point star: gold star, emerald inset star, gold core dot."""
    draw.polygon(star8_points(cx, cy, r, r * 0.52), fill=gold)
    draw.polygon(star8_points(cx, cy, r * 0.62, r * 0.33), fill=ink)
    draw.polygon(star8_points(cx, cy, r * 0.30, r * 0.16), fill=gold_lt)
    draw.ellipse([cx - r * 0.07, cy - r * 0.07, cx + r * 0.07, cy + r * 0.07],
                 fill=gold_lt)


def lattice(draw, w, h, step, color):
    """Faint 8-point-star lattice across the background."""
    for gx in range(-1, w // step + 2):
        for gy in range(-1, h // step + 2):
            cx, cy = gx * step, gy * step
            draw.polygon(star8_points(cx, cy, step * 0.42, step * 0.22),
                         outline=color)


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, img.size[0], img.size[1]], radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def build_icon_base(size=1024):
    img = vgrad((size, size), TEAL, EMERALD_DK)
    d = ImageDraw.Draw(img, "RGBA")
    lattice(d, size, size, size // 6, (255, 255, 255, 14))
    lattice(d, size, size, size // 6, (0, 0, 0, 0))  # noop keep
    cx = cy = size / 2
    R = size * 0.40
    # gold ring
    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=GOLD_LT, width=size // 64)
    d.ellipse([cx - R * 0.90, cy - R * 0.90, cx + R * 0.90, cy + R * 0.90],
              outline=GOLD, width=max(2, size // 160))
    draw_khatam(d, cx, cy, R * 0.72)
    return rounded(img, size // 5)


def build_splash(w=600, h=400):
    img = vgrad((w, h), EMERALD, EMERALD_DK)
    d = ImageDraw.Draw(img, "RGBA")
    lattice(d, w, h, 100, (255, 255, 255, 12))
    # gold star medallion left
    cx, cy, R = 120, h / 2, 86
    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=GOLD_LT, width=4)
    draw_khatam(d, cx, cy, R * 0.74)
    # gold divider
    d.line([230, 90, 230, 310], fill=GOLD, width=3)
    # text
    font = None
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf"):
        if os.path.exists(p):
            font = ImageFont.truetype(p, 36)
            font_sm = ImageFont.truetype(p, 17)
            break
    if font is None:
        font = ImageFont.load_default()
        font_sm = font
    d.text((252, 140), "Madrassa 360", font=font, fill=GOLD_LT)
    d.text((252, 195), "Madrasa Management Platform", font=font_sm,
           fill=(235, 245, 240))
    d.text((252, 250), "OFFLINE-FIRST  •  MULTI-TENANT", font=font_sm,
           fill=(170, 200, 190))
    return img.convert("RGB")  # BMP 24-bit


def main():
    res = os.path.join(REPO, "windows/runner/resources")
    os.makedirs(res, exist_ok=True)

    base = build_icon_base(1024)

    # 1) multi-resolution ICO
    ico_path = os.path.join(res, "app_icon.ico")
    base.save(ico_path, sizes=[(16, 16), (32, 32), (48, 48), (256, 256)])
    print("wrote", ico_path)

    # 2) splash BMP (600x400, 24-bit)
    bmp_path = os.path.join(res, "splash.bmp")
    build_splash().save(bmp_path, "BMP")
    print("wrote", bmp_path)

    # 3) Android mipmap launcher icons (simple res tree: ic_launcher.png only)
    for dpi, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                    ("xxhdpi", 144), ("xxxhdpi", 192)):
        d = os.path.join(REPO, "android/app/src/main/res/mipmap-" + dpi)
        if not os.path.isdir(d):
            print("skip", dpi, "(dir missing)")
            continue
        # launcher icons are opaque squares (no rounded alpha)
        sq = build_icon_base(512).convert("RGB").resize((px, px), Image.LANCZOS)
        sq.save(os.path.join(d, "ic_launcher.png"))
        print("wrote mipmap-" + dpi)

    # 4) QA preview sheet
    prev = Image.new("RGB", (1024 + 40, 460), "white")
    prev.paste(base.resize((420, 420), Image.LANCZOS), (20, 20))
    prev.paste(build_splash(), (460, 20))
    prev.save(os.path.join(REPO, "tool/branding_preview.png"))
    print("preview -> tool/branding_preview.png")


if __name__ == "__main__":
    main()
