# Partidas guardadas y perfil

## Guardar y cargar (`autoload/save_manager.gd`)
- **9 slots**, como el original (`global.Slot`). Cada uno es `user://partidas/partida_N.json`
  (en Linux: `~/.local/share/godot/app_userdata/Proyecto Reloaded/partidas/`).
- **En el juego: F5** (como `key_global_guardar`): con el jugador quieto, sin cruzar un salto y dentro
  del mapa, pregunta "¿Deseas guardar el juego?" y guarda en el slot de la partida. Una partida nueva
  toma el primer slot libre al guardar por primera vez; con los 9 ocupados, Nueva partida avisa
  (texto 59 del original) y hay que borrar uno en Cargar partida.
- **Seguridad**: se escribe primero `partida_N.tmp`, se comprueba que se puede leer, la partida
  anterior pasa a `partida_N.json.bak` y el `.tmp` ocupa su lugar. Cada archivo lleva una suma
  (sha256 de los datos): si el principal está dañado o fue editado a mano, se carga el respaldo y se avisa.
- **Qué se guarda** (`GameState.a_dict()`): nombre, dificultad, equipo (especie, apodo, nivel,
  experiencia, HP, energía, iv, ntv y movimientos), mapa, posición y dirección, a dónde lleva la salida
  del interior, banderas de la historia, `indice_lugar`, dinero, `prota_id`, apodo y personaje (códigos),
  trucos usados, opciones y tiempo de juego. La hora del día no: como en el original, sale del reloj del
  sistema. Las opciones de desarrollo (god, noclip...) tampoco.
- **Formato**: `{"formato", "version", "guardado", "suma", "resumen", "datos"}`. Si cambia lo que se
  guarda, se sube `VERSION` y `_migrar()` pone al día las partidas viejas. Las del juego original
  (`.savc`) no se importan.

## Perfil (`user://perfil.json`)
El nombre del jugador en este equipo: se pide la primera vez que se abre el juego y se cambia en el
título ("Cambiar nombre") o en Multijugador. Las partidas nuevas usan ese nombre. Cuando haya juego en
línea, el perfil será la cuenta.

## Pruebas
    ../tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path . res://tests/prueba_guardado.tscn

Guarda, carga, respaldo, archivo dañado, archivo editado, slots llenos y borrar, en una carpeta aparte.
