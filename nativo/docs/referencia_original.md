# Referencia del juego original

Cómo funcionan el overworld, la batalla y los datos en *Proyecto Reloaded* (GM8), para usarlo de
referencia en la reescritura nativa. Las rutas `extracted/...` son los scripts y objetos GML
extraídos (ver el README principal); los nombres entre paréntesis son scripts de `extracted/scripts/`.

## Convenciones y unidades
- El original corre a **30 steps por segundo** (`room_speed = 30` en mapas y en `BattleROOM`).
  Todo lo de este documento ya está convertido: **segundos** y **px/s**.
  - Velocidad: `px/step × 30 = px/s`. Tiempo: `steps / 30 = s` (alarma de 15 steps = 0.5 s).
  - `image_speed` (frames por step) `× 30 = fps`.
  - Una probabilidad `p` por step equivale a una tasa de `30·p` eventos por segundo
    (probabilidad por frame en nativo: `1 - (1 - p)^(30·delta)`, o `30·p·delta` si es pequeña).
- Resolución del original: vista de 320×180, tiles de 16 px.
- Direcciones con notación de teclado numérico (`mira`): 2 abajo, 8 arriba, 4 izquierda, 6 derecha,
  1/3/7/9 diagonales.
- `ACTUAL` = posición en el equipo (0-5) del Pokémon en combate. Lado 1 = jugador, lado 2 = rival.

## Batalla

**Es en tiempo real.** Cada Pokémon se mueve libremente por la arena y los ataques son proyectiles
que chocan. Existe un **modo por turnos opcional** (`CombatePorTurnos`, alarma 10 de `BATTLE`), pero
solo se activa con `global.battleTurnos` (ningún script lo pone en `true`; solo se guarda/carga) o en
el piso 34 de la Torre Batalla (`CONTROL_TORRE.PISO = 34`, en `DefineBattle`).

### Objetos y flujo
| Objeto | Rol | Archivos clave |
|---|---|---|
| `BATTLE` (id 17) | controlador: inicio, energía, debilitados, mega/Z, clima, objetos del rival | `objects/BATTLE.gml`, `DefineBattle`, `InitializeBattle`, `KeyActionsBattle`, `BattlePsPpOptimize`, `CheckDebilitados` |
| `Pokemon1` | Pokémon del jugador | `objects/Pokemon1.gml`, `Pokemon1Movimiento`, `Pokemon1CreateAttack`, `Pokemon1Canshoot`, `Pokemon1Canmove` |
| `Pokemon2` | Pokémon rival (IA) | `objects/Pokemon2.gml`, `Pokemon2Movimiento`, `Pokemon2CreateAttack`, `BattleEstrategia` |
| `Ataque1` / `Ataque2` | proyectil de cada lado | `objects/Ataque1.gml`, `CreateAttack`, `DefineAtaque1`, `Ataque1StepAction`, `Ataque1GolpeaPokemon2` |

Cada step de un Pokémon: cargar sprite → efectos de objeto/habilidad → **movimiento** → sprite según
dirección → **crear ataque**. Los alarms manejan el fin del cooldown (`alarm[0]`), el fin del
bloqueo de movimiento (`alarm[1]`), fin de estados, retirada, etc. El daño se aplica en la colisión
del proyectil con el Pokémon rival (`collision_Ataque2` → `Pokemon1CollitionAttack`, y
`Ataque1GolpeaPokemon2`, que es casi todo casos especiales de movimientos y habilidades).

Encaja con el patrón **BattlePokemon + controladores**: `Pokemon1Movimiento` lee el teclado (→
`PlayerController`) y `Pokemon2Movimiento` + `BattleEstrategia` deciden dirección y ataque
(→ `AIController`); el resto (moverse, colisionar, disparar, recibir daño) es común a los dos.

### Movimiento (`Pokemon1Movimiento`, `GetSpeedPokemonPos`, `VELPokemon`)
- 8 direcciones; en diagonal cada eje avanza `vel / √2`.
- Contra paredes (`obj_pared`) se mueve lo que pueda en cada eje; si choca a toda velocidad, avanza
  de a 1 px (30 px/s).
- No se mueve si: está debilitado, `canmove = false` (bloqueo tras atacar), dormido o congelado
  (`STD = 3` o `5`), o tiene fricción (fue empujado).
