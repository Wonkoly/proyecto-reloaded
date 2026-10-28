"""Eventos de las tiendas (TenderoHabla) y de los NPC que regalan objetos (RegalarHabla).

TenderoHabla: saluda, pregunta Comprar / Vender / No hacer nada y, al comprar, arma la lista con
ItemDistribution(z, desde, hasta, objetos...): pone los objetos en las casillas desde..hasta (lo que
viene después pisa lo anterior). La lista depende del mapa, de global.index_place (las tiendas de ciudad
comparten la room Tienda_Pokemon) y de banderas. Se traduce a un .evento con "tienda_poner" dentro de
los mismos "si". Lo que no se puede traducir (bucles sobre banderas de la Frente) se avisa en el evento.

Solo biblioteca estándar.
"""
from __future__ import annotations

import re

import entrenadores_original
import gml_visual


def _cond(e, room: int) -> str | None:
    """La condición como condición de evento; "1"/"0" si se decide aquí (room, TrainerBoy); None si no."""
    k = e[0]
    if k == "bin" and e[1] in ("=", "==") and e[2] == ("id", "room"):
        return "1" if e[3][0] == "num" and int(float(e[3][1])) == room else "0"
    if k == "bin" and e[1] in ("||", "or", "&&", "and"):
        a, b = _cond(e[2], room), _cond(e[3], room)
        if a is None or b is None:
            return None
        o = e[1] in ("||", "or")
        if a in ("0", "1") and b in ("0", "1"):
            return "1" if ((a == "1") or (b == "1") if o else (a == "1") and (b == "1")) else "0"
        if a in ("0", "1"):
            return (b if o and a == "0" else "1") if o else (b if a == "1" else "0")
        if b in ("0", "1"):
            return (a if o and b == "0" else "1") if o else (a if b == "1" else "0")
        return f"({a} {'o' if o else 'y'} {b})"
    if k == "llamada" and e[1] == "TrainerBoy":
        return "1"  # el protagonista por defecto es un chico
    if k == "bin" and e[2] == ("campo", ("id", "global"), "index_place") and e[3][0] == "num":
        op = {"=": "==", "==": "==", "!=": "!=", "<": "<", ">": ">", "<=": "<=", ">=": ">="}.get(e[1])
        return f"lugar {op} {int(float(e[3][1]))}" if op else None
    try:
        c = entrenadores_original._condicion(_bool_a_num(e))
    except entrenadores_original._Raro:
        return None
    return c.replace("true", "1").replace("false", "0")


def _bool_a_num(e):
    """true/false del GML como 1/0 (para que las condiciones se puedan traducir)."""
    if isinstance(e, tuple):
        if e in (("id", "true"), ("id", "false")):
            return ("num", "1" if e[1] == "true" else "0")
        return tuple(_bool_a_num(x) for x in e)
    if isinstance(e, list):
        return [_bool_a_num(x) for x in e]
    return e


def _bloque_compra(arbol, room: int, sangria: str, out: list[str], avisos: list[str]) -> None:
    for i in arbol:
        k = i[0]
        if k == "bloque":
            _bloque_compra(i[1], room, sangria, out, avisos)
        elif k == "if":
            c = _cond(i[1], room)
            if c is None:
                avisos.append("una condición no se pudo traducir")
                continue
            ramas = [(c, i[2])] + ([("no (" + c + ")" if c not in ("0", "1") else ("1" if c == "0" else "0"), i[3])] if i[3] else [])
            for cond, cuerpo in ramas:
                if cond == "0":
                    continue
                if cond == "1":
                    _bloque_compra([cuerpo], room, sangria, out, avisos)
                    continue
                sub: list[str] = []
                _bloque_compra([cuerpo], room, sangria + "    ", sub, avisos)
                if sub:
                    out.append(f"{sangria}si {cond}:")
                    out.extend(sub)
        elif k == "expr" and i[1][0] == "llamada" and i[1][1] == "ItemDistribution":
            args = i[1][2]
            try:
                desde = int(float(args[1][1]))
                ids = [str(int(float(a[1]))) for a in args[3:]]
            except (TypeError, ValueError, IndexError):
                avisos.append("un ItemDistribution raro")
                continue
            out.append(f"{sangria}tienda_poner {desde} {' '.join(ids)}")
        elif k == "for":
            avisos.append("objetos según banderas en un bucle (no traducido)")
        elif k == "exit":
            return


def evento_tienda(juego, room: int, room_nombre: str) -> str:
    gml = juego.script("TenderoHabla")
    m = re.search(r"if\(Q=1\)\{(.*)\} if\(Q=2\)", gml)
    arbol = gml_visual.Parser(gml_visual.tokenizar(m.group(1))).programa() if m else []
    saludo = {159: 8507, 160: 8507, 161: 8507, 162: 8507, 163: 8507, 164: 8507, 242: 10679, 556: 12423, 322: 14740}.get(room, 3490)
    compra: list[str] = []
    avisos: list[str] = []
    # Dialogo(TextDialog(3496)) y el resto de la rama Q=1: la lista de objetos.
    _bloque_compra(arbol, room, "    ", compra, avisos)
    compra = [l for l in compra if not l.strip().startswith("decir")]
    lineas = [f"# Tendero ({room_nombre}): TenderoHabla. Generado por tools/extraer.py (ver docs/eventos.md).",
              "# tienda_poner <casilla> <objetos...> pone objetos en la lista desde esa casilla (pisa lo que había)."]
    lineas += [f"# Aviso: {a}" for a in sorted(set(avisos))]
    lineas += [f"decir {saludo}", "elegir 3492 3493 3494 3495",
               "si opcion == 1:", "    decir 3496"] + compra + ["    tienda",
               "sino si opcion == 2:", "    decir 3497", "    vender",
               "sino:", "    decir 2451"]
    return "\n".join(lineas) + "\n"


def banderas_regalo(juego) -> dict[int, str]:
    """RegalarHabla: INDEX → bandera que se pone al recibir el regalo."""
    return {int(n): b for n, b in re.findall(r"if\(INDEX=(\d+)\)\(18\)\.(\w+)=true;", juego.script("RegalarHabla"))}
