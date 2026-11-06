class_name BattleHud
extends CanvasLayer
## HUD de batalla del original (DrawEventBattle1, DrawBattleAttacks, DrawMiniPokeball): los
## mismos sprites en las mismas coordenadas de la pantalla de 576×324, más el panel de mensajes.
## Se conecta solo por señales: lee los datos fijos al conectarse y luego escucha los cambios.

const UI: String = "res://assets/extraido/sprites/ui/"
const ESCALA_BARRA: float = 200.0 / 3.0
## Teclas que se muestran en la lista de ataques (Shift), como NameTecla del original.
const TECLAS: Array[String] = ["Z", "X", "C", "V"]
## draw_modifier: los nombres de cada stat (TextMenu 804-808, 2436 precisión, 2437 evasión).
const TEXTO_MODIFICADOR: Dictionary[int, int] = {1: 804, 2: 805, 3: 806, 4: 807, 5: 808, 6: 2436, 7: 2437}

## Lo que dibuja el panel de cada Pokémon.
class Lado:
	var nombre: String = ""
	var nivel: int = 1
	var hp: int = 0
	var hp_max: int = 1
	var energia: int = 0
	var energia_max: int = 1
	## Ids de tipo del original (frames de spr_gotype).
	var tipos: Array[int] = []
	var sexo: int = 0
	var estado: int = 0
	var exp_fraccion: float = 0.0
	var ataques: Array[MoveData] = []
	var debilitado: bool = false
	## Etapas que no son 0 (stat → valor; la precisión ya ×2 como la muestra el original).
	var modificadores: Dictionary[int, int] = {}
	var bp: BattlePokemon

var _jugador: Lado = Lado.new()
var _rival: Lado = Lado.new()
var _rival_entrenador: bool = false
var _mostrar_ataques: bool = false
## Con Ctrl (key_bt_tiempo): el tiempo de combate y los modificadores; con º (key_bt_show_pkmn), el equipo.
var _mostrar_tiempo: bool = false
var _mostrar_equipo: bool = false
var _tiempo: float = 0.0
var _equipo_jugador: Array = []
var _spr: Dictionary[String, SpriteOriginal] = {}
var _fuente_s: Font = load("res://assets/extraido/fonts/fuente_s.fnt")

@onready var _lienzo: Control = $Lienzo
@onready var _mensajes: PanelMensajes = $PanelMensajes
@onready var _resultado: Label = %Resultado


func _ready() -> void:
	_resultado.hide()
	# Solo los sprites del HUD (en la carpeta también están las hojas de iconos, muy grandes).
	for nombre: String in ["spr_barra_blue", "spr_barra_gray", "spr_barra_purple", "spr_barra_silver", "spr_barra_green",
			"spr_barra_red", "spr_barra_yellow", "spr_gotype", "spr_have", "spr_selhave", "spr_stat", "spr_team",
			"spr_mini_arrow", "spr_pkmnsex", "spr_pkmn_name1", "spr_pkmn_name2", "spr_simbolito_atfs",
			"spr_simbolito_atsp", "spr_simbolito_atst"]:
		if ResourceLoader.exists(UI + nombre + ".tres"):
			_spr[nombre] = load(UI + nombre + ".tres")
	_lienzo.draw.connect(_dibujar)


func conectar(jugador: BattlePokemon, rival: BattlePokemon, rival_entrenador: bool = false) -> void:
	_rival_entrenador = rival_entrenador
	for par: Array in [[_jugador, jugador], [_rival, rival]]:
		var lado: Lado = par[0]
		var bp: BattlePokemon = par[1]
		lado.bp = bp
		lado.nombre = bp.pokemon.apodo if bp.pokemon.apodo != "" else bp.pokemon.especie.nombre
		lado.nivel = bp.pokemon.nivel
		lado.tipos.assign(bp.pokemon.especie.tipos.map(func(t: Tipos.Tipo) -> int: return Tipos.ID_ORIGINAL[t]))
		lado.ataques = bp.pokemon.movimientos
		_on_hp(bp.pokemon.hp_actual, bp.hp_max, lado)
		_on_energia(bp.pokemon.energia_actual, bp.energia_max, lado)
		bp.hp_cambiado.connect(_on_hp.bind(lado))
		bp.energia_cambiada.connect(_on_energia.bind(lado))
		bp.ataco.connect(func(move: MoveData) -> void:
			_mensajes.agregar(Textos.par(Textos.batalla(195), lado.nombre, move.nombre)))
		bp.golpeado.connect(_on_golpeado.bind(lado))
		bp.movido.connect(_mensajes.on_pokemon_movido.bind(bp))


