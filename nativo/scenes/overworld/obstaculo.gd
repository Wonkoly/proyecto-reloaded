class_name Obstaculo
extends StaticBody2D
## Un obstáculo que se quita con una MO: arbusto (obj_arbusto, Corte), roca (obj_roca, Golpe Roca) o
## roca redonda (obj_roca_redonda, Fuerza: se empuja) o torbellino (obj_torbellino: surfeando, con Z).
## Al volver al mapa reaparece, como en el original (las rooms no son persistentes), salvo los que
## tienen bandera propia. Lo usa el Jugador con Z o con la tecla de la MO.

## InteractionArbusto / InteractionRocaFragmentada / InteractionRocaRedonda: texto, texto si no hay
## Pokémon que sepa la MO, medalla que pide (MEDALLA_STAR), habilidad de campo y tecla.
const MO: Dictionary[String, Dictionary] = {
	"corte": {"texto": 53, "falta": 54, "medalla": 2, "habilidad": 0, "tecla": KEY_1},
	"golpe_roca": {"texto": 55, "falta": 56, "medalla": 1, "habilidad": 5, "tecla": KEY_6},
	"fuerza": {"texto": 58, "falta": 59, "medalla": 5, "habilidad": 3, "tecla": KEY_4},
	"torbellino": {"texto": 62, "falta": 63, "medalla": 6, "habilidad": 11, "tecla": KEY_NONE},
}
## EfectoTorbellino: gira 4° por step; al quitarlo se desvanece 0.01 por step desde 0.8.
const GIRO_TORBELLINO: float = 120.0
## InteractionArbusto: el texto propio de cada variante (las demás del arbusto no dicen nada).
const TEXTO_OBJETO: Dictionary[String, int] = {"obj_arbusto": 53, "obj_telaraniaCortable": 14211}
## Capas contra las que choca la roca empujada: paredes, jugador y agua.
const MASCARA_EMPUJE: int = 1 | 16 | 64

@export var sprite: SpriteOriginal
@export var mo: String = "corte"
@export var objeto_original: String = ""
@export var escala: Vector2 = Vector2.ONE

var _ocupado: bool = false
var _angulo: float = 360.0  # DefineTorbellino: angle = 360


func _ready() -> void:
	set_process(mo == "torbellino")
	if mo == "torbellino":
		modulate.a = 0.8


func _process(delta: float) -> void:
	_angulo += GIRO_TORBELLINO * delta
	queue_redraw()


func _draw() -> void:
	if sprite:
		sprite.dibujar(self, 0, Vector2.ZERO, escala, Color.WHITE, _angulo if mo == "torbellino" else 0.0)


func rect() -> Rect2:
	var forma: CollisionShape2D = get_node_or_null("forma")
	if forma == null or not (forma.shape is RectangleShape2D):
		return Rect2(global_position, Vector2(16, 16))
	var tam: Vector2 = (forma.shape as RectangleShape2D).size
	return Rect2(forma.global_position - tam / 2.0, tam)


## KeyActionsCorte y compañía: el jugador a menos de 10 px, mirando hacia el obstáculo y alineado.
func frente_a(pos: Vector2, mira: int) -> bool:
	var r: Rect2 = rect()
	var centro: Vector2 = r.get_center()
	if not r.grow(10.0).has_point(pos):
		return false
	match mira:
		8: return pos.y > centro.y and absf(pos.x - centro.x) < 12.0
		2: return pos.y < centro.y and absf(pos.x - centro.x) < 12.0
		6, 3, 9: return pos.x < centro.x and absf(pos.y - centro.y) < 12.0
		4, 1, 7: return pos.x > centro.x and absf(pos.y - centro.y) < 12.0
	return false


func tecla() -> Key:
	return MO[mo].tecla


## El texto del obstáculo; con la medalla y un Pokémon que sepa la MO, la usa.
func usar(desde: Node) -> void:
	if _ocupado:
		return
	var jugador: Jugador = desde as Jugador
	if mo == "torbellino" and not (jugador and jugador.surfeando()):
		return  # InitializeTorbellino: solo surfeando
	_ocupado = true
	var d: Dictionary = MO[mo]
	var texto: int = TEXTO_OBJETO.get(objeto_original, 0) if mo == "corte" else d.texto
	if texto > 0:
		await CuadroOriginal.mensaje(desde, Textos.linea("txt_dialog", texto))
	if GameState.tiene_medalla(d.medalla):
		if GameState.con_habilidad_campo(d.habilidad) == null:
			await CuadroOriginal.mensaje(desde, Textos.linea("txt_dialog", d.falta))
		elif mo == "fuerza":
			GameState.fuerza_activa = true  # RealizaFuerza: usafuerza
		elif mo == "torbellino":
			# Se pasa al Pokémon con Torbellino (que aprende a surfear) y el remolino se desvanece.
			var p: PokemonInstance = GameState.con_habilidad_campo(d.habilidad)
			p.habilidades_campo |= 1 << 2
			GameState.surfer = p.especie.id_original
			_quitar(0.8 / 0.01 / 30.0)
		else:
			_quitar()
	_ocupado = false


## RealizaCorte / RealizaGolpeRoca: desaparece (en el original lo rompe el Pokémon que sale). Los que
## tienen INDEX no vuelven (PostDestroyObstaculo: obstaculo[INDEX] = true; su condición es esa bandera).
func _quitar(duracion: float = 0.3) -> void:
	var m: RegExMatch = RegEx.create_from_string("(obstaculo|estorbo_torbellino)_(\\d+)").search(str(get_meta("condicion", "")))
	collision_layer = 0
	var t: Tween = create_tween()
	t.tween_property(self, "modulate:a", 0.0, duracion)
	# La bandera al final: al cambiar la historia el mapa apaga el nodo y cortaría el fundido.
	if m:
		t.tween_callback(GameState.cambiar_historia.bind(m.get_string(0), 1))
	t.tween_callback(queue_free)


## EmpujeFuerza: con Fuerza activa, caminar contra la roca la mueve 16 px si ese lugar está libre.
func empujar(dir: Vector2) -> bool:
	if mo != "fuerza" or not GameState.fuerza_activa or _ocupado:
		return false
	collision_mask = MASCARA_EMPUJE
	var choca: bool = test_move(global_transform, dir * 16.0)
	collision_mask = 0
	if choca:
		return false
	_ocupado = true
	var t: Tween = create_tween()
	t.tween_property(self, "position", position + dir * 16.0, 4.0 / 30.0)
	t.tween_callback(func() -> void: _ocupado = false)
	return true
