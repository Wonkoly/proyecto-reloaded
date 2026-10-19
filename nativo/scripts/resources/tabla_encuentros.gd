class_name TablaEncuentros
extends Resource
## Los Pokémon salvajes de un mapa (data/encuentros/<mapa>.tres). Reemplaza por ahora a
## AparicionSalvajes del original, que es lógica (lugar, modo, hora del día, historia...).

const CARPETA: String = "res://data/encuentros"
## Paso del jugador andando en el original (3 px/step): convierte la probabilidad por step en
## probabilidad por distancia.
const PIXELES_POR_STEP: float = 3.0

## FrequencySalvajes: un encuentro con probabilidad 1/frecuencia por step caminando en la hierba
## (150 en la mayoría de mapas; HierbasSalvajes).
@export var frecuencia: int = 150
@export var encuentros: Array[EncuentroSalvaje] = []


## La tabla de un mapa (nombre de la room del original), o null si no tiene.
static func de_mapa(nombre_original: String) -> TablaEncuentros:
	var ruta: String = CARPETA.path_join(SceneManager.snake(nombre_original) + ".tres")
	return load(ruta) as TablaEncuentros if ResourceLoader.exists(ruta) else null


## Probabilidad de un encuentro al recorrer `distancia` px en la hierba.
func probabilidad(distancia: float) -> float:
	return 1.0 - pow(1.0 - 1.0 / maxf(frecuencia, 1.0), distancia / PIXELES_POR_STEP)


## Un salvaje al azar según los pesos, con IV y ntv al azar.
func elegir() -> PokemonInstance:
	var total: int = 0
	for e: EncuentroSalvaje in encuentros:
		total += maxi(e.peso, 0)
	if total <= 0:
		return null
	var azar: int = randi_range(1, total)
	for e: EncuentroSalvaje in encuentros:
		azar -= maxi(e.peso, 0)
		if azar <= 0:
			var especie: PokemonData = Datos.especie(e.id_especie)
			return PokemonInstance.crear(especie, randi_range(e.nivel_min, maxi(e.nivel_min, e.nivel_max))) if especie else null
	return null