## AddTextToBuffer: una línea más en el panel de mensajes de abajo.
func mensaje(texto: String) -> void:
	_mensajes.agregar(texto)


## Entró otro Pokémon de un equipo: nombre, nivel, tipos y ataques del panel de su lado.
func cambiar_pokemon(bp: BattlePokemon) -> void:
	var lado: Lado = _jugador if bp.lado == 1 else _rival
	lado.nombre = bp.pokemon.apodo if bp.pokemon.apodo != "" else bp.pokemon.especie.nombre
	lado.nivel = bp.pokemon.nivel
	lado.tipos.assign(bp.pokemon.especie.tipos.map(func(t: Tipos.Tipo) -> int: return Tipos.ID_ORIGINAL[t]))
	lado.ataques = bp.pokemon.movimientos
	_on_hp(bp.pokemon.hp_actual, bp.hp_max, lado)
	_on_energia(bp.pokemon.energia_actual, bp.energia_max, lado)


func mostrar_resultado(texto: String) -> void:
	_resultado.text = texto
	_resultado.show()


## El equipo del jugador para la lista de la tecla º (DIBUJA_PKMN).
func poner_equipo(equipo: Array) -> void:
	_equipo_jugador = equipo


func _process(delta: float) -> void:
	_tiempo += delta
	var antes: Array = [_mostrar_ataques, _mostrar_tiempo, _mostrar_equipo]
	_mostrar_ataques = Input.is_action_pressed("mostrar_ataques")
	_mostrar_tiempo = Input.is_physical_key_pressed(KEY_CTRL)
	_mostrar_equipo = Input.is_physical_key_pressed(KEY_QUOTELEFT)
	var cambio: bool = antes != [_mostrar_ataques, _mostrar_tiempo, _mostrar_equipo] or _mostrar_tiempo
	# El estado y las etapas cambian por muchos lados: se leen del Pokémon en combate.
	for lado: Lado in [_jugador, _rival]:
		if not is_instance_valid(lado.bp) or lado.bp.pokemon == null:
			continue
		var mods: Dictionary[int, int] = {}
		for stat: int in range(1, 7):
			var v: int = lado.bp.etapa(stat) * (2 if stat == 6 else 1)
			if v != 0:
				mods[stat] = v
		if lado.estado != int(lado.bp.pokemon.estado) or mods != lado.modificadores:
			lado.estado = int(lado.bp.pokemon.estado)
			lado.modificadores = mods
			cambio = true
	if cambio:
		_lienzo.queue_redraw()


func _on_hp(hp: int, hp_max: int, lado: Lado) -> void:
	lado.hp = hp
	lado.hp_max = hp_max
	lado.debilitado = hp <= 0
	_lienzo.queue_redraw()


func _on_energia(energia: int, energia_max: int, lado: Lado) -> void:
	lado.energia = energia
	lado.energia_max = energia_max
	_lienzo.queue_redraw()


## Mensaje de Ataque1GolpeaPokemon2: "<movimiento> ha golpeado a <Pokémon>." + la eficacia.
func _on_golpeado(move: MoveData, _danio: int, eficacia: float, lado: Lado) -> void:
	if move == null:  # el autogolpe de la confusión ya avisó con su propio texto
		return
	var texto: String
	if eficacia == 0.0:
		texto = Textos.par(Textos.batalla(75), move.nombre, lado.nombre)
	else:
		texto = Textos.par(Textos.batalla(209), move.nombre, lado.nombre)
		if eficacia <= 0.25:
			texto += Textos.batalla(210)
		elif eficacia == 0.5:
			texto += Textos.batalla(211)
		elif eficacia == 2.0 or eficacia == 1.5:
			texto += Textos.batalla(212)
		elif eficacia >= 3.0:
			texto += Textos.batalla(213)
	_mensajes.agregar(texto)


