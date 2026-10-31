class_name EntrenadorArena
extends Node2D
## Un entrenador quieto en la arena (Trainer1: el jugador; Trainer2: el rival y sus compañeros):
## una sombra elíptica bajo los pies y su sprite de perfil en el frame 1 (DrawTrainer1, DrawTrainer2).
## El jugador mira hacia el centro (image_xscale -1 si está en la mitad derecha); el rival, a la izquierda.

const OVERWORLD: String = "res://assets/extraido/sprites/overworld/%s.tres"

var sprite: SpriteOriginal
var xscale: float = 1.0


## El del jugador: su sprite de la derecha (en bici, el de bici: DefineTrainer1).
static func del_jugador(pos: Vector2) -> EntrenadorArena:
	var e := EntrenadorArena.new()
	e.name = "Trainer1"
	e.position = pos
	var nombres: Array = _personaje()
	var i: int = 5 if GameState.ciclista and nombres.size() == 9 else 2
	e.sprite = load(OVERWORLD % nombres[i]) if nombres.size() > i else null
	e.xscale = -1.0 if pos.x > 288.0 else 1.0
	return e


## El rival de un combate contra entrenador (global.TRAINER_R por su sprINDEX), mirando a la izquierda.
static func del_rival(entrenador: EntrenadorData, pos: Vector2) -> EntrenadorArena:
	var f: FileAccess = FileAccess.open("res://data/extraido/rivales_arena.json", FileAccess.READ)
	var tabla: Dictionary = JSON.parse_string(f.get_as_text()) if f else {}
	var nombre: String = str(tabla.get(str(int(entrenador.sprindex)), ""))
	if nombre == "":
		return null
	var e := EntrenadorArena.new()
	e.name = "Trainer2"
	e.position = pos
	e.sprite = load(OVERWORLD % nombre)
	e.xscale = -1.0
	return e


static func _personaje() -> Array:
	var f: FileAccess = FileAccess.open("res://data/extraido/personajes.json", FileAccess.READ)
	var tabla: Dictionary = JSON.parse_string(f.get_as_text()) if f else {}
	var v: Variant = tabla.get("entrenadores", {}).get(str(GameState.personaje_entrenador)) if GameState.personaje == 10 \
		else tabla.get("protagonistas", {}).get(str(GameState.personaje))
	return v if v is Array else []


func _ready() -> void:
	z_index = int(position.y / 100.0)  # depth = -(y/100)


func _draw() -> void:
	if sprite == null or sprite.frames.is_empty():
		return
	var tam: Vector2 = sprite.frames[0].get_size()
	var izquierda: float = -sprite.origen.x if xscale > 0.0 else sprite.origen.x - tam.x
	var abajo: float = tam.y - sprite.origen.y
	_elipse(Rect2(izquierda, abajo - 5.0, tam.x, 10.0), Color(0, 0, 0, 0.3))
	sprite.dibujar(self, 1, Vector2.ZERO, Vector2(xscale, 1))


func _elipse(r: Rect2, color: Color) -> void:
	var puntos := PackedVector2Array()
	for i: int in 24:
		var a: float = TAU * i / 24.0
		puntos.append(r.get_center() + Vector2(cos(a) * r.size.x / 2.0, sin(a) * r.size.y / 2.0))
	draw_colored_polygon(puntos, color)
