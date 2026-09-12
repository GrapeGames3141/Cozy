extends Node2D

const PlacementLogicRef = preload("res://scripts/core/placement_logic.gd")
const SaveDataRef = preload("res://scripts/core/save_data.gd")
const VisitorSchedulerRef = preload("res://scripts/core/visitor_scheduler.gd")
const VisitorMotionRef = preload("res://scripts/visitors/visitor_motion.gd")
const VisitorActorRef = preload("res://scripts/visitors/visitor_actor.gd")
const BASE_BOTTOM_MARGIN := 48
const DECOR := [
	{"id":"pumpkin_cluster","name":"Pumpkin Cluster","category":"Harvest","zones":["porch","yard"],"footprint":Vector2i(2,2),"tags":["pumpkin","warm"]},
	{"id":"single_pumpkin","name":"Single Pumpkin","category":"Harvest","zones":["porch","yard"],"footprint":Vector2i(1,1),"tags":["pumpkin"]},
	{"id":"apple_basket","name":"Apple Basket","category":"Harvest","zones":["porch","yard"],"footprint":Vector2i(1,1),"tags":["apple","harvest"]},
	{"id":"hay_bale","name":"Hay Bale","category":"Harvest","zones":["yard"],"footprint":Vector2i(3,2),"tags":["harvest"]},
	{"id":"corn_stalk_bundle","name":"Corn Stalk Bundle","category":"Harvest","zones":["porch","yard"],"footprint":Vector2i(2,3),"tags":["harvest"]},
	{"id":"wreath","name":"Maple Wreath","category":"Wall","zones":["wall"],"footprint":Vector2i(1,1),"tags":["welcome"]},
	{"id":"leaf_garland","name":"Leaf Garland","category":"Wall","zones":["wall","porch"],"footprint":Vector2i(3,1),"tags":["warm"]},
	{"id":"lantern","name":"Brass Lantern","category":"Porch","zones":["porch","yard"],"footprint":Vector2i(1,1),"tags":["lantern","warm"]},
	{"id":"pillar_candles","name":"Pillar Candles","category":"Porch","zones":["porch"],"footprint":Vector2i(1,1),"tags":["warm"]},
	{"id":"welcome_sign","name":"Welcome Sign","category":"Porch","zones":["porch","yard"],"footprint":Vector2i(1,1),"tags":["welcome"]},
	{"id":"porch_rug","name":"Porch Rug","category":"Porch","zones":["porch"],"footprint":Vector2i(2,1),"tags":["warm"]},
	{"id":"plaid_blanket","name":"Plaid Blanket","category":"Porch","zones":["porch"],"footprint":Vector2i(2,1),"tags":["blanket","warm"]},
	{"id":"porch_pillows","name":"Porch Pillows","category":"Porch","zones":["porch"],"footprint":Vector2i(2,1),"tags":["pillows","warm"]},
	{"id":"orange_mums","name":"Orange Mums","category":"Garden","zones":["porch","yard"],"footprint":Vector2i(1,1),"tags":["flowers","garden"]},
	{"id":"yellow_mums","name":"Yellow Mums","category":"Garden","zones":["porch","yard"],"footprint":Vector2i(1,1),"tags":["flowers","garden"]},
	{"id":"bench","name":"Garden Bench","category":"Garden","zones":["yard"],"footprint":Vector2i(3,2),"tags":["garden","warm"]},
	{"id":"rocking_chair","name":"Rocking Chair","category":"Porch","zones":["porch"],"footprint":Vector2i(2,3),"tags":["chair","warm"]},
	{"id":"acorn_bowl","name":"Acorn Bowl","category":"Harvest","zones":["porch","yard"],"footprint":Vector2i(1,1),"tags":["nuts"]},
	{"id":"bird_feeder","name":"Bird Feeder","category":"Garden","zones":["yard"],"footprint":Vector2i(1,2),"tags":["bird","nuts"]},
	{"id":"string_lights","name":"String Lights","category":"Wall","zones":["wall","porch"],"footprint":Vector2i(3,1),"tags":["warm"]},
]

