"""Grafo de conexiones entre mapas (data/extraido/conexiones.json) y su validación.

Cada mapa se pasa a una rejilla de posiciones del jugador cada CELDA px. Una posición está bloqueada
si la máscara del protagonista (ProtaMaskSprite: x-7..x+8, y-8..y+12) choca con una pared que siempre
está. Lo que se puede cruzar con algo (agua → surf, arbustos → corte, una pared o un NPC que solo está
según la historia...) son celdas "blandas" con sus requisitos.

Las celdas se juntan en zonas: las libres conectadas entre sí, y las blandas con los mismos requisitos.
Entrar a una zona pide sus requisitos. Las zonas se unen por:
- pasos: dos zonas vecinas en el mismo mapa (en los dos sentidos),
- saltos: se baja el borde (un solo sentido),
- conexiones: las salidas a otro mapa (o al mismo: teletransportes), con su condición de la historia.

Lo usan tools/extraer.py (genera el grafo) y tools/validar_conexiones.py (lo revisa).
"""

from __future__ import annotations

import math
import re
from collections import deque
from pathlib import Path

CELDA = 8
# Máscara del jugador respecto a su posición (ProtaMaskSprite: bbox 0..14 × 4..23, origen 7, 12).
CAJA = (-7, -8, 8, 12)
# Se perdona 1 px de solape con las paredes (el jugador se mueve de a 2-4 px y se arrima).
TOLERANCIA = 1
# Las salidas por los bordes se activan fuera del mapa (x > ancho-1, x < 1): se puede estar ahí.
MARGEN = 16
# Desde una celda libre el jugador puede moverse hasta media celda (pegarse a una pared): las salidas
# se activan si quedan a ese alcance (p. ej. puertas que asoman 1 px bajo el edificio).
ALCANCE = CELDA / 2 + 2
# Tipos de salida que deberían tener una de vuelta.
CON_REGRESO = ("puerta", "entrada", "borde", "escalera")


