#!/usr/bin/env python3
"""Generate Android launcher icons and Play Store listing graphics.

Everything here is derived from committed sources: the Cozy Fall leaf mark
(the same geometry as assets/icon.svg) and the runtime captures in previews/.
Re-run after changing either; outputs are deterministic.

    python3 tools/generate_store_assets.py
"""

from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
STORE = ROOT / "store"
SHOTS = STORE / "screenshots" / "phone"
PREVIEWS = ROOT / "previews"

BARK = (49, 73, 57)  # #314939 dark green ground
LEAF = (214, 109, 50)  # #d66d32 maple orange
VEIN = (255, 226, 160)  # #ffe2a0 cream
CREAM = (255, 243, 215)
AMBER = (239, 192, 119)

SERIF_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

SS = 4  # supersampling factor for the vector-ish mark


def bezier(p0, p1, p2, p3, steps=48):
    """Cubic bezier as a point list; PIL has no native curve support."""
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        out.append(
            (
                u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0],
                u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1],
            )
        )
    return out


def leaf_outline():
    """assets/icon.svg's leaf path, in its native 512 viewBox."""
    pts = []
    pts += bezier((256, 58), (186, 153), (107, 204), (107, 310))
    pts += bezier((107, 310), (107, 395), (172, 454), (256, 454))
    pts += bezier((256, 454), (340, 454), (405, 395), (405, 310))
    pts += bezier((405, 310), (405, 204), (326, 153), (256, 58))
    return pts


def draw_mark(size, scale=1.0, with_background=True, radius_ratio=0.1875):
    """The Cozy Fall leaf mark, rendered at `size` px square."""
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    if with_background:
        r = int(big * radius_ratio)
        d.rounded_rectangle([0, 0, big - 1, big - 1], radius=r, fill=BARK + (255,))

    # Map the 512 viewBox onto the canvas, shrunk by `scale` about the centre.
    k = big / 512 * scale
    off = (big - 512 * k) / 2

    def m(p):
        return (off + p[0] * k, off + p[1] * k)

    d.polygon([m(p) for p in leaf_outline()], fill=LEAF + (255,))

    w = 22 * k
    d.line([m((256, 106)), m((256, 397))], fill=VEIN + (255,), width=int(w), joint="curve")
    for ctrl in (((164, 240), (215, 248), (256, 282)), ((348, 240), (297, 248), (256, 282))):
        start, c1, c2 = ctrl
        d.line(
            [m(p) for p in bezier(start, c1, c2, (256, 282))],
            fill=VEIN + (255,),
            width=int(w),
            joint="curve",
        )
        for end in (start, (256, 282)):
            cx, cy = m(end)
            d.ellipse([cx - w / 2, cy - w / 2, cx + w / 2, cy + w / 2], fill=VEIN + (255,))

    return img.resize((size, size), Image.LANCZOS)


def write(img, path, mode="RGBA"):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.convert(mode).save(path, "PNG", optimize=True)
    print(f"  {path.relative_to(ROOT)}  {img.size[0]}x{img.size[1]} {mode}")


def build_icons():
    print("Launcher icons:")
    write(draw_mark(192), ASSETS / "icon_192.png")

    # Adaptive icons: Android masks the outer ~27%, so the foreground leaf is
    # inset into the 66% safe zone and the background is a flat full bleed.
    write(draw_mark(432, scale=0.62, with_background=False), ASSETS / "icon_adaptive_foreground_432.png")
    write(Image.new("RGBA", (432, 432), BARK + (255,)), ASSETS / "icon_adaptive_background_432.png")

    print("Play listing icon:")
    # Play rejects transparency in the 512 listing icon.
    write(draw_mark(512), STORE / "icon_512.png", mode="RGB")


def cover(src: Image.Image, w: int, h: int) -> Image.Image:
    """Scale-and-centre-crop, preserving aspect."""
    s = max(w / src.width, h / src.height)
    r = src.resize((round(src.width * s), round(src.height * s)), Image.LANCZOS)
    return r.crop(
        ((r.width - w) // 2, (r.height - h) // 2, (r.width - w) // 2 + w, (r.height - h) // 2 + h)
    )


def build_feature_graphic():
    """1024x500 feature graphic: real porch art, warm scrim, wordmark."""
    print("Feature graphic:")
    W, H = 1024, 500
    base = Image.open(PREVIEWS / "cozyfall_runtime_ambient_1920x1080.png").convert("RGB")
    # Favour the porch and steps over the roofline.
    crop = base.crop((0, 120, 1920, 1080))
    img = cover(crop, W, H)

    # Left-weighted scrim so the wordmark stays legible over the art.
    scrim = Image.new("L", (W, H), 0)
    sd = ImageDraw.Draw(scrim)
    for x in range(W):
        sd.line([(x, 0), (x, H)], fill=int(225 * max(0.0, 1 - (x / (W * 0.62)) ** 1.5)))
    img = Image.composite(Image.new("RGB", (W, H), BARK), img, scrim)

    d = ImageDraw.Draw(img)
    title = ImageFont.truetype(SERIF_BOLD, 92)
    tag = ImageFont.truetype(SANS, 30)
    d.text((64, 168), "Cozy Fall", font=title, fill=CREAM)
    d.text((68, 278), "A peaceful autumn decorating escape", font=tag, fill=AMBER)

    mark = draw_mark(112, with_background=False)
    img.paste(mark, (66, 46), mark)

    write(img, STORE / "feature_graphic_1024x500.png", mode="RGB")


def build_screenshots():
    """Play phone screenshots: unretouched 16:9 runtime captures."""
    print("Phone screenshots:")
    sources = [
        ("01_decorate.png", "cozyfall_runtime_edit_1920x1080.png"),
        ("02_ambient.png", "cozyfall_runtime_ambient_1920x1080.png"),
        ("03_fox_visitor.png", "visitor_fox_runtime_1920x1080.png"),
        ("04_squirrel_visitor.png", "visitor_walk_walk_a_1920x1080.png"),
    ]
    for name, src in sources:
        img = Image.open(PREVIEWS / src).convert("RGB")
        if img.size != (1920, 1080):
            img = cover(img, 1920, 1080)
        write(img, SHOTS / name, mode="RGB")


def build_tv_banner():
    """1280x720 TV banner for the leanback launcher (Cozy Fall also ships on TV)."""
    print("TV banner:")
    base = Image.open(PREVIEWS / "cozyfall_runtime_ambient_1920x1080.png").convert("RGB")
    img = cover(base, 1280, 720)
    scrim = Image.new("L", (1280, 720), 0)
    sd = ImageDraw.Draw(scrim)
    for x in range(1280):
        sd.line([(x, 0), (x, 720)], fill=int(215 * max(0.0, 1 - (x / (1280 * 0.7)) ** 1.6)))
    img = Image.composite(Image.new("RGB", (1280, 720), BARK), img, scrim)
    d = ImageDraw.Draw(img)
    d.text((80, 300), "Cozy Fall", font=ImageFont.truetype(SERIF_BOLD, 118), fill=CREAM)
    d.text((84, 440), "A peaceful autumn decorating escape", font=ImageFont.truetype(SANS, 36), fill=AMBER)
    mark = draw_mark(140, with_background=False)
    img.paste(mark, (80, 128), mark)
    write(img, STORE / "tv_banner_1280x720.png", mode="RGB")


if __name__ == "__main__":
    build_icons()
    build_feature_graphic()
    build_screenshots()
    build_tv_banner()
    print("\nDone.")
