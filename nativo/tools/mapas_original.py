"""Convierte rooms del original en escenas de Godot con nodos reales (ver tools/README.md).

- Tiles y fondos de la room → TileMapLayer / Sprite2D.
- Instancias según su objeto: paredes (descendientes de obj_pared) → colisión; las visibles además
  se dibujan con y-sort (árboles, edificios); obj_hierba → zona de hierba; flores y otros objetos
  visibles → decorado; lo demás → Marker2D (se lista en el resumen).
- Puertas (CreateDoors) y NPCs (CreateNPC1..5): se evalúan sus bloques de la room con el estado de
  la historia de ESTADO_HISTORIA (el resto de banderas en 0).
- Salidas por los bordes y escaleras (CambiosWorldRooms, CambiosSpecialRooms) → Area2D con destino.
"""

from __future__ import annotations

import json
import re
import struct
from pathlib import Path

import gml_visual

# Capas de física (project.godot): 1 paredes, 5 jugador, 6 zonas (hierba).
CAPA_PAREDES = 1
CAPA_JUGADOR = 16
CAPA_ZONAS = 32
# Tiles con depth menor que esto se dibujan encima de los objetos (los objetos usan -y/100).
DEPTH_TILES_ARRIBA = -10
# Estado de la historia con el que se evalúan CreateDoors/CreateNPC* (las banderas del objeto
# "variables"; las que no están valen 0). Por defecto: ya recibió su primer Pokémon (fy_002) y el
# móvil (movil), así el camino de PuebloAlba a la Ruta 1 está abierto.
ESTADO_HISTORIA = {"fy_002": 1, "movil": 1}
# Objetos que no son nada en el mapa: controladores, y obj_bloqueado (invisible; ProtaMovimiento no
# choca con él: marca celdas de las guaridas/decoración).
IGNORADOS = {"EXPLORER", "variables", "Control", "obj_bloqueado"}


class Juego:
    """Lo que hace falta saber del original: objetos (herencia, sprite, máscara) y sprites."""

    def __init__(self, ext: Path, juego: Path):
        self.ext = ext
        self.juego = juego
        indice = json.loads((ext / "index.json").read_text())
        self.objetos: list[str] = indice["objects"]
        self.sprites: list[str] = indice["sprites"]
        self.rooms: list[str] = indice["rooms"]
        self._obj: dict[str, dict] = {}
        self._meta: dict[str, dict | None] = {}

    def objeto(self, nombre: str) -> dict:
        if nombre not in self._obj:
            ruta = self.ext / "objects" / f"{nombre}.json"
            self._obj[nombre] = json.loads(ruta.read_text()) if ruta.exists() else {}
        return self._obj[nombre]

    def es(self, nombre: str | None, base: str) -> bool:
        while nombre:
            if nombre == base:
                return True
            nombre = self.objeto(nombre).get("parent")
        return False

    def meta(self, sprite: str | None) -> dict | None:
        if not sprite:
            return None
        if sprite not in self._meta:
            ruta = self.juego / "_internal" / "sprites" / sprite / "meta.json"
            self._meta[sprite] = json.loads(ruta.read_text()) if ruta.exists() else None
        return self._meta[sprite]

    def script(self, nombre: str) -> str:
        return (self.ext / "scripts" / f"{nombre}.gml").read_text(encoding="utf-8")


# ---------------------------------------------------------------------------------------------
# Evaluación de bloques de room (CreateDoors, CreateNPC*) como en una partida nueva

class _Desconocido(Exception):
    pass


class _Salir(Exception):
    pass


def bloques_room(arbol, room: int):
    """Los cuerpos de los if(room=(N)) de primer nivel (o con room=(N) || ...) para esta room."""
    for inst in arbol:
        if inst[0] == "if" and _menciona_room(inst[1], room):
            yield inst


def _menciona_room(cond, room: int) -> bool:
    if cond[0] == "bin" and cond[1] in ("=", "==") and cond[2] == ("id", "room"):
        return cond[3] == ("num", str(room))
    if cond[0] == "bin" and cond[1] in ("||", "or"):
        return _menciona_room(cond[2], room) or _menciona_room(cond[3], room)
    return False


