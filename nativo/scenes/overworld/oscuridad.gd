class_name Oscuridad
extends Node2D
## obj_Oscuro1: la oscuridad de una cueva alrededor del jugador (DrawDestello). Sin Destello se ve un
## círculo chico (spr_darkness1); con Destello (tecla 5) el círculo crece hasta el grande
## (spr_darkness2). En el Gimnasio de Sirio la luz llega con la medalla 3 y bajo el agua siempre se
## ve el círculo grande (SetInitialRadioDestello, SetFadeRadioDestello).

const UI: String = "res://assets/extraido/sprites/ui/"

## RADIO: escala del círculo chico; cuando llega a 40 solo queda el grande.
var radio: float = 1.0
var _chico: SpriteOriginal
var _grande: SpriteOriginal
var _acumulado: float = 0.0


func _ready() -> void:
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	top_level = true
	_chico = load(UI + "spr_darkness1.tres")
	_grande = load(UI + "spr_darkness2.tres")
	radio = 150.0 if _iluminada() else (100.0 if GameState.buceando else 1.0)


## La luz de esta cueva: la medalla 3 en el Gimnasio de Sirio, Destello en las demás.
func _iluminada() -> bool:
	if _mapa() == "GYM3_Sirio":
		return GameState.tiene_medalla(3)
	return GameState.bandera("usadestello") == 1


func _mapa() -> String:
	var m: Mapa = get_parent() as Mapa
	return m.nombre_original if m else ""


func _process(delta: float) -> void:
	var j: Jugador = DevConsole.jugador()
	if j:
		global_position = j.global_position
	_acumulado += delta * 30.0
	while _acumulado >= 1.0:
		_acumulado -= 1.0
		_step()
	queue_redraw()


func _step() -> void:
	var tope: float = 40.0
	if GameState.buceando and _mapa() != "GYM3_Sirio":
		tope = 150.0 if _iluminada() else 100.0
	if not _iluminada() and not GameState.buceando:
		radio = 1.0
	elif radio < tope:
		radio += 1.0


func _draw() -> void:
	if radio < 40.0 and _chico:
		_chico.dibujar(self, 0, Vector2.ZERO, Vector2(radio, radio))
	if radio > 1.0 and _grande:
		_grande.dibujar(self, 0, Vector2.ZERO)


## KeyActionsDestello + InteractionDestello + RealizaDestello: con la medalla 3 y un Pokémon con
## Destello (si no, TextDialog 57) la cueva se ilumina hasta salir a una de las rooms que la apagan.
## En el Gimnasio de Sirio y en las Ruinas Omega no se usa (TextDialog 2387).
func usar_destello(desde: Node) -> void:
	if not GameState.tiene_medalla(3):
		return
	if _mapa() in ["GYM3_Sirio", "RuinasOmega"]:
		await CajaDialogo.decir(desde, Textos.linea("txt_dialog", 2387))
		return
	if GameState.con_habilidad_campo(Campo.HABILIDAD_DESTELLO) == null:
		await CajaDialogo.decir(desde, Textos.linea("txt_dialog", 57))
		return
	GameState.historia["usadestello"] = 1