- **Velocidad en batalla**: `PokemonInstance.calcular_velocidad_batalla()`:
  ```
  v   = fórmula_stat(base_velocidad, nivel' = 23 + 0.35·nivel, iv, ntv)   (ver Stats)
  vel = (3 + 11·v/504) · 30   px/s
  ```
  Luego, por modificadores de batalla: `+7.5 px/s` por cada nivel de Velocidad (`Mod_Vel`, 0.25 px/step),
  estado 1 (`STD = 1`) `÷1.125`, varios efectos y habilidades `×1.25` o `÷1.25`, y en Espacio Raro
  `vel = 330 - vel` (11 px/step - vel). Al final se limita a **[60, 450] px/s** (2-15 px/step).

### Modos de ataque (`ExecuteAtack`)
| Modo | Movimientos | Qué hace |
|---|---|---|
| 1 contacto | 286 (Placaje, Arañazo, puños...) | el Pokémon se lanza con el ataque (`GolpeaAtack`): 15 steps (0.5 s) a su velocidad + 5 px/step (+150 px/s); el ataque es invisible |
| 2 proyectil | 408 (Ascuas, Lanzallamas...) | proyectil a 360 px/s |
| 3 estado | 184 (Danza espada, Rayo solar...) | no viaja ni choca: aplica `SecEffect` y desaparece a los 2 steps |
| 4 especial | 6 (Vuelo, Excavar, Buceo, Bote, Golpe umbrío, Golpe fantasma) | casos propios |

### Ataques (`CreateAttack`)
- 4 teclas de ataque (una por movimiento). Al pulsar, si `canshoot` y la energía alcanza
  (`PossibleAttack`: energía ≥ costo, **o la barra está llena** aunque el costo sea mayor; entonces
  la energía queda negativa):
  - gasta `costo_energia` (`PPAtack`),
  - **cooldown 0.5 s** sin poder volver a atacar (`alarm[0] = 15`) — global por Pokémon, no por movimiento,
  - **bloqueo 0.1667 s** sin poder moverse (`alarm[1] = 5`), y se detiene,
  - pone el sprite de ataque mirando hacia `mira` y crea el proyectil.
- Proyectil: **360 px/s** (12 px/step) **apuntando al rival** (`point_direction` al objetivo, ± `random(prec·10)`° según la precisión); desaparece a los **6.667 s**
  (`alarm[10] = 200`, `AtaqueTimeOut`) si no choca. Con "Yo primero" (`YP`) acelera
  `+45 px/s²` (`speed += YP/20` por step).
- Colisiones del proyectil: Pokémon rival (daño), paredes, ataques del otro lado (se anulan según el
  caso) y "energía" del rival.
- En `MoveData` estos valores son los defaults de `cooldown`, `bloqueo_movimiento`,
  `velocidad_proyectil` y `duracion_proyectil`.

### Daño (`Ataque1GolpeaPokemon2`)
```
daño = ((2·nivel/5 + 2) · MF · AT · poder / DEF / 50 + 2) · stab · eff · 0.85
daño_final = ceil(daño / PowDif)
```
- `AT`/`DEF`: Ataque y Defensa si el movimiento es FISICO; Ataque Esp. y Defensa Esp. si es ESPECIAL
  (`ModeAtack`: 0 físico, 1 especial, 2 estado). Hay variantes que usan otra stat (Defensa o
  Velocidad del atacante, defensa sin modificadores) para movimientos concretos.
- `MF` = 1.5 si el ataque salió de **Yo primero** (movimiento 400, copia el ataque rival más cercano
  y lo potencia: `ChangeAttack` pone `YP = true`); si no, 1.
- `stab` = 1.5 si el tipo del movimiento coincide con uno del atacante (2 con la habilidad 91, Adaptable).
- `eff` = `Efectividad.multiplicador()` (tabla de `Efectivo`; existe el modo inverso en el piso 39
  de la Torre y con `battleInverso`).
- `PowDif` = 1, 2 o 4: divisor que fijan algunos modos (Fábrica, Palacio, Infierno, Torre); 1 en lo normal.
- Después vienen decenas de modificadores por clima, habilidades, objetos y efectos activos
  (`danio *= 1.3`, `÷2`...). Con poder 0 no se calcula daño (movimientos de estado).