var save_data: Dictionary
var placed: Array = []
var cursor := Vector2i(384, 528)
var placement: Dictionary = {}
var selected_index := -1
var ambient := false
var ui: CanvasLayer
var safe_margin: MarginContainer
var _ad_bar: Node
var inventory: VBoxContainer
var context_menu: HBoxContainer
var status_label: Label
var legend_label: Label
var title_label: Label
var category_index := 0
var categories := ["Harvest", "Porch", "Garden", "Wall"]
var mode := "inventory"
var inventory_buttons: Array[Button] = []
var edit_scene_button: Button
var context_buttons: Array[Button] = []
var previous_category_button: Button
var next_category_button: Button
var scheduler
var visitor_layer: Node2D
var next_visit := 5.0
var elapsed := 0.0
var leaves := []
var capture_requested := false
var capture_visitor_id := "squirrel"
var capture_wait_seconds := 5.0

func _ready() -> void:
	set_process(true)
	save_data = SaveDataRef.load_or_default()
	placed = SaveDataRef.sanitize_placements(save_data.placed, DECOR)
	save_data.placed = placed
	ambient = bool(save_data.get("ambient", false))
	scheduler = VisitorSchedulerRef.new()
	build_world()
	build_ui()
	var capture_args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if capture_args.has("--capture"):
		capture_requested = true
		next_visit = INF
		for argument in capture_args:
			if argument.begins_with("--capture-visitor="): capture_visitor_id = argument.trim_prefix("--capture-visitor=")
			if argument.begins_with("--capture-delay="): capture_wait_seconds = maxf(0.1, argument.trim_prefix("--capture-delay=").to_float())
	set_ambient(ambient)
	if capture_requested: call_deferred("spawn_capture_visitor"); call_deferred("capture_preview")

func build_world() -> void:
	var background := Sprite2D.new()
	background.texture = load("res://assets/backgrounds/cottage_yard.png")
	background.position = Vector2(960, 540)
	background.scale = Vector2(1920.0 / 1672.0, 1080.0 / 941.0)
	background.z_index = -20
	add_child(background)
	visitor_layer = Node2D.new(); visitor_layer.z_index = 30; add_child(visitor_layer)
	for record in placed: add_decor_sprite(record)
	for i in 20:
		leaves.append({"p":Vector2((i * 163) % 1920, (i * 89) % 1080), "speed":24.0 + (i % 7) * 6.0, "phase":float(i)})
	queue_redraw()

func build_ui() -> void:
	ui = CanvasLayer.new(); add_child(ui)
	safe_margin = MarginContainer.new(); safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe_margin.add_theme_constant_override("margin_left", 72); safe_margin.add_theme_constant_override("margin_right", 72)
	safe_margin.add_theme_constant_override("margin_top", 48); ui.add_child(safe_margin)
	var ad_bar := ad_bar_service()
	if ad_bar != null:
		apply_banner_height(ad_bar.banner_height())
		ad_bar.banner_height_changed.connect(apply_banner_height)
	else:
		apply_banner_height(0.0)
	var root := VBoxContainer.new(); root.add_theme_constant_override("separation", 14); safe_margin.add_child(root)
	title_label = Label.new(); title_label.text = "COZY FALL"; title_label.add_theme_font_size_override("font_size", 44); title_label.add_theme_color_override("font_color", Color("fff1cf")); root.add_child(title_label)
	status_label = Label.new(); status_label.text = "Arrange the porch, invite a little wonder."; status_label.add_theme_font_size_override("font_size", 25); status_label.add_theme_color_override("font_color", Color("f9d997")); root.add_child(status_label)
	var controls := HBoxContainer.new(); controls.add_theme_constant_override("separation", 18); root.add_child(controls)
	var ambient_button := make_button("Ambient Mode", func(): set_ambient(true)); controls.add_child(ambient_button)
	edit_scene_button = make_button("Edit Scene", enter_scene_mode); controls.add_child(edit_scene_button)
	var save_button := make_button("Save Garden", save_now); controls.add_child(save_button)
	var hint := Label.new(); hint.text = "No currency. Just cozy."; hint.add_theme_font_size_override("font_size", 20); hint.add_theme_color_override("font_color", Color("e7c9a8")); controls.add_child(hint)
	inventory = VBoxContainer.new(); inventory.position = Vector2(0, 0); root.add_child(inventory)
	legend_label = Label.new(); legend_label.add_theme_font_size_override("font_size", 23); legend_label.add_theme_color_override("font_color", Color("fff1cf")); root.add_child(legend_label)
	context_menu = HBoxContainer.new(); context_menu.add_theme_constant_override("separation", 14); context_menu.visible = false; root.add_child(context_menu)
	for action in [["Move", begin_move_selected], ["Mirror", mirror_selected], ["Store", store_selected]]:
		var button: Button = make_button(action[0], action[1]); context_buttons.append(button); context_menu.add_child(button)
	rebuild_inventory()
	call_deferred("focus_initial_control")

