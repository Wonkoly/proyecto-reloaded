# Hoja de ruta del port nativo

Meta: clon jugable al 100 % del original (Proyecto Reloaded 1.9.2.2); los cambios de mecánica van después.
Orden: primero el ciclo básico (explorar → combatir → crecer → capturar → guardar), luego la historia
mapa por mapa, y al final los modos extra.

## Hecho
- Datos extraídos: especies, movimientos (nivel/MT/tutor/DT), tipos, sprites, mapas (717), tilesets,
  música, gritos, entrenadores, tiendas, objetos, diálogos, conexiones y encuentros.
- Batalla en tiempo real: movimiento, proyectiles, energía, daño, IA, HUD del original, animaciones de
  ataques, entrenadores (simples, dobles, triples), dinero.
- Overworld: jugador, colisiones, salidas, saltos, hierba y encuentros por tabla, reloj día/noche,
  NPCs (hablan, caminan, rutas fijas, cierran el paso), vigilantes, Centro Pokémon.
- Título, intro, guardar/cargar (9 ranuras), consola de desarrollo y códigos del original.
- Eventos de historia como datos (`docs/eventos.md`), mochila y tiendas.

## Ciclo básico (en curso)
| # | Sistema | Original | Estado |
|---|---|---|---|
| 1 | Experiencia, subir de nivel, aprender movimientos | `ExpGana`, `AjusteStatsLevelUp`, `AprendeAtaque` | hecho (falta Repartir Exp. y objetos de exp.) |
| 2 | Evolución por nivel | `CheckEvolution`, `EvolutionConfirmation`, objeto `EVOLUTION` | hecho (364 especies; faltan las especiales) |
| 3 | Captura con Poké Ball (tecla B, proyectil) | `LanzaCosa`, `PokeBallCapturando`, `CapturaPokemon` | hecho (al equipo o al PC; faltan apodo y balls que dependen de estados/pesca) |
| 4 | Huir (tecla E) y mochila en batalla (O) | `KeyActionsBattle` | hecho |
| 5 | Menú de equipo (Espacio) y cambio de Pokémon en batalla (1-6) | `key_menu_pokemon`, `key_bt_pkmn1..6` | hecho con listas (falta la pantalla de ficha del original) |
| 6 | Menú principal (Enter): equipo, mochila, Pokédex, entrenador, guardar, salir | `KeyActionsExplorer` | hecho (faltan Opciones, Áreas, Móvil, Habilidades) |
| 7 | PC de los Centros: cajas (dejar, sacar, liberar) | `PCKeyActions` | hecho con listas (faltan la sala de cajas y el PC de ítems) |
| 8 | Pokédex (F12): vistos/capturados, categoría y descripción | `Dex_*`, `pkdexC` | hecho con listas (falta su pantalla) |
| 9 | Música de mapas y batallas | `Sound_World`, `Sound_Battle` | hecho (594 mapas; faltan variantes por historia, legendarios y villanos) |

## Después
- El entrenador del jugador dentro de la arena (`Trainer1`, se mueve y lo pueden golpear).
- Efectos de movimientos: hechos los de `SecEffect1` que solo dependen del movimiento (445: estados con
  su probabilidad, etapas de stats propias y del rival, retroceso) y los estados en tiempo real
  (`EffectStatuses`: parálisis, quemado, sueño, veneno, congelación, maldición, infección). Faltan:
  efectos de confusión y enamorado, drenaje (`AbsorbeAttack`), ataques múltiples, evasión, iconos de
  estado en el HUD, y todo lo que depende de habilidades, objetos equipados, clima y mega/Z/dinamax.
- MO en el mapa: hechas Corte, Golpe Roca, Fuerza (tecla o Z frente al obstáculo) y Surf (tecla 3),
  con medallas `MEDALLA_STAR_n` y habilidades de campo (`AttackHabExt`), y Vuelo (tecla 2, medalla 4):
  la pantalla del mapa con los lugares visitados (`obj_pantallavuelo`, `data/extraido/vuelo.json`), el
  Pokémon que despega y aterriza, y las horas que pasan. El mapa también se abre con M o desde Usar Item.
  Cascada (Z junto a la cascada surfeando, medalla 8: sin ella la corriente no deja subir) y Buceo
  (tecla 7, medalla 7: `GoDiving` en `data/extraido/buceo.json`). Faltan Destello, Ola Lava,
  Treparrocas, el Pokémon que sale a usar la MO, el sprite de buzo bajo el agua, bici y montura; en Vuelo, elegir entre las llegadas de los lugares que tienen varias (Isla Sol, el Frente) y
  el grito del Pokémon (los gritos no se extraen por defecto).
- Historia completa: eventos de los 517 NPCs con scripts propios, rutas de NPCs por historia.
- Modos: Torre/Fábrica/Palacio/Torneo, guardería y huevos, minijuegos, multijugador local.
