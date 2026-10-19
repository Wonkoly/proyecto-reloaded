"""Tablas de encuentros del original (AparicionSalvajes) como datos, con gml_eval.

AparicionSalvajes(Lugar, ModoAparicion, Valor, Dia, RespuestaRequerida) elige la especie según un
Valor de 1 a 1000. Para cada room y modo se evalúan los bloques que le tocan con Valor 1..1000 y se
cuenta cuántos valores ocupa cada especie (su peso). Lo que no es lógica pura se resuelve así:

- Banderas de la historia ((18).x): cada comparación sobre banderas es un "átomo" que se fuerza a
  verdadero o falso. Con 3 átomos o menos, una subtabla por combinación (agrupando las iguales) con
  su condición; con más (ruinas Unown, salas de fósiles), una subtabla con la condición en cada
  especie, comprobando que su peso no cambie según las demás banderas.
- Posición del jugador (X, Y): el mapa se parte por los umbrales del código y cada parte con otra
  tabla es una subtabla con zona (Rect2); la más común queda sin zona, al final.
- Día y noche: se evalúa con Dia = 1 y 0; si sale igual, una sola subtabla SIEMPRE.
- Nivel: NV = base + ceil(random(k)) → nivel_min = base + 1 y nivel_max = base + k (random se
  evalúa casi en 0 y en k). random(k) devuelve [0, k): ceil da 0 solo si sale 0 exacto
  (probabilidad ~0), y entonces el nivel sería base; se ignora.
- Partida nueva para lo demás: globales en 0, instance_exists falso, choose la primera opción,
  formas al azar (SelectRandom*) en 0.

La frecuencia y en qué rooms se activa cada modo salen de HierbasSalvajes; las zonas sin hierba
donde también hay salvajes (cuevas), de ActivacionSalvajes.
"""

from __future__ import annotations

import itertools
import json
import math
import random
import re
from collections import Counter
from pathlib import Path

import gml_eval
import gml_visual

# ModoAparicion → SubtablaEncuentros.Metodo (mismo orden que el enum).
METODOS = {1: "HIERBA", 2: "SURF", 3: "BARRO", 4: "HIERBA_ESPECIAL", 5: "CANA_VIEJA", 6: "CANA_BUENA",
           7: "SUPERCANA", 8: "HIERBA_INVISIBLE", 9: "LAVA"}
# Pescando: con cualquier caña pica 1 de cada 2 veces (if(ceil(random(2))=2) "no pica").
FRECUENCIA_PESCA = 2
# Hasta cuántos átomos de la historia se generan todas las combinaciones.
MAX_ATOMOS_COMBINAR = 3
COMPARACIONES = ("=", "==", "!=", "<", ">", "<=", ">=")
# Funciones del original que dependen de cosas que no existen todavía (se toman como 0).
SIN_SISTEMA = ("SalvajeCapturado", "GetIndexIsla", "TrainerBoy")


def _es_bandera(e) -> bool:
    return isinstance(e, tuple) and (e[:2] == ("campo", ("num", "18")) or (
        e[0] == "indice" and isinstance(e[1], tuple) and e[1][:2] == ("campo", ("num", "18"))))


def _usa(e, prueba) -> bool:
    if not isinstance(e, (tuple, list)):
        return False
    if isinstance(e, tuple) and prueba(e):
        return True
    return any(_usa(x, prueba) for x in e if isinstance(x, (tuple, list)))


def _es_pos(e) -> bool:
    return e in (("id", "X"), ("id", "Y"))