### Stats (`PSPokemon`, `ATPokemon`, `DEFPokemon`, `ATSpPokemon`, `DEFSpPokemon`, `ShowStatVel`)
Implementadas en `PokemonInstance.calcular_stats()`. Cada stat usa su dígito de `iv` y de `ntv`
(hp = unidades, ataque = decenas, ..., velocidad = centenas de millar):
```
PS    = floor(10 + nivel/100 · (2·base + (ntv-1)·31/9 + iv·63/9 + 100))   (+20 % por nivel sobre 100)
otras = floor((0.9 + (ntv-1 + iv)/90) · (5 + nivel/100 · (2·base + iv·31/9 + (ntv-1)·63/9)))
```
con `iv` = dígito 0-9 y `ntv` = dígito + 1 (1-10). Base de PS = 1 → PS siempre 1 (Shedinja).
En batalla el PS máximo usa el nivel limitado a 100 (`Limit100`); el bonus de nivel > 100 se
guarda aparte (`XTRA_PS`).

- **iv**: 6 dígitos aleatorios al crear el Pokémon (`random(1000000)`).
- **ntv** ("talento natural", `selue`): 6 dígitos; el original los guarda junto con una suma de
  control anti-trampas (`selue = control·1000000 + ntv`), que en nativo no hace falta. Los objetos lo
  pueden subir ("El talento natural de X ha aumentado"); `999999` = perfecto.

### Energía ("PP")
No hay PP por movimiento: cada Pokémon tiene **una barra de energía** compartida por sus 4 ataques.
- Máximo: `PokemonInstance.calcular_energia_maxima()` (`PPMPokemon`):
  ```
  e = 40 + fórmula_otras(base_energia, nivel, round(Σiv/6), round(Σntv/6))   (+2 % por nivel sobre 100)
  energía_máx = ceil(e)
  ```
  (`round` de GM8 = redondeo bancario).
- Recarga (`BattlePsPpOptimize`, cada step): **+30/s** mientras el Pokémon puede moverse y está
  visible (no durante el bloqueo tras atacar). Habilidad 54: 2 de cada 3 ticks (20/s); objeto 363 y
  habilidad 259: +1 extra con probabilidad 1/10 (+3/s). En modo por turnos siempre está llena.
- Algunos efectos devuelven parte del costo (`+floor(PPAtack/4)` o `/3`).

### IA del rival (`Pokemon2Movimiento`, `BattleEstrategia`)
- Se mueve en línea recta y cambia de dirección al azar: probabilidad 1/50 por step (**0.6 cambios/s**),
  o 1/25 (1.2/s) con Espacio Inverso. Si está quieto y es "crack" (`EsUnCrack`): 1/10 por step
  (3/s), o arranca enseguida si hay un ataque del jugador en pantalla.
- Si es físico y no hay ataques del jugador en pantalla, 1 de cada 3 cambios va directo hacia el jugador.
- Entrenadores maestros (`MASTERTRAINER`): si tienen más energía que el jugador, lo persiguen; a
  menos de 80 px, si son más rápidos, van a la velocidad del jugador menos 30 px/s, y a menos de
  32 px se detienen.
- Elige objetivo con probabilidad 1/5 por step (6 veces/s).
- **Cuándo ataca** (`CreateAttack` con `argument0 = 2`): con probabilidad 1/F por step, F = 15
  quieto (**2 intentos/s**) o 30 en movimiento (1/s); 5 si es maestro con ventaja a menos de 80 px;
  ×2 en Fácil, ÷2 de Difícil para arriba. Al atacar se detiene (`speed = 0`). Los salvajes eligen
  el movimiento al azar; los entrenadores con `BattleEstrategia`. `FISICO` = tiene al menos un
  movimiento físico.
- `BattleEstrategia` elige el ataque al azar con pesos: parte de 25 por movimiento y los ajusta según
  el movimiento y la situación (efectividad, efectos activos...); 0 para los que no puede usar.

### Sprites de batalla
Ver `tools/README.md` (animaciones `mover_<dir>`, `ataque_<dir>`, `herido_<dir>`, `dormido`, `_alt`).
`_alt` se usa cuando el estado de vuelo del Pokémon no es el normal de su especie o cuando está en
reposo sin moverse (`Renew_Battle_Sprite`).

## Overworld

### Jugador (`objects/obj_Prota.gml`)
Cada step: `KeyActionsProta` (menús, interacción) → surf/cascada → saltos, patinar, corrientes →
**`ProtaMovimiento`** → `ProtaSetSprite` → **`ProtaCheckHierba`**. Las alarmas manejan
teletransporte, excavar, vuelo, surf, ola de lava, buceo, cascada, velocidad extrema, pesca,
treparrocas y gran ojo.

