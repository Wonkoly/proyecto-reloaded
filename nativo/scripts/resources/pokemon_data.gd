class_name PokemonData
extends Resource
## Una especie de Pokémon.

## Curva de experiencia (mismo orden que GetCrecimiento del original).
enum Crecimiento { MEDIO, RAPIDO, LENTO, PARABOLICO, ERRATICO, FLUCTUANTE }

@export var nombre: String = ""
@export var numero_pokedex: int = 0
## Número interno de la especie en el juego original (sprites, formas).
@export var id_original: int = 0
@export var tipos: Array[Tipos.Tipo] = []

@export_group("Stats base")
@export var hp: int = 1
@export var ataque: int = 1
@export var defensa: int = 1
@export var ataque_esp: int = 1
@export var defensa_esp: int = 1
@export var velocidad: int = 1
@export var energia: int = 1

@export_group("Experiencia")
@export var exp_base: int = 0
@export var crecimiento: Crecimiento = Crecimiento.MEDIO

@export_group("Captura y evolución")
## NumRareza: de 3 (legendarios) a 255; entra en la probabilidad de captura (PokeBallCapturando).
@export var ratio_captura: int = 45
## Evoluciona al llegar a este nivel (CheckEvolution); 0 = no evoluciona por nivel.
@export var nivel_evolucion: int = 0
## id_original de la especie en la que evoluciona por nivel (EvolutionConfirmation).
@export var evoluciona_a: int = 0

@export_group("Cría")
## id_original de la especie que nace del huevo (MYSON).
@export var cria: int = 0
## Grupos huevo (GrupoHuevo1/2; 0 = ninguno).
@export var grupo_huevo_1: int = 0
@export var grupo_huevo_2: int = 0
## % de hembras (PkmnSetSexValor sobre 1-100); -1 = sin sexo.
@export var porcentaje_hembra: int = 50
## OneSex: -1 machos y hembras, 1 solo macho, 2 solo hembra, 0 sin sexo.
@export var sexo_unico: int = -1

@export_group("")
@export var sprite: Texture2D
## Por nivel (ordenados por nivel), luego MT, tutor y DT.
@export var movimientos_aprendibles: Array[MovimientoAprendible] = []


## SpriteFrames de batalla generado por tools/extraer.py (null si no se extrajo).
func cargar_sprite_frames() -> SpriteFrames:
	var ruta: String = "res://assets/extraido/sprites/pokemon/%04d/sprite_frames.tres" % id_original
	return load(ruta) as SpriteFrames if ResourceLoader.exists(ruta) else null
