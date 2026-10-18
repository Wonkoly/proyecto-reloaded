extends Control
## Menú para abrir directo cada parte del juego mientras se construye.


func _ready() -> void:
	$Centro/Opciones/Batalla.grab_focus()


func _on_batalla_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/battle/battle_arena.tscn")
