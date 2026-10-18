# tools/extraer.py

Saca assets y datos del juego original y los convierte a formatos de Godot para `nativo/`.
Lo que genera es material del juego original: va a `assets/extraido/` y `data/extraido/`, que
están en `.gitignore`. Solo se versionan el script y este README.

## Requisitos
- Python 3.10 o más nuevo (solo la biblioteca estándar).
- `gamedata/` y `extracted/` en la raíz del repo, generados con el pipeline del README principal
  (pasos 2 y 3). Se pueden indicar otras rutas con `--juego` y `--extraido`.

## Uso
```sh
cd nativo
python3 tools/extraer.py                  # por defecto: datos + sprites de batalla 1-151 + 3 fondos de batalla
python3 tools/extraer.py --musica --gritos           # agrega categorías
python3 tools/extraer.py --mapas --mapas-lista PuebloAlba,Home_2
python3 tools/extraer.py --solo datos                # solo esa categoría (las demás no se tocan)
python3 tools/extraer.py --pokemon 1-151,2001-2010   # rango de sprites de batalla
python3 tools/extraer.py --todo                      # todo (~1.3 GB; los 717 mapas si no hay --mapas-lista)
python3 tools/extraer.py --limpiar                   # borra assets/extraido y data/extraido
```
Después abre `nativo/` en el editor para que importe lo nuevo, o corre
`../tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --import`.

**Es repetible:** cada categoría que corres queda exactamente como debe: solo escribe lo que
cambió, borra lo que sobra (con su `.import`) y conserva los `.import` de lo demás, así que Godot no
reimporta lo que no cambió. Correrlo dos veces seguidas no cambia nada. Las categorías que no pides
no se tocan (por ejemplo, `--solo datos` deja la música como estaba). No edites lo extraído: se
sobrescribe en la siguiente corrida.

## Categorías
| Categoría | Flag | Origen | Salida |
|---|---|---|---|
| datos | (por defecto) | `extracted/scripts/*.gml` (tablas) + `extracted/text/es/` | `data/extraido/moves/NNNN_nombre.tres` (MoveData), `data/extraido/pokemon/NNNN_nombre.tres` (PokemonData) |
| sprites | (por defecto) `--pokemon` | `extracted/pkmnbattle/` | `assets/extraido/sprites/pokemon/NNNN/*.png` + `sprite_frames.tres` |
| fondos | (por defecto) `--fondos-todos` | `gamedata/data/battleback/` | `assets/extraido/sprites/battlebacks/{realistic,traditional}/` (sin el flag: solo los 3 primeros realistas) |
| tilesets | `--tilesets` | `gamedata/_internal/backgrounds/` | `assets/extraido/sprites/tilesets/*.png` + un `TileSet` `.tres` de 16×16 por imagen |
| musica | `--musica` | `gamedata/data/audio/musica/{pk,re}/*.ogg`, `Music_Intro_*.mp3` | `assets/extraido/audio/music/` |
| gritos | `--gritos` | `gamedata/data/audio/grito/*.wav` | `assets/extraido/audio/sfx/gritos/` |
| entrenadores | `--entrenadores` | `gamedata/data/trainer/*.png` | `assets/extraido/sprites/trainers/` |
| mapas | `--mapas` `--mapas-lista` | `extracted/rooms/*.json` | `assets/extraido/mapas/nombre.tscn` (también extrae los tilesets) |

`NNNN` es el `id_original` del juego con 4 dígitos. Los nombres de archivo pasan a snake_case
(`Nidoran♀` → `0029_nidoran_hembra.tres`, `PuebloAlba` → `pueblo_alba.tscn`).

## Datos
- **Movimientos**: todos los de `txt_attack.txt` (866). `poder` = `TheoricBaseAttack`,
  `costo_energia` = `TheoricPPAtack`, `tipo` = `TheoricTypeAttack`, `categoria` = `ModeAtack`
  (0 físico, 1 especial, 2 estado). Cooldown, bloqueo y proyectil quedan con el valor por defecto
  de `MoveData`, que es el global del original.
- **Especies**: ids 1-1000 y 2001-2425 que tengan stats y nombre (1395). No se extraen los shiny
  (id + 1000) ni las formas/megas (ids > 100000). `numero_pokedex` = `GetOrdenDex`, `crecimiento` =
  `GetCrecimiento`. `movimientos_aprendibles` (`MovimientoAprendible`: movimiento, nivel y método):
  primero los de `Ataque_Nivel` ordenados por nivel, luego MT (`Ataque_MT` + `MTAtack`, en orden de
  MT), tutor (`Ataque_Tutor`) y DT (`Ataque_DT`; hay 25 DT al revés: los aprenden todos menos la
  lista). Mew (151) y la especie 500 aprenden cualquier MT/tutor/DT; Smeargle (235) ninguno. Las
  excepciones por forma (`TieneAprendizajeEspecifico`) no se aplican. `sprite` es el primer frame del sprite de batalla mirando abajo (`2.png`),
  solo si ese Pokémon tiene sprites extraídos.
