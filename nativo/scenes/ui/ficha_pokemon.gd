class_name FichaPokemon
extends CanvasLayer
## La ficha de un Pokémon del original, con sus tres pantallas (rooms PkmnInfoMenu, PkmnHabMenu y
## PkmnMovMenu): información (DrawGeneralMenuPokemon), stats (DrawStatsMenuPokemon) y movimientos
## (DrawMovesMenuPokemon). → / ← pasan de una a otra (Info → Habil. → Mov.), X sale; en movimientos,
## Z elige uno para ver su potencia, tipo, categoría y descripción.

enum Pagina { INFO, STATS, MOVIMIENTOS }

const UI: String = "res://assets/extraido/sprites/ui/"
const TAMANO: Vector2 = Vector2(320, 180)
const FONDOS: Array[String] = ["menu_info_pokemon", "menu_hab_pokemon", "menu_batt_pokemon"]
const BLANCO: int = 16777215
const GRIS: int = 6316128  # sombra del texto claro
const OSCURO: int = 0  # texto oscuro...
const SOMBRA_OSCURO: int = 13160656  # ...con sombra clara
const ROJO: int = 255

signal _cerrada

var pokemon: PokemonInstance
var pagina: Pagina = Pagina.INFO
## SEL / AT de DrawMovesMenuPokemon: eligiendo un movimiento y cuál (0-3).
var _eligiendo: bool = false
var _ataque: int = 0
var _lienzo: Node2D
var _fuente_s: Font
var _fuente_stat: Font
var _sprites: Dictionary[String, SpriteOriginal] = {}
var _fondos: Dictionary[String, Texture2D] = {}


static func abrir(desde: Node, p: PokemonInstance) -> void:
	var f := FichaPokemon.new()
	f.pokemon = p
	var arbol: SceneTree = desde.get_tree()
	arbol.root.add_child(f)
	var pausa_previa: bool = arbol.paused
	arbol.paused = true
	await f._cerrada
	arbol.paused = pausa_previa
	f.queue_free()


func _ready() -> void:
	layer = 108
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fuente_s = load("res://assets/extraido/fonts/fuente_s.fnt")
	_fuente_stat = load("res://assets/extraido/fonts/fuente_stat.fnt")
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


## draw_text_shadow(x, y, texto, color, sombra): alineación 0 izquierda, 1 derecha, 2 centro.
func _t(pos: Vector2, texto: String, color: int = BLANCO, sombra: int = GRIS, alineacion: int = 0, stat: bool = true) -> void:
	var f: Font = _fuente_stat if stat else _fuente_s
	var x: float = pos.x
	if alineacion != 0:
		var ancho: float = f.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, TextoGM.TAMANO).x
		x -= ancho if alineacion == 1 else ancho / 2.0
	TextoGM.dibujar(_lienzo, f, Vector2(x + 1, pos.y + 1), texto, TextoGM.color(sombra))
	TextoGM.dibujar(_lienzo, f, Vector2(x, pos.y), texto, TextoGM.color(color))


func _dibujar() -> void:
	# Las texturas quedan guardadas: una local se libera al acabar el dibujado y se ve blanca.
	if FONDOS[pagina] not in _fondos:
		_fondos[FONDOS[pagina]] = load(UI + "fondos/%s.png" % FONDOS[pagina])
	var fondo: Texture2D = _fondos[FONDOS[pagina]]
	if fondo:
		_lienzo.draw_texture_rect(fondo, Rect2(Vector2.ZERO, TAMANO), false)
	var titulos: Array[int] = [792, 793, 794]
	_t(Vector2(6, 0), Textos.linea("txt_menu", titulos[pagina]))
	_t(Vector2(314, 0), Textos.par(Textos.linea("txt_menu", 795), "X"), BLANCO, GRIS, 1)
	_t(Vector2(6, 165), Textos.par(Textos.linea("txt_menu", 821), "Z"))
	# Las pantallas vecinas, en rojo abajo.
	if pagina != Pagina.INFO:
		_t(Vector2(146, 165), Textos.linea("txt_menu", titulos[pagina - 1]), ROJO, GRIS, 1)
	if pagina != Pagina.MOVIMIENTOS:
		_t(Vector2(174, 165), Textos.linea("txt_menu", titulos[pagina + 1]), ROJO)
	_panel_izquierdo()
	match pagina:
		Pagina.INFO: _info()
		Pagina.STATS: _stats()
		Pagina.MOVIMIENTOS: _movimientos()


