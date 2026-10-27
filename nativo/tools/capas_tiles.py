"""Reparte los tiles de un mapa en capas por función, para editarlos cómodo en Godot.

En el original los tiles no dicen qué son: lo que choca, el agua y la hierba alta son objetos
(obj_pared, obj_agua*, obj_hierba) puestos encima. Cada tile toma la función del objeto que lo cubre:

    agua        tiles bajo objetos de agua
    obstaculos  tiles bajo objetos que no se pisan (descendientes de obj_pared y las vparedes)
    hierba      tiles bajo hierba alta
    suelo       el primer tile en su lugar (el paisaje)
    detalles    los que van encima de otro tile (bordes, caminos, flores...)

Reglas:
- El orden de dibujo es el del original: un tile va en la capa de su función solo si así queda encima
  de todo lo que tapa; si no, va a la siguiente vuelta ("<función> encima", "encima 2"...).
- Los tiles desplazados de la rejilla de 16 (p. ej. en x = 8) van en la misma capa como tile
  alternativo del TileSet con ese desplazamiento (ALT_DESFASE).
- Los tiles que nunca se ven (tapados por completo por otros) no se exportan; se listan aparte.
- Los que no caben en una TileMapLayer (escalados, teñidos, de tamaño o recorte no múltiplo de 16)
  y los que el juego borra o aclara por id (TileDestruye, TileSetAlpha) quedan como Sprite2D sueltos.

Solo usa la biblioteca estándar (el lector de PNG es mínimo: RGBA de 8 bits, como todos los tilesets).
"""
from __future__ import annotations

import re
import struct
import zlib
from collections import Counter, defaultdict
from pathlib import Path

FUNCIONES = ["suelo", "agua", "obstaculos", "hierba", "detalles"]
NOMBRES = {"suelo": "Suelo", "agua": "Agua", "obstaculos": "Obstaculos", "hierba": "Hierba", "detalles": "Detalles"}
# Objetos de colisión que no heredan de obj_pared.
PAREDES_SUELTAS = ("obj_vpared", "obj_hemipared", "obj_vhemipared", "obj_semipared")


def alt_desfase(dx: int, dy: int) -> int:
    """Id del tile alternativo que dibuja el tile desplazado (dx, dy) px dentro de su celda de 16."""
    return 0 if (dx, dy) == (0, 0) else 1 + dx + 16 * dy


# --------------------------------------------------------------------------- PNG (solo alfa)

