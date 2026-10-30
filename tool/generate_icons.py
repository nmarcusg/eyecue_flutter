#!/usr/bin/env python3
"""Generate every EyeCue launcher / adaptive / store icon from assets/logo.png.

The logo is the single source artwork (owner decision, work items I and K): it is
never redrawn, recoloured or re-lettered here -- only letterboxed onto square
canvases and downscaled.

Requires Pillow (pre-installed on the build host; it is NOT a project
dependency and nothing is installed by this script). No other dependency.

    python3 tool/generate_icons.py            # write every asset, then verify
    python3 tool/generate_icons.py --check    # verify the committed files only

See docs/icon-generation.md for the numbers and the source hash.
"""

import hashlib
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "logo.png"
RES = ROOT / "android" / "app" / "src" / "main" / "res"
STORE = ROOT / "store-assets"

# Android density buckets: dp -> px factor.
DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}

LEGACY_DP = 48  # mdpi legacy launcher icon; other densities scale by factor
FOREGROUND_DP = 108.0  # adaptive icon canvas
SAFE_ZONE_DP = 66.0  # adaptive icon safe-zone diameter (33 dp radius)
# Ink is scaled to a 31 dp radius instead of 33 dp: resampling widens the
# outermost anti-aliased pixels by up to 1 mdpi pixel (1 dp), and the measured
# extent must stay inside the 33 dp safe-zone radius at every density.
FG_INK_RADIUS_DP = 31.0
PLAY_ICON = 512
# 11 % padding on each side of the longest ink side -> content is 78 % of the
# canvas. Inside the 10-12 % band the contract asks for.
CONTENT_RATIO = 0.78
ALPHA_INK = 8  # alpha above this counts as ink when measuring a bounding box

# Background for every raster icon. kHomeSurfaceCard (#FFFFFF) is the only
# palette value (lib/theme/app_colors.dart) that keeps the glyph's black stroke
# (#0A0A0A, kHomeInk) and its cyan arc (#22C7F2, kHomeAccentCyan) both visible.
BACKGROUND = (255, 255, 255, 255)
BACKGROUND_HEX = "#FFFFFF"
MONOCHROME = (255, 255, 255, 255)

# Feature graphic: 1024x500, no alpha, dark scaffold field + the app's light
# card surface behind the logo. No text: no font is bundled, so drawing type
# would not be reproducible across machines.
FEATURE_SIZE = (1024, 500)
FEATURE_FIELD = (0x12, 0x12, 0x12, 255)  # kScaffoldBackground
FEATURE_PANEL = (620, 380, 44)  # width, height, corner radius
FEATURE_INK = 260  # logo longest side in px

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
"""

BACKGROUND_XML = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- kHomeSurfaceCard from lib/theme/app_colors.dart; see docs/icon-generation.md. -->
    <color name="ic_launcher_background">%s</color>
</resources>
""" % BACKGROUND_HEX


def source_metrics():
    """Ink bounding box, aspect and worst-case ink radius of the logo."""
    im = Image.open(SRC).convert("RGBA")
    bbox = im.getbbox()
    if bbox is None:
        raise SystemExit("%s has no opaque pixels" % SRC)
    crop = im.crop(bbox)
    # The contract's aspect check is on the ink bounding box, not the canvas.
    aspect = crop.width / crop.height
    # Radius of the farthest ink pixel from the crop centre: the only number
    # that tells us whether a circular mask can clip the mark.
    alpha = crop.getchannel("A").load()
    cx, cy = crop.width / 2.0, crop.height / 2.0
    radius = 0.0
    for y in range(crop.height):
        for x in range(crop.width):
            if alpha[x, y] > ALPHA_INK:
                d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
                if d > radius:
                    radius = d
    return crop, aspect, radius


