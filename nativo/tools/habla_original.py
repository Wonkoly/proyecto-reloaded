"""Traductor de los scripts *Habla del original (lo que hace un NPC al hablarle) a .evento.

Se usa el parser de GML de gml_visual. Las máquinas de estados (if(PROGRESO=k){...; PROGRESO+=1;
alarm[n]=t; exit;}) se encadenan en orden, como las ejecuta el original paso a paso. Lo que se traduce:
  Dialogo(TextDialog(N)[, S]) / DialogoIndexFace(N, S) → hablante + decir, o narrar sin hablante
  Dialogo(TextoPar1/2(TextDialog(N), a, b), S)          → decir N a b (con $prota$ / $rival$ si toca)
  (18).X = v, += v, -= v / (18).X[k] = v                → bandera X = v (X_k)
  PillaObject(id, n) / GastaObject(id, n)               → dar_objeto / quitar_objeto
  PrepareBattleTrainer(N)                               → combate N y lo que sigue, bajo "si gano:"
  show_pregunta / ShowDialogQuestion(TextDialog(N))     → si pregunta N:
  LookAtTheProta / ExclamationEffect / instance_destroy → mirar_jugador / exclamacion / ocultar
  CentroPokemon / HealingPokeCenter                     → curar
  Sleep(ms) (300 ms o más)                              → esperar
  if con banderas (18).X, números, &&, ||, !, =, <, >   → si ... :
Lo demás (efectos, sonidos, sprites, misiones, coreografías con with(...)) queda como comentario
"# sin traducir: ..." para revisarlo; la historia (banderas, combates, objetos, diálogos) sí pasa.
"""
from __future__ import annotations

import re

import gml_visual as gv

# Llamadas que no cambian nada del juego que el port necesite (visuales, sonido, seguridad...).
IGNORAR = {
    "screen_redraw", "EndAnimation", "BeginAnimation", "Destruye", "sound_play", "Sound_Play", "sound_stop_all",
    "Sound_World", "effect_create_above", "GetSecurityPK", "SecurityPK", "GetSecurityPK2", "SecurityPK2",
    "GetSecurityVFR", "SecurityVFR", "GetSecurityFrente", "SecurityFrente", "GetSecurityBAT", "SecurityBAT",
    "setEstadoObjetivo", "setEstadoMision", "EstableceLogro", "room_restart", "RoomRestart", "ImportGrito",
    "NPCSpriteAdjustments", "SpriteTrainer", "CreateBallEffect", "EffectAtackCreate", "ReadyInteraction",
    "UpdatePokemonCambioRoom", "draw_barra", "JuegaArray128", "LimpiezaTecla", "SetAlarm1", "Renew_Sprite",
    "Begin_Sprite", "GuardarPartida", "UpdateQuests", "keyboard_clear", "io_clear",
}


class _NoVa(Exception):
    pass


