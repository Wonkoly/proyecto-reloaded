# Fase 1: inicio de la historia (notas de trabajo)

Investigado en el original; falta implementarlo. Rama: `feat/historia-inicio`.

## Secuencia del original
1. Partida nueva en `Home_2` sin Pokémon: `fy_002 = 0`, `movil = 0`. Hoy `GameState.nueva_partida`
   da un Charmander y pone `fy_002 = 1` y `movil = 1`: **hay que quitarlo**.
2. `Home_1`: la madre (`obj_Mom_s16`, retrato `Character` 1287; 1288 si `prota_index == 1`).
   `MomHabla`:
   - con `fy_002 == 0`: su `str` (2473 chico / 2474 chica; 2475 si `prota_index == 1`);
   - con `fy_002 == 1` y `movil == 0`: 2499 (2500), 2501, 2502, 2503, narrar 3036, objeto 176 (móvil),
     2504 con F8, 2505; si el mapa del suelo no se recogió: 2506, narrar 3041, objeto 186 (mapa);
     después `movil = 1`;
   - con `movil == 1`: 2507 y pregunta 2464 (descansar: cura y pasan 2 horas).
3. `PuebloAlba`: `obj_NoPass_s8` cierra el este hasta `fy_002` (1501) y `obj_NoPass_s11` hasta `movil`
   (1502/1503). Ya están en la escena con sus condiciones.
4. `Lab_Oak`:
   - `obj_Oak1_s6` (condición `fy_002 == 0`), `OakStarterHabla`, retrato 404:
     2561 (con F1), 2562, narrar 2563 (Pokédex), 2564, 2565, 2566, 2567; el rival
     (`obj_Lab_Rival_s7`) mira a la derecha, "!", habla con su retrato (1000 + `rival_personaje`) 2569
     y 2570 (2571 si es el nieto), y se va (`RivalLabHuye`: abajo 51 px, derecha 24, abajo 150, a
     3 px/step). Si el rival ya no está: solo 2568.
   - Poké Balls `obj_ini_s0/1/2` (INI 1, 2, 3 → Pikachu 25, 447, Eevee 133; los códigos de iniciales
     cambian el trío, `InitializeStarterSelector`). `KeyActionsStarterSelector`: debajo, mirando
     arriba. Con `fy_002 == 1` o el rival todavía ahí: narrar 6833. Si no (`StarterSelectorElige`):
     cuadro con el Pokémon (`obj_PKCuadro`), 6834 con su nombre, pregunta 6835; si sí: el inicial a
     nivel 5, `pkchoose = INI`, `fy_002 = 1`, Pokédex visto y capturado, narrar 6837, "!" sobre Oak,
     6838 (nombre), 6839, 6840, 15 Poké Balls (objeto 1) asignadas a B, 6841 con B y F12.
   - Hoy las `obj_ini` son decorado: el extractor (`mapas_original.py`, cerca de `obj_people`) tiene
     que crearlas como NPC (`npc.tscn`) para poder hablarles.

## Lo que falta en el motor de eventos
- `ocultar [nodo]`, `mover nodo dirección px`, `exclamacion [nodo]`, `hablante rival`,
  `mostrar_pokemon id` / `ocultar_pokemon`, `asignar_ball id`.
- `dar_pokemon` debe marcar la Pokédex como capturado.

## Después
Validador de recorrido (`tools/recorrido.py`) y Ruta 1 → primer gimnasio (`MEDALLA_STAR[1]`).