class Contexto(gml_eval.Funciones):
    """gml_eval con el contexto de una partida nueva, una room, una posición y átomos forzados."""

    def __init__(self, carpeta: Path):
        super().__init__(carpeta)
        self.lugar = 0.0
        self.pos = (0.0, 0.0)
        self.aleatorio = "min"
        self.dia = 1.0
        self.forzar: dict[int, bool] = {}
        self.supuestos: Counter = Counter()

    def _valor(self, e, loc, prof):
        if id(e) in self.forzar:
            return float(self.forzar[id(e)])
        k = e[0]
        if k == "id" and e[1] == "room":
            return self.lugar
        if k == "campo":
            if e[1] == ("num", "18"):
                return 0.0
            if e[1] == ("id", "global"):
                if e[2] in ("xx", "yy"):
                    return self.pos[0 if e[2] == "xx" else 1]
                self.supuestos["global." + e[2]] += 1
                return 0.0
            if e[1] == ("num", "14") and e[2] in ("x", "y"):
                return self.pos[0 if e[2] == "x" else 1]
            if e[1] == ("num", "66") and e[2] == "Hora":
                # obj_DayNightControl.Hora: 12 de día, 22 de noche (el caso exacto de las 19:00 se pierde).
                self.supuestos["(66).Hora"] += 1
                return 12.0 if self.dia else 22.0
            raise gml_eval.Desconocido(f"campo {e[1]}.{e[2]}")
        if k == "indice" and e[1][0] != "id":
            return 0.0
        if k == "llamada":
            n = e[1]
            if n == "random":
                a = self._valor(e[2][0], loc, prof)
                return a if self.aleatorio == "max" else a * 1e-9
            if n == "ceil":
                return float(math.ceil(self._valor(e[2][0], loc, prof)))
            if n == "choose":
                return self._valor(e[2][0], loc, prof)
            if n in ("instance_exists", "instance_number") or n in SIN_SISTEMA or n.startswith("SelectRandom"):
                self.supuestos[n] += 1
                return 0.0
            if n == "IfElse":
                return self._valor(e[2][1] if self._valor(e[2][0], loc, prof) else e[2][2], loc, prof)
        return super()._valor(e, loc, prof)

    def correr(self, instrucciones: list, loc: dict) -> None:
        self._cache.clear()
        try:
            for s in instrucciones:
                self._ejecutar(s, loc, 0)
        except gml_eval._Retorno:
            pass


def a_gdscript(e) -> str:
    """Un átomo de la historia como expresión de GDScript sobre h (como en los mapas)."""
    k = e[0]
    if k == "num":
        v = float(e[1])
        return str(int(v)) if v.is_integer() else repr(v)
    if k == "id" and e[1] in ("true", "false"):
        return "1" if e[1] == "true" else "0"
    if k == "campo" and e[1] == ("num", "18"):
        return f'h.get("{e[2]}", 0)'
    if k == "indice" and _es_bandera(e) and e[2][0] == "num":
        return f'h.get("{e[1][2]}_{int(float(e[2][1]))}", 0)'
    if k == "un":
        return f"(not {a_gdscript(e[2])})" if e[1] in ("!", "not") else f"(-{a_gdscript(e[2])})"
    if k == "bin":
        op = {"=": "==", "&&": "and", "||": "or"}.get(e[1], e[1])
        return f"({a_gdscript(e[2])} {op} {a_gdscript(e[3])})"
    raise ValueError(f"no se puede escribir {e!r}")


