# Encuentros salvajes del original (AparicionSalvajes)

Las tablas se generan con `tools/encuentros_original.py` (categoría `encuentros` de `extraer.py`) en
`data/extraido/encuentros/<mapa>.tres`: **405 mapas, 1387 subtablas**. La `ruta_1.tres` que había hecha a
mano (Pidgey, Rattata, Caterpie: no coincidía con el original) quedó en `data/extraido/ejemplos/`.
Los mapas sin tabla no tienen encuentros; no se inventan tablas.

## Lo que se comprobó al generarlas

- **Bug de HierbasSalvajes**: la lista de rooms del modo hierba tiene `room=(61) || (24) || room=(25)`;
  `(24)` siempre es verdadero, así que el modo 1 vale en **todas** las rooms y su bloque sale con `exit`.
  **El modo 4 (hierba especial) es código muerto**: se genera (`codigo_muerto = true`, 10 subtablas)
  pero el juego no lo usa.
- **Cuándo se tira el dado**: `ExplorerSalvajes` (step del objeto EXPLORER) en cada step en que el
  jugador se movió (`moving`: la posición cambió desde el step anterior), 30 por segundo, con
  probabilidad 1/frecuencia (`FrequencySalvajes`: `ceil(random(F)) = F`). En nativo se replica por
  tiempo en movimiento (no por distancia): correr o ir en bici cambian la tasa por píxel como en el
  original.
- **Nivel**: `NV = base + ceil(random(k))`. `random(k)` devuelve [0, k): `ceil` da 1..k, así que
  `nivel_min = base + 1` y `nivel_max = base + k`. Solo si `random` devolviera 0 exacto saldría `base`
  (probabilidad ~0; se ignora). Si `NV <= 0` el original no da encuentro (`if(Pokemon<=0 || NV<=0){}`).
- **Unown y fósiles**: cada especie ocupa un hueco de tamaño fijo (Unown 38, salvo 627/628 con 6;
  fósiles 100) y una bandera apagada deja su hueco vacío (no sale nada). Comprobado con gml_eval en las
  16 combinaciones de Unown y 48 de fósiles: el peso no cambia según las demás banderas → condición por
  especie. Las tablas con hasta 3 condiciones de la historia (contando una vez la misma comparación
  escrita en varios sitios) se generan como una subtabla por combinación.
- **39 tablas no se usan en el original**: hay tabla, pero HierbasSalvajes no activa ese modo en la
  room (p. ej. surf en Ruta_2_2). No se generan.
- **Unown 601–628** están en las tablas pero no en `data/extraido/pokemon` (no los trae la extracción
  de datos): mientras falten, ese sorteo no da encuentro.
- **La hora exacta** (`(66).Hora = 19` en CuevaRemolino) se toma como 12 de día y 22 de noche: el caso
  de las 19:00 se pierde.

## Cómo es en el original

`AparicionSalvajes(Lugar, ModoAparicion, Valor, Dia, RespuestaRequerida)`: 260 KB de `if`.

- `Valor` es un número de 1 a 1000 que se tira por encuentro. Cada especie ocupa un tramo
  (`Valor<=850 && Valor>700`), así que su probabilidad es el largo del tramo / 1000.
- `Dia` es `global.day`. Muchos tramos son `IfElse(Dia, especie_de_día, especie_de_noche)`.
- `RespuestaRequerida`: 1 = especie, 2 = nivel, 3 = raro y 4 = súper raro. Los dos últimos solo con
  la Colonia (`(18).colonia_time`).
- El nivel es `base + ceil(random(k))`, a veces con `NV+=2` por especie o vuelto a tirar.

Los modos y quién los llama (`HierbasSalvajes`, `Pescando`, `ControlSafariHierbas`):

| Modo | Terreno (`global.hierba`, `ProtaCheckHierba`) | Bloques | Lugares |
|---:|---|---:|---:|
| 1 | hierba (`obj_hierba`) y cuevas o zonas sin hierba (`ActivacionSalvajes`) | 137 | 306 |
| 2 | surfeando | 68 | 199 |
| 3 | barro (`obj_barro`) | 1 | 6 |
| 4 | hierba en 10 rooms especiales (233, 235, 237, 254…) | 9 | 30 |
| 5 / 6 / 7 | pesca con caña vieja / buena / súper (objetos 181 / 182 / 183) | 67 c/u | ~208 |
| 8 | hierba invisible (`obj_hierbaInvisible`) | 13 | 23 |
| 9 | surf sobre lava (`obj_lava`) | 9 | 17 |

