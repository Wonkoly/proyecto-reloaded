extends Control
## Menú para abrir directo cada parte del juego mientras se construye.

@onready var especie_jugador: OptionButton = %EspecieJugador
@onready var nivel_jugador: SpinBox = %NivelJugador
@onready var especie_rival: OptionButton = %EspecieRival
@onready var nivel_rival: SpinBox = %NivelRival
@onready var entrenador: CheckBox = %Entrenador
@onready var crack: CheckBox = %Crack
@onready var maestro: CheckBox = %Maestro
@onready var dificultad: OptionButton = %Dificultad


const JUGADOR: PackedScene = preload("res://scenes/overworld/jugador.tscn")


func _ready() -> void:
	get_window().content_scale_size = Vector2i(576, 324)
	for id: int in Datos.especies_con_sprites():
		var texto: String = "%03d %s" % [id, Datos.especies_con_sprites()[id]]
		especie_jugador.add_item(texto, id)
		especie_rival.add_item(texto, id)
	especie_jugador.select(especie_jugador.get_item_index(ConfigPruebas.especie_jugador))
	especie_rival.select(especie_rival.get_item_index(ConfigPruebas.especie_rival))
	nivel_jugador.value = ConfigPruebas.nivel_jugador
	nivel_rival.value = ConfigPruebas.nivel_rival
	entrenador.button_pressed = ConfigPruebas.rival_entrenador
	crack.button_pressed = ConfigPruebas.rival_crack
	maestro.button_pressed = ConfigPruebas.rival_maestro
	for nombre: String in GameState.Dificultad:
		dificultad.add_item(nombre.capitalize(), GameState.Dificultad[nombre])
	dificultad.select(dificultad.get_item_index(GameState.dificultad))
	%Batalla.grab_focus()


func _on_batalla_pressed() -> void:
	ConfigPruebas.especie_jugador = especie_jugador.get_selected_id()
	ConfigPruebas.nivel_jugador = int(nivel_jugador.value)
	ConfigPruebas.especie_rival = especie_rival.get_selected_id()
	ConfigPruebas.nivel_rival = int(nivel_rival.value)
	ConfigPruebas.rival_entrenador = entrenador.button_pressed
	ConfigPruebas.rival_crack = crack.button_pressed
	ConfigPruebas.rival_maestro = maestro.button_pressed
	GameState.dificultad = dificultad.get_selected_id() as GameState.Dificultad
	get_tree().change_scene_to_file("res://scenes/battle/battle_arena.tscn")


## PuebloAlba con el jugador frente a la puerta de su casa.
func _on_overworld_pressed() -> void:
	var mapa: Mapa = (load("res://assets/extraido/mapas/pueblo_alba.tscn") as PackedScene).instantiate()
	var jugador: Jugador = JUGADOR.instantiate()
	jugador.position = Vector2(417, 214)
	mapa.objetos().add_child(jugador)
	get_tree().change_scene_to_node(mapa)
