extends Node
## Guardar y cargar partidas: 9 slots como el original (global.Slot), cada uno con su respaldo.
##
## Cada slot es user://partidas/partida_N.json:
##   {"formato": FORMATO, "version": VERSION, "guardado": unix, "suma": sha256 de "datos",
##    "resumen": {...para la pantalla de cargar...}, "datos": GameState.a_dict()}
## Al guardar se escribe primero partida_N.tmp, la partida anterior pasa a partida_N.bak (como el
## _bk del original) y el .tmp ocupa su lugar: un corte a mitad nunca deja el slot sin partida. Al
## cargar se comprueba la suma; si el archivo está dañado se usa el respaldo.

const SLOTS: int = 9
const CARPETA: String = "user://partidas"
## Dónde se guardan (las pruebas usan otra carpeta para no tocar las partidas reales).
var carpeta: String = CARPETA
const FORMATO: String = "proyecto-reloaded-nativo"
## Sube cuando cambia lo que se guarda; _migrar() pone al día las partidas viejas.
const VERSION: int = 1

## Perfil local del jugador (por ahora solo su nombre; será la cuenta del multijugador online).
const PERFIL: String = "user://perfil.json"
const LARGO_NOMBRE: int = 12
var ruta_perfil: String = PERFIL

## Resultado de cargar(): ok, de_respaldo (el principal estaba dañado) y el error si no se pudo.
class Carga:
	var ok: bool = false
	var de_respaldo: bool = false
	var error: String = ""


func ruta(slot: int) -> String:
	return carpeta.path_join("partida_%d.json" % slot)


func existe(slot: int) -> bool:
	return FileAccess.file_exists(ruta(slot)) or FileAccess.file_exists(ruta(slot) + ".bak")


## Slots con partida, en orden.
func ocupados() -> Array[int]:
	var out: Array[int] = []
	for n: int in range(1, SLOTS + 1):
		if existe(n):
			out.append(n)
	return out


## El primer slot libre, o 0 si están los 9 ocupados.
func primer_libre() -> int:
	for n: int in range(1, SLOTS + 1):
		if not existe(n):
			return n
	return 0


## Guarda la partida en curso en su slot (si aún no tiene, en el primero libre). Devuelve el error,
## o "" si se guardó.
func guardar(slot: int = GameState.slot) -> String:
	if slot <= 0:
		slot = primer_libre()
		if slot == 0:
			return Textos.linea("txt_menu", 59).replace("@", "\n")
	DirAccess.make_dir_recursive_absolute(carpeta)
	# Ida y vuelta por JSON: los números quedan como los devuelve JSON al leer (y la suma coincide).
	var datos: Dictionary = JSON.parse_string(JSON.stringify(GameState.a_dict()))
	var contenido := {
		"formato": FORMATO,
		"version": VERSION,
		"guardado": int(Time.get_unix_time_from_system()),
		"suma": _suma(datos),
		"resumen": _resumen(),
		"datos": datos,
	}
	var principal: String = ruta(slot)
	var tmp: String = principal.get_basename() + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "No se pudo escribir la partida (%s)." % error_string(FileAccess.get_open_error())
	f.store_string(JSON.stringify(contenido, "\t"))
	f.close()
	# Comprobación: lo escrito se puede leer y coincide.
	if _leer(tmp).is_empty():
		DirAccess.remove_absolute(tmp)
		return "No se pudo comprobar la partida guardada."
	# (En Windows renombrar sobre un archivo que existe falla: se borra antes.)
	if FileAccess.file_exists(principal):
		if _leer(principal).is_empty():
			DirAccess.remove_absolute(principal)  # dañado: el respaldo bueno se conserva
		else:
			if FileAccess.file_exists(principal + ".bak"):
				DirAccess.remove_absolute(principal + ".bak")
			DirAccess.rename_absolute(principal, principal + ".bak")
	var err: Error = DirAccess.rename_absolute(tmp, principal)
	if err != OK:
		return "No se pudo guardar la partida (%s)." % error_string(err)
	GameState.slot = slot
	return ""


