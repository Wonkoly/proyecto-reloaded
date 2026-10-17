# Proyecto Reloaded → Godot

Objetivo: portar *Proyecto Reloaded The Last Beta 1.9.2.2* (Game Maker 8, solo Windows) a **Godot 4**,
para que corra nativo en Linux, Windows, Mac (y potencialmente Android/web).

Fases:
1. **Extracción** — sacar todo el código, mapas y assets del `.exe` a formatos legibles. ✅
2. **Port 1:1** — el juego completo en Godot, con lógica y mecánicas 100% iguales al original.
3. **Multijugador online** — una vez que el port sea fiel.

## Estructura
| Carpeta | Qué es |
|---|---|
| `original/` | El juego tal cual vino. **Solo lectura**, es la referencia. |
| `*.zip` | Zip original de respaldo. |
| `tools/Godot_v4.7.2-stable_linux.x86_64` | Godot 4.7.2 oficial (hash verificado contra el release). |
| `tools/OpenGMK/` | Repo de OpenGMK (decompilador GM8). Se compila con `cmake` de `tools/.venv`. |
| `tools/gm8dump/` | Extractor propio (Rust): `.exe` → GML/JSON/PNG/audio. |
| `tools/resolve_ex.py` | Desofusca las llamadas `ex(<id>, …)` → `NombreScript(…)`. |
| `tools/decode_text.py` | Descifra `data/text/**/*.dll` → `.txt` UTF-8. |
| `tools/gmspr2png.py` | Convierte `data/pkmnbattle/*.gmspr` → tiras PNG + `index.json`. |
| `decompiled/` | `.gmk` decompilado (se abre con Game Maker 8.0). |
| `extracted/` | Todo en formato legible (se regenera con los pasos de abajo). |

## Pipeline completo
```sh
# 0. Dependencias externas (no van en git): el juego original en original/, OpenGMK y Godot
git clone --depth 1 https://github.com/OpenGMK/OpenGMK.git tools/OpenGMK
python3 -m venv tools/.venv && tools/.venv/bin/pip install cmake pillow
# Godot 4.7.2 estándar (no Mono) en tools/Godot_v4.7.2-stable_linux.x86_64

# 1. Herramientas
PATH="$PWD/tools/.venv/bin:$PATH" cargo build --release --manifest-path tools/OpenGMK/Cargo.toml -p gm8decompiler
cargo build --release --manifest-path tools/gm8dump/Cargo.toml
cargo build --release --manifest-path tools/gml2gd/Cargo.toml
cargo build --release --manifest-path tools/midi2ogg/Cargo.toml

# 2. Extraer el .exe
EXE="original/Proyecto Reloaded The Last Beta 1.9.2.2 Full.exe"
tools/gm8dump/target/release/gm8dump "$EXE" extracted
python3 -I tools/resolve_ex.py extracted
python3 -I tools/decode_text.py extracted original/data/text extracted/text
python3 -I tools/gmspr2png.py original/data/pkmnbattle extracted/pkmnbattle

# 3. Traducir GML -> GDScript y preparar datos
tools/gml2gd/target/release/gml2gd gen extracted godot
python3 -I tools/gen_gm_stubs.py godot
tools/.venv/bin/python -I tools/prepare_gamedata.py extracted original/data gamedata
# Música: los MIDI se pre-renderizan a OGG con el SoundFont libre GeneralUser GS (~5 min, requiere ffmpeg)
tools/midi2ogg/target/release/midi2ogg tools/soundfont/GeneralUser-GS.sf2 gamedata/data/audio

# 4. Revisar y correr
tools/godot_check.sh
tools/Godot_v4.7.2-stable_linux.x86_64 --path godot
```
Depuración: `GM_SNAPSHOTS="dir:segundos:cantidad"` guarda capturas y cierra;
`GM_INPUT="t:vk,..."` presiona teclas (códigos VK de Windows, p. ej. 90 = Z, 13 = Enter) en el segundo t;
`GM_INPUT_UNTIL=Mapa` descarta las teclas pendientes al llegar a ese mapa;
`GM_DEV_CMDS="t:comando;@Mapa+s:comando"` manda comandos de developer (requiere modo developer).

## Modo developer
```sh
tools/dev.sh        # o: GM_DEV=1 tools/Godot_v4.7.2-stable_linux.x86_64 --path godot
tools/dev.sh 1      # arranca directo en la partida del slot 1 (sin intro)
```
**F1** o **º** abre una consola dentro del juego (`tp`, `guardar`, `curar`, `dinero`, `objeto`, `atravesar`…);
mantener **Tab** = velocidad x4. Lista completa de comandos: [COMANDOS.md](COMANDOS.md).
`GM_ROOT=<carpeta>` usa otra carpeta del juego (para pruebas sin tocar tus partidas).

