#!/usr/bin/env python3
"""Extrae assets y datos del juego original a formatos nativos de Godot.

Lee gamedata/ (assets preparados por el pipeline del port) y extracted/ (scripts GML,
textos y tiras de sprites de batalla) y escribe en nativo/assets/extraido/ y
nativo/data/extraido/. Ver tools/README.md.

Solo usa la biblioteca estándar. Es repetible: cada categoría que se extrae deja su
carpeta exactamente como debe quedar (escribe solo lo que cambió y borra lo que sobra,
junto con sus .import/.uid); las categorías que no se piden no se tocan.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import struct
import sys
import unicodedata
from pathlib import Path

NATIVO = Path(__file__).resolve().parent.parent
REPO = NATIVO.parent
ASSETS = NATIVO / "assets" / "extraido"
DATA = NATIVO / "data" / "extraido"

STEPS_POR_SEGUNDO = 30

# Id de tipo del juego (TipoName: 1 Normal, 2 Fuego, 3 Agua...) -> índice de Tipos.Tipo
TIPO_JUEGO_A_ENUM = {
    1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 6: 12, 7: 6, 8: 8, 9: 10,
    10: 7, 11: 11, 12: 5, 13: 15, 14: 16, 15: 9, 16: 13, 17: 14, 18: 17,
}

# Especies: 1-1000 y 2001-2425 (1001-2000 y 3001-4000 son sus shiny; >100000 son formas).
RANGOS_ESPECIES = [(1, 1000), (2001, 2425)]

# Sprites de batalla. Las direcciones son las del teclado numérico (2 = abajo, 8 = arriba...).
DIRECCIONES_MOVER = ["1", "2", "3", "4", "6", "7", "8", "9"]
# En las tiras A (ataque) y H (herido) cada frame es una dirección (Renew_Sprite_Atack).
DIRECCION_POR_FRAME = ["8", "9", "6", "3", "2", "1", "4", "7"]

CATEGORIAS = ["datos", "sprites", "fondos", "tilesets", "musica", "gritos", "entrenadores", "mapas"]
POR_DEFECTO = ["datos", "sprites", "fondos"]
CARPETAS = {
    "datos": [DATA / "pokemon", DATA / "moves"],
    "sprites": [ASSETS / "sprites" / "pokemon"],
    "fondos": [ASSETS / "sprites" / "battlebacks"],
    "tilesets": [ASSETS / "sprites" / "tilesets"],
    "musica": [ASSETS / "audio" / "music"],
    "gritos": [ASSETS / "audio" / "sfx" / "gritos"],
    "entrenadores": [ASSETS / "sprites" / "trainers"],
    "mapas": [ASSETS / "mapas"],
}


def avisar(msg: str) -> None:
    print("aviso:", msg, file=sys.stderr)


def snake(nombre: str) -> str:
    """'PuebloAlba' -> 'pueblo_alba', 'Nidoran♀' -> 'nidoran_hembra'."""
    nombre = nombre.replace("♀", " hembra").replace("♂", " macho")
    nombre = unicodedata.normalize("NFKD", nombre).encode("ascii", "ignore").decode()
    nombre = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", nombre)
    return re.sub(r"[^a-z0-9]+", "_", nombre.lower()).strip("_")


def res(path: Path) -> str:
    return "res://" + path.relative_to(NATIVO).as_posix()


def png_size(path: Path) -> tuple[int, int]:
    with open(path, "rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])


def fmt_float(x: float) -> str:
    s = repr(float(x))
    return s[:-2] if s.endswith(".0") and "e" not in s else s


def gd_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


# --------------------------------------------------------------------------------------
# Salida: se arma un plan {ruta: bytes | Path a copiar} y se sincroniza al final.

class Plan:
    def __init__(self) -> None:
        self.archivos: dict[Path, bytes | Path] = {}

    def escribir(self, ruta: Path, contenido: str) -> None:
        self.archivos[ruta] = contenido.encode("utf-8")

    def copiar(self, origen: Path, ruta: Path) -> None:
        self.archivos[ruta] = origen


def sincronizar(plan: Plan, raices: list[Path]) -> None:
    escritos = 0
    for ruta, fuente in sorted(plan.archivos.items()):
        nuevo = fuente if isinstance(fuente, bytes) else None
        if ruta.exists():
            if nuevo is None:
                a, b = ruta.stat(), fuente.stat()
                if (a.st_size, a.st_mtime_ns) == (b.st_size, b.st_mtime_ns):
                    continue
            elif ruta.read_bytes() == nuevo:
                continue
        ruta.parent.mkdir(parents=True, exist_ok=True)
        if nuevo is None:
            shutil.copy2(fuente, ruta)  # conserva la fecha: así la próxima vez se compara rápido
        else:
            ruta.write_bytes(nuevo)
        escritos += 1
    borrados = 0
    for raiz in raices:
        if not raiz.exists():
            continue
        for f in sorted(raiz.rglob("*"), reverse=True):
            if f.is_dir():
                if not any(f.iterdir()):
                    f.rmdir()
                continue
            principal = f.with_suffix("") if f.suffix in (".import", ".uid") else f
            if principal not in plan.archivos:
                f.unlink()
                borrados += 1
    print(f"  {len(plan.archivos)} archivos ({escritos} escritos, {borrados} borrados)")


# --------------------------------------------------------------------------------------
# Lectura de las tablas de datos en GML (cadenas de if(cond)return(valor); ).

_COND_OK = re.compile(r"^[\sA-Za-z0-9_()!=<>&|]*$")


def _parentesis(s: str, i: int) -> int:
    """Índice justo después del paréntesis que cierra el que abre en s[i]."""
    nivel = 0
    for j in range(i, len(s)):
        if s[j] == "(":
            nivel += 1
        elif s[j] == ")":
            nivel -= 1
            if nivel == 0:
                return j + 1
    raise ValueError("paréntesis sin cerrar")


def _compilar_cond(cond: str, var: str):
    if not _COND_OK.match(cond):
        return None
    py = cond.replace("&&", " and ").replace("||", " or ")
    py = re.sub(r"(?<![<>!=])=(?!=)", "==", py)
    py = re.sub(rf"\b{var}\b", "v", py)
    if re.search(r"[A-Za-z_]\w*", py.replace(" and ", " ").replace(" or ", " ").replace("v", "")):
        return None
    try:
        return eval("lambda v: " + py, {"__builtins__": {}})
    except SyntaxError:
        return None


class Tabla:
    """Una función de datos del original: valor(id) = primer return cuya condición se cumple."""

    def __init__(self, gml: str, var: str = "argument0", asignacion: str | None = None) -> None:
        self.simples: dict[int, tuple[int, float | None]] = {}
        self.complejas: list[tuple[int, object, float | str | None]] = []
        self.remapeos: list[tuple[object, int]] = []
        self.ilegibles = 0
        orden = 0
        i = 0
        while True:
            i = gml.find("if(", i)
            if i < 0:
                break
            fin = _parentesis(gml, i + 2)
            cond = gml[i + 3:fin - 1]
            resto = gml[fin:].lstrip()
            i = fin
            m_ret = re.match(r"return\s*\(*\s*(-?[\d.]+|" + var + r")\s*\)*\s*;", resto)
            m_asig = asignacion and re.match(asignacion + r"\s*=\s*\(*(-?[\d.]+)\)*\s*;", resto)
            m_remap = re.match(var + r"\s*=\s*(\d+)\s*;", resto)
            if m_remap and not m_ret:
                f = _compilar_cond(cond, var)
                if f:
                    self.remapeos.append((f, int(m_remap.group(1))))
                continue
            if not (m_ret or m_asig):
                if resto.startswith("return"):
                    f = _compilar_cond(cond, var)
                    self.complejas.append((orden, f, None))  # valor no literal
                    self.ilegibles += f is None
                    orden += 1
                continue
            valor_txt = (m_ret or m_asig).group(1)
            valor: float | str = "var" if valor_txt == var else float(valor_txt)
            m_simple = re.fullmatch(rf"\s*{var}\s*=\s*\(?(\d+)\)?\s*", cond)
            if m_simple and valor != "var":
                n = int(m_simple.group(1))
                self.simples.setdefault(n, (orden, valor))
            else:
                f = _compilar_cond(cond, var)
                self.complejas.append((orden, f, valor))
                self.ilegibles += f is None
            orden += 1

    def valor(self, v: int, defecto: float | None = None) -> float | None:
        for f, nuevo in self.remapeos:
            if f(v):
                v = nuevo
        mejor = self.simples.get(v)
        for orden, f, val in self.complejas:
            if mejor and orden > mejor[0]:
                break
            if f is None:
                continue
            if f(v):
                if val is None:
                    return defecto
                mejor = (orden, float(v) if val == "var" else val)
                break
        return mejor[1] if mejor else defecto


def leer_lineas(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8").replace("\r", "").split("\n")


def leer_aprendizaje(gml: str) -> dict[int, list[tuple[int, int]]]:
    """Ataque_Nivel: if(PK=N){if(NV=L)return(M); ... return(0);} -> {N: [(nivel, movimiento)]}."""
    sets: dict[int, list[tuple[int, int]]] = {}
    for pk, cuerpo in re.findall(r"if\(PK=(\d+)\)\{(.*?)return\(0\);\}", gml):
        movs = [(int(nv), int(m)) for nv, m in re.findall(r"if\(NV=(\d+)\)return\((\d+)\)", cuerpo)]
        sets.setdefault(int(pk), movs)
    return sets


# Especies que aprenden cualquier MT, tutor o DT (Ataque_MT, Ataque_Tutor, Ataque_DT); 235 ninguno.
APRENDEN_TODO = {151, 500}
NO_APRENDEN = {235}
METODO = {"NIVEL": 0, "MT": 1, "TUTOR": 2, "DT": 3}


def leer_switch(gml: str, var: str) -> dict[int, set[int]]:
    """Ataque_MT / Ataque_Tutor: if(VAR=N){switch(PK){case a: case b: {return(true)...}} -> {N: {a, b}}."""
    tabla: dict[int, set[int]] = {}
    for n, cuerpo in re.findall(rf"if\({var}=(\d+)\)\{{switch\(PK\)\{{(.*?)default:", gml):
        tabla.setdefault(int(n), set()).update(int(c) for c in re.findall(r"case (\d+):", cuerpo))
    for n in re.findall(rf"if\({var}=(\d+)\)\{{return true;\}}", gml):  # sin lista: todos
        tabla[int(n)] = {-1}
    return tabla


def leer_dt(gml: str) -> dict[int, tuple[bool, set[int]]]:
    """Ataque_DT: if(AT=M){if(PK=a || ...)return true;} -> {M: (excluye, {a, ...})}.
    Algunos bloques son al revés: return false para la lista y true para el resto (excluye=True)."""
    tabla = {}
    partes = re.split(r"if\(AT=(\d+)\)\{", gml)
    for i in range(1, len(partes), 2):
        cuerpo = partes[i + 1]
        tabla[int(partes[i])] = ("return false" in cuerpo, {int(x) for x in re.findall(r"PK=(\d+)", cuerpo)})
    return tabla


def aprendizaje_otros(pk: int, mts: dict, mt_mov: "Tabla", tutores: dict, dts: dict) -> list[tuple[int, int]]:
    """[(metodo, movimiento)] por MT (en orden de MT), tutor y DT (en orden de movimiento)."""
    if pk in NO_APRENDEN:
        return []
    todo = pk in APRENDEN_TODO
    lista = []
    for mt, especies in sorted(mts.items()):
        mov = mt_mov.valor(mt)
        if mov and (todo or pk in especies or -1 in especies):
            lista.append((METODO["MT"], int(mov)))
    for mov, especies in sorted(tutores.items()):
        if todo or pk in especies or -1 in especies:
            lista.append((METODO["TUTOR"], mov))
    for mov, (excluye, especies) in sorted(dts.items()):
        if todo or (pk in especies) != excluye:
            lista.append((METODO["DT"], mov))
    return lista


# --------------------------------------------------------------------------------------
# Generación de .tres

class Tres:
    def __init__(self, tipo: str, script_class: str | None = None) -> None:
        self.tipo = tipo
        self.script_class = script_class
        self.ext: dict[str, tuple[str, str]] = {}
        self.subs: list[tuple[str, str, list[str]]] = []

    def ext_resource(self, tipo: str, ruta: str) -> str:
        if ruta not in self.ext:
            self.ext[ruta] = (tipo, str(len(self.ext) + 1))
        return f'ExtResource("{self.ext[ruta][1]}")'

    def sub_resource(self, tipo: str, props: list[str]) -> str:
        ident = f"{tipo}_{len(self.subs) + 1}"
        self.subs.append((tipo, ident, props))
        return f'SubResource("{ident}")'

    def texto(self, props: list[str], tipo_recurso: str = "resource", extra_header: str = "") -> str:
        cab = f'[gd_{tipo_recurso} type="{self.tipo}"'
        if self.script_class:
            cab += f' script_class="{self.script_class}"'
        out = [cab + f" format=3{extra_header}]", ""]
        for ruta, (tipo, ident) in self.ext.items():
            out.append(f'[ext_resource type="{tipo}" path="{ruta}" id="{ident}"]')
        if self.ext:
            out.append("")
        for tipo, ident, sprops in self.subs:
            out.append(f'[sub_resource type="{tipo}" id="{ident}"]')
            out.extend(sprops)
            out.append("")
        out.append("[resource]")
        out.extend(props)
        return "\n".join(out) + "\n"


def atlas(tres: Tres, png: Path, region: tuple[int, int, int, int], margen=None) -> str:
    props = [f"atlas = {tres.ext_resource('Texture2D', res(png))}",
             "region = Rect2(%d, %d, %d, %d)" % region]
    if margen and any(margen):
        props.append("margin = Rect2(%d, %d, %d, %d)" % margen)
    return tres.sub_resource("AtlasTexture", props)


# --------------------------------------------------------------------------------------
# Categorías

def parse_rangos(texto: str) -> list[int]:
    ids: set[int] = set()
    for parte in texto.split(","):
        a, _, b = parte.partition("-")
        ids.update(range(int(a), int(b or a) + 1))
    return sorted(ids)


def extraer_sprites(plan: Plan, ext: Path, ids: list[int]) -> None:
    indice = json.loads((ext / "pkmnbattle" / "index.json").read_text())
    for pk in ids:
        carpeta = ASSETS / "sprites" / "pokemon" / f"{pk:04d}"
        tiras = {}  # sufijo -> (meta, png destino)
        for clave, meta in indice.items():
            m = re.fullmatch(rf"P{pk}_([0-9AHS])(_ALT)?", clave)
            if not m:
                continue
            sufijo = m.group(1) + ("_alt" if m.group(2) else "")
            destino = carpeta / f"{sufijo.lower()}.png"
            plan.copiar(ext / "pkmnbattle" / f"{clave}.png", destino)
            tiras[sufijo] = (meta, destino)
        if not tiras:
            avisar(f"sin sprites de batalla para el Pokémon {pk}")
            continue
        # Todos los frames comparten un lienzo centrado en el origen del sprite original.
        mitad_w = max(max(m["origin"][0], m["w"] - m["origin"][0]) for m, _ in tiras.values())
        mitad_h = max(max(m["origin"][1], m["h"] - m["origin"][1]) for m, _ in tiras.values())
        tres = Tres("SpriteFrames")
        animaciones = []

        def frame(meta, png, n):
            ox, oy = meta["origin"]
            margen = (mitad_w - ox, mitad_h - oy, 2 * mitad_w - meta["w"], 2 * mitad_h - meta["h"])
            return atlas(tres, png, (n * meta["w"], 0, meta["w"], meta["h"]), margen)

        def animacion(nombre, frames, fps, loop):
            animaciones.append((nombre, frames, fps, loop))

        for alt in ("", "_alt"):
            for d in DIRECCIONES_MOVER:
                if d + alt in tiras:
                    meta, png = tiras[d + alt]
                    fps = velocidad_animacion(meta["frames"]) * STEPS_POR_SEGUNDO
                    animacion(f"mover_{d}{alt}", [frame(meta, png, n) for n in range(meta["frames"])], fps, True)
            for letra, nombre in (("A", "ataque"), ("H", "herido")):
                if letra + alt in tiras:
                    meta, png = tiras[letra + alt]
                    for n in range(min(meta["frames"], len(DIRECCION_POR_FRAME))):
                        animacion(f"{nombre}_{DIRECCION_POR_FRAME[n]}{alt}", [frame(meta, png, n)], 0.0, False)
            if "S" + alt in tiras:
                meta, png = tiras["S" + alt]
                animacion(f"dormido{alt}", [frame(meta, png, n) for n in range(meta["frames"])],
                          0.05 * STEPS_POR_SEGUNDO, True)
        props = ["animations = [" + ", ".join(
            "{\n\"frames\": [" + ", ".join(
                "{\n\"duration\": 1.0,\n\"texture\": %s\n}" % f for f in frames) + "],\n"
            f"\"loop\": {'true' if loop else 'false'},\n\"name\": &\"{nombre}\",\n\"speed\": {fmt_float(fps)}\n}}"
            for nombre, frames, fps, loop in animaciones) + "]"]
        plan.escribir(carpeta / "sprite_frames.tres", tres.texto(props))


def velocidad_animacion(frames: int) -> float:
    """GetImageSpeed del original (image_speed por step)."""
    if frames >= 4:
        return 0.3
    return {3: 0.2, 2: 0.15}.get(frames, 0.1)


def extraer_datos(plan: Plan, ext: Path, indice: dict) -> None:
    scripts = ext / "scripts"
    gml = lambda nombre: (scripts / f"{nombre}.gml").read_text(encoding="utf-8")
    texto = ext / "text" / "es"

    # Movimientos
    nombres_mov = leer_lineas(texto / "txt_attack.txt")
    descs_mov = leer_lineas(texto / "txt_attack_desc.txt")
    poder = Tabla(gml("TheoricBaseAttack"))
    tipo_mov = Tabla(gml("TheoricTypeAttack"))
    costo = Tabla(gml("TheoricPPAtack"))
    modo = Tabla(gml("ModeAtack"))
    rutas_mov: dict[int, Path] = {}
    tipos_raros: dict[int, int] = {}
    for i, nombre in enumerate(nombres_mov, start=1):
        nombre = nombre.strip()
        if not nombre:
            continue
        t = tipo_mov.valor(i)
        t = 1 if t is None else int(t)
        if t not in TIPO_JUEGO_A_ENUM:
            tipos_raros[t] = tipos_raros.get(t, 0) + 1
        ruta = DATA / "moves" / f"{i:04d}_{snake(nombre) or 'sin_nombre'}.tres"
        rutas_mov[i] = ruta
        tres = Tres("Resource", "MoveData")
        props = [
            f"script = {tres.ext_resource('Script', 'res://scripts/resources/move_data.gd')}",
            f"nombre = {gd_str(nombre)}",
            f"id_original = {i}",
            f"tipo = {TIPO_JUEGO_A_ENUM.get(t, 0)}",
            f"categoria = {int(modo.valor(i, 2) or 0)}",
            f"poder = {int(poder.valor(i, 0) or 0)}",
            f"costo_energia = {int(costo.valor(i, 0) or 0)}",
            f"descripcion = {gd_str(descs_mov[i - 1].strip() if i <= len(descs_mov) else '')}",
        ]
        plan.escribir(ruta, tres.texto(props))
    for t, n in sorted(tipos_raros.items()):
        avisar(f"{n} movimientos con tipo {t} del juego (sin equivalente en Tipos): se guardan como NORMAL")
    print(f"  {len(rutas_mov)} movimientos")

    # Especies
    nombres_pk = leer_lineas(texto / "txt_pkmn.txt")
    stats = {campo: Tabla(gml(script), asignacion="base") for campo, script in [
        ("hp", "StatPSPokemon"), ("ataque", "StatATPokemon"), ("defensa", "StatDEFPokemon"),
        ("ataque_esp", "StatATSpPokemon"), ("defensa_esp", "StatDEFSpPokemon"),
        ("velocidad", "StatVELPokemon"), ("energia", "StatPPMPokemon")]}
    tipo_a = Tabla(gml("TypeAPokemon"))
    tipo_b = Tabla(gml("TypeBPokemon"))
    exp_base = Tabla(gml("ExpBase"), var="PK")
    orden_dex = Tabla(gml("GetOrdenDex"))
    crecimiento = Tabla(gml("GetCrecimiento"), var="PK")
    aprendizaje = leer_aprendizaje(gml("Ataque_Nivel"))
    mts, mt_mov = leer_switch(gml("Ataque_MT"), "MK"), Tabla(gml("MTAtack"))
    tutores, dts = leer_switch(gml("Ataque_Tutor"), "MV"), leer_dt(gml("Ataque_DT"))
    total = 0
    for a, b in RANGOS_ESPECIES:
        for pk in range(a, b + 1):
            linea = pk if pk <= 1000 else pk - 1000
            nombre = nombres_pk[linea - 1].strip() if linea <= len(nombres_pk) else ""
            if not nombre or stats["hp"].valor(pk) is None:
                continue
            dex = int(orden_dex.valor(pk, pk) or pk)
            tres = Tres("Resource", "PokemonData")
            tipos = [TIPO_JUEGO_A_ENUM[int(t)] for t in (tipo_a.valor(pk, 0), tipo_b.valor(pk, 0))
                     if t and int(t) in TIPO_JUEGO_A_ENUM]
            props = [
                f"script = {tres.ext_resource('Script', 'res://scripts/resources/pokemon_data.gd')}",
                f"nombre = {gd_str(nombre)}",
                f"numero_pokedex = {dex}",
                f"id_original = {pk}",
                "tipos = Array[int]([%s])" % ", ".join(str(t) for t in tipos),
            ]
            for campo, tabla in stats.items():
                props.append(f"{campo} = {int(tabla.valor(pk, 1) or 1)}")
            props.append(f"exp_base = {int(exp_base.valor(pk, 0) or 0)}")
            props.append(f"crecimiento = {int(crecimiento.valor(dex, 0) or 0)}")
            frente = ASSETS / "sprites" / "pokemon" / f"{pk:04d}" / "2.png"
            if frente.exists():  # la categoría sprites ya se sincronizó antes que datos
                w, h = png_size(frente)
                frames = indice.get(f"P{pk}_2", {}).get("frames", 1)
                props.append(f"sprite = {atlas(tres, frente, (0, 0, w // max(frames, 1), h))}")
            entradas = [(METODO["NIVEL"], m, nv) for nv, m in sorted(aprendizaje.get(pk, []))]
            entradas += [(metodo, m, 0) for metodo, m in aprendizaje_otros(pk, mts, mt_mov, tutores, dts)]
            script_apr = tres.ext_resource("Script", "res://scripts/resources/movimiento_aprendible.gd")
            refs = []
            for metodo, m, nv in entradas:
                if m not in rutas_mov:
                    continue
                sub = [f"script = {script_apr}", f"move = {tres.ext_resource('Resource', res(rutas_mov[m]))}"]
                if nv:
                    sub.append(f"nivel = {nv}")
                if metodo:
                    sub.append(f"metodo = {metodo}")
                refs.append(tres.sub_resource("Resource", sub))
            props.append(f"movimientos_aprendibles = Array[{script_apr}]([{', '.join(refs)}])")
            plan.escribir(DATA / "pokemon" / f"{pk:04d}_{snake(nombre)}.tres", tres.texto(props))
            total += 1
    print(f"  {total} especies")
    tablas = {"TheoricBaseAttack": poder, "TheoricTypeAttack": tipo_mov, "TheoricPPAtack": costo, "ModeAtack": modo,
              "TypeAPokemon": tipo_a, "TypeBPokemon": tipo_b, "ExpBase": exp_base, "GetOrdenDex": orden_dex,
              "GetCrecimiento": crecimiento, **{t: v for t, v in zip(
                  ["StatPSPokemon", "StatATPokemon", "StatDEFPokemon", "StatATSpPokemon", "StatDEFSpPokemon",
                   "StatVELPokemon", "StatPPMPokemon"], stats.values())}}
    for nombre, tabla in tablas.items():
        if tabla.ilegibles:
            avisar(f"{nombre}: {tabla.ilegibles} condiciones que no se pudieron leer (se ignoran)")


def extraer_fondos(plan: Plan, juego: Path, todos: bool) -> None:
    for estilo in ("realistic", "traditional"):
        pngs = sorted((juego / "data" / "battleback" / estilo).glob("*.png"), key=lambda p: (len(p.stem), p.stem))
        if not todos:
            pngs = pngs[:3] if estilo == "realistic" else []
        for png in pngs:
            plan.copiar(png, ASSETS / "sprites" / "battlebacks" / estilo / f"{snake(png.stem)}.png")


def extraer_tilesets(plan: Plan, juego: Path) -> dict[str, tuple[Path, Path, int, int]]:
    """Copia cada fondo/tileset del juego y crea su TileSet de 16x16. Devuelve {nombre: (png, tres, w, h)}."""
    tilesets = {}
    for png in sorted((juego / "_internal" / "backgrounds").glob("*.png")):
        destino = ASSETS / "sprites" / "tilesets" / f"{snake(png.stem)}.png"
        plan.copiar(png, destino)
        w, h = png_size(png)
        tres = Tres("TileSet")
        celdas = [f"{x}:{y}/0 = 0" for y in range(h // 16) for x in range(w // 16)]
        fuente = tres.sub_resource("TileSetAtlasSource", [f"texture = {tres.ext_resource('Texture2D', res(destino))}"] + celdas)
        ruta_tres = destino.with_suffix(".tres")
        plan.escribir(ruta_tres, tres.texto([f"sources/0 = {fuente}"]))
        tilesets[png.stem] = (destino, ruta_tres, w, h)
    return tilesets


def extraer_mapas(plan: Plan, ext: Path, tilesets: dict, filtro: list[str] | None) -> None:
    rooms = sorted((ext / "rooms").glob("*.json"))
    if filtro:
        rooms = [r for r in rooms if r.stem in filtro]
        faltan = set(filtro) - {r.stem for r in rooms}
        if faltan:
            avisar("mapas que no existen: " + ", ".join(sorted(faltan)))
    for ruta in rooms:
        room = json.loads(ruta.read_text(encoding="utf-8"))
        plan.escribir(ASSETS / "mapas" / f"{snake(room['name'])}.tscn", escena_mapa(room, tilesets))
    print(f"  {len(rooms)} mapas")


def escena_mapa(room: dict, tilesets: dict) -> str:
    ext: dict[str, tuple[str, str]] = {}

    def ref(tipo: str, ruta: Path) -> str:
        r = res(ruta)
        if r not in ext:
            ext[r] = (tipo, str(len(ext) + 1))
        return f'ExtResource("{ext[r][1]}")'

    nodos: list[str] = []

    def nodo(nombre: str, tipo: str, padre: str, props: list[str]) -> None:
        nodos.append(f'[node name="{nombre}" type="{tipo}" parent="{padre}"]')
        nodos.extend(props)
        nodos.append("")

    nombre_raiz = room["name"]
    nodo("Fondos", "Node2D", ".", [])
    for i, bg in enumerate(room["backgrounds"]):
        if not bg.get("visible") or not bg.get("bg") or bg["bg"] not in tilesets:
            continue
        png, _, w, h = tilesets[bg["bg"]]
        props = [f"texture = {ref('Texture2D', png)}", "centered = false",
                 f"position = Vector2({bg['x']}, {bg['y']})"]
        if bg.get("tile_h") or bg.get("tile_v"):
            rw = room["width"] if bg.get("tile_h") else w
            rh = room["height"] if bg.get("tile_v") else h
            props += ["texture_repeat = 2", "region_enabled = true", f"region_rect = Rect2(0, 0, {rw}, {rh})"]
        if bg.get("foreground"):
            props.append("z_index = 1")
        nodo(f"fondo_{i}", "Sprite2D", "Fondos", props)

    nodo("Tiles", "Node2D", ".", [])
    por_depth: dict[int, list[dict]] = {}
    for t in room["tiles"]:
        por_depth.setdefault(t["depth"], []).append(t)
    for depth in sorted(por_depth, reverse=True):  # mayor depth = más al fondo = primero
        padre_depth = f"profundidad_{depth}".replace("-", "m")
        nodo(padre_depth, "Node2D", "Tiles", [])
        # una capa por tileset y desfase dentro de la rejilla (hay tiles puestos en x = 8, etc.)
        capas: dict[tuple[str, int, int], dict[tuple[int, int], tuple[int, int]]] = {}
        sueltos: list[dict] = []
        for t in por_depth[depth]:
            if t["bg"] not in tilesets:
                avisar(f"{nombre_raiz}: tileset {t['bg']} no existe")
                continue
            _, _, tw, th = tilesets[t["bg"]]
            en_rejilla = (t["xscale"] == 1 and t["yscale"] == 1 and t["blend"] == 0xFFFFFFFF
                          and all(v % 16 == 0 for v in (t["tx"], t["ty"], t["w"], t["h"]))
                          and t["tx"] + t["w"] <= tw - tw % 16 and t["ty"] + t["h"] <= th - th % 16)
            celdas = {}
            if en_rejilla:
                fx, fy = t["x"] % 16, t["y"] % 16
                capa = capas.setdefault((t["bg"], fx, fy), {})
                for dy in range(0, t["h"], 16):
                    for dx in range(0, t["w"], 16):
                        celda = ((t["x"] - fx + dx) // 16, (t["y"] - fy + dy) // 16)
                        if celda in capa or celda in celdas:
                            en_rejilla = False
                        celdas[celda] = ((t["tx"] + dx) // 16, (t["ty"] + dy) // 16)
            if en_rejilla:
                capa.update(celdas)
            else:
                sueltos.append(t)
        for (bg, fx, fy), celdas in sorted(capas.items()):
            datos = bytearray(struct.pack("<H", 0))
            for (x, y), (ax, ay) in sorted(celdas.items(), key=lambda c: (c[0][1], c[0][0])):
                datos += struct.pack("<hhHHHH", x, y, 0, ax, ay, 0)
            props = [] if (fx, fy) == (0, 0) else [f"position = Vector2({fx}, {fy})"]
            nombre = snake(bg) + ("" if (fx, fy) == (0, 0) else f"_desfase_{fx}_{fy}")
            nodo(nombre, "TileMapLayer", f"Tiles/{padre_depth}", props + [
                "tile_map_data = PackedByteArray(%s)" % ", ".join(str(b) for b in datos),
                f"tile_set = {ref('TileSet', tilesets[bg][1])}"])
        for t in sueltos:
            props = [f"texture = {ref('Texture2D', tilesets[t['bg']][0])}", "centered = false",
                     f"position = Vector2({t['x']}, {t['y']})",
                     "region_enabled = true", f"region_rect = Rect2({t['tx']}, {t['ty']}, {t['w']}, {t['h']})"]
            if t["xscale"] != 1 or t["yscale"] != 1:
                props.append(f"scale = Vector2({fmt_float(t['xscale'])}, {fmt_float(t['yscale'])})")
            if t["blend"] != 0xFFFFFFFF:
                c = t["blend"]
                props.append("modulate = Color(%s, %s, %s, %s)" % tuple(
                    fmt_float(round(v / 255, 4)) for v in (c & 255, (c >> 8) & 255, (c >> 16) & 255, (c >> 24) & 255)))
            nodo(f"tile_{t['id']}", "Sprite2D", f"Tiles/{padre_depth}", props)

    nodo("Instancias", "Node2D", ".", [])
    for inst in room["instances"]:
        props = [f"position = Vector2({inst['x']}, {inst['y']})"]
        if inst.get("angle"):
            props.append(f"rotation = {fmt_float(-inst['angle'] * 3.141592653589793 / 180)}")
        if inst["xscale"] != 1 or inst["yscale"] != 1:
            props.append(f"scale = Vector2({fmt_float(inst['xscale'])}, {fmt_float(inst['yscale'])})")
        props.append(f"metadata/objeto = {gd_str(inst['object'] or '')}")
        if inst.get("creation_code"):
            props.append(f"metadata/codigo_creacion = {gd_str(inst['creation_code'])}")
        nodo(f"{inst['object'] or 'sin_objeto'}_{inst['id']}", "Marker2D", "Instancias", props)

    out = ["[gd_scene format=3]", ""]
    for r, (tipo, ident) in ext.items():
        out.append(f'[ext_resource type="{tipo}" path="{r}" id="{ident}"]')
    out += ["", f'[node name="{snake(nombre_raiz)}" type="Node2D"]',
            f"metadata/nombre_original = {gd_str(nombre_raiz)}",
            f"metadata/tamano = Vector2i({room['width']}, {room['height']})", ""]
    return "\n".join(out + nodos)


def _chunks_wav(b: bytes, con_relleno: bool) -> list[tuple[bytes, bytes]] | None:
    chunks, i = [], 12
    while i + 8 <= len(b):
        cid, sz = b[i:i + 4], struct.unpack("<I", b[i + 4:i + 8])[0]
        if not re.fullmatch(rb"[ -~]{4}", cid) or sz > len(b) - i - 8:
            return None
        chunks.append((cid, b[i + 8:i + 8 + sz]))
        i += 8 + sz + (sz & 1 if con_relleno else 0)
    if con_relleno and i != len(b):  # sobran o faltan bytes (falta el relleno del último chunk)
        return None
    return chunks


def extraer_gritos(plan: Plan, origen: Path, destino: Path) -> None:
    """Copia los .wav; arregla los que Godot no puede importar (ver README)."""
    arreglados = 0
    for f in sorted(origen.glob("*.wav")):
        b = f.read_bytes()
        chunks = _chunks_wav(b, True)
        bien = chunks is not None
        chunks = chunks or _chunks_wav(b, False) or []
        partes = dict(chunks)
        fmt, data = partes.get(b"fmt "), partes.get(b"data")
        ruta = destino / (snake(f.stem) + ".wav")
        if fmt and data and struct.unpack("<H", fmt[:2])[0] == 0x55:  # MP3 dentro del WAV
            plan.archivos[ruta.with_suffix(".mp3")] = data
            arreglados += 1
        elif bien or not (fmt and data):
            plan.copiar(f, ruta)
        else:  # chunk impar sin byte de relleno (Godot se pasa del final): se rearma con fmt + data
            cuerpo = (b"WAVE" + b"fmt " + struct.pack("<I", len(fmt)) + fmt
                      + b"data" + struct.pack("<I", len(data)) + data + b"\0" * (len(data) & 1))
            plan.archivos[ruta] = b"RIFF" + struct.pack("<I", len(cuerpo)) + cuerpo
            arreglados += 1
    print(f"  {arreglados} wav arreglados")


def extraer_simple(plan: Plan, origen: Path, destino: Path, patrones: list[str]) -> None:
    for patron in patrones:
        for f in sorted(origen.glob(patron)):
            rel = f.relative_to(origen)
            plan.copiar(f, destino / rel.parent / (snake(f.stem) + f.suffix.lower()))


# --------------------------------------------------------------------------------------

EXT = REPO / "extracted"


def main() -> None:
    global EXT
    ap = argparse.ArgumentParser(description="Extrae assets y datos del juego original para nativo/.")
    ap.add_argument("--juego", type=Path, default=REPO / "gamedata", help="carpeta gamedata/ (por defecto la del repo)")
    ap.add_argument("--extraido", type=Path, default=REPO / "extracted", help="carpeta extracted/ (por defecto la del repo)")
    ap.add_argument("--pokemon", default="1-151", help="ids para los sprites de batalla, p. ej. 1-151,2001-2010")
    ap.add_argument("--solo", help="solo estas categorías (separadas por coma): " + ", ".join(CATEGORIAS))
    for c in CATEGORIAS:
        if c not in POR_DEFECTO:
            ap.add_argument(f"--{c}", action="store_true", help=f"agrega la categoría {c}")
    ap.add_argument("--mapas-lista", metavar="NOMBRES", help="con --mapas: solo estos mapas (nombre original, separados por coma)")
    ap.add_argument("--fondos-todos", action="store_true", help="todos los fondos de batalla (por defecto solo 3)")
    ap.add_argument("--todo", action="store_true", help="todas las categorías")
    ap.add_argument("--limpiar", action="store_true", help="borra todo lo extraído y sale")
    args = ap.parse_args()
    EXT = args.extraido

    if args.limpiar:
        for raiz in (ASSETS, DATA):
            if raiz.exists():
                shutil.rmtree(raiz)
        print("Borrado:", res(ASSETS), res(DATA))
        return

    if args.todo:
        categorias = list(CATEGORIAS)
    elif args.solo:
        categorias = [c.strip() for c in args.solo.split(",")]
        malas = [c for c in categorias if c not in CATEGORIAS]
        if malas:
            ap.error("categorías desconocidas: " + ", ".join(malas))
    else:
        categorias = POR_DEFECTO + [c for c in CATEGORIAS if c not in POR_DEFECTO and getattr(args, c)]
    if "mapas" in categorias and "tilesets" not in categorias:
        categorias.append("tilesets")  # los mapas usan los TileSet
    for carpeta in (args.juego, args.extraido):
        if not carpeta.is_dir():
            sys.exit(f"No existe {carpeta}: corre primero el pipeline del README principal.")

    orden = [c for c in CATEGORIAS if c in categorias]
    # sprites antes que datos: PokemonData.sprite apunta al sprite si se extrajo
    orden.sort(key=lambda c: (c != "sprites", c != "tilesets"))
    tilesets = {}
    for cat in orden:
        print(f"[{cat}]")
        plan = Plan()
        if cat == "datos":
            extraer_datos(plan, EXT, json.loads((EXT / "pkmnbattle" / "index.json").read_text()))
        elif cat == "sprites":
            extraer_sprites(plan, EXT, parse_rangos(args.pokemon))
        elif cat == "fondos":
            extraer_fondos(plan, args.juego, args.fondos_todos)
        elif cat == "tilesets":
            tilesets = extraer_tilesets(plan, args.juego)
        elif cat == "mapas":
            filtro = [m.strip() for m in args.mapas_lista.split(",")] if args.mapas_lista else None
            extraer_mapas(plan, EXT, tilesets, filtro)
        elif cat == "musica":
            musica = args.juego / "data" / "audio"
            extraer_simple(plan, musica / "musica", ASSETS / "audio" / "music", ["*/*.ogg"])
            extraer_simple(plan, musica, ASSETS / "audio" / "music" / "intro", ["*.mp3"])
        elif cat == "gritos":
            extraer_gritos(plan, args.juego / "data" / "audio" / "grito", ASSETS / "audio" / "sfx" / "gritos")
        elif cat == "entrenadores":
            extraer_simple(plan, args.juego / "data" / "trainer", ASSETS / "sprites" / "trainers", ["*.png"])
        sincronizar(plan, CARPETAS[cat])
    print("Listo. Abre nativo/ en Godot (o corre --import) para que importe lo nuevo.")


if __name__ == "__main__":
    main()
