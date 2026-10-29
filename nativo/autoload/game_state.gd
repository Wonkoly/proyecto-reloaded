extends Node
## Estado global de la partida (equipo, flags, posición del jugador...).

## Cambió una bandera de la historia (los mapas activan o desactivan lo que depende de ella).
signal historia_cambiada

## Dificultad del original (global.dificultad). Los nombres siguen el orden de las opciones del
## menú (txt_menu: Fácil, Normal, Difícil, Maestro, Extrema); el original tiene un sexto valor.
enum Dificultad { FACIL = 1, NORMAL, DIFICIL, MAESTRO, EXTREMA, SEXTA }

## Divisor del daño (PowDif) por dificultad: x = daño que hace el jugador, y = el que hace el rival.
const POW_DIF: Dictionary[Dificultad, Vector2i] = {
	Dificultad.FACIL: Vector2i(2, 4),
	Dificultad.NORMAL: Vector2i(4, 4),
	Dificultad.DIFICIL: Vector2i(4, 2),
	Dificultad.MAESTRO: Vector2i(2, 2),
	Dificultad.EXTREMA: Vector2i(1, 1),
	Dificultad.SEXTA: Vector2i(4, 1),
}

var dificultad: Dificultad = Dificultad.NORMAL

## El equipo del jugador (el primero que no esté debilitado sale a combatir).
var equipo: Array[PokemonInstance] = []
## Room del original donde está el jugador y su posición (global.lugar, global.xx/yy, global.mira).
var mapa_actual: String = "PuebloAlba"
var posicion_jugador: Vector2 = Vector2(417, 214)
var mira: int = 2
## Al entrar por una puerta: a dónde vuelve la salida del interior (global.room_out, outx/outy).
var mapa_salida: String = ""
var posicion_salida: Vector2 = Vector2.ZERO
## El Pokémon salvaje de la batalla en curso (null si la batalla no viene del overworld).
var salvaje: PokemonInstance
## El último entrenador contra el que se peleó (last_trainer_index/x/y/mira): su NPC de después del
## combate aparece donde quedó (TalkLastTrainer).
var ultimo_entrenador: Dictionary = {}
## El entrenador del combate en curso (INDEX, 0 = ninguno): lo pide el evento con "combate N".
var combate_entrenador: int = 0
## Los compañeros del combate (dobles y triples: sus equipos pelean junto al de combate_entrenador).
var combate_companeros: Array[int] = []
## Banderas de la historia (las del objeto "variables" del original; las que no están valen 0).
## Empieza tras recibir el primer Pokémon y el móvil (igual que ESTADO_HISTORIA en
## tools/mapas_original.py, con el que se toman los valores iniciales de los mapas).
var historia: Dictionary[String, int] = {"fy_002": 1, "movil": 1}
## global.index_place: el INDEX de la última puerta usada (los interiores compartidos lo usan para
## saber a qué isla o calle devolver al jugador).
var indice_lugar: int = 0

