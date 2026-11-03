#!/usr/bin/env python3
"""Builds FrameNova's icons from art/FrameNova-appicon.png (a rounded tile with a glowing rim).

Writes:
  art/FrameNova-icon-square-1024.png   flat square master (no rounded corners, no rim)
  ios/FrameNova/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png   opaque iOS icon (1024 x 1024)
  art/FrameNova-play-icon-512.png      Google Play store icon (512 x 512, opaque; Play rounds the corners itself)
  android/app/src/main/res/mipmap-*/ic_launcher_background.png   adaptive icon layer (108 dp, full bleed)
  android/app/src/main/res/mipmap-*/ic_launcher_monochrome.png   themed icon layer (white logo, Android 13+)

The tile's rim and its transparent or black exterior are replaced by a gradient fitted to the tile's background, faded in
under the artwork, so the square is flat to its edges. Needs Pillow and numpy:  python3 scripts/make-icons.py
"""
import os
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art", "FrameNova-appicon.png")
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")


def tile_bounds(lum):
    """The tile's bounding box: where the centre row and column rise above the black surround."""
    h, w = lum.shape
    row, col = lum[h // 2], lum[:, w // 2]
    xs = np.nonzero(row > 60)[0]
    ys = np.nonzero(col > 60)[0]
    return xs[0], ys[0], xs[-1] + 1, ys[-1] + 1


def rounded_mask(size, inset, radius, feather):
    """A rounded square of [size] inset by [inset], 1 inside and 0 outside, softened over [feather] pixels."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) + 0.5
    lo, hi = inset + radius, size - inset - radius
    dx = np.maximum(np.maximum(lo - xx, xx - hi), 0)
    dy = np.maximum(np.maximum(lo - yy, yy - hi), 0)
    outside = np.hypot(dx, dy) - radius  # signed distance outside the rounded square
    return np.clip(0.5 - outside / feather, 0, 1)


def main():
    # Composite alpha before finding the tile so invisible RGB cannot affect its bounds or gradient.
    source = Image.open(SRC).convert("RGBA")
    opaque = Image.alpha_composite(Image.new("RGBA", source.size, (0, 0, 0, 255)), source)
    src = np.asarray(opaque.convert("RGB")).astype(np.float32)
    x0, y0, x1, y1 = tile_bounds(src.sum(axis=2))
    side = min(x1 - x0, y1 - y0)
    tile = src[y0:y0 + side, x0:x0 + side]
    lum = tile.sum(axis=2)

    # Background gradient: a plane per channel fitted to dark interior pixels, away from the rim and the artwork.
    yy, xx = np.mgrid[0:side, 0:side].astype(np.float32)
    band = rounded_mask(side, side * 0.06, side * 0.12, 2) - rounded_mask(side, side * 0.14, side * 0.06, 2)
    pick = (band > 0.5) & (lum < 200)
    a = np.stack([np.ones(pick.sum()), xx[pick] / side, yy[pick] / side], axis=1)
    planes = [np.linalg.lstsq(a, tile[..., c][pick], rcond=None)[0] for c in range(3)]
    grad = np.stack([p[0] + p[1] * xx / side + p[2] * yy / side for p in planes], axis=-1)

    # Keep the tile inside its rim; fade to the gradient towards the edges and corners.
    keep = rounded_mask(side, side * 0.10, side * 0.10, side * 0.12)[..., None]
    square = np.clip(tile * keep + grad * (1 - keep), 0, 255)
    master = Image.fromarray(square.astype(np.uint8)).resize((1024, 1024), Image.LANCZOS)
    os.makedirs(os.path.join(ROOT, "art"), exist_ok=True)
    master.save(os.path.join(ROOT, "art", "FrameNova-icon-square-1024.png"))
    ios_icon = os.path.join(ROOT, "ios", "FrameNova", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
    os.makedirs(os.path.dirname(ios_icon), exist_ok=True)
    master.save(ios_icon)
    master.resize((512, 512), Image.LANCZOS).save(os.path.join(ROOT, "art", "FrameNova-play-icon-512.png"))

    # Adaptive icon (108 dp): the square fills the 66 dp safe zone, on the same gradient extended to the edges, so
    # every launcher mask (circle, squircle, square) shows the whole logo.
    layer = 1024
    inner = round(layer * 66 / 108)
    off = (layer - inner) // 2
    ly, lx = np.mgrid[0:layer, 0:layer].astype(np.float32)
    ux, uy = (lx - off) / inner, (ly - off) / inner  # gradient coordinates continue beyond the square
    ext = np.stack([p[0] + p[1] * ux + p[2] * uy for p in planes], axis=-1)
    full = Image.fromarray(np.clip(ext, 0, 255).astype(np.uint8))
    full.paste(master.resize((inner, inner), Image.LANCZOS), (off, off))

    # Themed icon: the logo's brightness above the background as a white silhouette.
    sq = np.asarray(master).astype(np.float32)
    bg = np.asarray(Image.fromarray(np.clip(grad, 0, 255).astype(np.uint8)).resize((1024, 1024))).astype(np.float32)
    glow = np.clip((sq.max(axis=2) - bg.max(axis=2) - 40) / 120, 0, 1)
    mono_sq = Image.fromarray((glow * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1)).resize((inner, inner), Image.LANCZOS)
    mono = Image.new("LA", (layer, layer), (255, 0))
    mono.paste(Image.merge("LA", (Image.new("L", (inner, inner), 255), mono_sq)), (off, off))

    for density, px in {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}.items():
        folder = os.path.join(RES, "mipmap-" + density)
        os.makedirs(folder, exist_ok=True)
        full.resize((px, px), Image.LANCZOS).save(os.path.join(folder, "ic_launcher_background.png"), optimize=True)
        mono.resize((px, px), Image.LANCZOS).convert("RGBA").save(os.path.join(folder, "ic_launcher_monochrome.png"), optimize=True)
    print("tile", (x0, y0, side), "icons written")


if __name__ == "__main__":
    main()
