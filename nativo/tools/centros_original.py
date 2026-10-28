"""Centros Pokémon del original → data/extraido/centros.json

- AdjustmentsRoom: entrar a ciertos mapas registra el último centro (global.lastcenter = N). Solo se
  toman las asignaciones sin otra condición que el mapa (room = A o room = B...).
- GoCentroPokemon: al perder, el jugador aparece en el centro N (lugar, xx, yy, mira) y su salida lleva
  a room_out (outx, outy) con global.index_place.

Solo biblioteca estándar.
"""
from __future__ import annotations

import re


def centros(juego) -> dict:
    rooms = juego.rooms
    por_mapa: dict[str, int] = {}
    ajustes = juego.script("AdjustmentsRoom")
    for cond, n in re.findall(r"if\(((?:room=\(\d+\)(?: \|\| )?)+)\)\s*\{?\s*global\.lastcenter=\(?(-?\d+)\)?;", ajustes):
        for r in re.findall(r"room=\((\d+)\)", cond):
            if 0 <= int(r) < len(rooms) and rooms[int(r)]:
                por_mapa.setdefault(rooms[int(r)], int(n))
    destinos: dict[str, dict] = {}
    go = juego.script("GoCentroPokemon")
    for n, cuerpo in re.findall(r"if\(global\.lastcenter=\(?(-?\d+)\)?(?: \|\|[^)]*\))?\)\{(.*?)\}", go):
        def campo(nombre: str):
            m = re.search(rf"global\.{nombre}=\(?(-?\d+)\)?;", cuerpo)
            return int(m.group(1)) if m else None
        lugar = campo("lugar")
        if lugar is None or not (0 <= lugar < len(rooms)):
            continue
        d = {"mapa": rooms[lugar], "x": campo("xx"), "y": campo("yy"), "mira": campo("mira") or 2,
             "indice_lugar": campo("index_place") or 0}
        salida = campo("room_out")
        if salida is not None and 0 <= salida < len(rooms):
            d.update(salida_mapa=rooms[salida], salida_x=campo("outx") or 0, salida_y=campo("outy") or 0)
        if d["x"] is None:  # casa: global.homeDescansoX/Y (la cama)
            d.update(x=89, y=147)
        destinos[n] = d
    return {"por_mapa": por_mapa, "destinos": destinos}
