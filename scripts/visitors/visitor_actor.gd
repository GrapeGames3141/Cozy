class_name VisitorActor
extends Node2D

const VisitorMotionRef = preload("res://scripts/visitors/visitor_motion.gd")

signal route_finished
var sprite := Sprite2D.new()
var frame_a: Texture2D
var frame_b: Texture2D
var base_scale := Vector2.ONE
var texture_height := 1.0
var facing := 1
var walking := false
var gait_elapsed := 0.0
var gait_cadence := 7.0
var route := PackedVector2Array()
var route_index := 0

func setup(texture_a: Texture2D, texture_b: Texture2D, height: float) -> void:
	frame_a = texture_a; frame_b = texture_b; sprite.texture = frame_a; texture_height = frame_a.get_size().y
	base_scale = Vector2.ONE * (height / texture_height); sprite.scale = base_scale
	add_child(sprite); _reset_pose()

func play_path(points: PackedVector2Array) -> void:
	route = points; route_index = 0; position = route[0]; _advance_segment()

func _advance_segment() -> void:
	if route_index >= route.size() - 1:
		walking = false; _reset_pose(); route_finished.emit(); return
	var delta := route[route_index + 1] - position
	facing = VisitorMotionRef.facing_for_delta(delta, facing); sprite.flip_h = facing < 0; walking = true
	var tween := create_tween()
	tween.tween_property(self, "position", route[route_index + 1], maxf(0.28, delta.length() / 190.0)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func(): route_index += 1; _advance_segment())

func _process(delta: float) -> void:
	if walking:
		gait_elapsed += delta
		# Alternate authored opposite leg poses; no procedural squash/stretch.
		sprite.texture = frame_b if int(floor(gait_elapsed * gait_cadence)) % 2 == 1 else frame_a
		sprite.position = Vector2(0, -texture_height * base_scale.y * 0.5)

func _reset_pose() -> void:
	gait_elapsed = 0.0; sprite.texture = frame_a; sprite.scale = base_scale; sprite.position = Vector2(0, -texture_height * base_scale.y * 0.5)
