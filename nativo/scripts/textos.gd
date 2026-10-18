class_name Textos
## Textos del juego original (data/extraido/textos/es/, ver tools/README.md).

const CARPETA: String = "res://data/extraido/textos/es"

static var _archivos: Dictionary[String, PackedStringArray] = {}


## Línea n (contando desde 1) de un archivo de textos, como TextBattle(n), TextMenu(n)...
static func linea(archivo: String, n: int) -> String:
	if archivo not in _archivos:
		var f: FileAccess = FileAccess.open(CARPETA.path_join(archivo + ".txt"), FileAccess.READ)
		_archivos[archivo] = f.get_as_text().replace("\r", "").split("\n") if f else PackedStringArray()
	var lineas: PackedStringArray = _archivos[archivo]
	return lineas[n - 1] if n >= 1 and n <= lineas.size() else ""


## TextBattle(n) del original.
static func batalla(n: int) -> String:
	return linea("txt_battle", n)


## TextoPar1/TextoPar2: reemplaza $par1$ y $par2$.
static func par(texto: String, par1: String, par2: String = "") -> String:
	return texto.replace("$par1$", par1).replace("$par2$", par2)
