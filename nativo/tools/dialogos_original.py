"""Datos para los diálogos de los NPCs del original (Dialogo / DialogoSimple):

- quién habla: NameTrainer(sprINDEX) (líneas de txt_character), el nombre del cuadro con retrato;
- su retrato: ImportTrainer(sprINDEX) da un sprite interno o data/trainer/<n>.gif, y
  getBigTrainerOffsets(sprINDEX, "X"/"Y"/"Z") el recorte de 32x32 (y el cuadro) que se dibuja;
- GetStaticNPCIndex: el sprINDEX de los NPCs que solo tienen sprite (TalkHabla lo usa al hablar);
- NameTecla: el nombre de una tecla, para los textos que la nombran ($par1$).

Solo biblioteca estándar.
"""
from __future__ import annotations

import re
from pathlib import Path

import gml_eval
import gml_visual


class Funciones(gml_eval.Funciones):
    """gml_eval que además lee los textos del juego (TextMenu, TextCharacter, TextDialog...)."""

    ARCHIVOS = {"TextMenu": "txt_menu", "TextCharacter": "txt_character", "TextDialog": "txt_dialog",
                "TextBattle": "txt_battle"}

    def __init__(self, carpeta_scripts: Path, carpeta_textos: Path):
        super().__init__(carpeta_scripts)
        self.textos = carpeta_textos
        self._lineas: dict[str, list[str]] = {}

    def linea(self, archivo: str, n: int) -> str:
        if archivo not in self._lineas:
            ruta = self.textos / f"{archivo}.txt"
            self._lineas[archivo] = ruta.read_text(encoding="utf-8").replace("\r", "").split("\n") if ruta.exists() else []
        lineas = self._lineas[archivo]
        return lineas[n - 1] if 1 <= n <= len(lineas) else ""

    def _llamar(self, nombre: str, args: list, profundidad: int):
        if nombre in self.ARCHIVOS:
            return self.linea(self.ARCHIVOS[nombre], int(args[0]))
        if nombre == "chr":
            return chr(int(args[0]))
        if nombre == "ord":
            return float(ord(args[0][0])) if args[0] else 0.0
        return super()._llamar(nombre, args, profundidad)


def teclas_por_defecto(gml_default: str) -> dict[str, int]:
    """DefaultKeyAssignment: nombre de la tecla del original (key_ex_accion...) → su código."""
    out = {}
    for nombre, valor in re.findall(r"(key_\w+)=([^;]+);", gml_default):
        valor = valor.strip()
        m = re.fullmatch(r"ord\('(.)'\)", valor)
        if m:
            out[nombre] = ord(m.group(1))
        elif isinstance(gml_visual.CONSTANTES.get(valor), (int, float)):
            out[nombre] = int(gml_visual.CONSTANTES[valor])
    return out


def indices_estaticos(gml: str) -> dict[int, int]:
    """GetStaticNPCIndex: sprite del NPC → su sprINDEX."""
    return {int(s): int(n) for s, n in re.findall(r"if\(trainerSprite=\((\d+)\)\)return\((\d+)\);", gml)}


def _sprites_import(gml: str) -> dict[float, int]:
    """ImportTrainer: los TR que usan un sprite interno (global.TRAINER_SPR=(S); exit)."""
    return {float(t): int(s) for t, s in re.findall(r"if\(TR=([\d.]+)\)\{global\.TRAINER_SPR=\((\d+)\);exit;?\}", gml)}


def _nombre_archivo(tr: float) -> str:
    """El nombre de data/trainer/<TRS>.gif que arma ImportTrainer: 17.2 → "17_2"."""
    if tr in (17.2, 18.2, 56.2, 65.2):
        tr = float(int(tr))
    if tr == 3052:
        tr = 10052
    texto = f"{tr:.4f}".rstrip("0").rstrip(".")
    return texto.replace(".", "_")


class Personajes:
    """Nombre y retrato de cada sprINDEX, como los resuelve el original al hablar."""

    def __init__(self, juego, funciones: Funciones, carpeta_trainers: Path):
        self.juego = juego
        self.f = funciones
        self.trainers = carpeta_trainers
        self.import_sprites = _sprites_import(juego.script("ImportTrainer"))
        self.estaticos = indices_estaticos(juego.script("GetStaticNPCIndex"))

    def nombre(self, sprindex: float) -> str:
        v = self.f.llamar("NameTrainer", float(sprindex))
        return v if isinstance(v, str) else ""

    def retrato(self, sprindex: float) -> dict | None:
        """{"sprite": nombre interno} o {"archivo": "<n>.png", "frames": n}, con el recorte x, y y el
        cuadro; None si no tiene."""
        if sprindex < 0:
            return None
        recorte = {}
        for clave, eje in (("x", "X"), ("y", "Y"), ("cuadro", "Z")):
            v = self.f.llamar("getBigTrainerOffsets", float(sprindex), eje)
            recorte[clave] = int(v) if isinstance(v, float) else 0
        if float(sprindex) in self.import_sprites:
            s = self.import_sprites[float(sprindex)]
            nombre = self.juego.sprites[s] if 0 <= s < len(self.juego.sprites) else None
            return {"sprite": nombre, **recorte} if nombre else None
        archivo = _nombre_archivo(float(sprindex)) + ".png"
        if not (self.trainers / archivo).exists():
            return None
        frames = self.trainers / (archivo + ".frames")
        n = int(frames.read_text().strip() or 1) if frames.exists() else 1
        return {"archivo": archivo, "frames": n, **recorte}