class Traductor:
    def __init__(self, nombre: str, salas: list[str] | None = None):
        self.nombre = nombre
        self.salas = salas or []
        # global.xx / yy / mira / lugar antes de room=global.lugar (un viaje a otro mapa).
        self.viaje: dict[str, str] = {}
        # if(distance_to_object((14))<N) al principio: el original lo lanza al acercarse a N px.
        self.automatico = 0
        # Variables del objeto (PROGRESO y las que el script asigna con valores simples).
        self.locales: set[str] = set()
        self.lineal = False
        self.alarma = 0
        self.lineas: list[str] = []
        self.sin_traducir = 0
        self.hablante: str | None = None

    # -- utilidades -------------------------------------------------------------------------
    def _emitir(self, nivel: int, texto: str) -> None:
        self.lineas.append("\t" * nivel + texto)

    def _comentario(self, nivel: int, nodo) -> None:
        self.sin_traducir += 1
        self._emitir(nivel, "# sin traducir: " + _gml(nodo)[:110])

    # -- expresiones ------------------------------------------------------------------------
    def condicion(self, e) -> str:
        k = e[0]
        if k == "num":
            return e[1]
        if k == "id" and e[1] in ("true", "false"):
            return "1" if e[1] == "true" else "0"
        if k == "campo" and e[1] == ("num", "18"):
            return e[2]
        if k == "indice" and e[1][0] == "campo" and e[1][1] == ("num", "18") and e[2][0] == "num":
            return f"{e[1][2]}_{e[2][1]}"
        if k == "un" and e[1] == "!":
            dentro = self.condicion(e[2])
            return f"no {dentro}" if dentro.startswith("pregunta ") else f"no ({dentro})"
        if k == "un" and e[1] == "-":
            return f"-{self.condicion(e[2])}"
        if k == "id" and e[1] in self.locales:
            return "_" + e[1].lower()
        if k == "campo" and e[1] == ("id", "global") and e[2] == "day":
            return "dia"
        if k == "llamada" and e[1] == "TrainerBoy":
            return "chico"
        if k == "campo" and e[1] == ("id", "global") and e[2] == "snd_SE":
            return "0"  # el sonido del original: aquí no cambia nada
        if k == "bin" and e[1] in ("=", "==", "!=") and e[2][0] == "llamada" \
                and e[2][1] in ("show_pregunta", "ShowDialogQuestion") and e[3] in (("num", "0"), ("id", "false"), ("num", "1"), ("id", "true")):
            # show_pregunta(...) = / != sí o no.
            si = (e[3] in (("num", "1"), ("id", "true"))) == (e[1] != "!=")
            return f"{'' if si else 'no '}pregunta {self._texto(e[2][2][0])}"
        if k == "bin" and e[1] in ("=", "==") and e[2] == ("campo", ("id", "global"), "day"):
            return "dia" if e[3] in (("id", "true"), ("num", "1")) else "no dia"
        if k == "bin":
            op = {"&&": " y ", "||": " o ", "=": " == ", "==": " == ", "!=": " != ", "<": " < ", ">": " > ",
                  "<=": " <= ", ">=": " >= ", "+": " + ", "-": " - "}.get(e[1])
            if op is None:
                raise _NoVa
            return f"({self.condicion(e[2])}{op}{self.condicion(e[3])})"
        if k == "llamada" and e[1] in ("show_pregunta", "ShowDialogQuestion"):
            return f"pregunta {self._texto(e[2][0])}"
        if k == "llamada" and e[1] == "ObjetoEnMochila" and e[2][0][0] == "num":
            return f"objeto_{e[2][0][1]}"
        raise _NoVa

    def _texto(self, e) -> str:
        """TextDialog(N) → N; TextoPar1/2(TextDialog(N), a, b) → N a b."""
        if e[0] == "llamada" and e[1] == "TextDialog" and e[2][0][0] == "num":
            return e[2][0][1]
        if e[0] == "llamada" and e[1] in ("TextoPar1", "TextoPar2") and e[2]:
            base = self._texto(e[2][0])
            return " ".join([base] + [self._parametro(a) for a in e[2][1:]])
        raise _NoVa

    def _parametro(self, e) -> str:
        if e[0] == "id" and e[1] == "global" or e[0] == "campo" and e[1] == ("id", "global"):
            nombre = e[2] if e[0] == "campo" else ""
            return {"protaname": "$prota$", "rivalname": "$rival$"}.get(nombre, "?")
        if e[0] == "llamada" and e[1] == "SayMyName":
            return "$prota$"
        if e[0] == "llamada" and e[1] == "NameObject" and e[2][0][0] == "num":
            return f'"{e[2][0][1]}"'
        if e[0] == "num":
            return e[1]
        if e[0] == "str":
            return f'"{e[1]}"'
        raise _NoVa

    def _hablante(self, nivel: int, e) -> None:
        if e is None:
            quien = None
        elif e[0] == "num":
            quien = e[1]
        elif e[0] == "id" and e[1] == "sprINDEX":
            quien = "npc"
        elif e[0] == "llamada" and e[1] in ("IndexProtaGrande", "SayMyName"):
            quien = "jugador"
        elif e[0] == "llamada" and e[1] == "IndexRivalGrande" or e == ("campo", ("id", "global"), "rivalname"):
            quien = "rival"
        else:
            raise _NoVa
        if quien != self.hablante and quien is not None:
            self._emitir(nivel, f"hablante {quien}")
            self.hablante = quien

    # -- instrucciones ----------------------------------------------------------------------
    def bloque(self, nodos, nivel: int) -> None:
        i = 0
        while i < len(nodos):
            n = nodos[i]
            # exit: lo que sigue no se ejecuta en esta pasada.
            if n[0] == "exit":
                return
            # PrepareBattleTrainer(N): el combate; al volver el original reinicia la room (el evento acaba).
            if n[0] == "expr" and n[1][0] == "llamada" and n[1][1] == "PrepareBattleTrainer" and n[1][2][0][0] == "num":
                num = n[1][2][0][1]
                self._emitir(nivel, f"combate {num}")
                self._emitir(nivel, "si gano:")
                self._emitir(nivel + 1, f"bandera trainer_{num} = 1")
                self._emitir(nivel, "fin")
                return
            # if(!PillaObject(id, n)) exit;: da el objeto y sigue.
            if n[0] == "if" and n[1][0] == "un" and n[1][1] == "!" and n[1][2][0] == "llamada" \
                    and n[1][2][1] == "PillaObject" and n[1][2][2][0][0] == "num":
                a = n[1][2][2]
                self._emitir(nivel, f"dar_objeto {a[0][1]} {a[1][1] if len(a) > 1 and a[1][0] == 'num' else 1}")
                i += 1
                continue
            # if(c){...; exit;} resto  →  si c: ...  sino: resto
            if n[0] == "if" and n[3] is None and _termina_en_exit(n[2]) and i + 1 < len(nodos):
                try:
                    c = self.condicion(n[1])
                except _NoVa:
                    self._comentario(nivel, n)
                    i += 1
                    continue
                self._emitir(nivel, f"si {c}:")
                hablante = self.hablante
                antes = len(self.lineas)
                self.instruccion(n[2], nivel + 1)
                if len(self.lineas) == antes:
                    self._emitir(nivel + 1, "esperar 0")
                self._emitir(nivel, "sino:")
                self.hablante = hablante
                antes = len(self.lineas)
                self.bloque(nodos[i + 1:], nivel + 1)
                if len(self.lineas) == antes:
                    self._emitir(nivel + 1, "esperar 0")
                return
            self.instruccion(n, nivel)
            i += 1

    def instruccion(self, n, nivel: int) -> None:
        k = n[0]
        try:
            if k == "bloque":
                self.bloque(n[1], nivel)
            elif k in ("nada", "var"):
                pass
            elif k == "exit":
                pass  # solo puede llegar aquí como sentencia suelta de un if: se corta la pasada
            elif k == "if":
                self._si(n, nivel)
            elif k == "asig":
                self._asignacion(n, nivel)
            elif k == "expr" and n[1][0] == "llamada":
                self._llamada(n[1], nivel)
            elif k == "with":
                self._con(n, nivel)
            elif k == "for":
                self._para(n, nivel)
            else:
                self._comentario(nivel, n)
        except _NoVa:
            self._comentario(nivel, n)

    def _si(self, n, nivel: int) -> None:
        _, cond, entonces, sino = n
        c = self.condicion(cond)
        self._emitir(nivel, f"si {c}:")
        hablante = self.hablante
        antes = len(self.lineas)
        self.instruccion(entonces, nivel + 1)
        if len(self.lineas) == antes:
            self._emitir(nivel + 1, "esperar 0")
        self.hablante = None if self.hablante != hablante else hablante
        if sino is not None:
            self._emitir(nivel, "sino:")
            antes = len(self.lineas)
            self.hablante = hablante
            self.instruccion(sino, nivel + 1)
            if len(self.lineas) == antes:
                self._emitir(nivel + 1, "esperar 0")
            self.hablante = None

    def _asignacion(self, n, nivel: int) -> None:
        _, lv, op, valor = n
        nombre = None
        if lv[0] == "campo" and lv[1] == ("num", "18"):
            nombre = lv[2]
        elif lv[0] == "indice" and lv[1][0] == "campo" and lv[1][1] == ("num", "18") and lv[2][0] == "num":
            nombre = f"{lv[1][2]}_{lv[2][1]}"
        if lv[0] == "campo" and lv[1] == ("id", "global") and lv[2] in ("xx", "yy", "mira", "lugar") and op == "=":
            self.viaje[lv[2]] = _gml(valor)
            return
        if lv[0] == "id" and lv[1] == "room" and _gml(valor) == "global.lugar" and {"xx", "yy", "lugar"} <= set(self.viaje):
            lugar = self.viaje["lugar"].strip("()")
            if lugar.isdigit() and int(lugar) < len(self.salas):
                self._emitir(nivel, f"ir_a {self.salas[int(lugar)]} {self.viaje['xx']} {self.viaje['yy']} {self.viaje.get('mira', '2')}")
                self.viaje = {}
                return
            raise _NoVa
        if lv[0] == "campo" and lv[1] == ("id", "global") and lv[2] in ("index_place", "outx", "outy", "room_out"):
            return
        if lv[0] == "indice" and lv[1] == ("id", "alarm"):
            # Solo la alarma que llama a este script lo vuelve a correr (las otras son de otra cosa).
            if not self.lineal and lv[2] == ("num", str(self.alarma)):
                self._emitir(nivel, "bandera _sigue = 1")  # el original vuelve a correr el script
            return
        if lv[0] == "id" and lv[1] in self.locales:
            self._emitir(nivel, f"bandera _{lv[1].lower()} {op} {self.condicion(valor)}")
            return
        if nombre is None:
            if lv[0] == "id" and lv[1] in ("PROGRESO", "alarm", "image_speed", "image_index", "sprite_index", "mira",
                                          "canshoot", "DIR", "vspeed", "hspeed", "speed", "direction", "visible"):
                return
            if lv[0] == "indice" and lv[1] == ("id", "alarm"):
                return
            if lv[0] == "campo" and lv[1] in (("num", "14"), ("num", "27"), ("num", "3")):
                return  # el jugador y la pantalla: posturas y fundidos
            raise _NoVa
        v = self.condicion(valor)
        self._emitir(nivel, f"bandera {nombre} {op} {v}")

    def _llamada(self, e, nivel: int) -> None:
        nombre, args = e[1], e[2]
        if nombre in IGNORAR:
            return
        if nombre in ("Dialogo", "DialogoSimple") and args and _texto_segun_sexo(args[0]):
            # TextDialog(IfElse(TrainerBoy(), A, B)): un texto para chico y otro para chica.
            a, b = _texto_segun_sexo(args[0])
            resto = list(args[1:])
            self._emitir(nivel, "si chico:")
            self._llamada(("llamada", nombre, [("llamada", "TextDialog", [a])] + resto), nivel + 1)
            self._emitir(nivel, "sino:")
            self._llamada(("llamada", nombre, [("llamada", "TextDialog", [b])] + resto), nivel + 1)
            self.hablante = None
            return
        if nombre in ("Dialogo", "DialogoSimple"):
            texto = self._texto(args[0])
            # Dialogo(texto, nombre, sprINDEX) con el nombre calculado (NameMainProta, rival...).
            if len(args) > 2 and args[2][0] == "id" and args[2][1] == "sprINDEX":
                args = [args[0], ("id", "sprINDEX")]
            elif len(args) > 2 and args[2][0] == "llamada" and args[2][1] == "IndexRivalGrande":
                args = [args[0], args[2]]
            if nombre == "Dialogo" and len(args) > 2 and args[2][0] == "num":
                self._hablante(nivel, args[2])  # Dialogo(texto, nombre, sprINDEX)
                self._emitir(nivel, f"decir {texto}")
            elif nombre == "Dialogo" and len(args) > 1:
                self._hablante(nivel, args[1])
                self._emitir(nivel, f"decir {texto}")
            else:
                self._emitir(nivel, f"narrar {texto}")
        elif nombre == "DialogoIndexFace" and args and args[0][0] == "num":
            # DialogoIndexFace(N, nombre, sprINDEX): el retrato es el tercero (o el del NPC).
            cara = args[2] if len(args) > 2 and args[2][0] == "num" else ("id", "sprINDEX")
            self._hablante(nivel, cara)
            self._emitir(nivel, f"decir {args[0][1]}")
        elif nombre in ("show_mensaje", "ShowDialogMessage"):
            self._emitir(nivel, f"narrar {self._texto(args[0])}")
        elif nombre in ("show_pregunta", "ShowDialogQuestion"):
            self._emitir(nivel, f"si pregunta {self._texto(args[0])}:")
            self._emitir(nivel + 1, "esperar 0")
        elif nombre == "PillaObject" and len(args) >= 1 and args[0][0] == "num":
            self._emitir(nivel, f"dar_objeto {args[0][1]} {args[1][1] if len(args) > 1 and args[1][0] == 'num' else 1}")
        elif nombre == "GastaObject" and args and args[0][0] == "num":
            self._emitir(nivel, f"quitar_objeto {args[0][1]} {args[1][1] if len(args) > 1 and args[1][0] == 'num' else 1}")
        elif nombre == "LookAtTheProta":
            self._emitir(nivel, "mirar_jugador")
        elif nombre in ("ExclamationEffect", "ExclamationEffectExt"):
            self._emitir(nivel, "exclamacion")
        elif nombre == "instance_destroy":
            self._emitir(nivel, "ocultar")
        elif nombre in ("CentroPokemon", "HealingPokeCenter"):
            self._emitir(nivel, "curar")
        elif nombre in ("Sleep", "sleep") and args and args[0][0] == "num":
            ms = float(args[0][1])
            if ms >= 300:
                self._emitir(nivel, f"esperar {ms / 1000:g}")
        else:
            raise _NoVa

    def _para(self, n, nivel: int) -> None:
        """for(i=0;i<90;i+=1){if(global.ObX[i]=N)...}: buscar el objeto N en la mochila (o quitarlo)."""
        cuerpo = n[4][1] if n[4][0] == "bloque" else [n[4]]
        if len(cuerpo) != 1 or cuerpo[0][0] != "if":
            raise _NoVa
        cond, entonces = cuerpo[0][1], cuerpo[0][2]
        if not (cond[0] == "bin" and cond[1] in ("=", "==") and cond[2][0] == "indice"
                and cond[2][1][0] == "campo" and cond[2][1][2].startswith("Ob") and cond[3][0] == "num"):
            raise _NoVa
        objeto = cond[3][1]
        sentencias = entonces[1] if entonces[0] == "bloque" else [entonces]
        quita = any(s[0] == "asig" and s[1][0] == "indice" and s[1][1][0] == "campo" and s[1][1][2].startswith("Ob")
                    and s[3] == ("num", "0") for s in sentencias)
        if quita:
            self._emitir(nivel, f"quitar_objeto {objeto} 999")
            return
        asignaciones = [s for s in sentencias if s[0] == "asig" and s[1][0] == "id" and s[1][1] in self.locales]
        if len(asignaciones) != len(sentencias) or not asignaciones:
            raise _NoVa
        self._emitir(nivel, f"si objeto_{objeto}:")
        for s in asignaciones:
            self._emitir(nivel + 1, f"bandera _{s[1][1].lower()} = {self.condicion(s[3])}")

    def _con(self, n, nivel: int) -> None:
        # with((14)){...}: el jugador (posturas); with((N)){ExclamationEffect();}: otro objeto.
        _, quien, cuerpo = n
        if quien == ("num", "14"):
            return
        if cuerpo[0] == "bloque" and all(c[0] == "expr" and c[1][0] == "llamada" and c[1][1] in IGNORAR for c in cuerpo[1]):
            return
        raise _NoVa


