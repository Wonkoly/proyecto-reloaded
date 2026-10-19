class_name Npc
extends StaticBody2D
## Un NPC del original (obj_people: obj_Talk, obj_NoPass...), creado por CreateNPC*: su sprite en
## 4 direcciones (izquierda = derecha volteada), hacia dónde mira y su texto (TextDialog).

@export var sprite_abajo: SpriteOriginal
@export var sprite_arriba: SpriteOriginal
@export var sprite_derecha: SpriteOriginal
## Notación de teclado numérico (2 abajo, 8 arriba, 4 izquierda, 6 derecha).
@export var mira: int = 2
## MOVE en el original: camina solo (pendiente).
@export var se_mueve: bool = false
## Línea de txt_dialog con lo que dice (0 = nada).
@export var dialogo: int = 0
@export var objeto_original: String = ""


func texto() -> String:
	return Textos.linea("txt_dialog", dialogo) if dialogo > 0 else ""


func _draw() -> void:
	var s: SpriteOriginal = {2: sprite_abajo, 8: sprite_arriba, 4: sprite_derecha, 6: sprite_derecha}.get(mira, sprite_abajo)
	if s == null:
		s = sprite_abajo
	if s:
		s.dibujar(self, 0, Vector2.ZERO, Vector2(-1 if mira == 4 else 1, 1))
