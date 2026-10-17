"""Converts GameMaker 8 .gmspr files (magic 1234321, zlib body, BGRA frames) to PNG strips.

Each sprite becomes one horizontal strip <name>.png, and all origins/frame sizes go to
index.json so the Godot importer can slice them into SpriteFrames.

Usage: python3 -I gmspr2png.py <dir with .gmspr> <out_dir>
"""
import json, struct, sys, zlib
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

def write_png(path, w, h, rgba):
    raw = b"".join(b"\0" + rgba[y * w * 4:(y + 1) * w * 4] for y in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))

def convert(args):
    src, out = args
    b = src.read_bytes()
    magic, _ = struct.unpack("<II", b[:8])
    if magic != 1234321:
        return src.stem, None
    d = zlib.decompress(b[8:])
    _ver, ox, oy, n = struct.unpack("<IiiI", d[:16])
    pos, frames = 16, []
    for _ in range(n):
        _fv, w, h, ln = struct.unpack("<IIII", d[pos:pos + 16])
        px = bytearray(d[pos + 16:pos + 16 + ln])
        px[0::4], px[2::4] = px[2::4], px[0::4]  # BGRA -> RGBA
        frames.append((w, h, bytes(px)))
        pos += 16 + ln
    if not frames:
        return src.stem, {"frames": 0, "origin": [ox, oy]}
    w, h = frames[0][0], frames[0][1]
    # Horizontal strip: row y of the strip is row y of every frame side by side.
    strip = b"".join(b"".join(f[2][y * w * 4:(y + 1) * w * 4] for f in frames) for y in range(h))
    write_png(out / f"{src.stem}.png", w * len(frames), h, strip)
    return src.stem, {"frames": len(frames), "w": w, "h": h, "origin": [ox, oy]}

if __name__ == "__main__":
    src_dir, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    files = sorted(src_dir.glob("*.gmspr"))
    with ProcessPoolExecutor() as ex:
        index = dict(ex.map(convert, [(f, out) for f in files], chunksize=64))
    (out / "index.json").write_text(json.dumps(index, indent=1))
    bad = [k for k, v in index.items() if v is None]
    print(f"converted {len(files) - len(bad)} / {len(files)}; bad magic: {bad[:10]}")
