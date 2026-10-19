"""Traductor de la parte visual de los ataques del original (GML) a GDScript.

Lee EfectoEspecial (tipo de partícula de cada movimiento), EffectAtackCreate (sprite y efectos al
lanzar) y EffectAtack (lo que hace cada step) y genera funciones que trabajan sobre un objeto
AtaqueVisual (scenes/battle/ataque_visual.gd), que ofrece las mismas variables y funciones con
nombres de GM8. Solo traduce instrucciones visuales; las que tocan lógica del juego (instancias,
globales, estados de batalla) se omiten una por una y se cuentan.
"""

from __future__ import annotations

import re

# ---------------------------------------------------------------------------------------------
# Léxico y parser (subconjunto de GML suficiente para estos scripts)

_TOKEN = re.compile(r"""
    (?P<num>\d+\.\d*|\.\d+|\d+)
  | (?P<str>"[^"]*"|'[^']*')
  | (?P<id>[A-Za-z_]\w*)
  | (?P<op>\+=|-=|\*=|/=|==|!=|<=|>=|&&|\|\||[-+*/<>=!(){}\[\];,.:])
  | (?P<sp>\s+|//[^\n]*)
""", re.X)


def tokenizar(s: str) -> list[tuple[str, str]]:
    out, i = [], 0
    while i < len(s):
        m = _TOKEN.match(s, i)
        if not m:
            raise SyntaxError(f"carácter inesperado {s[i]!r}")
        i = m.end()
        if m.lastgroup != "sp":
            out.append((m.lastgroup, m.group()))
    return out


class Parser:
    def __init__(self, tokens):
        self.t = tokens
        self.i = 0

    def ver(self, k=0):
        return self.t[self.i + k] if self.i + k < len(self.t) else ("eof", "")

    def es(self, valor):
        return self.ver()[1] == valor

    def tomar(self, valor=None):
        tok = self.ver()
        if valor is not None and tok[1] != valor:
            raise SyntaxError(f"se esperaba {valor!r} y vino {tok[1]!r}")
        self.i += 1
        return tok

    # instrucciones ---------------------------------------------------------------------------
    def programa(self):
        out = []
        while self.ver()[0] != "eof":
            out.append(self.instruccion())
        return out

    def instruccion(self):
        inicio = self.i
        try:
            return self._instruccion()
        except SyntaxError:
            # Se salta la instrucción: hasta el ";" o el "}" que la cierra en su mismo nivel.
            self.i = inicio
            nivel = 0
            while self.ver()[0] != "eof":
                v = self.ver()[1]
                if v in "({[":
                    nivel += 1
                elif v in ")}]":
                    if nivel == 0:
                        break
                    nivel -= 1
                    if nivel == 0 and v == "}":
                        self.tomar()
                        break
                elif v == ";" and nivel == 0:
                    self.tomar()
                    break
                self.tomar()
            if self.i == inicio:
                self.tomar()
            return ("error",)

    def _instruccion(self):
        tok = self.ver()
        if tok[1] == ";":
            self.tomar()
            return ("nada",)
        if tok[1] == "{":
            self.tomar()
            cuerpo = []
            while not self.es("}"):
                cuerpo.append(self.instruccion())
            self.tomar("}")
            return ("bloque", cuerpo)
        if tok[1] == "if":
            self.tomar()
            cond = self.expresion()
            entonces = self.instruccion()
            sino = None
            antes = self.i
            while self.es(";"):  # GML acepta "} ; else"
                self.tomar()
            if not self.es("else"):
                self.i = antes
            if self.es("else"):
                self.tomar()
                sino = self.instruccion()
            return ("if", cond, entonces, sino)
        if tok[1] in ("repeat", "with", "while"):
            self.tomar()
            arg = self.expresion()
            return (tok[1], arg, self.instruccion())
        if tok[1] == "for":
            self.tomar()
            self.tomar("(")
            ini = self.instruccion()
            cond = self.expresion()
            self.tomar(";")
            paso = self.simple()
            self.tomar(")")
            return ("for", ini, cond, paso, self.instruccion())
        if tok[1] == "var":
            self.tomar()
            nombres = [self.tomar()[1]]
            while self.es(","):
                self.tomar()
                nombres.append(self.tomar()[1])
            self.fin()
            return ("var", nombres)
        if tok[1] == "exit":
            self.tomar()
            self.fin()
            return ("exit",)
        if tok[1] in ("switch", "return", "break", "continue"):
            raise SyntaxError(tok[1])
        inst = self.simple()
        self.fin()
        return inst

    def simple(self):
        lv = self.postfijo()
        if self.ver()[1] in ("=", "+=", "-=", "*=", "/="):
            op = self.tomar()[1]
            return ("asig", lv, op, self.expresion())
        if lv[0] != "llamada":
            raise SyntaxError("instrucción sin efecto")
        return ("expr", lv)

    def fin(self):
        if self.es(";"):
            self.tomar()

    # expresiones -----------------------------------------------------------------------------
    _NIVELES = [("||", "or", "xor"), ("&&", "and"), ("=", "==", "!=", "<", ">", "<=", ">="),
                ("+", "-"), ("*", "/", "mod", "div")]

    def expresion(self, nivel=0):
        if nivel == len(self._NIVELES):
            return self.unario()
        izq = self.expresion(nivel + 1)
        while self.ver()[1] in self._NIVELES[nivel]:
            op = self.tomar()[1]
            izq = ("bin", op, izq, self.expresion(nivel + 1))
        return izq

    def unario(self):
        if self.ver()[1] in ("-", "!", "not", "+"):
            op = self.tomar()[1]
            return ("un", op, self.unario())
        return self.postfijo()

    def postfijo(self):
        e = self.primario()
        while True:
            if self.es("."):
                self.tomar()
                e = ("campo", e, self.tomar()[1])
            elif self.es("["):
                self.tomar()
                idx = self.expresion()
                while self.es(","):
                    self.tomar()
                    self.expresion()
                self.tomar("]")
                e = ("indice", e, idx)
            elif self.es("(") and e[0] == "id":
                self.tomar()
                args = []
                while not self.es(")"):
                    args.append(self.expresion())
                    if self.es(","):
                        self.tomar()
                self.tomar(")")
                e = ("llamada", e[1], args)
            else:
                return e

    def primario(self):
        tipo, valor = self.tomar()
        if tipo == "num":
            return ("num", valor)
        if tipo == "str":
            return ("str", valor[1:-1])
        if tipo == "id":
            return ("id", valor)
        if valor == "(":
            e = self.expresion()
            self.tomar(")")
            return e
        raise SyntaxError(f"expresión inesperada {valor!r}")