**Movimiento libre por píxel, no por casillas** (`ProtaMovimiento`):
| Modo | Normal | Correr | Andar lento | Animación |
|---|---|---|---|---|
| A pie | 90 px/s | 120 px/s | 60 px/s | 6 / 7.5 / 4.5 fps |
| Bicicleta | 180 px/s | 210 px/s | 90 px/s | igual |
| Montura | 330 px/s (120 con la tecla de velocidad extrema, o al revés según opción) | | | estática |

- Tecla "stop": se detiene y redondea la posición a píxeles enteros.
- Colisiona con `obj_pared`. Si queda dentro de agua sin surf, se empuja 1-2 px hacia fuera.
- Arena que desliza (`obj_arenadesliza`): sin bici ni montura lo baja a 120 px/s.
- Barro (`obj_barro`), corrientes de agua, hielo (`ProtaPatina`) y saltos tienen scripts propios.

### Hierba y encuentros (`ProtaCheckHierba`, `EXPLORER` → `ExplorerSalvajes` → `HierbasSalvajes`)
- Pisar `obj_hierba` (con hierba también 8 px más abajo) pone `global.hierba`; también hay cueva,
  barro, agua (surf) y "hierba especial".
- Mientras el jugador **se mueve** sobre hierba, cada step hay un encuentro con probabilidad `1/F`
  (`FrequencySalvajes(F)`). `F` depende del mapa: 100-750 (con F = 150: **30/F = 0.2
  encuentros/s → uno cada ~5 s caminando**). Repelente ×1.5 a F, atractor ÷1.5; hay hordas aparte.
- Qué Pokémon y nivel: `AparicionSalvajes(lugar, modo, valor, día, respuesta)` (259 KB: depende del
  mapa, modo de aparición, hora del día, historia). `IniciaSalvaje` lo crea: `iv = random(1000000)`,
  ataques por nivel (`ColocaAtaques`), objeto y sexo.

### Mapas
- 717 rooms (`extracted/rooms/*.json`): tiles de 16 px de 270 tilesets, fondos e instancias
  (paredes, hierba, NPCs, edificios, árboles). `tools/extraer.py --mapas` los convierte a `.tscn`.
- Lo que no está en las rooms: salidas entre mapas (`CambiosWorldRooms`, 96 KB), NPCs según la
  historia (`CreateNPC*`), puertas (`CreateDoors`), objetos (`CreateObjects`), dispositivos
  (`CreateDevices`).
- Cámara: vista de 320×180 que sigue a `obj_Prota` con bordes de 120×90 px.

## Códigos (`ExecuteCheat`)
Con **F3** (`key_global_code`) se abre un cuadro "Introduce un Cheat..." (13 letras como máximo; se
compara en mayúsculas). En nativo: autoload `Trucos` (F3, o Shift+F3 cuando está la consola dev) y el
comando `codigo <texto>`.

| Código | Qué hace | Nativo |
|---|---|---|
| `GUARDERIA` | Pide macho y hembra (números) y dice qué huevo darían; con uno vacío recorre los 1034 | sí (`Cria.huevo`, port de `EGG`; cría y grupos huevo extraídos con `gml_eval.py`) |
| `TORBELLINOS` / `ENTRENADORES` | Lista los torbellinos sin despejar (1-200) / entrenadores sin vencer (1-1050) | sí (banderas `estorbo_torbellino_N` / `trainer_N` de `GameState.historia`) |
| `ME RINDO` (en batalla) / `INCONSCIENTE` (en el mapa) | Pregunta y te deja debilitado: al último Centro (o a la cama de casa), curado, sin dinero, `ev_1429 += 1` | sí (a la cama de Home_2: no hay Centros todavía) |
| `SELUE<99999 − prota_ID>` | Antitrampas: cuenta Pokémon con la suma de control alterada | sí (siempre 0) |
| `CHEATS` | Cuántos trucos usaste | sí |
| `MOTE` / `APODO` | Cambia el apodo del protagonista | sí |
| `Q` / `CARA` | Personaje 0-9, o 10 = sprite de un entrenador (1-351, `ValorTrainerTrucado`) | sí |
| `QQ` / `VESTUARIO` | Abre el vestuario | no (no hay vestuario) |
| `LOGBATTLE` / `BATTLELOG` | Guarda los mensajes de batalla en `LogBattle.txt` | sí (`user://LogBattle.txt`) |
| `PRISA` | Texto rápido (`vel_text = 2`) | solo el ajuste (no hay diálogos todavía) |
| `TRANSITION` | Transición especial entre mapas | solo el ajuste |
| `CLEANBATTLE` | Oculta el HUD de batalla | sí |
| `LLAMAME` | Te llama un contacto al azar | no (no hay teléfono) |
| `GIGAMAX`, `GIGAMAX1`, `GIGAMAX2` | Efecto gigamax en batalla | no |
| `GUARDIAN` | Un Pokémon guardián en batalla | no |
| `SHINY` | Muestra la contraseña del Mega-Inductor si se cumplen condiciones de la historia | no (las condiciones no se dan) |
| `ABOUT`, `VERSION`, `HELP`, `INFO`, `AYUDA`, `INFORMACION`, `BETA` | Versión del juego ("Pokémon Reloaded Last Beta 1.9.2.1") | sí |
| `MIERDA`, `JODER`, `VIOLENCIA`, `DIOS`, `PAZ`, `JUSTICIA`, `VERDAD`, `FUCK`, `GOD`, `PEACE` | Los 10 consejos de Fer | sí |