def _gml(n) -> str:
    """El nodo como texto parecido al GML (para los comentarios)."""
    if isinstance(n, tuple):
        if n and n[0] == "llamada":
            return f"{n[1]}(" + ",".join(_gml(a) for a in n[2]) + ")"
        if n and n[0] in ("num", "id", "str"):
            return str(n[1])
        if n and n[0] == "campo":
            return f"{_gml(n[1])}.{n[2]}"
        if n and n[0] == "asig":
            return f"{_gml(n[1])}{n[2]}{_gml(n[3])}"
        if n and n[0] == "expr":
            return _gml(n[1])
        if n and n[0] == "if":
            return f"if({_gml(n[1])})..."
        if n and n[0] == "bin":
            return f"{_gml(n[2])}{n[1]}{_gml(n[3])}"
        if n and n[0] == "with":
            return f"with({_gml(n[1])})..."
        return n[0] if n else ""
    return str(n)


def _pasos(ast) -> list | None:
    """Si el script es if(PROGRESO=0){..} if(PROGRESO=1){..}...: los cuerpos en orden."""
    pasos: dict[int, list] = {}
    for n in ast:
        if n[0] == "if" and n[1][0] == "bin" and n[1][1] in ("=", "==") and n[1][2] == ("id", "PROGRESO") \
                and n[1][3][0] == "num" and n[3] is None:
            cuerpo = n[2][1] if n[2][0] == "bloque" else [n[2]]
            # El exit de cada paso solo corta ese paso.
            pasos[int(float(n[1][3][1]))] = [c for c in cuerpo if c[0] != "exit"]
        elif n[0] not in ("nada", "var"):
            return None
    return [pasos[k] for k in sorted(pasos)] if pasos else None