class Generador:
    def __init__(self, ext: Path):
        self.ext = ext
        self.carpeta = ext / "scripts"
        self.rooms: list[str] = json.loads((ext / "index.json").read_text())["rooms"]
        arbol = gml_visual.Parser(gml_visual.tokenizar((self.carpeta / "AparicionSalvajes.gml").read_text())).programa()
        self.modos: dict[int, list] = {}
        for inst in arbol:
            if inst[0] == "if" and inst[1][0] == "bin" and inst[1][2] == ("id", "ModoAparicion"):
                self.modos[int(float(inst[1][3][1]))] = inst[2][1] if inst[2][0] == "bloque" else [inst[2]]
        self.ctx = Contexto(self.carpeta)
        self.activacion = activacion_modos(self.carpeta.joinpath("HierbasSalvajes.gml").read_text())
        self.sin_hierba_arbol = gml_visual.Parser(gml_visual.tokenizar(
            (self.carpeta / "ActivacionSalvajes.gml").read_text())).programa()
        self.problemas: list[str] = []
        self.sin_nivel = 0
        self._avisados: set = set()

    def tamano(self, room: str) -> tuple[int, int]:
        r = json.loads((self.ext / "rooms" / f"{room}.json").read_text())
        return r["width"], r["height"]

    # -- evaluación ------------------------------------------------------------------------

    def _aplican(self, modo: int, ridx: int) -> list:
        """Los bloques del modo que tocan a esta room (if(Lugar=(N) || ...) que da verdadero)."""
        self.ctx.lugar = float(ridx)
        base = {"Lugar": float(ridx), "ModoAparicion": float(modo), "Valor": 500.0, "Dia": 1.0}
        # Las instrucciones del modo que no dependen del lugar (p. ej. NV=1+ceil(random(14)) en la caña
        # vieja) también cuentan, en su orden. Si no hay ningún bloque de esta room, no hay tabla.
        out, alguno = [], False
        for s in self.modos.get(modo, []):
            if s[0] != "if" or not _usa(s[1], lambda e: e == ("id", "Lugar")):
                out.append(s)
                continue
            if _usa(s[1], _es_pos):
                # if(Lugar=(51) && X<520): depende de la posición; va entero y lo decide la zona.
                if _usa(s[1], lambda e: e[0] == "bin" and e[2] == ("id", "Lugar") and e[3] == ("num", str(ridx))):
                    out.append(s)
                    alguno = True
                continue
            try:
                if self.ctx._valor(s[1], dict(base), 0):
                    out.append(s[2])
                    alguno = True
            except gml_eval.Desconocido as error:
                self.problemas.append(f"{self.rooms[ridx]} modo {modo}: no se pudo evaluar la condición de un "
                                      f"bloque ({error})")
        return out if alguno else []

    def tabla(self, bloques: list, modo: int, ridx: int, dia: float) -> dict:
        """{especie: [peso, nivel_min, nivel_max]}, raros, súper raros (con el contexto actual)."""
        entradas: dict[int, list] = {}
        raros: set = set()
        super_raros: set = set()
        self.ctx.dia = dia
        for v in range(1, 1001):
            fila = []
            for aleatorio in ("min", "max"):
                self.ctx.aleatorio = aleatorio
                loc = {"Lugar": float(ridx), "ModoAparicion": float(modo), "Valor": float(v), "Dia": dia,
                       "RespuestaRequerida": 1.0, "X": self.ctx.pos[0], "Y": self.ctx.pos[1],
                       "NV": 0.0, "PK": 0.0, "RARO": 0.0, "SUPER_RARO": 0.0}
                try:
                    self.ctx.correr(bloques, loc)
                except gml_eval.Desconocido as error:
                    clave = f"{self.rooms[ridx]} {METODOS[modo]}: {error}"
                    if clave not in self._avisados:
                        self._avisados.add(clave)
                        self.problemas.append(clave + " (esos valores quedan sin encuentro)")
                    break
                fila.append(loc)
            if len(fila) < 2:
                continue
            lo, hi = fila
            pk = int(lo["PK"])
            if pk and hi["NV"] <= 0:
                # if(Pokemon<=0 || NV<=0){}: sin nivel no hay encuentro (cañas en las salas de fósiles).
                self.sin_nivel += 1
                pk = 0
            if pk:
                e = entradas.setdefault(pk, [0, 999, 0])
                e[0] += 1
                e[1] = min(e[1], int(lo["NV"]))
                e[2] = max(e[2], int(hi["NV"]))
        self.ctx.aleatorio = "min"
        for b in bloques:
            for nombre, destino in (("RARO", raros), ("SUPER_RARO", super_raros)):
                destino.update(_especies_asignadas(b, nombre))
        return {"entradas": entradas, "raros": sorted(raros), "super_raros": sorted(super_raros)}

    # -- una room y un modo → subtablas -------------------------------------------------------

    def subtablas(self, modo: int, ridx: int) -> list[dict]:
        bloques = self._aplican(modo, ridx)
        if not bloques:
            return []
        atomos = _atomos(bloques)
        usa_dia = _usa(bloques, lambda e: e == ("id", "Dia"))
        ancho, alto = self.tamano(self.rooms[ridx])
        celdas = _celdas(bloques, ancho, alto)
        resultados = []  # (condicion, zona, horario, tabla, condiciones por especie)
        for cond, forzar, por_especie in self._casos_historia(bloques, modo, ridx, atomos, usa_dia):
            for horario, dia in ((("DIA", 1.0), ("NOCHE", 0.0)) if usa_dia else (("SIEMPRE", 1.0),)):
                por_celda = []
                for rect, punto in celdas:
                    self.ctx.forzar, self.ctx.pos = forzar, punto
                    por_celda.append((rect, self.tabla(bloques, modo, ridx, dia)))
                self.ctx.forzar, self.ctx.pos = {}, (0.0, 0.0)
                for zona, t in _zonas(por_celda):
                    resultados.append({"condicion": cond, "zona": zona, "horario": horario, "tabla": t,
                                       "condicion_especie": por_especie})
        # Día y noche iguales en todas las variantes → SIEMPRE.
        if usa_dia:
            dias = [r for r in resultados if r["horario"] == "DIA"]
            noches = [r for r in resultados if r["horario"] == "NOCHE"]
            if all(_igual(a["tabla"], b["tabla"]) for a, b in zip(dias, noches)):
                resultados = [dict(r, horario="SIEMPRE") for r in dias]
        # Zonas primero (gana la primera que coincide), la general al final.
        resultados.sort(key=lambda r: r["zona"] is None)
        return [r for r in resultados if r["tabla"]["entradas"]]

    def _casos_historia(self, bloques, modo, ridx, atomos, usa_dia):
        """[(condición de la subtabla, átomos forzados, {especie: condición})]."""
        if not atomos:
            return [("", {}, {})]
        if len(atomos) <= MAX_ATOMOS_COMBINAR:
            grupos: list[tuple[dict, list]] = []
            for valores in itertools.product((False, True), repeat=len(atomos)):
                self.ctx.forzar = _forzar(atomos, valores)
                firma = self.tabla(bloques, modo, ridx, 1.0)
                if usa_dia:
                    firma = (firma, self.tabla(bloques, modo, ridx, 0.0))
                for g in grupos:
                    if _igual(g[0], firma):
                        g[1].append(valores)
                        break
                else:
                    grupos.append((firma, [valores]))
            self.ctx.forzar = {}
            return [(_condicion(atomos, combos), _forzar(atomos, combos[0]), {})
                    for _, combos in grupos]
        # Muchas banderas (Unown, fósiles): condición por especie.
        todos = _forzar(atomos, [True] * len(atomos))
        self.ctx.forzar = todos
        base = self.tabla(bloques, modo, ridx, 1.0)["entradas"]
        por_especie: dict[int, list] = {pk: [] for pk in base}
        for a in atomos:
            self.ctx.forzar = {**todos, **{id(n): False for n in a}}
            sin = self.tabla(bloques, modo, ridx, 1.0)["entradas"]
            for pk in base:
                if pk not in sin:
                    por_especie[pk].append(a_gdscript(a[0]))
        # Comprobación: con cualquier combinación, la tabla es la base filtrada por esas condiciones
        # y el peso de cada especie no cambia.
        combos = list(itertools.product((False, True), repeat=len(atomos)))
        if len(combos) > 48:
            combos = random.Random(0).sample(combos, 48)
        for valores in combos:
            self.ctx.forzar = _forzar(atomos, valores)
            real = self.tabla(bloques, modo, ridx, 1.0)["entradas"]
            verdad = {a_gdscript(a[0]): v for a, v in zip(atomos, valores)}
            esperada = {pk: e for pk, e in base.items() if all(verdad[c] for c in por_especie[pk])}
            if {pk: e[0] for pk, e in real.items()} != {pk: e[0] for pk, e in esperada.items()}:
                self.problemas.append(f"{self.rooms[ridx]} modo {modo}: el peso de las especies cambia según "
                                      f"otras banderas; no se genera")
                self.ctx.forzar = {}
                return []
        self.ctx.forzar = {}
        return [("", todos, {pk: " and ".join(c) for pk, c in por_especie.items() if c})]

    # -- zonas sin hierba (ActivacionSalvajes) ------------------------------------------------

    def sin_hierba(self, ridx: int) -> list[tuple[float, float, float, float]]:
        ancho, alto = self.tamano(self.rooms[ridx])
        # ActivacionSalvajes: con obj_cueva en la room (las 124 cuevas) hay salvajes en toda la room.
        # NIEBLA y TOR_ARENA (los crea el clima, que no existe todavía) harían lo mismo.
        room = json.loads((self.ext / "rooms" / f"{self.rooms[ridx]}.json").read_text())
        if any(i["object"] == "obj_cueva" for i in room["instances"]):
            return [(0.0, 0.0, float(ancho), float(alto))]
        out = []
        self.ctx.lugar = float(ridx)
        for rect, punto in _celdas(_de_la_room(self.sin_hierba_arbol, ridx), ancho, alto):
            self.ctx.pos = punto
            if self.ctx.llamar_contexto("ActivacionSalvajes"):
                out.append(rect)
        self.ctx.pos = (0.0, 0.0)
        return _unir(out)

    # -- todo ---------------------------------------------------------------------------------

    def generar(self) -> dict[str, dict]:
        """{room: {"subtablas": [...], "sin_hierba": [...]}} de todas las rooms con algo."""
        out: dict[str, dict] = {}
        for ridx, room in enumerate(self.rooms):
            subs = []
            for modo in sorted(self.modos):
                act = self.activacion.get(modo)
                for s in self.subtablas(modo, ridx):
                    s["metodo"] = METODOS[modo]
                    if modo in (5, 6, 7):
                        s["frecuencia"] = FRECUENCIA_PESCA
                    else:
                        s["frecuencia"] = act["frecuencia"](ridx) if act else 150
                    s["codigo_muerto"] = bool(act and act.get("codigo_muerto"))
                    if act and act["rooms"] is not None and ridx not in act["rooms"]:
                        self.problemas.append(f"{room} {METODOS[modo]}: tiene tabla pero HierbasSalvajes no "
                                              f"activa ese modo en la room (no se usa en el original)")
                        continue
                    subs.append(s)
            zonas = self.sin_hierba(ridx)
            if subs or zonas:
                out[room] = {"subtablas": subs, "sin_hierba": zonas}
        return out


