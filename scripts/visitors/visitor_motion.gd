class_name VisitorMotion
extends RefCounted

const SCREEN_WIDTH := 1920.0
const OFFSCREEN_PADDING := 32.0
const YARD_FOOTLINE := 842.0
const STEP_BASE_Y := 816.0
const STEP_MID_Y := 764.0
const PORCH_FOOTLINE := 704.0

static func offscreen_foot(side: String, rendered_width: float) -> Vector2:
	var outside := rendered_width * 0.5 + OFFSCREEN_PADDING
	return Vector2(SCREEN_WIDTH + outside if side == "right" else -outside, YARD_FOOTLINE)

static func interaction_foot(interaction: String) -> Vector2:
	var targets := {"bird_feeder":Vector2(1240, YARD_FOOTLINE), "orange_mums":Vector2(1050, YARD_FOOTLINE), "lantern":Vector2(790, PORCH_FOOTLINE), "apple_basket":Vector2(900, PORCH_FOOTLINE), "rocking_chair":Vector2(700, PORCH_FOOTLINE), "plaid_blanket":Vector2(850, PORCH_FOOTLINE)}
	return targets.get(interaction, Vector2(1100, YARD_FOOTLINE))

static func inbound_path(definition: Dictionary, rendered_width: float) -> PackedVector2Array:
	var side: String = definition.get("entry_side", "left")
	var target := interaction_foot(str(definition.get("interaction", "")))
	var path := PackedVector2Array([offscreen_foot(side, rendered_width), Vector2(1715 if side == "right" else 205, YARD_FOOTLINE)])
	if definition.get("surface", "yard") == "yard": path.append(target); return path
	var step_x := 1010.0 if side == "right" else 910.0
	path.append(Vector2(step_x, STEP_BASE_Y)); path.append(Vector2(step_x, STEP_MID_Y)); path.append(Vector2(step_x, PORCH_FOOTLINE)); path.append(target)
	return path

static func outbound_path(definition: Dictionary, rendered_width: float) -> PackedVector2Array:
	var inbound := inbound_path(definition, rendered_width); inbound.reverse(); return inbound

static func facing_for_delta(delta: Vector2, current_facing: int = 1) -> int:
	if delta.x > 0.5: return 1
	if delta.x < -0.5: return -1
	return current_facing

static func endpoint_is_fully_offscreen(point: Vector2, rendered_width: float) -> bool:
	return point.x + rendered_width * 0.5 < 0.0 or point.x - rendered_width * 0.5 > SCREEN_WIDTH

static func is_supported_path(path: PackedVector2Array, surface: String) -> bool:
	if path.size() < 3: return false
	for point in path:
		if point.y < PORCH_FOOTLINE - 0.1 or point.y > YARD_FOOTLINE + 0.1: return false
	if surface == "yard":
		for point in path:
			if absf(point.y - YARD_FOOTLINE) > 0.1: return false
	else:
		var starts_on_yard := absf(path[0].y - YARD_FOOTLINE) < 0.1
		var ends_on_yard := absf(path[-1].y - YARD_FOOTLINE) < 0.1
		if not starts_on_yard and not ends_on_yard: return false
		var has_step_base := false
		var has_step_mid := false
		for point in path:
			has_step_base = has_step_base or absf(point.y - STEP_BASE_Y) < 0.1
			has_step_mid = has_step_mid or absf(point.y - STEP_MID_Y) < 0.1
		if not has_step_base or not has_step_mid: return false
		var porch_endpoint := path[-1] if starts_on_yard else path[0]
		if absf(porch_endpoint.y - PORCH_FOOTLINE) > 0.1: return false
	return true
