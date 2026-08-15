extends SceneTree

const PlacementLogicRef = preload("res://scripts/core/placement_logic.gd")
const SaveDataRef = preload("res://scripts/core/save_data.gd")
const VisitorSchedulerRef = preload("res://scripts/core/visitor_scheduler.gd")
const VisitorMotionRef = preload("res://scripts/visitors/visitor_motion.gd")
const VisitorActorRef = preload("res://scripts/visitors/visitor_actor.gd")
const MainScene = preload("res://scenes/main.tscn")
var failures := []

func expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message); push_error(message)

func _init() -> void:
	test_placement()
	test_save()
	test_visitors()
	test_visitor_motion()
	await test_ui_modes()
	if failures.is_empty(): print("ALL COZY FALL TESTS PASSED")
	else: print("TEST FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)

func test_placement() -> void:
	var empty := []
	var good := PlacementLogicRef.can_place(Vector2i(144, 540), Vector2i(1, 1), ["porch"], empty)
	expect(good.ok, "porch item should fit porch zone")
	var wrong := PlacementLogicRef.can_place(Vector2i(144, 540), Vector2i(1, 1), ["wall"], empty)
	expect(not wrong.ok, "wall item should reject porch zone")
	var placed := [{"position":Vector2i(144, 540), "footprint":Vector2i(2,1)}]
	var overlap := PlacementLogicRef.can_place(Vector2i(192, 540), Vector2i(1, 1), ["porch"], placed)
	expect(not overlap.ok, "overlap must reject")
	expect(PlacementLogicRef.depth_for(Vector2i(144,444)) > PlacementLogicRef.depth_for(Vector2i(144,396)), "depth follows y")
	var scale := PlacementLogicRef.render_scale(Vector2(160, 300), Vector2i(2,1))
	expect(160.0 * scale <= 96.1 and 300.0 * scale <= 48.1, "rendered decor must stay inside logical footprint tolerance")

func test_save() -> void:
	var data := SaveDataRef.default_data(); data.placed.append({"id":"lantern", "position":Vector2i(144,540), "footprint":Vector2i(1,1)})
	expect(SaveDataRef.save(data), "save writes local v1 file")
	var loaded := SaveDataRef.load_or_default(); expect(loaded.version == 1 and loaded.placed.size() == 1 and loaded.placed[0].position is Vector2i, "save roundtrip preserves v1 placement")
	var file := FileAccess.open(SaveDataRef.PATH, FileAccess.WRITE); file.store_string("this is not json"); file.close()
	expect(SaveDataRef.load_or_default().placed.is_empty(), "corrupt save falls back gracefully")
	var definitions: Array = [{"id":"lantern", "zones":["porch"], "footprint":Vector2i(1,1)}]
	var invalid: Array = [{"id":"unknown", "position":Vector2i(144,540), "footprint":Vector2i(1,1)}, {"id":"lantern", "position":"bad", "footprint":Vector2i(1,1)}, {"id":"lantern", "position":Vector2i(144,540), "footprint":Vector2i(3,1)}, {"id":"lantern", "position":Vector2i(144,540), "footprint":Vector2i(1,1)}, {"id":"lantern", "position":Vector2i(144,540), "footprint":Vector2i(1,1)}]
	expect(SaveDataRef.sanitize_placements(invalid, definitions).size() == 1, "invalid, unknown, and overlapping saved placements are ignored")

func test_visitors() -> void:
	var scheduler := VisitorSchedulerRef.new(12345)
	var seen := {}
	for i in 12:
		var visitor := scheduler.choose(["bird", "tea", "welcome", "garden"], float(i) * 500.0)
		if not visitor.is_empty(): seen[visitor.id] = true; scheduler.leave(visitor.id)
	expect(seen.size() >= 4, "seeded scheduler produces varied visitors")
	var first := scheduler.choose([], 9999.0); var second := scheduler.choose([], 10000.0); var third := scheduler.choose([], 10001.0)
	expect(not first.is_empty() and not second.is_empty() and third.is_empty(), "max two concurrent visitors")
	var cooldown := VisitorSchedulerRef.new(5); var v := cooldown.choose([], 0.0); cooldown.leave(v.id)
	for definition in cooldown.definitions: cooldown.last_seen[definition.id] = -1000.0
	cooldown.last_seen[v.id] = 0.0
	for i in 10:
		var choice := cooldown.choose([], 10.0); expect(choice.is_empty() or choice.id != v.id, "repeat cooldown excludes last visitor"); if not choice.is_empty(): cooldown.leave(choice.id)
	var app = MainScene.instantiate(); app.ambient = false; expect(app.visitor_interval() == 18.0, "edit visitor interval")
	app.ambient = true; expect(app.visitor_interval() <= 18.0, "ambient visits are at least as frequent")

func test_visitor_motion() -> void:
	var scheduler := VisitorSchedulerRef.new(77)
	for definition in scheduler.definitions:
		var width := float(definition.display_height) * 1.45
		var inbound := VisitorMotionRef.inbound_path(definition, width)
		var outbound := VisitorMotionRef.outbound_path(definition, width)
		expect(VisitorMotionRef.endpoint_is_fully_offscreen(inbound[0], width), "%s inbound starts fully offscreen" % definition.id)
		expect(VisitorMotionRef.endpoint_is_fully_offscreen(outbound[-1], width), "%s outbound ends fully offscreen" % definition.id)
		expect(VisitorMotionRef.is_supported_path(inbound, definition.surface), "%s inbound route uses supported surfaces" % definition.id)
		expect(VisitorMotionRef.is_supported_path(outbound, definition.surface), "%s outbound route reverses supported surfaces" % definition.id)
		for path in [inbound, outbound]:
			var facing := 1
			for i in path.size() - 1:
				var delta: Vector2 = path[i + 1] - path[i]
				facing = VisitorMotionRef.facing_for_delta(delta, facing)
				if absf(delta.x) > 0.5: expect(facing == (1 if delta.x > 0 else -1), "%s faces its horizontal segment" % definition.id)
	var actor := VisitorActorRef.new()
	var texture: Texture2D = load("res://assets/visitors/01_squirrel.png")
	var walk_texture: Texture2D = load("res://assets/visitors/01_squirrel_walk_b.png")
	actor.setup(texture, walk_texture, 100.0)
	var foot_before := actor.sprite.position.y + actor.texture_height * actor.sprite.scale.y * 0.5
	actor.walking = true; actor._process(0.20)
	var gait_changed := actor.sprite.texture == walk_texture and actor.sprite.scale == actor.base_scale
	var foot_during := actor.sprite.position.y + actor.texture_height * actor.sprite.scale.y * 0.5
	actor.walking = false; actor._reset_pose()
	var foot_idle := actor.sprite.position.y + actor.texture_height * actor.sprite.scale.y * 0.5
	expect(gait_changed and actor.sprite.texture == texture and absf(foot_before) < 0.01 and absf(foot_during) < 0.01 and absf(foot_idle) < 0.01, "visitor alternates authored walk frames, preserves the foot anchor, and resets A while idle")

func test_ui_modes() -> void:
	var app = MainScene.instantiate(); root.add_child(app)
	await process_frame
	expect(get_root().gui_get_focus_owner() == app.inventory_buttons[0], "first decor card grabs initial TV focus")
	app.begin_placement(app.DECOR[0]); await process_frame
	expect(app.mode == "placement" and get_root().gui_get_focus_owner() == null, "Select on card releases focus for placement")
	app.commit_placement(); await process_frame
	expect(app.mode == "inventory" and get_root().gui_get_focus_owner() == app.inventory_buttons[0], "place restores inventory focus")
	var initial_category: int = app.category_index
	app.next_category_button.grab_focus(); expect(get_root().gui_get_focus_owner() == app.next_category_button and app.next_category_button.focus_neighbor_bottom == app.inventory_buttons[0].get_path(), "Next Collection is TV-focusable with a D-pad route back to cards")
	app.next_category_button.emit_signal("pressed"); await process_frame
	expect(app.category_index == posmod(initial_category + 1, app.categories.size()) and get_root().gui_get_focus_owner() == app.inventory_buttons[0], "focused Next Collection changes category and restores card focus")
	app.enter_scene_mode(); app.cursor = app.placed[0].position; app.select_at_cursor(); await process_frame
	expect(app.mode == "context" and get_root().gui_get_focus_owner() == app.context_buttons[0], "Edit Scene reaches focused Move/Mirror/Store context")
	app.set_ambient(true); expect(app.mode == "ambient" and not app.ui.visible, "Ambient mode hides UI")
	var back := InputEventAction.new(); back.action = "ui_cancel"; back.pressed = true; app._unhandled_input(back); await process_frame
	expect(app.mode == "inventory" and app.ui.visible, "Back exits Ambient mode to decorating")
	root.remove_child(app)
	app.free()