def _llamar_contexto(self: Contexto, nombre: str):
    self._cache.clear()
    return self.llamar(nombre)


Contexto.llamar_contexto = _llamar_contexto


def _de_la_room(arbol, ridx: int) -> list:
    """Las partes de una condición que hablan de esta room (room=(N) && X<=646...), para no partir el
    mapa con los umbrales de las demás."""
    out = []

    def menciona(x):
        return _usa(x, lambda e: e[0] == "bin" and e[1] in ("=", "==") and e[2] == ("id", "room")
                    and e[3] == ("num", str(ridx)))

    def recorrer(x):
        if isinstance(x, tuple) and x and x[0] == "bin" and x[1] in ("&&", "and") and menciona(x):
            out.append(x)
            return
        if isinstance(x, (tuple, list)):
            for y in x:
                recorrer(y)

    recorrer(arbol)
    return out


def _igual(a, b) -> bool:
    return json.dumps(a, sort_keys=True, default=str) == json.dumps(b, sort_keys=True, default=str)


def _especies_asignadas(e, variable: str) -> set[int]:
    """Las especies posibles en RARO=choose(...) / SUPER_RARO=... (todas las opciones de choose)."""
    out: set[int] = set()

    def numeros(x):
        if isinstance(x, tuple) and x[0] == "num":
            out.add(int(float(x[1])))
        elif isinstance(x, (tuple, list)):
            for y in x:
                numeros(y)

    def buscar(x):
        if isinstance(x, tuple) and x[0] == "asig" and x[1] == ("id", variable):
            numeros(x[3])
        elif isinstance(x, (tuple, list)):
            for y in x:
                buscar(y)

    buscar(e)
    return {n for n in out if n > 0}


