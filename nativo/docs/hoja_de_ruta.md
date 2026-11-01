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
| 1 | Experiencia, subir de nivel, aprender movimientos | `ExpGana`, `AjusteStatsLevelUp`, `AprendeAtaque` | hecho (con Repartir Exp., Amuleto Exp., Huevo Suerte) |
| 2 | Evolución por nivel | `CheckEvolution`, `EvolutionConfirmation`, objeto `EVOLUTION` | hecho (364 especies; faltan las especiales) |
| 3 | Captura con Poké Ball (tecla B, proyectil) | `LanzaCosa`, `PokeBallCapturando`, `CapturaPokemon` | hecho (al equipo o al PC, con apodo; faltan balls que dependen de estados/pesca) |
| 4 | Huir (tecla E) y mochila en batalla (O) | `KeyActionsBattle` | hecho |
| 5 | Menú de equipo (Espacio) y cambio de Pokémon en batalla (1-6) | `key_menu_pokemon`, `key_bt_pkmn1..6` | hecho con listas (falta la pantalla de ficha del original) |
| 6 | Menú principal (Enter): equipo, mochila, Pokédex, entrenador, guardar, salir | `KeyActionsExplorer` | hecho (faltan Opciones, Áreas, Móvil, Habilidades) |
| 7 | PC de los Centros: cajas (dejar, sacar, liberar) | `PCKeyActions` | hecho con listas (faltan la sala de cajas y el PC de ítems) |
| 8 | Pokédex (F12): vistos/capturados, categoría y descripción | `Dex_*`, `pkdexC` | hecho con listas (falta su pantalla) |
| 9 | Música de mapas y batallas | `Sound_World`, `Sound_Battle` | hecho (594 mapas; faltan variantes por historia, legendarios y villanos) |

## Después
- Los entrenadores en la arena: hecho (`Trainer1` en (98, 64) y los rivales en (480, 244), quietos
  con su sombra; el original no los mueve ni los golpea).
- Efectos de movimientos: hechos los de `SecEffect1` que solo dependen del movimiento (445: estados con
  su probabilidad, etapas de stats propias y del rival, retroceso) y los estados en tiempo real
  (`EffectStatuses`: parálisis, quemado, sueño, veneno, congelación, maldición, infección), y al atacar
  (`PossibleAttack`): parálisis y enamoramiento hacen perder el ataque 1 de cada 3, la confusión 1 de
  cada 2 con autogolpe (`Pokemon1AutoHit`); drenaje (12 movimientos), ataques múltiples (`EsMultiple`,
  `EffectAtackDestroy`) y mensajes de fin de estado. En el HUD: el icono de estado al día, Ctrl muestra
  el tiempo y las etapas de cada lado y º la lista del equipo. Faltan los clones de Doble Equipo (la
  evasión del panel) y lo que depende de habilidades, clima y mega/Z/dinamax.
- MO en el mapa: hechas Corte, Golpe Roca, Fuerza (tecla o Z frente al obstáculo) y Surf (tecla 3),
  con medallas `MEDALLA_STAR_n` y habilidades de campo (`AttackHabExt`), y Vuelo (tecla 2, medalla 4):
  la pantalla del mapa con los lugares visitados (`obj_pantallavuelo`, `data/extraido/vuelo.json`), el
  Pokémon que despega y aterriza, y las horas que pasan. El mapa también se abre con M o desde Usar Item.
  Cascada (Z junto a la cascada surfeando, medalla 8: sin ella la corriente no deja subir) y Buceo
  (tecla 7, medalla 7: `GoDiving` en `data/extraido/buceo.json`), Destello (tecla 5 en las cuevas
  oscuras de `data/extraido/campo.json`, medalla 3), Ola Lava (tecla 3 junto a la lava, medalla 8) y
  Treparrocas (Z frente a la pared trepable, medalla 7). Bici (V, 6 px/step, se baja al entrar a un
  edificio que no sea cueva) y pesca (C con una caña de cara al agua: a los 90 steps pica la mitad de
  las veces y sale un salvaje de la subtabla de esa caña), Vel. Extrema (la montura: 11 px/step, 4
  con X) y Torbellino (Z surfeando frente al remolino, medalla 6). El menú Habilidades (opción 6 del
  menú principal) lanza cada una. Faltan el Pokémon que sale a usar la MO, el sprite de buzo bajo el
  agua y las habilidades que no son de paso (Teletransporte, Excavar, Gran Ojo, Dulce Aroma, Daño
  Secreto); en Vuelo, elegir entre las llegadas de los lugares que tienen varias (Isla Sol, el Frente) y
  el grito del Pokémon (los gritos no se extraen por defecto).
- Historia completa: eventos de los 517 NPCs con scripts propios, rutas de NPCs por historia.
- Modos: Torre/Fábrica/Palacio/Torneo, guardería y huevos, minijuegos, multijugador local.
