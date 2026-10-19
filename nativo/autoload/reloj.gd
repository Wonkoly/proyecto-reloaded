extends Node
## La hora del juego, como obj_DayNightControl del original (InitializeDayNight, DayNightManageTime):
## arranca con la hora del sistema y después cuenta sola. En el overworld avanza 1 segundo de juego
## por step (30 por segundo real: una hora de juego son 2 minutos), en batalla y otras pantallas 1
## segundo por segundo real. No avanza en pausa ni durante las transiciones. Es de día de 8:00 a
## 18:59 (Hora > 7 && Hora < 19).

signal cambio_de_dia(es_de_dia: bool)

const STEPS_POR_SEGUNDO: float = 30.0

var hora: int = 0
var minuto: int = 0
var segundo: int = 0
## Con "hora <h>" de la consola dev la hora queda quieta hasta "hora real".
var fija: bool = false

var _pasos: float = 0.0
var _contador_batalla: int = 0
var _de_dia: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	poner_hora_del_sistema()


func es_de_dia() -> bool:
	return hora > 7 and hora < 19


func texto() -> String:
	return "%02d:%02d %s%s" % [hora, minuto, "día" if es_de_dia() else "noche", " (fija)" if fija else ""]


## Vuelve a la hora del sistema y deja que avance como en el original.
func poner_hora_del_sistema() -> void:
	var t: Dictionary = Time.get_time_dict_from_system()
	hora = t["hour"]
	minuto = t["minute"]
	segundo = t["second"]
	fija = false
	_avisar()


## Fija la hora (consola dev): queda quieta hasta poner_hora_del_sistema().
func fijar(h: int, m: int = 0) -> void:
	hora = clampi(h, 0, 23)
	minuto = clampi(m, 0, 59)
	segundo = 0
	fija = true
	_avisar()


func _process(delta: float) -> void:
	if fija or SceneManager.en_transicion:
		return
	_pasos += delta * STEPS_POR_SEGUNDO
	while _pasos >= 1.0:
		_pasos -= 1.0
		_step()


## Un step de DayNightManageTime: en el overworld avanza cada step; en las demás escenas, uno de cada 30.
func _step() -> void:
	if not get_tree().current_scene is Mapa:
		_contador_batalla += 1
		if _contador_batalla < int(STEPS_POR_SEGUNDO):
			return
		_contador_batalla = 0
	segundo += 1
	if segundo < 60:
		return
	segundo = 0
	minuto += 1
	if minuto < 60:
		return
	minuto = 0
	hora = (hora + 1) % 24
	_avisar()


func _avisar() -> void:
	if es_de_dia() != _de_dia:
		_de_dia = es_de_dia()
		cambio_de_dia.emit(_de_dia)