def _rellenar_vacios(lineas: list[str]) -> list[str]:
    """Un "si/sino/mientras ...:" sin ninguna orden adentro (solo comentarios) lleva "esperar 0"."""
    out: list[str] = []
    for i, l in enumerate(lineas):
        out.append(l)
        if not l.rstrip().endswith(":") or l.lstrip().startswith("#"):
            continue
        sangria = len(l) - len(l.lstrip("\t"))
        tiene = False
        for sig in lineas[i + 1:]:
            s = len(sig) - len(sig.lstrip("\t"))
            if sig.strip() and not sig.lstrip().startswith("#"):
                tiene = s > sangria
                break
        if not tiene:
            out.append("\t" * (sangria + 1) + "esperar 0")
    return out


def _texto_segun_sexo(e):
    """TextDialog(IfElse(TrainerBoy(), A, B)) → (A, B)."""
    if e[0] == "llamada" and e[1] == "TextDialog" and e[2] and e[2][0][0] == "llamada" and e[2][0][1] == "IfElse":
        a = e[2][0][2]
        if len(a) == 3 and a[0] == ("llamada", "TrainerBoy", []) and a[1][0] == "num" and a[2][0] == "num":
            return a[1], a[2]
    return None


def _es_progreso(n) -> bool:
    return n[0] == "asig" and n[1] == ("id", "PROGRESO")