## The AdBarService autoload, or null. Headless tool/test runs start without
## autoloads, so the scene must stay usable when the ad bar is absent.
func ad_bar_service() -> Node:
	if is_instance_valid(_ad_bar): return _ad_bar
	var tree := get_tree()
	if tree != null and tree.root != null and tree.root.has_node("AdBarService"):
		_ad_bar = tree.root.get_node("AdBarService")
	return _ad_bar

## Keeps the bottom row of chrome clear of the AdMob banner. Returns to the
## plain TV safe-area inset whenever the bar is absent or suppressed.
func apply_banner_height(height: float) -> void:
	if not is_instance_valid(safe_margin): return
	safe_margin.add_theme_constant_override("margin_bottom", BASE_BOTTOM_MARGIN + int(roundf(maxf(0.0, height))))

func focus_initial_control() -> void:
	if not inventory_buttons.is_empty(): inventory_buttons[0].grab_focus()

func restore_inventory_focus() -> void:
	mode = "inventory"
	call_deferred("focus_initial_control")

func enter_scene_mode() -> void:
	mode = "scene"; get_viewport().gui_release_focus(); status_label.text = "Edit Scene: move the cursor over placed decor, then Select."; update_legend(); queue_redraw()

func make_button(text_value: String, action: Callable) -> Button:
	var button := Button.new(); button.text = text_value; button.custom_minimum_size = Vector2(250, 60); button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 25); button.pressed.connect(action)
	return button

func rebuild_inventory() -> void:
	for child in inventory.get_children(): child.queue_free()
	inventory_buttons.clear()
	var collection_row := HBoxContainer.new(); collection_row.add_theme_constant_override("separation", 12); inventory.add_child(collection_row)
	previous_category_button = make_button("◀ Previous Collection", func(): change_category(-1)); previous_category_button.custom_minimum_size = Vector2(290, 58); collection_row.add_child(previous_category_button)
	var heading := Label.new(); heading.text = "Decor Collection: %s" % categories[category_index]; heading.custom_minimum_size = Vector2(380, 58); heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; heading.add_theme_font_size_override("font_size", 29); heading.add_theme_color_override("font_color", Color("fff1cf")); collection_row.add_child(heading)
	next_category_button = make_button("Next Collection ▶", func(): change_category(1)); next_category_button.custom_minimum_size = Vector2(270, 58); collection_row.add_child(next_category_button)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 12); inventory.add_child(row)
	for definition in DECOR:
		if definition.category != categories[category_index]: continue
		var button := make_button(definition.name, func(d = definition): begin_placement(d))
		button.custom_minimum_size = Vector2(215, 72); inventory_buttons.append(button); row.add_child(button)
	for index in inventory_buttons.size():
		inventory_buttons[index].focus_neighbor_left = inventory_buttons[posmod(index - 1, inventory_buttons.size())].get_path()
		inventory_buttons[index].focus_neighbor_right = inventory_buttons[posmod(index + 1, inventory_buttons.size())].get_path()
		inventory_buttons[index].focus_neighbor_top = previous_category_button.get_path()
	previous_category_button.focus_neighbor_right = next_category_button.get_path()
	next_category_button.focus_neighbor_left = previous_category_button.get_path()
	previous_category_button.focus_neighbor_bottom = inventory_buttons[0].get_path()
	next_category_button.focus_neighbor_bottom = inventory_buttons[0].get_path()
	update_legend()

