#!/usr/bin/env python3
"""Generate procedural placeholder PBR textures.

These are committed to the repo so the Godot materials ALWAYS resolve, even if
the CI asset downloads fail. The GitHub Actions workflow overwrites them with
real 1K PBR maps (ambientCG / PolyHaven) when the network allows.

Usage:  python3 tools/gen_placeholder_textures.py
"""

import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "res", "assets", "textures")
SIZE = 512


def save(img, *parts):
    path = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.convert("RGB").save(path, "JPEG", quality=88)
    print("wrote", os.path.relpath(path))


def height_to_normal(height, strength=2.0):
    """Sobel-ish height -> tangent space normal map."""
    w, h = height.size
    px = height.load()
    out = Image.new("RGB", (w, h))
    op = out.load()
    for y in range(h):
        for x in range(w):
            l = px[(x - 1) % w, y]
            r = px[(x + 1) % w, y]
            u = px[x, (y - 1) % h]
            d = px[x, (y + 1) % h]
            dx = (r - l) / 255.0 * strength
            dy = (d - u) / 255.0 * strength
            nx, ny, nz = -dx, -dy, 1.0
            ln = math.sqrt(nx * nx + ny * ny + nz * nz)
            op[x, y] = (
                int((nx / ln * 0.5 + 0.5) * 255),
                int((ny / ln * 0.5 + 0.5) * 255),
                int((nz / ln * 0.5 + 0.5) * 255),
            )
    return out


def grain(size, seed, scale=1.0, base=128, spread=40):
    rnd = random.Random(seed)
    img = Image.new("L", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            px[x, y] = max(0, min(255, int(base + rnd.gauss(0, spread) * scale)))
    return img


def make_asphalt():
    rnd = random.Random(11)
    size = SIZE
    coarse = grain(size, 11, base=120, spread=55).filter(ImageFilter.GaussianBlur(0.6))
    blobs = Image.new("L", (size, size), 120)
    d = ImageDraw.Draw(blobs)
    for _ in range(2600):
        x = rnd.randrange(size)
        y = rnd.randrange(size)
        r = rnd.randint(1, 5)
        v = rnd.randint(60, 205)
        d.ellipse([x - r, y - r, x + r, y + r], fill=v)
    blobs = blobs.filter(ImageFilter.GaussianBlur(0.8))
    height = Image.blend(coarse, blobs, 0.55)

    albedo = Image.new("RGB", (size, size))
    ap = albedo.load()
    hp = height.load()
    for y in range(size):
        for x in range(size):
            v = hp[x, y] / 255.0
            g = 0.14 + v * 0.20
            ap[x, y] = (int(g * 255 * 1.0), int(g * 255 * 1.02), int(g * 255 * 1.08))
    save(albedo, "asphalt", "albedo.jpg")
    save(height_to_normal(height, 2.2), "asphalt", "normal.jpg")

    rough = Image.new("RGB", (size, size))
    rp = rough.load()
    for y in range(size):
        for x in range(size):
            v = hp[x, y]
            r = max(0, min(255, int(190 + (v - 128) * 0.35)))
            rp[x, y] = (r, r, r)
    save(rough, "asphalt", "roughness.jpg")


def make_concrete():
    rnd = random.Random(29)
    size = SIZE
    height = grain(size, 29, base=135, spread=26).filter(ImageFilter.GaussianBlur(1.1))
    d = ImageDraw.Draw(height)
    for _ in range(70):
        x = rnd.randrange(size)
        y = rnd.randrange(size)
        for _ in range(rnd.randint(4, 12)):
            nx = x + rnd.randint(-16, 16)
            ny = y + rnd.randint(-16, 16)
            d.line([x, y, nx, ny], fill=rnd.randint(70, 105), width=1)
            x, y = nx, ny
    for _ in range(400):
        x = rnd.randrange(size)
        y = rnd.randrange(size)
        r = rnd.randint(1, 3)
        d.ellipse([x - r, y - r, x + r, y + r], fill=rnd.randint(80, 120))
    height = height.filter(ImageFilter.GaussianBlur(0.5))

    albedo = Image.new("RGB", (size, size))
    ap = albedo.load()
    hp = height.load()
    for y in range(size):
        for x in range(size):
            v = hp[x, y] / 255.0
            g = 0.42 + v * 0.30
            ap[x, y] = (int(g * 255), int(g * 253), int(g * 246))
    save(albedo, "concrete", "albedo.jpg")
    save(height_to_normal(height, 1.6), "concrete", "normal.jpg")


def make_wall():
    """Brick wall albedo + normal."""
    rnd = random.Random(77)
    size = SIZE
    rows = 8
    bh = size // rows
    bw = size // 4
    mortar = 6

    albedo = Image.new("RGB", (size, size), (196, 190, 178))
    height = Image.new("L", (size, size), 70)
    da = ImageDraw.Draw(albedo)
    dh = ImageDraw.Draw(height)

    for row in range(rows + 1):
        y0 = row * bh
        offset = (bw // 2) if row % 2 else 0
        x = -offset
        while x < size:
            x0 = x + mortar // 2
            x1 = x + bw - mortar // 2
            y1 = y0 + bh - mortar
            base = rnd.choice(
                [(150, 62, 46), (138, 56, 42), (162, 74, 52), (124, 52, 40), (170, 88, 62)]
            )
            jitter = rnd.randint(-12, 12)
            col = tuple(max(0, min(255, c + jitter)) for c in base)
            da.rectangle([x0, y0 + mortar // 2, x1, y1], fill=col)
            dh.rectangle([x0, y0 + mortar // 2, x1, y1], fill=rnd.randint(185, 225))
            x += bw

    ap = albedo.load()
    for y in range(size):
        for x in range(size):
            r, g, b = ap[x, y]
            n = rnd.randint(-14, 14)
            ap[x, y] = (
                max(0, min(255, r + n)),
                max(0, min(255, g + n)),
                max(0, min(255, b + n)),
            )
    albedo = albedo.filter(ImageFilter.GaussianBlur(0.4))
    height = height.filter(ImageFilter.GaussianBlur(1.0))
    save(albedo, "wall", "albedo.jpg")
    save(height_to_normal(height, 2.6), "wall", "normal.jpg")


if __name__ == "__main__":
    make_asphalt()
    make_concrete()
    make_wall()
    print("placeholder textures done")
