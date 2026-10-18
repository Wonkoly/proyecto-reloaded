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

### Ataques (`CreateAttack`)
- 4 teclas de ataque (una por movimiento). Al pulsar, si `canshoot` y la energía alcanza
  (`PossibleAttack`: energía ≥ costo, **o la barra está llena** aunque el costo sea mayor; entonces
  la energía queda negativa):
  - gasta `costo_energia` (`PPAtack`),
  - **cooldown 0.5 s** sin poder volver a atacar (`alarm[0] = 15`) — global por Pokémon, no por movimiento,
  - **bloqueo 0.1667 s** sin poder moverse (`alarm[1] = 5`), y se detiene,
  - pone el sprite de ataque mirando hacia `mira` y crea el proyectil.
- Proyectil: **360 px/s** (12 px/step) en la dirección del atacante; desaparece a los **6.667 s**
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
- Los niveles de aprendizaje (`Ataque_Nivel`) se pierden al pasar a `movimientos_aprendibles`;
  MT, tutores y DT (`Ataque_MT`, `Ataque_Tutor`, `Ataque_DT`) no se extraen todavía.
- Las apariciones salvajes (`AparicionSalvajes`) son lógica, no una tabla: falta decidir cómo pasarlas a datos.
- Megas, formas, movimientos Z, clima, estados y habilidades: solo están en el código de batalla.