La frecuencia (1/150, 1/250, 1/300 por paso) y las hordas no están en esta función: están en
`HierbasSalvajes` (`FrequencySalvajes`, `FREC_HORDAS`, `HordaComplementario`).

## ¿Se pueden generar con gml_eval?

**Sí.** Lo probé con un prototipo (no versionado) sobre `tools/gml_eval.py`. Para cada modo y room
busca los bloques que aplican y los evalúa con Valor 1..1000, de día y de noche. Supone una partida
nueva: banderas en 0, `instance_exists` falso, `random` al mínimo y al máximo para sacar el rango de
nivel, y `choose` con la primera opción. Tarda unos 2,5 min para todo.

- **1176 tablas en 394 mapas.** La hierba de día (modo 1) da **294 mapas**. Solo hierba de día ya es
  ~25 veces lo que hay hoy.
- Por modo: hierba 294, surf 195, pesca 205 por caña, hierba especial 30, hierba invisible 22, lava 14
  y barro 6.
- Ruta_1 de día: 638 (20 %), 631, 161, 16 y 19 (15 % c/u) y 754, 2293, 910 y 2078 (5 % c/u), nivel 2–4.
  De noche, 161 → 163 y 16 → 21. PuebloAlba comparte esa tabla (`Lugar=(0) || Lugar=(11)`).
- Cruce con los mapas nativos: 167 tienen hierba. 21 de ellos no tienen tabla de hierba, casi todos
  mapas de buceo (`*_Buceo`) y algunas rutas (Ruta_26, Ruta_42, CiudadNaos, PlayaBrujula…). Hay que
  revisarlos. 148 mapas tienen tabla del modo 1 sin hierba: son cuevas y zonas de `ActivacionSalvajes`,
  donde aparecen salvajes en cualquier sitio.

Para hacerlo de verdad, a gml_eval le faltan `for` y los arrays (`salvaje_pk[i]`). Hoy dejan sin
evaluar 11 tablas: las ruinas Unown (room 201, según los puzles resueltos) y las salas de fósiles
(288/289, según `repuebla_fosil`).

## Qué depende de cosas que aún no existen

- **Hora**: `Dia = global.day`. 148 de las 1176 tablas cambian de noche; sin ciclo día/noche se usaría
  siempre la de día.
- **Historia**: unas 25 tablas leen banderas: `acceso_celeste` (10 tablas), `dojo_lee`,
  `invasionSeismo`, `LIGA_JOHTO/HOENN`, `ultraCristalino`, `encuentroHole`, `kartana`… Se pueden
  guardar como condición, igual que los NPCs.
- **Instancias y posición**: `instance_exists` (eventos en curso, ~5 tablas) y `X`/`Y` del jugador
  (partes del mapa con otra tabla, p. ej. la room 201 con `Y<1600`).
- **Objetos**: las cañas (modos 5–7), la Colonia (raro y súper raro) y el objeto 347 del Pokémon que
  acompaña (menos hordas).
- **Hordas**: en `HierbasSalvajes`, no en la tabla.
- **Surf y pesca**: los modos 2, 5–7 y 9 no se pueden usar hasta que existan.
- **Otros**: formas al azar (`SelectRandomVivillon/HadaFlor/Alcremie`, según `global.first*`),
  `TrainerBoy`, `SalvajeCapturado(132)` (un Ditto que solo sale si no lo tienes), y
  `GetIndexIsla` en la room 525.

## Qué se perdería (generando solo modo hierba de día, partida nueva)

