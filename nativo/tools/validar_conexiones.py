#!/usr/bin/env python3
"""Valida las conexiones entre mapas sin abrir Godot (lee lo que genera tools/extraer.py).

    python3 tools/validar_conexiones.py                  # resumen en la terminal
    python3 tools/validar_conexiones.py --mapa PuebloAlba  # las salidas de un mapa con su estado
    python3 tools/validar_conexiones.py --json salida.json --markdown salida.md

Para cada salida revisa que el mapa destino exista, que el punto de llegada sea caminable (ni dentro
de una pared ni fuera del mapa), que al llegar no se quede encima de otra salida (rebote) y que haya
una de vuelta en puertas, bordes y escaleras. Después mira a qué mapas se llega desde PuebloAlba en
tres escenarios: (a) la historia al empezar, (b) todas las banderas en su valor final y (c) como (b)
ignorando surf, bici y MO.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import conexiones as cx  # noqa: E402
from mapas_original import ESTADO_HISTORIA  # noqa: E402

NATIVO = Path(__file__).resolve().parent.parent
REPO = NATIVO.parent
DATA = NATIVO / "data" / "extraido"
INICIO = "PuebloAlba"


def cargar() -> tuple[dict, dict]:
    for f in ("conexiones.json", "mapas_geometria.json"):
        if not (DATA / f).exists():
            sys.exit(f"Falta data/extraido/{f}: corre python3 tools/extraer.py --solo conexiones")
    return (json.loads((DATA / "conexiones.json").read_text(encoding="utf-8")),
            json.loads((DATA / "mapas_geometria.json").read_text(encoding="utf-8")))


def _toca(caja: tuple, r: list) -> bool:
    return caja[0] < r[2] and caja[2] > r[0] and caja[1] < r[3] and caja[3] > r[1]


def caja_jugador(x: float, y: float, margen: float = -cx.TOLERANCIA) -> tuple:
    return (x + cx.CAJA[0] - margen, y + cx.CAJA[1] - margen, x + cx.CAJA[2] + margen, y + cx.CAJA[3] + margen)


# Si al llegar la máscara se mete en una pared hasta 4 px, el jugador sale caminando (se mueve de a
# 2-4 px y Godot lo despega): no cuenta como llegar dentro de la pared.
SALE_SOLO = 4


def _penetracion(caja: tuple, r: list) -> float:
    return min(caja[2] - r[0], r[2] - caja[0], caja[3] - r[1], r[3] - caja[1])


def estado_llegada(geo: dict, x: float, y: float) -> tuple[str, str]:
    """("ok" | "fuera" | "pared" | "historia" | "agua" | "obstaculo", detalle) del jugador en (x, y)."""
    if not (0 <= x <= geo["ancho"] and 0 <= y <= geo["alto"]):
        return "fuera", f"({x:g}, {y:g}) fuera de {geo['ancho']}×{geo['alto']}"
    caja = caja_jugador(x, y)
    for r in geo["paredes"]:
        if not r[4] and _toca(caja, r) and _penetracion(caja_jugador(x, y, 0), r) > SALE_SOLO:
            return "pared", f"({x:g}, {y:g}) dentro de {r[5] or 'una pared'} en ({r[0]:g}, {r[1]:g})"
    for r in geo["paredes"]:
        if r[4] and _toca(caja, r) and cx.cumple(r[4], ESTADO_HISTORIA):
            return "historia", f"({x:g}, {y:g}) tapado al empezar la historia ({r[4]})"
    for r in geo["agua"]:
        if _toca(caja, r):
            return "agua", f"({x:g}, {y:g}) en el agua ({r[4]})"
    for r in geo["obstaculos"]:
        if _toca(caja, r):
            return "obstaculo", f"({x:g}, {y:g}) sobre un obstáculo ({r[4]})"
    return "ok", ""


def activa_al_llegar(s: dict, x: float, y: float, rej: cx.Rejilla) -> bool:
    """Si una salida que se activa sola (sin pulsar) se dispara con el jugador en (x, y)."""
    if s["activacion"] != 0:
        return False
    r = s["rect"]
    if s["por_punto"]:
        if not (r[0] < x < r[2] and r[1] < y < r[3]):
            return False
        c, _ = rej.celda_de(x, y, 0)
        return c is None or rej.duenos().get(c, s["nodo"]) == s["nodo"]
    return _toca(caja_jugador(x, y, 0), r)  # place_meeting: solape exacto


def puntos_llegada(con: dict, s: dict, rej: cx.Rejilla, zona: list[int]) -> list[tuple[float, float]]:
    """Dónde aparece el jugador: un punto, o uno por cada posición desde la que se activa (relativas)."""
    if not any(con["relativa"]):
        return [tuple(con["llegada"])]
    puntos = []
    for c in rej.celdas_salida(s):
        if zona[c] == -1:
            continue
        px, py = rej.pos(c)
        puntos.append((px + con["llegada"][0] if con["relativa"][0] else con["llegada"][0],
                       py + con["llegada"][1] if con["relativa"][1] else con["llegada"][1]))
    return sorted(set(puntos))


def validar(grafo: dict, geos: dict, mapas: list[str] | None = None) -> list[dict]:
    """Un resultado por salida: {origen, nodo, tipo, destino, estado ("ok"/"error"/"aviso"), problemas}."""
    resultados = []
    for origen in sorted(mapas or geos):
        geo = geos[origen]
        rej = cx.Rejilla(geo)
        zona = cx.zonas_mapa(rej, 0)[0]
        cons = {c["salida"]["nodo"]: c for c in grafo["conexiones"] if c["origen"] == origen}
        for s in geo["salidas"]:
            con = cons[s["nodo"]]
            problemas: list[tuple[str, str]] = []
            destino = s["destino"]
            if s["volver"]:
                if not con.get("regresos"):
                    problemas.append(("sin_entrada", "salida de interior sin ninguna puerta que entre a este mapa"))
            elif not destino:
                problemas.append(("sin_destino", "la salida no tiene destino (ROOM = -1)"))
            elif destino not in geos:
                problemas.append(("destino_inexistente", f"{destino} no es un mapa"))
            if not con["zonas"] and not problemas:
                problemas.append(("inalcanzable", "no hay ningún sitio caminable desde el que se active"))
            if destino in geos and not s["volver"]:
                dgeo = geos[destino]
                drej = cx.Rejilla(dgeo)
                puntos = puntos_llegada(con, s, rej, zona) or [tuple(con["llegada"])]
                estados = Counter()
                detalle = {}
                rebotes = []
                for x, y in puntos:
                    est, det = estado_llegada(dgeo, x, y)
                    estados[est] += 1
                    detalle.setdefault(est, det)
                    for s2 in dgeo["salidas"]:
                        if (s2["destino"] or s2["volver"]) and activa_al_llegar(s2, x, y, drej):
                            rebotes.append(f"({x:g}, {y:g}) activa {s2['nodo']} → {s2['destino'] or 'regreso'}")
                if estados["ok"] == 0:
                    # El más leve: si alguna llegada cae al agua, es una ruta de surf.
                    leve = next(e for e in ("agua", "obstaculo", "historia", "pared", "fuera") if estados[e])
                    problemas.append(("llegada_" + leve, detalle[leve]))
                if rebotes:
                    # Teletransportes/conductos que llegan a su pareja: el original no los repite
                    # (global.teletransportado, GO) y en nativo las salidas "al entrar" no se activan al
                    # aparecer encima. En los bordes, si solo rebotan algunas posiciones son esquinas.
                    if s["tipo"] in ("teletransporte", "conducto", "brecha"):
                        clase = "llega_a_pareja"
                    elif len(rebotes) < len(puntos):
                        clase = "rebote_esquina"
                    else:
                        clase = "rebote"
                    problemas.append((clase, f"{len(rebotes)}/{len(puntos)} puntos; " + rebotes[0]))
                if s["tipo"] in cx.CON_REGRESO and destino != origen:
                    vuelve = any(s2["destino"] == origen for s2 in dgeo["salidas"]) or \
                        (s["regreso"] in (1, 2) and any(s2["volver"] for s2 in dgeo["salidas"]))
                    if not vuelve:
                        problemas.append(("sin_regreso", f"{destino} no tiene salida a {origen}"))
            avisos = {"llegada_agua", "llegada_historia", "llegada_obstaculo", "sin_destino", "llega_a_pareja",
                      "rebote_esquina"}
            estado = "ok" if not problemas else "aviso" if all(p[0] in avisos for p in problemas) else "error"
            resultados.append({"origen": origen, "nodo": s["nodo"], "tipo": s["tipo"],
                               "destino": destino or ("regreso" if s["volver"] else ""), "estado": estado,
                               "requisitos": con["requisitos"], "problemas": problemas})
    return resultados


# ---------------------------------------------------------------------------------------------
# Alcanzabilidad

def zonas_inicio(grafo: dict) -> list[int]:
    """Las zonas de PuebloAlba a las que se llega saliendo de la casa del protagonista (Home_1)."""
    for con in grafo["conexiones"]:
        if con["origen"] == "Home_1" and con["destino"] == INICIO and con["zonas"]:
            return sorted({b for _, b in con["zonas"]})
    zonas = [z for z in grafo["zonas"] if z["mapa"] == INICIO and not z["requiere"]]
    return [max(zonas, key=lambda z: z["celdas"])["id"]]


def escenarios(carpeta_scripts: Path) -> dict[str, tuple[dict, set | None]]:
    finales = cx.valores_finales(carpeta_scripts)
    return {"a": (dict(ESTADO_HISTORIA), set()), "b": (finales, set()), "c": (finales, None)}


def entradas_por_script(carpeta_scripts: Path, rooms: list[str]) -> dict[str, list[str]]:
    """Mapa → scripts del original que mandan ahí (global.lugar = (N) o room_goto) sin ser una salida
    convertida (eventos, NPCs, vehículos, menús)."""
    patron = re.compile(r"(?:global\.lugar\s*=\s*|room_goto\s*\()\((\d+)\)")
    convertidos = {"CambiosWorldRooms", "CambiosSpecialRooms"}
    out: dict[str, list[str]] = defaultdict(list)
    for f in sorted(carpeta_scripts.glob("*.gml")):
        if f.stem in convertidos:
            continue
        for n in set(patron.findall(f.read_text(encoding="utf-8", errors="replace"))):
            if int(n) < len(rooms):
                out[rooms[int(n)]].append(f.stem)
    return out


def inalcanzables(grafo: dict, geos: dict, vistas: set[int], banderas: dict, capacidades: set | None,
                  por_script: dict[str, list[str]]) -> dict[str, str]:
    """Los mapas a los que no se llega y la razón probable."""
    zonas = grafo["zonas"]
    mapas_vistos = {zonas[z]["mapa"] for z in vistas}
    entradas: dict[str, list] = defaultdict(list)
    for con in grafo["conexiones"]:
        if con["destino"] == "@regreso":  # obj_out solo devuelve a donde ya se estuvo
            continue
        for a, b in con["zonas"]:
            if zonas[b]["mapa"] != con["origen"]:
                entradas[zonas[b]["mapa"]].append((con, a, b))
    razones: dict[str, str] = {}
    cadena: dict[str, set] = {}
    for mapa in sorted(grafo["mapas"]):
        if mapa in mapas_vistos:
            continue
        posibles = entradas.get(mapa, [])
        if not posibles:
            scripts = por_script.get(mapa, [])
            if not geos[mapa]["salidas"] and not scripts:
                razones[mapa] = "no es un mapa del mundo (pantalla, menú o sala sin salidas)"
            elif scripts:
                razones[mapa] = "solo se entra por un evento: " + ", ".join(scripts[:3]) + ("…" if len(scripts) > 3 else "")
            else:
                razones[mapa] = "ninguna salida ni script lleva aquí"
            continue
        motivos = Counter()
        for con, a, b in posibles:
            if a not in vistas:
                if zonas[a]["mapa"] in mapas_vistos:
                    req = ", ".join(zonas[a]["requiere"]) or "aislada: hay que cruzar agua, un obstáculo o una barrera"
                    motivos[f"la salida de {zonas[a]['mapa']} está en una parte a la que no se llega ({req})"] += 2
            elif not any(cx.cumple(con["requisitos"]["historia"], banderas, n) for n in range(0, 40)):
                motivos[f"la salida de {con['origen']} depende de la historia: {con['requisitos']['historia']}"] += 3
            elif not cx.zona_transitable(zonas[b], banderas, capacidades):
                motivos[f"se llega a una parte que pide {', '.join(zonas[b]['requiere'])}"] += 3
            else:
                motivos[f"la salida de {con['origen']} solo vale entrando por otra puerta (index_place / room_out)"] += 1
        if motivos:
            razones[mapa] = motivos.most_common(1)[0][0]
        else:
            cadena[mapa] = {zonas[a]["mapa"] for _, a, _ in posibles}
    # Los que solo tienen entradas desde otros inalcanzables: detrás de qué mapa "frontera" (con razón
    # propia) quedan.
    directas = dict(razones)
    for mapa, origenes in cadena.items():
        vistos, cola, frontera = {mapa}, list(origenes), []
        while cola and len(frontera) < 2:
            m = cola.pop(0)
            if m in vistos:
                continue
            vistos.add(m)
            if m in directas:
                frontera.append(m)
            elif por_script.get(m):
                frontera.append(f"{m} (se entra por un evento: {por_script[m][0]})")
            else:
                cola += sorted(cadena.get(m, ()))
        razones[mapa] = ("detrás de " + ", ".join(frontera)) if frontera else "solo desde mapas a los que tampoco se llega"
    return razones


def alcanzabilidad(grafo: dict, geos: dict, carpeta_scripts: Path) -> dict[str, dict]:
    inicio = zonas_inicio(grafo)
    rooms = json.loads((carpeta_scripts.parent / "index.json").read_text())["rooms"]
    por_script = entradas_por_script(carpeta_scripts, rooms)
    out = {}
    for nombre, (banderas, capacidades) in escenarios(carpeta_scripts).items():
        vistas = cx.alcanzables(grafo, inicio, banderas, capacidades)
        mapas = {grafo["zonas"][z]["mapa"] for z in vistas}
        out[nombre] = {"alcanzados": len(mapas),
                       "inalcanzables": inalcanzables(grafo, geos, vistas, banderas, capacidades, por_script)}
    return out


# ---------------------------------------------------------------------------------------------

ESCENARIOS = {"a": "historia al empezar", "b": "banderas en su valor final", "c": "(b) sin surf, bici ni MO"}


def resumen(grafo: dict, resultados: list[dict], alc: dict | None) -> str:
    lineas = [f"{len(grafo['mapas'])} mapas, {len(resultados)} salidas, {len(grafo['zonas'])} zonas"]
    estados = Counter(r["estado"] for r in resultados)
    lineas.append("salidas: " + ", ".join(f"{k} {v}" for k, v in sorted(estados.items())))
    tipos = Counter(p[0] for r in resultados for p in r["problemas"])
    lineas.append("problemas: " + ", ".join(f"{k} {v}" for k, v in tipos.most_common()))
    if alc:
        for k, v in alc.items():
            lineas.append(f"({k}) {ESCENARIOS[k]}: se llega a {v['alcanzados']} mapas, faltan {len(v['inalcanzables'])}")
    return "\n".join(lineas)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--mapa", help="solo las salidas de este mapa (nombre original)")
    ap.add_argument("--json", type=Path, help="guarda los resultados completos")
    ap.add_argument("--sin-alcance", action="store_true", help="no calcula la alcanzabilidad")
    ap.add_argument("--extraido", type=Path, default=REPO / "extracted")
    args = ap.parse_args()
    grafo, geos = cargar()
    if args.mapa:
        if args.mapa not in geos:
            sys.exit(f"No existe el mapa {args.mapa}")
        for r in validar(grafo, geos, [args.mapa]):
            req = [r["requisitos"]["historia"]] if r["requisitos"]["historia"] else []
            req += r["requisitos"]["terreno"]
            extra = "; ".join(d for _, d in r["problemas"])
            print(f"{r['estado']:6} {r['tipo']:16} → {r['destino']:24} {('requiere ' + ', '.join(req)) if req else ''} {extra}")
        return
    resultados = validar(grafo, geos)
    alc = None if args.sin_alcance else alcanzabilidad(grafo, geos, args.extraido / "scripts")
    print(resumen(grafo, resultados, alc))
    if args.json:
        args.json.write_text(json.dumps({"resultados": resultados, "alcanzabilidad": alc}, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
