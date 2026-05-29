#!/usr/bin/env python3
import os
import struct
import zlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ICONSET = os.path.join(ROOT, "Support", "AppIcon.iconset")
ICNS = os.path.join(ROOT, "Support", "AppIcon.icns")


def clamp(value, low=0, high=255):
    return max(low, min(high, value))


def blend(dst, src, alpha):
    return tuple(int(dst[i] * (1 - alpha) + src[i] * alpha) for i in range(4))


def rounded_rect_alpha(x, y, w, h, radius):
    dx = max(radius - x, 0, x - (w - radius - 1))
    dy = max(radius - y, 0, y - (h - radius - 1))
    if dx == 0 and dy == 0:
        return 1.0
    dist = (dx * dx + dy * dy) ** 0.5
    return clamp(radius + 0.5 - dist, 0, 1)


def line_alpha(px, py, ax, ay, bx, by, thickness):
    vx = bx - ax
    vy = by - ay
    wx = px - ax
    wy = py - ay
    denom = vx * vx + vy * vy
    t = 0 if denom == 0 else clamp((wx * vx + wy * vy) / denom, 0, 1)
    cx = ax + vx * t
    cy = ay + vy * t
    dist = ((px - cx) ** 2 + (py - cy) ** 2) ** 0.5
    return clamp(thickness / 2 + 1 - dist, 0, 1)


def draw_icon(size):
    if size <= 64:
        return draw_small_icon(size)

    scale = size / 1024
    pixels = []
    bg = (35, 39, 47, 255)
    accent = (88, 166, 255, 255)
    white = (245, 247, 250, 255)

    for y in range(size):
        row = []
        for x in range(size):
            sx = (x + 0.5) / scale
            sy = (y + 0.5) / scale
            shade = int(22 * (sy / 1024))
            color = (bg[0] + shade, bg[1] + shade, bg[2] + shade, 255)

            card_alpha = rounded_rect_alpha(sx - 232, sy - 292, 560, 360, 52)
            if card_alpha > 0:
                color = blend(color, (255, 255, 255, 42), card_alpha)

            front_alpha = rounded_rect_alpha(sx - 308, sy - 372, 500, 300, 44)
            if front_alpha > 0:
                color = blend(color, (255, 255, 255, 72), front_alpha)

            arrow1 = max(
                line_alpha(sx, sy, 290, 704, 734, 704, 66),
                line_alpha(sx, sy, 650, 604, 738, 704, 66),
                line_alpha(sx, sy, 650, 804, 738, 704, 66),
            )
            arrow2 = max(
                line_alpha(sx, sy, 734, 320, 290, 320, 66),
                line_alpha(sx, sy, 374, 220, 286, 320, 66),
                line_alpha(sx, sy, 374, 420, 286, 320, 66),
            )
            if arrow1 > 0:
                color = blend(color, accent, arrow1)
            if arrow2 > 0:
                color = blend(color, white, arrow2)

            row.append(color)
        pixels.append(row)
    return pixels


def draw_small_icon(size):
    pixels = []
    bg = (38, 43, 52, 255)
    accent = (80, 155, 245, 255)
    white = (244, 247, 251, 255)
    shadow = (24, 28, 36, 255)

    for y in range(size):
        row = []
        for x in range(size):
            color = bg

            margin = max(2, round(size * 0.13))
            top = round(size * 0.28)
            card_h = max(5, round(size * 0.34))
            if margin <= x < size - margin and top <= y < top + card_h:
                color = white

            back_offset = max(1, round(size * 0.10))
            if margin + back_offset <= x < size - margin + back_offset and top - back_offset <= y < top + card_h - back_offset:
                color = blend(color, (226, 233, 242, 255), 0.55)

            y_mid = round(size * 0.68)
            thickness = max(2, round(size * 0.14))
            if margin <= x <= size - margin and abs(y - y_mid) <= thickness // 2:
                color = accent

            head = max(3, round(size * 0.22))
            if size - margin - head <= x <= size - margin:
                if abs((y - y_mid) - (x - (size - margin - head))) <= thickness:
                    color = accent
                if abs((y - y_mid) + (x - (size - margin - head))) <= thickness:
                    color = accent

            if x < 1 or y < 1 or x >= size - 1 or y >= size - 1:
                color = shadow

            row.append(color)
        pixels.append(row)
    return pixels


def write_png(path, pixels):
    height = len(pixels)
    width = len(pixels[0])
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for r, g, b, a in row:
            raw.extend([r, g, b, a])

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as file:
        file.write(png)


def write_icns():
    chunks = [
        ("icp4", "icon_16x16.png"),
        ("ic11", "icon_16x16@2x.png"),
        ("icp5", "icon_32x32.png"),
        ("ic12", "icon_32x32@2x.png"),
        ("icp6", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"),
        ("ic13", "icon_128x128@2x.png"),
        ("ic08", "icon_256x256.png"),
        ("ic14", "icon_256x256@2x.png"),
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"),
    ]
    body = bytearray()
    for chunk_type, filename in chunks:
        with open(os.path.join(ICONSET, filename), "rb") as file:
            data = file.read()
        body.extend(chunk_type.encode("ascii"))
        body.extend(struct.pack(">I", len(data) + 8))
        body.extend(data)

    with open(ICNS, "wb") as file:
        file.write(b"icns")
        file.write(struct.pack(">I", len(body) + 8))
        file.write(body)


def main():
    os.makedirs(ICONSET, exist_ok=True)
    names = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    cache = {}
    for size, name in names:
        cache.setdefault(size, draw_icon(size))
        write_png(os.path.join(ICONSET, name), cache[size])
    write_icns()


if __name__ == "__main__":
    main()
