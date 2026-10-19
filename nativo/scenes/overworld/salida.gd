class_name Salida
extends Area2D
## Paso a otro mapa: un borde del mapa (CambiosWorldRooms / CambiosSpecialRooms), una puerta
## (CreateDoors: se entra pulsando arriba) o la salida de un interior (obj_out: se sale pulsando
## abajo y se vuelve a donde se entró). El SceneManager hace el cambio.

signal activada(salida: Salida)

enum Activacion { AL_ENTRAR, ARRIBA, ABAJO }

## Room de destino en el original (Ruta_1, Home_1...).
@export var destino: String = ""
@export var destino_posicion: Vector2 = Vector2.ZERO
## La coordenada de destino se suma a la del jugador (bordes: "(14).x + 112").
@export var relativa_x: bool = false
@export var relativa_y: bool = false
@export var activacion: Activacion = Activacion.AL_ENTRAR
## obj_out: vuelve al mapa y la posición desde donde se entró.
@export var volver: bool = false
## Sprite de la puerta (se dibuja al abrirse).
@export var sprite: SpriteOriginal

var abierta: bool = false


func _ready() -> void:
	add_to_group("salidas")


## La puerta se abre (DoorOpening) antes de entrar.
func abrir() -> void:
	abierta = true
	queue_redraw()


## Posición en el mapa de destino para un jugador que sale desde `posicion_jugador`.
func posicion_destino(posicion_jugador: Vector2) -> Vector2:
	return Vector2(
		posicion_jugador.x + destino_posicion.x if relativa_x else destino_posicion.x,
		posicion_jugador.y + destino_posicion.y if relativa_y else destino_posicion.y)


func _draw() -> void:
	if sprite and abierta:
		sprite.dibujar(self, sprite.frames.size() - 1, Vector2.ZERO)
