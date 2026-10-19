# Consola de desarrollo

Solo en builds de depuración (al correr desde el editor o con `--path`); en un export de release
`DevConsole` se elimina al arrancar.

| Tecla | Qué hace |
|---|---|
| **F1** | Abre/cierra la consola (pausa el juego mientras está abierta) |
| ↑ / ↓ | Historial de comandos |
| Tab | Completa el comando o su argumento (mapas, especies) |
| **F3** | Overlay (Shift+F3: pantalla de códigos del original): FPS, mapa, posición, banderas de la historia, tamaño del equipo |
| **F4** | Dibuja colisiones (rojo), NPCs (naranja), hierba (verde), salidas con su destino (azul) y marcadores sin convertir (amarillo) |

| Comando | Qué hace |
|---|---|
| `ayuda [comando]` | Lista los comandos o explica uno |
| `tp <mapa> [x y]` | Va a un mapa (al centro si no se da posición) |
| `mapas [filtro]` | Lista los mapas extraídos |
| `noclip` | Atravesar paredes |
| `velocidad <factor>` | Velocidad de todo el juego (`Engine.time_scale`) |
| `dar <especie> <nivel>` | Agrega un Pokémon al equipo (id o nombre) |
| `curar` | HP y energía al máximo |
| `nivel <n>` | Nivel del primer Pokémon del equipo |
| `encuentro <especie> <nivel>` | Batalla ya contra un salvaje |
| `encuentros on\|off` | Activa/desactiva los salvajes en la hierba |
| `dificultad <1\|2\|4\|0>` | Fuerza el divisor de daño (PowDif) de los dos lados; 0 vuelve al de la dificultad |
| `historia [bandera] [valor]` | Muestra o cambia banderas de la historia |
| `god` | Tu Pokémon no recibe daño |
| `energia_infinita` | Tu Pokémon tiene siempre la energía llena |
| `pos` | Mapa, posición y dirección del jugador |
| `codigo <texto>` | Mete un código del original (ver `referencia_original.md`; también Shift+F3) |
| `validar` | Revisa las salidas del mapa actual con la historia actual: destino, llegada caminable, rebote, regreso; cada una ok / error / requiere X / inactiva ahora |
| `ir <mapa> [tp]` | Ruta con menos cambios de mapa desde el actual (de `data/extraido/conexiones.json`) con el tipo y requisitos de cada paso; con `tp` va al primer mapa de la ruta |

Para agregar un comando, una línea en `scenes/debug/comandos_dev.gd`:
`c.registrar("nombre", "descripción", "uso", funcion)` (la función recibe los argumentos como
`PackedStringArray` y devuelve el texto a mostrar).
