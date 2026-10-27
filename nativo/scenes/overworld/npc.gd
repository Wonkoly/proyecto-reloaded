class_name Npc
extends StaticBody2D
## Un NPC del original (obj_people: obj_Talk, obj_NoPass...), creado por CreateNPC* o puesto en la room.
## Como obj_Talk:
## - Habla (KeyActionsTalk + TalkHabla): con Z, si el jugador lo mira de frente (alineado a menos de
##   6 px y a menos de `distancia` px) o lo toca; se gira hacia él, dice su texto (CajaDialogo) y no
##   vuelve a hablar en 30 steps. Si tiene mira_fija, 10 steps después vuelve a mirar hacia ahí.
## - Mira a otro lado de vez en cuando (TalkSetSprite: 1/200 por step, si no tiene mira fija).
## - Si se_mueve (MOVE) camina (TalkSetMovimiento: 1 % por step; de esas, 20 % solo se gira y el resto
##   da un paso de 16 px a 2 px/step si el camino está libre: People_PasoN).
## obj_NoPass (NoPassStepActions): si el jugador entra en la zona que vigila (según hacia dónde mira y
## el paso que cierra, hasta `distancia` px) sale un "!", el jugador lo mira, habla y lo hace retroceder
## 10 steps a 4 px/step en la dirección de no_pasar (NoPassMueveProta).
## obj_Entrenador (EntrenadorStepActions): mira en línea recta hasta `distancia` px (4 px de ancho,
## sin paredes ni agua en medio); si ve al jugador lo congela, "!", camina hacia él a 3 px/step hasta
## quedar al lado y corre su evento (el reto y el combate). También al hablarle.
## Cualquier NPC con evento (data/eventos/ o data/extraido/eventos/, ver Eventos) lo corre en lugar de
## decir su texto: así se cambia la historia sin tocar el código.
## Los NPC "estáticos" (sin sprINDEX o de 1211 a 1299) tienen un solo sprite de 3 frames: arriba,
## lado y abajo (TalkSetSprite).

const STEPS_POR_SEGUNDO: float = 30.0
## Lo que frena a un NPC que camina: paredes (y otros NPC), el jugador y el agua.
const MASCARA_CAMINAR: int = 1 | 16 | 64
## TextDialog(2439): lo que dice un obj_Talk sin texto propio (DefineTalk).
const TEXTO_POR_DEFECTO: int = 2439
const EXCLAMACION: String = "res://assets/extraido/sprites/ui/spr_exc.tres"
## vk_left, vk_up, vk_right, vk_down → dirección.
const DIR_TECLA: Dictionary[int, Vector2] = {37: Vector2.LEFT, 38: Vector2.UP, 39: Vector2.RIGHT, 40: Vector2.DOWN}

@export var sprite_abajo: SpriteOriginal
@export var sprite_arriba: SpriteOriginal
@export var sprite_derecha: SpriteOriginal
## Notación de teclado numérico (2 abajo, 8 arriba, 4 izquierda, 6 derecha).
@export var mira: int = 2
## mirafijo: hacia dónde vuelve a mirar después de hablar (-1 = a ningún lado: mira al azar).
@export var mira_fija: int = -1
## MOVE en el original: camina solo.
@export var se_mueve: bool = false
## Línea de txt_dialog con lo que dice (0 = nada) y sus $par1$, $par2$...
@export var dialogo: int = 0
@export var dialogo_parametros: PackedStringArray = PackedStringArray()
## Texto armado en el código del original (en lugar de una línea de txt_dialog).
@export var texto_fijo: String = ""
## Nombre del cuadro de diálogo (name); si no, el de su sprINDEX.
@export var nombre: String = ""
## sprINDEX: de quién es el sprite, el nombre y el retrato del diálogo (-1 = ninguno).
@export var sprindex: float = -1.0
## Distancia máxima para hablarle (px entre los bordes; obj_Talk: 10).
@export var distancia: float = 10.0
## nopass (obj_NoPass): la tecla de la dirección que no deja pasar (vk_left = 37...); 0 = ninguna.
@export var no_pasar: int = 0
## INDEX del entrenador (obj_Entrenador; 0 = no es entrenador): su equipo en Datos.entrenador().
@export var entrenador: int = 0
@export var objeto_original: String = ""

var _acumulado: float = 0.0
var _frame: float = 1.0
var _hablando: bool = false
## Steps sin poder volver a hablar (alarm[1] = 30) y hasta volver a mira_fija (alarm[2] = 10).
var _espera_hablar: int = 0
var _espera_mira: int = 0
## Paso en curso: dirección y px que faltan (People_PasoN: 8 steps de 2 px).
var _dir_paso: Vector2 = Vector2.ZERO
var _pasos: int = 0
var _exclamacion: bool = false
## Entrenador que vio al jugador y camina hacia él (PILLA).
var _yendo: Jugador


