"""Builds the folder the Godot port runs from (`gamedata/`):

  gamedata/_internal/  assets extracted from the .exe (sprites, rooms, fonts, sounds, ...)
  gamedata/data/       the original data/ folder, with GIFs converted to PNG
                       (multi-frame GIFs become a horizontal strip + "<file>.png.frames")

Usage: tools/.venv/bin/python -I prepare_gamedata.py <extracted_dir> <original_data_dir> <gamedata_dir>
"""
import shutil
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from PIL import Image, ImageSequence

INTERNAL = ["index.json", "settings.json", "scripts_raw.json", "room_order.json", "paths.json", "constants.json",
            "sprites", "backgrounds", "fonts", "sounds", "rooms"]


def gif_to_png(args):
    src, dst = args
    with Image.open(src) as im:
        frames = [f.convert("RGBA") for f in ImageSequence.Iterator(im)]
    if len(frames) == 1:
        frames[0].save(dst)
    else:
        w, h = frames[0].size
        strip = Image.new("RGBA", (w * len(frames), h))
        for i, f in enumerate(frames):
            strip.paste(f, (i * w, 0))
        strip.save(dst)
        Path(str(dst) + ".frames").write_text(str(len(frames)))
    return src


def main():
    extracted, data, out = map(Path, sys.argv[1:4])
    internal = out / "_internal"
    internal.mkdir(parents=True, exist_ok=True)
    for name in INTERNAL:
        s, d = extracted / name, internal / name
        if d.exists():
            shutil.rmtree(d) if d.is_dir() else d.unlink()
        shutil.copytree(s, d) if s.is_dir() else shutil.copy2(s, d)
    objs = internal / "objects"
    objs.mkdir(exist_ok=True)
    for f in (extracted / "objects").glob("*.json"):
        shutil.copy2(f, objs / f.name)

    # Original data folder: copy everything except GIFs, which are converted.
    jobs = []
    for f in data.rglob("*"):
        rel = f.relative_to(data)
        dst = out / "data" / rel
        if f.is_dir():
            dst.mkdir(parents=True, exist_ok=True)
        elif f.suffix.lower() == ".gif":
            dst.parent.mkdir(parents=True, exist_ok=True)
            png = dst.with_suffix(".png")
            if not png.exists() or png.stat().st_mtime < f.stat().st_mtime:
                jobs.append((f, png))
        else:
            dst.parent.mkdir(parents=True, exist_ok=True)
            if not dst.exists() or dst.stat().st_size != f.stat().st_size:
                shutil.copy2(f, dst)
    with ProcessPoolExecutor() as ex:
        for _ in ex.map(gif_to_png, jobs, chunksize=64):
            pass
    print(f"gamedata ready at {out} ({len(jobs)} GIFs converted)")


if __name__ == "__main__":
    main()
