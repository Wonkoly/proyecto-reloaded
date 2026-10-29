extends Node
## Reproducción de música y efectos de sonido.

const MUSICA_INTRO: String = "res://assets/extraido/audio/intro/music_intro_%d.mp3"
const SONIDOS_UI: String = "res://assets/extraido/audio/sfx/ui/"
const MUSICA: String = "res://assets/extraido/audio/music/%s.ogg"
## Qué pista suena en cada mapa y en cada tipo de batalla (Sound_World / Sound_Battle, ver
## tools/musica_original.py).
const TABLA_MUSICA: String = "res://data/extraido/musica/musica.json"

## Canción del título (global.musicaIntro / data/audio/config.ini del original):
## -1 = una al azar de las 10, 0 = sin música, n = Music_Intro_n.
var musica_intro: int = -1

var _musica: AudioStreamPlayer
var _tabla: Dictionary = {}
var _efectos: Array[AudioStreamPlayer] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_musica = AudioStreamPlayer.new()
	add_child(_musica)
	for i: int in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_efectos.append(p)


## Pone una canción en bucle (si ya suena, no la reinicia).
func reproducir_musica(stream: AudioStream) -> void:
	if stream == null or (_musica.playing and _musica.stream == stream):
		return
	if "loop" in stream:
		stream.set("loop", true)
	_musica.stream = stream
	_musica.play()


## ImportMusica: la pista por su nombre (sin extensión); no hace nada si no existe.
func reproducir_pista(nombre: String) -> void:
	var ruta: String = MUSICA % nombre
	if ResourceLoader.exists(ruta):
		reproducir_musica(load(ruta))


## Sound_World: la música del mapa; los interiores sin música propia usan la del mapa de afuera y
## los mapas sin pista dejan sonar la que había.
func musica_mapa(nombre_original: String) -> void:
	var mapas: Dictionary = _tabla_musica().get("mapas", {})
	var pista: String = str(mapas.get(nombre_original, ""))
	if pista == "@afuera":
		pista = str(mapas.get(GameState.mapa_salida, ""))
	if pista != "" and not pista.begins_with("@"):
		reproducir_pista(pista)


## Sound_Battle: "salvaje", "legendario", "entrenador", "lider", "malo"...
func musica_batalla(clave: String) -> void:
	var pista: String = str(_tabla_musica().get("batallas", {}).get(clave, ""))
	if pista != "":
		reproducir_pista(pista)


func _tabla_musica() -> Dictionary:
	if _tabla.is_empty():
		var f: FileAccess = FileAccess.open(TABLA_MUSICA, FileAccess.READ)
		_tabla = JSON.parse_string(f.get_as_text()) if f else {"mapas": {}}
	return _tabla


func detener_musica() -> void:
	_musica.stop()
	_musica.stream = null


func sonando() -> bool:
	return _musica.playing


## La música del título como BlackConfiguration: Music_Intro_n según musica_intro (no se reinicia si ya suena).
func reproducir_intro() -> void:
	if musica_intro == 0:
		detener_musica()
		return
	if _musica.playing:
		return
	var n: int = musica_intro if musica_intro > 0 else randi_range(1, 10)
	var ruta: String = MUSICA_INTRO % n
	if ResourceLoader.exists(ruta):
		reproducir_musica(load(ruta))


## Un efecto de sonido de los menús (snd_click...), por nombre de archivo sin extensión.
func efecto_ui(nombre: String) -> void:
	var ruta: String = SONIDOS_UI + nombre + ".wav"
	if not ResourceLoader.exists(ruta):
		return
	for p: AudioStreamPlayer in _efectos:
		if not p.playing:
			p.stream = load(ruta)
			p.play()
			return