func change_category(direction: int) -> void:
	category_index = posmod(category_index + direction, categories.size())
	rebuild_inventory()
	call_deferred("focus_initial_control")

func update_legend() -> void:
	if ambient: legend_label.text = "D-pad: enjoy the yard    Select / Back: return to decorating"
	elif mode == "placement": legend_label.text = "D-pad: move ghost    Select: place    Back: cancel"
	elif mode == "context": legend_label.text = "D-pad: choose Move, Mirror, or Store    Back: return to scene"
	elif mode == "scene": legend_label.text = "D-pad: move cursor   Select: select decor   Back: inventory"
	else: legend_label.text = "D-pad: navigate decor cards   Select: place   Edit Scene: manage placed decor"

func begin_placement(definition: Dictionary) -> void:
	mode = "placement"; get_viewport().gui_release_focus(); placement = definition; cursor = PlacementLogicRef.snap(Vector2(720, 540)); status_label.text = "Place %s" % definition.name; update_legend(); queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo(): return
	if ambient and (event.is_action("ui_accept") or event.is_action("ui_cancel")):
		set_ambient(false); get_viewport().set_input_as_handled(); return
	if event.is_action("ui_cancel"):
		if mode == "placement": placement = {}; status_label.text = "Placement cancelled."; restore_inventory_focus()
		elif mode == "context": context_menu.visible = false; selected_index = -1; mode = "scene"; get_viewport().gui_release_focus()
		elif mode == "scene": restore_inventory_focus()
		else: status_label.text = "Choose a decor card, then place it in the yard."
		update_legend(); queue_redraw(); return
	var delta := Vector2i.ZERO
	if event.is_action("ui_left"): delta.x = -PlacementLogicRef.CELL.x
	elif event.is_action("ui_right"): delta.x = PlacementLogicRef.CELL.x
	elif event.is_action("ui_up"): delta.y = -PlacementLogicRef.CELL.y
	elif event.is_action("ui_down"): delta.y = PlacementLogicRef.CELL.y
	if delta != Vector2i.ZERO:
		if mode == "context" and (event.is_action("ui_left") or event.is_action("ui_right")):
			mirror_selected()
		elif mode == "inventory" and placement.is_empty() and (event.is_action("ui_left") or event.is_action("ui_right")):
			# Collection switching is deliberately exposed through focusable buttons above the cards.
			pass
		else: cursor = Vector2i(clampi(cursor.x + delta.x, 0, 1872), clampi(cursor.y + delta.y, 96, 1032))
		queue_redraw(); return
	if event.is_action("ui_accept"):
		if mode == "placement": commit_placement()
		elif mode == "scene": select_at_cursor()
		get_viewport().set_input_as_handled()

func commit_placement() -> void:
	var result: Dictionary = PlacementLogicRef.can_place(cursor, placement.footprint, placement.zones, placed)
	if not result.ok: status_label.text = result.reason; return
	var record: Dictionary = {"id":placement.id, "position":cursor, "footprint":placement.footprint, "mirrored":false}
	placed.append(record); add_decor_sprite(record); placement = {}; status_label.text = "Lovely. %s is right at home." % record.id.capitalize(); save_now(); restore_inventory_focus(); update_legend(); queue_redraw()

