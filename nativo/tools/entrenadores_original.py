"""Equipos de los entrenadores del original (TrainerPokemon) como datos.

TrainerPokemon(N) asigna al entrenador z: PK1..6 (especie), NV1..6 (nivel), OB1..6 (objeto) y
AT1..6 (AT[0] = true y AT[1..4] los movimientos propios). Algunos valores dependen de la partida:
- NV = setMinMax(mínimo, MAX_NV, ajuste): el nivel sube con el nivel más alto del equipo del jugador;
- PK = (18).bandera: la especie guardada en una bandera (el inicial del rival);
- if((18).pkchoose=1) PK6=...: variantes según la historia → un miembro por variante con su condición.

Solo biblioteca estándar.
"""
from __future__ import annotations

import re

import gml_visual


class _Raro(Exception):
    pass


def _valor(e):
    """Número, {"bandera": nombre}, {"min": n, "ajuste": a} o _Raro."""
    k = e[0]
    if k == "num":
        return int(float(e[1]))
    if k == "id" and e[1] in ("true", "false"):
        return 1 if e[1] == "true" else 0
    if k == "un" and e[1] == "-":
        v = _valor(e[2])
        if isinstance(v, int):
            return -v
    if k == "campo" and e[1] == ("num", "18"):
        return {"bandera": e[2]}
    if k == "id" and e[1] == "MAX_NV":
        return {"min": 0, "ajuste": 0}
    if k == "llamada" and e[1] == "setMinMax" and len(e[2]) == 3:
        a, b = _valor(e[2][0]), _valor(e[2][2])
        if isinstance(a, int) and isinstance(b, int):
            return {"min": a, "ajuste": b}
    raise _Raro()


def _condicion(e) -> str:
    """Condición de evento (docs/eventos.md) sobre las banderas."""
    k = e[0]
    if k == "num":
        return str(int(float(e[1])))
    if k == "campo" and e[1] == ("num", "18"):
        return e[2]
    if k == "indice" and e[1][0] == "campo" and e[1][1] == ("num", "18") and e[2][0] == "num":
        return f"{e[1][2]}_{int(float(e[2][1]))}"
    if k == "un" and e[1] in ("!", "not"):
        return f"no ({_condicion(e[2])})"
    if k == "bin":
        op = {"=": "==", "&&": "y", "||": "o", "and": "y", "or": "o"}.get(e[1], e[1])
        if op not in ("==", "!=", "<", ">", "<=", ">=", "y", "o"):
            raise _Raro()
        return f"({_condicion(e[2])} {op} {_condicion(e[3])})"
    raise _Raro()


def _ejecutar(i, conds: list[str], asignaciones: list) -> None:
    k = i[0]
    if k == "bloque":
        for x in i[1]:
            _ejecutar(x, conds, asignaciones)
    elif k == "if":
        try:
            c = _condicion(i[1])
        except _Raro:
            return
        _ejecutar(i[2], conds + [c], asignaciones)
        if i[3] is not None:
            _ejecutar(i[3], conds + [f"no {c}"], asignaciones)
    elif k == "asig" and i[2] == "=":
        lv = i[1]
        try:
            v = _valor(i[3])
        except _Raro:
            return
        if lv[0] == "campo" and lv[1] == ("id", "z"):
            asignaciones.append((lv[2], None, v, " y ".join(conds)))
        elif lv[0] == "indice" and lv[1][0] == "campo" and lv[1][1] == ("id", "z") and lv[2][0] == "num":
            asignaciones.append((lv[1][2], int(float(lv[2][1])), v, " y ".join(conds)))


def equipos(gml: str) -> dict[int, list[dict]]:
    """{N: [{especie | especie_bandera, nivel, nivel_escala, ajuste, objeto, movimientos, condicion}]}"""
    out = {}
    for n, cuerpo in re.findall(r"if\(argument0=(\d+)\)\{(.*?)exit;\}", gml):
        try:
            arbol = gml_visual.Parser(gml_visual.tokenizar(cuerpo)).programa()
        except Exception:
            continue
        asig: list = []
        for inst in arbol:
            _ejecutar(inst, [], asig)
        miembros = []
        for k in range(1, 7):
            especies = [(v, c) for campo, idx, v, c in asig if campo == f"PK{k}" and idx is None]
            # La última asignación sin condición manda; las condicionales son variantes.
            sin_cond = [v for v, c in especies if not c]
            variantes = [(v, c) for v, c in especies if c] or ([(sin_cond[-1], "")] if sin_cond else [])
            if not variantes and sin_cond:
                variantes = [(sin_cond[-1], "")]
            nivel = next((v for campo, idx, v, c in reversed(asig) if campo == f"NV{k}" and idx is None), 0)
            objeto = next((v for campo, idx, v, c in reversed(asig) if campo == f"OB{k}" and idx is None), 0)
            at = {idx: v for campo, idx, v, c in asig if campo == f"AT{k}" and idx is not None}
            movimientos = [at[i] for i in (1, 2, 3, 4) if isinstance(at.get(i), int) and at[i] > 0] if at.get(0) else []
            for especie, cond in variantes:
                if especie == 0:
                    continue
                m = {"nivel": 5, "nivel_escala": False, "ajuste": 0, "objeto": objeto if isinstance(objeto, int) else 0,
                     "movimientos": movimientos, "condicion": cond}
                if isinstance(especie, dict) and "bandera" in especie:
                    m["especie_bandera"] = especie["bandera"]
                elif isinstance(especie, int):
                    m["especie"] = especie
                else:
                    continue
                if isinstance(nivel, dict):
                    m.update(nivel=max(1, nivel["min"]), nivel_escala=True, ajuste=nivel["ajuste"])
                elif isinstance(nivel, int) and nivel > 0:
                    m["nivel"] = nivel
                miembros.append(m)
        out[int(n)] = miembros
    return out