## DrawGeneralMenuPokemon (parte izquierda): el Pokémon, número, nombre, nivel, mote, sexo y ball.
func _panel_izquierdo() -> void:
	var e: PokemonData = pokemon.especie
	if e.sprite and not (pagina == Pagina.MOVIMIENTOS and _eligiendo):
		_lienzo.draw_texture(e.sprite, Vector2(52, 69) - e.sprite.get_size() / 2.0)
	if pagina != Pagina.INFO:
		return
	var n: int = e.numero_pokedex
	var num: String = Textos.par(Textos.linea("txt_menu", 1164 if n >= 100 else 1165 if n >= 10 else 1166), str(n))
	if e.id_original < 100000:
		_t(Vector2(4, 116), num)
	_t(Vector2(104, 116), e.nombre, BLANCO, GRIS, 1)
	_t(Vector2(104, 129), Textos.par(Textos.linea("txt_menu", 1168), str(pokemon.nivel)), BLANCO, GRIS, 1)
	if pokemon.apodo != "" and pokemon.apodo != e.nombre:
		_t(Vector2(104, 142), pokemon.apodo, BLANCO, GRIS, 1)
	if _sprite("spr_pkmnsex"):
		_sprite("spr_pkmnsex").dibujar(_lienzo, pokemon.sexo, Vector2(30, 134))
	if _sprite("spr_ball"):
		_sprite("spr_ball").dibujar(_lienzo, pokemon.ball, Vector2(16, 138))


## DrawGeneralMenuPokemon (página 1): el entrenador original, cómo se obtuvo y el objeto.
func _info() -> void:
	_t(Vector2(116, 35), Textos.linea("txt_menu", 797))
	_t(Vector2(125, 23), Textos.linea("txt_menu", 796), BLANCO, GRIS, 0, false)
	_t(Vector2(125, 51), Textos.linea("txt_menu", 798), BLANCO, GRIS, 0, false)
	_t(Vector2(125, 133), Textos.linea("txt_menu", 799), BLANCO, GRIS, 0, false)
	_t(Vector2(143, 35), GameState.nombre_jugador, OSCURO, SOMBRA_OSCURO)
	_t(Vector2(213, 63), Textos.linea("txt_menu", 1875), OSCURO, SOMBRA_OSCURO, 2)
	for i: int in 4:
		_t(Vector2(122, 75 + [0, 14, 27, 40][i]), Textos.linea("txt_menu", 1885 + i), OSCURO, SOMBRA_OSCURO)
	_t(Vector2(310, 102), str(pokemon.nivel), GRIS, SOMBRA_OSCURO, 1)
	_t(Vector2(310, 115), nombre_ball(pokemon.ball), GRIS, SOMBRA_OSCURO, 1)
	if pokemon.objeto == 0:
		_t(Vector2(116, 145), Textos.linea("txt_menu", 1162), OSCURO, SOMBRA_OSCURO)
	else:
		_t(Vector2(132, 145), Inventario.nombre(pokemon.objeto), OSCURO, SOMBRA_OSCURO)


## NameBall: la ball por su índice (1-13 son los objetos 1-13, 15-26 los 472-483, 27 el 522).
static func nombre_ball(indice: int) -> String:
	var b: int = indice + 1
	if b >= 1 and b <= 13:
		return Inventario.nombre(b)
	if b == 14:
		return Textos.linea("txt_menu", 1421)
	if b >= 15 and b <= 26:
		return Inventario.nombre(b + 457)
	return Inventario.nombre(522) if b == 27 else ""


