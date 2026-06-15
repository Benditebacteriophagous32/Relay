#!/usr/bin/env python3
"""
Generate Relay's app icon: a Liquid-Glass-styled macOS squircle.

Design: a deep indigo→violet gradient squircle (the macOS superellipse shape),
a frosted translucent "glass" speech bubble floating above it with a soft drop
shadow and a bright specular sheen, and three subtle dots inside (a live chat).
Rendered at 4x supersample for crisp edges, then downsampled to every size the
AppIcon set needs.

Usage:  python3 scripts/make-icon.py  RelayNative/Assets.xcassets/AppIcon.appiconset
"""
import sys, os, json
from PIL import Image, ImageDraw, ImageFilter

SS = 4                      # supersample factor
M = 1024                    # master logical size
N = M * SS                  # render size


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def superellipse_mask(size, inset, n=5.0):
    """A macOS-style continuous-corner squircle mask (white on black)."""
    img = Image.new("L", (size, size), 0)
    px = img.load()
    cx = cy = size / 2.0
    r = (size - 2 * inset) / 2.0
    for y in range(size):
        ny = (y - cy) / r
        if abs(ny) > 1.05:
            continue
        for x in range(size):
            nx = (x - cx) / r
            if abs(nx) ** n + abs(ny) ** n <= 1.0:
                px[x, y] = 255
    return img


def vertical_gradient(size, top, bottom):
    base = Image.new("RGB", (1, size))
    for y in range(size):
        base.putpixel((0, y), lerp(top, bottom, y / (size - 1)))
    return base.resize((size, size))


def diagonal_gradient(size, c0, c1, c2):
    """Three-stop gradient along the top-left → bottom-right diagonal."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            if t < 0.5:
                col = lerp(c0, c1, t / 0.5)
            else:
                col = lerp(c1, c2, (t - 0.5) / 0.5)
            px[x, y] = col
    return img


def render_master():
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))

    # --- squircle body: premium indigo → violet → soft magenta ---------------
    inset = int(N * 0.085)                       # small full-bleed margin
    body_mask = superellipse_mask(N, inset)
    grad = diagonal_gradient(N, (108, 99, 255), (86, 64, 214), (158, 92, 220))
    body = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    body.paste(grad, (0, 0), body_mask)

    # top sheen: a brighter arc across the upper third (glass on the surface)
    sheen = Image.new("L", (N, N), 0)
    sd = ImageDraw.Draw(sheen)
    sd.ellipse([int(N * -0.25), int(N * -0.55), int(N * 1.25), int(N * 0.45)], fill=70)
    sheen = sheen.filter(ImageFilter.GaussianBlur(N * 0.04))
    white = Image.new("RGBA", (N, N), (255, 255, 255, 255))
    sheen_layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    sheen_layer.paste(white, (0, 0), Image.composite(sheen, Image.new("L", (N, N), 0), body_mask))
    body = Image.alpha_composite(body, sheen_layer)

    img = Image.alpha_composite(img, body)

    # --- frosted glass speech bubble -----------------------------------------
    # bubble geometry
    bx0, by0 = int(N * 0.245), int(N * 0.255)
    bx1, by1 = int(N * 0.755), int(N * 0.665)
    radius = int((by1 - by0) * 0.46)

    bubble_shape = Image.new("L", (N, N), 0)
    bd = ImageDraw.Draw(bubble_shape)
    bd.rounded_rectangle([bx0, by0, bx1, by1], radius=radius, fill=255)
    # tail (lower-left), drawn as a triangle then unioned
    tail = [(int(N * 0.345), by1 - int(N * 0.01)),
            (int(N * 0.345), by1 + int(N * 0.085)),
            (int(N * 0.445), by1 - int(N * 0.01))]
    bd.polygon(tail, fill=255)

    # soft, diffuse drop shadow so the bubble floats (light + violet-tinted,
    # never a hard grey slab under the glass)
    shadow = bubble_shape.filter(ImageFilter.GaussianBlur(N * 0.045))
    sh = shadow.point(lambda v: int(v * 0.26))
    off = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    off.paste(Image.new("RGBA", (N, N), (38, 22, 78, 255)), (0, int(N * 0.018)), sh)
    img = Image.alpha_composite(img, off)

    # frosted glass fill: flat, luminous near-white across the whole bubble
    glass_layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    glass_layer.paste(Image.new("RGBA", (N, N), (255, 255, 255, 255)), (0, 0), bubble_shape)
    img = Image.alpha_composite(img, glass_layer)

    # one soft elliptical sheen in the upper bubble (glass catching light),
    # clipped to the bubble so there's no hard band
    sheen2 = Image.new("L", (N, N), 0)
    s2 = ImageDraw.Draw(sheen2)
    s2.ellipse([bx0 + int(N * 0.02), by0 - int(N * 0.02),
                bx1 - int(N * 0.02), by0 + int((by1 - by0) * 0.62)], fill=255)
    sheen2 = sheen2.filter(ImageFilter.GaussianBlur(N * 0.03))
    sheen2 = sheen2.point(lambda v: int(v * 0.18))
    sheen2 = Image.composite(sheen2, Image.new("L", (N, N), 0), bubble_shape)
    sheen2_layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    sheen2_layer.paste(Image.new("RGBA", (N, N), (255, 255, 255, 255)), (0, 0), sheen2)
    img = Image.alpha_composite(img, sheen2_layer)

    # --- three dots inside (a live conversation) -----------------------------
    cy = (by0 + by1) // 2
    dot_r = int(N * 0.028)
    gap = int(N * 0.085)
    cx = (bx0 + bx1) // 2
    dots = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dots)
    for k in (-1, 0, 1):
        dcx = cx + k * gap
        dd.ellipse([dcx - dot_r, cy - dot_r, dcx + dot_r, cy + dot_r],
                   fill=(96, 78, 220, 235))
    img = Image.alpha_composite(img, dots)

    # downsample master to crisp 1024
    return img.resize((M, M), Image.LANCZOS)


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    master = render_master()

    # macOS AppIcon required pixel sizes
    sizes = {16, 32, 64, 128, 256, 512, 1024}
    files = {}
    for s in sorted(sizes):
        f = f"icon_{s}.png"
        master.resize((s, s), Image.LANCZOS).save(os.path.join(out, f))
        files[s] = f
    master.save(os.path.join(out, "icon_1024.png"))

    # Contents.json: every idiom/scale entry macOS expects
    entries = [
        (16, 1, 16), (16, 2, 32),
        (32, 1, 32), (32, 2, 64),
        (128, 1, 128), (128, 2, 256),
        (256, 1, 256), (256, 2, 512),
        (512, 1, 512), (512, 2, 1024),
    ]
    images = [{
        "size": f"{pt}x{pt}",
        "idiom": "mac",
        "filename": files[px],
        "scale": f"{scale}x",
    } for (pt, scale, px) in entries]
    contents = {"images": images, "info": {"version": 1, "author": "xcode"}}
    with open(os.path.join(out, "Contents.json"), "w") as fh:
        json.dump(contents, fh, indent=2)
    print(f"✓ wrote icon set ({len(files)} pngs) to {out}")


if __name__ == "__main__":
    main()
