"""La música de cada mapa y de las batallas del original (Sound_World, Sound_Battle).

Sound_World es una cadena de if(ROOM=(n) || ...){ImportMusica("pista");exit;}: la primera condición
que se cumple elige la pista. Aquí se toman las que dependen solo del número de sala (las que además
piden una bandera de la historia o un objeto en la sala son variantes y se saltan). Algunas salas
(interiores) usan la música de la sala de afuera (ROOM = global.room_out): quedan como "@afuera".
Las salas sin pista no cambian la música que ya suena.
"""

from __future__ import annotations

import re


def _cerrar(s: str, i: int, abre: str, cierra: str) -> int:
    """Índice justo después del cierre que corresponde a la apertura en s[i]."""
    nivel = 0
    for j in range(i, len(s)):
        if s[j] == abre:
            nivel += 1
        elif s[j] == cierra:
            nivel -= 1
            if nivel == 0:
                return j + 1
    return len(s)


def _sentencias_if(s: str):
    """(condición, cuerpo) de cada if del nivel superior, en orden."""
    i = 0
    while i < len(s):
        if s[i] == "{":
            i = _cerrar(s, i, "{", "}")
            continue
        if s.startswith("if(", i):
            fin = _cerrar(s, i + 2, "(", ")")
            cond = s[i + 3:fin - 1]
            j = fin
            while j < len(s) and s[j] == " ":
                j += 1
            if j < len(s) and s[j] == "{":
                fin_cuerpo = _cerrar(s, j, "{", "}")
                yield cond, s[j + 1:fin_cuerpo - 1]
            else:
                fin_cuerpo = s.find(";", j) + 1
                yield cond, s[j:fin_cuerpo]
            i = fin_cuerpo
            continue
        i += 1


def _pista_directa(cuerpo: str) -> str | None:
    """El último ImportMusica("x") del cuerpo que no está dentro de otro bloque."""
    pista = None
    nivel = 0
    for m in re.finditer(r'[{}]|ImportMusica\("([^"]*)"\)', cuerpo):
        t = m.group(0)
        if t == "{":
            nivel += 1
        elif t == "}":
            nivel -= 1
        elif nivel == 0:
            pista = m.group(1)
    return pista


def musica_mapas(sound_world: str, salas: list) -> dict[str, str]:
    """{nombre de sala: pista (nombre original sin extensión) o "@afuera"}."""
    resultado: dict[str, str] = {}
    for cond, cuerpo in _sentencias_if(sound_world):
        numeros = [int(n) for n in re.findall(r"(?:ROOM|room)=\((\d+)\)", cond)]
        if not numeros or "&&" in cond or "!=" in cond:
            continue
        if "ROOM=global.room_out" in cuerpo:
            pista = "@afuera"
        else:
            pista = _pista_directa(cuerpo)
        if not pista:
            continue
        for n in numeros:
            if 0 <= n < len(salas) and salas[n] and salas[n] not in resultado:
                resultado[salas[n]] = pista
    return resultado


def musica_batallas(sound_battle: str) -> dict[str, str]:
    """Pistas de Sound_Battle: salvaje, legendario, entrenador, líder, villano..."""
    pistas = dict(re.findall(r'ImportMusica\("((snd_[A-Za-z_]+))"\)', sound_battle))
    claves = {"snd_salvaje": "salvaje", "snd_salvaje_legendario": "legendario", "snd_salvaje_nohuyes": "no_huyes",
              "snd_battle": "entrenador", "snd_battle_lider": "lider", "snd_battle_malo": "malo",
              "snd_battle_accion": "accion", "snd_battle_Malisimo": "malisimo", "snd_battle_As": "as",
              "snd_safariB": "safari"}
    return {clave: pista for pista, clave in claves.items() if pista in pistas}