var dinero: int = 0
## La mochila: id del objeto → cantidad (ver scripts/inventario.gd).
var objetos: Dictionary[int, int] = {}
## La Poké Ball que se lanza con la tecla B en batalla (global.ball_asign); -1 = ninguna.
var ball_asignada: int = -1
## El objeto que se usa con la tecla A en combate (global.obj_asign); -1 = ninguno.
var objeto_asignado: int = -1
## PC: cajas de 30 huecos (global.boxpkmn); hay 8 al empezar (global.NumCajas) y hasta 149.
var cajas: Array[Array] = []
var nombres_cajas: Array[String] = []
## Pokédex: número de Pokédex → 1 visto, 2 capturado (pkdexV / pkdexC).
var pokedex: Dictionary[int, int] = {}
## (18).usafuerza: Fuerza activada en el mapa actual (se apaga al cambiar de mapa).
var fuerza_activa: bool = false
## global.surfer: id_original del Pokémon con el que se surfea (0 = a pie).
var surfer: int = 0
## (18).canFly: lugares visitados a los que se puede volar (data/extraido/vuelo.json); Pueblo Alba (0)
## está desde el principio (DefineVariables). El valor es 1, o más en los lugares con varias llegadas.
var vuelo: Dictionary[int, int] = {0: 1}
## Bajo el agua con Buceo (en esas rooms global.surfer sigue puesto aunque no haya agua).
var buceando: bool = false
## (142).LAVA: se surfea sobre lava con Ola Lava (no sobre agua).
var surf_lava: bool = false
## Nombre del protagonista (global.protaname); al empezar, el del perfil.
var nombre_jugador: String = ""
## Nombre del rival (global.rivalname; lo elige la presentación del profesor, que aún no existe).
var nombre_rival: String = ""
## Quién es el rival (global.rival_index: uno de los protagonistas 0-9, se elige con el personaje).
## Mientras no existe la selección de personaje es Gary (1).
var rival_personaje: int = 1
## global.lastcenter: el último Centro Pokémon (data/extraido/centros.json; -100 = la casa).
var ultimo_centro: int = -100
## Slot de la partida (1-9, como global.Slot); 0 = todavía no se guardó.
var slot: int = 0
## Segundos jugados (cuenta mientras hay partida y el juego no está en pausa).
var tiempo_juego: float = 0.0
## Hay una partida en curso (no en el título).
var en_partida: bool = false
## Identificador del jugador (global.prota_ID): el código SELUE depende de él.
var prota_id: int = randi_range(0, 99999)
## Apodo del protagonista (código MOTE) y personaje (código CARA: 0-9, 10 = sprite de entrenador).
var apodo_jugador: String = ""
var personaje: int = 0
var personaje_entrenador: int = 1
# Opciones del original que cambian algunos códigos (global.numcheats, saveLogBattle, vel_text...).
var trucos_usados: int = 0
var guardar_log_batalla: bool = false
var velocidad_texto: int = 1
var transicion_especial: bool = false

# Opciones de desarrollo (las cambia la consola dev).
var dev_god: bool = false
var dev_energia_infinita: bool = false
var dev_noclip: bool = false
var dev_encuentros: bool = true
## PowDif forzado para los dos lados (0 = el de la dificultad).
var dev_pow_dif: int = 0


## Dónde empieza una partida nueva (InitialGlobal: global.lugar = Home_2, xx/yy, mira, y room_out/
## outx/outy: a dónde lleva la puerta de la casa).
const INICIO_MAPA: String = "Home_2"
const INICIO_POSICION: Vector2 = Vector2(89, 147)
const INICIO_SALIDA_MAPA: String = "PuebloAlba"
const INICIO_SALIDA_POSICION: Vector2 = Vector2(417, 199)


func _ready() -> void:
	if equipo.is_empty():
		_equipo_inicial()
	if cajas.is_empty():
		_cajas_iniciales()


## Deja todo como al empezar una partida del original: en la casa del protagonista, sin Pokémon ni
## móvil (el inicial lo da el Profesor Oak en su laboratorio y el móvil la madre).
func nueva_partida(nombre: String = "") -> void:
	dificultad = Dificultad.NORMAL
	nombre_jugador = nombre
	ultimo_centro = -100
	ultimo_entrenador = {}
	rival_personaje = 1
	nombre_rival = Textos.linea("txt_character", rival_personaje + 1)  # NameMainProta
	slot = 0
	tiempo_juego = 0.0
	en_partida = true
	equipo.clear()
	mapa_actual = INICIO_MAPA
	posicion_jugador = INICIO_POSICION
	mira = 2
	mapa_salida = INICIO_SALIDA_MAPA
	posicion_salida = INICIO_SALIDA_POSICION
	salvaje = null
	historia = {}
	indice_lugar = 0
	dinero = 0
	objetos.clear()
	ball_asignada = -1
	objeto_asignado = -1
	surfer = 0
	vuelo = {0: 1}
	buceando = false
	surf_lava = false
	_cajas_iniciales()
	pokedex.clear()
	for p: PokemonInstance in equipo:
		marcar_pokedex(p.especie, 2)
	prota_id = randi_range(0, 99999)
	apodo_jugador = ""
	personaje = 0
	personaje_entrenador = 1
	trucos_usados = 0
	historia_cambiada.emit()


func _process(delta: float) -> void:
	if en_partida:
		tiempo_juego += delta