# ---------------------------------------------------------------------------------------------
# Traducción a GDScript

COLORES = {
    "c_aqua": 0xFFFF00, "c_black": 0, "c_blue": 0xFF0000, "c_dkgray": 0x404040, "c_fuchsia": 0xFF00FF,
    "c_gray": 0x808080, "c_green": 0x008000, "c_lime": 0x00FF00, "c_ltgray": 0xC0C0C0, "c_maroon": 0x000080,
    "c_navy": 0x800000, "c_olive": 0x008080, "c_purple": 0x800080, "c_red": 0x0000FF, "c_silver": 0xC0C0C0,
    "c_teal": 0x808000, "c_white": 0xFFFFFF, "c_yellow": 0x00FFFF, "c_orange": 0x40A0FF,
}
EFECTOS = ["ef_explosion", "ef_ring", "ef_ellipse", "ef_firework", "ef_smoke", "ef_smokeup", "ef_star",
           "ef_spark", "ef_flare", "ef_cloud", "ef_rain", "ef_snow"]
FORMAS = ["pt_shape_pixel", "pt_shape_disk", "pt_shape_square", "pt_shape_line", "pt_shape_star",
          "pt_shape_circle", "pt_shape_ring", "pt_shape_sphere", "pt_shape_flare", "pt_shape_spark",
          "pt_shape_explosion", "pt_shape_cloud", "pt_shape_smoke", "pt_shape_snow"]
CONSTANTES = {**COLORES, **{e: i for i, e in enumerate(EFECTOS)}, **{f: i for i, f in enumerate(FORMAS)},
              "ps_shape_rectangle": 0, "ps_shape_ellipse": 1, "ps_shape_diamond": 2, "ps_shape_line": 3,
              "ps_distr_linear": 0, "ps_distr_gaussian": 1, "ps_distr_invgaussian": 2,
              "true": 1, "false": 0, "noone": -4, "pi": "PI"}

