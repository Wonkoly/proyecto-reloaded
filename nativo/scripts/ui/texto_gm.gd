class_name TextoGM
## Texto como lo dibuja GM8 (draw_text, draw_text_color, draw_text_shadow, AjustarTexto): `#` es salto
## de línea, la posición es la esquina de arriba (o el centro de arriba si va centrado) y las líneas
## se separan por el alto de la fuente.

const FUENTE1: String = "res://assets/extraido/fonts/fuente1.fnt"           # fuente 0 (Fuente1)
const FUENTE_DIALOGO: String = "res://assets/extraido/fonts/fuente_dialogo.fnt"  # fuente 2 (FuenteDialogo)
const TAMANO: int = 16  # las fuentes de mapa de bits tienen un solo tamaño; este solo se pasa por la API


## Color de GM8 (entero BGR: c_red = 255) a Color.
static func color(bgr: int, alfa: float = 1.0) -> Color:
	return Color8(bgr & 255, (bgr >> 8) & 255, (bgr >> 16) & 255, int(clampf(alfa, 0.0, 1.0) * 255))


## draw_text_color: texto en (x, y), centrado en x si `centrado`.
static func dibujar(lienzo: CanvasItem, fuente: Font, pos: Vector2, texto: String, col: Color,
		centrado: bool = false) -> void:
	var alto: float = fuente.get_height(TAMANO)
	var y: float = pos.y + fuente.get_ascent(TAMANO)
	for linea: String in texto.split("#"):
		var x: float = pos.x
		if centrado:
			x -= floorf(fuente.get_string_size(linea, HORIZONTAL_ALIGNMENT_LEFT, -1, TAMANO).x / 2.0)
		lienzo.draw_string(fuente, Vector2(x, y), linea, HORIZONTAL_ALIGNMENT_LEFT, -1, TAMANO, col)
		y += alto


## draw_text_shadow del original: sombra (blanca si el texto es oscuro) a la derecha, abajo y en
## diagonal, y el texto encima.
static func con_sombra(lienzo: CanvasItem, fuente: Font, pos: Vector2, texto: String, col: Color,
		sombra: Color = Color.BLACK, centrado: bool = false) -> void:
	if (col.r8 + col.g8 + col.b8) / 3.0 < 60.0:
		sombra = Color.WHITE
	for d: Vector2 in [Vector2(1, 1), Vector2(0, 1), Vector2(1, 0)]:
		dibujar(lienzo, fuente, pos + d, texto, sombra, centrado)
	dibujar(lienzo, fuente, pos, texto, col, centrado)


## AjustarTexto: parte el texto en líneas de como mucho `ancho` px (separadas por `#`).
static func ajustar(texto: String, ancho: float, fuente: Font) -> String:
	var lineas: PackedStringArray = []
	for parrafo: String in texto.split("#"):
		var actual: String = ""
		for palabra: String in parrafo.split(" ", false):
			var prueba: String = palabra if actual == "" else actual + " " + palabra
			if actual != "" and fuente.get_string_size(prueba, HORIZONTAL_ALIGNMENT_LEFT, -1, TAMANO).x > ancho:
				lineas.append(actual)
				actual = palabra
			else:
				actual = prueba
		lineas.append(actual)
	return "#".join(lineas)
