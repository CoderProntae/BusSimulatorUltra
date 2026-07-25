#!/usr/bin/env python3
"""Generate a procedural Radiance (.hdr) panorama sky.

Committed as a fallback so the WorldEnvironment ALWAYS has a real HDRI
panorama sky (with sun disk + clouds + horizon haze), even when the CI
PolyHaven download fails. CI overwrites it with a real 1K HDRI when possible.

Output: res/assets/environment/sky.hdr  (new-style RLE Radiance RGBE)
"""

import math
import os
import random
import struct

OUT = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "res", "assets", "environment", "sky.hdr"
)
W, H = 1024, 512


def float_to_rgbe(r, g, b):
    m = max(r, g, b)
    if m < 1e-32:
        return (0, 0, 0, 0)
    mant, exp = math.frexp(m)
    scale = mant * 256.0 / m
    return (
        min(255, int(r * scale)),
        min(255, int(g * scale)),
        min(255, int(b * scale)),
        min(255, max(0, exp + 128)),
    )


def write_rle_component(out, data):
    """New-style RLE for a single component of one scanline."""
    i = 0
    n = len(data)
    while i < n:
        run_end = i
        while run_end < n - 1 and data[run_end] == data[run_end + 1]:
            run_end += 1
        run_len = run_end - i + 1
        if run_len >= 4:
            while run_len > 0:
                chunk = min(run_len, 127)
                out.append(128 + chunk)
                out.append(data[i])
                i += chunk
                run_len -= chunk
        else:
            # literal run until a run of >=4 begins
            start = i
            j = i
            while j < n:
                k = j
                while k < n - 1 and data[k] == data[k + 1] and k - j < 4:
                    k += 1
                if k - j >= 3:
                    break
                j += 1
                if j - start >= 128:
                    break
            count = min(j - start, 128)
            if count <= 0:
                count = 1
            out.append(count)
            out.extend(data[start:start + count])
            i = start + count


# --- value noise for clouds -------------------------------------------------
RND = random.Random(1234)
GRID = 64
NOISE = [[RND.random() for _ in range(GRID)] for _ in range(GRID)]


def vnoise(x, y):
    x0, y0 = int(math.floor(x)), int(math.floor(y))
    fx, fy = x - x0, y - y0
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    a = NOISE[x0 % GRID][y0 % GRID]
    b = NOISE[(x0 + 1) % GRID][y0 % GRID]
    c = NOISE[x0 % GRID][(y0 + 1) % GRID]
    d = NOISE[(x0 + 1) % GRID][(y0 + 1) % GRID]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(x, y):
    total = 0.0
    amp = 0.5
    freq = 1.0
    for _ in range(5):
        total += vnoise(x * freq, y * freq) * amp
        freq *= 2.0
        amp *= 0.5
    return total


def sky_color(u, v):
    """u in [0,1) longitude, v in [0,1] latitude (0 = zenith)."""
    theta = v * math.pi          # 0 top .. pi bottom
    phi = u * math.tau
    dy = math.cos(theta)
    dx = math.sin(theta) * math.cos(phi)
    dz = math.sin(theta) * math.sin(phi)

    # sun direction (warm afternoon sun)
    sun_alt = math.radians(32.0)
    sun_az = math.radians(135.0)
    sx = math.cos(sun_alt) * math.cos(sun_az)
    sy = math.sin(sun_alt)
    sz = math.cos(sun_alt) * math.sin(sun_az)

    up = max(dy, 0.0)

    if dy >= 0.0:
        # sky gradient: deep blue zenith -> pale horizon
        zenith = (0.16, 0.33, 0.72)
        horizon = (0.72, 0.80, 0.92)
        t = pow(1.0 - up, 3.2)
        r = zenith[0] + (horizon[0] - zenith[0]) * t
        g = zenith[1] + (horizon[1] - zenith[1]) * t
        b = zenith[2] + (horizon[2] - zenith[2]) * t
        scale = 2.6
    else:
        # ground hemisphere: muted grey-green
        d = min(1.0, -dy * 2.4)
        r = 0.24 - 0.10 * d
        g = 0.23 - 0.09 * d
        b = 0.20 - 0.08 * d
        scale = 0.9

    cosang = dx * sx + dy * sy + dz * sz
    cosang = max(-1.0, min(1.0, cosang))
    ang = math.acos(cosang)

    # sun disk + glow
    if dy > -0.05:
        if ang < math.radians(2.0):
            return (900.0, 780.0, 620.0)
        glow = math.exp(-ang * 5.0) * 3.0
        halo = math.exp(-ang * 1.4) * 0.55
        r += glow * 1.0 + halo * 0.55
        g += glow * 0.86 + halo * 0.44
        b += glow * 0.62 + halo * 0.30

    # clouds (only above horizon)
    if dy > 0.0:
        cu = phi / math.tau * 26.0
        cv = (1.0 - up) * 16.0
        c = fbm(cu, cv)
        cover = max(0.0, (c - 0.48) / 0.52)
        cover = min(1.0, cover * 1.5) * min(1.0, up * 4.0)
        lit = 0.85 + 0.55 * max(0.0, cosang)
        r = r * (1 - cover) + (1.25 * lit) * cover
        g = g * (1 - cover) + (1.25 * lit) * cover
        b = b * (1 - cover) + (1.28 * lit) * cover

    return (r * scale, g * scale, b * scale)


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as fh:
        fh.write(b"#?RADIANCE\n")
        fh.write(b"# Procedural fallback sky for BusSimulator\n")
        fh.write(b"FORMAT=32-bit_rle_rgbe\n\n")
        fh.write(("-Y %d +X %d\n" % (H, W)).encode("ascii"))

        for y in range(H):
            v = (y + 0.5) / H
            comps = [bytearray(W) for _ in range(4)]
            for x in range(W):
                u = (x + 0.5) / W
                r, g, b = sky_color(u, v)
                rr, gg, bb, ee = float_to_rgbe(r, g, b)
                comps[0][x] = rr
                comps[1][x] = gg
                comps[2][x] = bb
                comps[3][x] = ee
            fh.write(struct.pack("BBBB", 2, 2, (W >> 8) & 0xFF, W & 0xFF))
            out = bytearray()
            for ci in range(4):
                write_rle_component(out, comps[ci])
            fh.write(out)
    print("wrote", os.path.relpath(OUT), os.path.getsize(OUT), "bytes")


if __name__ == "__main__":
    main()