## Carga el slot en GameState (no cambia de escena).
func cargar(slot: int) -> Carga:
	var r := Carga.new()
	var contenido: Dictionary = _leer(ruta(slot))
	if contenido.is_empty():
		contenido = _leer(ruta(slot) + ".bak")
		r.de_respaldo = not contenido.is_empty()
	if contenido.is_empty():
		r.error = Textos.linea("txt_menu", 2466).replace("#", "\n").replace("@", "\n")
		return r
	GameState.desde_dict(_migrar(contenido).datos, slot)
	r.ok = true
	return r


## El resumen de un slot para la pantalla de cargar ({} si está vacío o dañado sin respaldo):
## nombre, mapa, equipo [[especie, nivel]...], tiempo (s), dinero, guardado (unix) y respaldo (bool).
func resumen(slot: int) -> Dictionary:
	var contenido: Dictionary = _leer(ruta(slot))
	var respaldo: bool = false
	if contenido.is_empty():
		contenido = _leer(ruta(slot) + ".bak")
		respaldo = true
	if contenido.is_empty():
		return {}
	var r: Dictionary = contenido.get("resumen", {}).duplicate()
	r["guardado"] = contenido.get("guardado", 0)
	r["respaldo"] = respaldo
	return r


## El slot guardado más recientemente, o 0 si no hay partidas.
func mas_reciente() -> int:
	var mejor: int = 0
	var cuando: float = -1.0
	for n: int in ocupados():
		var r: Dictionary = resumen(n)
		if not r.is_empty() and float(r.guardado) > cuando:
			cuando = float(r.guardado)
			mejor = n
	return mejor


## El nombre del perfil ("" si todavía no hay).
func nombre_perfil() -> String:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(ruta_perfil)) if FileAccess.file_exists(ruta_perfil) else null
	return limpiar_nombre(str(d.get("nombre", ""))) if d is Dictionary else ""


func guardar_perfil(nombre: String) -> void:
	var f: FileAccess = FileAccess.open(ruta_perfil, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"nombre": limpiar_nombre(nombre)}, "\t"))


## Sin espacios de sobra, sin # ni @ (separan líneas en los textos del original) y de 12 letras como mucho.
static func limpiar_nombre(nombre: String) -> String:
	return " ".join(nombre.replace("#", "").replace("@", "").strip_edges().split(" ", false)).left(LARGO_NOMBRE)


## Borra el slot y su respaldo.
func borrar(slot: int) -> void:
	for p: String in [ruta(slot), ruta(slot) + ".bak", ruta(slot).get_basename() + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	if GameState.slot == slot:
		GameState.slot = 0


func _resumen() -> Dictionary:
	return {
		"nombre": GameState.nombre_jugador,
		"mapa": GameState.mapa_actual,
		"equipo": GameState.equipo.map(func(p: PokemonInstance) -> Array:
			return [p.especie.id_original if p.especie else 0, p.nivel]),
		"tiempo": int(GameState.tiempo_juego),
		"dinero": GameState.dinero,
	}


## El contenido de un archivo de partida si es válido (formato y suma correctos), o {}.
func _leer(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var texto: String = FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(texto) != OK or not json.data is Dictionary:
		return {}
	var c: Dictionary = json.data
	if c.get("formato") != FORMATO or not c.get("datos") is Dictionary:
		return {}
	if int(c.get("version", 0)) > VERSION:
		return {}  # de una versión más nueva del juego
	if c.get("suma") != _suma(c.datos):
		return {}
	return c


## La suma se calcula sobre el JSON de "datos" con las claves ordenadas, para que no dependa del orden.
func _suma(datos: Dictionary) -> String:
	return JSON.stringify(datos, "", true).sha256_text()


## Pone al día una partida de una versión anterior del formato.
func _migrar(contenido: Dictionary) -> Dictionary:
	# VERSION 1 es la primera: no hay nada que migrar todavía.
	return contenido