## Datos

### Experiencia (`CrecimientoPokemon`, `GetCrecimiento`, `ExpBase`)
Experiencia total para llegar al nivel `n` (nivel 1 = 1), según `PokemonData.crecimiento`:
| Curva | Fórmula |
|---|---|
| MEDIO | n³ |
| RAPIDO | 0.8·n³ |
| LENTO | 1.25·n³ |
| PARABOLICO | 1.2·n³ − 15·n² + 100·n − 140 |
| ERRATICO | n ≤ 50: n³·(100−n)/50; ≤ 68: n³·(150−n)/100; ≤ 98: n³·(1.274 − n/150 − a) con a = 0, 0.008, 0.014 según n mod 3 = 0, 1, 2; si no: n³·(160−n)/100 |
| FLUCTUANTE | n ≤ 15: n³·(24 + (n+1)/3)/50; ≤ 35: n³·(14+n)/50; si no: n³·(32 + n/2)/50 |

Resultado redondeado (`round`, bancario). `exp_base` es la base de experiencia que da al ser
derrotado: en batalla `ExpGana` da `floor(nivel_rival · exp_base · 1.5 / 7)`.

### Tipos
Ids del juego → `Tipos.Tipo`: 1 Normal, 2 Fuego, 3 Agua, 4 Planta, 5 Eléctrico, 6 Roca, 7 Lucha,
8 Tierra, 9 Psíquico, 10 Veneno, 11 Bicho, 12 Hielo, 13 Siniestro, 14 Acero, 15 Volador,
16 Fantasma, 17 Dragón, 18 Hada (19 = "???", hace ×2 a todo y recibe ×2). Tabla de efectividad en
`scripts/resources/efectividad.gd`.

### Ids de especies
1-1000 especies base, 1001-2000 sus shiny (id + 1000), 2001-2425 especies nuevas del juego,
3001-4000 sus shiny, > 100000 / 150000 / 200000 formas y megas (`NumeroPokemonEspecial`).
`numero_pokedex` sale de `GetOrdenDex` (los ids internos no siguen la Pokédex nacional a partir del 494).

## Pendiente de revisar
- **Overworld nativo**: los encuentros usan `TablaEncuentros` (`data/encuentros/<mapa>.tres`, a
  mano) en lugar de `AparicionSalvajes`; la probabilidad de `FrequencySalvajes` se aplica por
  distancia (paso de referencia 3 px). Falta: hordas, repelente/atractor, hierba especial, surf,
  bici, saltos, hablar con NPCs y sus diálogos, elección de personaje (siempre Ash), curar al
  equipo (si todos están debilitados no hay encuentros) y guardar/cargar partida.
