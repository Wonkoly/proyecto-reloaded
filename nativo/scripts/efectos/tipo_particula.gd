class_name TipoParticula
extends RefCounted
## Un tipo de partícula como los de GM8 (part_type_*). Tiempos en steps del original (30/s) y
## velocidades en px/step: ParticulasGM avanza a 30 steps/s, igual que el original.

## Imagen: una de las 14 formas de GM8 (pt_shape_*) o un sprite del juego.
var forma: int = 0
var sprite: SpriteOriginal
var size_min: float = 1.0
var size_max: float = 1.0
var size_incr: float = 0.0
var size_wiggle: float = 0.0
var xscale: float = 1.0
var yscale: float = 1.0
var life_min: int = 100
var life_max: int = 100
var speed_min: float = 0.0
var speed_max: float = 0.0
var speed_incr: float = 0.0
var speed_wiggle: float = 0.0
var dir_min: float = 0.0
var dir_max: float = 0.0
var dir_incr: float = 0.0
var dir_wiggle: float = 0.0
var grav_amount: float = 0.0
var grav_dir: float = 270.0
var ang_min: float = 0.0
var ang_max: float = 0.0
var ang_incr: float = 0.0
var ang_wiggle: float = 0.0
var ang_relative: bool = false
## 1 a 3 colores: con 2 o 3 el color cambia a lo largo de la vida (part_type_color2/3).
var colores: Array[Color] = [Color.WHITE]
var alpha1: float = 1.0
var alpha2: float = 1.0
var alpha3: float = 1.0
var aditivo: bool = false


## part_type_alpha2: alfa al nacer y al morir.
func alfa2(a1: float, a2: float) -> TipoParticula:
	alpha1 = a1
	alpha2 = (a1 + a2) / 2.0
	alpha3 = a2
	return self


func alfa3(a1: float, a2: float, a3: float) -> TipoParticula:
	alpha1 = a1
	alpha2 = a2
	alpha3 = a3
	return self


func tamano(minimo: float, maximo: float, incremento: float = 0.0, wiggle: float = 0.0) -> TipoParticula:
	size_min = minimo
	size_max = maximo
	size_incr = incremento
	size_wiggle = wiggle
	return self


func velocidad(minimo: float, maximo: float, incremento: float = 0.0, wiggle: float = 0.0) -> TipoParticula:
	speed_min = minimo
	speed_max = maximo
	speed_incr = incremento
	speed_wiggle = wiggle
	return self


func direccion(minimo: float, maximo: float, incremento: float = 0.0, wiggle: float = 0.0) -> TipoParticula:
	dir_min = minimo
	dir_max = maximo
	dir_incr = incremento
	dir_wiggle = wiggle
	return self


func orientacion(minimo: float, maximo: float, incremento: float = 0.0, wiggle: float = 0.0,
		relativa: bool = false) -> TipoParticula:
	ang_min = minimo
	ang_max = maximo
	ang_incr = incremento
	ang_wiggle = wiggle
	ang_relative = relativa
	return self


func vida(minimo: int, maximo: int) -> TipoParticula:
	life_min = minimo
	life_max = maximo
	return self


func gravedad(cantidad: float, direccion_: float) -> TipoParticula:
	grav_amount = cantidad
	grav_dir = direccion_
	return self