def _atomos(bloques: list) -> list:
    """Las comparaciones (o banderas sueltas) sobre la historia que deciden algo en los bloques."""
    vistos: dict[int, tuple] = {}

    def desde_condicion(c):
        if c[0] == "bin" and c[1] in ("&&", "||", "and", "or"):
            desde_condicion(c[2])
            desde_condicion(c[3])
        elif c[0] == "un" and c[1] in ("!", "not"):
            desde_condicion(c[2])
        elif _usa(c, _es_bandera):
            vistos[id(c)] = c

    def recorrer(x):
        if not isinstance(x, (tuple, list)):
            return
        if isinstance(x, tuple) and x and x[0] in ("if", "while") and isinstance(x[1], tuple):
            desde_condicion(x[1])
        if isinstance(x, tuple) and x and x[0] == "llamada" and x[1] == "IfElse":
            desde_condicion(x[2][0])
        for y in x:
            recorrer(y)

    recorrer(bloques)
    # La misma comparación escrita en varios sitios es un solo átomo (se fuerza junta).
    grupos: dict[str, list] = {}
    for nodo in vistos.values():
        try:
            grupos.setdefault(a_gdscript(nodo), []).append(nodo)
        except ValueError:
            grupos.setdefault(repr(nodo), []).append(nodo)
    return list(grupos.values())