- **Mapas nativos** (`tools/mapas_original.py`): los 717 se extraen (`--mapas todos`). Instancias que
  todavía quedan como `Marker2D` (7468 de 125 tipos; las más frecuentes):

  | Veces | Objeto | Mapas |
  |---|---|---|
  | 5246 | `obj_patina` | 16 |
  | 759 | `obj_puente3D_ABAJO` | 30 |
  | 510 | `obj_puente3D_ARRIBA` | 30 |
  | 276 | `obj_TopeRocaInverso` | 3 |
  | 124 | `obj_cueva` | 124 |
  | 48 | `obj_GIGA_NONE` | 1 |
  | 47 | `NIEBLA_P` | 15 |
  | 39 | `obj_superficie` | 15 |
  | 35 | `obj_arenadesliza` | 6 |
  | 32 | `obj_CloseDoor7` | 8 |
  | 32 | `obj_CloseDoor1` | 8 |
  | 30 | `obj_base` | 30 |
  | 24 | `obj_CloseDoor9` | 8 |
  | 24 | `obj_CloseDoor5` | 8 |
  | 24 | `obj_CloseDoor3` | 8 |
  | 23 | `obj_tenderoSecreta` | 9 |
  | 15 | `BUCEO` | 15 |
  | 11 | `REFLEJO` | 11 |
  | 11 | `obj_CAMARA` | 11 |
  | 8 | `obj_CloseDoor0` | 8 |
  | 7 | `obj_curator` | 7 |
  | 7 | `HUMEJOS` | 7 |
  | 5 | `obj_PERRO_huye` | 1 |
  | 5 | `obj_PantallaRecord` | 1 |
  | 4 | `obj_MeteoritoLuna` | 1 |

  `obj_patina` es el hielo (se resbala), `obj_puente3D_*` los puentes que se cruzan por arriba y por
  abajo, `obj_cueva` la oscuridad de las cuevas, `obj_CloseDoorN` puertas que se cierran. Tampoco se
  convierten las sombras de los edificios (`obj_shadowFixed`), el movimiento de los NPCs (`MOVE`), la
  dirección de `obj_out_special` (`arriba`/`abajo`, una sola instancia la usa), la espera de 2 s de
  `obj_TelePort`, Surf/MO (el agua y los obstáculos solo bloquean) y las instancias giradas. `EXPLORER`
  (encuentros) no es un nodo: lo hace el jugador. Las barreras que dependen de cosas que no son
  banderas de la historia (`global.capturados`, objetos, hora) quedan como en una partida nueva.
- **Batalla nativa (`scenes/battle/`)**: solo daño genérico. Faltan los casos especiales de
  `Ataque1GolpeaPokemon2` (movimientos con efectos propios, contacto, absorber, multigolpe...),
  `ExecuteAtack` (ataques que no son proyectil), estados (`STD`), cambios de stats (`Mod_*`), clima,
  habilidades, objetos, mega/Z, "Yo primero" (MF), precisión (desvío del disparo), críticos,
  rebote en paredes de 9 movimientos, proyectiles de poder 400 (`Ataque1CollitionAt2`), empuje al
  recibir un golpe (`friction`), sombras, máscaras de colisión por especie (`DefineMaskPokemon`),
  animación en reposo de voladores/levitantes, y cuánto dura la pose de herido (ahora 0.2 s).
- **Animaciones de ataques**: `tools/gml_visual.py` traduce la parte visual de `EfectoEspecial`,
  `EffectAtackCreate` y `EffectAtack` (~94 % de sus instrucciones; se omiten las que tocan lógica de
  batalla) y `AtaqueVisual`/`ParticulasGM`/`EfectoSprite` las ejecutan como GM8. Falta: la lógica
  previa a los bloques de `EffectAtack` (ataques perseguidores y rápidos que aceleran), mezcla
  aditiva (`part_type_blend`), partículas de sprite animadas, el modo ESTADO no aplica su efecto
  (`SecEffect*`, p. ej. Rayo solar carga y dispara) y el modo ESPECIAL (Vuelo, Excavar...) se trata
  como contacto.
- **IA nativa (`AIController`)**: se mueve en 8 direcciones (el original en cualquier ángulo); al
  chocar con una pared elige otra dirección (el original no rebota); el maestro no ajusta su
  velocidad a la del jugador; `BattleEstrategia` solo usa el peso base y la efectividad (faltan las
  reglas por movimiento); no hay desobediencia, "acoso", Espacio Inverso ni varios rivales.
- **HUD nativo (`scenes/ui/battle_hud.tscn`)**: dibuja lo mismo que `DrawEventBattle1` (paneles,
  barras, tipos, caja del equipo, símbolos de ataques, lista con Shift) y el panel de mensajes
  (`obj_panel_informativo`). Falta: Ball asignada y su cantidad (centro), objeto equipado, sexo
  (`PkmnSetSexValor`), estados, barra de experiencia real, límites de cambios/objetos, modificadores
  de stats y tiempo de combate, golpes críticos y el resto de mensajes de batalla.
- Los movimientos iniciales de un Pokémon (`ColocaAtaques`) están en
  `PokemonInstance.asignar_movimientos_por_nivel()`; si la especie no aprende nada por nivel, el
  original pone el movimiento 167 (falta).
- Las apariciones salvajes (`AparicionSalvajes`) son lógica, no una tabla: falta decidir cómo pasarlas a datos.
- Megas, formas, movimientos Z, clima, estados y habilidades: solo están en el código de batalla.