## Lo que se guarda de la partida (SaveManager). Las opciones de desarrollo no se guardan.
func a_dict() -> Dictionary:
	return {
		"nombre_jugador": nombre_jugador,
		"nombre_rival": nombre_rival,
		"rival_personaje": rival_personaje,
		"ultimo_centro": ultimo_centro,
		"ultimo_entrenador": ultimo_entrenador,
		"dificultad": dificultad,
		"equipo": equipo.map(func(p: PokemonInstance) -> Dictionary: return p.a_dict()),
		"mapa_actual": mapa_actual,
		"posicion_jugador": [posicion_jugador.x, posicion_jugador.y],
		"mira": mira,
		"mapa_salida": mapa_salida,
		"posicion_salida": [posicion_salida.x, posicion_salida.y],
		"historia": historia.duplicate(),
		"indice_lugar": indice_lugar,
		"dinero": dinero,
		"objetos": objetos.keys().map(func(k: int) -> Array: return [k, objetos[k]]),
		"ball_asignada": ball_asignada,
		"objeto_asignado": objeto_asignado,
		"cajas": cajas.map(func(caja: Array) -> Array: return caja.map(
			func(p: Variant) -> Variant: return (p as PokemonInstance).a_dict() if p else null)),
		"nombres_cajas": nombres_cajas,
		"pokedex": pokedex.keys().map(func(k: int) -> Array: return [k, pokedex[k]]),
		"prota_id": prota_id,
		"apodo_jugador": apodo_jugador,
		"personaje": personaje,
		"personaje_entrenador": personaje_entrenador,
		"trucos_usados": trucos_usados,
		"guardar_log_batalla": guardar_log_batalla,
		"velocidad_texto": velocidad_texto,
		"transicion_especial": transicion_especial,
		"tiempo_juego": tiempo_juego,
		"surfer": surfer,
		"vuelo": vuelo.keys().map(func(k: int) -> Array: return [k, vuelo[k]]),
		"buceando": buceando,
		"surf_lava": surf_lava,
	}


## Restaura una partida guardada (lo que falte queda como en una partida nueva).
func desde_dict(d: Dictionary, slot_: int) -> void:
	nueva_partida(str(d.get("nombre_jugador", "")))
	slot = slot_
	rival_personaje = int(d.get("rival_personaje", 1))
	ultimo_centro = int(d.get("ultimo_centro", -100))
	ultimo_entrenador = d.get("ultimo_entrenador", {}) if d.get("ultimo_entrenador") is Dictionary else {}
	nombre_rival = str(d.get("nombre_rival", Textos.linea("txt_character", rival_personaje + 1)))
	dificultad = clampi(int(d.get("dificultad", Dificultad.NORMAL)), Dificultad.FACIL, Dificultad.SEXTA) as Dificultad
	if d.has("equipo"):
		equipo.clear()
		for p: Variant in d.equipo:
			var pokemon: PokemonInstance = PokemonInstance.desde_dict(p) if p is Dictionary else null
			if pokemon:
				equipo.append(pokemon)
	mapa_actual = str(d.get("mapa_actual", mapa_actual))
	posicion_jugador = _vector(d.get("posicion_jugador"), posicion_jugador)
	mira = int(d.get("mira", mira))
	mapa_salida = str(d.get("mapa_salida", mapa_salida))
	posicion_salida = _vector(d.get("posicion_salida"), posicion_salida)
	if d.get("historia") is Dictionary:
		historia.clear()
		for k: Variant in d.historia:
			historia[str(k)] = int(d.historia[k])
	indice_lugar = int(d.get("indice_lugar", 0))
	dinero = int(d.get("dinero", 0))
	objetos.clear()
	for par: Variant in d.get("objetos", []):
		if par is Array and par.size() == 2 and int(par[1]) > 0:
			objetos[int(par[0])] = int(par[1])
	ball_asignada = int(d.get("ball_asignada", -1))
	objeto_asignado = int(d.get("objeto_asignado", -1))
	if d.get("cajas") is Array:
		cajas.clear()
		for caja: Variant in d.cajas:
			var huecos: Array = []
			huecos.resize(POKEMON_POR_CAJA)
			if caja is Array:
				for i: int in mini(caja.size(), POKEMON_POR_CAJA):
					huecos[i] = PokemonInstance.desde_dict(caja[i]) if caja[i] is Dictionary else null
			cajas.append(huecos)
		nombres_cajas.clear()
		for i: int in cajas.size():
			var nombres: Array = d.get("nombres_cajas", [])
			nombres_cajas.append(str(nombres[i]) if i < nombres.size() else _nombre_caja(i))
	for par: Variant in d.get("pokedex", []):
		if par is Array and par.size() == 2:
			pokedex[int(par[0])] = int(par[1])
	prota_id = int(d.get("prota_id", prota_id))
	apodo_jugador = str(d.get("apodo_jugador", ""))
	personaje = int(d.get("personaje", 0))
	personaje_entrenador = int(d.get("personaje_entrenador", 1))
	trucos_usados = int(d.get("trucos_usados", 0))
	guardar_log_batalla = bool(d.get("guardar_log_batalla", false))
	velocidad_texto = int(d.get("velocidad_texto", 1))
	transicion_especial = bool(d.get("transicion_especial", false))
	tiempo_juego = float(d.get("tiempo_juego", 0.0))
	surfer = int(d.get("surfer", 0))
	buceando = bool(d.get("buceando", false))
	surf_lava = bool(d.get("surf_lava", false))
	for par: Variant in d.get("vuelo", []):
		if par is Array and par.size() == 2:
			vuelo[int(par[0])] = int(par[1])
	historia_cambiada.emit()


