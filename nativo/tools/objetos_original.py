"""Objetos del original → data/extraido/objetos.json

Por id (como en el juego): 1-821 (txt_obj), 1001-2087 (decoración de la base secreta,
txt_obj_secret_base) y 5001-5866 (DT: "DT<n> <movimiento>"). De cada uno: nombre, descripción
(DescObject), precio (PrecioObject) y bolsillo (EsObjetoBall/Item/Baya/Clave/MT; "base" y "dt").

Solo biblioteca estándar.
"""
from __future__ import annotations

MAX_OBJ = 821
MAX_BASE = 1087
MAX_DT = 866


def objetos(f) -> dict[str, dict]:
    """f: dialogos_original.Funciones."""
    import math  # noqa: F401
    out = {}
    ids = list(range(1, MAX_OBJ + 1)) + list(range(1001, 1001 + MAX_BASE)) + list(range(5001, 5001 + MAX_DT))
    for i in ids:
        if i <= MAX_OBJ:
            nombre = f.linea("txt_obj", i)
            bolsillo = next((b for b, fn in (("ball", "EsObjetoBall"), ("baya", "EsObjetoBaya"), ("clave", "EsObjetoClave"),
                                               ("mt", "EsObjetoMT")) if f.llamar(fn, float(i))), "objeto")
        elif i < 5000:
            nombre = f.linea("txt_obj_secret_base", i - 1000)
            bolsillo = "base"
        else:
            nombre = f"DT{i - 5000} {f.linea('txt_attack', i - 5000)}".strip()
            bolsillo = "dt"
        if not nombre:
            continue
        precio = f.llamar("PrecioObject", float(i))
        if i > 5000 and i not in (5666,) and not 5752 <= i <= 5769:
            pp = f.llamar("TheoricPPAtack", float(i - 5000))  # 100 * ceil(25 * PP / 100)
            precio = float(100 * -(-25 * int(pp) // 100)) if isinstance(pp, float) else precio
        desc = f.llamar("DescObject", float(i))
        out[str(i)] = {"nombre": nombre, "descripcion": desc if isinstance(desc, str) else "",
                       "precio": int(precio) if isinstance(precio, float) else 0, "bolsillo": bolsillo}
    return out
