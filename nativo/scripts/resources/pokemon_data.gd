class_name PokemonData
extends Resource
## Una especie de Pokémon.

@export var nombre: String = ""
@export var numero_pokedex: int = 0
@export var tipos: Array[Tipos.Tipo] = []

@export_group("Stats base")
@export var hp: int = 1
@export var ataque: int = 1
@export var defensa: int = 1
@export var ataque_esp: int = 1
@export var defensa_esp: int = 1
@export var velocidad: int = 1

@export_group("")
@export var sprite: Texture2D
@export var movimientos_aprendibles: Array[MoveData] = []