## Arquitectura del port (`godot/`)
- `gen/` — **generado, no editar**: `scripts/S_*.gd` (5,075 scripts), `objects/O_*.gd` (eventos de 1,991
  objetos), `RoomCode.gd` (código de creación de mapas e instancias), `events.json`.
- `runtime/` — runtime de GM8 escrito a mano, portado de OpenGMK:
  `gm_core` (estado, eventos, mapas, ciclo) → `gm_lib_draw` → `gm_lib_inst` → `gm_lib_data` → `gm_lib_sys`
  → `gm_lib_fx` → `gm` (clase final; `tools/gen_gm_stubs.py` agrega stubs si falta alguna función).
- La lógica corre en **su propio hilo**, como GM8 (que se bloquea con `sleep`/`screen_redraw`); el hilo
  principal (`gm_screen.gd`) dibuja los cuadros con RenderingServer, lee la entrada y reproduce audio.
- Los scripts generados se compilan **bajo demanda** (`G.sc(id)`), y un hilo de baja prioridad precompila
  el resto: compilar todo de una vez le toma a Godot ~85 s.

## Estado
- ✅ Arranca, título, opciones, nueva partida, selección de personaje, ingreso de nombre.
- ✅ Primer mapa (Home_2), guardar con F5 y cargar partida.
- ✅ Música MIDI (pre-renderizada a OGG), partículas y efectos (`part_*`, `effect_*`, port de OpenGMK),
  caminos suaves, `move_bounce_*`, `mp_potential_step_object`.
- ✅ Argumentos de funciones con el tipo de GM8: texto donde se espera número = 0, número donde se espera
  texto = "" (el transpilador usa las firmas de OpenGMK, `tools/gml2gd/gm_builtins.json`).
- ℹ️ El "texto fantasma" en los diálogos es fiel al original: el cuadro de diálogo es 95 % opaco.
- ✅ Batallas: salvajes, captura y contra entrenador, de principio a fin (probadas con la consola dev).
- ✅ Rendimiento: rejilla de colisiones incremental, orden de dibujo en caché, recorte de lo que queda
  fuera de la vista y reloj del juego sincronizado con el refresco (30 fps parejos en mapas normales).
- ⏳ Pendiente: revisar contra el original batallas, eventos de colisión y el resto de mapas;
  `part_type_blend` (mezcla aditiva) se guarda pero se dibuja con mezcla normal; los mapas gigantes
  (IslaAlma, MontePiscis_3: 3–4 mil instancias) van a 18–20 fps por el costo de GDScript.

## Lo que hay dentro del juego
- **5,075 scripts** (~14 MB de GML), **1,991 objetos**, **717 mapas**, 3,857 sprites internos,
  270 tilesets, 62 sonidos, 21 fuentes, 311 constantes.
- Fuera del `.exe` (en `data/`): 26,237 sprites de batalla `.gmspr`, ~6k `.gif`, música `.mid`/`.mp3`, gritos `.wav`.
- **Ofuscación** (ya revertida): llamadas a scripts por número vía `ex(id, …)` (114,010 llamadas);
  textos cifrados por sustitución en archivos `.dll` falsos (scripts `ValuesAdjustment6` + `SpecialChars`).
- El código está todo en una línea por script (minificado); los nombres sí están.
- Muchos "scripts" son en realidad tablas de datos (`if(argument0=N)return(...)`, listas de `PK=…`):
  movesets, MTs/DTs, tutores, entrenadores, apariciones salvajes. Se pueden convertir a datos automáticamente.
- Sin DLLs nativas ni red: el `MULTIPLAYER` que trae es **local** (carga dos partidas guardadas y las enfrenta).
- Sistemas más grandes: batalla (`BATTLE`, `Pokemon1/2`, `Ataque1/2`, `SecEffect*`), mundo (`obj_Prota`,
  `Create{NPC,Doors,Objects,Devices}`, `CambiosWorldRooms`), caja/PC, Pokédex, mochila, minijuegos
  (tragaperras, cartas, fábrica de combate, torneo), guardado (`LoadFileSav`).

## Estrategia del port (fase 2, original)
Reescribir 14 MB de GML a mano no es viable si queremos fidelidad 100%. El plan es:
1. **Runtime GM8 en Godot** (GDScript): instancias, eventos (create/step/alarm/draw/colisión/teclado),
   `depth`, rooms, views, tiles, y las funciones de GML que el juego usa (draw_*, string_*, ds_*, file_*, sound_*…).
2. **Transpilador GML → GDScript** (con el parser de OpenGMK, `gml-parser`) que convierta cada script y
   evento automáticamente, manteniendo los nombres originales.
3. **Importador de assets**: rooms → escenas `.tscn` (TileMap + instancias), sprites → `SpriteFrames`,
   tablas de datos → recursos/JSON.
4. Probar mapa por mapa contra el original y, solo después, limpiar/refactorizar lo que haga falta.
