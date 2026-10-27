## Renderiza el paisaje de mapas extraídos (Fondos, TilesDebajo y TilesArriba, sin objetos) a PNG, para
## compararlo con el original (tools/comparar_mapas.py). Necesita ventana (no --headless):
##   godot --path nativo --script res://tools/render_mapa.gd -- <carpeta_salida> mapa [mapa...]
## (mapa = nombre de archivo sin .tscn, p. ej. pueblo_alba; "todos" = todos los extraídos)
extends SceneTree

const PAISAJE := ["Fondos", "TilesDebajo", "TilesArriba"]

func _initialize() -> void:
	_render.call_deferred()

func _render() -> void:
	var args := OS.get_cmdline_user_args()
	var salida: String = args[0]
	var mapas: Array = Array(args.slice(1))
	if mapas == ["todos"]:
		mapas = Array(DirAccess.get_files_at("res://assets/extraido/mapas")).filter(
			func(f): return f.ends_with(".tscn")).map(func(f): return f.get_basename())
	DirAccess.make_dir_recursive_absolute(salida)
	for m in mapas:
		var escena := load("res://assets/extraido/mapas/%s.tscn" % m) as PackedScene
		if escena == null:
			printerr("no existe ", m)
			continue
		var mapa := escena.instantiate()
		var tam: Vector2i = mapa.get("tamano")
		mapa.set_script(null) # solo el dibujo: sin la lógica del mapa
		for c in mapa.get_children():
			if not c.name in PAISAJE:
				mapa.remove_child(c)
				c.free()
		var vp := SubViewport.new()
		vp.size = tam
		# Sobre negro opaco, como compara tools/comparar_mapas.py (un viewport transparente devuelve los
		# fondos semitransparentes premultiplicados).
		var negro := ColorRect.new()
		negro.color = Color.BLACK
		negro.size = tam
		vp.add_child(negro)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		vp.add_child(mapa)
		root.add_child(vp)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(salida.path_join(m + ".png"))
		vp.queue_free()
		await process_frame
	quit()
