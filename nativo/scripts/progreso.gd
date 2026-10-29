class_name Progreso
## Experiencia, niveles y movimientos nuevos con los mensajes del original (ExpGana, AprendeAtaque).
## Todo se usa con await; los cuadros congelan el juego mientras se leen.


static func nombre(p: PokemonInstance) -> String:
	return p.apodo if p.apodo != "" else p.especie.nombre


## ExpGana: experiencia que da un rival derrotado: nivel × exp_base / 7 (× 1.5 contra entrenadores).
static func experiencia_de(rival: PokemonInstance, entrenador: bool) -> int:
	return floori(rival.nivel * rival.especie.exp_base * (1.5 if entrenador else 1.0) / 7.0)


## Da experiencia a un Pokémon: "X ha ganado N puntos de Exp.", "X ha subido al Nivel N." y los
## movimientos de cada nivel nuevo. Devuelve true si subió de nivel (global.subido).
static func dar_experiencia(desde: Node, p: PokemonInstance, cantidad: int) -> bool:
	if p.hp_actual <= 0 or cantidad <= 0:
		return false
	if p.nivel >= 100:
		p.experiencia = p.exp_para_nivel(100)
		return true
	await CuadroOriginal.mensaje(desde, Textos.par(Textos.linea("txt_menu", 250), nombre(p), str(cantidad)))
	var niveles: Array[int] = p.ganar_experiencia(cantidad)
	for n: int in niveles:
		await CuadroOriginal.mensaje(desde, Textos.par(Textos.linea("txt_menu", 252), nombre(p), str(n)))
		for m: MoveData in p.movimientos_de_nivel(n):
			await aprender(desde, p, m)
	return not niveles.is_empty()


## AprendeAtaque: con hueco lo aprende; con 4 ataques deja elegir cuál olvidar (o no aprenderlo).
static func aprender(desde: Node, p: PokemonInstance, move: MoveData) -> bool:
	match p.aprender(move):
		0:
			await CuadroOriginal.mensaje(desde, Textos.par(Textos.linea("txt_menu", 205), nombre(p), move.nombre))
			return true
		1:
			return false
	await CuadroOriginal.mensaje(desde, Textos.par(Textos.linea("txt_menu", 206), nombre(p), move.nombre))
	while true:
		var filas: Array = p.movimientos.map(func(m: MoveData) -> Dictionary:
			return {"texto": m.nombre, "derecha": str(m.costo_energia)})
		filas.append({"texto": move.nombre, "derecha": str(move.costo_energia)})
		var i: int = await MenuLista.elegir(desde, Textos.par(Textos.linea("txt_menu", 211), move.nombre), filas)
		if i < 0 or i == p.movimientos.size():
			# ForgetLearningSelection posi = 0: no aprenderlo.
			if await CuadroOriginal.preguntar(desde, Textos.par(Textos.linea("txt_menu", 208), nombre(p), move.nombre)):
				await CuadroOriginal.mensaje(desde, Textos.linea("txt_menu", 204))
				return false
			continue
		var viejo: MoveData = p.movimientos[i]
		if await CuadroOriginal.preguntar(desde, Textos.par(Textos.linea("txt_menu", 213), move.nombre, viejo.nombre)):
			p.movimientos[i] = move
			await CuadroOriginal.mensaje(desde, Textos.par(Textos.linea("txt_menu", 216), viejo.nombre, move.nombre))
			return true
	return false
