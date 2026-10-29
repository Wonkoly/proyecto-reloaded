"""Tabla de Buceo (GoDiving): a qué room y posición lleva sumergirse (abajo) o salir a la superficie
(arriba) según la room, global.index_place y la posición del jugador.

Cada room da una lista de pasos que se aplican en orden (el original no usa else: el último que se
cumple gana). Un paso tiene una condición sobre x/y (expresión de Godot, "" = siempre) y lo que
asigna: llegada ("x"/"y" = la misma coordenada, o la superficie más cercana), mapa, índice de lugar y,
si lo pone, a dónde vuelve la salida del interior (global.room_out, outx, outy).
"""
import re


def _bloque(s: str, i: int) -> tuple[str, int]:
    """El cuerpo entre la llave que abre en s[i] y la que la cierra."""
    nivel = 0
    for j in range(i, len(s)):
        if s[j] == "{":
            nivel += 1
        elif s[j] == "}":
            nivel -= 1
            if nivel == 0:
                return s[i + 1:j], j + 1
    return s[i + 1:], len(s)


def _condicion(c: str) -> str:
    c = c.replace("(14).x", "x").replace("(14).y", "y").replace("&&", "and").replace("||", "or")
    return re.sub(r"(?<![<>!=])=(?!=)", "==", c).strip()


def _asignaciones(texto: str, salas: list[str]) -> dict:
    paso: dict = {}
    for campo, valor in re.findall(r"global\.(xx|yy|lugar|index_place|room_out|outx|outy)=([^;]+);", texto):
        valor = valor.strip()
        if campo in ("xx", "yy"):
            if "instance_nearest" in valor:
                paso[campo] = "superficie"
            elif valor.endswith(".x") or valor.endswith(".y") or valor in ("x", "y"):
                paso[campo] = valor[-1]
            else:
                paso[campo] = int(valor)
        elif campo in ("lugar", "room_out"):
            n = int(valor.strip("()"))
            paso["mapa" if campo == "lugar" else "salida_mapa"] = salas[n] if 0 <= n < len(salas) else ""
        elif campo == "index_place":
            paso["indice"] = int(valor.strip("()"))
        else:
            paso["salida_" + campo[-1]] = int(valor.strip("()"))
    return paso


def _pasos(cuerpo: str, salas: list[str]) -> list[dict]:
    pasos: list[dict] = []
    i, suelto = 0, ""
    while i < len(cuerpo):
        m = re.compile(r"if\((.*?)\)\{").search(cuerpo, i)
        if not m:
            suelto += cuerpo[i:]
            break
        suelto += cuerpo[i:m.start()]
        adentro, i = _bloque(cuerpo, m.end() - 1)
        if suelto.strip():
            pasos.append(dict(cond="", **_asignaciones(suelto, salas)))
            suelto = ""
        pasos.append(dict(cond=_condicion(m[1]), **_asignaciones(adentro, salas)))
    if suelto.strip() and _asignaciones(suelto, salas):
        pasos.append(dict(cond="", **_asignaciones(suelto, salas)))
    return [p for p in pasos if len(p) > 1]


def buceo(go_diving: str, salas: list[str]) -> dict[str, list[dict]]:
    """{"abajo:Mapa" / "arriba:Mapa": [{"indice": k o None, "pasos": [...]}, ...]}."""
    tabla: dict[str, list[dict]] = {}
    for direccion in ("abajo", "arriba"):
        m = re.search(r"if\(argument0=vk_%s\)\{" % ("down" if direccion == "abajo" else "up"), go_diving)
        if not m:
            continue
        seccion, _ = _bloque(go_diving, m.end() - 1)
        for r in re.finditer(r"if\(room=\((\d+)\)(?: && global\.index_place=(\d+))?\)\{", seccion):
            cuerpo, _ = _bloque(seccion, r.end() - 1)
            room = int(r[1])
            if not 0 <= room < len(salas):
                continue
            tabla.setdefault(f"{direccion}:{salas[room]}", []).append({
                "indice": int(r[2]) if r[2] else None, "pasos": _pasos(cuerpo, salas)})
    return tabla
