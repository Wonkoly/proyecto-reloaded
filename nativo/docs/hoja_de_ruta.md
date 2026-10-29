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
| 5 | Menú de equipo y cambio de Pokémon en batalla | `key_bt_show_pkmn`, `NextPokemon` | pendiente |
| 6 | Menú de pausa del overworld (equipo, mochila, guardar, opciones) | `KeyActionsProta` | pendiente |
| 7 | PC / caja | `MenuCaja*` | pendiente |
| 8 | Pokédex (vistos/capturados, ficha) | `Dex_*`, `pkdexC` | pendiente |
| 9 | Música de mapas y batallas | `ImportMusica` | pendiente |

## Después
- El entrenador del jugador dentro de la arena (`Trainer1`, se mueve y lo pueden golpear).
- Estados (quemado, dormido...), habilidades, objetos equipados, clima, mega/Z/dinamax, efectos
  especiales de cada movimiento (`Ataque1GolpeaPokemon2`).
- Evoluciones por objeto, intercambio, amistad y condiciones especiales (`CheckTeamEvolution`).
- MO en el mapa (surf, corte, fuerza, vuelo...), bici, montura.
- Historia completa: eventos de los 517 NPCs con scripts propios, rutas de NPCs por historia.
- Modos: Torre/Fábrica/Palacio/Torneo, guardería y huevos, minijuegos, multijugador local.
