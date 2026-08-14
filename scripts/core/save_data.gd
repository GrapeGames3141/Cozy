class_name SaveDataV1
extends RefCounted

const PATH := "user://cozy_fall_save.json"
const VERSION := 1
const PlacementLogicRef = preload("res://scripts/core/placement_logic.gd")

static func default_data() -> Dictionary:
	return {"version": VERSION, "placed": [], "ambient": false, "last_visitor": {}, "visitor_history": []}

static func save(data: Dictionary) -> bool:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(to_json_data(data)))
	return true

static func load_or_default() -> Dictionary:
	if not FileAccess.file_exists(PATH): return default_data()
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null: return default_data()
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not (json.data is Dictionary):
		return default_data()
	var data: Dictionary = json.data
	if int(data.get("version", -1)) != VERSION or not (data.get("placed", []) is Array): return default_data()
	return from_json_data(data)

static func to_json_data(data: Dictionary) -> Dictionary:
	var output: Dictionary = data.duplicate(true)
	var serialized: Array = []
	for raw in data.get("placed", []):
		if not raw is Dictionary: continue
		var record: Dictionary = raw.duplicate(true)
		for field in ["position", "footprint"]:
			var value: Variant = record.get(field)
			if value is Vector2i: record[field] = [value.x, value.y]
		serialized.append(record)
	output["placed"] = serialized
	return output

static func from_json_data(data: Dictionary) -> Dictionary:
	var output: Dictionary = data.duplicate(true)
	var restored: Array = []
	for raw in data.get("placed", []):
		if not raw is Dictionary: continue
		var record: Dictionary = raw.duplicate(true)
		for field in ["position", "footprint"]:
			var value: Variant = record.get(field, [])
			if value is Array and value.size() == 2: record[field] = Vector2i(int(value[0]), int(value[1]))
		if record.get("position") is Vector2i and record.get("footprint") is Vector2i: restored.append(record)
	output["placed"] = restored
	return output

static func sanitize_placements(records: Array, definitions: Array) -> Array:
	var by_id := {}
	for definition in definitions:
		if definition is Dictionary and definition.get("id") is String: by_id[definition.id] = definition
	var accepted: Array = []
	for raw in records:
		if not raw is Dictionary or not raw.get("id") is String or not by_id.has(raw.id): continue
		var definition: Dictionary = by_id[raw.id]
		var position: Variant = raw.get("position")
		var footprint: Variant = raw.get("footprint")
		if not position is Vector2i or not footprint is Vector2i or footprint != definition.footprint: continue
		var check: Dictionary = PlacementLogicRef.can_place(position, footprint, definition.zones, accepted)
		if not check.ok: continue
		accepted.append({"id": raw.id, "position": position, "footprint": footprint, "mirrored": bool(raw.get("mirrored", false))})
	return accepted
