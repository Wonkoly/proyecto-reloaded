class_name MoveData
extends Resource
## Definición de un movimiento.
## Los valores por defecto de tiempos y proyectil son los globales del original
## (30 steps/s): ver docs/referencia_original.md.

enum Categoria { FISICO, ESPECIAL, ESTADO }
## Cómo se ejecuta (ExecuteAtack): el Pokémon se lanza contra el rival, dispara un proyectil, actúa
## sobre sí mismo sin proyectil, o es un caso especial (Vuelo, Excavar...).
enum Modo { CONTACTO, PROYECTIL, ESTADO, ESPECIAL }

@export var nombre: String = ""
## Número interno del movimiento en el juego original.
@export var id_original: int = 0
@export var tipo: Tipos.Tipo = Tipos.Tipo.NORMAL
@export var categoria: Categoria = Categoria.FISICO
@export var modo: Modo = Modo.PROYECTIL
@export var poder: int = 0
## Energía que gasta cada uso.
@export var costo_energia: int = 0
@export_multiline var descripcion: String = ""

@export_group("Tiempos y proyectil")
## Segundos sin poder volver a atacar (original: 15 steps).
@export var cooldown: float = 0.5
## Segundos sin poder moverse tras atacar (original: 5 steps).
@export var bloqueo_movimiento: float = 5.0 / 30.0
## Píxeles por segundo (original: 12 px/step).
@export var velocidad_proyectil: float = 360.0
## Segundos antes de desaparecer si no choca (original: 200 steps).
@export var duracion_proyectil: float = 200.0 / 30.0
