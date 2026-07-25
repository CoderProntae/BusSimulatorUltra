#!/usr/bin/env python3
"""Independently decode res/assets/environment/sky.hdr to prove Godot can read it.

Parses the Radiance header + new-style RLE scanlines, checks dimensions and
that every scanline decodes to exactly WIDTH pixels, then writes a PNG preview.
"""

import math
import os
import struct
import sys

HDR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "res", "assets", "environment", "sky.hdr"
)


def read_rle(path):
    with open(path, "rb") as fh:
        data = fh.read()

    if not data.startswith(b"#?RADIANCE") and not data.startswith(b"#?RGBE"):
        raise SystemExit("bad magic")

    pos = data.index(b"\n") + 1
    fmt = None
    while True:
        end = data.index(b"\n", pos)
        line = data[pos:end]
        pos = end + 1
        if line == b"":
            break
        if line.startswith(b"FORMAT="):
            fmt = line.split(b"=")[1].decode()
    if fmt != "32-bit_rle_rgbe":
        raise SystemExit("unexpected FORMAT: %r" % fmt)

    end = data.index(b"\n", pos)
    res = data[pos:end].decode()
    pos = end + 1
    parts = res.split()
    if parts[0] != "-Y" or parts[2] != "+X":
        raise SystemExit("unexpected resolution line: %r" % res)
    height = int(parts[1])
    width = int(parts[3])

    pixels = []
    for y in range(height):
        b0, b1, b2, b3 = struct.unpack_from("BBBB", data, pos)
        pos += 4
        if b0 != 2 or b1 != 2:
            raise SystemExit("scanline %d is not new-style RLE" % y)
        scan_w = (b2 << 8) | b3
        if scan_w != width:
            raise SystemExit("scanline %d width mismatch %d != %d" % (y, scan_w, width))
        comps = [bytearray() for _ in range(4)]
        for ci in range(4):
            got = 0
            while got < width:
                count = data[pos]
                pos += 1
                if count > 128:
                    n = count - 128
                    val = data[pos]
                    pos += 1
                    comps[ci].extend([val] * n)
                    got += n
                else:
                    n = count
                    if n == 0:
                        raise SystemExit("zero-length literal run, scanline %d" % y)
                    comps[ci].extend(data[pos:pos + n])
                    pos += n
                    got += n
            if got != width:
                raise SystemExit(
                    "scanline %d comp %d decoded %d != %d" % (y, ci, got, width)
                )
        pixels.append(comps)

    trailing = len(data) - pos
    return width, height, pixels, trailing


def rgbe_to_float(r, g, b, e):
    if e == 0:
        return (0.0, 0.0, 0.0)
    f = math.ldexp(1.0, e - (128 + 8))
    return (r * f, g * f, b * f)


def main():
    width, height, pixels, trailing = read_rle(HDR)
    print("decoded OK: %dx%d, trailing bytes=%d" % (width, height, trailing))

    mx = 0.0
    total = 0.0
    for comps in pixels:
        for x in range(0, width, 8):
            r, g, b = rgbe_to_float(comps[0][x], comps[1][x], comps[2][x], comps[3][x])
            lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            mx = max(mx, lum)
            total += lum
    print("max luminance = %.1f (sun disk should be >100)" % mx)
    print("avg sampled luminance = %.3f" % (total / (height * (width / 8))))

    try:
        from PIL import Image
    except ImportError:
        return
    img = Image.new("RGB", (width, height))
    px = img.load()
    for y, comps in enumerate(pixels):
        for x in range(width):
            r, g, b = rgbe_to_float(comps[0][x], comps[1][x], comps[2][x], comps[3][x])
            # simple Reinhard tonemap + gamma for preview only
            def tm(c):
                c = c / (1.0 + c)
                return int(max(0, min(255, pow(c, 1 / 2.2) * 255)))
            px[x, y] = (tm(r), tm(g), tm(b))
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/sky_preview.png"
    img.save(out)
    print("preview ->", out)


if __name__ == "__main__":
    main()