def _forzar(atomos: list, valores) -> dict[int, bool]:
    return {id(n): v for grupo, v in zip(atomos, valores) for n in grupo}


def _condicion(atomos: list, combos: list[tuple]) -> str:
    """La condición (GDScript sobre h) que cubre exactamente esas combinaciones de los átomos."""
    total = 2 ** len(atomos)
    if len(combos) == total:
        return ""
    gd = [a_gdscript(a[0]) for a in atomos]
    conjunto = set(combos)
    # Un solo átomo o una conjunción de literales.
    for r in range(1, len(atomos) + 1):
        for indices in itertools.combinations(range(len(atomos)), r):
            for valores in itertools.product((False, True), repeat=r):
                cubre = {c for c in itertools.product((False, True), repeat=len(atomos))
                         if all(c[i] == v for i, v in zip(indices, valores))}
                if cubre == conjunto:
                    return " and ".join(g if v else f"not {g}" for g, v in zip([gd[i] for i in indices], valores))
    return " or ".join("(" + " and ".join(g if v else f"not {g}" for g, v in zip(gd, c)) + ")" for c in combos)


def _celdas(arbol, ancho: int, alto: int) -> list[tuple[tuple, tuple]]:
    """Partes del mapa según los umbrales de X e Y del código: [(rect x0, y0, x1, y1, punto)]."""
    umbrales = {"X": set(), "Y": set()}

    def recorrer(x):
        if isinstance(x, tuple) and x and x[0] == "bin" and x[1] in COMPARACIONES:
            for a, b in ((x[2], x[3]), (x[3], x[2])):
                if _es_pos(a) and isinstance(b, tuple) and b[0] == "num":
                    umbrales[a[1]].add(float(b[1]))
        if isinstance(x, (tuple, list)):
            for y in x:
                recorrer(y)

    recorrer(arbol)

    def tramos(cortes: set, limite: int) -> list[tuple[float, float, float]]:
        pts = sorted(c for c in cortes if 0 < c < limite)
        bordes = [0.0] + pts + [float(limite)]
        out = []
        for a, b in zip(bordes, bordes[1:]):
            # El punto representativo: en medio; en un corte exacto (X = t, X <= t) se prueba a ambos lados.
            out.append((a, b, (a + b) / 2 if b - a > 1 else a))
        return out

    return [((x0, y0, x1, y1), (px, py)) for x0, x1, px in tramos(umbrales["X"], ancho)
            for y0, y1, py in tramos(umbrales["Y"], alto)]


