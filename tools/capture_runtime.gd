## Real offscreen scene renders for CI evidence; captures the actual main UI, decor, and a visitor.
extends SceneTree

const MAIN := preload("res://scenes/main.tscn")

func _init() -> void:
	await capture(Vector2i(1280, 720), false)
	await capture(Vector2i(1920, 1080), false)
	await capture(Vector2i(1920, 1080), true)
	print("Saved real Cozy Fall runtime captures.")
	quit()

func capture(size: Vector2i, ambient: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = size; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false; root.add_child(viewport)
	var app = MAIN.instantiate(); viewport.add_child(app)
	await process_frame
	app.placed.append({"id":"pumpkin_cluster", "position":Vector2i(720, 576), "footprint":Vector2i(2,2), "mirrored":false})
	app.add_decor_sprite(app.placed.back())
	app.placed.append({"id":"rocking_chair", "position":Vector2i(576, 528), "footprint":Vector2i(2,3), "mirrored":false})
	app.add_decor_sprite(app.placed.back())
	app.spawn_visitor()
	if visitor_layer_has_child(app): app.visitor_layer.get_child(0).position = Vector2(1150, 760)
	if ambient: app.set_ambient(true)
	await process_frame
	await process_frame
	var suffix := "ambient" if ambient else "edit"
	viewport.get_texture().get_image().save_png("res://previews/cozyfall_runtime_%s_%dx%d.png" % [suffix, size.x, size.y])
	viewport.queue_free()

func visitor_layer_has_child(app) -> bool:
	return app.visitor_layer.get_child_count() > 0
