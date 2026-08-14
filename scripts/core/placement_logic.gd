class_name PlacementLogic
extends RefCounted

const CELL := Vector2i(48, 48)
const ZONES := {
	"wall": Rect2i(72, 168, 1776, 360),
	"porch": Rect2i(72, 528, 1776, 192),
	"yard": Rect2i(0, 720, 1920, 360),
}

static func snap(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL.x) * CELL.x, floori(point.y / CELL.y) * CELL.y)

static func zone_at(position: Vector2i) -> String:
	for name in ZONES:
		if ZONES[name].has_point(position + CELL / 2): return name
	return ""

static func footprint_rect(position: Vector2i, footprint: Vector2i) -> Rect2i:
	return Rect2i(position, footprint * CELL)

static func can_place(position: Vector2i, footprint: Vector2i, allowed_zones: Array, placed: Array) -> Dictionary:
	var rect := footprint_rect(position, footprint)
	var zone := zone_at(position)
	if zone.is_empty() or not allowed_zones.has(zone): return {"ok": false, "reason": "That decor belongs somewhere else."}
	if not ZONES[zone].encloses(rect): return {"ok": false, "reason": "Keep it inside the %s." % zone}
	for item in placed:
		if rect.intersects(footprint_rect(item.position, item.footprint)):
			return {"ok": false, "reason": "That spot is already cozy."}
	return {"ok": true, "reason": ""}

static func depth_for(position: Vector2i) -> int:
	return position.y + CELL.y

static func render_scale(texture_size: Vector2, footprint: Vector2i) -> float:
	var target := Vector2(footprint * CELL) * 0.90
	var scale := minf(target.x / texture_size.x, target.y / texture_size.y)
	assert(texture_size * scale <= Vector2(footprint * CELL) * 1.01, "Decor render bounds exceed logical footprint")
	return scale
