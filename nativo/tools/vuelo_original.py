"""Tabla de Vuelo y del mapa de la región (pantalla obj_pantallavuelo del original).

- CheckMousePantallaVuelo: en qué región (INDEX) está cada lugar, su zona en el mapa y a qué room lleva.
- DefinePantallaVuelo: el nombre de cada lugar (str_lugN = TextPlace(M)).
- FlyScreenValues: dónde se dibuja la marca de cada lugar visitado.
- FlyScreenNext: el orden en que las flechas ↑/↓ recorren los lugares de cada región.
- ConfirmaVuelo: el punto de llegada (global.xx/yy). Los lugares con varias llegadas (Isla Sol, el Frente
  y las rooms de las regiones 3 y 4) toman la primera; elegir entre ellas queda pendiente.
- AdjustmentsRoom: entrar a una room (o al Centro Pokémon de una ciudad, global.index_place) marca el
  lugar como visitado (canFly[n]). Las marcas con condiciones de historia no se leen todavía.
- MapaLugar: la región de cada room (0 si no aparece).
- MapaLocationActivate: dónde se marca al jugador en el mapa según la room (en un interior, la de afuera).
"""
import re


def _lugares(check: str, define: str, confirma: str, valores: str, salas: list[str]) -> dict[str, dict]:
    textos = {m[0]: int(m[1]) for m in re.findall(r"(str_lug\d+)=TextPlace\((\d+)\)", define)}
    marcas: dict[int, list[int]] = {}
    for n, eje, v in re.findall(r'argument0=(\d+)\)\{ if\(argument1="X"\)return\((-?\d+)\); if\(argument1="Y"\)return\((-?\d+)\);', valores):
        marcas[int(n)] = [int(eje), int(v)]
    llegadas: dict[int, list[int]] = {}
    trozos = re.split(r"if\(L=\((\d+)\)\)\{", confirma)[1:]
    for room, cuerpo in zip(trozos[::2], trozos[1::2]):
        m = re.search(r"global\.xx=(\d+);global\.yy=(\d+);", cuerpo)
        if m and int(room) not in llegadas:
            llegadas[int(room)] = [int(m[1]), int(m[2])]
    cortes = [(m.start(), int(m[1])) for m in re.finditer(r"if\(INDEX=(\d+)\)\{ if\(\(18\)\.canFly", check)]
    patron = (r"\(18\)\.canFly\[(\d+)\](?:=true|>=1|>=true)\)\{if\(Mouse_Position\(x_offset\+view_xview\+(\d+),"
              r"y_offset\+view_yview\+(\d+),x_offset\+view_xview\+(\d+),y_offset\+view_yview\+(\d+)\)\)\{"
              r"str=(\w+);L=\((\d+)\)")
    lugares: dict[str, dict] = {}
    for m in re.finditer(patron, check):
        region = ([r for p, r in cortes if p < m.start()] or [0])[-1]
        n, room = int(m[1]), int(m[7])
        if str(n) in lugares:
            continue
        lugares[str(n)] = {
            "region": region,
            "zona": [int(m[2]), int(m[3]), int(m[4]), int(m[5])],
            "marca": marcas.get(n, [int(m[2]), int(m[3])]),
            "texto": textos.get(m[6], 0),
            "mapa": salas[room] if 0 <= room < len(salas) else "",
            "llegada": llegadas.get(room, [0, 0]),
        }
    return lugares