func _dibujar() -> void:
	_panel(_jugador, 0.0, "spr_pkmn_name1")
	_panel(_rival, 224.0, "spr_pkmn_name2")
	_indicadores_ataques(_jugador)
	_equipo(Vector2(225, 5), Vector2(234, 10), _jugador)
	_spr["spr_team"].dibujar(_lienzo, 0, Vector2(449, 5))
	if _rival_entrenador:
		_mini_pokeballs(Vector2(458, 10), _rival)
	if _mostrar_equipo:
		_lista_equipo()
	elif _mostrar_ataques:
		_lista_ataques()
	elif _mostrar_tiempo:
		_panel_tiempo()


## Panel de un Pokémon; el del rival es el mismo desplazado 224 px.
func _panel(lado: Lado, dx: float, sprite: String) -> void:
	_spr[sprite].dibujar(_lienzo, 0, Vector2(176 + dx, 24))
	_texto(lado.nombre, Vector2(107 + dx, 9), HORIZONTAL_ALIGNMENT_LEFT, Color.BLACK)
	_texto(Textos.par(Textos.batalla(160), str(lado.nivel)), Vector2(215 + dx, 9), HORIZONTAL_ALIGNMENT_RIGHT, Color.BLACK)
	var porcentaje: float = 100.0 * lado.hp / lado.hp_max
	var barra: String = "spr_barra_green" if porcentaje >= 50.0 else "spr_barra_red" if porcentaje <= 15.0 else "spr_barra_yellow"
	_spr["spr_barra_gray"].dibujar(_lienzo, 0, Vector2(140 + dx, 25), Vector2(ESCALA_BARRA, 1))
	_spr[barra].dibujar(_lienzo, 0, Vector2(140 + dx, 25), Vector2(ESCALA_BARRA * maxi(lado.hp, 0) / lado.hp_max, 1))
	if lado == _jugador:
		_spr["spr_barra_blue"].dibujar(_lienzo, 0, Vector2(97, 43), Vector2(100.0 * lado.exp_fraccion, 1))
	_spr["spr_barra_silver"].dibujar(_lienzo, 0, Vector2(140 + dx, 33), Vector2(ESCALA_BARRA, 1))
	if lado.energia > 0:
		_spr["spr_barra_purple"].dibujar(_lienzo, 0, Vector2(140 + dx, 33),
			Vector2(ESCALA_BARRA * lado.energia / lado.energia_max, 1))
	var xs: Array[float] = [94.0, 107.0]
	if lado.tipos.size() == 1:
		xs = [100.0]
	for i: int in mini(lado.tipos.size(), 2):
		_spr["spr_gotype"].dibujar(_lienzo, lado.tipos[i], Vector2(xs[i] + dx, 29))
	_spr["spr_pkmnsex"].dibujar(_lienzo, lado.sexo, Vector2(117 + dx, 21))
	_spr["spr_stat"].dibujar(_lienzo, lado.estado, Vector2(106 + dx, 25))


## Símbolos de los 4 ataques bajo la caja del equipo (DrawBattleAttacks): la forma dice la
## categoría y el color si se puede usar (azul) o no alcanza la energía (gris).
func _indicadores_ataques(lado: Lado) -> void:
	for i: int in 4:
		var sprite: String = "spr_simbolito_atfs"
		var frame: int = 0
		if i < lado.ataques.size():
			var m: MoveData = lado.ataques[i]
			sprite = ["spr_simbolito_atfs", "spr_simbolito_atsp", "spr_simbolito_atst"][m.categoria]
			frame = 1 if m.costo_energia > lado.energia and lado.energia < lado.energia_max else 2
		_spr[sprite].dibujar(_lienzo, frame, Vector2(229 + 9 * i, 35))


