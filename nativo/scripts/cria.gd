class_name Cria
## Qué huevo dan dos Pokémon (EGG del original, llamado desde Control: el primero es macho y el
## segundo hembra). Devuelve -(especie del huevo) como el original, o 0 si no pueden criar.

## Especies que nunca dejan huevo como padres (bebés, Unown y formas especiales).
const NO_CRIAN: Array[int] = [298, 438, 439, 440, 433, 446, 406, 360, 201, 447, 236, 239, 240, 238, 175,
	172, 173, 174, 1000, 2283]
const DITTO: int = 132
const MEW: int = 151
## Grupo huevo "Desconocido" (no crían salvo con su especie o Mew).
const GRUPO_DESCONOCIDO: int = 14


static func huevo(pk1: int, pk2: int) -> int:
	pk1 = _base(pk1)
	pk2 = _base(pk2)
	if pk1 <= 0 or pk2 <= 0:
		return 0
	for pk: int in [pk1, pk2]:
		if pk in NO_CRIAN or (pk >= 601 and pk <= 628):
			return 0
	if pk1 == 503:
		pk1 = DITTO
	if pk2 == 503:
		pk2 = DITTO
	var par: Callable = func(a: int, b: int) -> bool: return (pk1 == a and pk2 == b) or (pk1 == b and pk2 == a)
	var al_azar: Callable = func(a: int, b: int) -> int: return -a if randi_range(1, 2) == 2 else -b
	if pk1 == DITTO and pk2 == DITTO:
		return -DITTO
	if par.call(DITTO, MEW):
		return -DITTO if randi_range(1, 10) <= 9 else -MEW
	if pk1 == MEW and pk2 == MEW:
		return -MEW
	if par.call(490, MEW):
		return -490
	if pk1 == 490 and pk2 == 490:
		return -489
	if (pk1 == DITTO and _cria(pk2) == 489) or (pk2 == DITTO and _cria(pk1) == 489):
		return 0
	for especial: Array in [[380, MEW, -380], [381, MEW, -381], [381, 380, -499], [982, MEW, -982],
			[983, MEW, -983], [982, 983, -980], [249, MEW, -2283], [821, MEW, -2283]]:
		if par.call(especial[0], especial[1]):
			return especial[2]
	for legendario: int in [386, 492, 487]:
		if _cria(pk1) == legendario and _cria(pk2) == legendario:
			return -legendario
	for pareja: Array in [[29, 32, 29, 32], [30, 33, 29, 32], [31, 34, 29, 32], [449, 549, 449, 549],
			[450, 550, 449, 549], [313, 314, 313, 314], [241, 128, 128, 241], [650, 652, 650, 652], [651, 653, 650, 652]]:
		if par.call(pareja[0], pareja[1]):
			return al_azar.call(pareja[2], pareja[3])
	if par.call(413, 414) or par.call(413, 412) or par.call(414, 412):
		return -412
	if par.call(982, 983):
		return -980
	if pk1 in [980, 981, 982, 983] and pk2 in [980, 981, 982, 983]:
		return 0
	if _cria(pk1) == _cria(pk2) and _sexo_unico(_cria(pk1)) in [1, 2]:
		return 0
	if GRUPO_DESCONOCIDO in _grupos(pk1) and (pk2 == pk1 or pk2 == MEW):
		return -_cria(pk1)
	if GRUPO_DESCONOCIDO in _grupos(pk2) and (pk1 == pk2 or pk1 == MEW):
		return -_cria(pk2)
	if _grupo1(pk1) == GRUPO_DESCONOCIDO or _grupo1(pk2) == GRUPO_DESCONOCIDO:
		return 0
	if pk1 == MEW:
		return -_cria(pk2)
	if pk2 == MEW:
		return -_cria(pk1)
	if pk1 == DITTO:
		return -_cria(pk2)
	if pk2 == DITTO:
		return -_cria(pk1)
	if _cria(pk1) == _cria(pk2):
		return -_cria(pk1)
	if _grupo1(pk1) == _grupo1(pk2) or _grupo1(pk1) == _grupo2(pk2) or _grupo2(pk1) == _grupo1(pk2) \
			or (_grupo2(pk1) == _grupo2(pk2) and _grupo2(pk2) != 0):
		return -_cria(pk2)
	return 0


## Sin formas (id > 100000) ni shiny (id + 1000), como hace EGG al empezar.
static func _base(pk: int) -> int:
	for d: int in [200000, 150000, 100000]:
		if pk > d:
			pk -= d
	if (pk > 1000 and pk <= 2000) or (pk > 3000 and pk <= 4000):
		pk -= 1000
	return pk


static func _datos(pk: int) -> PokemonData:
	return Datos.especie(pk) if pk > 0 else null


static func _cria(pk: int) -> int:
	var d: PokemonData = _datos(pk)
	return d.cria if d else 0


static func _grupo1(pk: int) -> int:
	var d: PokemonData = _datos(pk)
	return d.grupo_huevo_1 if d else 0


static func _grupo2(pk: int) -> int:
	var d: PokemonData = _datos(pk)
	return d.grupo_huevo_2 if d else 0


static func _grupos(pk: int) -> Array[int]:
	return [_grupo1(pk), _grupo2(pk)]


static func _sexo_unico(pk: int) -> int:
	var d: PokemonData = _datos(pk)
	return d.sexo_unico if d else -1
