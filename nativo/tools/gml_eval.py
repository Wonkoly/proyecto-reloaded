"""Evalúa funciones puras del original (GML) en Python, para precalcular tablas como datos.

Sirve para scripts que son lógica sin estado del juego (MYSON, GrupoHuevo1, OneSex...): variables
locales y arrays locales (a[i]), if/else, for/while/repeat, return y llamadas a otros scripts
(recursivas). Si una función toca algo que no se puede saber (globales, instancias, random), devuelve
None. Una subclase puede dar valores a esas cosas redefiniendo _valor (ver encuentros_original.py).
"""

from __future__ import annotations

from pathlib import Path

import gml_visual


class Desconocido(Exception):
    pass


# Tope de vueltas de un bucle (un while que no termina no cuelga la extracción).
MAX_VUELTAS = 100000


class _Retorno(Exception):
    def __init__(self, valor):
        self.valor = valor


class Funciones:
    def __init__(self, carpeta_scripts: Path):
        self.carpeta = carpeta_scripts
        self._arboles: dict[str, list] = {}
        self._cache: dict[tuple, object] = {}

    def llamar(self, nombre: str, *args):
        """Valor de la función o None si no se puede calcular."""
        try:
            return self._llamar(nombre, list(args), 0)
        except (Desconocido, RecursionError, ZeroDivisionError):
            return None

    def _arbol(self, nombre: str):
        if nombre not in self._arboles:
            ruta = self.carpeta / f"{nombre}.gml"
            if not ruta.exists():
                raise Desconocido(nombre)
            self._arboles[nombre] = gml_visual.Parser(gml_visual.tokenizar(ruta.read_text(encoding="utf-8"))).programa()
        return self._arboles[nombre]

    def _llamar(self, nombre: str, args: list, profundidad: int):
        clave = (nombre, tuple(args))
        if clave in self._cache:
            return self._cache[clave]
        if profundidad > 40:
            raise Desconocido("recursión")
        locales = {f"argument{i}": a for i, a in enumerate(args)}
        locales["argument"] = args
        try:
            for inst in self._arbol(nombre):
                self._ejecutar(inst, locales, profundidad)
            valor = 0.0
        except _Retorno as r:
            valor = r.valor
        self._cache[clave] = valor
        return valor

    def _ejecutar(self, i, loc, prof):
        k = i[0]
        if k == "bloque":
            for x in i[1]:
                self._ejecutar(x, loc, prof)
        elif k == "if":
            if self._valor(i[1], loc, prof):
                self._ejecutar(i[2], loc, prof)
            elif i[3] is not None:
                self._ejecutar(i[3], loc, prof)
        elif k == "return":
            raise _Retorno(self._valor(i[1], loc, prof) if i[1] is not None else 0.0)
        elif k == "exit":
            raise _Retorno(0.0)
        elif k == "asig":
            lv, op = i[1], i[2]
            v = self._valor(i[3], loc, prof)
            if lv[0] == "id":
                if op != "=":
                    v = _operar(op, loc.get(lv[1], 0.0), v)
                loc[lv[1]] = v
            elif lv[0] == "indice" and lv[1][0] == "id":
                # Array local: a[i] = v (en GM el array nace al asignarle un índice).
                arr = loc.get(lv[1][1])
                if not isinstance(arr, dict):
                    arr = loc[lv[1][1]] = {}
                n = int(self._valor(lv[2], loc, prof))
                arr[n] = _operar(op, arr.get(n, 0.0), v) if op != "=" else v
            else:
                raise Desconocido("asignación a campo")
        elif k == "for":
            self._ejecutar(i[1], loc, prof)
            for _ in range(MAX_VUELTAS):
                if not self._valor(i[2], loc, prof):
                    break
                self._ejecutar(i[4], loc, prof)
                self._ejecutar(i[3], loc, prof)
            else:
                raise Desconocido("bucle sin fin")
        elif k == "while":
            for _ in range(MAX_VUELTAS):
                if not self._valor(i[1], loc, prof):
                    break
                self._ejecutar(i[2], loc, prof)
            else:
                raise Desconocido("bucle sin fin")
        elif k == "repeat":
            for _ in range(min(int(self._valor(i[1], loc, prof)), MAX_VUELTAS)):
                self._ejecutar(i[2], loc, prof)
        elif k == "expr":
            self._valor(i[1], loc, prof)
        elif k in ("var", "nada"):
            pass
        else:
            raise Desconocido(k)

    def _valor(self, e, loc, prof):
        k = e[0]
        if k == "num":
            return float(e[1])
        if k == "str":
            return e[1]
        if k == "id":
            if e[1] in loc:
                return loc[e[1]]
            if e[1] in gml_visual.CONSTANTES and not isinstance(gml_visual.CONSTANTES[e[1]], str):
                return float(gml_visual.CONSTANTES[e[1]])
            raise Desconocido(e[1])
        if k == "indice" and e[1][0] == "id" and isinstance(loc.get(e[1][1]), dict):
            return loc[e[1][1]].get(int(self._valor(e[2], loc, prof)), 0.0)
        if k == "un":
            v = self._valor(e[2], loc, prof)
            return float(not v) if e[1] in ("!", "not") else -v
        if k == "bin":
            op = e[1]
            if op in ("&&", "and"):
                return float(bool(self._valor(e[2], loc, prof)) and bool(self._valor(e[3], loc, prof)))
            if op in ("||", "or"):
                return float(bool(self._valor(e[2], loc, prof)) or bool(self._valor(e[3], loc, prof)))
            a, b = self._valor(e[2], loc, prof), self._valor(e[3], loc, prof)
            operaciones = {"=": lambda: a == b, "==": lambda: a == b, "!=": lambda: a != b, "<": lambda: a < b,
                           ">": lambda: a > b, "<=": lambda: a <= b, ">=": lambda: a >= b, "+": lambda: a + b,
                           "-": lambda: a - b, "*": lambda: a * b, "/": lambda: a / b, "mod": lambda: a % b,
                           "div": lambda: a // b}
            r = operaciones[op]()
            return float(r) if isinstance(r, bool) else r
        if k == "llamada":
            nombre, args = e[1], [self._valor(a, loc, prof) for a in e[2]]
            if nombre == "abs":
                return abs(args[0])
            if nombre == "frac":
                return args[0] - int(args[0])
            if nombre == "floor":
                return float(int(args[0] // 1))
            if nombre == "ceil":
                return float(-int(-args[0] // 1))
            if nombre in ("random", "irandom", "choose", "random_range") or (
                    nombre.startswith(("instance_", "Get", "Draw")) and nombre not in GET_PUROS):
                raise Desconocido(nombre)
            return self._llamar(nombre, args, prof + 1)
        raise Desconocido(k)


# Funciones Get* que solo dependen de sus argumentos (las demás leen el estado del juego).
GET_PUROS = {"GetOrdenDex", "GetCrecimiento"}


def _operar(op: str, a, b):
    return {"+=": lambda: a + b, "-=": lambda: a - b, "*=": lambda: a * b, "/=": lambda: a / b}[op]()