# Variables del ataque que existen en AtaqueVisual (mismo nombre que en GM8, en minúsculas).
VARIABLES = {"x", "y", "direction", "speed", "image_angle", "image_xscale", "image_yscale", "image_alpha",
             "image_blend", "image_speed", "image_index", "visible", "sprite_index", "index", "spr", "shape",
             "size", "spd", "col", "life", "COLOR", "COL", "friction", "hspeed", "vspeed", "xprevious",
             "yprevious", "POKECREATOR", "dir"}
# Nombres que no son variables del ataque: si aparecen, la instrucción no se traduce.
NO_VARIABLES = {"global", "other", "self", "all", "room", "creator", "objetivo", "pokemon", "argument0",
                "argument1", "id", "object_index"}
SIN_EFECTO = {"depth", "pt1", "em", "mask_index", "solid", "persistent"}
CAMPOS_CREADOR = {"x", "y", "mira", "image_xscale", "image_yscale", "bbox_bottom", "bbox_top", "vel"}
# Campos de los sprites de efecto (EfectoSprite) y de las instancias de EfectoAlpha.
CAMPOS_EFECTO = {"x", "y", "sprite_index", "image_index", "image_speed", "image_alpha", "image_blend",
                 "image_xscale", "image_yscale", "image_angle", "direction", "speed", "gira", "aumento",
                 "anim", "RESTA", "target", "WHT", "friction", "hspeed", "vspeed", "depth"}
OBJETO_EFECTO_ALPHA = 10  # EfectoAlpha

FUNCIONES = {
    "random": lambda a: f"randf() * {a[0]}", "irandom": lambda a: f"randi_range(0, int({a[0]}))",
    "random_range": lambda a: f"randf_range({a[0]}, {a[1]})",
    "choose": lambda a: f"[{', '.join(a)}].pick_random()",
    "ceil": lambda a: f"ceilf({a[0]})", "floor": lambda a: f"floorf({a[0]})", "round": lambda a: f"a.round_gm({a[0]})",
    "abs": lambda a: f"absf({a[0]})", "sign": lambda a: f"signf({a[0]})", "sqrt": lambda a: f"sqrt({a[0]})",
    "min": lambda a: f"min({', '.join(a)})", "max": lambda a: f"max({', '.join(a)})",
    "sin": lambda a: f"sin({a[0]})", "cos": lambda a: f"cos({a[0]})",
    "degtorad": lambda a: f"deg_to_rad({a[0]})", "radtodeg": lambda a: f"rad_to_deg({a[0]})",
    "lengthdir_x": lambda a: f"a.lengthdir_x({a[0]}, {a[1]})", "lengthdir_y": lambda a: f"a.lengthdir_y({a[0]}, {a[1]})",
    "point_direction": lambda a: f"a.point_direction({', '.join(a)})",
    "point_distance": lambda a: f"Vector2({a[0]}, {a[1]}).distance_to(Vector2({a[2]}, {a[3]}))",
    "make_color_rgb": lambda a: f"a.make_color_rgb({', '.join(a)})",
    "make_color_hsv": lambda a: f"a.make_color_hsv({', '.join(a)})",
    "merge_color": lambda a: f"a.merge_color({', '.join(a)})",
    "frac": lambda a: f"a.frac({a[0]})",
}
# Funciones de partículas: (argumentos que se saltan, método de AtaqueVisual).
PARTICULAS = {
    "part_emitter_burst": (3, "burst"), "part_emitter_region": (2, "region"),
    "part_type_size": (1, "pt_size"), "part_type_scale": (1, "pt_scale"), "part_type_speed": (1, "pt_speed"),
    "part_type_direction": (1, "pt_direction"), "part_type_orientation": (1, "pt_orientation"),
    "part_type_life": (1, "pt_life"), "part_type_gravity": (1, "pt_gravity"), "part_type_color1": (1, "pt_color1"),
    "part_type_color2": (1, "pt_color2"), "part_type_color3": (1, "pt_color3"), "part_type_alpha1": (1, "pt_alpha1"),
    "part_type_alpha2": (1, "pt_alpha2"), "part_type_alpha3": (1, "pt_alpha3"), "part_type_blend": (1, "pt_blend"),
    "part_type_shape": (1, "pt_shape"), "part_type_sprite": (1, "pt_sprite"),
    "effect_create_above": (0, "effect_above"), "effect_create_below": (0, "effect_below"),
    "effect_create_sprite": (0, "effect_sprite"), "effect_create_sprite_fixed": (0, "effect_sprite"),
}
NO_OPS = {"part_system_depth", "part_system_create", "part_emitter_destroy", "part_type_destroy"}


