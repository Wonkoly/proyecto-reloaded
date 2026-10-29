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

import capas_tiles
import dialogos_original
import tiendas_original

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
# Saltos (ProtaSaltos): dirección del salto y rotación de la colisión de un solo sentido (en Godot
# bloquea a lo que se mueve hacia su +Y local: girada 180° bloquea subir, -90° ir a la derecha...).
SALTOS = {"obj_saltos_I": ((-1, 0), -1.5707963), "obj_saltos_D": ((1, 0), 1.5707963), "obj_saltos": ((0, 1), 3.1415927)}
# obj_saltos se sube 16 px (12 en la room 40) cuando el jugador está debajo (DefineSaltos): bloquea ahí.
SUBIDA_SALTO = 16
# Objetos que no son nada en el mapa: controladores, y obj_bloqueado (invisible; ProtaMovimiento no
# choca con él: marca celdas de las guaridas/decoración).
IGNORADOS = {"EXPLORER", "variables", "Control", "obj_bloqueado"}
# global.index_place: el INDEX de la puerta por la que se entró (DoorEnter). Las salidas y NPCs de los
# interiores compartidos dependen de él: en las condiciones se escribe "lugar" (GameState.indice_lugar).
LUGAR = ("campo", ("id", "global"), "index_place")
# Nodo de cada zona de encuentros → SubtablaEncuentros.Metodo (HIERBA 0, BARRO 2, HIERBA_INVISIBLE 7).
ZONAS_ENCUENTRO = {"ZonaHierba": 0, "ZonaBarro": 2, "ZonaHierbaInvisible": 7}
# Capa 7: el agua (aparte de las paredes para que Surf pueda dejar de chocar con ella).
CAPA_AGUA = 64
# Qué hace falta para pasar por cada tipo de agua (la primera clase que coincide) y por los
# obstáculos que se quitan con un movimiento (siguen siendo paredes en el mapa).
AGUA = [("obj_lava", "lava"), ("obj_lava_undertiles", "lava"), ("obj_agua1", "surf")]
OBSTACULOS = [("obj_arbusto", "corte"), ("obj_roca_redonda", "fuerza"), ("obj_roca", "golpe_roca"),
              ("obj_torbellino", "torbellino"), ("obj_rocatrepable", "trepa")]
# Los que son un nodo Obstaculo que se puede quitar en el juego (InteractionArbusto/RocaFragmentada/RocaRedonda).
MO_OBSTACULOS = {"corte", "golpe_roca", "fuerza"}
# Zonas sin colisión que piden algo para cruzarlas (ProtaStartsCascada: Surf + Cascada para subir).
TERRENO = {o: "surf+cascada" for o in ("obj_cascada", "obj_cascadaPlata", "obj_cascadaVerde", "obj_cascadaLeon",
                                         "obj_cascadaSpec", "obj_cascadaLunar", "obj_cascadaLunarXL",
                                         "obj_cascadaCristalino")}
# obj_out en estas rooms vuelve a una posición fija y no a outx/outy (OutDoorStepActions).
VOLVER_FIJO = {78: (624, 180), 441: (313, 432), 445: (840, 408), 450: (1368, 472), 510: (416, 456),
               541: (360, 952), 546: (400, 624)}


class Juego:
    """Lo que hace falta saber del original: objetos (herencia, sprite, máscara) y sprites."""

    def __init__(self, ext: Path, juego: Path):
        self.ext = ext
        self.juego = juego
        indice = json.loads((ext / "index.json").read_text())
        self.objetos: list[str] = indice["objects"]
        self.sprites: list[str] = indice["sprites"]
        self.rooms: list[str] = indice["rooms"]
        # Número de fuente de cada tileset en los TileSet de los mapas (el mismo en todos).
        self.fondos: list[str | None] = indice["backgrounds"]
        self._mascaras: capas_tiles.Mascaras | None = None
        self._tiles_ref: set[int] | None = None
        self._dialogos: dialogos_original.Funciones | None = None
        self._teclas: dict[str, int] | None = None
        self._personajes: dialogos_original.Personajes | None = None
        # sprINDEX de los NPCs extraídos: dialogo_personajes.json tiene su nombre y retrato.
        self.sprindex_usados: set[float] = set()
        # Entrenadores colocados (TrainerCreation): INDEX → {nombre, sprindex}; y los eventos que se
        # generan para ellos: (room, nodo) → texto del .evento.
        self.entrenadores_vistos: dict[int, dict] = {}
        self.eventos_generados: dict[tuple[str, str], str] = {}
        self._obj: dict[str, dict] = {}
        self._meta: dict[str, dict | None] = {}
        self._arboles: dict[str, list] = {}

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

    @property
    def mascaras(self) -> capas_tiles.Mascaras:
        if self._mascaras is None:
            self._mascaras = capas_tiles.Mascaras(self.juego / "_internal" / "backgrounds")
        return self._mascaras

    @property
    def tiles_ref(self) -> set[int]:
        """Tiles que el código del juego borra o aclara por id: se conservan siempre y sueltos."""
        if self._tiles_ref is None:
            self._tiles_ref = capas_tiles.tiles_referenciados(self.ext / "scripts")
        return self._tiles_ref

    @property
    def dialogos(self) -> dialogos_original.Funciones:
        if self._dialogos is None:
            self._dialogos = dialogos_original.Funciones(self.ext / "scripts", self.ext / "text" / "es")
        return self._dialogos

    @property
    def personajes(self) -> dialogos_original.Personajes:
        if self._personajes is None:
            self._personajes = dialogos_original.Personajes(self, self.dialogos, self.juego / "data" / "trainer")
        return self._personajes

    def nombre_tecla(self, clave: str) -> str:
        """NameTecla de una tecla del original por su nombre (key_menu_pokemon → "Espacio")."""
        if self._teclas is None:
            self._teclas = dialogos_original.teclas_por_defecto(self.script("DefaultKeyAssignment"))
        codigo = self._teclas.get(clave)
        v = self.dialogos.llamar("NameTecla", float(codigo)) if codigo is not None else None
        return v if isinstance(v, str) else "?"

    def meta(self, sprite: str | None) -> dict | None:
        if not sprite:
            return None
        if sprite not in self._meta:
            ruta = self.juego / "_internal" / "sprites" / sprite / "meta.json"
            self._meta[sprite] = json.loads(ruta.read_text()) if ruta.exists() else None
        return self._meta[sprite]

    def script(self, nombre: str) -> str:
        return (self.ext / "scripts" / f"{nombre}.gml").read_text(encoding="utf-8")

    def arbol(self, nombre: str) -> list:
        """El script parseado (se guarda: los de puertas, NPCs y salidas se leen para cada room)."""
        if nombre not in self._arboles:
            self._arboles[nombre] = gml_visual.Parser(gml_visual.tokenizar(self.script(nombre))).programa()
        return self._arboles[nombre]


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
    if cond[0] == "bin" and cond[1] in ("&&", "and"):
        # if(room=(N) && global.index_place=0): el resto de la condición la decide el Evaluador.
        return _menciona_room(cond[2], room) or _menciona_room(cond[3], room)
    return False


