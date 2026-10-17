# Comandos de developer

Solo funcionan en **modo developer**:

```sh
tools/dev.sh        # abre el juego en modo developer
tools/dev.sh 1      # igual, pero arranca directo en la partida del slot 1 (sin intro)
```

## Teclas

| Tecla | Qué hace |
|---|---|
| **F1** o **º** (la tecla a la izquierda del 1) | Abre/cierra la consola dentro del juego |
| **Tab** (mantenida, con la consola cerrada) | Juego a velocidad x4 |

Dentro de la consola:

| Tecla | Qué hace |
|---|---|
| Enter | Ejecuta el comando |
| Tab | Completa el comando o el nombre del mapa (`tp pue` + Tab → lista de pueblos) |
| ↑ / ↓ | Comandos anteriores |
| RePág / AvPág | Desplaza el historial |
| Esc | Cierra la consola |

Mientras la consola está abierta, el teclado no llega al juego.

## Comandos

Los nombres no distinguen mayúsculas y las búsquedas no distinguen acentos. Los nombres de objetos salen en el idioma
que tenga el juego (en inglés: `objetos potion`; en español: `objetos pocion` encuentra «Poción»).

### Moverse
| Comando | Qué hace |
|---|---|
| `tp <mapa> [x y]` | Va a otro mapa. Sin `x y` aparece en el centro. Acepta nombre (`tp PuebloAlba`) o índice (`tp 11`) |
| `tp <x> <y>` | Mueve al protagonista dentro del mapa actual |
| `mapas [filtro]` | Lista los mapas con su índice (`mapas ciudad`) |
| `atravesar` | Activa/desactiva atravesar paredes |
| `info` | Mapa actual, posición del protagonista, instancias y fps (útil para reportar fallos de tiles) |

También sirven `ir` y `teleport` en lugar de `tp`.

### Partida
| Comando | Qué hace |
|---|---|
| `guardar` | Guarda ya, sin las restricciones del juego (cinemáticas, eventos, etc.) |
| `cargar [slot]` | Reinicia y carga la partida del slot (por defecto, el actual) sin pasar por la intro |
| `turbo [n]` | Velocidad del juego: `turbo 4`, `turbo 1` (normal). Máximo 16 |

El guardado normal del juego sigue siendo **F5**.

### Equipo y objetos
| Comando | Qué hace |
|---|---|
| `curar` | Cura al equipo como en el Centro Pokémon |
| `dinero [cantidad]` | Muestra el dinero, o lo fija (`dinero 50000`) |
| `objetos [filtro]` | Busca objetos por nombre y muestra su id (`objetos ball`) |
| `objeto <id> [cantidad]` | Añade objetos a la mochila (`objeto 1 5` = 5 Poké Balls) |
| `sinencuentros` | Activa/desactiva los Pokémon salvajes |
| `pokemons [filtro]` | Busca Pokémon por nombre y muestra su id (`pokemons charm`) |
| `pokemon <id> [nivel]` | Añade un Pokémon al equipo (`pokemon 4 15` = Charmander nivel 15) |
| `equipo` | Muestra el equipo: nombre, nivel y PS |

### Batallas
| Comando | Qué hace |
|---|---|
| `batalla <id> [nivel]` | Combate contra un Pokémon salvaje, como al pisar hierba alta (`batalla 16 3`) |
| `entrenador <n>` | Pone al entrenador n del juego a tu lado y empieza el combate (1 = rival, 2 = Rattata/Pidgey/Hoothoot…) |

Para capturar: la Ball debe estar asignada en la mochila (tecla B sobre ella; o `global ball_asign 0`), luego B en combate.
El mote del Pokémon capturado se acepta con Enter.

### Avanzado
| Comando | Qué hace |
|---|---|
| `global <nombre> [valor]` | Lee o escribe una variable global del juego (`global Slot`) |
| `var <objeto> <campo> [valor]` | Lee o escribe una variable de la primera instancia de un objeto. Los avances de la historia están en el objeto `variables` (`var variables fy_002`) |
| `script <Nombre> [args...]` | Llama a un script del juego (`script SetDinero 1000`). Los textos van entre comillas |
| `perf` | Informe de rendimiento cada segundo: fps, ms de lógica/dibujo y los objetos más costosos |
| `efecto <0-11> [tamaño 0-2] [color]` | Crea un efecto de partículas sobre el protagonista: 0 explosión, 1 anillo, 2 elipse, 3 fuegos artificiales, 4 humo, 5 humo que sube, 6 estrella, 7 chispa, 8 destello, 9 nube, 10 lluvia, 11 nieve |
| `tecla <vk>` | Pulsa una tecla (código VK de Windows: 90 = Z, 88 = X, 13 = Enter, 116 = F5) |

### Consola
| Comando | Qué hace |
|---|---|
| `ayuda [comando]` | Lista los comandos, o explica uno (`ayuda tp`) |
| `limpiar` | Borra la consola |
| `ventana` | Abre/cierra la ventana de developer (opcional: lista de mapas con clic, botones de guardar y turbo) |

## Notas
- Los comandos que tocan el juego (`tp`, `guardar`, `curar`…) se ejecutan cuando el juego queda libre:
  si hay un diálogo abierto, esperan a que termine.
- `tp` a pantallas que no son mapas (menús como `CajaPkmnMenu`) puede dejar el juego en un estado raro;
  usa `mapas` para ver los nombres.

## Pruebas automáticas
Variables de entorno para correr el juego sin tocarlo (ver README):
`GM_DEV_CMDS="t:comando;@Mapa+s:comando"`, `GM_DEV_LOAD=<slot>`, `GM_INPUT`, `GM_INPUT_UNTIL`,
`GM_SNAPSHOTS` y `GM_ROOT` (carpeta del juego alternativa, para no tocar tus partidas).