def alfa_png(ruta: Path) -> tuple[int, int, list[int], list[int]]:
    """(ancho, alto, visibles, opacos): cada fila es un entero con el bit x encendido si el píxel x
    no es transparente (visibles) o si es 100 % opaco (opacos: los únicos que tapan lo de abajo)."""
    datos = ruta.read_bytes()
    if datos[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{ruta}: no es PNG")
    pos, idat, w = 8, [], 0
    while pos < len(datos):
        n, tipo = struct.unpack(">I4s", datos[pos:pos + 8])
        cuerpo = datos[pos + 8:pos + 8 + n]
        if tipo == b"IHDR":
            w, h, prof, color, _, _, entrelazado = struct.unpack(">IIBBBBB", cuerpo)
            if (prof, color, entrelazado) != (8, 6, 0):
                raise ValueError(f"{ruta}: formato PNG no soportado ({prof} bits, color {color})")
        elif tipo == b"IDAT":
            idat.append(cuerpo)
        pos += 12 + n
    crudo = zlib.decompress(b"".join(idat))
    paso = w * 4
    previa = bytearray(paso)
    visibles, opacos = [], []
    for y in range(h):
        filtro = crudo[y * (paso + 1)]
        f = bytearray(crudo[y * (paso + 1) + 1:(y + 1) * (paso + 1)])
        if filtro == 1:
            for i in range(4, paso):
                f[i] = (f[i] + f[i - 4]) & 255
        elif filtro == 2:
            for i in range(paso):
                f[i] = (f[i] + previa[i]) & 255
        elif filtro == 3:
            for i in range(paso):
                f[i] = (f[i] + ((f[i - 4] if i >= 4 else 0) + previa[i]) // 2) & 255
        elif filtro == 4:
            for i in range(paso):
                a = f[i - 4] if i >= 4 else 0
                b = previa[i]
                c = previa[i - 4] if i >= 4 else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                f[i] = (f[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        previa = f
        vis = opa = 0
        for x in range(w):
            a = f[x * 4 + 3]
            if a:
                vis |= 1 << x
                if a == 255:
                    opa |= 1 << x
        visibles.append(vis)
        opacos.append(opa)
    return w, h, visibles, opacos


class Mascaras:
    """Transparencia de los tilesets, decodificada una vez por imagen."""

    def __init__(self, carpeta: Path):
        self.carpeta = carpeta
        self._img: dict[str, tuple | None] = {}
        self._reg: dict[tuple, tuple] = {}

    def imagen(self, bg: str) -> tuple | None:
        if bg not in self._img:
            ruta = self.carpeta / f"{bg}.png"
            self._img[bg] = alfa_png(ruta) if ruta.exists() else None
        return self._img[bg]

    def tam(self, bg: str) -> tuple[int, int]:
        im = self.imagen(bg)
        return (im[0], im[1]) if im else (0, 0)

    def region(self, t: dict) -> tuple[list[int], list[int]]:
        """(visibles, opacos) del recorte del tile: una fila por píxel de alto, bit 0 = su columna tx."""
        clave = (t["bg"], t["tx"], t["ty"], t["w"], t["h"])
        if clave not in self._reg:
            im = self.imagen(t["bg"])
            vis, opa = [], []
            mascara = (1 << t["w"]) - 1
            for y in range(t["ty"], t["ty"] + t["h"]):
                if im and 0 <= y < im[1]:
                    vis.append((im[2][y] >> t["tx"]) & mascara)
                    opa.append((im[3][y] >> t["tx"]) & mascara)
                else:
                    vis.append(0)
                    opa.append(0)
            self._reg[clave] = (vis, opa)
        return self._reg[clave]


def _rect(t: dict) -> tuple[float, float, float, float]:
    x0, y0 = t["x"], t["y"]
    x1, y1 = x0 + t["w"] * t["xscale"], y0 + t["h"] * t["yscale"]
    return min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1)


def _simple(t: dict) -> bool:
    """Sin escala ni tinte, en píxeles enteros: su transparencia se puede comparar al píxel."""
    return (t["xscale"] == 1 and t["yscale"] == 1 and t["blend"] == 0xFFFFFFFF
            and float(t["x"]).is_integer() and float(t["y"]).is_integer())


def _fila(m: Mascaras, t: dict, y: int, opacos: bool = False) -> int:
    """Bits de la fila y del mapa que ocupa el tile (bit 0 = x 0 del mapa; lo que cae en x < 0 se pierde)."""
    filas = m.region(t)[1 if opacos else 0]
    bits = filas[y - int(t["y"])]
    x = int(t["x"])
    return bits << x if x >= 0 else bits >> -x


def pisa(m: Mascaras, a: dict, b: dict) -> bool:
    """¿a y b tienen píxeles visibles en el mismo lugar del mapa?"""
    ra, rb = _rect(a), _rect(b)
    x0, y0, x1, y1 = max(ra[0], rb[0]), max(ra[1], rb[1]), min(ra[2], rb[2]), min(ra[3], rb[3])
    if x0 >= x1 or y0 >= y1:
        return False
    if not (_simple(a) and _simple(b)):
        return True
    return any(_fila(m, a, y) & _fila(m, b, y) for y in range(int(y0), int(y1)))


def invisibles(m: Mascaras, tiles: list[dict], referenciados: set[int]) -> set[int]:
    """Ids de los tiles (en orden de dibujo) que no dejan ningún píxel a la vista: todo lo que dibujan
    queda bajo píxeles opacos de tiles posteriores. Los que el juego borra o aclara (referenciados)
    nunca tapan ni se quitan; tampoco los escalados o teñidos."""
    tapado: dict[int, int] = defaultdict(int)
    out = set()
    for t in reversed(tiles):
        if t["id"] in referenciados or not _simple(t):
            continue
        y0 = int(t["y"])
        if not any(_fila(m, t, y) & ~tapado[y] for y in range(y0, y0 + t["h"])):
            out.add(t["id"])
        for y in range(y0, y0 + t["h"]):
            tapado[y] |= _fila(m, t, y, opacos=True)
    return out


def tiles_referenciados(scripts: Path) -> set[int]:
    """Ids de tiles que el código del juego toca (TileDestruye, TileSetAlpha, tile_*)."""
    patron = re.compile(r"(?:TileDestruye|TileSetAlpha|tile_[a-z_]+)\((10\d{6})\b")
    ids = set()
    for f in scripts.glob("*.gml"):
        ids.update(int(x) for x in patron.findall(f.read_text(encoding="utf-8", errors="replace")))
    return ids


def funcion_objeto(juego, nombre: str) -> str | None:
    """Función que un objeto da a los tiles que cubre (juego: mapas_original.Juego)."""
    cadena = []
    while nombre:
        cadena.append(nombre)
        nombre = juego.objeto(nombre).get("parent")
    if any(n.startswith("obj_agua") for n in cadena):
        return "agua"
    if "obj_pared" in cadena or any(n.startswith(PAREDES_SUELTAS) for n in cadena):
        return "obstaculos"
    if any(n.startswith("obj_hierba") for n in cadena):
        return "hierba"
    return None


def _celdas8(r) -> list[tuple[int, int]]:
    return [(gx, gy) for gx in range(int(r[0]) // 8, int(r[2] - 1) // 8 + 1)
            for gy in range(int(r[1]) // 8, int(r[3] - 1) // 8 + 1)]


class Capa:
    def __init__(self, funcion: str, vuelta: int):
        self.funcion = funcion
        self.vuelta = vuelta
        self.celdas: dict[tuple[int, int], tuple[str, int, int, int]] = {}  # celda -> (bg, ax, ay, alt)
        self.sueltos: list[dict] = []

    @property
    def nombre(self) -> str:
        base = NOMBRES[self.funcion]
        return base if self.vuelta == 0 else f"{base}Encima" + ("" if self.vuelta == 1 else str(self.vuelta))


def repartir(m: Mascaras, juego, instancias: list[dict], tiles: list[dict], referenciados: set[int],
             caja) -> list[Capa]:
    """Capas por función, en orden de dibujo, para `tiles` (ya en orden de dibujo del original).
    caja(meta, x, y, sx, sy) -> (cx, cy, w, h) | None da el rectángulo de una instancia."""
    cubre = {f: set() for f in ("agua", "obstaculos", "hierba")}
    for i in instancias:
        f = funcion_objeto(juego, i["object"])
        if not f:
            continue
        o = juego.objeto(i["object"])
        meta = juego.meta(o.get("mask") or o.get("sprite"))
        c = caja(meta, i["x"], i["y"], i["xscale"], i["yscale"]) if meta else None
        if c:
            cubre[f].update(_celdas8((c[0] - c[2] / 2, c[1] - c[3] / 2, c[0] + c[2] / 2, c[1] + c[3] / 2)))
    usado = Counter()
    capas: dict[tuple[int, int], Capa] = {}
    puestos: list[tuple[dict, tuple]] = []      # (tile, posición de dibujo)
    cerca = defaultdict(list)                   # celda de 32 px -> índices en puestos
    for t in tiles:
        r = _rect(t)
        c8 = _celdas8(r)
        func = next((f for f in ("agua", "obstaculos", "hierba")
                     if c8 and sum(c in cubre[f] for c in c8) * 2 > len(c8)), None)
        if func is None:
            func = "detalles" if any(usado[c] for c in c8) else "suelo"
        for c in c8:
            usado[c] += 1
        # Tiene que dibujarse después de todo lo anterior con lo que se pisa.
        minimo = None
        vistos = set()
        zonas = {(gx // 4, gy // 4) for gx, gy in c8}
        for z in zonas:
            for k in cerca[z]:
                if k not in vistos:
                    vistos.add(k)
                    if puestos[k][1] > (minimo or (-1,)) and pisa(m, puestos[k][0], t):
                        minimo = puestos[k][1]
        fi = FUNCIONES.index(func)
        tw, th = m.tam(t["bg"])
        en_capa = (_simple(t) and t["id"] not in referenciados
                   and all(v % 16 == 0 for v in (t["tx"], t["ty"], t["w"], t["h"]))
                   and t["tx"] + t["w"] <= tw - tw % 16 and t["ty"] + t["h"] <= th - th % 16)
        dx, dy = int(t["x"]) % 16, int(t["y"]) % 16
        celdas = {((int(t["x"]) + ox) // 16, (int(t["y"]) + oy) // 16):
                  (t["bg"], (t["tx"] + ox) // 16, (t["ty"] + oy) // 16, alt_desfase(dx, dy))
                  for oy in range(0, t["h"], 16) for ox in range(0, t["w"], 16)} if en_capa else {}
        vuelta = 0
        while True:
            pos = (vuelta, fi, 0 if en_capa else 1)
            libre = minimo is None or pos > minimo or (not en_capa and pos == minimo)
            capa = capas.get((vuelta, fi))
            if libre and en_capa and capa and any(c in capa.celdas for c in celdas):
                libre = False
            if libre:
                break
            vuelta += 1
        capa = capas.setdefault((vuelta, fi), Capa(func, vuelta))
        if en_capa:
            capa.celdas.update(celdas)
        else:
            capa.sueltos.append(t)
        puestos.append((t, pos))
        for z in zonas:
            cerca[z].append(len(puestos) - 1)
    return [capas[k] for k in sorted(capas)]