class Evaluador:
    """Ejecuta un subconjunto de GML con el estado de una partida nueva: (18).x, global.x = 0."""

    def __init__(self, juego: Juego, room: int):
        self.juego = juego
        self.room = room
        self.instancias: list[dict] = []
        self.locales: dict[str, object] = {}

    def correr(self, inst) -> None:
        try:
            self.ejecutar(inst)
        except _Salir:
            pass

    def ejecutar(self, i) -> None:
        k = i[0]
        if k == "bloque":
            for x in i[1]:
                self.ejecutar(x)
        elif k == "if":
            try:
                c = self.valor(i[1])
            except _Desconocido:
                return
            if c:
                self.ejecutar(i[2])
            elif i[3] is not None:
                self.ejecutar(i[3])
        elif k == "exit":
            raise _Salir()
        elif k == "asig":
            try:
                v = self.valor(i[3])
            except _Desconocido:
                return
            lv = i[1]
            if lv[0] == "id":
                self.locales[lv[1]] = v
            elif lv[0] == "campo" and lv[1][0] == "id" and isinstance(self.locales.get(lv[1][1]), dict):
                self.locales[lv[1][1]][lv[2]] = v
        elif k == "expr":
            try:
                self.valor(i[1])
            except _Desconocido:
                pass
        elif k == "with":
            if i[1][0] == "id" and isinstance(self.locales.get(i[1][1]), dict) and i[2][0] == "expr":
                self.locales[i[1][1]]["with_" + i[2][1][1]] = True

    def valor(self, e):
        k = e[0]
        if k == "num":
            return float(e[1])
        if k == "str":
            return e[1]
        if k == "id":
            if e[1] in gml_visual.CONSTANTES:
                c = gml_visual.CONSTANTES[e[1]]
                return float(c) if not isinstance(c, str) else 3.14159
            if e[1] == "room":
                return float(self.room)
            if e[1] in self.locales:
                return self.locales[e[1]]
            raise _Desconocido(e[1])
        if k == "campo":
            base = e[1]
            if base == ("num", "18"):
                return float(ESTADO_HISTORIA.get(e[2], 0))  # banderas de la historia
            if base[0] == "num" or base == ("id", "global"):
                return 0.0  # globales y otros objetos: valor inicial
            if base[0] == "id" and isinstance(self.locales.get(base[1]), dict):
                return self.locales[base[1]].get(e[2], 0.0)
            raise _Desconocido("campo")
        if k == "indice":
            return 0.0
        if k == "un":
            v = self.valor(e[2])
            return (not v) if e[1] in ("!", "not") else -v
        if k == "bin":
            a, b = self.valor(e[2]), self.valor(e[3])
            op = e[1]
            if op in ("&&", "and"):
                return bool(a) and bool(b)
            if op in ("||", "or"):
                return bool(a) or bool(b)
            if isinstance(a, dict) or isinstance(b, dict):
                raise _Desconocido("objeto")
            return {"=": a == b, "==": a == b, "!=": a != b, "<": a < b, ">": a > b, "<=": a <= b,
                    ">=": a >= b, "+": a + b if not isinstance(a, str) else str(a) + str(b),
                    "-": a - b, "*": a * b, "/": a / b if b else 0.0}[op]
        if k == "llamada":
            nombre, args = e[1], e[2]
            if nombre == "instance_create":
                x, y, obj = (self.valor(a) for a in args)
                inst = {"objeto": self.juego.objetos[int(obj)], "x": x, "y": y}
                self.instancias.append(inst)
                return inst
            if nombre in ("Destruye", "instance_destroy"):
                v = self.valor(args[0]) if args else None
                if isinstance(v, dict):
                    v["destruida"] = True
                elif isinstance(v, float):
                    for inst in self.instancias:
                        if inst["objeto"] == self.juego.objetos[int(v)]:
                            inst["destruida"] = True
                return 0.0
            if nombre == "TextDialog":
                return {"dialogo": int(self.valor(args[0]))}
            if nombre in ("TextoPar1", "TextoPar2", "TextoPar3"):
                return self.valor(args[0])
            if nombre == "NameTecla":
                return ""
            raise _Desconocido(nombre)
        raise _Desconocido(k)


def instancias_por_script(juego: Juego, room: int, scripts: list[str]) -> list[dict]:
    out = []
    for nombre in scripts:
        arbol = gml_visual.Parser(gml_visual.tokenizar(juego.script(nombre))).programa()
        for bloque in bloques_room(arbol, room):
            ev = Evaluador(juego, room)
            ev.correr(bloque)
            out += [i for i in ev.instancias if not i.get("destruida")]
    return out