def _avanza_uno(paso: list) -> bool:
    """El paso termina pasando al siguiente (PROGRESO += 1) sin otros cambios de PROGRESO adentro."""
    progresos = [c for c in paso if _es_progreso(c)]
    anidados = any("PROGRESO" in repr(c) for c in paso if not _es_progreso(c))
    return len(progresos) == 1 and progresos[0][2] == "+=" and progresos[0][3] == ("num", "1") and not anidados


def _termina_en_exit(n) -> bool:
    if n[0] == "exit":
        return True
    return n[0] == "bloque" and bool(n[1]) and n[1][-1][0] == "exit"


def _locales(ast) -> set[str]:
    """Variables del objeto que el script usa como estado: PROGRESO y las asignadas a números."""
    nombres: set[str] = {"PROGRESO"}

    def rec(x):
        if isinstance(x, tuple):
            if x and x[0] == "asig" and x[1][0] == "id" and x[1][1].isupper() and x[3][0] in ("num", "id"):
                nombres.add(x[1][1])
            for y in x:
                rec(y)
        elif isinstance(x, list):
            for y in x:
                rec(y)
    rec(ast)
    return nombres


def _distancia(cond) -> int:
    """if(distance_to_object((14))<N) → N (0 si no es eso)."""
    if cond[0] == "bin" and cond[1] in ("<", "<=") and cond[2][0] == "llamada" and cond[2][1] == "distance_to_object" \
            and cond[2][2] == [("num", "14")] and cond[3][0] == "num":
        return int(float(cond[3][1]))
    return 0


