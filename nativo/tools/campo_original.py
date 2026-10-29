"""Tablas de las MO que dependen de la room (AdjustmentsRoom).

- oscuros: rooms donde se crea obj_Oscuro1 (cuevas oscuras; Destello las ilumina).
- apaga_destello: entrar a estas rooms pone (18).usadestello = false (la luz de Destello se acaba).
"""
import re


def _rooms(lista: str, salas: list[str]) -> list[str]:
    return [salas[int(n)] for n in re.findall(r"\((\d+)\)", lista) if 0 <= int(n) < len(salas)]


def campo(ajustes: str, salas: list[str]) -> dict[str, list[str]]:
    oscuros: list[str] = []
    for lista in re.findall(r"if\(((?:room=\(\d+\)(?: \|\| )?)+)\)\{ if\(!instance_exists\(\(145\)\)\)instance_create", ajustes):
        oscuros += _rooms(lista, salas)
    apaga: list[str] = []
    for lista in re.findall(r"if\(((?:room=\(\d+\)(?: \|\| )?)+)\)\{\(18\)\.usadestello=false;\}", ajustes):
        apaga += _rooms(lista, salas)
    return {"oscuros": oscuros, "apaga_destello": apaga}
