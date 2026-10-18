#!/bin/sh
# Mapas como escenas editables de Godot (godot/rooms/<Mapa>.tscn).
# Uso:
#   tools/rooms.sh Mapa [Mapa...]           crea la escena de esos mapas (no toca las que ya existen)
#   tools/rooms.sh --force Mapa [Mapa...]   la vuelve a crear desde el original (pierde tus cambios)
#   tools/rooms.sh --check Mapa [Mapa...]   comprueba que la escena sea igual al mapa original
#                                           (sirve solo antes de editarla)
# Cuando existe la escena de un mapa, el juego carga el mapa desde ella en lugar del JSON.
cd "$(dirname "$0")/.." || exit 1
GODOT=tools/Godot_v4.7.2-stable_linux.x86_64
if [ "$1" = "--check" ]; then
	shift
	exec $GODOT --headless --path godot --script res://rooms/editor/check_scenes.gd -- "$@"
fi
# Las imágenes de los tilesets se importan al proyecto para que el editor y los TileSets las usen.
mkdir -p godot/rooms/backgrounds
NEW=0
for f in gamedata/_internal/backgrounds/*.png; do
	[ -f "godot/rooms/backgrounds/${f##*/}" ] || { cp "$f" godot/rooms/backgrounds/; NEW=1; }
done
[ $NEW = 1 ] && timeout 1800 $GODOT --headless --path godot --import >/dev/null 2>&1
exec $GODOT --headless --path godot --script res://rooms/editor/make_scenes.gd -- "$@"
