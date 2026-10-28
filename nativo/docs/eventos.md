# Eventos: cómo cambiar la historia

La historia del juego son **banderas** (`GameState.historia`: `trainer_2`, `fy_002`, `movil`…) y
**eventos**: archivos `.evento` con lo que pasa al hablar con alguien o cuando un entrenador te ve.
El motor (`autoload/eventos.gd`) solo los ejecuta: para cambiar la historia no hace falta tocar código.

## Dónde están
| Carpeta | Qué es |
|---|---|
| `data/extraido/eventos/<mapa>/<nodo>.evento` | Los que genera `tools/extraer.py` desde el original. **No se editan**: se regeneran. |
| `data/eventos/<mapa>/<nodo>.evento` | **Los tuyos.** Si existe, se usa en lugar del generado. Van en git y el extractor nunca los toca. |
| `data/extraido/entrenadores/NNNN.tres` | Cada entrenador del original (`EntrenadorData`): nombre, sprite y equipo. |
| `data/entrenadores/NNNN.tres` | Los entrenadores que edites (se usan en lugar del extraído). Se abren en el inspector de Godot. |

`<mapa>` es el nombre del mapa en minúsculas con guiones bajos (`ruta_1`, `pueblo_alba`) y `<nodo>` el
nombre del NPC en la escena del mapa (`obj_Entrenador_s3`, `obj_Talk_s6`: se ve en el árbol de la
escena `assets/extraido/mapas/<mapa>.tscn`).

**Para cambiar algo:** copia el `.evento` generado (o crea uno nuevo con el nombre de cualquier NPC) a
`data/eventos/<mapa>/` y edítalo. Cualquier NPC con evento lo corre al hablarle, en lugar de su texto.

## El formato
Una orden por línea. `#` empieza un comentario (salvo entre comillas). Los bloques de `si` van con
sangría (espacios o tabs).

```
# data/eventos/ruta_1/obj_Entrenador_s3.evento
decir 222                      # línea 222 de txt_dialog (el texto del juego original)
decir "¡Ahora digo otra cosa!"  # o un texto propio
combate 2                      # contra el entrenador 2; después, "gano" dice si ganaste
si gano:
    bandera trainer_2 = 1      # vencido: el mapa lo cambia por el NPC de después del combate
    dinero + 120
sino:
    decir "Vuelve cuando estés listo."
```

### Órdenes
| Orden | Qué hace |
|---|---|
| `decir N [par1 par2…]` | Habla el NPC del evento (con su nombre y retrato): la línea N de `txt_dialog`, con `$par1$`, `$par2$`… |
| `decir "texto"` | Lo mismo con un texto propio. `$prota$` es el nombre del jugador, `$rival$` el del rival, `@` separa cuadros y "Nombre: texto" pone otro nombre. |
| `narrar N` / `narrar "texto"` | Cuadro sin nombre ni retrato. |
| `exclamacion` | "!" sobre el NPC. |
| `mirar_jugador` / `jugador_mira_npc` | Uno mira al otro. |
| `combate N [M…]` | Combate contra el entrenador N (`data/.../entrenadores/NNNN.tres`); con más números, contra varios a la vez (dobles: sus equipos se intercalan). Deja `gano` en 1 o 0. Al perder vas al último Centro Pokémon y el evento termina. |
| `hablante N ["Nombre"]` / `hablante "Nombre"` / `hablante npc` | Quién habla en los `decir` que siguen: un sprINDEX (su retrato y nombre), un nombre suelto, o de nuevo el NPC del evento. |
| `exclamacion_de N` | "!" sobre el entrenador N del mapa (el compañero de un doble). |
| `curar_centro` | La curación de la enfermera: cura al equipo con la animación de la máquina. |
| `ir_al_centro` | Lleva al jugador al último Centro Pokémon (y termina el evento). |
| `frame N` | Cuadro fijo del sprite del NPC (`frame -1`: el normal). |
| `sonido nombre` | Un sonido de `assets/extraido/audio/sfx/ui/` (`snd_curar`, `snd_get`…). |
| `bandera nombre = valor` | Cambia una bandera (también `+=` y `-=`; el valor puede ser una cuenta con otras banderas). Los mapas se actualizan al momento. |
| `dinero + N` / `dinero - N` / `dinero = N` | Dinero del jugador. |
| `curar` | Cura al equipo. |
| `dar_pokemon especie nivel` | Agrega un Pokémon al equipo (si hay lugar). |
| `esperar segundos` | Pausa. |
| `empujar dirección pasos` | Mueve al jugador (`izquierda`, `derecha`, `arriba`, `abajo`; 4 px por paso). |
| `ir_a Mapa x y [mira]` | Lleva al jugador a otro mapa (`ir_a PuebloAlba 417 199 2`). |
| `fin` | Termina el evento. |

### Condiciones (`si … :`, `sino si … :`, `sino:`)
- Banderas por su nombre: `trainer_2 == 0`, `movil == 1`, `MEDALLA_STAR_1 >= 1`. Una bandera que nunca
  se puso vale 0. `trainer[2]` es lo mismo que `trainer_2`.
- `y`, `o`, `no`, paréntesis y números: `si (fy_002 == 1 y no movil) o trainer_2 == 1:`
- `gano`: si ganaste el último `combate`.
- `pregunta "¿Texto?"`: pregunta Sí/No (`si pregunta "¿Quieres pelear?":`).

### Errores
Si un evento tiene un error de formato no se ejecuta y la consola de Godot dice el archivo y la línea
(`ruta_1/obj_Talk_s6.evento:3: el bloque está vacío`). Las pruebas
`res://tests/prueba_eventos.tscn` comprueban el motor y que todos los generados se leen bien.

## Lo que hace solo el juego (no hace falta escribirlo)
- Los entrenadores (`entrenador = N` en el NPC) miran en línea recta hasta su `distancia`; si te ven,
  "!", caminan hasta ti y corren su evento. También al hablarles.
- Lo que aparece o desaparece según las banderas (`metadata/condicion` de cada nodo del mapa), como el
  entrenador y su versión de después del combate.

## Entrenadores (`EntrenadorData`)
`id` (su número, la bandera `trainer_N`), `nombre`, `sprindex` (sprite/retrato), `lider` y `equipo`:
una lista de `MiembroEquipo` con `especie` (o `especie_bandera`: la especie guardada en una bandera),
`nivel` (con `nivel_escala` sube hasta el nivel más alto de tu equipo + `ajuste`, como `setMinMax`),
`objeto`, `movimientos` (vacío = los que aprende por nivel) y `condicion` (solo si se cumple).
