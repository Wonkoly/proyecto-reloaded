"""Entrega de medallas de los líderes (Lider<Nombre>EntregaMedalla, Capitan...): lo que pasa al ganarles,
convertido a órdenes de .evento para el bloque "si gano:" de su combate.

Del bloque if((18).MEDALLA_STAR[k]=false){...} se leen, en orden y sin los if anidados:
  Dialogo(TextDialog(N),S)  → hablante S (sprINDEX: el propio NPC) / decir N
  Dialogo(TextDialog(N))    → narrar N
  (18).X=true/false/n       → bandera X = 1/0/n         (18).X[k]=... → bandera X_k = ...
  PillaObject(id,n)         → dar_objeto id n
El resto (sonidos, esperas, misiones, room_restart) no cambia nada que el port use.
"""
import re


def _sin_anidados(cuerpo: str) -> str:
    """Quita los if(...){...} y los if(...)sentencia; que haya dentro del bloque."""
    salida, i = [], 0
    while i < len(cuerpo):
        m = re.compile(r"if\(").search(cuerpo, i)
        if not m:
            salida.append(cuerpo[i:])
            break
        salida.append(cuerpo[i:m.start()])
        nivel, j = 0, m.end() - 1
        while j < len(cuerpo):  # el paréntesis de la condición
            nivel += cuerpo[j] == "("
            nivel -= cuerpo[j] == ")"
            j += 1
            if nivel == 0:
                break
        while j < len(cuerpo) and cuerpo[j] == " ":
            j += 1
        if j < len(cuerpo) and cuerpo[j] == "{":
            nivel = 0
            while j < len(cuerpo):
                nivel += cuerpo[j] == "{"
                nivel -= cuerpo[j] == "}"
                j += 1
                if nivel == 0:
                    break
        else:
            j = cuerpo.find(";", j) + 1 or len(cuerpo)
        i = j
    return "".join(salida)


def entrega(script: str) -> list[str]:
    m = re.search(r"if\(\(18\)\.MEDALLA_STAR\[(\d)\]=false\)\{", script)
    if not m:
        return []
    nivel, j = 1, m.end()
    while j < len(script) and nivel:
        nivel += script[j] == "{"
        nivel -= script[j] == "}"
        j += 1
    cuerpo = _sin_anidados(script[m.end():j - 1])
    ordenes: list[str] = []
    hablante = None
    for s in re.finditer(r"Dialogo\(TextDialog\((\d+)\)(?:,(\d+|sprINDEX))?\)|\(18\)\.(\w+)(?:\[(\d+)\])?=([^;]+);|"
                         r"PillaObject\((\d+),(\d+)\)", cuerpo):
        if s.group(1):
            if s.group(2):
                if s.group(2) != hablante:
                    ordenes.append("hablante npc" if s.group(2) == "sprINDEX" else f"hablante {s.group(2)}")
                    hablante = s.group(2)
                ordenes.append(f"decir {s.group(1)}")
            else:
                ordenes.append(f"narrar {s.group(1)}")
        elif s.group(3):
            nombre = s.group(3) + (f"_{s.group(4)}" if s.group(4) else "")
            valor = s.group(5).strip("()")
            valor = {"true": "1", "false": "0"}.get(valor, valor)
            if re.fullmatch(r"-?\d+", valor):
                ordenes.append(f"bandera {nombre} = {valor}")
        else:
            ordenes.append(f"dar_objeto {s.group(6)} {s.group(7)}")
    return ordenes