def sprites_entrenador(juego: Juego) -> dict[int, dict[str, int]]:
    """SpriteTrainer: sprINDEX → ids de sprD, sprU, sprR."""
    tabla = {}
    for n, cuerpo in re.findall(r"if\(sprINDEX=(\d+)\)\{(.*?)exit;\}", juego.script("SpriteTrainer")):
        tabla[int(n)] = {k: int(v) for k, v in re.findall(r"(spr[DUR])=\((\d+)\)", cuerpo)}
    return tabla


# ---------------------------------------------------------------------------------------------
# Salidas (CambiosWorldRooms, CambiosSpecialRooms)

def salidas_room(juego: Juego, room: int, ancho: int, alto: int) -> tuple[list[dict], int]:
    """[{rect, destino, x, y, relativa_x, relativa_y}], cantidad de condiciones que no se pudieron leer."""
    salidas, raras = [], 0
    for nombre in ("CambiosWorldRooms", "CambiosSpecialRooms"):
        arbol = gml_visual.Parser(gml_visual.tokenizar(juego.script(nombre))).programa()
        for bloque in bloques_room(arbol, room):
            cuerpo = bloque[2][1] if bloque[2][0] == "bloque" else [bloque[2]]
            for inst in cuerpo:
                if inst[0] != "if":
                    continue
                s = _salida(inst, ancho, alto, juego)
                if s:
                    salidas.append(s)
                else:
                    raras += 1
    return salidas, raras


def _salida(inst, ancho: int, alto: int, juego: Juego) -> dict | None:
    margen = 64
    rect = {"x0": -margen, "x1": ancho + margen, "y0": -margen, "y1": alto + margen}
    for comp in _conjuncion(inst[1]):
        if comp is None:
            return None
        eje, op, n = comp
        if op in (">", ">="):
            rect[eje + "0"] = max(rect[eje + "0"], n)
        elif op in ("<", "<="):
            rect[eje + "1"] = min(rect[eje + "1"], n)
        else:
            return None
    asig = {}
    cuerpo = inst[2][1] if inst[2][0] == "bloque" else [inst[2]]
    for a in cuerpo:
        if a[0] == "asig" and a[1][0] == "campo" and a[1][1] == ("id", "global") and a[2] == "=":
            asig[a[1][2]] = a[3]
    if "lugar" not in asig or asig["lugar"][0] != "num":
        return None
    sal = {"rect": rect, "destino": juego.rooms[int(asig["lugar"][1])]}
    for eje, clave in (("x", "xx"), ("y", "yy")):
        v = _coordenada(asig.get(clave))
        if v is None:
            return None
        sal[eje], sal["relativa_" + eje] = v
    return sal


def _conjuncion(c):
    if c[0] == "bin" and c[1] in ("&&", "and"):
        yield from _conjuncion(c[2])
        yield from _conjuncion(c[3])
        return
    if c[0] == "bin" and c[2][0] == "campo" and c[2][1] == ("num", "14") and c[2][2] in ("x", "y") and c[3][0] == "num":
        yield (c[2][2], c[1], float(c[3][1]))
        return
    yield None


def _coordenada(e) -> tuple[float, bool] | None:
    """global.xx = 2 → (2, fija); = (14).x+112 → (112, relativa)."""
    if e is None:
        return None
    if e[0] == "num":
        return float(e[1]), False
    if e[0] == "campo" and e[1] == ("num", "14"):
        return 0.0, True
    if e[0] == "bin" and e[1] in ("+", "-") and e[2][0] == "campo" and e[2][1] == ("num", "14") and e[3][0] == "num":
        return float(e[3][1]) * (1 if e[1] == "+" else -1), True
    return None


# ---------------------------------------------------------------------------------------------
# Escena