class Rejilla:
    """Las celdas de un mapa: 0 libre, 1 bloqueada, 2 blanda (con requisitos), 3 salto."""

    def __init__(self, geo: dict):
        self.geo = geo
        self.ox = self.oy = -MARGEN
        self.nx = (geo["ancho"] + 2 * MARGEN) // CELDA + 1
        self.ny = (geo["alto"] + 2 * MARGEN) // CELDA + 1
        n = self.nx * self.ny
        self.tipo = bytearray(n)
        self.requiere: dict[int, frozenset] = {}
        self.salto: dict[int, tuple[int, int]] = {}
        blandas: dict[int, set] = {}
        for x0, y0, x1, y1, cond, *_ in geo["paredes"]:
            if cond:
                for c in self.celdas_caja(x0, y0, x1, y1):
                    blandas.setdefault(c, set()).add("no:" + cond)
            else:
                for c in self.celdas_caja(x0, y0, x1, y1):
                    self.tipo[c] = 1
        for x0, y0, x1, y1, req, _cond, *_ in geo["agua"] + geo["obstaculos"] + geo["terreno"]:
            for c in self.celdas_caja(x0, y0, x1, y1):
                blandas.setdefault(c, set()).update(req.split("+"))
        for c, reqs in blandas.items():
            if self.tipo[c] != 1:
                self.tipo[c] = 2
                self.requiere[c] = frozenset(reqs)
        for x0, y0, x1, y1, dx, dy, _cond in geo["saltos"]:
            for c in self.celdas_caja(x0, y0, x1, y1):
                if self.tipo[c] != 1:
                    self.tipo[c] = 3
                    self.salto[c] = (dx, dy)

    def pos(self, c: int) -> tuple[int, int]:
        return self.ox + (c % self.nx) * CELDA, self.oy + (c // self.nx) * CELDA

    def _rango(self, a: float, b: float, origen: int, n: int) -> range:
        """Índices i con a < origen + i*CELDA < b."""
        i0 = max(0, math.floor((a - origen) / CELDA) + 1)
        i1 = min(n - 1, math.ceil((b - origen) / CELDA) - 1)
        return range(i0, i1 + 1)

    def celdas_caja(self, x0, y0, x1, y1, margen: float = -TOLERANCIA):
        """Posiciones en las que la máscara del jugador (agrandada `margen` px) toca el rectángulo."""
        for j in self._rango(y0 - CAJA[3] - margen, y1 - CAJA[1] + margen, self.oy, self.ny):
            base = j * self.nx
            for i in self._rango(x0 - CAJA[2] - margen, x1 - CAJA[0] + margen, self.ox, self.nx):
                yield base + i

    def celdas_punto(self, x0, y0, x1, y1, margen: float = 0):
        """Posiciones dentro del rectángulo (las salidas que miran el punto del jugador)."""
        for j in self._rango(y0 - margen, y1 + margen, self.oy, self.ny):
            base = j * self.nx
            for i in self._rango(x0 - margen, x1 + margen, self.ox, self.nx):
                yield base + i

    def celdas_salida(self, s: dict) -> list[int]:
        r = s["rect"]
        if not s["por_punto"]:
            return list(self.celdas_caja(*r, margen=ALCANCE))
        return [c for c in self.celdas_punto(*r) if self.duenos().get(c) == s["nodo"]]

    def duenos(self) -> dict[int, str]:
        """Qué salida "por punto" se activa en cada posición. CambiosWorldRooms prueba las salidas en
        orden y sale con la primera (exit;): en una esquina gana la que está antes. Las relativas copian
        la coordenada del jugador, así que en ese eje está dentro del mapa."""
        if not hasattr(self, "_duenos"):
            self._duenos: dict[int, str] = {}
            for s in self.geo["salidas"]:
                if not s["por_punto"]:
                    continue
                rel = s.get("relativa", (False, False))
                for c in self.celdas_punto(*s["rect"], margen=ALCANCE):
                    px, py = self.pos(c)
                    if (rel[0] and not 0 <= px < self.geo["ancho"]) or (rel[1] and not 0 <= py < self.geo["alto"]):
                        continue
                    self._duenos.setdefault(c, s["nodo"])
        return self._duenos

    def celda_de(self, x: float, y: float, radio: int = 3) -> tuple[int | None, bool]:
        """La celda transitable más cercana a (x, y) y si hubo que moverse para encontrarla."""
        i0, j0 = round((x - self.ox) / CELDA), round((y - self.oy) / CELDA)
        for r in range(radio + 1):
            mejores = []
            for j in range(j0 - r, j0 + r + 1):
                for i in range(i0 - r, i0 + r + 1):
                    if max(abs(i - i0), abs(j - j0)) != r or not (0 <= i < self.nx and 0 <= j < self.ny):
                        continue
                    c = j * self.nx + i
                    if self.tipo[c] in (0, 2):
                        px, py = self.pos(c)
                        mejores.append(((px - x) ** 2 + (py - y) ** 2, c))
            if mejores:
                return min(mejores)[1], r > 0
        return None, True

    def vecinos(self, c: int):
        i, j = c % self.nx, c // self.nx
        if i > 0:
            yield c - 1, (-1, 0)
        if i < self.nx - 1:
            yield c + 1, (1, 0)
        if j > 0:
            yield c - self.nx, (0, -1)
        if j < self.ny - 1:
            yield c + self.nx, (0, 1)


def zonas_mapa(rej: Rejilla, primer_id: int) -> tuple[list[int], list[dict], set, set]:
    """Etiqueta las zonas. Devuelve (zona por celda, zonas, pasos {(a, b)}, saltos {(a, b)})."""
    n = rej.nx * rej.ny
    zona = [-1] * n
    zonas: list[dict] = []
    for inicio in range(n):
        t = rej.tipo[inicio]
        if zona[inicio] != -1 or t in (1, 3):
            continue
        req = rej.requiere.get(inicio, frozenset())
        zid = primer_id + len(zonas)
        zona[inicio] = zid
        cola = deque([inicio])
        celdas = 0
        suma_x = suma_y = 0
        while cola:
            c = cola.popleft()
            celdas += 1
            px, py = rej.pos(c)
            suma_x += px
            suma_y += py
            for v, _ in rej.vecinos(c):
                if zona[v] == -1 and rej.tipo[v] == t and rej.requiere.get(v, frozenset()) == req:
                    zona[v] = zid
                    cola.append(v)
        zonas.append({"id": zid, "requiere": sorted(req), "celdas": celdas,
                      "centro": [round(suma_x / celdas), round(suma_y / celdas)]})
    pasos: set = set()
    saltos: set = set()
    for c in range(n):
        a = zona[c]
        if a == -1:
            if rej.tipo[c] == 3:
                _saltos_desde(rej, zona, c, saltos)
            continue
        i, j = c % rej.nx, c // rej.nx
        for v in ((c + 1) if i < rej.nx - 1 else -1, (c + rej.nx) if j < rej.ny - 1 else -1):
            if v >= 0 and zona[v] != -1 and zona[v] != a:
                pasos.add((min(a, zona[v]), max(a, zona[v])))
    return zona, zonas, pasos, saltos


def _saltos_desde(rej: Rejilla, zona: list[int], c: int, saltos: set) -> None:
    """Desde la celda de un salto: la zona de la que se llega (atrás) y a la que cae (adelante)."""
    dx, dy = rej.salto[c]
    paso = dx + dy * rej.nx
    atras = c - paso
    if not (0 <= atras < len(zona)) or zona[atras] == -1:
        return
    adelante = c
    for _ in range(8):
        adelante += paso
        if not (0 <= adelante < len(zona)) or rej.tipo[adelante] == 1:
            return
        if zona[adelante] != -1:
            if zona[adelante] != zona[atras]:
                saltos.add((zona[atras], zona[adelante]))
            return


def construir(geos: dict[str, dict], rooms: list[str]) -> dict:
    """El grafo de todos los mapas (geos: nombre original → geometría de mapas_original.escena_mapa)."""
    rejillas: dict[str, Rejilla] = {}
    zona_por_celda: dict[str, list[int]] = {}
    zonas: list[dict] = []
    pasos: list = []
    for nombre in sorted(geos):
        rej = Rejilla(geos[nombre])
        z, zs, ps, ss = zonas_mapa(rej, len(zonas))
        for zz in zs:
            zz["mapa"] = nombre
        rejillas[nombre], zona_por_celda[nombre] = rej, z
        zonas += zs
        pasos += [[a, b, "paso"] for a, b in sorted(ps)] + [[a, b, "salto"] for a, b in sorted(ss)]

    def zona_llegada(mapa: str, x: float, y: float) -> int | None:
        if mapa not in rejillas:
            return None
        c, _ = rejillas[mapa].celda_de(x, y)
        return zona_por_celda[mapa][c] if c is not None else None

    conexiones = []
    entradas_con_regreso: dict[str, list] = {}
    for nombre in sorted(geos):
        rej, zc = rejillas[nombre], zona_por_celda[nombre]
        for s in geos[nombre]["salidas"]:
            disparo = [c for c in rej.celdas_salida(s) if zc[c] != -1]
            pares: dict[tuple, None] = {}
            if not s["volver"] and s["destino"]:
                for c in disparo:
                    px, py = rej.pos(c)
                    lx = px + s["llegada"][0] if s["relativa"][0] else s["llegada"][0]
                    ly = py + s["llegada"][1] if s["relativa"][1] else s["llegada"][1]
                    destino = zona_llegada(s["destino"], lx, ly)
                    if destino is not None:
                        pares[(zc[c], destino)] = None
                if s["regreso"] in (1, 2):
                    entradas_con_regreso.setdefault(s["destino"], []).append((nombre, s, disparo))
            conexiones.append({
                "origen": nombre, "destino": "@regreso" if s["volver"] else s["destino"],
                "salida": {"nodo": s["nodo"], "tipo": s["tipo"], "rect": s["rect"], "activacion": s["activacion"]},
                "llegada": s["llegada"] if not s["volver"] else s["volver_posicion"],
                "relativa": s["relativa"], "regreso": s["regreso"], "indice": s.get("indice", -1),
                "requisitos": {"historia": s["condicion"],
                               "terreno": _menos_exigente([zonas[z]["requiere"] for z in {zc[c] for c in disparo}])},
                "zonas": [list(p) for p in pares]})
    # obj_out (volver): a donde se entró por una puerta que guardó el regreso (outx = la puerta, outy = el jugador).
    for con in conexiones:
        if con["destino"] != "@regreso":
            continue
        rej, zc = rejillas[con["origen"]], zona_por_celda[con["origen"]]
        salida_zonas = {zc[c] for c in rej.celdas_salida(_salida_de(geos, con)) if zc[c] != -1}
        regresos = set()
        for mapa, puerta, disparo in entradas_con_regreso.get(con["origen"], []):
            if con["llegada"]:
                puntos = [tuple(con["llegada"])]
            else:
                puntos = {(puerta["x"], rejillas[mapa].pos(c)[1]) for c in disparo}
            for x, y in puntos:
                z = zona_llegada(mapa, x, y)
                if z is not None:
                    regresos.add((mapa, z))
        con["regresos"] = sorted({m for m, _ in regresos})
        con["zonas"] = [[a, z] for a in sorted(salida_zonas) for _, z in sorted(regresos)]
        con["zonas_salida"] = sorted(salida_zonas)
        if con["llegada"]:  # posición fija (OutDoorStepActions): la zona según el mapa al que se vuelve
            con["fija"] = {m: z for m, z in sorted(regresos)}
    return {"celda": CELDA, "mapas": {n: {"ancho": g["ancho"], "alto": g["alto"]} for n, g in geos.items()},
            "zonas": zonas, "pasos": pasos, "conexiones": conexiones}


def _menos_exigente(requisitos: list[list[str]]) -> list[str]:
    """Lo que pide la zona más fácil desde la que se activa una salida ([] si se llega caminando)."""
    return min(requisitos, key=lambda r: (len(r), r)) if requisitos else []


def _salida_de(geos: dict, con: dict) -> dict:
    return next(s for s in geos[con["origen"]]["salidas"] if s["nodo"] == con["salida"]["nodo"])


# ---------------------------------------------------------------------------------------------
# Escenarios de la historia

def valores_finales(carpeta_scripts: Path) -> dict[str, int]:
    """El valor "final" de cada bandera de la historia ((18).x): el mayor que se le asigna en los
    scripts; si solo se le suma (+= 1), cuántas veces se suma."""
    asignados: dict[str, float] = {}
    sumas: dict[str, int] = {}
    patron = re.compile(r"\(18\)\.(\w+)(?:\[(\d+)\])?\s*(\+=|=)\s*(true|false|-?\d+(?:\.\d+)?)")
    for f in carpeta_scripts.glob("*.gml"):
        for nombre, indice, op, valor in patron.findall(f.read_text(encoding="utf-8", errors="replace")):
            clave = f"{nombre}_{indice}" if indice else nombre
            v = 1.0 if valor == "true" else 0.0 if valor == "false" else float(valor)
            if op == "=":
                asignados[clave] = max(asignados.get(clave, 0.0), v)
            else:
                sumas[clave] = sumas.get(clave, 0) + 1
    finales = {k: int(v) for k, v in asignados.items()}
    for k, n in sumas.items():
        finales[k] = max(finales.get(k, 0), n)
    return finales


class _Banderas(dict):
    """Las banderas para evaluar condiciones (h.get(nombre, 0))."""


def cumple(condicion: str, banderas: dict, lugar: int = 0) -> bool:
    if not condicion:
        return True
    try:
        return bool(eval(condicion, {"__builtins__": {}}, {"h": _Banderas(banderas), "lugar": lugar}))
    except Exception:
        return True


def zona_transitable(zona: dict, banderas: dict, capacidades: set | None, lugar: int = 0) -> bool:
    """capacidades None = se ignoran surf, bici y MO."""
    for r in zona["requiere"]:
        if r.startswith("no:"):
            if cumple(r[3:], banderas, lugar):
                return False
        elif capacidades is not None and r not in capacidades:
            return False
    return True


def alcanzables(grafo: dict, inicio: list[int], banderas: dict, capacidades: set | None) -> set[int]:
    """Las zonas a las que se llega desde las de inicio. El estado lleva lo que el juego recuerda al
    cruzar puertas: global.index_place (lugar) y global.room_out (a qué zona devuelve obj_out)."""
    zonas = grafo["zonas"]
    ady: dict[int, list[int]] = {}
    for a, b, tipo in grafo["pasos"]:
        ady.setdefault(a, []).append(b)
        if tipo == "paso":
            ady.setdefault(b, []).append(a)
    salidas: dict[int, list] = {}
    for con in grafo["conexiones"]:
        if con["destino"] == "@regreso":
            for a in con.get("zonas_salida", []):
                salidas.setdefault(a, []).append((None, con))
        else:
            for a, b in con["zonas"]:
                salidas.setdefault(a, []).append((b, con))
    vistas_estado = {(z, 0, -1) for z in inicio}
    cola = deque(vistas_estado)
    vistas = set(inicio)

    def visitar(z: int, lugar: int, regreso: int) -> None:
        estado = (z, lugar, regreso)
        if estado not in vistas_estado and zona_transitable(zonas[z], banderas, capacidades, lugar):
            vistas_estado.add(estado)
            vistas.add(z)
            cola.append(estado)

    while cola:
        z, lugar, regreso = cola.popleft()
        for v in ady.get(z, ()):
            visitar(v, lugar, regreso)
        for b, con in salidas.get(z, ()):
            if not cumple(con["requisitos"]["historia"], banderas, lugar):
                continue
            if b is None:  # obj_out: vuelve a la zona de la puerta por la que se entró
                if regreso >= 0:
                    destino = con["fija"].get(zonas[regreso]["mapa"]) if "fija" in con else regreso
                    if destino is not None:
                        visitar(destino, lugar, -1)
                continue
            nuevo_lugar = con["indice"] if con.get("indice", -1) >= 0 else lugar
            nuevo_regreso = {1: z, 2: z if regreso < 0 else regreso, 3: -1}.get(con.get("regreso", 0), regreso)
            visitar(b, nuevo_lugar, nuevo_regreso)
    return vistas