class NoTraducible(Exception):
    pass


class Traductor:
    def __init__(self):
        self.sprites: set[int] = set()
        self.omitidas = 0
        self.traducidas = 0
        self.locales: set[str] = set()   # variables locales que son efectos (z = effect_create_sprite...)

    # expresiones ------------------------------------------------------------------------------
    def expr(self, e) -> str:
        k = e[0]
        if k == "num":
            return e[1] if "." in e[1] else e[1]
        if k == "str":
            raise NoTraducible("texto")
        if k == "id":
            n = e[1]
            if n in CONSTANTES:
                return str(CONSTANTES[n])
            if n in VARIABLES:
                return f"a.{n}"
            if n in self.locales:
                return n
            if n in NO_VARIABLES or n.startswith(("spr_", "obj_", "snd_", "bck_")):
                raise NoTraducible(n)
            return f'a.vars.get("{n}", 0)'  # variable propia del ataque o local (0 si no se asignó)
        if k == "campo":
            base, campo = e[1], e[2]
            if base == ("id", "creator") and campo in CAMPOS_CREADOR:
                return f"a.creator_{campo.lower()}"
            if base == ("id", "z") and campo in CAMPOS_EFECTO:
                return f'a.z_get("{campo}")'  # z: variable de instancia del ataque (un EfectoSprite)
            raise NoTraducible(f"campo {campo}")
        if k == "indice":
            raise NoTraducible("arreglo")
        if k == "un":
            op = {"!": "not ", "not": "not ", "-": "-", "+": "+"}[e[1]]
            return f"({op}{self.expr(e[2])})"
        if k == "bin":
            op = {"=": "==", "and": "and", "&&": "and", "||": "or", "or": "or", "xor": "!=",
                  "mod": "%", "div": "/"}.get(e[1], e[1])
            izq, der = self.expr(e[2]), self.expr(e[3])
            if e[1] in ("=", "=="):
                return f"a.eq({izq}, {der})"  # GML compara como números (true = 1)
            if e[1] == "!=":
                return f"(not a.eq({izq}, {der}))"
            if e[1] == "mod":
                return f"fmod({izq}, {der})"
            if e[1] == "div":
                return f"floorf(({izq}) / ({der}))"
            if e[1] == "/":
                return f"(float({izq}) / ({der}))"
            return f"({izq} {op} {der})"
        if k == "llamada":
            nombre, args = e[1], e[2]
            if nombre in FUNCIONES:
                return FUNCIONES[nombre]([self.expr(x) for x in args])
            if nombre in PARTICULAS:
                saltar, metodo = PARTICULAS[nombre]
                if nombre.startswith("effect_create_sprite") and args and args[0][0] == "num":
                    self.sprites.add(int(args[0][1]))
                if nombre == "part_type_sprite" and len(args) > 1 and args[1][0] == "num":
                    self.sprites.add(int(args[1][1]))
                return f"a.{metodo}({', '.join(self.expr(x) for x in args[saltar:])})"
            if nombre == "instance_create" and len(args) == 3 and args[2] == ("num", str(OBJETO_EFECTO_ALPHA)):
                return f"a.effect_alpha({self.expr(args[0])}, {self.expr(args[1])})"
            raise NoTraducible(f"función {nombre}")
        raise NoTraducible(k)

    # instrucciones ----------------------------------------------------------------------------
    def bloque(self, insts, ind: int) -> list[str]:
        out = []
        for inst in insts:
            out.extend(self.inst(inst, ind))
        return out

    def inst(self, i, ind: int) -> list[str]:
        p = "\t" * ind
        k = i[0]
        if k == "nada" or k == "var":
            return []
        if k == "error":
            self.omitidas += 1
            return []
        if k == "bloque":
            return self.bloque(i[1], ind)
        if k == "exit":
            return [p + "return"]
        try:
            if k == "if":
                cond = self.expr(i[1])
                entonces = self.inst(i[2], ind + 1) or [p + "\tpass"]
                out = [f"{p}if {cond}:"] + entonces
                if i[3] is not None:
                    sino = self.inst(i[3], ind + 1) or [p + "\tpass"]
                    out += [f"{p}else:"] + sino
                return out
            if k == "repeat":
                cuerpo = self.inst(i[2], ind + 1) or [p + "\tpass"]
                return [f"{p}for _i in int({self.expr(i[1])}):"] + cuerpo
            if k == "expr":
                nombre = i[1][1]
                if nombre in NO_OPS:
                    return []
                linea = self.expr(i[1])
                self.traducidas += 1
                return [p + linea]
            if k == "asig":
                lv, op, valor = i[1], i[2], i[3]
                if lv[0] == "id" and lv[1] in SIN_EFECTO:
                    if lv[1] == "pt1" and valor == ("llamada", "part_type_create", []):
                        self.traducidas += 1
                        return [p + "a.pt_create()"]
                    return []
                if lv[0] == "id" and lv[1] == "z" and valor[0] == "llamada":
                    linea = f"{p}a.z = {self.expr(valor)}"  # siempre devuelve un EfectoSprite
                    self.traducidas += 1
                    return [linea]
                if lv[0] == "campo" and lv[1] == ("id", "z") and lv[2] in CAMPOS_EFECTO:
                    v = self.expr(valor)
                    if op != "=":
                        v = f'a.z_get("{lv[2]}") {op[0]} {v}'
                    self.traducidas += 1
                    return [f'{p}a.z_set("{lv[2]}", {v})']
                if lv[0] == "id" and lv[1] not in VARIABLES and lv[1] not in CONSTANTES \
                        and lv[1] not in NO_VARIABLES and lv[1] not in self.locales:
                    destino = f'a.vars["{lv[1]}"]'
                    if op != "=":
                        self.traducidas += 1
                        return [f'{p}{destino} = a.vars.get("{lv[1]}", 0) {op[0]} {self.expr(valor)}']
                else:
                    destino = self.expr(lv)
                if lv[1:] == ("sprite_index",) or (lv[0] == "campo" and lv[2] == "sprite_index") or lv == ("id", "spr"):
                    if valor[0] == "num":
                        self.sprites.add(int(valor[1]))
                self.traducidas += 1
                return [f"{p}{destino} {op} {self.expr(valor)}"]
        except NoTraducible:
            self.omitidas += 1
            return [f"{p}pass  # omitido"] if k == "if" else []
        self.omitidas += 1
        return []

    def funcion(self, nombre: str, gml: str, doc: str) -> str:
        self.locales = set()
        arbol = Parser(tokenizar(gml)).programa()
        cuerpo = self.bloque(arbol, 1) or ["\tpass"]
        return f"## {doc}\nstatic func {nombre}(a: AtaqueVisual) -> void:\n" + "\n".join(cuerpo) + "\n"