class Escena:
    def __init__(self, res):
        self.res = res
        self.ext: dict[str, tuple[str, str]] = {}
        self.subs: list[str] = []
        self._formas: dict[tuple, str] = {}
        self.nodos: list[str] = []

    def ref(self, tipo: str, ruta: str) -> str:
        if ruta not in self.ext:
            self.ext[ruta] = (tipo, str(len(self.ext) + 1))
        return f'ExtResource("{self.ext[ruta][1]}")'

    def rect(self, w: float, h: float) -> str:
        clave = (round(w, 3), round(h, 3))
        if clave not in self._formas:
            ident = f"rect_{len(self._formas) + 1}"
            self._formas[clave] = ident
            self.subs.append(f'[sub_resource type="RectangleShape2D" id="{ident}"]\nsize = Vector2({clave[0]}, {clave[1]})\n')
        return f'SubResource("{self._formas[clave]}")'

    def nodo(self, nombre: str, tipo: str | None, padre: str | None, props: list[str], instancia: str | None = None,
             grupos: list[str] | None = None) -> None:
        cab = f'[node name="{nombre}"'
        if tipo:
            cab += f' type="{tipo}"'
        if padre is not None:
            cab += f' parent="{padre}"'
        if instancia:
            cab += f" instance={instancia}"
        if grupos:
            cab += " groups=[" + ", ".join(f'"{g}"' for g in grupos) + "]"
        self.nodos.append(cab + "]")
        self.nodos.extend(props)
        self.nodos.append("")

    def texto(self) -> str:
        out = ["[gd_scene format=3]", ""]
        for r, (tipo, ident) in self.ext.items():
            out.append(f'[ext_resource type="{tipo}" path="{r}" id="{ident}"]')
        out.append("")
        out += self.subs
        return "\n".join(out + self.nodos)


def gd_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def f(x: float) -> str:
    return str(int(x)) if float(x).is_integer() else repr(round(float(x), 4))


def caja(meta: dict, x: float, y: float, sx: float, sy: float) -> tuple[float, float, float, float] | None:
    """Rectángulo de colisión en el mapa (centro x, centro y, ancho, alto) de una instancia."""
    col = meta["colliders"][0] if meta.get("colliders") else meta.get("bbox")
    if not col:
        return None
    x0 = x + (col["left"] - meta["origin_x"]) * sx
    x1 = x + (col["right"] + 1 - meta["origin_x"]) * sx
    y0 = y + (col["top"] - meta["origin_y"]) * sy
    y1 = y + (col["bottom"] + 1 - meta["origin_y"]) * sy
    x0, x1 = min(x0, x1), max(x0, x1)
    y0, y1 = min(y0, y1), max(y0, y1)
    return (x0 + x1) / 2, (y0 + y1) / 2, x1 - x0, y1 - y0


def fondos(room: dict, tilesets: dict, e: Escena) -> None:
    """Los fondos de la room (Sprite2D, repetidos si el original los repite)."""
    e.nodo("Fondos", "Node2D", ".", [])
    for i, bg in enumerate(room["backgrounds"]):
        if not bg.get("visible") or not bg.get("bg") or bg["bg"] not in tilesets:
            continue
        png, _, w, h = tilesets[bg["bg"]]
        props = [f"texture = {e.ref('Texture2D', e.res(png))}", "centered = false", f"position = Vector2({bg['x']}, {bg['y']})"]
        if bg.get("tile_h") or bg.get("tile_v"):
            rw = room["width"] if bg.get("tile_h") else w
            rh = room["height"] if bg.get("tile_v") else h
            props += ["texture_repeat = 2", "region_enabled = true", f"region_rect = Rect2(0, 0, {rw}, {rh})"]
        if bg.get("foreground"):
            props.append("z_index = 1")
        e.nodo(f"fondo_{i}", "Sprite2D", "Fondos", props)


