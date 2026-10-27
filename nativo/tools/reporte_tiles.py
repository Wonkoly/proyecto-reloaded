"""Reporte de los tiles de los mapas del original → docs/reporte_tiles.md

    python3 tools/reporte_tiles.py

Por mapa: las capas en que quedan (capas_tiles.py) y lo raro del original: tiles que nunca se ven
(tapados por completo), duplicados exactos, tiles fuera del mapa, recortes que se salen de la imagen
del tileset y tilesets que no existen. Solo biblioteca estándar.
"""
from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import capas_tiles  # noqa: E402
import mapas_original  # noqa: E402

NATIVO = Path(__file__).resolve().parent.parent
REPO = NATIVO.parent


def revisar(room: dict, juego: mapas_original.Juego) -> dict:
    m = juego.mascaras
    w, h = room["width"], room["height"]
    orden = sorted(room["tiles"], key=lambda t: -t["depth"])
    sin_tileset = [t for t in orden if m.imagen(t["bg"]) is None]
    validos = [t for t in orden if m.imagen(t["bg"]) is not None]
    fuera_imagen = []
    for t in validos:
        iw, ih = m.tam(t["bg"])
        if t["tx"] < 0 or t["ty"] < 0 or t["tx"] + t["w"] > iw or t["ty"] + t["h"] > ih:
            fuera_imagen.append(t)
    fuera_mapa = []
    for t in validos:
        x0, y0, x1, y1 = capas_tiles._rect(t)
        if x1 <= 0 or y1 <= 0 or x0 >= w or y0 >= h:
            fuera_mapa.append(t)
    claves = Counter((t["bg"], t["x"], t["y"], t["tx"], t["ty"], t["w"], t["h"], t["depth"], t["xscale"],
                      t["yscale"], t["blend"]) for t in validos)
    duplicados = sum(n - 1 for n in claves.values() if n > 1)
    ocultos = capas_tiles.invisibles(m, validos, juego.tiles_ref)
    capas = []
    for arriba in (False, True):
        grupo = [t for t in validos if (t["depth"] < mapas_original.DEPTH_TILES_ARRIBA) == arriba and t["id"] not in ocultos]
        if grupo:
            capas += [("Arriba/" if arriba else "") + c.nombre
                      for c in capas_tiles.repartir(m, juego, room["instances"], grupo, juego.tiles_ref, mapas_original.caja)]
    return {"tiles": len(orden), "capas": capas, "ocultos": len(ocultos), "duplicados": duplicados,
            "fuera_mapa": [t["id"] for t in fuera_mapa], "fuera_imagen": [t["id"] for t in fuera_imagen],
            "sin_tileset": sorted({t["bg"] for t in sin_tileset})}


def main() -> None:
    juego = mapas_original.Juego(REPO / "extracted", REPO / "gamedata")
    filas = []
    tot = Counter()
    for ruta in sorted((REPO / "extracted" / "rooms").glob("*.json")):
        room = json.loads(ruta.read_text(encoding="utf-8"))
        r = revisar(room, juego)
        filas.append((room["name"], r))
        tot["tiles"] += r["tiles"]
        tot["ocultos"] += r["ocultos"]
        tot["duplicados"] += r["duplicados"]
        tot["fuera_mapa"] += len(r["fuera_mapa"])
        tot["fuera_imagen"] += len(r["fuera_imagen"])
        tot["capas"] += len(r["capas"])
    n = len(filas)
    ncapas = sorted(len(r["capas"]) for _, r in filas)
    out = [
        "# Tiles de los mapas",
        "",
        "Generado por `tools/reporte_tiles.py`. Cómo se reparten las capas: `tools/capas_tiles.py`.",
        "",
        "## Resumen",
        f"- {n} mapas, {tot['tiles']} tiles.",
        f"- Capas por mapa (Debajo + Arriba): mediana {ncapas[n // 2]}, máximo {ncapas[-1]}.",
        f"- **Tiles que nunca se ven** (tapados por completo por otros; no se exportan): {tot['ocultos']}"
        f" ({tot['ocultos'] * 100 / tot['tiles']:.1f} %). De ellos, duplicados exactos: {tot['duplicados']}.",
        f"- Tiles fuera de los límites del mapa: {tot['fuera_mapa']}.",
        f"- Tiles cuyo recorte se sale de la imagen del tileset: {tot['fuera_imagen']}.",
        "",
        "## Por mapa",
        "Solo los mapas con algo raro en el original o con más de 8 capas.",
        "",
        "| Mapa | Tiles | Capas | Nunca se ven | Duplicados | Fuera del mapa | Recorte fuera de la imagen | Tileset inexistente |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for nombre, r in filas:
        raro = r["fuera_mapa"] or r["fuera_imagen"] or r["sin_tileset"] or len(r["capas"]) > 8
        if not raro and not r["ocultos"]:
            continue
        if not raro and r["ocultos"] < 200:
            continue
        out.append(f"| {nombre} | {r['tiles']} | {len(r['capas'])} | {r['ocultos']} | {r['duplicados']} | "
                   f"{len(r['fuera_mapa'])} | {', '.join(map(str, r['fuera_imagen'][:5]))}"
                   f"{'…' if len(r['fuera_imagen']) > 5 else ''} | {', '.join(r['sin_tileset'])} |")
    destino = NATIVO / "docs" / "reporte_tiles.md"
    destino.write_text("\n".join(out) + "\n", encoding="utf-8")
    print("\n".join(out[5:11]))
    print(f"→ {destino.relative_to(REPO)}")


if __name__ == "__main__":
    main()