- **Tipos**: el juego numera los tipos en otro orden; el script los traduce a `Tipos.Tipo`
  (tabla `TIPO_JUEGO_A_ENUM`). El tipo 19 del juego ("???") no existe en `Tipos`: el único movimiento
  con ese tipo queda como NORMAL, y las especies 500 y 2249 (tipo aleatorio en batalla, "???" fuera)
  quedan sin tipos.
- Las tablas del original son cadenas de `if(argument0=N)return(X);`. El script las lee sin ejecutar
  código; las condiciones que dependen del estado del juego (forma de Burmy, `IsBattle`...) se
  ignoran y se avisa por pantalla.

## Sprites de batalla
Cada Pokémon tiene un `sprite_frames.tres` (para un `AnimatedSprite2D`) y las tiras PNG originales
(`2.png`, `3.png`, `a.png`, `2_alt.png`...): los frames son regiones de esas tiras, no se duplican
imágenes. Las direcciones usan la notación del teclado numérico del original:
```
7 8 9
4 · 6      2 = abajo, 8 = arriba, 6 = derecha, 3 = abajo-derecha, 9 = arriba-derecha
1 2 3
```
Nombres de las animaciones:

| Animación | Origen | Frames | Velocidad |
|---|---|---|---|
| `mover_2`, `mover_3`, `mover_6`, `mover_8`, `mover_9` | `P{id}_{dir}` | 1-5 | `GetImageSpeed`: 4+ frames 9 fps, 3 → 6, 2 → 4.5, 1 → 3; en bucle |
| `mover_1`, `mover_4`, `mover_7` | solo si el Pokémon tiene dibujo propio (448 de ~3000) | | |
| `ataque_<dir>` | `P{id}_A`: un frame por dirección (8, 9, 6, 3, 2 y, si los tiene, 1, 4, 7) | 1 | estática |
| `herido_<dir>` | `P{id}_H`, igual que ataque | 1 | estática |
| `dormido` | `P{id}_S` | 2 | 1.5 fps, en bucle |
| `<cualquiera>_alt` | `P{id}_*_ALT`: pose alternativa (volando/en suelo o en reposo) | | |

**Volteo:** si no existe `mover_1`/`4`/`7` (ni `ataque_1`...), usa la de `3`/`6`/`9` con `flip_h = true`.
Si no existe `dormido`, el original usa `herido` (`sprS = sprH`).

**Origen:** todos los frames de un Pokémon comparten el mismo lienzo y el origen del sprite original
queda en el centro, así que con `centered = true` (lo normal) el punto de apoyo está en la posición
del nodo, y `flip_h` lo refleja sobre ese mismo punto, como en el original.

Se ignoran sufijos raros que aparecen en muy pocos Pokémon (`A2`, `B`, `C`, `H (2)`).

## Audio
- Música: se copian los `.ogg` ya renderizados desde MIDI por el pipeline del port (`midi2ogg`).
- Gritos: Godot solo importa WAV PCM bien formados. El script arregla al vuelo los que no lo son:
  3 son MP3 dentro de un WAV (496, 513, 517: se guarda el MP3 tal cual como `.mp3`) y ~140 tienen un
  chunk de tamaño impar sin byte de relleno (se rearman con `fmt` + `data`; el audio no cambia).

## Mapas
Cada mapa es una escena con:
- `Fondos`: los fondos de la room (`Sprite2D`, repetidos si el original los repite).
- `Tiles/profundidad_N`: de atrás hacia adelante (en GM mayor depth = más al fondo). Dentro, un
  `TileMapLayer` por tileset; si hay tiles puestos fuera de la rejilla de 16 (p. ej. en x = 8) van en
  otra capa `<tileset>_desfase_X_Y` desplazada. Los que no caben en ninguna rejilla (escalados,
  teñidos, de tamaño no múltiplo de 16) quedan como `Sprite2D` sueltos (`tile_<id>`).
- `Instancias`: un `Marker2D` por instancia con `metadata/objeto` y, si tiene, `metadata/codigo_creacion`
  (GML, solo como referencia). Edificios, árboles, NPCs y paredes son instancias: no se ven hasta que
  el overworld nativo las convierta en nodos.

Las salidas entre mapas, NPCs según la historia y puertas no están en las rooms sino en scripts
(`CambiosWorldRooms`, `CreateNPC*`, `CreateDoors`): ver `docs/referencia_original.md`.
