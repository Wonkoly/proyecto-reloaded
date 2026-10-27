class_name EntrenadorData
extends Resource
## Un entrenador del original: su número (INDEX, la bandera trainer_N), quién es y su equipo
## (TrainerCreation + TrainerPokemon). Se busca primero en data/entrenadores/ (los editados) y luego en
## data/extraido/entrenadores/ (Datos.entrenador).

@export var id: int = 0
@export var nombre: String = ""
## sprINDEX: sprite, retrato y nombre genérico (Datos de dialogo_personajes.json).
@export var sprindex: float = -1.0
@export var lider: bool = false
@export var equipo: Array[MiembroEquipo] = []


## Los Pokémon que saca, en orden, según las banderas de la historia y el equipo del jugador.
func crear_equipo() -> Array[PokemonInstance]:
	var max_nv: int = 1
	for p: PokemonInstance in GameState.equipo:
		max_nv = maxi(max_nv, p.nivel)
	var out: Array[PokemonInstance] = []
	for m: MiembroEquipo in equipo:
		if m.condicion != "" and not Eventos.condicion_simple(m.condicion):
			continue
		var id_especie: int = m.especie if m.especie_bandera == "" else GameState.bandera(m.especie_bandera)
		var e: PokemonData = Datos.especie(id_especie) if id_especie > 0 else null
		if e == null:
			continue
		var p := PokemonInstance.crear(e, m.nivel_para(max_nv))
		if not m.movimientos.is_empty():
			p.movimientos.clear()
			for id_mov: int in m.movimientos:
				var mv: MoveData = Datos.movimiento(id_mov)
				if mv:
					p.movimientos.append(mv)
		out.append(p)
	return out
