class_name PantallaEquipo
extends CanvasLayer
## La pantalla del equipo del original (room PokemonMenu: MenuPokemonControl con DrawMainMenuPokemon y
## una obj_barrapokemon por Pokémon con DrawBarraPokemon), con el estilo de menú 1 (el de siempre):
## a la izquierda el Pokémon elegido y sus tipos; a la derecha las seis barras.
## Teclas (KeyActionsPokemonMenu): ↑/↓ eligen, Z abre las opciones, X sale; con "Mover" elegido, Z en
## otro Pokémon los cambia de lugar.

const UI: String = "res://assets/extraido/sprites/ui/"
const TAMANO: Vector2 = Vector2(320, 180)
## DrawBarraPokemon (estilo 1): la barra k va en (196, 20 + 24k).
const BARRA_X: float = 196.0
const BARRA_Y: float = 20.0
const BARRA_PASO: float = 24.0
## Colores de GM8 (BGR) del texto de la barra: normal, elegida, "mover" y "mover elegida".
const COLOR_NORMAL: int = 14145495
const COLOR_SOMBRA: int = 6316128

signal _cerrada

var _sel: int = 0
## (37).SEL: el que se está moviendo (-1 = ninguno).
var _mover: int = -1
var _ocupado: bool = false
var _lienzo: Node2D
var _fuente: Font
var _sprites: Dictionary[String, SpriteOriginal] = {}
var _fondo: Texture2D
var _iconos: Dictionary = {}


static func abrir(desde: Node) -> void:
	var p := PantallaEquipo.new()
	var arbol: SceneTree = desde.get_tree()
	arbol.root.add_child(p)
	var pausa_previa: bool = arbol.paused
	arbol.paused = true
	await p._cerrada
	arbol.paused = pausa_previa
	p.queue_free()


func _ready() -> void:
	layer = 105
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fuente = load("res://assets/extraido/fonts/fuente_s.fnt")
	_fondo = load(UI + "fondos/menu_pokemon.png")
	var f: FileAccess = FileAccess.open("res://data/extraido/pokemon/iconos.json", FileAccess.READ)
	_iconos = JSON.parse_string(f.get_as_text()) if f else {}
	_sel = maxi(0, GameState.equipo.find(GameState.pokemon_para_combatir()))
	_lienzo = Node2D.new()
	_lienzo.scale = get_viewport().get_visible_rect().size / TAMANO
	_lienzo.draw.connect(_dibujar)
	add_child(_lienzo)
	AudioManager.efecto_ui("snd_click")


func _sprite(nombre: String) -> SpriteOriginal:
	if nombre not in _sprites:
		var ruta: String = UI + SceneManager.snake(nombre) + ".tres"
		_sprites[nombre] = load(ruta) if ResourceLoader.exists(ruta) else null
	return _sprites[nombre]


func _texto(pos: Vector2, texto: String, color: int = 16777215, alineacion: int = 0) -> void:
	var x: float = pos.x
	if alineacion != 0:
		var ancho: float = _fuente.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, TextoGM.TAMANO).x
		x -= ancho if alineacion == 1 else ancho / 2.0
	TextoGM.con_sombra(_lienzo, _fuente, Vector2(x, pos.y), texto, TextoGM.color(color), TextoGM.color(COLOR_SOMBRA))


func _dibujar() -> void:
	# El fondo de la room (MenuPokemon: una tira de 1 px que se repite a lo ancho).
	if _fondo:
		_lienzo.draw_texture_rect(_fondo, Rect2(Vector2.ZERO, TAMANO), true)
	_panel_elegido()
	for k: int in GameState.equipo.size():
		_barra(k)
	# DrawMainMenuPokemon: el texto de abajo ("Elegir un Pokémon." o lo que se esté haciendo).
	var str_abajo: String = Textos.linea("txt_menu", 777) if _mover < 0 else \
		Textos.par(Textos.linea("txt_menu", 783), Progreso.nombre(GameState.equipo[_mover]))
	_texto(Vector2(15, 157), str_abajo)


