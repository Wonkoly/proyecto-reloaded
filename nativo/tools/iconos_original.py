"""Iconos pequeños de cada especie (Draw_mini): {especie: [sprite, frame]}.

El original elige con una cadena de if(PK...) { draw_sprite_ext((sprite), frame, ...); exit; }; aquí se
evalúan en orden para cada especie (gana la primera que se cumple). Los frames son N, PK o PK-N.
"""
import re


def _python(cond: str) -> str:
    cond = cond.replace("&&", " and ").replace("||", " or ")
    return re.sub(r"(?<![<>!=])=(?!=)", "==", cond)


def iconos(draw_mini: str, sprites: list[str], especies: list[int]) -> dict[str, list]:
    reglas = []
    for cond, spr, frame in re.findall(r"if\(([^{]*?)\)\{?draw_sprite_ext\(\((\d+)\),([^,]+),", draw_mini):
        if not re.fullmatch(r"[\sPK0-9<>=!&|()]+", cond) or not re.fullmatch(r"PK(-\d+)?|\d+", frame.strip()):
            continue
        reglas.append((compile(_python(cond), "c", "eval"), sprites[int(spr)], frame.strip()))
    tabla: dict[str, list] = {}
    for pk in especies:
        for c, spr, frame in reglas:
            if eval(c, {"PK": pk}):
                f = pk - int(frame[3:]) if frame.startswith("PK-") else pk if frame == "PK" else int(frame)
                tabla[str(pk)] = [spr, f]
                break
    return tabla
