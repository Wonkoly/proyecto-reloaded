class_name Vuelo
## Vuelo (MO 2) y los lugares visitados del mapa de la región: data/extraido/vuelo.json
## (tools/vuelo_original.py). La pantalla es PantallaVuelo.

## Objetos que habilitan el mapa (AdjustmentsRoom: ObjetoEnMochila 186 → mapa1, 166 → gps).
const OBJETO_MAPA: int = 186
const OBJETO_GPS: int = 166
## Habilidad de campo de Vuelo (AttackHabExt).
const HABILIDAD: int = 1
## obj_pkmn_vuelo: sube y baja a 4 px por step (120 px/s); despega 100 steps y aterriza 30 después.
const VELOCIDAD: float = 120.0
const DESPEGUE: float = 100.0 / 30.0
const ESPERA_ATERRIZAJE: float = 1.0

static var _datos: Dictionary = {}


static func datos() -> Dictionary:
	if _datos.is_empty():
		var f: FileAccess = FileAccess.open("res://data/extraido/vuelo.json", FileAccess.READ)
		_datos = JSON.parse_string(f.get_as_text()) if f else {}
	return _datos


## MapaLugar: la región del mapa (0 Astra; 1-3 las demás; 4 donde no se vuela).
static func region(mapa: String) -> int:
	return int(datos().get("regiones", {}).get(mapa, 0))


## El mapa de afuera (en un interior, al que lleva la salida: global.room_out).
static func afuera() -> String:
	return GameState.mapa_salida if GameState.mapa_salida != "" else GameState.mapa_actual


## AdjustmentsRoom: entrar a una ciudad (o a su Centro Pokémon, por global.index_place) la marca.
static func marcar(mapa: String) -> void:
	var n: Variant = datos().get("centros", {}).get(str(GameState.indice_lugar)) if mapa == "Centro_Pokemon" \
		else datos().get("al_entrar", {}).get(mapa)
	if n != null and GameState.vuelo.get(int(n), 0) < 1:
		GameState.vuelo[int(n)] = 1


static func visitado(n: int) -> bool:
	return GameState.vuelo.get(n, 0) >= 1


## Las regiones que el jugador puede ver en el mapa (mapa2..mapa4 se dan con la historia).
static func regiones_abiertas() -> Array[int]:
	var r: Array[int] = [0]
	for k: int in [2, 3, 4]:
		if GameState.bandera("mapa%d" % k) == 1:
			r.append(k - 1)
	return r


## KeyActionsProta (tecla 2) + ProtaVuelo: las condiciones del original y, si se puede, la pantalla.
static func intentar(jugador: Jugador) -> void:
	if not GameState.tiene_medalla(4):
		return
	var r: int = region(GameState.mapa_actual)
	var texto: int = 0
	if GameState.mapa_salida != "":
		texto = 2406  # en un interior
	elif not GameState.objetos.has(OBJETO_MAPA):
		texto = 2408
	elif r in [1, 2, 3] and GameState.bandera("mapa%d" % (r + 1)) != 1:
		texto = [2409, 2410, 8528][r - 1]
	elif GameState.bandera("historia_manaphy") >= 5 or GameState.bandera("topsecretAntares") == 2:
		texto = 2411
	elif r == 4:
		texto = 2391
	if texto:
		await CajaDialogo.decir(jugador, Textos.linea("txt_dialog", texto))
		return
	if GameState.con_habilidad_campo(HABILIDAD) == null:
		await CuadroOriginal.mensaje(jugador, Textos.linea("txt_dialog", 2392))
		return
	var lugar: Dictionary = await PantallaVuelo.abrir(jugador, true)
	if not lugar.is_empty():
		await volar(jugador, lugar)


## PrepararVuelo + obj_pkmn_vuelo + PokemonVueloTransporte: el Pokémon sale, sube, pasan las horas
## (3 si cambia de región, 1 si no), el jugador aparece en la llegada y el Pokémon baja hasta él.
static func volar(jugador: Jugador, lugar: Dictionary) -> void:
	var p: PokemonInstance = GameState.con_habilidad_campo(HABILIDAD)
	if p == null:
		return
	if jugador.surfeando():
		jugador.terminar_surf()
	jugador.mira = 2
	jugador.process_mode = Node.PROCESS_MODE_DISABLED
	var s: AnimatedSprite2D = _sprite(p.especie, 8)
	jugador.get_parent().add_child(s)
	s.global_position = jugador.global_position + Vector2(0, -20)
	var t: Tween = s.create_tween()
	t.tween_property(s, "global_position:y", s.global_position.y - VELOCIDAD * DESPEGUE, DESPEGUE)
	await t.finished
	var mapa: String = str(lugar.mapa)
	if mapa != GameState.mapa_actual:
		Reloj.adelantar(3 if region(mapa) != region(GameState.mapa_actual) else 1)
	GameState.mapa_salida = ""
	await SceneManager.ir_a_mapa(mapa, Vector2(lugar.llegada[0], lugar.llegada[1]), 2)
	var nuevo: Jugador = DevConsole.jugador()
	if nuevo == null:
		return
	nuevo.process_mode = Node.PROCESS_MODE_DISABLED
	await nuevo.get_tree().create_timer(ESPERA_ATERRIZAJE).timeout
	var b: AnimatedSprite2D = _sprite(p.especie, 2)
	nuevo.get_parent().add_child(b)
	b.global_position = nuevo.global_position + Vector2(0, -200)
	t = b.create_tween()
	t.tween_property(b, "global_position", nuevo.global_position, 200.0 / VELOCIDAD)
	await t.finished
	b.queue_free()
	nuevo.process_mode = Node.PROCESS_MODE_INHERIT


## El Pokémon en el mapa (Begin_Sprite / Renew_Sprite): mirando arriba al subir, abajo al bajar.
static func _sprite(especie: PokemonData, mira: int) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = especie.cargar_sprite_frames()
	s.z_index = 10
	var anim: String = "mover_%d" % mira
	if s.sprite_frames and s.sprite_frames.has_animation(anim):
		s.play(anim)
	return s
