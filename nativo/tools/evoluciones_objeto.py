"""Evoluciones por objeto del original (piedras y demás): qué especies acepta cada objeto y en qué
evolucionan.

UseObject: if(OB=N){... if(PK=a || PK=b ...){ pregunta 543; global.EvolMode=(M); room 12 }...}
EvolutionConfirmation: if(pk=X){ if(evolMode=(M)){pk=Y;} ...} o if(pk=X){pk=Y;exit;}; si no, pk + 1 de
la misma familia de cría (MYSON).
"""

from __future__ import annotations

import re

from musica_original import _cerrar, _sentencias_if


def evoluciones(use_object: str, confirmacion: str, misma_familia) -> dict[int, dict[int, int]]:
    """{id del objeto: {especie: especie en la que evoluciona}}."""
    destinos: dict[int, dict[int, int]] = {}  # especie -> {modo (0 = cualquiera): destino}
    for cond, cuerpo in _sentencias_if(confirmacion):
        m = re.fullmatch(r"pk=(\d+)", cond.strip())
        if not m:
            continue
        pk = int(m.group(1))
        por_modo = {int(a): int(b) for a, b in re.findall(r"if\(evolMode=\((\d+)\)\)\{?pk=(\d+);", cuerpo)}
        simple = re.fullmatch(r"pk=(\d+);\s*(?:LostItemEvolution\(ac\);\s*)?exit;", cuerpo.strip())
        if simple:
            por_modo[0] = int(simple.group(1))
        destinos.setdefault(pk, por_modo)
    resultado: dict[int, dict[int, int]] = {}
    for m in re.finditer(r"if\(OB=(\d+)\)\{", use_object):  # anidados: se buscan en todo el script
        cuerpo = use_object[m.end() - 1:_cerrar(use_object, m.end() - 1, "{", "}")]
        objeto = int(m.group(1))
        for mp in re.finditer(r"if\(((?:PK=\d+(?: \|\| )?)+)\)\{", cuerpo):
            bloque = cuerpo[mp.end() - 1:_cerrar(cuerpo, mp.end() - 1, "{", "}")]
            mm = re.search(r"global\.EvolMode=\(?(\d+)\)?;", bloque)
            if not mm:
                continue
            especies, modo = mp.group(1), int(mm.group(1))
            for pk in (int(x) for x in re.findall(r"PK=(\d+)", especies)):
                d = destinos.get(pk)
                if d is not None:
                    destino = d.get(modo, d.get(0))
                elif misma_familia(pk, pk + 1):
                    destino = pk + 1
                else:
                    destino = None
                if destino:
                    resultado.setdefault(objeto, {})[pk] = destino
    return resultado


def reglas_nivel(check: str, confirmacion: str, misma_familia) -> dict[int, list[dict]]:
    """CheckEvolution en orden: {especie: [{nivel, objeto, objeto_no, ball, dia, destino}]}. La primera
    regla que se cumple manda. Se saltan las que piden sexo o condiciones del equipo (condicion,
    instance_exists): no se pueden comprobar con datos."""
    destinos: dict[int, dict[int, int]] = {}
    for cond, cuerpo in _sentencias_if(confirmacion):
        m = re.fullmatch(r"pk=(\d+)", cond.strip())
        if m:
            d = {int(a): int(b) for a, b in re.findall(r"if\(evolMode=\((\d+)\)\)\{?pk=(\d+);", cuerpo)}
            simple = re.fullmatch(r"pk=(\d+);\s*(?:LostItemEvolution\(ac\);\s*)?exit;", cuerpo.strip())
            if simple:
                d[0] = int(simple.group(1))
            destinos.setdefault(int(m.group(1)), d)
    cuerpo_check = check[check.find("if(PS<=0"):]
    reglas: dict[int, list[dict]] = {}
    for m in re.finditer(r"if\((pk=\d+[^(){}]*?)\)\s*(?:\{global\.EvolMode=(\d+);return true;\}|return true;)", cuerpo_check):
        cond, modo = m.group(1), int(m.group(2)) if m.group(2) else 1
        if re.search(r"condicion|sex|instance_exists|\(", cond):
            continue
        r: dict = {"nivel": 0}
        for clave, valor in re.findall(r"(pk|nv>|obj!|obj|ball|global\.day)=+(\w+)", cond):
            if clave == "pk":
                pk = int(valor)
            elif clave == "nv>":
                r["nivel"] = int(valor)
            elif clave == "obj":
                r["objeto"] = int(valor)
            elif clave == "obj!":
                r["objeto_no"] = int(valor)
            elif clave == "ball":
                r["ball"] = int(valor)
            elif clave == "global.day":
                r["dia"] = valor == "true"
        d = destinos.get(pk, {})
        if modo >= 22:
            destino = modo  # EvolMode con la especie directa (Slowbro 80, Scizor 212...)
        else:
            destino = d.get(modo, d.get(0)) or (pk + 1 if misma_familia(pk, pk + 1) else None)
        if destino:
            r["destino"] = destino
            reglas.setdefault(pk, []).append(r)
    return reglas
