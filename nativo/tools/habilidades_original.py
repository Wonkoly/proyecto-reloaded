"""Habilidades que solo cambian el daño de un golpe (Ataque1GolpeaPokemon2: if(HABILIDADx=N && cond)
{pokemon2.DANO*=f; hab_fugaz(...)}). Cada regla dice de quién es la habilidad (atacante = HABILIDAD1,
defensor = HABILIDAD2), la condición traducida a una expresión de Godot y el factor.

Variables de la condición: tipo (tipo del ataque, id del original), modo (ModeAtack: 0 físico, 1
especial), poder, eff (efectividad), estado_at / estado_def (STD), ps_at / max_at / ps_def / max_def,
hab_at / hab_def (la habilidad de cada uno), dia y sol. Las que usan otra cosa no se leen.
"""
import re

_PATRON = re.compile(r"if\((HABILIDAD([12])=(\d+)[^{}]*?)\)\{(?:hab_fugaz\([12],[A-Z]+\);)?pokemon2\.DANO([*/])=([\d.]+);"
                     r"(?:hab_fugaz\([12],[A-Z]+\);)?\}")
_TRADUCCION = [
    (r"global\.MAX_PS_1\[ATACANTE\]", "max_at"), (r"global\.MAX_PS_2\[RECEPTOR\]", "max_def"),
    (r"global\.PS_1\[ATACANTE\]", "ps_at"), (r"global\.PS_2\[RECEPTOR\]", "ps_def"),
    (r"global\.STD1\[ATACANTE\]", "estado_at"), (r"global\.STD2\[RECEPTOR\]", "estado_def"),
    (r"ModeAtack\(index\)", "modo"), (r"\bTp\b", "tipo"), (r"\bPB\b", "poder"),
    (r"HABILIDAD1", "hab_at"), (r"HABILIDAD2", "hab_def"),
    (r"instance_exists\(\(382\)\)", "sol"), (r"global\.day=true", "dia"),
    (r"&&", " and "), (r"\|\|", " or "),
]
_CONOCIDAS = {"max_at", "max_def", "ps_at", "ps_def", "estado_at", "estado_def", "modo", "tipo", "poder", "eff",
              "hab_at", "hab_def", "sol", "dia", "and", "or", "not"}


def _expresion(cond: str) -> str | None:
    for a, b in _TRADUCCION:
        cond = re.sub(a, b, cond)
    cond = re.sub(r"\((\d+)\)", r"\1", cond)
    cond = re.sub(r"(?<![<>!=])=(?!=)", "==", cond)
    if set(re.findall(r"[A-Za-z_]+", cond)) - _CONOCIDAS:
        return None
    return re.sub(r"\s+", " ", cond).strip()


def _anidada(texto: str, pos: int) -> bool:
    """Si la sentencia en pos está dentro de un if que le pone otra condición."""
    nivel = 0
    for i in range(pos - 1, -1, -1):
        if texto[i] == "}":
            nivel += 1
        elif texto[i] == "{":
            if nivel == 0:
                antes = texto[max(0, i - 200):i].rstrip()
                # Contenedores que no cambian nada: el with(ATAQUE1) del script, un else (cadenas de reglas
                # excluyentes) y el bloque del daño de los ataques con poder.
                return not (re.search(r"with\([^()]*\)$", antes) or antes.endswith("else")
                            or antes.endswith("if(PB!=0)"))
            nivel -= 1
    return False


def reglas_danio(ataque1_golpea: str) -> list[dict]:
    reglas = []
    for m in _PATRON.finditer(ataque1_golpea):
        if _anidada(ataque1_golpea, m.start()):
            continue
        resto = m.group(1)[len(f"HABILIDAD{m.group(2)}={m.group(3)}"):].strip()
        cond = _expresion(resto[resto.startswith("&&") and 2:].strip()) if resto else ""
        if cond is None:
            continue
        factor = float(m.group(5))
        reglas.append({"de": "atacante" if m.group(2) == "1" else "defensor", "habilidad": int(m.group(3)),
                       "cond": cond, "factor": factor if m.group(4) == "*" else 1.0 / factor})
    return reglas
