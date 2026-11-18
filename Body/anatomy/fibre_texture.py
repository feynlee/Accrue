"""The grain drawn on a working muscle: fine dark lines along the fibres, as a tile.

    python fibre_texture.py muscle-fibres.png

The tile repeats in both directions; export_app.py lays it on every muscle with u across
the fibres and v along them (FIBRE_PITCH metres per tile). It is gray on white and the
app multiplies it with the highlight colour.
"""
import struct
import sys
import zlib

import numpy as np

SIZE = 256
rng = np.random.default_rng(7)
v, u = np.mgrid[0:SIZE, 0:SIZE] / SIZE


def waver(strength, waves=(1, 2, 3)):
    """A slow drift along the fibre that comes back to where it began."""
    return sum(strength / k * np.sin(2 * np.pi * (k * v + rng.random())) for k in waves)


def lines(count, width, depth, drift):
    """`count` lines across the tile, unevenly spaced, each fading in and out along its length."""
    out = np.zeros_like(u)
    at = (np.arange(count) + rng.uniform(-0.3, 0.3, count)) / count
    for x in at:
        d = (u - x - waver(drift) + 0.5) % 1.0 - 0.5
        fade = 0.65 + 0.35 * np.sin(2 * np.pi * (rng.integers(1, 3) * v + rng.random()))
        out = np.maximum(out, depth * rng.uniform(0.7, 1.0) * fade * np.exp(-(d / width) ** 2))
    return out


# the furrows between the bundles of fibres, then the fibres inside each bundle
dark = np.maximum(lines(5, 0.022, 0.5, 0.012), lines(22, 0.008, 0.16, 0.006))
tile = np.clip(1.0 - dark, 0, 1)
rows = (np.round(tile * 255).astype(np.uint8))


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


raw = b"".join(b"\x00" + r.tobytes() for r in rows)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 0, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
print("wrote", sys.argv[1], len(png), "bytes, mean", round(float(tile.mean()), 3))
