# Plan para terminar el port nativo

Meta: *Proyecto Reloaded* 1.9.2.2 jugable de principio a fin en `nativo/`, fiel al original.
Los cambios de mecánica van después de terminarlo.
Estado detallado de cada sistema: [hoja_de_ruta.md](hoja_de_ruta.md).

## Cómo se trabaja (igual en todas las fases)
1. **Leer el original** (`extracted/scripts`, `objects`), nunca copiar código de `godot/`.
2. **Lo que es tabla, se extrae** a datos con una herramienta en `tools/` (como `efectos_original.py`).
   **Lo que es lógica, se escribe** a mano en GDScript, con el nombre del script original en el comentario.
3. **Probar jugando**: un script de prueba en ventana con entrada simulada y capturas, hasta que se vea
   y se comporte como el original. Las pruebas que valgan la pena quedan en `tests/`.
4. **Un commit por sistema**, subido a la rama de la fase; `hoja_de_ruta.md` al día.

## Fase 1 — De la casa a la primera medalla
**Estado: hecha** (`feat/historia-inicio`). `tests/prueba_historia.gd` recorre la casa, el laboratorio,
el móvil, la ruta y el gimnasio de Mino. Pendientes menores: los textos según el sexo del
protagonista (`TrainerBoy`), el trío de iniciales del código de iniciales, el rival que reaparece si se
sale del laboratorio sin elegir, y los eventos opcionales del camino (Terón, Celebi en Bosque Spica).
El objetivo es que una partida nueva llegue a la medalla 1 sin trucos.
- **Inicio del juego**: presentación del profesor, nombre, elección del inicial (hoy se regala un
  Charmander) y los eventos de la casa y de Pueblo Alba.
- **Validador de recorrido** (`tools/recorrido.py` + prueba en Godot): sigue la historia con las
  banderas del original, mapa por mapa, y lista qué evento falta o dónde se traba. Sirve para todas
  las fases siguientes.
- **Eventos de los NPCs del camino**: los que el validador marque, convertidos a `.evento`
  (hay 430 scripts `*Habla` en el original y 236 eventos ya generados).
- **Primer gimnasio**: entrenadores, líder, entrega de la medalla (`MEDALLA_STAR[1]`) y lo que
  desbloquea.
- **Listo cuando**: el validador recorre de la casa a la medalla 1 sin errores, y una partida jugada a
  mano llega igual.

## Fase 2 — Objetos que faltan
**Estado: hecha** (`feat/objetos`). Caramelo Raro, vitaminas y Mochis, objetos evolutivos, MT/DT,
evoluciones especiales (nivel + objeto, Amigo Ball, día/noche, sexo, y por equipo: Nincada deja a
Shedinja en un hueco, Mantyke con Remoraid, la 769 con un Siniestro), equipar y quitar objetos, el objeto
asignado a la tecla A en combate, los IV que crecen al subir de nivel, y en combate Cintas/Gafas
Elección, Cinta Experto, Gafas Especiales, Vidasfera, Chaleco Asalto, Restos, potenciadores de tipo,
gemas y objetos de especie. Quedan para la fase 4: el resto de objetos de combate que dependen de
habilidades o clima, y las evoluciones por lluvia o contadores (`extraInfo`).
- Caramelo Raro y objetos que suben stats, usados desde la mochila (`UseDirectObject`).
- Piedras evolutivas y el resto de evoluciones especiales (`EvolutionConfirmation`,
  `CheckTeamEvolution`: objeto, intercambio, amistad, condiciones).
- MT y MO: enseñar movimientos desde la mochila (`MTAtack`, `Ataque_MT`), y con eso las MO sin trucos.
- Objetos equipados más comunes en batalla.
- **Listo cuando**: se puede evolucionar con piedra y enseñar Corte con su MO en una partida normal.

## Fase 3 — Viajar
**En curso** (`feat/viajar`). Hecho: mapa de la región con los lugares visitados y Vuelo
(`tests/prueba_vuelo.gd`), Cascada y Buceo (`tests/prueba_mo.gd`).
- Mapa de la región (Áreas) con los lugares visitados (`MapaLugar`).
- Vuelo (objeto 153), y después Buceo, Cascada, Destello, Ola Lava y Treparrocas, con el mismo
  patrón que Surf.
- Pesca (cañas y encuentros de pesca; las tablas ya están).
- Bici y montura.
- **Listo cuando**: se vuela entre ciudades visitadas y cada MO cruza su obstáculo en su mapa.

## Fase 4 — Batalla completa
- El entrenador del jugador en la arena (`Trainer1`): se mueve y lo pueden golpear.
- Habilidades de los Pokémon (las más comunes primero, extraídas donde se pueda).
- Lo que falta de los efectos: confusión, enamoramiento, drenaje, ataques múltiples, evasión,
  iconos de estado en el HUD, Repartir Exp., apodos al capturar.
- Clima, megaevoluciones, movimientos Z y dinamax.
- **Listo cuando**: una batalla grabada del original y la misma en nativo se ven y se juegan igual.

## Fase 5 — Pantallas del original
- Ficha del equipo, Pokédex y cajas del PC con el aspecto del original (portar los `Draw*` con sus
  sprites, como el HUD de batalla); PC de ítems.
- Opciones, móvil, misiones y ficha de entrenador.
- **Listo cuando**: cada pantalla se compara con una captura del original.

## Fase 6 — El resto de la historia
- Gimnasios 2 a 8 y todo lo que hay entre medio, con el ciclo de la fase 1 (validador → eventos →
  prueba), un gimnasio por rama.
- Liga, final y post-juego.
- **Listo cuando**: el validador recorre la historia completa y una partida a mano llega a los créditos.

## Fase 7 — Modos extra
- Guardería y huevos (la cría ya está a medias).
- Frentes de Batalla: Torre, Fábrica, Palacio, Torneo, Supervivencia, Zona e Infierno.
- Safari, minijuegos y multijugador local.

## Orden y paralelo
- La historia (fases 1 y 6) es el camino principal.
- Las fases 2, 3 y 5 tocan otros archivos y se pueden llevar en sesiones aparte al mismo tiempo.
  La 4 conviene después de la 2 (los objetos equipados entran en las dos).
- La 7 va al final o cuando sobre tiempo.

## Riesgos
- **Eventos con lógica rara**: algunos NPCs del original hacen cosas fuera de lo común; el formato
  `.evento` puede necesitar órdenes nuevas (se documentan en `eventos.md`).
- **Volumen de la historia**: es la parte más larga. El validador es lo que la hace manejable.
- **Datos regenerables**: `assets/extraido` y `data/extraido` se regeneran. Los mapas siempre con
  `extraer.py --solo mapas --mapas todos`, y nada editado a mano ahí dentro.