def generar(efecto_especial: str, effect_atack_create: str, effect_atack: str) -> tuple[str, set[int], int, int]:
    """Devuelve (script GDScript, ids de sprites usados, instrucciones traducidas, omitidas)."""
    t = Traductor()
    # EfectoEspecial: entero (empieza creando el sistema global, que aquí no hace falta).
    especial = efecto_especial[efecto_especial.index("spr=(-1)"):]
    # EffectAtackCreate: desde que comprueba el emisor; antes hay lógica de batalla.
    crear = effect_atack_create[effect_atack_create.index("if(em=(-1) || pt1=(-1))exit;"):]
    # EffectAtack: los bloques por movimiento; antes ajusta velocidad y dirección (lógica).
    paso = effect_atack[effect_atack.index("if(index=1 || index=775)"):]
    partes = [
        "extends RefCounted\n## Generado por tools/extraer.py (gml_visual.py) desde EfectoEspecial, EffectAtackCreate\n"
        "## y EffectAtack del juego original. No editar: se regenera.\n",
        t.funcion("especial", especial, "EfectoEspecial: tipo de partícula del movimiento (spr/shape, size, spd, col, life)."),
        t.funcion("crear", crear, "EffectAtackCreate: sprite y efectos al lanzar el ataque."),
        t.funcion("paso", paso, "EffectAtack: lo que hace el ataque en cada step (ráfagas, efectos)."),
    ]
    return "\n\n".join(partes), t.sprites, t.traducidas, t.omitidas