def _zonas(por_celda: list[tuple[tuple, dict]]) -> list[tuple[tuple | None, dict]]:
    """Agrupa las partes con la misma tabla. La más común queda sin zona; las demás, un rectángulo
    por parte (unidas si se tocan)."""
    if len(por_celda) == 1:
        return [(None, por_celda[0][1])]
    grupos: list[tuple[dict, list]] = []
    for rect, t in por_celda:
        for g in grupos:
            if _igual(g[0], t):
                g[1].append(rect)
                break
        else:
            grupos.append((t, [rect]))
    grupos.sort(key=lambda g: -sum((r[2] - r[0]) * (r[3] - r[1]) for r in g[1]))
    out = []
    for t, rects in grupos[1:]:
        for r in _unir(rects):
            out.append((r, t))
    out.append((None, grupos[0][0]))
    return out


def _unir(rects: list[tuple]) -> list[tuple]:
    """Une rectángulos vecinos de la misma fila y columna (las partes vienen de una rejilla)."""
    rects = sorted(rects, key=lambda r: (r[1], r[0]))
    filas: list[list] = []
    for r in rects:
        u = filas[-1] if filas else None
        if u and u[1] == r[1] and u[3] == r[3] and u[2] == r[0]:
            u[2] = r[2]
        else:
            filas.append(list(r))
    out: list[list] = []
    for r in sorted(filas, key=lambda r: (r[0], r[1])):
        u = next((o for o in out if o[0] == r[0] and o[2] == r[2] and o[3] == r[1]), None)
        if u:
            u[3] = r[3]
        else:
            out.append(r)
    return [tuple(r) for r in out]


def activacion_modos(gml: str) -> dict[int, dict]:
    """En qué rooms activa HierbasSalvajes cada modo y con qué frecuencia (1 entre N por step en
    movimiento, FrequencySalvajes).

    - Surf (2), barro (3), hierba invisible (8) y lava (9): una lista de rooms y una frecuencia.
    - Hierba (1): la lista de rooms tiene "|| (24) ||", que siempre es verdadero: vale en todas. La
      frecuencia es 200, 125 o 150 según la room (MAX_FREQUENCY; el caso de 100 depende de un evento).
    - Hierba especial (4): su bloque va después del de hierba, que siempre sale con exit: es código
      muerto del original.
    """
    out: dict[int, dict] = {}
    for modo in (2, 3, 8, 9, 4):
        m = re.search(r"AparicionSalvajes\(room,\(%d\),Valor" % modo, gml)
        if not m:
            continue
        antes = gml[:m.start()]
        i = antes.rfind("if(room=")
        cond = antes[i:antes.index("{", i)]
        rooms = {int(x) for x in re.findall(r"room=\((\d+)\)", cond)}
        freq = int(re.findall(r"FrequencySalvajes\((\d+)\)", antes[i:])[0])
        out[modo] = {"rooms": rooms, "frecuencia": (lambda f: lambda _r: f)(freq), "codigo_muerto": modo == 4}
    especiales = []
    for lista, f in re.findall(r"if\(((?:room=\(\d+\)\s*\|\|\s*)*room=\(\d+\))\)MAX_FREQUENCY=(\d+)", gml):
        especiales.append(({int(x) for x in re.findall(r"\((\d+)\)", lista)}, int(f)))
    m = re.search(r"else MAX_FREQUENCY=(\d+)", gml)
    defecto = int(m.group(1)) if m else 150

    def freq_hierba(ridx: int) -> int:
        return next((f for rooms, f in especiales if ridx in rooms), defecto)

    out[1] = {"rooms": None, "frecuencia": freq_hierba, "codigo_muerto": False}
    return out
