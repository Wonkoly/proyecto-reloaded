"""Compara el paisaje de los mapas extraídos (renderizado por Godot con tools/render_mapa.gd) con el
del original dibujado aquí desde los datos de GM8 (fondos + tiles en su orden de dibujo).

    ../tools/.venv/bin/python -I tools/comparar_mapas.py <carpeta_renders> [mapa ...] [--diff carpeta]

Necesita Pillow (el venv de tools/ del repo). Imprime los píxeles distintos de cada mapa y, con --diff,
guarda para cada mapa con diferencias una imagen original | extraído | diferencias.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageChops

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extraer import snake  # noqa: E402  (mismos nombres de archivo que el extractor)

NATIVO = Path(__file__).resolve().parent.parent
INTERNO = NATIVO.parent / "gamedata" / "_internal"


_imgs: dict[str, Image.Image | None] = {}


def imagen(bg: str) -> Image.Image | None:
    if bg not in _imgs:
        p = INTERNO / "backgrounds" / f"{bg}.png"
        _imgs[bg] = Image.open(p).convert("RGBA") if p.exists() else None
    return _imgs[bg]


def original(room: dict) -> Image.Image:
    """El paisaje como lo dibuja GM8: fondos visibles (no de primer plano) repetidos desde su posición
    en toda la room, y luego los tiles de mayor a menor depth en el orden de la room."""
    w, h = room["width"], room["height"]
    lienzo = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for b in room["backgrounds"]:
        im = imagen(b["bg"]) if b.get("visible") and b.get("bg") else None
        if im is None:
            continue
        bw, bh = im.size
        xs = range(b["x"] % bw - bw, w, bw) if b.get("tile_h") else [b["x"]]
        ys = range(b["y"] % bh - bh, h, bh) if b.get("tile_v") else [b["y"]]
        for y in ys:
            for x in xs:
                _pega(lienzo, im, x, y)
    for t in sorted(room["tiles"], key=lambda t: -t["depth"]):
        im = imagen(t["bg"])
        if im is None:
            continue
        rec = im.crop((t["tx"], t["ty"], t["tx"] + t["w"], t["ty"] + t["h"]))
        if t["xscale"] != 1 or t["yscale"] != 1:
            rec = rec.resize((max(1, round(abs(t["w"] * t["xscale"]))), max(1, round(abs(t["h"] * t["yscale"])))),
                             Image.NEAREST)
            if t["xscale"] < 0:
                rec = rec.transpose(Image.FLIP_LEFT_RIGHT)
            if t["yscale"] < 0:
                rec = rec.transpose(Image.FLIP_TOP_BOTTOM)
        if t["blend"] != 0xFFFFFFFF:
            c = t["blend"]
            tinte = Image.new("RGBA", rec.size, (c & 255, (c >> 8) & 255, (c >> 16) & 255, (c >> 24) & 255))
            rec = ImageChops.multiply(rec, tinte)
        x = t["x"] + (t["w"] * t["xscale"] if t["xscale"] < 0 else 0)
        y = t["y"] + (t["h"] * t["yscale"] if t["yscale"] < 0 else 0)
        _pega(lienzo, rec, int(x), int(y))
    return lienzo


def _pega(lienzo: Image.Image, im: Image.Image, x: int, y: int) -> None:
    """alpha_composite admitiendo posiciones fuera del lienzo."""
    x0, y0 = max(0, -x), max(0, -y)
    if x0 >= im.width or y0 >= im.height or x >= lienzo.width or y >= lienzo.height:
        return
    lienzo.alpha_composite(im.crop((x0, y0, im.width, im.height)), (max(0, x), max(0, y)))


def comparar(nombre: str, renders: Path, diffs: Path | None) -> int | None:
    room_json = INTERNO / "rooms" / f"{nombre}.json"
    render = renders / f"{snake(nombre)}.png"
    if not render.exists():
        return None
    room = json.loads(room_json.read_text(encoding="utf-8"))
    a = original(room)
    b = Image.open(render).convert("RGBA")
    if a.size != b.size:
        b = b.crop((0, 0, a.width, a.height))
    # Se compara el color visible (sobre negro) para no contar diferencias de píxeles invisibles.
    negro = Image.new("RGBA", a.size, (0, 0, 0, 255))
    ra = Image.alpha_composite(negro, a).convert("RGB")
    rb = Image.alpha_composite(negro, b).convert("RGB")
    d = ImageChops.difference(ra, rb).convert("L").point(lambda v: 255 if v > 8 else 0)
    n = d.histogram()[255]
    if n and diffs:
        diffs.mkdir(parents=True, exist_ok=True)
        hoja = Image.new("RGB", (a.width * 3 + 8, a.height), (255, 0, 0))
        hoja.paste(ra, (0, 0))
        hoja.paste(rb, (a.width + 4, 0))
        hoja.paste(Image.merge("RGB", (d, Image.new("L", d.size), Image.new("L", d.size))), (a.width * 2 + 8, 0))
        hoja.save(diffs / f"{snake(nombre)}.png")
    return n


def main() -> None:
    args = sys.argv[1:]
    diffs = None
    if "--diff" in args:
        i = args.index("--diff")
        diffs = Path(args[i + 1])
        del args[i:i + 2]
    renders = Path(args[0])
    nombres = args[1:] or sorted(p.stem for p in (INTERNO / "rooms").glob("*.json"))
    malos = 0
    for n in nombres:
        r = comparar(n, renders, diffs)
        if r is None:
            continue
        if r:
            malos += 1
        print(f"{n}: {'igual' if not r else f'{r} píxeles distintos'}")
    print(f"{malos} mapas con diferencias")


if __name__ == "__main__":
    main()
