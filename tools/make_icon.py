"""Draws the ForeverFlip icon (ForeverFlip/Media/Logo.tga) shown in the game's AddOns list.

A gold coin with two arrows turning around it: a coin being flipped. The image is drawn with plain
Python (no image library): 64 x 64 pixels, 32-bit TGA with alpha, which the game reads as is.

    python tools/make_icon.py
"""

import math
import pathlib
import struct

SIZE = 64
SAMPLES = 4  # anti-aliasing: 4 x 4 samples per pixel
OUT = pathlib.Path(__file__).resolve().parent.parent / "ForeverFlip" / "Media" / "Logo.tga"

RIM = (120, 72, 10)
GOLD_DARK = (196, 132, 24)
GOLD = (246, 196, 62)
GOLD_LIGHT = (255, 236, 150)
ARROW = (70, 200, 120)
ARROW_EDGE = (20, 70, 40)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def coin(x, y):
    """Colour of the coin at (x, y) in -1..1, or None outside it."""
    r = math.hypot(x, y)
    if r > 0.74:
        return None
    if r > 0.66:
        return RIM
    # Light from the top left.
    shade = max(0.0, min(1.0, 0.55 - 0.45 * (x + y) / 0.66))
    face = mix(GOLD_DARK, GOLD_LIGHT, shade) if r < 0.52 else mix(GOLD_DARK, GOLD, shade)
    if 0.50 < r < 0.54:
        return GOLD_DARK  # the inner ring of the coin
    # An "F" stamped on the face.
    if -0.20 <= x <= -0.08 and -0.30 <= y <= 0.30:
        return GOLD_DARK
    if -0.20 <= x <= 0.22 and -0.30 <= y <= -0.18:
        return GOLD_DARK
    if -0.20 <= x <= 0.14 and -0.04 <= y <= 0.07:
        return GOLD_DARK
    return face


def arrow(x, y):
    """Colour of the two curved arrows around the coin, or None."""
    r = math.hypot(x, y)
    angle = math.degrees(math.atan2(y, x)) % 360
    band = 0.80 <= r <= 0.92
    edge = 0.78 <= r <= 0.94
    # Two arcs: 200..320 and 20..140 degrees (screen y points down), each ending in a head.
    for start, end in ((200, 320), (20, 140)):
        if start <= angle <= end:
            if band:
                return ARROW
            if edge:
                return ARROW_EDGE
        # Arrow head at the end of the arc: a triangle pointing along the circle.
        head = math.radians(end + 8)
        tip = (0.86 * math.cos(head), 0.86 * math.sin(head))
        base = math.radians(end - 6)
        left = (0.70 * math.cos(base), 0.70 * math.sin(base))
        right = (1.02 * math.cos(base), 1.02 * math.sin(base))
        if inside((x, y), tip, left, right):
            return ARROW
    return None


def inside(p, a, b, c):
    def side(p1, p2, p3):
        return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])

    d1, d2, d3 = side(p, a, b), side(p, b, c), side(p, c, a)
    neg = d1 < 0 or d2 < 0 or d3 < 0
    pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (neg and pos)


def pixel(px, py):
    total = [0.0, 0.0, 0.0]
    covered = 0
    for sy in range(SAMPLES):
        for sx in range(SAMPLES):
            x = ((px + (sx + 0.5) / SAMPLES) / SIZE) * 2 - 1
            y = ((py + (sy + 0.5) / SAMPLES) / SIZE) * 2 - 1
            colour = arrow(x, y) or coin(x, y)
            if colour:
                covered += 1
                for i in range(3):
                    total[i] += colour[i]
    if covered == 0:
        return 0, 0, 0, 0
    alpha = covered / (SAMPLES * SAMPLES)
    return tuple(int(round(c / covered)) for c in total) + (int(round(alpha * 255)),)


def main():
    rows = []
    for py in range(SIZE):
        rows.append([pixel(px, py) for px in range(SIZE)])
    # TGA type 2 (uncompressed true colour), 32 bits, origin top left (descriptor bit 5), 8 alpha bits.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    data = bytearray()
    for row in rows:
        for r, g, b, a in row:
            data += bytes((b, g, r, a))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(header + bytes(data))
    print(f"wrote {OUT} ({len(header) + len(data)} bytes)")


if __name__ == "__main__":
    main()
