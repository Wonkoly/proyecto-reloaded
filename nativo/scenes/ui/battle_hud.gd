class_name BattleHud
extends CanvasLayer
## HUD de batalla: HP y energía de los dos Pokémon y los 4 ataques del jugador.
## Se conecta solo por señales: lee los datos fijos (nombres, costos) al conectarse y luego
## escucha hp_cambiado, energia_cambiada y el fin de la batalla.

const COLOR_HP: Array[Color] = [Color("e05038"), Color("f8c030"), Color("58d058")]
const COLOR_ENERGIA: Color = Color("58a8f8")
const COLOR_FONDO_BARRA: Color = Color(0.1, 0.1, 0.12, 0.85)
const TECLAS: Array[String] = ["J", "K", "L", "Ñ"]

var _costos: Array[int] = []

@onready var _ataques: HBoxContainer = %Ataques
@onready var _resultado: Label = %Resultado


func _ready() -> void:
	_resultado.hide()
	for panel: Control in [%Jugador, %Rival]:
		_estilizar(panel.get_node("BarraHP"), COLOR_HP[2])
		_estilizar(panel.get_node("BarraEnergia"), COLOR_ENERGIA)


func conectar(jugador: BattlePokemon, rival: BattlePokemon) -> void:
	_conectar_panel(%Jugador, jugador)
	_conectar_panel(%Rival, rival)
	_crear_ataques(jugador)
	jugador.energia_cambiada.connect(_actualizar_ataques)
	_actualizar_ataques(jugador.pokemon.energia_actual, jugador.energia_max)


func mostrar_resultado(texto: String) -> void:
	_resultado.text = texto
	_resultado.show()


func _conectar_panel(panel: Control, bp: BattlePokemon) -> void:
	(panel.get_node("Nombre") as Label).text = "%s  Nv. %d" % [bp.pokemon.especie.nombre, bp.pokemon.nivel]
	var al_hp: Callable = _actualizar_hp.bind(panel)
	var al_energia: Callable = _actualizar_energia.bind(panel)
	bp.hp_cambiado.connect(al_hp)
	bp.energia_cambiada.connect(al_energia)
	al_hp.call(bp.pokemon.hp_actual, bp.hp_max)
	al_energia.call(bp.pokemon.energia_actual, bp.energia_max)


func _actualizar_hp(hp: int, hp_max: int, panel: Control) -> void:
	var barra: ProgressBar = panel.get_node("BarraHP")
	barra.max_value = hp_max
	barra.value = hp
	var fraccion: float = float(hp) / hp_max
	var color: Color = COLOR_HP[0] if fraccion <= 0.2 else COLOR_HP[1] if fraccion <= 0.5 else COLOR_HP[2]
	(barra.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = color
	(panel.get_node("BarraHP/Texto") as Label).text = "%d/%d" % [hp, hp_max]


func _actualizar_energia(energia: int, energia_max: int, panel: Control) -> void:
	var barra: ProgressBar = panel.get_node("BarraEnergia")
	barra.max_value = energia_max
	barra.value = maxi(energia, 0)
	(panel.get_node("BarraEnergia/Texto") as Label).text = "%d/%d" % [energia, energia_max]


func _crear_ataques(bp: BattlePokemon) -> void:
	for hijo: Node in _ataques.get_children():
		hijo.queue_free()
	_costos.clear()
	for i: int in bp.pokemon.movimientos.size():
		var m: MoveData = bp.pokemon.movimientos[i]
		var caja := PanelContainer.new()
		var fondo := StyleBoxFlat.new()
		fondo.bg_color = COLOR_FONDO_BARRA
		fondo.set_content_margin_all(3)
		caja.add_theme_stylebox_override("panel", fondo)
		caja.custom_minimum_size = Vector2(128, 0)
		var etiqueta := Label.new()
		etiqueta.text = "[%s] %s\n%d de energía" % [TECLAS[i], m.nombre, m.costo_energia]
		etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caja.add_child(etiqueta)
		_ataques.add_child(caja)
		_costos.append(m.costo_energia)


## Atenúa los ataques que no alcanza a pagar (salvo con la barra llena, como en el original).
func _actualizar_ataques(energia: int, energia_max: int) -> void:
	for i: int in _costos.size():
		var alcanza: bool = energia >= _costos[i] or energia >= energia_max
		(_ataques.get_child(i) as Control).modulate = Color.WHITE if alcanza else Color(1, 1, 1, 0.45)


func _estilizar(barra: ProgressBar, color: Color) -> void:
	var fondo := StyleBoxFlat.new()
	fondo.bg_color = COLOR_FONDO_BARRA
	var relleno := StyleBoxFlat.new()
	relleno.bg_color = color
	barra.add_theme_stylebox_override("background", fondo)
	barra.add_theme_stylebox_override("fill", relleno)
