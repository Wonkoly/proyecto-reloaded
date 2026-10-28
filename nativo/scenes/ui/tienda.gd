class_name Tienda
## Comprar (KeyActionsCompra) y vender (KeyActionsVenta), con los textos del original.

static func _m(n: int) -> String:
	return Textos.linea("txt_menu", n)


static func _pie() -> String:
	return "%s: %d €" % [_m(852), GameState.dinero]


## La lista de objetos de la tienda: elegir, cuántos, confirmar y pagar; hasta cancelar.
static func comprar(desde: Node, objetos: Array[int]) -> void:
	var sel: int = 0
	while true:
		var filas: Array = objetos.map(func(id: int) -> Dictionary: return {"texto": Inventario.nombre(id),
			"derecha": "%d €" % Inventario.precio(id), "desc": Inventario.descripcion(id)})
		sel = await MenuLista.elegir(desde, _m(851), filas, {"pie": _pie(), "inicial": sel})
		if sel < 0:
			break
		var id: int = objetos[sel]
		var precio: int = Inventario.precio(id)
		if precio > GameState.dinero:
			await CuadroOriginal.mensaje(desde, _m(854))
			continue
		var tiene: int = Inventario.cantidad(id)
		var maximo: int = mini(GameState.dinero / maxi(1, precio), Inventario.MAXIMO - tiene)
		var titulo: String = Textos.par(_m(856), Inventario.nombre(id)) if tiene == 1 else Textos.par(_m(855), Inventario.nombre(id), str(tiene))
		var n: int = await MenuLista.cantidad(desde, titulo, mini(maximo, 99), precio)
		if n <= 0:
			continue
		var pregunta: String = Textos.par(_m(861), Inventario.nombre(id), str(precio)) if n == 1 \
			else Textos.par(_m(860), Inventario.nombre(id), str(n)).replace("$par3$", str(n * precio))
		if not await CuadroOriginal.preguntar(desde, pregunta):
			continue
		if Inventario.dar(id, n):
			GameState.dinero -= n * precio
			AudioManager.efecto_ui("snd_get")
			await CuadroOriginal.mensaje(desde, _m(864))
	await CuadroOriginal.mensaje(desde, _m(853))


## Los objetos de la mochila por bolsillo: a la mitad de su precio; los clave y sin precio no.
static func vender(desde: Node) -> void:
	var pestana: int = 0
	var sel: int = 0
	while true:
		var b: String = Inventario.BOLSILLOS[pestana]
		var ids: Array[int] = Inventario.de_bolsillo(b)
		var filas: Array = ids.map(func(id: int) -> Dictionary: return {"texto": Inventario.nombre(id),
			"derecha": "x%d" % Inventario.cantidad(id), "desc": Inventario.descripcion(id)})
		var titulos: Array = Inventario.BOLSILLOS.map(func(x: String) -> String: return Inventario.NOMBRES_BOLSILLO[x])
		sel = await MenuLista.elegir(desde, "", filas, {"pie": _pie(), "pestanas": titulos, "pestana": pestana, "inicial": sel})
		if sel == MenuLista.IZQUIERDA or sel == MenuLista.DERECHA:
			pestana = (pestana + (1 if sel == MenuLista.DERECHA else -1) + titulos.size()) % titulos.size()
			sel = 0
			continue
		if sel < 0:
			break
		var id: int = ids[sel]
		if b == "clave":
			await CuadroOriginal.mensaje(desde, _m(866))
			continue
		var pago: int = Inventario.precio(id) / 2
		if pago <= 0:
			await CuadroOriginal.mensaje(desde, _m(865))
			continue
		var tiene: int = Inventario.cantidad(id)
		var titulo: String = Textos.par(_m(868), Inventario.nombre(id)) if tiene == 1 else Textos.par(_m(867), Inventario.nombre(id), str(tiene))
		var n: int = await MenuLista.cantidad(desde, titulo, tiene, pago)
		if n <= 0:
			continue
		var pregunta: String = Textos.par(_m(873), Inventario.nombre(id), str(pago)) if n == 1 \
			else Textos.par(_m(872), Inventario.nombre(id), str(n)).replace("$par3$", str(n * pago))
		if not await CuadroOriginal.preguntar(desde, pregunta):
			continue
		if Inventario.quitar(id, n):
			GameState.dinero += n * pago
			await CuadroOriginal.mensaje(desde, _m(876))