def traducir(nombre: str, gml: str, salas: list[str] | None = None, alarma: int = 0) -> tuple[str, int, int]:
    """(texto del .evento, cuántas instrucciones quedaron sin traducir, distancia a la que se lanza solo
    o 0)."""
    ast = gv.Parser(gv.tokenizar(gml)).programa()
    t = Traductor(nombre, salas)
    t.alarma = alarma
    t.locales = _locales(ast)
    # if(PROGRESO=0){ if(distance_to_object((14))<N){...} }: el original lo lanza al acercarse.
    for n in ast:
        if n[0] == "if" and _gml(n[1]) == "PROGRESO=0":
            cuerpo = n[2][1] if n[2][0] == "bloque" else [n[2]]
            if cuerpo and cuerpo[0][0] == "if" and _distancia(cuerpo[0][1]):
                t.automatico = _distancia(cuerpo[0][1])
                cuerpo[0:1] = cuerpo[0][2][1] if cuerpo[0][2][0] == "bloque" else [cuerpo[0][2]]
            break
    pasos = _pasos(ast)
    if pasos is not None and all(_avanza_uno(p) for p in pasos[:-1]):
        # Máquina de estados limpia: los pasos uno detrás de otro (lo que el original hace con alarmas).
        t.lineal = True
        for paso in pasos:
            t.bloque([c for c in paso if not _es_progreso(c)], 0)
    elif f"alarm[{alarma}]" in gml:
        # Mientras el script deje una alarma puesta, el original lo vuelve a correr.
        t._emitir(0, "bandera _sigue = 1")
        t._emitir(0, "mientras _sigue == 1:")
        t._emitir(1, "bandera _sigue = 0")
        t.bloque(ast, 1)
    else:
        t.bloque(ast, 0)
    texto = "\n".join(_rellenar_vacios(t.lineas))
    # Un "fin" al final no hace falta.
    texto = re.sub(r"\nfin\s*$", "", texto)
    return texto + "\n", t.sin_traducir, t.automatico