- Las especies de noche (en 148 tablas).
- Lo que cambia con la historia (se quedaría en su valor al empezar), salvo que se guarde la condición.
- Las zonas por posición dentro de un mapa y las formas al azar (siempre la primera).
- Raro y súper raro (Colonia), hordas y su especie complementaria.
- Las 11 tablas con `for`, hasta que gml_eval lo soporte.
- 17 tablas no cubren los 1000 valores: en esos tramos no aparece nada. Eso es del original y se
  conserva si la suma de pesos se compara con 1000.

## En el juego

- Zonas de encuentro en los mapas con su método: `ZonaHierba` (obj_hierba), `ZonaHierbaInvisible`
  (obj_hierbaInvisible) y `ZonaBarro` (obj_barro). `Jugador.metodo_actual()` decide como
  ProtaCheckHierba: hierba invisible, hierba (en su posición y 8 px más abajo), barro y, si no, las
  zonas de cueva de la tabla (`sin_hierba`: las 124 rooms con `obj_cueva` y las partes de
  ActivacionSalvajes) con la tabla de hierba.
- La subtabla es la primera que coincide en método, horario (`Reloj.es_de_dia()`), condición y zona.
  El dado se tira por step en movimiento y la especie se sortea de 1 a 1000 (el resto no da nada).
- El salvaje se crea como IniciaSalvaje: IV y ntv al azar, ataques por nivel.
- Comandos dev: `encuentros_mapa` y `simular_encuentros <n>`.

## Pendientes

- Surf, pesca y lava (sus subtablas ya están generadas).
- De IniciaSalvaje: objeto (`ColocaObjeto`), sexo (`PkmnSetSex`), `ISEP` (1-102), shiny (1/800;
  1/400 con el Amuleto Iris, menos con la Colonia y las cadenas de capturas), Intimidación (+nivel) y
  Vista Lince (otro objeto).
- Repelente, Flauta, habilidades que cambian la frecuencia (FrequencySalvajes: REPELEDOR/ATRACTOR),
  hordas y la Colonia (raros y súper raros).
- Los climas NIEBLA y TOR_ARENA, que también activan salvajes sin hierba (ActivacionSalvajes).
- Unown 601-628: sin datos de especie propios (son formas de Unown 201).
- Los sprites de batalla de las especies fuera de 1-151 no se extraen por defecto (`--pokemon`).

## Diseño (implementado)


Una tabla por mapa con varias subtablas, cada una con método, momento, condición y zona:

```gdscript
class_name TablaEncuentros   # data/extraido/encuentros/<mapa>.tres (generado)
@export var subtablas: Array[SubtablaEncuentros]

class_name SubtablaEncuentros
enum Metodo { HIERBA, HIERBA_ESPECIAL, HIERBA_INVISIBLE, BARRO, SURF, LAVA, CANA_VIEJA, CANA_BUENA, SUPERCANA }
enum Momento { SIEMPRE, DIA, NOCHE }
@export var metodo: Metodo
@export var momento: Momento = Momento.SIEMPRE   # una sola SIEMPRE si día y noche son iguales
@export var condicion: String = ""               # sobre h y lugar, como metadata/condicion
@export var zona: Rect2 = Rect2()                # vacío = todo el mapa (X/Y del original)
@export var frecuencia: int = 150                # FrequencySalvajes de ese método y room
@export var encuentros: Array[EncuentroSalvaje]  # peso = valores de 1..1000 que ocupa
@export var raros: PackedInt32Array              # choose(...) de RARO (Colonia)
@export var super_raros: PackedInt32Array
```

- **Elegir la subtabla**: el método según dónde está el jugador (hierba, agua, barro, lava, caña en
  uso). Después el momento según la hora (sin reloj, `DIA`), la condición con `GameState` y la zona.
- **Elegir la especie**: un número de 1 a 1000 como el original. Si cae fuera de los pesos (suma <
  1000), no aparece nada. El nivel sale de `nivel_min..nivel_max` de cada `EncuentroSalvaje`, que ya
  existe.
- **Las cuevas**: el método HIERBA sin zona de hierba se activa en toda la room o en las zonas de
  `ActivacionSalvajes`. Hace falta otro tipo de zona en el mapa.
- **Extracción**: una categoría `encuentros` en `extraer.py` que use gml_eval como el prototipo.
  Primero solo HIERBA + DIA y el resto cuando existan hora, surf y pesca.
