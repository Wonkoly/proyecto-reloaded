class_name Salida
extends Area2D
## Paso a otro mapa. Según el objeto del original:
## - borde / escalera (CambiosWorldRooms, CambiosSpecialRooms): se activa al llegar; el original
##   mira solo el punto del jugador ((14).x, (14).y) dentro del rectángulo → por_punto.
## - puerta (obj_door y derivados, obj_door_inv, obj_NOdoor): pulsando arriba con la máscara encima.
## - salida de un interior (obj_out): pulsando abajo, vuelve a donde se entró.
## - salida especial (obj_out_special), teletransporte, conducto, brecha: al llegar.
## El SceneManager hace el cambio.

signal activada(salida: Salida)

enum Activacion { AL_ENTRAR, ARRIBA, ABAJO }
## Qué hace con el "regreso" (global.room_out/outx/outy) al usarla.
enum Regreso { NADA, GUARDAR, GUARDAR_SI_VACIO, BORRAR }

## Room de destino en el original (Ruta_1, Home_1...).
@export var destino: String = ""
@export var destino_posicion: Vector2 = Vector2.ZERO
## La coordenada de destino se suma a la del jugador (bordes: "(14).x + 112").
@export var relativa_x: bool = false
@export var relativa_y: bool = false
@export var activacion: Activacion = Activacion.AL_ENTRAR
@export var regreso: Regreso = Regreso.NADA
## obj_out: vuelve al mapa y la posición desde donde se entró.
@export var volver: bool = false
## obj_out en algunas rooms vuelve a una posición fija (OutDoorStepActions); (-1, -1) si no.
@export var volver_posicion: Vector2 = Vector2(-1, -1)
## global.index_place que deja al usarla (el INDEX de la puerta); -1 no lo cambia.
@export var indice_lugar: int = -1
## Se activa con el punto del jugador dentro del rectángulo, no con su máscara.
@export var por_punto: bool = false
## borde, escalera, puerta, salida_interior, salida_especial, teletransporte... (consola dev).
@export var tipo: String = ""
## Sprite de la puerta (se dibuja al abrirse).
@export var sprite: SpriteOriginal

var abierta: bool = false


func _ready() -> void:
	add_to_group("salidas")


## Si el jugador (su cuerpo, o su punto con por_punto) está dentro.
func contiene(jugador: Node2D) -> bool:
	if not por_punto:
		return overlaps_body(jugador)
	return rect_global().has_point(jugador.global_position)


## El rectángulo de activación en coordenadas del mapa.
func rect_global() -> Rect2:
	var forma: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if forma == null or not forma.shape is RectangleShape2D:
		return Rect2(global_position, Vector2.ZERO)
	var tam: Vector2 = (forma.shape as RectangleShape2D).size
	return Rect2(global_position + forma.position - tam / 2.0, tam)


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