def _orden(siguiente: str) -> dict[str, list[int]]:
    """FlyScreenNext: sucesor de cada lugar por región; se recorre desde el primero."""
    orden: dict[str, list[int]] = {}
    bloques = re.split(r"if\(INDEX=(\d+)\)\{", siguiente)[1:]
    for k in range(0, len(bloques), 2):
        region, cuerpo = bloques[k], bloques[k + 1]
        if region in orden:  # al final se repite if(INDEX=k) para los desplazamientos
            continue
        sig: dict[int, int] = {}
        m = re.search(r"if\(mouse_fly<=(\d+)\)mouse_fly\+=1;", cuerpo)
        if m:
            for i in range(-1, int(m[1]) + 1):
                sig[i] = i + 1
        m = re.search(r"mouse_fly>=(\d+) && mouse_fly<=(\d+)\)mouse_fly\+=1;", cuerpo)
        if m:
            for i in range(int(m[1]), int(m[2]) + 1):
                sig[i] = i + 1
        for a, b, c in re.findall(r"if\(mouse_fly=\((-?\d+)\)(?: \|\| mouse_fly=(\d+))?\)mouse_fly=(\d+);", cuerpo):
            sig[int(a)] = int(c)
            if b:
                sig[int(b)] = int(c)
        for a, c in re.findall(r"if\(mouse_fly=(\d+)\)mouse_fly=(\d+);", cuerpo):
            sig[int(a)] = int(c)
        lista, i = [], sig.get(-1)
        while i is not None and i not in lista:
            lista.append(i)
            i = sig.get(i)
        orden[region] = lista
    return orden


def _al_entrar(ajustes: str, salas: list[str]) -> tuple[dict[str, int], dict[str, int]]:
    """AdjustmentsRoom: {mapa: lugar} y, en el Centro Pokémon (room 2), {index_place: lugar}."""
    mapas: dict[str, int] = {}
    for room, n in re.findall(r"if\(room=\((\d+)\)\)\(18\)\.canFly\[(\d+)\]=true;", ajustes):
        if 0 <= int(room) < len(salas):
            mapas.setdefault(salas[int(room)], int(n))
    centros: dict[str, int] = {}
    for k, n in re.findall(r"if\(global\.index_place=(\d+)(?: && \(18\)\.canFly\[\d+\]=false)?\)\(18\)\.canFly\[(\d+)\]=true;", ajustes):
        centros.setdefault(k, int(n))
    return mapas, centros


def _regiones(mapa_lugar: str, salas: list[str]) -> dict[str, int]:
    """MapaLugar: {mapa: región} para las regiones 1-4 (el resto es la 0). La primera lista del
    original devuelve la región de afuera (global.room_out) y no se incluye."""
    regiones: dict[str, int] = {}
    for lista, r in re.findall(r"if\(((?:argument0=\(\d+\)(?: \|\| )?)+)\)\{\s*return\((\d)\);", mapa_lugar):
        for room in re.findall(r"\((\d+)\)", lista):
            if 0 <= int(room) < len(salas):
                regiones.setdefault(salas[int(room)], int(r))
    return regiones


def _ubicaciones(activa: str, salas: list[str]) -> dict[str, list[int]]:
    ubic: dict[str, list[int]] = {}
    for lista, x, y in re.findall(r"if\(((?:\s*\|*\s*L=\(\d+\)\s*)+)\)\{x=(\d+);y=(\d+);exit;\}", activa):
        for room in re.findall(r"\((\d+)\)", lista):
            if 0 <= int(room) < len(salas):
                ubic.setdefault(salas[int(room)], [int(x), int(y)])
    return ubic


def vuelo(scripts, salas: list[str]) -> dict:
    leer = lambda n: (scripts / f"{n}.gml").read_text(errors="replace")
    mapas, centros = _al_entrar(leer("AdjustmentsRoom"), salas)
    return {
        "lugares": _lugares(leer("CheckMousePantallaVuelo"), leer("DefinePantallaVuelo"), leer("ConfirmaVuelo"),
                            leer("FlyScreenValues"), salas),
        "orden": _orden(leer("FlyScreenNext")),
        "al_entrar": mapas,
        "centros": centros,
        "regiones": _regiones(leer("MapaLugar"), salas),
        "ubicaciones": _ubicaciones(leer("MapaLocationActivate"), salas),
    }