func _ready() -> void:
	if nombre == "$rival$":
		_vestir_rival()
	add_to_group("npcs")
	collision_mask = MASCARA_CAMINAR
	queue_redraw()


## El rival se ve como el protagonista que es (global.spr_rivalD/U/R; IndexRivalGrande: 1000 + índice).
func _vestir_rival() -> void:
	var tabla: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/extraido/personajes.json"))
	var nombres: Variant = tabla.get("protagonistas", {}).get(str(GameState.rival_personaje)) if tabla is Dictionary else null
	if nombres is Array and nombres.size() == 3:
		var base: String = "res://assets/extraido/sprites/overworld/%s.tres"
		sprite_abajo = load(base % nombres[0])
		sprite_arriba = load(base % nombres[1])
		sprite_derecha = load(base % nombres[2])
	sprindex = 1000.0 + GameState.rival_personaje


## Su evento (Eventos.de_nodo), o null.
func evento() -> Evento:
	var mapa: Mapa = get_tree().current_scene as Mapa
	return Eventos.de_nodo(mapa.nombre_original, name) if mapa else null


## Lo que dice (con sus parámetros), o "" si no habla.
func texto() -> String:
	var t: String = texto_fijo
	if dialogo > 0:
		t = Textos.linea("txt_dialog", dialogo)
	elif t == "" and objeto_original == "obj_Talk":
		t = Textos.linea("txt_dialog", TEXTO_POR_DEFECTO)
	return CajaDialogo.preparar(t, dialogo_parametros) if t != "" else ""


func es_estatico() -> bool:
	return sprindex < 0.0 or (sprindex >= 1211.0 and sprindex <= 1299.0 and sprindex != 1294.0)


## KeyActionsTalk: si el jugador lo mira de frente o lo toca. Devuelve hacia dónde se giraría el NPC
## (0 = no habla, -1 = habla sin girarse).
func responde_a(jugador: Jugador) -> int:
	if _hablando or _espera_hablar > 0 or _yendo or (texto() == "" and evento() == null):
		return 0
	var p: Vector2 = jugador.global_position
	var n: Vector2 = global_position
	var cerca: bool = _distancia_a(jugador) < distancia
	if absf(p.x - n.x) < 6.0 and jugador.mira == 8 and p.y > n.y and cerca:
		return 2
	if absf(p.x - n.x) < 6.0 and jugador.mira == 2 and p.y < n.y and cerca:
		return 8
	if absf(p.y - n.y) < 6.0 and jugador.mira in [3, 6, 9] and p.x < n.x and cerca:
		return 4
	if absf(p.y - n.y) < 6.0 and jugador.mira in [1, 4, 7] and p.x > n.x and cerca:
		return 6
	if _rect().intersects(_rect_de(jugador)):
		return -1
	return 0


## TalkHabla.
func hablar(nueva_mira: int) -> void:
	_hablando = true
	if nueva_mira > 0:
		mira = nueva_mira
		_frame = 1.0
		queue_redraw()
	_espera_hablar = 30
	if mira_fija != -1:
		_espera_mira = 10
	var e: Evento = evento()
	if e:
		await Eventos.ejecutar(e, self)
	else:
		await CajaDialogo.decir(self, texto(), sprindex, nombre)
	if is_instance_valid(self):
		_hablando = false


## ExclamationEffect: "!" sobre la cabeza medio segundo (el juego se congela) y una pausa.
func exclamacion() -> void:
	var arbol: SceneTree = get_tree()
	var pausa_previa: bool = arbol.paused
	arbol.paused = true
	_exclamacion = true
	queue_redraw()
	await arbol.create_timer(0.5, true, false, true).timeout
	_exclamacion = false
	queue_redraw()
	await arbol.create_timer(0.2, true, false, true).timeout
	arbol.paused = pausa_previa


## Mira hacia un punto (en 4 direcciones).
func mirar_a(punto: Vector2) -> void:
	var d: Vector2 = punto - global_position
	mira = (6 if d.x > 0 else 4) if absf(d.x) > absf(d.y) else (2 if d.y > 0 else 8)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_acumulado += delta * STEPS_POR_SEGUNDO
	while _acumulado >= 1.0:
		_acumulado -= 1.0
		_paso()