## DrawStatsMenuPokemon (página 1): tipos, stats, experiencia y su barra.
func _stats() -> void:
	var s: Dictionary = pokemon.calcular_stats()
	_t(Vector2(124, 20), Textos.linea("txt_menu", 800), BLANCO, GRIS, 0, false)
	_t(Vector2(231, 20), Textos.linea("txt_menu", 801), BLANCO, GRIS, 0, false)
	_t(Vector2(124, 52), Textos.linea("txt_menu", 802), BLANCO, GRIS, 0, false)
	_t(Vector2(124, 111), Textos.linea("txt_menu", 809), BLANCO, GRIS, 0, false)
	var tipos: Array = pokemon.especie.tipos.map(func(t: Tipos.Tipo) -> int: return FormulasBatalla.TIPO_ORIGINAL[t])
	for i: int in mini(tipos.size(), 2):
		var x0: float = 123.0 if i == 0 else 229.0
		var ancho: float = 76.0 if i == 0 else 74.0
		var c: Color = PantallaEquipo._color_tipo(tipos[i])
		_lienzo.draw_rect(Rect2(x0, 34, ancho, 15), c.lightened(30.0 / 255.0))
		_lienzo.draw_rect(Rect2(x0, 34, ancho, 15), c.darkened(35.0 / 255.0), false)
		if _sprite("spr_gotype"):
			_sprite("spr_gotype").dibujar(_lienzo, tipos[i], Vector2(x0 + 2, 36))
		var nombre: String = Textos.batalla(4 + tipos[i])
		TextoGM.con_sombra(_lienzo, _fuente_stat, Vector2(x0 + 40 - _fuente_stat.get_string_size(nombre,
			HORIZONTAL_ALIGNMENT_LEFT, -1, TextoGM.TAMANO).x / 2.0, 34), nombre, c, Color.BLACK)
	var filas: Array = [[138, 63, 803, "hp", 212, 63], [138, 74, 815, "", 212, 74], [138, 85, 804, "ataque", 212, 85],
		[138, 96, 805, "defensa", 212, 96], [240, 64, 806, "ataque_esp", 314, 64], [240, 80, 807, "defensa_esp", 314, 80],
		[240, 96, 808, "velocidad", 314, 96]]
	for f: Array in filas:
		_t(Vector2(f[0], f[1]), Textos.linea("txt_menu", f[2]), BLANCO, GRIS, 2, false)
		var valor: String
		if f[3] == "hp":
			valor = "%d/%d" % [pokemon.hp_actual, s["hp"]] if pokemon.hp_actual != s["hp"] else str(s["hp"])
		elif f[3] == "":
			var maximo: int = pokemon.calcular_energia_maxima()
			valor = "%d/%d" % [pokemon.energia_actual, maximo] if pokemon.energia_actual != maximo else str(maximo)
		else:
			valor = str(s[f[3]])
		_t(Vector2(f[4], f[5]), valor, OSCURO, SOMBRA_OSCURO, 1)
	_t(Vector2(118, 123), Textos.linea("txt_menu", 810))
	_t(Vector2(118, 139), Textos.linea("txt_menu", 811))
	_t(Vector2(314, 123), str(pokemon.experiencia), OSCURO, SOMBRA_OSCURO, 1)
	if pokemon.nivel < 100:
		_t(Vector2(314, 139), str(pokemon.exp_para_nivel(pokemon.nivel + 1) - pokemon.experiencia), OSCURO, SOMBRA_OSCURO, 1)
		var antes: int = pokemon.exp_para_nivel(pokemon.nivel)
		var tramo: int = maxi(pokemon.exp_para_nivel(pokemon.nivel + 1) - antes, 1)
		if _sprite("spr_barra_blue"):
			_sprite("spr_barra_blue").dibujar(_lienzo, 0, Vector2(248, 157), Vector2(64.0 * (pokemon.experiencia - antes) / tramo, 1))
	else:
		_t(Vector2(314, 139), Textos.linea("txt_menu", 813), OSCURO, SOMBRA_OSCURO, 1)
	_t(Vector2(225, 156), Textos.linea("txt_menu", 812), 49151)


