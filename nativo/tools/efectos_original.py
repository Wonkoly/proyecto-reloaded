"""Efectos secundarios de los movimientos del original (SecEffect1: el Pokémon 1 recibe el ataque
del 2). Cada bloque if(at=A || at=B){...} se resume en:
  estado / prob_estado: global.STD1[ACTUAL1]=(S) (al rival) con randomPorcent(P) (100 si no hay);
  cambios_rival / cambios_propios: ModificaStat(1|2,(stat),n*SIMPLE_..) con su randomPorcent;
  retroceso: global.PS_2[ACTUAL2]-=ceil(pokemon1.DANO/n); drenaje: global.PS_2[ACTUAL2]+=ceil(pokemon1.DANO/n).
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
        m = re.search(r"global\.PS_2\[ACTUAL2\]\+=ceil\(pokemon1\.DANO/(\d+)\)", cuerpo)
        if m:
            e["drenaje"] = int(m.group(1))
        if e:
            for at in ids:
                propio = dict(e)
                if at in compuertas:
                    for k in ("prob_estado", "prob_cambios"):
                        if k in propio:
                            propio[k] = compuertas[at] * propio[k] // 100
                resultado.setdefault(at, propio)
    return resultado