## DrawMainMenuPokemon: el fondo del sprite grande, el Pokémon elegido y sus dos tipos.
func _panel_elegido() -> void:
	var fondo: SpriteOriginal = _sprite("spr_backPokemonBigSprite")
	if fondo:
		fondo.dibujar(_lienzo, 0, Vector2(4, 11))
	if _sel >= GameState.equipo.size():
		return
	var p: PokemonInstance = GameState.equipo[_sel]
	if p.especie.sprite:
		_lienzo.draw_texture(p.especie.sprite, Vector2(56, 64) - p.especie.sprite.get_size() / 2.0)
	var tipos: Array = p.especie.tipos.map(func(t: Tipos.Tipo) -> int: return FormulasBatalla.TIPO_ORIGINAL[t])
	for i: int in mini(tipos.size(), 2):
		var y: float = 119.0 if i == 0 else 138.0
		var c: Color = _color_tipo(tipos[i])
		# color_brightness(color, +30) de fondo y (color, -35) de borde.
		_lienzo.draw_rect(Rect2(9, y, 67, 17), c.lightened(30.0 / 255.0))
		_lienzo.draw_rect(Rect2(9, y, 67, 17), c.darkened(35.0 / 255.0), false)
		var icono: SpriteOriginal = _sprite("spr_gotype")
		if icono:
			icono.dibujar(_lienzo, tipos[i], Vector2(11, y + 3))
		# DrawTipoName: el nombre (TipoName: TextBattle 4 + tipo) centrado, de su color con sombra negra.
		var nombre: String = Textos.batalla(4 + tipos[i])
		var ancho: float = _fuente.get_string_size(nombre, HORIZONTAL_ALIGNMENT_LEFT, -1, TextoGM.TAMANO).x
		TextoGM.con_sombra(_lienzo, _fuente, Vector2(48 - ancho / 2.0, y + 1), nombre, c, Color.BLACK)


## TipoColor del original.
static func _color_tipo(t: int) -> Color:
	const COLORES: Dictionary[int, Color] = {1: Color8(152, 156, 158), 2: Color8(255, 162, 81), 3: Color8(101, 175, 212),
		4: Color8(91, 192, 108), 5: Color8(247, 221, 96), 6: Color8(211, 197, 146), 7: Color8(216, 66, 92),
		8: Color8(215, 142, 95), 9: Color8(251, 134, 134), 10: Color8(178, 98, 207), 11: Color8(164, 198, 45),
		12: Color8(134, 216, 208), 13: Color8(105, 110, 124), 14: Color8(85, 148, 161), 15: Color8(157, 183, 231),
		16: Color8(85, 104, 170), 17: Color8(8, 104, 195), 18: Color8(243, 164, 227), 19: Color8(89, 193, 182)}
	return COLORES.get(t, Color.GRAY)