static func _vector(v: Variant, si_no: Vector2) -> Vector2:
	return Vector2(float(v[0]), float(v[1])) if v is Array and v.size() == 2 else si_no


func _equipo_inicial() -> void:
	var charmander: PokemonData = Datos.especie(4)
	if charmander:
		equipo.append(PokemonInstance.crear(charmander, 5))


const POKEMON_POR_CAJA: int = 30
const CAJAS_INICIALES: int = 8


func _cajas_iniciales() -> void:
	cajas.clear()
	nombres_cajas.clear()
	for i: int in CAJAS_INICIALES:
		var huecos: Array = []
		huecos.resize(POKEMON_POR_CAJA)
		cajas.append(huecos)
		nombres_cajas.append(_nombre_caja(i))


## TextMenu(199): "Caja N".
static func _nombre_caja(i: int) -> String:
	return Textos.par(Textos.linea("txt_menu", 199), str(i + 1))


## CapturaPokemon: el primer hueco libre del PC. Devuelve [caja, posición] o [] si está lleno.
func guardar_en_pc(p: PokemonInstance) -> Array[int]:
	for c: int in cajas.size():
		for i: int in POKEMON_POR_CAJA:
			if cajas[c][i] == null:
				cajas[c][i] = p
				return [c, i]
	return []


## Dex_SEE / Dex_CATCH: marca la especie como vista (1) o capturada (2); nunca baja.
func marcar_pokedex(especie: PokemonData, estado: int) -> void:
	if especie:
		pokedex[especie.numero_pokedex] = maxi(pokedex.get(especie.numero_pokedex, 0), estado)


## CentroPokemon(1): HP y energía al máximo (y sin estados, cuando los haya).
func curar_equipo() -> void:
	for p: PokemonInstance in equipo:
		p.hp_actual = p.calcular_stats()["hp"]
		p.energia_actual = p.calcular_energia_maxima()
		p.estado = MoveData.Estado.NINGUNO


## El primero del equipo que puede combatir, o null si todos están debilitados.
func pokemon_para_combatir() -> PokemonInstance:
	for p: PokemonInstance in equipo:
		if p.hp_actual > 0:
			return p
	return null


## PowDif del daño que hace un lado de la batalla (1 = jugador, 2 = rival).
func pow_dif(lado: int) -> int:
	if dev_pow_dif > 0:
		return dev_pow_dif
	return POW_DIF[dificultad].x if lado == 1 else POW_DIF[dificultad].y


## MEDALLA_STAR[n] (1-8), como bandera de la historia "MEDALLA_STAR_n".
func tiene_medalla(n: int) -> bool:
	return bandera("MEDALLA_STAR_%d" % n) != 0


## El primer Pokémon del equipo con esa habilidad de campo (ConsultaHabExt), o null.
func con_habilidad_campo(n: int) -> PokemonInstance:
	for p: PokemonInstance in equipo:
		if p.tiene_habilidad_campo(n):
			return p
	return null


func bandera(nombre: String) -> int:
	return historia.get(nombre, 0)


func cambiar_historia(nombre: String, valor: int) -> void:
	historia[nombre] = valor
	historia_cambiada.emit()
