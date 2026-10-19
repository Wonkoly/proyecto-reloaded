class_name SubtablaEncuentros
extends Resource
## Una parte de la tabla de encuentros de un mapa: un método (hierba, surf, caña...), un horario,
## una condición de la historia y una zona opcional. Viene de AparicionSalvajes (ver
## tools/encuentros_original.py); el peso de cada entrada es cuántos de los 1000 valores ocupa.

## El ModoAparicion del original menos 1 (HIERBA = modo 1 ... LAVA = modo 9).
enum Metodo { HIERBA, SURF, BARRO, HIERBA_ESPECIAL, CANA_VIEJA, CANA_BUENA, SUPERCANA, HIERBA_INVISIBLE, LAVA }
enum Horario { SIEMPRE, DIA, NOCHE }

## AparicionSalvajes tira un Valor de 1 a 1000 por encuentro.
const VALORES: int = 1000

@export var metodo: Metodo = Metodo.HIERBA
@export var horario: Horario = Horario.SIEMPRE
## Expresión sobre h (GameState.historia) y lugar, como metadata/condicion en los mapas.
@export var condicion: String = ""
## Rect2 vacío = todo el mapa (las condiciones sobre X/Y del original).
@export var zona: Rect2 = Rect2()
## FrequencySalvajes: un encuentro con probabilidad 1/frecuencia por step en movimiento (las cañas:
## pica 1 de cada `frecuencia` lanzamientos).
@export var frecuencia: int = 150
@export var entradas: Array[EncuentroSalvaje] = []
## Las especies de RARO y SUPER_RARO (solo con la Colonia, que todavía no existe).
@export var raros: PackedInt32Array = PackedInt32Array()
@export var super_raros: PackedInt32Array = PackedInt32Array()
## Modo 4 del original: su bloque de HierbasSalvajes nunca se alcanza (ver docs/analisis_encuentros.md).
## Se genera para tenerlo, pero no se usa.
@export var codigo_muerto: bool = false


## Si vale para ese método, momento del día y posición. `cumple` evalúa una condición de la historia.
func aplica(metodo_: Metodo, es_de_dia: bool, posicion: Vector2, cumple: Callable) -> bool:
	if codigo_muerto or metodo != metodo_:
		return false
	if (horario == Horario.DIA and not es_de_dia) or (horario == Horario.NOCHE and es_de_dia):
		return false
	if zona.has_area() and not zona.has_point(posicion):
		return false
	return condicion == "" or bool(cumple.call(condicion))


## Las entradas que existen ahora (Unown y fósiles dependen de la historia por especie).
func entradas_activas(cumple: Callable) -> Array[EncuentroSalvaje]:
	return entradas.filter(func(e: EncuentroSalvaje) -> bool: return e.condicion == "" or bool(cumple.call(e.condicion)))


## Sortea como el original: un valor de 1 a 1000 contra los pesos. null si cae en el resto (los
## valores sin especie, o los de una especie que la historia todavía no deja salir).
func sortear(cumple: Callable, valor: int = -1) -> EncuentroSalvaje:
	var v: int = valor if valor > 0 else randi_range(1, VALORES)
	for e: EncuentroSalvaje in entradas:
		v -= e.peso
		if v <= 0:
			return e if e.condicion == "" or bool(cumple.call(e.condicion)) else null
	return null


## Probabilidad de cada especie y de que no salga nada (para la consola dev).
func probabilidades(cumple: Callable) -> Dictionary:
	var out: Dictionary = {}
	var usado: int = 0
	for e: EncuentroSalvaje in entradas_activas(cumple):
		out[e.id_especie] = float(e.peso) / VALORES
		usado += e.peso
	out[0] = float(VALORES - usado) / VALORES
	return out