## DrawBarraPokemon (estilo impar): la barra con su frame (0 normal, 1 elegida, 4/5 moviendo), el
## nombre, el nivel, los PS con su barra, el estado, el sexo, el icono, el objeto y la ball del que
## combate.
func _barra(k: int) -> void:
	var p: PokemonInstance = GameState.equipo[k]
	var pos := Vector2(BARRA_X, BARRA_Y + BARRA_PASO * k)
	var frame: int = 1 if _sel == k else 0
	if _mover == k:
		frame = 5 if _sel == k else 4
	var color: int = COLOR_NORMAL if frame == 0 else 16777215
	if frame == 4:
		color = 8454143
	elif frame == 5:
		color = 65535  # c_yellow
	var barra: SpriteOriginal = _sprite("spr_barrapokemon1")
	if barra:
		barra.dibujar(_lienzo, frame, pos)
	_texto(pos + Vector2(-39, -12), Progreso.nombre(p), color)
	_texto(pos + Vector2(-33, -2), Textos.par(Textos.linea("txt_menu", 790), str(p.nivel)), color)
	var hp_max: int = p.calcular_stats()["hp"]
	_texto(pos + Vector2(53, -2), "%d/%d" % [p.hp_actual, hp_max], color)
	var pct: float = 100.0 * p.hp_actual / maxf(hp_max, 1)
	var spr_barra: SpriteOriginal = _sprite("spr_barra_green" if pct >= 50 else "spr_barra_red" if pct <= 15 else "spr_barra_yellow")
	if spr_barra:
		spr_barra.dibujar(_lienzo, 0, pos + Vector2(45, -5), Vector2(48.0 * p.hp_actual / maxf(hp_max, 1), 0.8))
	var stat: SpriteOriginal = _sprite("spr_stat")
	if stat:
		stat.dibujar(_lienzo, int(p.estado), pos + Vector2(39, 6))
	var sexo: SpriteOriginal = _sprite("spr_pkmnsex")
	if sexo:
		sexo.dibujar(_lienzo, p.sexo, pos + Vector2(7, 2))
	var icono: Array = _iconos.get(str(p.especie.id_original), [])
	if icono.size() == 2 and _sprite(icono[0]):
		_sprite(icono[0]).dibujar(_lienzo, int(icono[1]), pos + Vector2(-59, 0))
	if p.objeto != 0:
		_icono_objeto(p.objeto, pos + Vector2(105, 0))
	if p == GameState.pokemon_para_combatir():
		var ball: SpriteOriginal = _sprite("spr_nanoball")
		if ball:
			ball.dibujar(_lienzo, p.ball, pos + Vector2(90, 2))


## DrawIconItem: el icono de un objeto (hasta el 193 en spr_item_icon, 291-617 y 638-821 en los nuevos).
func _icono_objeto(id: int, pos: Vector2) -> void:
	var s: SpriteOriginal = null
	var frame: int = 0
	if id <= 193:
		s = _sprite("spr_item_icon")
		frame = id
	elif (id >= 291 and id <= 617) or (id >= 638 and id <= 821):
		s = _sprite("spr_item_icon_nuevos")
		frame = id - 290
	if s:
		s.dibujar(_lienzo, frame, pos)


func _input(evento: InputEvent) -> void:
	if _ocupado:
		return
	get_viewport().set_input_as_handled()
	if not (evento is InputEventKey and evento.pressed and not evento.echo):
		return
	var n: int = GameState.equipo.size()
	match evento.physical_keycode:
		KEY_UP:
			_sel = (_sel - 1 + n) % maxi(n, 1)
		KEY_DOWN:
			_sel = (_sel + 1) % maxi(n, 1)
		KEY_X, KEY_ESCAPE:
			if _mover >= 0:
				_mover = -1
			else:
				_cerrada.emit()
				return
		KEY_Z, KEY_ENTER, KEY_KP_ENTER:
			_accion()
	_lienzo.queue_redraw()


## KeyActionsPokemonMenu (Z): moviendo, cambia de lugar; si no, las opciones del original (Datos,
## Mover, Dar/Quitar Ítem, Salir).
func _accion() -> void:
	if _sel >= GameState.equipo.size():
		return
	if _mover >= 0:
		if _mover != _sel:
			var p: PokemonInstance = GameState.equipo[_mover]
			GameState.equipo[_mover] = GameState.equipo[_sel]
			GameState.equipo[_sel] = p
		_mover = -1
		return
	_ocupado = true
	var p_sel: PokemonInstance = GameState.equipo[_sel]
	var opciones: Array[int] = [764, 765, 2388 if p_sel.objeto != 0 else 2387, 78]
	var i: int = await MenuLista.elegir(self, Textos.linea("txt_menu", 776),
		opciones.map(func(o: int) -> Dictionary: return {"texto": Textos.linea("txt_menu", o)}))
	match opciones[i] if i >= 0 else -1:
		764: await FichaPokemon.abrir(self, p_sel)
		765: _mover = _sel
		2387, 2388: await MenuEquipo._objeto(self, p_sel)
	_ocupado = false
	_lienzo.queue_redraw()
