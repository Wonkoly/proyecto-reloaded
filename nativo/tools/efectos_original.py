"""Efectos secundarios de los movimientos del original (SecEffect1: el Pokémon 1 recibe el ataque
del 2). Cada bloque if(at=A || at=B){...} se resume en:
  estado / prob_estado: global.STD1[ACTUAL1]=(S) (al rival) con randomPorcent(P) (100 si no hay);
  cambios_rival / cambios_propios: ModificaStat(1|2,(stat),n*SIMPLE_..) con su randomPorcent;
  retroceso: global.PS_2[ACTUAL2]-=ceil(pokemon1.DANO/n);
  drenaje: la fracción del daño que recupera (recuperar=floor(pokemon1.DANO*RAIZ/2), o *0.75 en alguno).
Los casos que dependen de habilidades, objetos, clima o efectos activos no se leen (ver docs).
"""

from __future__ import annotations

import re

from musica_original import _cerrar, _sentencias_if


def _prob_antes(cuerpo: str, pos: int) -> int:
    """randomPorcent(N) más cercano antes de pos (100 si no hay)."""
    previos = list(re.finditer(r"randomPorcent\((\d+)", cuerpo[:pos]))
    return int(previos[-1].group(1)) if previos else 100


def efectos(sec_effect: str) -> dict[int, dict]:
    resultado: dict[int, dict] = {}
    for cond, cuerpo in _sentencias_if(sec_effect):
        if re.sub(r"at=\d+|\|\||\s", "", cond):
            continue  # condición con algo más que at=
        ids = [int(n) for n in re.findall(r"at=(\d+)", cond)]
        # if((at=A || at=B) && !randomPorcent(P))exit;: probabilidad propia de esos movimientos del bloque.
        compuertas: dict[int, int] = {}
        for m in re.finditer(r"if\(\(?((?:at=\d+(?: \|\| )?)+)\)? && !randomPorcent\((\d+)[^)]*\)\)exit;", cuerpo):
            for at in re.findall(r"at=(\d+)", m.group(1)):
                compuertas[int(at)] = int(m.group(2))
        cuerpo = re.sub(r"if\(\(?(?:at=\d+(?: \|\| )?)+\)? && !randomPorcent\([^)]*\)\)exit;", "", cuerpo)
        e: dict = {}
        m = re.search(r"global\.STD1\[ACTUAL1\]=\((\d+)\)", cuerpo)
        if m:
            e["estado"] = int(m.group(1))
            e["prob_estado"] = _prob_antes(cuerpo, m.start())
        for m in re.finditer(r"ModificaStat\(([12]),\((\d)\),(-?\d+)\*SIMPLE_(?:UNO|DOS)", cuerpo):
            clave = "cambios_rival" if m.group(1) == "1" else "cambios_propios"
            e.setdefault(clave, {}).setdefault(int(m.group(2)), int(m.group(3)))
            e.setdefault("prob_cambios", _prob_antes(cuerpo, m.start()))
        m = re.search(r"global\.PS_2\[ACTUAL2\]-=ceil\(pokemon1\.DANO/(\d+)\)", cuerpo)
        if m:
            e["retroceso"] = int(m.group(1))
        drenaje_propio: dict[int, float] = {}
        if "recuperar=floor(pokemon1.DANO*RAIZ/2)" in cuerpo:
            e["drenaje"] = 0.5
            for at, f in re.findall(r"if\(at=(\d+)\)recuperar=floor\(pokemon1\.DANO\*RAIZ\*([\d.]+)\)", cuerpo):
                drenaje_propio[int(at)] = float(f)
        if e:
            for at in ids:
                propio = dict(e)
                if at in drenaje_propio:
                    propio["drenaje"] = drenaje_propio[at]
                if at in compuertas:
                    for k in ("prob_estado", "prob_cambios"):
                        if k in propio:
                            propio[k] = compuertas[at] * propio[k] // 100
                resultado.setdefault(at, propio)
    return resultado


def golpes(es_multiple: str) -> dict[int, list[int]]:
    """EsMultiple: cuántas veces golpea cada movimiento (choose(...) es una de las opciones al azar,
    random(10) del 1 al 10). Los que cuentan el equipo (Paliza) no se leen."""
    tabla: dict[int, list[int]] = {}
    for at, valor in re.findall(r"if\(argument0=(\d+)\)return\(([^;]*?)\);", es_multiple):
        if valor.startswith("choose("):
            tabla[int(at)] = [int(n) for n in re.findall(r"\d+", valor)]
        elif valor == "ceil(random(10))":
            tabla[int(at)] = list(range(1, 11))
        elif valor.isdigit():
            tabla[int(at)] = [int(valor)]
    return tabla