class Evaluador:
    """Ejecuta un subconjunto de GML. Los if que dependen de banderas de la historia ((18).x) no se
    deciden: se recorren las dos ramas y cada instancia creada guarda su condición como expresión de
    GDScript sobre h (GameState.historia), p. ej. h.get("fy_002", 0) == 0. Lo demás (globales, otros
    objetos) vale lo inicial (0). Los valores de propiedades y variables dentro de ramas de la historia
    se toman como en ESTADO_HISTORIA."""

    def __init__(self, juego: Juego, room: int, ancho: int = 0, alto: int = 0, instancias_room: list | None = None):
        self.juego = juego
        self.room = room
        self.ancho, self.alto = ancho, alto
        # Para instance_position (SetOnlyWater no pone agua sobre la playa).
        self.instancias_room = instancias_room or []
        self.instancias: list[dict] = []
        self.locales: dict[str, object] = {}
        # Condiciones de la historia de lo que se ejecuta ahora (se cumplen todas).
        self.condicion: list[str] = []
        # Si con ESTADO_HISTORIA se llegaría aquí (las asignaciones fuera de las instancias nuevas
        # solo cuentan entonces).
        self.concreto = True

    def _rama(self, inst, cond: str, verdadera: bool) -> None:
        cond_antes, concreto_antes = self.condicion, self.concreto
        self.condicion = cond_antes + [cond]
        self.concreto = concreto_antes and verdadera
        salio = False
        try:
            self.ejecutar(inst)
        except _Salir:
            salio = True
        self.condicion, self.concreto = cond_antes, concreto_antes
        if salio:
            # exit dentro de la rama: lo que sigue solo pasa si la rama no se tomó.
            self.condicion = cond_antes + [f"not ({cond})"]
            self.concreto = concreto_antes and not verdadera

    def simbolica(self, e) -> str | None:
        """La condición como GDScript sobre h si depende de la historia; None si no (o no se puede)."""
        if not _usa_historia(e):
            return None
        try:
            return self._gd(e)
        except _Desconocido:
            return None

    def _gd(self, e) -> str:
        k = e[0]
        if k == "num":
            v = float(e[1])
            return str(int(v)) if v.is_integer() else repr(v)
        if k == "id" and e[1] in ("true", "false"):
            return "1" if e[1] == "true" else "0"
        if k == "campo" and e[1] == ("num", "18"):
            return f'h.get("{e[2]}", 0)'
        if k == "indice" and e[1][0] == "campo" and e[1][1] == ("num", "18") and e[2][0] == "num":
            return f'h.get("{e[1][2]}_{int(float(e[2][1]))}", 0)'
        if e == LUGAR:
            return "lugar"
        if e == ("id", "room"):
            return str(self.room)
        if k == "campo" and (e[1][0] == "num" or e[1] == ("id", "global")):
            return "0"
        if k == "un":
            return f"(not {self._gd(e[2])})" if e[1] in ("!", "not") else f"(-{self._gd(e[2])})"
        if k == "bin":
            op = {"=": "==", "&&": "and", "||": "or", "and": "and", "or": "or"}.get(e[1], e[1])
            if op not in ("==", "!=", "<", ">", "<=", ">=", "and", "or", "+", "-", "*"):
                raise _Desconocido(op)
            return f"({self._gd(e[2])} {op} {self._gd(e[3])})"
        raise _Desconocido(k)

    def _del_contexto(self, inst: dict) -> bool:
        """Si la instancia se creó en la rama actual (o más adentro)."""
        return len(inst.get("condicion", [])) >= len(self.condicion)

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
            simb = self.simbolica(i[1])
            try:
                c = self.valor(i[1])
            except _Desconocido:
                return
            if simb is not None:
                self._rama(i[2], simb, bool(c))
                if i[3] is not None:
                    self._rama(i[3], f"not ({simb})", not c)
            elif c:
                self.ejecutar(i[2])
            elif i[3] is not None:
                self.ejecutar(i[3])
        elif k == "exit":
            raise _Salir()
        elif k == "for":
            self.ejecutar(i[1])
            for _ in range(100000):
                try:
                    if not self.valor(i[2]):
                        break
                except _Desconocido:
                    break
                self.ejecutar(i[4])
                self.ejecutar(i[3])
        elif k == "asig":
            try:
                v = self.valor(i[3])
                if i[2] in ("+=", "-=", "*=") and i[1][0] == "id":
                    actual = self.valor(i[1])
                    v = actual + v if i[2] == "+=" else actual - v if i[2] == "-=" else actual * v
            except (_Desconocido, TypeError):
                return
            lv = i[1]
            if lv[0] == "id":
                if self.concreto or isinstance(v, dict):
                    self.locales[lv[1]] = v
            elif lv[0] == "campo" and lv[1][0] == "id" and isinstance(self.locales.get(lv[1][1]), dict):
                destino = self.locales[lv[1][1]]
                if self.concreto or self._del_contexto(destino):
                    destino[lv[2]] = v
        elif k == "expr":
            try:
                self.valor(i[1])
            except _Desconocido:
                pass
        elif k == "with":
            if i[1][0] == "id" and isinstance(self.locales.get(i[1][1]), dict) and i[2][0] == "expr":
                llamada = i[2][1]
                args = []
                if llamada[0] == "llamada":
                    try:
                        args = [self.valor(a) for a in llamada[2]]
                    except _Desconocido:
                        args = []
                self.locales[i[1][1]]["with_" + llamada[1]] = args or True

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
            if e[1] in ("room_width", "room_height") and self.ancho:
                return float(self.ancho if e[1] == "room_width" else self.alto)
            if e[1] in self.locales:
                return self.locales[e[1]]
            raise _Desconocido(e[1])
        if k == "campo":
            base = e[1]
            if base == ("num", "18"):
                return float(ESTADO_HISTORIA.get(e[2], 0))  # banderas de la historia
            if base == ("id", "global") and e[2] == "rivalname":
                return "$rival$"  # se reemplaza al mostrar el texto
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
            operaciones = {"=": lambda: a == b, "==": lambda: a == b, "!=": lambda: a != b, "<": lambda: a < b,
                           ">": lambda: a > b, "<=": lambda: a <= b, ">=": lambda: a >= b,
                           "+": lambda: a + b if not isinstance(a, str) else str(a) + str(b),
                           "-": lambda: a - b, "*": lambda: a * b, "/": lambda: a / b if b else 0.0,
                           "mod": lambda: a % b if b else 0.0, "div": lambda: a // b if b else 0.0}
            if op not in operaciones:
                raise _Desconocido(op)
            return operaciones[op]()
        if k == "llamada":
            nombre, args = e[1], e[2]
            if nombre == "instance_create":
                x, y, obj = (self.valor(a) for a in args)
                if not isinstance(obj, float) or not 0 <= int(obj) < len(self.juego.objetos):
                    raise _Desconocido("objeto")
                inst = {"objeto": self.juego.objetos[int(obj)], "x": x, "y": y, "condicion": list(self.condicion),
                        "destruir_si": []}
                self.instancias.append(inst)
                return inst
            if nombre in ("Destruye", "instance_destroy"):
                v = self.valor(args[0]) if args else None
                destino = [v] if isinstance(v, dict) else [
                    i for i in self.instancias if isinstance(v, float) and 0 <= int(v) < len(self.juego.objetos)
                    and i["objeto"] == self.juego.objetos[int(v)]]
                for inst in destino:
                    extra = self.condicion[len(inst["condicion"]):]
                    if extra:
                        inst["destruir_si"].append(" and ".join(f"({c})" for c in extra))
                    elif self.concreto or self._del_contexto(inst):
                        inst["destruida"] = True
                return 0.0
            if nombre == "create_water_rectangle":
                # for(i=a; i*16<=c; i+=1) for(j=b; j*16<=d; j+=1) instance_create(i*16, j*16, obj)
                a, b, c, d, obj = (self.valor(x) for x in args)
                for ci in range(int(a), int(c // 16) + 1):
                    for cj in range(int(b), int(d // 16) + 1):
                        self.instancias.append({"objeto": self.juego.objetos[int(obj)], "x": ci * 16.0, "y": cj * 16.0,
                                                "condicion": list(self.condicion), "destruir_si": []})
                return 0.0
            if nombre in ("instance_position", "position_meeting"):
                x, y, obj = (self.valor(a) for a in args)
                nombre_obj = self.juego.objetos[int(obj)] if isinstance(obj, float) else None
                return float(any(self.juego.es(i["object"], nombre_obj) and i["x"] <= x < i["x"] + 16 and i["y"] <= y < i["y"] + 16
                                 for i in self.instancias_room))
            if nombre == "TextDialog":
                return {"dialogo": int(self.valor(args[0]))}
            if nombre in ("TextoPar1", "TextoPar2", "TextoPar3"):
                # El texto y sus $par1$, $par2$... (se reemplazan al mostrarlo).
                base = self.valor(args[0])
                pars = [self._parametro(a) for a in args[1:]]
                if isinstance(base, dict):
                    return {**base, "par": pars}
                for n, par in enumerate(pars, 1):
                    base = str(base).replace(f"$par{n}$", par)
                return base
            if nombre == "NameTecla":
                return self._parametro(e)
            if nombre in ("TextCharacter", "TextCharacter2"):
                return " ".join(self.juego.dialogos.linea("txt_character", int(self.valor(a))) for a in args)
            if nombre == "BuildTextTrainer":
                # El texto de después del combate; de paso pone el nombre (argument1) al NPC z.
                texto = {"dialogo": int(self.valor(args[0])), "par": [self._parametro(a) for a in args[2:]]}
                z = self.locales.get("z")
                quien = self.valor(args[1]) if len(args) > 1 else 0.0
                if isinstance(z, dict) and isinstance(quien, float):
                    if quien > 0:
                        z["name"] = self.juego.dialogos.linea("txt_character", int(quien))
                    elif quien == -101:
                        z["name"] = "$rival$"
                return texto
            if nombre == "IniTrainer" and len(args) == 2:
                z = self.valor(args[0])
                if isinstance(z, dict):
                    z["sprINDEX"] = self.valor(args[1])
                return 0.0
            raise _Desconocido(nombre)
        raise _Desconocido(k)


    def _parametro(self, a) -> str:
        """Un parámetro de TextoPar como texto (string() de GM; NameTecla: el nombre de la tecla)."""
        if a[0] == "llamada" and a[1] == "NameTecla" and a[2] and a[2][0][0] == "campo":
            return self.juego.nombre_tecla(a[2][0][2])
        try:
            v = self.valor(a)
        except _Desconocido:
            return "?"  # depende del estado del juego: el texto se conserva igual
        if isinstance(v, float):
            return str(int(v)) if v.is_integer() else str(round(v, 2))
        return v if isinstance(v, str) else ""


def _linea_decir(texto) -> str | None:
    if isinstance(texto, dict) and "dialogo" in texto:
        pars = " ".join(gd_str(p) for p in texto.get("par", []))
        return f"decir {texto['dialogo']}" + (f" {pars}" if pars else "")
    if isinstance(texto, str) and texto:
        return f"decir {gd_str(texto)}"
    return None


def evento_entrenador(n: int, texto, inst: dict, room: str, companeros: list | None = None, juego=None) -> str:
    """El .evento de un entrenador (EntrenadorHabla): su texto (y el de sus compañeros, en los dobles), el
    combate y, si gana el jugador, sus banderas trainer_N (con ellas el mapa cambia al entrenador por el
    NPC de después del combate)."""
    nombre = inst.get("name") if isinstance(inst.get("name"), str) else ""
    lineas = [f"# Entrenador {n}{': ' + nombre if nombre else ''} ({room}). Generado por tools/extraer.py:",
              "# para cambiarlo, cópialo a data/eventos/ con el mismo nombre (ver docs/eventos.md).",
              "# Se ejecuta cuando el entrenador te ve (y camina hasta ti) o cuando le hablas."]
    d = _linea_decir(texto)
    if d:
        lineas.append(d)
    numeros = [n]
    for c in companeros or []:
        numeros.append(int(c["INDEX"]))
        d = _linea_decir(c.get("str"))
        if d:
            quien = c.get("sprINDEX", -1)
            nom = c.get("name") if isinstance(c.get("name"), str) else ""
            lineas += ["exclamacion_de " + str(int(c["INDEX"])),
                       f"hablante {f(quien) if isinstance(quien, float) else -1} {gd_str(nom)}", d, "hablante npc"]
    lineas += ["combate " + " ".join(str(x) for x in numeros), "si gano:"]
    lineas += [f"    bandera trainer_{x} = 1" for x in numeros]
    return "\n".join(lineas) + "\n"


def _usa_historia(e) -> bool:
    if isinstance(e, tuple):
        if e[:2] == ("campo", ("num", "18")) or e == LUGAR:
            return True
        return any(_usa_historia(x) for x in e[1:] if isinstance(x, (tuple, list)))
    if isinstance(e, list):
        return any(_usa_historia(x) for x in e)
    return False


def condicion_final(inst: dict) -> str:
    """Expresión de GDScript (sobre h) con la que la instancia existe; "" si siempre."""
    partes = [f"({c})" for c in inst.get("condicion", [])]
    if inst.get("destruir_si"):
        partes.append("not (" + " or ".join(f"({d})" for d in inst["destruir_si"]) + ")")
    return " and ".join(partes)


def activa_al_inicio(condicion: str) -> bool:
    return not condicion or bool(eval(condicion, {"__builtins__": {}}, {"h": dict(ESTADO_HISTORIA), "lugar": 0}))


def instancias_por_script(juego: Juego, room: int, scripts: list[str], ancho: int = 0, alto: int = 0,
                          instancias_room: list | None = None) -> list[dict]:
    out = []
    for nombre in scripts:
        for bloque in bloques_room(juego.arbol(nombre), room):
            ev = Evaluador(juego, room, ancho, alto, instancias_room)
            ev.correr(bloque)
            out += [i for i in ev.instancias if not i.get("destruida")]
    return out


def personajes(juego: Juego, funciones) -> dict:
    """Los sprites de personaje del código Q/CARA (ExecuteCheat): 0-9 los protagonistas y 10 el sprite
    de un entrenador (1-351 → ValorTrainerTrucado → sprINDEX → SpriteTrainer)."""
    gml = juego.script("ExecuteCheat")
    protas = {}
    for n, cuerpo in re.findall(r"if\(char=(\d+)\)\{(global\.sprD=.*?)\}", gml):
        ids = dict(re.findall(r"global\.spr([DUR])=\((\d+)\)", cuerpo))
        protas[int(n)] = [juego.sprites[int(ids[k])] for k in "DUR"]
    tabla = sprites_entrenador(juego)
    entrenadores = {}
    for n in range(0, 352):
        indice = funciones.llamar("ValorTrainerTrucado", float(n))
        sprs = tabla.get(int(indice), {}) if isinstance(indice, float) else {}
        if all(k in sprs for k in ("sprD", "sprU", "sprR")):
            entrenadores[n] = [juego.sprites[sprs[k]] for k in ("sprD", "sprU", "sprR")]
    return {"protagonistas": protas, "entrenadores": entrenadores}


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
        for bloque in bloques_room(juego.arbol(nombre), room):
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
    if rect["x1"] <= rect["x0"] or rect["y1"] <= rect["y0"]:
        return None  # condiciones que se contradicen (o fuera del mapa)
    asig = {}
    cuerpo = inst[2][1] if inst[2][0] == "bloque" else [inst[2]]
    for a in cuerpo:
        if a[0] == "asig" and a[1][0] == "campo" and a[1][1] == ("id", "global") and a[2] == "=":
            asig[a[1][2]] = a[3]
    if "lugar" not in asig or asig["lugar"][0] != "num":
        return None
    sal = {"rect": rect, "destino": juego.rooms[int(asig["lugar"][1])],
           "indice": int(float(asig["index_place"][1])) if asig.get("index_place", ("",))[0] == "num" else -1}
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
        # Condición de la historia de la instancia que se está escribiendo ("" = siempre existe).
        self.condicion = ""

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
        if self.condicion:
            grupos = (grupos or []) + ["historia"]
            props = props + [f"metadata/condicion = {gd_str(self.condicion)}"]
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


def tiles(room: dict, tilesets: dict, e: Escena, juego: Juego, arriba: bool, usados: dict) -> None:
    """Tiles por función (capas_tiles.py): Suelo, Agua, Obstaculos, Hierba, Detalles y, si algo tiene
    que dibujarse encima de lo anterior, <Función>Encima. Los de depth < DEPTH_TILES_ARRIBA van encima
    de los objetos (TilesArriba), el resto debajo (TilesDebajo). Todas las capas usan el TileSet del
    mapa; `usados` junta los tiles de cada tileset para armarlo (tileset_del_mapa)."""
    raiz = "TilesArriba" if arriba else "TilesDebajo"
    e.nodo(raiz, "Node2D", ".", [])
    ocultos = invisibles_room(room, tilesets, juego)
    grupo = [t for t in sorted(room["tiles"], key=lambda t: -t["depth"])  # estable: respeta el orden dentro de cada depth
             if (t["depth"] < DEPTH_TILES_ARRIBA) == arriba and t["bg"] in tilesets and t["id"] not in ocultos]
    capas = capas_tiles.repartir(juego.mascaras, juego, room["instances"], grupo, juego.tiles_ref, caja)
    for capa in capas:
        if capa.celdas:
            datos = bytearray(struct.pack("<H", 0))
            for (x, y), (bg, ax, ay, alt) in sorted(capa.celdas.items(), key=lambda c: (c[0][1], c[0][0])):
                datos += struct.pack("<hhHHHH", x, y, juego.fondos.index(bg), ax, ay, alt)
                usados.setdefault(bg, set()).add((ax, ay, alt))
            e.nodo(capa.nombre, "TileMapLayer", raiz, [
                "tile_map_data = PackedByteArray(%s)" % ", ".join(str(b) for b in datos),
                'tile_set = SubResource("tileset_mapa")'])
        if capa.sueltos:
            padre = f"{raiz}/{capa.nombre}Sueltos"
            e.nodo(f"{capa.nombre}Sueltos", "Node2D", raiz, [])
            for t in capa.sueltos:
                props = [f"texture = {e.ref('Texture2D', e.res(tilesets[t['bg']][0]))}", "centered = false",
                         f"position = Vector2({f(t['x'])}, {f(t['y'])})",
                         "region_enabled = true", f"region_rect = Rect2({t['tx']}, {t['ty']}, {t['w']}, {t['h']})"]
                if t["xscale"] != 1 or t["yscale"] != 1:
                    props.append(f"scale = Vector2({f(t['xscale'])}, {f(t['yscale'])})")
                if t["blend"] != 0xFFFFFFFF:
                    c = t["blend"]
                    props.append("modulate = Color(%s, %s, %s, %s)" % tuple(
                        f(round(v / 255, 4)) for v in (c & 255, (c >> 8) & 255, (c >> 16) & 255, (c >> 24) & 255)))
                e.nodo(f"tile_{t['id']}", "Sprite2D", padre, props)


_ocultos: dict[str, set[int]] = {}


def invisibles_room(room: dict, tilesets: dict, juego: Juego) -> set[int]:
    """Tiles del mapa que nunca se ven (tapados por completo); se calcula sobre todas las profundidades."""
    if room["name"] not in _ocultos:
        todos = [t for t in sorted(room["tiles"], key=lambda t: -t["depth"]) if t["bg"] in tilesets]
        _ocultos[room["name"]] = capas_tiles.invisibles(juego.mascaras, todos, juego.tiles_ref)
    return _ocultos[room["name"]]


def tileset_del_mapa(e: Escena, juego: Juego, tilesets: dict, usados: dict) -> None:
    """El TileSet del mapa (sub_resource "tileset_mapa"): una fuente por tileset que usa, con todos sus
    tiles de 16x16 para pintar y, en los tiles que el mapa pone desplazados, el alternativo con ese
    desplazamiento (capas_tiles.alt_desfase)."""
    fuentes = []
    for bg in sorted(usados, key=juego.fondos.index):
        _, _, w, h = tilesets[bg]
        alts = {}
        for ax, ay, alt in usados[bg]:
            if alt:
                alts.setdefault((ax, ay), set()).add(alt)
        props = [f"resource_name = {gd_str(bg)}", f"texture = {e.ref('Texture2D', e.res(tilesets[bg][0]))}"]
        for y in range(h // 16):
            for x in range(w // 16):
                props.append(f"{x}:{y}/0 = 0")
                for alt in sorted(alts.get((x, y), ())):
                    dx, dy = (alt - 1) % 16, (alt - 1) // 16
                    props += [f"{x}:{y}/{alt} = {alt}", f"{x}:{y}/{alt}/texture_origin = Vector2i({-dx}, {-dy})"]
                if (x, y) in alts:
                    props.append(f"{x}:{y}/next_alternative_id = {max(alts[(x, y)]) + 1}")
        sid = f"fuente_{juego.fondos.index(bg)}"
        e.subs.append(f'[sub_resource type="TileSetAtlasSource" id="{sid}"]\n' + "\n".join(props) + "\n")
        fuentes.append(f'sources/{juego.fondos.index(bg)} = SubResource("{sid}")')
    e.subs.append('[sub_resource type="TileSet" id="tileset_mapa"]\n' + "\n".join(fuentes) + "\n")


def escena_mapa(room: dict, juego: Juego, tilesets: dict, sprite_tres, snake, res,
                tabla_npc: dict) -> tuple[str, list[str], dict]:
    """Devuelve (texto .tscn, objetos no convertidos, geometría para el grafo de conexiones).
    sprite_tres(nombre) → ruta res:// del SpriteOriginal."""
    ridx = juego.rooms.index(room["name"])
    ancho, alto = room["width"], room["height"]
    e = Escena(res)
    no_convertidos: list[str] = []
    # Geometría (rectángulos x0, y0, x1, y1 en px del mapa) para tools/conexiones.py.
    geo: dict = {"ancho": ancho, "alto": alto, "paredes": [], "agua": [], "obstaculos": [], "saltos": [],
                 "salidas": [], "terreno": []}
    e.nodo(snake(room["name"]), "Node2D", None, [
        f"script = {e.ref('Script', 'res://scenes/overworld/mapa.gd')}",
        f"nombre_original = {gd_str(room['name'])}",
        f"tamano = Vector2i({ancho}, {alto})"])
    fondos(room, tilesets, e)
    usados: dict[str, set] = {}
    tiles(room, tilesets, e, juego, arriba=False, usados=usados)
    e.nodo("BaseHierba", "Node2D", ".", [])
    e.nodo("Objetos", "Node2D", ".", ["y_sort_enabled = true"])
    tiles(room, tilesets, e, juego, arriba=True, usados=usados)
    tileset_del_mapa(e, juego, tilesets, usados)
    e.nodo("Paredes", "StaticBody2D", ".", [f"collision_layer = {CAPA_PAREDES}", "collision_mask = 0"])
    e.nodo("Agua", "StaticBody2D", ".", [f"collision_layer = {CAPA_AGUA}", "collision_mask = 0"])
    # Zonas de encuentros, cada una con su método (SubtablaEncuentros.Metodo; ProtaCheckHierba).
    for nodo_zona, metodo in ZONAS_ENCUENTRO.items():
        e.nodo(nodo_zona, "Area2D", ".", [
            f"script = {e.ref('Script', 'res://scenes/overworld/zona_hierba.gd')}", f"collision_layer = {CAPA_ZONAS}",
            "collision_mask = 0", "monitoring = false", f"metodo = {metodo}"], grupos=["zona_hierba"])
    e.nodo("Salidas", "Node2D", ".", [])
    e.nodo("Saltos", "Node2D", ".", [])
    e.nodo("Marcadores", "Node2D", ".", [])
    n_pared = n_hierba = n_salida = 0
    agua_fija: list[tuple] = []

    def rect_de(c) -> list[float]:
        return [c[0] - c[2] / 2, c[1] - c[3] / 2, c[0] + c[2] / 2, c[1] + c[3] / 2]

    def pared(meta, x, y, sx=1.0, sy=1.0, requisito=None, obj=""):
        nonlocal n_pared
        c = caja(meta, x, y, sx, sy) if meta else None
        if c:
            n_pared += 1
            e.nodo(f"pared_{n_pared}", "CollisionShape2D", "Paredes", [
                f"position = Vector2({f(c[0])}, {f(c[1])})", f"shape = {e.rect(c[2], c[3])}"])
            if requisito:
                geo["obstaculos"].append(rect_de(c) + [requisito, e.condicion, obj])
            else:
                geo["paredes"].append(rect_de(c) + [e.condicion, obj])

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

    def salida(nombre: str, padre: str, x: float, y: float, rect: list[float], destino: str, llegada: tuple,
               tipo: str, activacion: int = 0, regreso: int = 0, por_punto: bool = False,
               relativa: tuple = (False, False), volver: bool = False, sprite: str | None = None,
               volver_posicion: tuple | None = None, indice: int = -1) -> None:
        """Una Salida (Area2D) en (x, y) que se activa en rect (coordenadas del mapa)."""
        props = [f"position = Vector2({f(x)}, {f(y)})", f"script = {e.ref('Script', 'res://scenes/overworld/salida.gd')}",
                 "collision_layer = 0", f"collision_mask = {CAPA_JUGADOR}", "monitorable = false",
                 f"destino = {gd_str(destino)}", f"destino_posicion = Vector2({f(llegada[0])}, {f(llegada[1])})",
                 f"tipo = {gd_str(tipo)}"]
        for prop, valor, defecto in (("relativa_x", relativa[0], False), ("relativa_y", relativa[1], False),
                                     ("activacion", activacion, 0), ("regreso", regreso, 0),
                                     ("por_punto", por_punto, False), ("volver", volver, False)):
            if valor != defecto:
                props.append(f"{prop} = {('true' if valor else 'false') if isinstance(valor, bool) else valor}")
        if indice >= 0:
            props.append(f"indice_lugar = {indice}")
        if volver_posicion:
            props.append(f"volver_posicion = Vector2({f(volver_posicion[0])}, {f(volver_posicion[1])})")
        if sprite:
            props.append(f"sprite = {e.ref('Resource', sprite_tres(sprite))}")
        e.nodo(nombre, "Area2D", padre, props)
        e.nodo("CollisionShape2D", "CollisionShape2D", f"{padre}/{nombre}", [
            f"position = Vector2({f((rect[0] + rect[2]) / 2 - x)}, {f((rect[1] + rect[3]) / 2 - y)})",
            f"shape = {e.rect(rect[2] - rect[0], rect[3] - rect[1])}"])
        geo["salidas"].append({
            "nodo": nombre, "tipo": tipo, "x": x, "y": y, "rect": [round(v, 2) for v in rect], "destino": destino,
            "llegada": [llegada[0], llegada[1]], "relativa": list(relativa), "activacion": activacion,
            "regreso": regreso, "por_punto": por_punto, "volver": volver, "condicion": e.condicion, "indice": indice,
            "volver_posicion": list(volver_posicion) if volver_posicion else None})

    def room_de(v) -> str:
        return juego.rooms[int(v)] if isinstance(v, (int, float)) and 0 <= int(v) < len(juego.rooms) else ""

    instancias = [dict(i, origen="room") for i in room["instances"]]
    scripts = ["CreateDoors", "CreateNPC1", "CreateNPC2", "CreateNPC3", "CreateNPC4", "CreateNPC5", "CreateDevices",
               "TrainerCreation"]
    if any(i["object"] == "ONLYWATER" for i in room["instances"]):
        scripts.append("SetOnlyWater")
    instancias += [dict(i, origen="script", xscale=1.0, yscale=1.0, id=f"s{k}")
                   for k, i in enumerate(instancias_por_script(juego, ridx, scripts, ancho, alto, room["instances"]))]
    # obj_borradorDeAgua (BorradorAguaActua): borra el agua más cercana (puentes, muelles).
    aguas = [i for i in instancias if juego.es(i.get("objeto") or i.get("object"), "obj_agua1")]
    for b in [i for i in instancias if (i.get("objeto") or i.get("object")) == "obj_borradorDeAgua"]:
        vivas = [a for a in aguas if not a.get("borrada")]
        if vivas:
            min(vivas, key=lambda a: (a["x"] - b["x"]) ** 2 + (a["y"] - b["y"]) ** 2)["borrada"] = True
    for inst in instancias:
        obj = inst["objeto"] if "objeto" in inst else inst["object"]
        if not obj or obj in IGNORADOS or juego.es(obj, "obj_bloqueado") or obj in ("obj_borradorDeAgua", "ONLYWATER"):
            continue
        datos = juego.objeto(obj)
        sprite = datos.get("sprite")
        meta = juego.meta(datos.get("mask") or sprite)
        x, y = float(inst["x"]), float(inst["y"])
        sx, sy = float(inst.get("xscale", 1.0)), float(inst.get("yscale", 1.0))
        nombre = f"{obj}_{inst['id']}"
        e.condicion = condicion_final(inst)
        c_rel = caja(meta, 0, 0, sx, sy) if meta else (8, 8, 16, 16)
        rect_obj = [x + c_rel[0] - c_rel[2] / 2, y + c_rel[1] - c_rel[3] / 2, x + c_rel[0] + c_rel[2] / 2, y + c_rel[1] + c_rel[3] / 2]
        if juego.es(obj, "obj_door"):
            # DoorStepActions/DoorEnter: pulsando arriba con la máscara encima; guarda el regreso.
            destino = room_de(inst.get("ROOM", -1))
            salida(nombre, "Objetos", x, y, rect_obj, destino, (inst.get("X", 0), inst.get("Y", 0)), "puerta",
                   activacion=1, regreso=1, sprite=sprite, indice=int(inst.get("INDEX", 0)))
        elif obj == "obj_door_inv":
            # Puerta invisible (InvisibleDoorStepActions): igual que obj_door; arriba=true salvo que se cambie.
            salida(nombre, "Salidas", x, y, rect_obj, room_de(inst.get("ROOM", -1)), (inst.get("X", 0), inst.get("Y", 0)),
                   "puerta", activacion=1 if inst.get("arriba", True) else 0, regreso=1, indice=int(inst.get("INDEX", 0)))
        elif obj == "obj_NOdoor":
            # Entrada sin puerta (NoDoorStepActions/NoDoorEnter): pulsando arriba (o abajo) con la máscara
            # encima; entrada=true guarda el regreso si no había uno, salida=true lo borra.
            arriba, abajo = inst.get("arriba", True), inst.get("abajo", False)
            regreso = 3 if inst.get("salida", False) else 2 if inst.get("entrada", True) else 0
            salida(nombre, "Salidas", x, y, rect_obj, room_de(inst.get("ROOM", -1)), (inst.get("X", -1), inst.get("Y", -1)),
                   "entrada", activacion=1 if arriba else 2 if abajo else 0, regreso=regreso,
                   indice=int(inst.get("INDEX", 0)))
        elif obj == "obj_out_special":
            # OutSpecialEnter: al tocarla, a roomOUT (xOUT, yOUT); borra el regreso.
            salida(nombre, "Salidas", x, y, rect_obj, room_de(inst.get("roomOUT", -1)),
                   (inst.get("xOUT", -1), inst.get("yOUT", -1)), "salida_especial", regreso=3)
        elif juego.es(obj, "obj_teleport_suelo"):
            # TeleportSueloStepActions: el punto del jugador en (x+2..x+14, y-6..y+2); DST_ROOM = esta room.
            destino = room_de(inst.get("DST_ROOM", ridx))
            salida(nombre, "Salidas", x, y, [x + 2, y - 6, x + 14, y + 2], destino,
                   (inst.get("DST_X", -1), inst.get("DST_Y", -1)), "teletransporte", por_punto=True)
            if datos.get("visible") and sprite:
                decorado(f"{nombre}_sprite", sprite, x, y)
        elif obj == "obj_TelePort":
            # TeleportDeviceCheckProta: con la máscara encima 60 pasos (2 s) lleva a XX, YY de ROOM (esta room).
            # En nativo se activa al llegar, sin la espera.
            salida(nombre, "Salidas", x, y, rect_obj, room_de(inst.get("ROOM", ridx)), (inst.get("XX", 0), inst.get("YY", 0)),
                   "teletransporte")
        elif obj == "obj_conducto_tierra":
            # ConductoTierraStepActions: el punto del jugador en (x+4..x+12, y-8..y+8).
            salida(nombre, "Salidas", x, y, [x + 4, y - 8, x + 12, y + 8], room_de(inst.get("D_ROOM", -1)),
                   (inst.get("D_X", -1), inst.get("D_Y", -1)), "conducto", por_punto=True)
            if sprite:
                decorado(f"{nombre}_sprite", sprite, x, y)
        elif obj == "obj_brechaTransporte":
            # BrechaTransporteStepActions: el jugador a 12 px o menos.
            salida(nombre, "Salidas", x, y, [x - 12, y - 12, x + 12, y + 12], room_de(inst.get("ROOM", -1)),
                   (inst.get("X", -1), inst.get("Y", -1)), "brecha", por_punto=True)
            if sprite:
                decorado(f"{nombre}_sprite", sprite, x, y, 0.7, 0.7, alfa=0.6)
        elif obj == "obj_out":
            fija = VOLVER_FIJO.get(ridx)
            salida(nombre, "Objetos", x, y, rect_obj if meta else [x, y, x + 16, y + 16], "", (0, 0), "salida_interior",
                   activacion=2, volver=True, volver_posicion=fija)
            if sprite:
                decorado(f"{nombre}_sprite", sprite, x, y)
        elif juego.es(obj, "obj_people"):
            if obj == "obj_Watcher":
                # DefineWatcher: sprINDEX 411, "Vigilante", alcance 80, TextDialog(5179), mira al azar, MOVE.
                inst.setdefault("MOVE", True)
                inst.setdefault("vel", 2.0)
                inst.setdefault("sprINDEX", 411.0)
                inst.setdefault("name", juego.dialogos.linea("txt_character", 711))
                inst.setdefault("distancia", 80.0)
                inst.setdefault("str", {"dialogo": 5179})
                inst.setdefault("mirafijo", 0.0)
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
                if texto.get("par"):
                    props.append("dialogo_parametros = PackedStringArray(%s)" % ", ".join(gd_str(p) for p in texto["par"]))
            elif isinstance(texto, str) and texto:
                props.append(f"texto_fijo = {gd_str(texto)}")
            if isinstance(inst.get("name"), str) and inst["name"]:
                props.append(f"nombre = {gd_str(inst['name'])}")
            # Quién habla (TalkHabla: sin sprINDEX, el de su sprite con GetStaticNPCIndex).
            sprindex = inst.get("sprINDEX", -1)
            if not isinstance(sprindex, float) or sprindex < 0:
                spr_id = inst.get("sprite_index")
                sprindex = float(juego.personajes.estaticos.get(int(spr_id), -1)) if isinstance(spr_id, float) else -1.0
            if sprindex >= 0:
                props.append(f"sprindex = {f(sprindex)}")
                juego.sprindex_usados.add(sprindex)
            mirafijo = inst.get("mirafijo")
            if not isinstance(mirafijo, float) and juego.es(obj, "obj_Entrenador"):
                mirafijo = 0.0  # DefineEntrenador: mirafijo = false (mira al azar y vigila)
            if isinstance(mirafijo, float):
                props.append(f"mira_fija = {int(mirafijo)}")
            # TimelineMovimientoPeople: 10 horizontal, 11 vertical, 0 vueltas en sentido horario, 1 antihorario,
            # dentro de minX..maxX, minY..maxY, a vel px/step, empezando hacia direction.
            ruta = inst.get("with_TimelineMovimientoPeople")
            if isinstance(ruta, list) and ruta and isinstance(ruta[0], float) and int(ruta[0]) in (0, 1, 10, 11):
                caja_ruta = [inst.get(k) for k in ("minX", "minY", "maxX", "maxY")]
                if all(isinstance(v, float) for v in caja_ruta):
                    vel = inst.get("vel", 2.0 if obj == "obj_Watcher" else 3.0)
                    props += [f"ruta = {int(ruta[0])}",
                              f"ruta_caja = Rect2({f(caja_ruta[0])}, {f(caja_ruta[1])}, {f(caja_ruta[2] - caja_ruta[0])}, {f(caja_ruta[3] - caja_ruta[1])})",
                              f"ruta_velocidad = {f(vel)}", f"ruta_direccion = {int(inst.get('direction', 0.0) or 0)}"]
            if isinstance(inst.get("TRAINER"), float) and inst["TRAINER"] > 0:
                props.append(f"entrenador_vencido = {int(inst['TRAINER'])}")
            # Distancia para hablar: obj_Talk 10 (DefineTalk), obj_NoPass 64 (DefineNoPass), el resto 12
            # (ProtaInteraction). obj_NoPass cierra por defecto el paso hacia la izquierda (vk_left).
            no_pasa = juego.es(obj, "obj_NoPass")
            es_entrenador = juego.es(obj, "obj_Entrenador") and isinstance(inst.get("INDEX"), float)
            dist = inst.get("distancia")
            if not isinstance(dist, float):
                # DefineEntrenador: 80 (lo que alcanza a ver).
                dist = 80.0 if es_entrenador else 64.0 if no_pasa else 10.0 if juego.es(obj, "obj_Talk") else 12.0
            if dist != 10:
                props.append(f"distancia = {f(dist)}")
            nopass = inst.get("nopass", 37.0 if no_pasa else None)
            if isinstance(nopass, float):
                props.append(f"no_pasar = {int(nopass)}")
            if obj == "obj_Watcher":
                # WatcherPillaProta: si ve al jugador, va hasta él, habla (WatcherHabla) y en el Castillo
                # Rekiem lo saca del edificio (ExplorerEscape).
                props.append("vigila = true")
                lineas = ["# Vigilante (obj_Watcher). Generado por tools/extraer.py (ver docs/eventos.md)."]
                d = _linea_decir(texto)
                if d:
                    lineas.append(d)
                if room["name"].startswith("CastleRekiem"):
                    lineas.append("expulsar")
                juego.eventos_generados[(room["name"], nombre)] = "\n".join(lineas) + "\n"
            if obj == "obj_tendero":
                juego.eventos_generados[(room["name"], nombre)] = tiendas_original.evento_tienda(juego, ridx, room["name"])
            if obj == "obj_Regalar" and isinstance(inst.get("index"), float):
                # RegalarHabla: dice su texto, da el objeto (PillaObject), dice str2 y pone la bandera de INDEX.
                if not hasattr(juego, "_banderas_regalo"):
                    juego._banderas_regalo = tiendas_original.banderas_regalo(juego)
                lineas = ["# Regala un objeto (RegalarHabla). Generado por tools/extraer.py (ver docs/eventos.md)."]
                d = _linea_decir(texto)
                if d:
                    lineas.append(d)
                cant = inst.get("cantidad", 1.0)
                lineas.append(f"dar_objeto {int(inst['index'])} {int(cant) if isinstance(cant, float) else 1}")
                d2 = _linea_decir(inst.get("str2"))
                if d2:
                    lineas.append(d2.replace("decir", "narrar", 1))
                bandera = juego._banderas_regalo.get(int(inst["INDEX"])) if isinstance(inst.get("INDEX"), float) else None
                if bandera:
                    lineas.append(f"bandera {bandera} = 1")
                juego.eventos_generados[(room["name"], nombre)] = "\n".join(lineas) + "\n"
            if obj == "obj_enfermera":
                # EnfermeraHabla: DialogoIndexFace(2460, 1290), HealingPokeCenter, DialogoIndexFace(2461, 1290).
                props += ["frame_fijo = 0", "sprindex = 1290"]
                juego.sprindex_usados.add(1290.0)
                juego.eventos_generados[(room["name"], nombre)] = (
                    "# La enfermera del Centro Pokémon (EnfermeraHabla). Generado por tools/extraer.py.\n"
                    "hablante 1290\ndecir 2460\ncurar_centro\ndecir 2461\nframe 2\nesperar 0.17\nframe 0\n")
            if es_entrenador:
                n_ent = int(inst["INDEX"])
                props.append(f"entrenador = {n_ent}")
                juego.entrenadores_vistos.setdefault(n_ent, {"nombre": inst.get("name") if isinstance(inst.get("name"), str) else "",
                                                             "sprindex": sprindex, "lider": bool(inst.get("lider"))})
                # isDoble / isTriple: los compañeros (compi_1, compi_2) retan y pelean con él.
                companeros = [c for c in (inst.get("compi_1"), inst.get("compi_2"))
                              if isinstance(c, dict) and isinstance(c.get("INDEX"), float)]
                juego.eventos_generados[(room["name"], nombre)] = evento_entrenador(n_ent, texto, inst, room["name"], companeros, juego)
            e.nodo(nombre, None, "Objetos", props, instancia=e.ref("PackedScene", "res://scenes/overworld/npc.tscn"))
            if meta and (c := caja(meta, 0, 0, 1, 1)):
                e.nodo("CollisionShape2D", "CollisionShape2D", f"Objetos/{nombre}", [
                    f"position = Vector2({f(c[0])}, {f(c[1])})", f"shape = {e.rect(c[2], c[3])}"])
                if not inst.get("MOVE"):  # los que caminan no tapan un paso para siempre
                    geo["paredes"].append([x + c[0] - c[2] / 2, y + c[1] - c[3] / 2, x + c[0] + c[2] / 2, y + c[1] + c[3] / 2, e.condicion, obj])
        elif juego.es(obj, "obj_saltos") and meta:
            clase = next(k for k in SALTOS if juego.es(obj, k))
            (dx, dy), rot = SALTOS[clase]
            c = caja(meta, 0, 0, sx, sy)
            e.nodo(nombre, "Area2D", "Saltos", [
                f"position = Vector2({f(x)}, {f(y)})", f"script = {e.ref('Script', 'res://scenes/overworld/salto.gd')}",
                "collision_layer = 0", f"collision_mask = {CAPA_JUGADOR}", "monitorable = false",
                f"direccion = Vector2({dx}, {dy})"])
            e.nodo("CollisionShape2D", "CollisionShape2D", f"Saltos/{nombre}", [
                f"position = Vector2({f(c[0])}, {f(c[1])})", f"shape = {e.rect(c[2], c[3])}"])
            e.nodo("Bloqueo", "StaticBody2D", f"Saltos/{nombre}", [f"collision_layer = {CAPA_PAREDES}", "collision_mask = 0"])
            subida = (12 if ridx == 40 else SUBIDA_SALTO) if clase == "obj_saltos" else 0
            e.nodo("CollisionShape2D", "CollisionShape2D", f"Saltos/{nombre}/Bloqueo", [
                f"position = Vector2({f(c[0])}, {f(c[1] - subida)})", f"rotation = {rot}",
                f"shape = {e.rect(c[2], c[3]) if dy else e.rect(c[3], c[2])}", "one_way_collision = true"])
            geo["saltos"].append(rect_de((x + c[0], y + c[1], c[2], c[3])) + [dx, dy, e.condicion])
        elif obj in ("obj_reversibleHorizontal", "obj_reversibleVertical") and meta:
            c = caja(meta, 0, 0, sx, sy)
            e.nodo(nombre, "Area2D", "Saltos", [
                f"position = Vector2({f(x)}, {f(y)})", f"script = {e.ref('Script', 'res://scenes/overworld/salto.gd')}",
                "collision_layer = 0", f"collision_mask = {CAPA_JUGADOR}", "monitorable = false",
                f"reversible = {1 if obj == 'obj_reversibleHorizontal' else 2}"])
            e.nodo("CollisionShape2D", "CollisionShape2D", f"Saltos/{nombre}", [
                f"position = Vector2({f(c[0])}, {f(c[1])})", f"shape = {e.rect(c[2], c[3])}"])
        elif juego.es(obj, "obj_agua1"):
            # Agua (ProtaMovimiento: place_meeting con obj_agua1 y derivados): no se pisa sin Surf.
            if not inst.get("borrada"):
                c = caja(meta, x, y, sx, sy) if meta else (x + 8, y + 8, 16, 16)
                requisito = next((r for base, r in AGUA if juego.es(obj, base)), "surf")
                if e.condicion:
                    n_pared += 1
                    e.nodo(f"agua_{n_pared}", "CollisionShape2D", "Agua", [
                        f"position = Vector2({f(c[0])}, {f(c[1])})", f"shape = {e.rect(c[2], c[3])}"])
                else:
                    agua_fija.append((*rect_de(c), requisito))
                geo["agua"].append(rect_de(c) + [requisito, e.condicion])
                if datos.get("visible") and sprite:
                    decorado(nombre, sprite, x, y, sx, sy)
        elif obj in TERRENO and meta:
            # Cascadas: sin colisión en el mapa, pero para subirlas hace falta Surf y Cascada.
            geo["terreno"].append(rect_de(caja(meta, x, y, sx, sy)) + [TERRENO[obj], e.condicion])
            if datos.get("visible") and sprite:
                decorado(nombre, sprite, x, y, sx, sy, 0.2)
        elif juego.es(obj, "obj_hierba") or obj == "obj_barro":
            # Hierba (obj_hierba), hierba invisible (obj_hierbaInvisible: sin dibujo) y barro (obj_barro).
            n_hierba += 1
            zona = "ZonaHierbaInvisible" if juego.es(obj, "obj_hierbaInvisible") else "ZonaBarro" if obj == "obj_barro" else "ZonaHierba"
            if zona == "ZonaHierba":
                decorado(f"base_{n_hierba}", "spr_bck_hierba", x - 8, y - 8, padre="BaseHierba")
                decorado(nombre, sprite, x, y, sx, sy, alfa=0.75)
            elif datos.get("visible") and sprite:
                decorado(nombre, sprite, x, y, sx, sy)
            if meta and (c := caja(meta, x, y, sx, sy)):
                e.nodo(f"hierba_{n_hierba}", "CollisionShape2D", zona, [
                    f"position = Vector2({f(c[0])}, {f(c[1])})", f"shape = {e.rect(c[2], c[3])}"])
        elif juego.es(obj, "obj_pared"):
            requisito = next((r for base, r in OBSTACULOS if juego.es(obj, base)), None)
            c = caja(meta, x, y, sx, sy) if meta else None
            if requisito in MO_OBSTACULOS and c and sprite:
                # Arbusto, roca o roca redonda: un Obstaculo que se quita con Corte / Golpe Roca / Fuerza.
                geo["obstaculos"].append(rect_de(c) + [requisito, e.condicion, obj])
                n_pared += 1
                e.nodo(nombre, "StaticBody2D", "Objetos", [
                    f"position = Vector2({f(x)}, {f(y)})", f"collision_layer = {CAPA_PAREDES}", "collision_mask = 0",
                    f"script = {e.ref('Script', 'res://scenes/overworld/obstaculo.gd')}",
                    f"sprite = {e.ref('Resource', sprite_tres(sprite))}", f"mo = {gd_str(requisito)}",
                    f"objeto_original = {gd_str(obj)}"] + ([f"escala = Vector2({f(sx)}, {f(sy)})"] if (sx, sy) != (1.0, 1.0) else []))
                e.nodo("forma", "CollisionShape2D", f"Objetos/{nombre}", [
                    f"position = Vector2({f(c[0] - x)}, {f(c[1] - y)})", f"shape = {e.rect(c[2], c[3])}"])
            else:
                pared(meta, x, y, sx, sy, requisito, obj)
                if datos.get("visible") and sprite:
                    decorado(nombre, sprite, x, y, sx, sy)
        elif datos.get("visible") and sprite:
            velocidad = 0.125 if juego.es(obj, "obj_flower") else 0.0  # DefineFlower: image_speed 0.125
            decorado(nombre, sprite, x, y, sx, sy, velocidad)
        else:
            no_convertidos.append(obj)
            e.nodo(nombre, "Marker2D", "Marcadores", [f"position = Vector2({f(x)}, {f(y)})", f"metadata/objeto = {gd_str(obj)}"])

    e.condicion = ""
    for k, (x0, y0, x1, y1) in enumerate(unir_rectangulos([r[:4] for r in agua_fija]), start=1):
        e.nodo(f"agua_fija_{k}", "CollisionShape2D", "Agua", [
            f"position = Vector2({f((x0 + x1) / 2)}, {f((y0 + y1) / 2)})", f"shape = {e.rect(x1 - x0, y1 - y0)}"])
    salidas, raras = salidas_room(juego, ridx, ancho, alto)
    for s in salidas:
        r = s["rect"]
        n_salida += 1
        rect = [r["x0"], r["y0"], r["x1"], r["y1"]]
        borde = rect[0] < 0 or rect[1] < 0 or rect[2] > ancho or rect[3] > alto
        salida(f"salida_{n_salida}_{snake(s['destino'])}", "Salidas", 0, 0, rect, s["destino"], (s["x"], s["y"]),
               "borde" if borde else "escalera", por_punto=True, relativa=(s["relativa_x"], s["relativa_y"]),
               indice=s["indice"])
    if raras:
        no_convertidos.append(f"{raras} salidas con condiciones de la historia")
    return e.texto(), no_convertidos, geo


def unir_rectangulos(rects: list) -> list[tuple]:
    """Junta rectángulos que se tocan (el agua son miles de celdas de 16×16): primero en filas, luego
    las filas iguales que se apilan."""
    filas: list[list[float]] = []
    for x0, y0, x1, y1 in sorted(set(map(tuple, rects)), key=lambda r: (r[1], r[3], r[0])):
        u = filas[-1] if filas else None
        if u and u[1] == y0 and u[3] == y1 and x0 <= u[2]:
            u[2] = max(u[2], x1)
        else:
            filas.append([x0, y0, x1, y1])
    out: list[list[float]] = []
    abiertas: dict[tuple, list[float]] = {}
    for x0, y0, x1, y1 in sorted(filas, key=lambda r: (r[1], r[0])):
        u = abiertas.get((x0, x1))
        if u and u[3] == y0:
            u[3] = y1
        else:
            u = [x0, y0, x1, y1]
            abiertas[(x0, x1)] = u
            out.append(u)
    return [tuple(r) for r in out]
