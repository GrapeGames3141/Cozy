class_name VisitorScheduler
extends RefCounted

const MAX_CONCURRENT := 2
const COOLDOWN_SECONDS := 180.0
var rng := RandomNumberGenerator.new()
var active: Array[String] = []
var last_seen := {}
var definitions := [
	{"id":"squirrel", "weight":4.0, "tags":["bird", "nuts"], "entry_side":"right", "surface":"yard", "interaction":"bird_feeder", "display_height":100.0},
	{"id":"rabbit", "weight":3.0, "tags":["flowers", "garden"], "entry_side":"left", "surface":"yard", "interaction":"orange_mums", "display_height":125.0},
	{"id":"fox", "weight":2.0, "tags":["lantern", "harvest"], "entry_side":"right", "surface":"porch", "interaction":"lantern", "display_height":170.0},
	{"id":"raccoon", "weight":2.0, "tags":["pumpkin", "apple"], "entry_side":"right", "surface":"porch", "interaction":"apple_basket", "display_height":145.0},
	{"id":"black_cat", "weight":3.0, "tags":["chair", "warm"], "entry_side":"left", "surface":"porch", "interaction":"rocking_chair", "display_height":125.0},
	{"id":"white_maltipoo", "weight":3.0, "tags":["blanket", "pillows", "welcome"], "entry_side":"left", "surface":"porch", "interaction":"plaid_blanket", "display_height":120.0},
]

func _init(seed: int = 0) -> void:
	if seed == 0: rng.randomize()
	else: rng.seed = seed

func choose(decor_tags: Array, now: float) -> Dictionary:
	if active.size() >= MAX_CONCURRENT: return {}
	var options := []
	var total := 0.0
	for definition in definitions:
		if now - float(last_seen.get(definition.id, -COOLDOWN_SECONDS * 2.0)) < COOLDOWN_SECONDS: continue
		var weight: float = definition.weight
		for tag in definition.tags:
			if decor_tags.has(tag): weight += 2.0
		options.append({"definition": definition, "weight": weight}); total += weight
	if options.is_empty(): return {}
	var roll := rng.randf() * total
	for option in options:
		roll -= option.weight
		if roll <= 0.0:
			var selected: Dictionary = option.definition
			active.append(selected.id); last_seen[selected.id] = now
			return selected
	return {}

func leave(visitor_id: String) -> void:
	active.erase(visitor_id)
