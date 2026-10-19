class_name DibujoDebug
extends Node2D
## Dibuja sobre el mapa (F4 en la consola dev): colisiones (rojo), NPCs (naranja), zonas de hierba
## (verde; barro marrón, hierba invisible cian, zonas de cueva con salvajes sin hierba en verde
## claro), agua (azul oscuro), salidas con su destino (azul) y marcadores sin convertir (amarillo).

const COLOR_PARED: Color = Color(1, 0.2, 0.2, 0.8)
const COLOR_NPC: Color = Color(1, 0.6, 0.1, 0.8)
const COLOR_HIERBA: Color = Color(0.2, 1, 0.3, 0.25)
const COLOR_BARRO: Color = Color(0.6, 0.4, 0.2, 0.35)
const COLOR_HIERBA_INVISIBLE: Color = Color(0.2, 0.9, 1, 0.3)
const COLOR_SIN_HIERBA: Color = Color(0.6, 1, 0.6, 0.12)
const COLOR_AGUA: Color = Color(0.1, 0.2, 0.8, 0.3)
const COLOR_SALIDA: Color = Color(0.3, 0.6, 1, 0.35)
const COLOR_MARCADOR: Color = Color(1, 0.9, 0.1, 0.9)
const TAMANO_TEXTO: int = 6


func _ready() -> void:
	z_index = 4096
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var mapa: Mapa = get_parent() as Mapa
	if mapa == null:
		return
	var fuente: Font = ThemeDB.fallback_font
	_formas(mapa.get_node("Paredes"), COLOR_PARED, false)
	for zona: String in ["ZonaHierba", "ZonaBarro", "ZonaHierbaInvisible"]:
		if mapa.has_node(zona):
			_formas(mapa.get_node(zona), {"ZonaHierba": COLOR_HIERBA, "ZonaBarro": COLOR_BARRO}.get(zona, COLOR_HIERBA_INVISIBLE), true)
	if mapa.has_node("Agua"):
		_formas(mapa.get_node("Agua"), COLOR_AGUA, true)
	var tabla: TablaEncuentros = TablaEncuentros.de_mapa(mapa.nombre_original)
	if tabla:
		for r: Rect2 in tabla.sin_hierba:
			draw_rect(r, COLOR_SIN_HIERBA)
	for n: Node in mapa.objetos().get_children():
		if n is Npc:
			_formas(n, COLOR_NPC, false)
		elif n is Salida:
			_salida(n as Salida, fuente)
	for s: Node in mapa.get_node("Salidas").get_children():
		_salida(s as Salida, fuente)
	for m: Node in mapa.get_node("Marcadores").get_children():
		var p: Vector2 = (m as Node2D).global_position
		draw_line(p - Vector2(3, 3), p + Vector2(3, 3), COLOR_MARCADOR)
		draw_line(p - Vector2(3, -3), p + Vector2(3, -3), COLOR_MARCADOR)
		draw_string(fuente, p + Vector2(4, -2), str(m.get_meta("objeto", m.name)), HORIZONTAL_ALIGNMENT_LEFT, -1, TAMANO_TEXTO, COLOR_MARCADOR)


func _formas(cuerpo: Node, color: Color, relleno: bool) -> void:
	for h: Node in cuerpo.get_children():
		var c: CollisionShape2D = h as CollisionShape2D
		if c and c.shape is RectangleShape2D:
			var tam: Vector2 = (c.shape as RectangleShape2D).size
			var r: Rect2 = Rect2(c.global_position - tam / 2.0, tam)
			draw_rect(r, color, relleno)


func _salida(s: Salida, fuente: Font) -> void:
	if s == null:
		return
	_formas(s, COLOR_SALIDA, true)
	var destino: String = "← volver" if s.volver else s.destino
	draw_string(fuente, s.global_position + _centro(s) + Vector2(-12, 0), destino, HORIZONTAL_ALIGNMENT_LEFT, -1, TAMANO_TEXTO, Color.WHITE)


func _centro(s: Salida) -> Vector2:
	for h: Node in s.get_children():
		if h is CollisionShape2D:
			return (h as CollisionShape2D).position
	return Vector2.ZERO