func select_at_cursor() -> void:
	selected_index = -1
	for index in placed.size():
		if PlacementLogicRef.footprint_rect(placed[index].position, placed[index].footprint).has_point(cursor): selected_index = index; break
	status_label.text = "Move, mirror, or store this decor." if selected_index >= 0 else "Nothing there yet — pick a decor card."
	context_menu.visible = selected_index >= 0
	if selected_index >= 0: mode = "context"; call_deferred("focus_context")
	update_legend(); queue_redraw()

func begin_move_selected() -> void:
	if selected_index < 0: return
	placement = decor_definition(placed[selected_index].id); cursor = placed[selected_index].position; placed.remove_at(selected_index); selected_index = -1
	mode = "placement"; get_viewport().gui_release_focus(); context_menu.visible = false
	for child in get_tree().get_nodes_in_group("decor_sprite"): child.queue_free()
	for record in placed: add_decor_sprite(record)
	status_label.text = "Move the decor, then Select to set it down."; update_legend()

func store_selected() -> void:
	if selected_index < 0: return
	placed.remove_at(selected_index); selected_index = -1; mode = "scene"
	context_menu.visible = false
	for child in get_tree().get_nodes_in_group("decor_sprite"): child.queue_free()
	for record in placed: add_decor_sprite(record)
	save_now(); status_label.text = "Stored safely in your collection."; update_legend(); queue_redraw()

func mirror_selected() -> void:
	if selected_index < 0: return
	placed[selected_index].mirrored = not bool(placed[selected_index].get("mirrored", false))
	for child in get_tree().get_nodes_in_group("decor_sprite"): child.queue_free()
	for record in placed: add_decor_sprite(record)
	save_now(); status_label.text = "Mirrored for a fresh little composition."; update_legend()

func focus_context() -> void:
	if not context_buttons.is_empty(): context_buttons[0].grab_focus()

func decor_definition(id: String) -> Dictionary:
	for definition in DECOR:
		if definition.id == id: return definition
	return {}

func add_decor_sprite(record: Dictionary) -> void:
	var definition: Dictionary = decor_definition(record.id)
	var index := DECOR.find(definition) + 1
	var sprite := Sprite2D.new(); sprite.texture = load("res://assets/decor/%02d_%s.png" % [index, definition.id])
	sprite.position = Vector2(record.position) + Vector2(record.footprint * PlacementLogicRef.CELL) / 2.0
	var scale := PlacementLogicRef.render_scale(sprite.texture.get_size(), record.footprint)
	sprite.scale = Vector2(scale, scale)
	var rendered_bounds := sprite.texture.get_size() * scale
	assert(rendered_bounds.x <= float(record.footprint.x * PlacementLogicRef.CELL.x) * 1.01 and rendered_bounds.y <= float(record.footprint.y * PlacementLogicRef.CELL.y) * 1.01)
	sprite.z_index = PlacementLogicRef.depth_for(record.position); sprite.flip_h = bool(record.get("mirrored", false)); sprite.add_to_group("decor_sprite"); add_child(sprite)

func set_ambient(value: bool) -> void:
	ambient = value; mode = "ambient" if value else "inventory"; ui.visible = not value; DisplayServer.screen_set_keep_on(value)
	var ad_bar := ad_bar_service()
	if ad_bar != null: ad_bar.set_suppressed(value)
	if not value: status_label.text = "Welcome back to decorating."; call_deferred("focus_initial_control"); update_legend()
	queue_redraw()

func save_now() -> void:
	save_data.placed = placed; save_data.ambient = ambient; SaveDataRef.save(save_data); status_label.text = "Your cozy corner is saved."