def render(crop, canvas_px, ink_long_px, background):
    """Letterbox the crop onto a square canvas: ink_long_px = longest ink side."""
    scale = ink_long_px / max(crop.width, crop.height)
    w = max(1, round(crop.width * scale))
    h = max(1, round(crop.height * scale))
    if w > crop.width or h > crop.height:
        raise SystemExit(
            "refusing to upscale: %dx%d target ink from a %dx%d source"
            % (w, h, crop.width, crop.height)
        )
    logo = crop.resize((w, h), Image.LANCZOS)
    canvas = Image.new("RGBA", (canvas_px, canvas_px), background)
    canvas.alpha_composite(logo, ((canvas_px - w) // 2, (canvas_px - h) // 2))
    return canvas


def render_monochrome(crop, canvas_px, ink_long_px):
    """Single-colour silhouette: the logo's own alpha, filled with one colour."""
    shaped = render(crop, canvas_px, ink_long_px, (0, 0, 0, 0))
    out = Image.new("RGBA", (canvas_px, canvas_px), MONOCHROME)
    out.putalpha(shaped.getchannel("A"))
    return out


def render_feature(crop):
    """Feature graphic: dark field, light panel, the same mark centred."""
    img = Image.new("RGBA", FEATURE_SIZE, FEATURE_FIELD)
    pw, ph, radius = FEATURE_PANEL
    panel = Image.new("RGBA", FEATURE_SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(panel)
    x0 = (FEATURE_SIZE[0] - pw) // 2
    y0 = (FEATURE_SIZE[1] - ph) // 2
    draw.rounded_rectangle(
        [x0, y0, x0 + pw - 1, y0 + ph - 1], radius=radius, fill=BACKGROUND
    )
    img.alpha_composite(panel)
    logo = render(crop, FEATURE_INK + 40, FEATURE_INK, (0, 0, 0, 0))
    # render() gives a square canvas; crop it back to the ink box for centring.
    box = logo.getbbox()
    logo = logo.crop(box)
    img.alpha_composite(
        logo,
        ((FEATURE_SIZE[0] - logo.width) // 2, (FEATURE_SIZE[1] - logo.height) // 2),
    )
    return img.convert("RGB")


def targets(crop):
    """Every target: (path, image, expected size, kind)."""
    # Adaptive foreground: the whole mark must sit inside the 66 dp safe-zone
    # circle, so scale by the worst-case ink radius, not the bounding box.
    fg_ink_dp = FG_INK_RADIUS_DP / source_ratio(crop)
    out = []
    for name, factor in DENSITIES.items():
        legacy = round(LEGACY_DP * factor)
        ink = CONTENT_RATIO * legacy
        icon = render(crop, legacy, ink, BACKGROUND)
        mipmap = RES / ("mipmap-" + name)
        out.append((mipmap / "ic_launcher.png", icon, legacy, "legacy"))
        # Round: the same pixels -- 11 % padding keeps the ink (max radius
        # 0.397 x canvas) inside any circular launcher mask.
        out.append((mipmap / "ic_launcher_round.png", icon.copy(), legacy, "legacy"))
        fg = round(FOREGROUND_DP * factor)
        out.append(
            (
                mipmap / "ic_launcher_foreground.png",
                render(crop, fg, fg_ink_dp * factor, (0, 0, 0, 0)),
                fg,
                "foreground",
            )
        )
        out.append(
            (
                mipmap / "ic_launcher_monochrome.png",
                render_monochrome(crop, fg, fg_ink_dp * factor),
                fg,
                "monochrome",
            )
        )
    out.append(
        (
            STORE / "play-icon-512.png",
            render(crop, PLAY_ICON, CONTENT_RATIO * PLAY_ICON, BACKGROUND),
            PLAY_ICON,
            "legacy",
        )
    )
    return out, fg_ink_dp


def source_ratio(crop):
    """Worst-case ink radius as a fraction of the longest crop side."""
    return source_metrics()[2] / max(crop.width, crop.height)


def ink_box(img, kind):
    """Ink bounds: alpha for transparent icons, non-background pixels otherwise."""
    if kind == "legacy":
        # An opaque background makes the alpha channel useless for measuring.
        diff = ImageChops.difference(
            img.convert("RGB"), Image.new("RGB", img.size, BACKGROUND[:3])
        )
        return diff.convert("L").point(lambda v: 255 if v > ALPHA_INK else 0).getbbox()
    alpha = img.getchannel("A")
    return alpha.point(lambda v: 255 if v > ALPHA_INK else 0).getbbox()


def verify(items, fg_ink_dp):
    """Assert every dimension, aspect, centre and safe-zone property."""
    crop, aspect, _ = source_metrics()
    failures = []
    print("\n%-58s %-9s %-9s %-8s %-8s" % ("file", "size", "ink-aspect", "centre", "ink-req"))
    for path, _, size, kind in items:
        rel = str(path.relative_to(ROOT))
        if not path.exists():
            failures.append("%s: missing" % rel)
            continue
        img = Image.open(path)
        problems = []
        if img.size != (size, size):
            problems.append("size %dx%d != %dx%d" % (img.size + (size, size)))
        if img.mode != "RGBA":
            problems.append("mode %s != RGBA (needs alpha)" % img.mode)
        box = ink_box(img, kind)
        if box is None:
            problems.append("no ink")
            continue
        w, h = box[2] - box[0], box[3] - box[1]
        got = w / h
        if abs(got - aspect) > 0.02:
            problems.append("ink aspect %.4f != %.4f" % (got, aspect))
        cx = (box[0] + box[2]) / 2.0 - size / 2.0
        cy = (box[1] + box[3]) / 2.0 - size / 2.0
        if abs(cx) > 1.0 or abs(cy) > 1.0:
            problems.append("ink off centre by %.1f,%.1f px" % (cx, cy))
        if box[0] < 1 or box[1] < 1 or box[2] > size - 1 or box[3] > size - 1:
            problems.append("ink touches the canvas edge")
        # Longest ink side must match the intended padding / safe-zone size.
        factor = size / (FOREGROUND_DP if kind != "legacy" else LEGACY_DP)
        want = (fg_ink_dp if kind != "legacy" else CONTENT_RATIO * LEGACY_DP) * factor
        if abs(max(w, h) - want) > 2.0:
            problems.append("ink longest side %d != %.1f px" % (max(w, h), want))
        if kind == "foreground":
            # Every ink pixel must fit the 66 dp safe-zone circle (33 dp radius).
            alpha = img.getchannel("A").load()
            worst = 0.0
            for y in range(box[1], box[3]):
                for x in range(box[0], box[2]):
                    if alpha[x, y] > ALPHA_INK:
                        d = ((x - size / 2.0) ** 2 + (y - size / 2.0) ** 2) ** 0.5
                        worst = max(worst, d)
            limit = (SAFE_ZONE_DP / 2.0) * size / FOREGROUND_DP
            if worst > limit:
                problems.append("ink radius %.1f px > %.1f px safe zone" % (worst, limit))
            else:
                print(
                    "  sfz  %-53s radius %.1f / %.1f px (%.1f dp)"
                    % (rel, worst, limit, worst * FOREGROUND_DP / size)
                )
        if kind == "monochrome":
            colours = {
                p[:3] for p in img.getdata() if p[3] > 200
            }
            if len(colours) != 1:
                problems.append("not a single colour silhouette: %d colours" % len(colours))
        if problems:
            failures.append("%s: %s" % (rel, "; ".join(problems)))
        print(
            "%-58s %-9s %-9.4f %-8s %-8.1f%s"
            % (
                rel,
                "%dx%d" % img.size,
                got,
                "yes" if abs(cx) <= 1.0 and abs(cy) <= 1.0 else "NO",
                want,
                "" if not problems else "  <-- " + "; ".join(problems),
            )
        )
    feature = STORE / "feature-graphic-1024x500.png"
    if not feature.exists():
        failures.append("%s: missing" % feature)
    else:
        img = Image.open(feature)
        if img.size != FEATURE_SIZE:
            failures.append("%s: size %dx%d" % ((str(feature),) + img.size))
        if img.mode != "RGB":
            failures.append("%s: mode %s, the feature graphic must have no alpha" % (feature, img.mode))
        print("%-58s %-9s (no alpha: %s)" % (str(feature.relative_to(ROOT)), "%dx%d" % img.size, img.mode))
    return failures


def main():
    crop = source_metrics()[0]
    items, fg_ink_dp = targets(crop)
    if "--check" not in sys.argv:
        for path, image, _, _ in items:
            path.parent.mkdir(parents=True, exist_ok=True)
            image.save(path, "PNG", optimize=True)
        (RES / "mipmap-anydpi-v26").mkdir(parents=True, exist_ok=True)
        for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
            (RES / "mipmap-anydpi-v26" / name).write_text(ADAPTIVE_XML)
        (RES / "values" / "ic_launcher_background.xml").write_text(BACKGROUND_XML)
        feature = render_feature(crop)
        STORE.mkdir(parents=True, exist_ok=True)
        feature.save(STORE / "feature-graphic-1024x500.png", "PNG", optimize=True)

    print("source %s sha256 %s" % (SRC.name, hashlib.sha256(SRC.read_bytes()).hexdigest()))
    print("ink metrics: %dx%d px, aspect %.4f, safe-zone ink %.2f dp"
          % (crop.width, crop.height, crop.width / crop.height, fg_ink_dp))
    failures = verify(items, fg_ink_dp)
    print("\noutput hashes:")
    for path in sorted(p for p, _, _, _ in items) + [
        STORE / "feature-graphic-1024x500.png"
    ]:
        print("  %s  %s" % (hashlib.sha256(path.read_bytes()).hexdigest(), path.relative_to(ROOT)))
    if failures:
        print("\nFAILED:")
        for line in failures:
            print("  " + line)
        raise SystemExit(1)
    print("\nOK: %d icons + feature graphic verified" % len(items))


if __name__ == "__main__":
    main()