func _paso() -> void:
	if _espera_hablar > 0:
		_espera_hablar -= 1
	if _espera_mira > 0:
		_espera_mira -= 1
		if _espera_mira == 0:
			mira = mira_fija
			queue_redraw()
	if _yendo:
		_ir_hacia_jugador()
		return
	if _hablando:
		return
	if _pasos > 0:
		_caminar()
		return
	if entrenador != 0:
		var j: Jugador = _jugador()
		if j and not Eventos.en_curso and _ve(j):
			_pillar(j)
		return
	if no_pasar != 0 and objeto_original == "obj_NoPass" and _espera_hablar == 0:
		var jugador: Jugador = _jugador()
		if jugador and _vigila(jugador):
			_detener(jugador)
		return
	if objeto_original != "obj_Talk":
		return
	# TalkSetSprite: quieto y sin mira fija, de vez en cuando mira a otro lado.
	if mira_fija == -1 and randi_range(1, 200) == 200:
		mira = 2 * randi_range(1, 4)
		queue_redraw()
	# TalkSetMovimiento.
	if se_mueve and sprindex >= 0.0 and randf() * 100.0 < 1.0:
		var dir: int = [2, 4, 6, 8].pick_random()
		if randf() * 100.0 < 20.0:
			mira = dir
			queue_redraw()
		else:
			_empezar_paso(dir)


## People_PasoN, step 0: si los 16 px de enfrente están libres, empieza a caminar hacia ahí.
func _empezar_paso(dir: int) -> void:
	var v: Vector2 = {2: Vector2.DOWN, 4: Vector2.LEFT, 6: Vector2.RIGHT, 8: Vector2.UP}[dir]
	if test_move(global_transform, v * 16.0):
		return
	mira = dir
	_dir_paso = v
	_pasos = 8


## People_PasoN, steps 1 y 2: 2 px por step, se frena si algo se cruza.
func _caminar() -> void:
	if test_move(global_transform, _dir_paso * 2.0):
		_pasos = 0
		_frame = 1.0
		queue_redraw()
		return
	position += _dir_paso * 2.0
	_pasos -= 1
	var s: SpriteOriginal = _sprite()
	_frame = fposmod(_frame + 0.2, s.frames.size()) if s and not s.frames.is_empty() else 1.0
	if _pasos == 0:
		_frame = 1.0
	queue_redraw()


## EntrenadorStepActions: en su línea de visión (cob = 4 px de cada lado, hasta `distancia`) y sin
## paredes ni agua entre los dos (collision_line a su altura, 8 px arriba y 8 abajo).
func _ve(j: Jugador) -> bool:
	var p: Vector2 = j.global_position
	var n: Vector2 = global_position
	var en_linea: bool = false
	match mira:
		2: en_linea = absf(p.x - n.x) < 4 and p.y > n.y and p.y - n.y < distancia
		4: en_linea = absf(p.y - n.y) < 4 and p.x < n.x and n.x - p.x < distancia
		6: en_linea = absf(p.y - n.y) < 4 and p.x > n.x and p.x - n.x < distancia
		8: en_linea = absf(p.x - n.x) < 4 and p.y < n.y and n.y - p.y < distancia
	if not en_linea:
		return false
	var espacio: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	for dy: float in [0.0, -8.0, 8.0]:
		var q := PhysicsRayQueryParameters2D.create(n + Vector2(0, dy), p + Vector2(0, dy), 1 | 64, [get_rid()])
		var choque: Dictionary = espacio.intersect_ray(q)
		if not choque.is_empty() and choque.collider is not Npc:
			return false
	return true


## Lo vio: "!", el jugador se queda quieto y el entrenador va hacia él.
func _pillar(j: Jugador) -> void:
	_hablando = true
	j.detener()
	await exclamacion()
	_yendo = j
	_hablando = false


## Camina 3 px/step hacia el jugador hasta quedar a menos de 5 px; entonces corre su evento.
func _ir_hacia_jugador() -> void:
	if _distancia_a(_yendo) < 5.0:
		var j: Jugador = _yendo
		_yendo = null
		_frame = 1.0
		j.mirar_a(global_position)
		hablar(-1)
		return
	var v: Vector2 = {2: Vector2.DOWN, 4: Vector2.LEFT, 6: Vector2.RIGHT, 8: Vector2.UP}.get(mira, Vector2.ZERO)
	var paso: Vector2 = v * minf(3.0, maxf(1.0, _distancia_a(_yendo) - 4.0))
	if test_move(global_transform, paso):
		var j2: Jugador = _yendo
		_yendo = null
		j2.mirar_a(global_position)
		hablar(-1)
		return
	position += paso
	var s: SpriteOriginal = _sprite()
	_frame = fposmod(_frame + 0.2, s.frames.size()) if s and not s.frames.is_empty() else 1.0
	queue_redraw()


func _jugador() -> Jugador:
	var mapa: Node = get_tree().current_scene
	return mapa.get_node_or_null("Objetos/Jugador") as Jugador if mapa else null