func _process(delta: float) -> void:
	elapsed += delta
	for leaf in leaves:
		leaf.p.x -= leaf.speed * delta; leaf.p.y += sin(elapsed + leaf.phase) * delta * 12.0
		if leaf.p.x < -20: leaf.p.x = 1940; leaf.p.y = fmod(leaf.p.y + 137.0, 1080.0)
	if elapsed >= next_visit and placement.is_empty() and selected_index < 0:
		spawn_visitor(); next_visit = elapsed + visitor_interval()
	queue_redraw()

func capture_preview() -> void:
	# Let the deterministic visitor complete its supported inbound walk before the capture.
	await get_tree().create_timer(capture_wait_seconds).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		push_error("Runtime capture requires a GPU viewport; no image was returned.")
		get_tree().quit(1)
		return
	image.save_png("res://previews/runtime_capture_%dx%d.png" % [get_viewport().size.x, get_viewport().size.y])
	capture_requested = false
	get_tree().quit()

func visitor_interval() -> float:
	return 9.0 if ambient else 18.0

func spawn_visitor() -> void:
	var tags: Array = []
	for record in placed:
		for tag in decor_definition(record.id).tags:
			if not tags.has(tag): tags.append(tag)
	var visitor: Dictionary = scheduler.choose(tags, elapsed)
	if visitor.is_empty(): return
	spawn_visitor_definition(visitor)

func spawn_capture_visitor() -> void:
	# Captures always show a complete, grounded visitor rather than an offscreen entry.
	for definition in scheduler.definitions:
		if definition.id == capture_visitor_id: spawn_visitor_definition(definition); return
	spawn_visitor_definition(scheduler.definitions[0])

func spawn_visitor_definition(visitor: Dictionary) -> void:
	var idx := ["squirrel","rabbit","fox","raccoon","black_cat","white_maltipoo"].find(visitor.id) + 1
	var texture: Texture2D = load("res://assets/visitors/%02d_%s.png" % [idx, visitor.id])
	var walk_texture: Texture2D = load("res://assets/visitors/%02d_%s_walk_b.png" % [idx, visitor.id])
	var actor: Node2D = VisitorActorRef.new(); actor.setup(texture, walk_texture, float(visitor.display_height)); actor.z_index = 1000; visitor_layer.add_child(actor)
	var rendered_width := texture.get_size().x * float(visitor.display_height) / texture.get_size().y
	var inbound := VisitorMotionRef.inbound_path(visitor, rendered_width)
	var outbound := VisitorMotionRef.outbound_path(visitor, rendered_width)
	var phase := 0
	actor.route_finished.connect(func():
		if phase == 0:
			phase = 1
			get_tree().create_timer(2.0).timeout.connect(func(): actor.play_path(outbound))
		else:
			scheduler.leave(visitor.id)
			actor.queue_free())
	actor.play_path(inbound)
	status_label.text = "%s came by to admire the %s." % [visitor.id.replace("_", " ").capitalize(), visitor.interaction.replace("_", " ")]

func _draw() -> void:
	for leaf in leaves:
		var color := Color("e99a3d", 0.72) if int(leaf.phase) % 2 == 0 else Color("c85d35", 0.68)
		var axis := Vector2(cos(elapsed * 0.8 + leaf.phase), sin(elapsed * 0.8 + leaf.phase))
		var cross := Vector2(-axis.y, axis.x)
		draw_colored_polygon(PackedVector2Array([leaf.p + axis * 7.0, leaf.p + cross * 3.2, leaf.p - axis * 7.0, leaf.p - cross * 3.2]), color)
	if not placement.is_empty():
		var rect := PlacementLogicRef.footprint_rect(cursor, placement.footprint)
		var check: Dictionary = PlacementLogicRef.can_place(cursor, placement.footprint, placement.zones, placed)
		draw_rect(rect, Color(0.5, 0.9, 0.5, 0.38) if check.ok else Color(0.95, 0.25, 0.2, 0.45), true)
		draw_rect(rect, Color("fff1cf"), false, 3.0)
	elif not ambient:
		draw_rect(Rect2(cursor, PlacementLogicRef.CELL), Color("fff1cf"), false, 2.0)