func _equipo(caja: Vector2, primera: Vector2, lado: Lado) -> void:
	_spr["spr_team"].dibujar(_lienzo, 0, caja)
	_mini_pokeballs(primera, lado)
	_spr["spr_selhave"].dibujar(_lienzo, 0, primera)  # el Pokémon en combate


## Las 6 Poké Balls del equipo (DrawMiniPokeball): vacía, con vida o debilitado.
func _mini_pokeballs(primera: Vector2, lado: Lado) -> void:
	for i: int in 6:
		var frame: int = (2 if lado.debilitado else 1) if i == 0 else 0
		_spr["spr_have"].dibujar(_lienzo, frame, primera + Vector2(8 * (i % 3), 8 * floori(i / 3.0)))


## Con Shift: la lista de ataques con su tecla (DIBUJA_ATAQUES).
func _lista_ataques() -> void:
	var lineas: PackedStringArray = []
	for i: int in _jugador.ataques.size():
		lineas.append("%s - %s" % [TECLAS[i], _jugador.ataques[i].nombre])
	_lienzo.draw_rect(Rect2(103, 76, 97, 15 + 11 * lineas.size()), Color(0, 0, 0, 0.6))
	for i: int in lineas.size():
		_texto(lineas[i], Vector2(112, 80 + 11 * i), HORIZONTAL_ALIGNMENT_LEFT, Color(1, 1, 1, 0.9))


## Con º: el equipo con la tecla de cada uno (DIBUJA_PKMN: "1 - Pikachu").
func _lista_equipo() -> void:
	var lineas: PackedStringArray = []
	for i: int in _equipo_jugador.size():
		var p: PokemonInstance = _equipo_jugador[i]
		lineas.append("%d - %s" % [i + 1, Progreso.nombre(p)])
	_lienzo.draw_rect(Rect2(103, 76, 97, 15 + 11 * lineas.size()), Color(0, 0, 0, 0.6))
	for i: int in lineas.size():
		_texto(lineas[i], Vector2(112, 80 + 11 * i), HORIZONTAL_ALIGNMENT_LEFT, Color(1, 1, 1, 0.9))


## Con Ctrl (show_battle_time): el tiempo de combate (stringTime) y, de cada lado, las etapas que no
## son 0 con una flecha por etapa (draw_modifier).
func _panel_tiempo() -> void:
	var s: int = 1 + floori(_tiempo)
	_lienzo.draw_rect(Rect2(248, 50, 80, 23), Color(0, 0, 0, 0.6))
	_texto("%02d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60], Vector2(288, 54), HORIZONTAL_ALIGNMENT_CENTER, Color(1, 1, 1, 0.9))
	for par: Array in [[_jugador, 103.0, 108.0], [_rival, 331.0, 336.0]]:
		var lado: Lado = par[0]
		if lado.modificadores.is_empty():
			continue
		_lienzo.draw_rect(Rect2(par[1], 50, 142, 15 + 11 * lado.modificadores.size()), Color(0, 0, 0, 0.6))
		var y: float = 54.0
		for stat: int in range(1, 8):
			if not lado.modificadores.has(stat):
				continue
			var v: int = lado.modificadores[stat]
			_texto(Textos.linea("txt_menu", TEXTO_MODIFICADOR[stat]), Vector2(par[2], y), HORIZONTAL_ALIGNMENT_LEFT, Color(1, 1, 1, 0.9))
			for i: int in absi(v):
				_spr["spr_mini_arrow"].dibujar(_lienzo, 0 if v > 0 else 1, Vector2(par[2] + 51 + 7 * i, y + 6),
					Vector2.ONE, Color(1, 1, 1, 0.8))
			y += 11.0


## draw_text del original: (x, y) es la esquina de arriba del texto, según la alineación.
func _texto(texto: String, pos: Vector2, alineacion: HorizontalAlignment, color: Color) -> void:
	var ancho: float = _fuente_s.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var x: float = pos.x - (ancho if alineacion == HORIZONTAL_ALIGNMENT_RIGHT else ancho / 2.0 if alineacion == HORIZONTAL_ALIGNMENT_CENTER else 0.0)
	_lienzo.draw_string(_fuente_s, Vector2(x, pos.y + _fuente_s.get_ascent(12)), texto,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