## NoPassStepActions: ¿el jugador está en la zona que vigila?
func _vigila(jugador: Jugador) -> bool:
	var p: Vector2 = jugador.global_position
	var n: Vector2 = global_position
	var d: float = distancia
	match mira_fija:
		2:
			if no_pasar == 39 and p.y > n.y and p.x < n.x + 5 and p.y - n.y < d: return true
			if no_pasar == 37 and p.y > n.y and p.x > n.x - 5 and p.y - n.y < d: return true
			return absf(p.x - n.x) < 5 and p.y > n.y and p.y - n.y < d
		4:
			if no_pasar == 38 and p.x < n.x and p.y > n.y - 5 and n.x - p.x < d: return true
			if no_pasar == 40 and p.x < n.x and p.y < n.y + 5 and n.x - p.x < d: return true
			return absf(p.y - n.y) < 5 and p.x < n.x and n.x - p.x < d
		6:
			if no_pasar == 38 and p.x > n.x and p.y > n.y - 5 and p.x - n.x < d: return true
			if no_pasar == 40 and p.x > n.x and p.y < n.y + 5 and p.x - n.x < d: return true
			return absf(p.y - n.y) < 5 and p.x > n.x and p.x - n.x < d
		8:
			if no_pasar == 39 and p.y < n.y and p.x < n.x + 5 and n.y - p.y < d: return true
			if no_pasar == 37 and p.y < n.y and p.x > n.x - 5 and n.y - p.y < d: return true
			return absf(p.x - n.x) < 5 and p.y < n.y and n.y - p.y < d
	return false


## ExclamationEffect + NoPassHabla + NoPassMueveProta.
func _detener(jugador: Jugador) -> void:
	_hablando = true
	var arbol: SceneTree = get_tree()
	arbol.paused = true  # el original se queda dentro de Sleep()
	_exclamacion = true
	queue_redraw()
	await arbol.create_timer(0.5, true, false, true).timeout
	_exclamacion = false
	queue_redraw()
	await arbol.create_timer(0.2, true, false, true).timeout
	arbol.paused = false
	# Refresh_Mira(point_direction(jugador → NPC)): el jugador lo mira (en 8 direcciones).
	var angulo: float = fposmod(rad_to_deg(-(global_position - jugador.global_position).angle()), 360.0)
	jugador.mira = [6, 9, 8, 7, 4, 1, 2, 3][int(fposmod(angulo + 22.5, 360.0) / 45.0) % 8]
	jugador.queue_redraw()
	await CajaDialogo.decir(self, texto(), sprindex, nombre)
	await arbol.create_timer(2.0 / STEPS_POR_SEGUNDO).timeout
	jugador.empujar(DIR_TECLA.get(no_pasar, Vector2.ZERO), 4.0 * STEPS_POR_SEGUNDO, 10.0 / STEPS_POR_SEGUNDO)
	_espera_hablar = 10
	_hablando = false


func _sprite() -> SpriteOriginal:
	if es_estatico():
		return sprite_abajo
	var s: SpriteOriginal = {2: sprite_abajo, 8: sprite_arriba, 4: sprite_derecha, 6: sprite_derecha}.get(mira, sprite_abajo)
	return s if s else sprite_abajo


func _draw() -> void:
	var s: SpriteOriginal = _sprite()
	if s == null:
		return
	# DrawPeople1: sombra (elipse negra al 30 % bajo los pies).
	var r: Rect2 = _rect()
	if r.size != Vector2.ZERO:
		var centro := Vector2(r.get_center().x, r.end.y + 2.0) - global_position
		draw_set_transform(centro, 0.0, Vector2(r.size.x / 2.0, 5.0))
		draw_circle(Vector2.ZERO, 1.0, Color(0, 0, 0, 0.3))
		draw_set_transform(Vector2.ZERO)
	var frame: int = int(_frame)
	var voltear: bool = mira == 4
	if es_estatico():
		frame = {8: 0, 4: 1, 6: 1, 2: 2}.get(mira, 2)
	s.dibujar(self, frame, Vector2.ZERO, Vector2(-1 if voltear else 1, 1))
	if _exclamacion and ResourceLoader.exists(EXCLAMACION):
		(load(EXCLAMACION) as SpriteOriginal).dibujar(self, 0, Vector2(0, -20))


## Rectángulo de colisión en el mapa (bbox del original).
func _rect() -> Rect2:
	return _rect_de(self)


static func _rect_de(cuerpo: Node2D) -> Rect2:
	var forma := cuerpo.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if forma == null or not forma.shape is RectangleShape2D:
		return Rect2(cuerpo.global_position, Vector2.ZERO)
	var tam: Vector2 = (forma.shape as RectangleShape2D).size
	return Rect2(forma.global_position - tam / 2.0, tam)


## distance_to_object: distancia entre los bordes de los dos rectángulos (0 si se tocan).
func _distancia_a(cuerpo: Node2D) -> float:
	var a: Rect2 = _rect()
	var b: Rect2 = _rect_de(cuerpo)
	var dx: float = maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dy: float = maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	return sqrt(dx * dx + dy * dy)
