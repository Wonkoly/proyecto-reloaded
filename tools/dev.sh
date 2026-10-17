#!/bin/sh
# Abre el juego en modo developer. Uso: tools/dev.sh [slot]
#   slot: carga esa partida al arrancar, sin pasar por la intro.
cd "$(dirname "$0")/.." || exit 1
ARGS="--dev"
[ -n "$1" ] && ARGS="$ARGS --load=$1"
exec tools/Godot_v4.7.2-stable_linux.x86_64 --path godot -- $ARGS