## DrawMovesMenuPokemon: los cuatro movimientos con su tipo y energía, la habilidad y, eligiendo
## uno, su potencia, categoría, tipo y descripción.
func _movimientos() -> void:
	_t(Vector2(7, 129), Textos.linea("txt_menu", 819))
	_t(Vector2(7, 145), Textos.linea("txt_menu", 820))
	_t(Vector2(125, 18), Textos.linea("txt_menu", 814), BLANCO, GRIS, 0, false)
	_t(Vector2(125, 91), Textos.linea("txt_menu", 816), BLANCO, GRIS, 0, false)
	_t(Vector2(125, 119), Textos.linea("txt_menu", 817), BLANCO, GRIS, 0, false)
	_t(Vector2(17, 117), Textos.linea("txt_menu", 818), BLANCO, GRIS, 0, false)
	for i: int in 4:
		_t(Vector2(281, 30 + i * 16), Textos.linea("txt_menu", 815), OSCURO, SOMBRA_OSCURO, 0, false)
		if i >= pokemon.movimientos.size():
			_t(Vector2(129, 29 + i * 16), "-")
			_t(Vector2(314, 29 + i * 16), "--", OSCURO, SOMBRA_OSCURO, 1)
			continue
		var m: MoveData = pokemon.movimientos[i]
		var tipo: int = FormulasBatalla.TIPO_ORIGINAL[m.tipo]
		if _sprite("spr_gotype"):
			_sprite("spr_gotype").dibujar(_lienzo, tipo, Vector2(113, 31 + i * 16))
		_t(Vector2(129, 29 + i * 16), m.nombre)
		_t(Vector2(314, 29 + i * 16), str(m.costo_energia) if m.costo_energia else "--", OSCURO, SOMBRA_OSCURO, 1)
	var hab: int = pokemon.habilidad()
	_t(Vector2(118, 103), Habilidades.nombre(hab) if hab > 0 else "-", OSCURO, SOMBRA_OSCURO)
	if not _eligiendo or _ataque >= pokemon.movimientos.size():
		return
	var m: MoveData = pokemon.movimientos[_ataque]
	var t: int = FormulasBatalla.TIPO_ORIGINAL[m.tipo]
	if _sprite("spr_SelAttack"):
		_sprite("spr_SelAttack").dibujar(_lienzo, 0, Vector2(112, 30 + _ataque * 16))
	_t(Vector2(101, 129), str(m.poder) if m.poder else "--", OSCURO, SOMBRA_OSCURO, 1)
	if _sprite("spr_type2"):
		_sprite("spr_type2").dibujar(_lienzo, int(m.categoria), Vector2(83, 145))
	if _sprite("spr_gobigtype"):
		_sprite("spr_gobigtype").dibujar(_lienzo, t, Vector2(32, 46))
	var nombre: String = Textos.batalla(4 + t)
	TextoGM.con_sombra(_lienzo, _fuente_stat, Vector2(53 - _fuente_stat.get_string_size(nombre, HORIZONTAL_ALIGNMENT_LEFT, -1,
		TextoGM.TAMANO).x / 2.0, 94), nombre, PantallaEquipo._color_tipo(t), Color.BLACK)
	var desc: String = TextoGM.ajustar(m.descripcion, 194, _fuente_stat)
	_t(Vector2(118, 132), desc, OSCURO, SOMBRA_OSCURO)


func _input(evento: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if not (evento is InputEventKey and evento.pressed and not evento.echo):
		return
	match evento.physical_keycode:
		KEY_X, KEY_ESCAPE, KEY_SPACE:
			if _eligiendo:
				_eligiendo = false
			else:
				_cerrada.emit()
				return
		KEY_RIGHT:
			if not _eligiendo and pagina < Pagina.MOVIMIENTOS:
				pagina = (pagina + 1) as Pagina
		KEY_LEFT:
			if not _eligiendo and pagina > Pagina.INFO:
				pagina = (pagina - 1) as Pagina
		KEY_Z, KEY_ENTER:
			if pagina == Pagina.MOVIMIENTOS and not pokemon.movimientos.is_empty():
				_eligiendo = not _eligiendo
		KEY_UP:
			if _eligiendo:
				_ataque = (_ataque - 1 + pokemon.movimientos.size()) % pokemon.movimientos.size()
		KEY_DOWN:
			if _eligiendo:
				_ataque = (_ataque + 1) % pokemon.movimientos.size()
	_lienzo.queue_redraw()