def tiles(room: dict, tilesets: dict, e: Escena, snake, arriba: bool) -> None:
    """Tiles por profundidad (mayor depth = más al fondo = primero). Los de depth < DEPTH_TILES_ARRIBA
    van encima de los objetos (TilesArriba), el resto debajo (TilesDebajo). Una TileMapLayer por
    tileset y desfase de la rejilla de 16; los que no caben en una rejilla quedan como Sprite2D."""
    raiz = "TilesArriba" if arriba else "TilesDebajo"
    e.nodo(raiz, "Node2D", ".", [])
    por_depth: dict[int, list[dict]] = {}
    for t in room["tiles"]:
        if (t["depth"] < DEPTH_TILES_ARRIBA) == arriba:
            por_depth.setdefault(t["depth"], []).append(t)
    for depth in sorted(por_depth, reverse=True):
        padre = f"profundidad_{depth}".replace("-", "m")
        e.nodo(padre, "Node2D", raiz, [])
        capas: dict[tuple[str, int, int], dict[tuple[int, int], tuple[int, int]]] = {}
        sueltos: list[dict] = []
        for t in por_depth[depth]:
            if t["bg"] not in tilesets:
                continue
            _, _, tw, th = tilesets[t["bg"]]
            en_rejilla = (t["xscale"] == 1 and t["yscale"] == 1 and t["blend"] == 0xFFFFFFFF
                          and all(v % 16 == 0 for v in (t["tx"], t["ty"], t["w"], t["h"]))
                          and t["tx"] + t["w"] <= tw - tw % 16 and t["ty"] + t["h"] <= th - th % 16)
            celdas = {}
            if en_rejilla:
                fx, fy = t["x"] % 16, t["y"] % 16
                capa = capas.setdefault((t["bg"], fx, fy), {})
                for dy in range(0, t["h"], 16):
                    for dx in range(0, t["w"], 16):
                        celda = ((t["x"] - fx + dx) // 16, (t["y"] - fy + dy) // 16)
                        if celda in capa or celda in celdas:
                            en_rejilla = False
                        celdas[celda] = ((t["tx"] + dx) // 16, (t["ty"] + dy) // 16)
            if en_rejilla:
                capa.update(celdas)
            else:
                sueltos.append(t)
        for (bg, fx, fy), celdas in sorted(capas.items()):
            datos = bytearray(struct.pack("<H", 0))
            for (x, y), (ax, ay) in sorted(celdas.items(), key=lambda c: (c[0][1], c[0][0])):
                datos += struct.pack("<hhHHHH", x, y, 0, ax, ay, 0)
            props = [] if (fx, fy) == (0, 0) else [f"position = Vector2({fx}, {fy})"]
            nombre = snake(bg) + ("" if (fx, fy) == (0, 0) else f"_desfase_{fx}_{fy}")
            e.nodo(nombre, "TileMapLayer", f"{raiz}/{padre}", props + [
                "tile_map_data = PackedByteArray(%s)" % ", ".join(str(b) for b in datos),
                f"tile_set = {e.ref('TileSet', e.res(tilesets[bg][1]))}"])
        for t in sueltos:
            props = [f"texture = {e.ref('Texture2D', e.res(tilesets[t['bg']][0]))}", "centered = false",
                     f"position = Vector2({t['x']}, {t['y']})",
                     "region_enabled = true", f"region_rect = Rect2({t['tx']}, {t['ty']}, {t['w']}, {t['h']})"]
            if t["xscale"] != 1 or t["yscale"] != 1:
                props.append(f"scale = Vector2({f(t['xscale'])}, {f(t['yscale'])})")
            if t["blend"] != 0xFFFFFFFF:
                c = t["blend"]
                props.append("modulate = Color(%s, %s, %s, %s)" % tuple(
                    f(round(v / 255, 4)) for v in (c & 255, (c >> 8) & 255, (c >> 16) & 255, (c >> 24) & 255)))
            e.nodo(f"tile_{t['id']}", "Sprite2D", f"{raiz}/{padre}", props)


def escena_mapa(room: dict, juego: Juego, tilesets: dict, sprite_tres, snake, res,
                tabla_npc: dict) -> tuple[str, list[str]]:
    """Devuelve (texto .tscn, objetos no convertidos). sprite_tres(nombre) → ruta res:// del SpriteOriginal."""
    ridx = juego.rooms.index(room["name"])
    e = Escena(res)
    no_convertidos: list[str] = []
    e.nodo(snake(room["name"]), "Node2D", None, [
        f"script = {e.ref('Script', 'res://scenes/overworld/mapa.gd')}",
        f"nombre_original = {gd_str(room['name'])}",
        f"tamano = Vector2i({room['width']}, {room['height']})"])
    fondos(room, tilesets, e)
    tiles(room, tilesets, e, snake, arriba=False)
    e.nodo("BaseHierba", "Node2D", ".", [])
    e.nodo("Objetos", "Node2D", ".", ["y_sort_enabled = true"])
    tiles(room, tilesets, e, snake, arriba=True)
    e.nodo("Paredes", "StaticBody2D", ".", [f"collision_layer = {CAPA_PAREDES}", "collision_mask = 0"])
    e.nodo("ZonaHierba", "Area2D", ".", [
        f"script = {e.ref('Script', 'res://scenes/overworld/zona_hierba.gd')}", f"collision_layer = {CAPA_ZONAS}",
        "collision_mask = 0", "monitoring = false"], grupos=["zona_hierba"])
    e.nodo("Salidas", "Node2D", ".", [])
    e.nodo("Marcadores", "Node2D", ".", [])
    n_pared = n_hierba = 0

    def pared(meta, x, y, sx=1.0, sy=1.0):
        nonlocal n_pared
        c = caja(meta, x, y, sx, sy) if meta else None
        if c:
            n_pared += 1
            e.nodo(f"pared_{n_pared}", "CollisionShape2D", "Paredes", [
                f"position = Vector2({f(c[0])}, {f(c[1])})", f"shape = {e.rect(c[2], c[3])}"])

    def decorado(nombre, sprite, x, y, sx=1.0, sy=1.0, velocidad=0.0, alfa=1.0, padre="Objetos"):
        props = [f"position = Vector2({f(x)}, {f(y)})", f"script = {e.ref('Script', 'res://scenes/overworld/decorado.gd')}",
                 f"sprite = {e.ref('Resource', sprite_tres(sprite))}"]
        if velocidad:
            props.append(f"image_speed = {f(velocidad)}")
        if alfa != 1.0:
            props.append(f"image_alpha = {f(alfa)}")
        if (sx, sy) != (1.0, 1.0):
            props.append(f"escala = Vector2({f(sx)}, {f(sy)})")
        e.nodo(nombre, "Node2D", padre, props)

    instancias = [dict(i, origen="room") for i in room["instances"]]
    instancias += [dict(i, origen="script", xscale=1.0, yscale=1.0, id=f"s{k}")
                   for k, i in enumerate(instancias_por_script(juego, ridx, ["CreateDoors", "CreateNPC1", "CreateNPC2",
                                                                               "CreateNPC3", "CreateNPC4", "CreateNPC5"]))]
    for inst in instancias:
        obj = inst["objeto"] if "objeto" in inst else inst["object"]
        if not obj or obj in IGNORADOS:
            continue
        datos = juego.objeto(obj)
        sprite = datos.get("sprite")
        meta = juego.meta(datos.get("mask") or sprite)
        x, y = float(inst["x"]), float(inst["y"])
        sx, sy = float(inst.get("xscale", 1.0)), float(inst.get("yscale", 1.0))
        nombre = f"{obj}_{inst['id']}"
        if juego.es(obj, "obj_door"):
            props = [f"position = Vector2({f(x)}, {f(y)})", f"script = {e.ref('Script', 'res://scenes/overworld/salida.gd')}",
                     "collision_layer = 0", f"collision_mask = {CAPA_JUGADOR}", "monitorable = false",
                     f"destino = {gd_str(juego.rooms[int(inst.get('ROOM', -1))] if inst.get('ROOM', -1) >= 0 else '')}",
                     f"destino_posicion = Vector2({f(inst.get('X', 0))}, {f(inst.get('Y', 0))})", "activacion = 1"]
            if sprite:
                props.append(f"sprite = {e.ref('Resource', sprite_tres(sprite))}")
            e.nodo(nombre, "Area2D", "Objetos", props)
            c = caja(juego.meta(sprite), 0, 0, 1, 1) if juego.meta(sprite) else (0, 0, 16, 16)
            e.nodo("CollisionShape2D", "CollisionShape2D", f"Objetos/{nombre}", [
                f"position = Vector2({f(c[0])}, {f(c[1])})", f"shape = {e.rect(c[2], c[3])}"])
        elif obj == "obj_out":
            e.nodo(nombre, "Area2D", "Objetos", [
                f"position = Vector2({f(x)}, {f(y)})", f"script = {e.ref('Script', 'res://scenes/overworld/salida.gd')}",
                "collision_layer = 0", f"collision_mask = {CAPA_JUGADOR}", "monitorable = false",
                "activacion = 2", "volver = true"])
            c = caja(meta, 0, 0, sx, sy) if meta else (0, 0, 16, 16)
            e.nodo("CollisionShape2D", "CollisionShape2D", f"Objetos/{nombre}", [
                f"position = Vector2({f(c[0])}, {f(c[1])})", f"shape = {e.rect(c[2], c[3])}"])
            if sprite:
                decorado(f"{nombre}_sprite", sprite, x, y)
        elif juego.es(obj, "obj_people"):
            props = [f"position = Vector2({f(x)}, {f(y)})", f"collision_layer = {CAPA_PAREDES}", "collision_mask = 0",
                     f"objeto_original = {gd_str(obj)}", f"mira = {int(inst.get('mira', inst.get('mirafijo', 2)) or 2)}"]
            sprs = tabla_npc.get(int(inst.get("sprINDEX", -1)), {})
            for clave, prop in (("sprD", "sprite_abajo"), ("sprU", "sprite_arriba"), ("sprR", "sprite_derecha")):
                propio = juego.sprites[int(inst["sprite_index"])] if "sprite_index" in inst else sprite
                nombre_spr = juego.sprites[sprs[clave]] if clave in sprs else (propio if clave == "sprD" else None)
                if nombre_spr:
                    props.append(f"{prop} = {e.ref('Resource', sprite_tres(nombre_spr))}")
            if inst.get("MOVE"):
                props.append("se_mueve = true")
            texto = inst.get("str")
            if isinstance(texto, dict) and "dialogo" in texto:
                props.append(f"dialogo = {texto['dialogo']}")
            e.nodo(nombre, None, "Objetos", props, instancia=e.ref("PackedScene", "res://scenes/overworld/npc.tscn"))
            if meta and (c := caja(meta, 0, 0, 1, 1)):
                e.nodo("CollisionShape2D", "CollisionShape2D", f"Objetos/{nombre}", [
                    f"position = Vector2({f(c[0])}, {f(c[1])})", f"shape = {e.rect(c[2], c[3])}"])
        elif juego.es(obj, "obj_hierba"):
            n_hierba += 1
            decorado(f"base_{n_hierba}", "spr_bck_hierba", x - 8, y - 8, padre="BaseHierba")
            decorado(nombre, sprite, x, y, sx, sy, alfa=0.75)
            if meta and (c := caja(meta, x, y, sx, sy)):
                e.nodo(f"hierba_{n_hierba}", "CollisionShape2D", "ZonaHierba", [
                    f"position = Vector2({f(c[0])}, {f(c[1])})", f"shape = {e.rect(c[2], c[3])}"])
        elif juego.es(obj, "obj_pared"):
            pared(meta, x, y, sx, sy)
            if datos.get("visible") and sprite:
                decorado(nombre, sprite, x, y, sx, sy)
        elif datos.get("visible") and sprite:
            velocidad = 0.125 if juego.es(obj, "obj_flower") else 0.0  # DefineFlower: image_speed 0.125
            decorado(nombre, sprite, x, y, sx, sy, velocidad)
        else:
            no_convertidos.append(obj)
            e.nodo(nombre, "Marker2D", "Marcadores", [f"position = Vector2({f(x)}, {f(y)})", f"metadata/objeto = {gd_str(obj)}"])

    salidas, raras = salidas_room(juego, ridx, room["width"], room["height"])
    for k, s in enumerate(salidas, start=1):
        r = s["rect"]
        nombre = f"salida_{k}_{snake(s['destino'])}"
        e.nodo(nombre, "Area2D", "Salidas", [
            f"script = {e.ref('Script', 'res://scenes/overworld/salida.gd')}", "collision_layer = 0",
            f"collision_mask = {CAPA_JUGADOR}", "monitorable = false", f"destino = {gd_str(s['destino'])}",
            f"destino_posicion = Vector2({f(s['x'])}, {f(s['y'])})",
            f"relativa_x = {'true' if s['relativa_x'] else 'false'}", f"relativa_y = {'true' if s['relativa_y'] else 'false'}"])
        e.nodo("CollisionShape2D", "CollisionShape2D", f"Salidas/{nombre}", [
            f"position = Vector2({f((r['x0'] + r['x1']) / 2)}, {f((r['y0'] + r['y1']) / 2)})",
            f"shape = {e.rect(r['x1'] - r['x0'], r['y1'] - r['y0'])}"])
    if raras:
        no_convertidos.append(f"{raras} salidas con condiciones de la historia")
    return e.texto(), no_convertidos
