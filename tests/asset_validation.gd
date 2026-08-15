extends SceneTree

var failures := 0

func require(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("ASSET VALIDATION FAILURE: " + message)

func _init() -> void:
	var decor: Array[String] = []
	var visitors: Array[String] = []
	for file in DirAccess.get_files_at("res://assets/decor"):
		if file.ends_with(".png"): decor.append(file)
	for file in DirAccess.get_files_at("res://assets/visitors"):
		if file.ends_with(".png"): visitors.append(file)
	require(decor.size() == 20, "Expected 20 decor cutouts")
	var expected := ["01_pumpkin_cluster.png", "02_single_pumpkin.png", "03_apple_basket.png", "04_hay_bale.png", "05_corn_stalk_bundle.png", "06_wreath.png", "07_leaf_garland.png", "08_lantern.png", "09_pillar_candles.png", "10_welcome_sign.png", "11_porch_rug.png", "12_plaid_blanket.png", "13_porch_pillows.png", "14_orange_mums.png", "15_yellow_mums.png", "16_bench.png", "17_rocking_chair.png", "18_acorn_bowl.png", "19_bird_feeder.png", "20_string_lights.png"]
	for file in expected: require(decor.has(file), "Missing correctly mapped decor cutout: " + file)
	var base_visitors: Array[String] = []
	for file in visitors:
		if not file.contains("_walk_b"): base_visitors.append(file)
	require(base_visitors.size() == 6, "Expected six visitor frame-A cutouts")
	for file in base_visitors:
		var image := Image.load_from_file("res://assets/visitors/" + file)
		var walk_file := file.trim_suffix(".png") + "_walk_b.png"
		require(FileAccess.file_exists("res://assets/visitors/" + walk_file), "Missing walk-B pair: " + walk_file)
		var walk := Image.load_from_file("res://assets/visitors/" + walk_file)
		require(walk.get_size() == image.get_size(), "%s must match its A-frame canvas" % walk_file)
		validate_visitor_frame(image, file)
		validate_visitor_frame(walk, walk_file)
	if failures > 0:
		printerr("Asset validation failed with %d failure(s)." % failures)
		quit(1)
	print("Asset validation passed: 20 decor, six paired RGBA visitor walk frames with safe transparent margins.")
	quit(0)

func validate_visitor_frame(image: Image, file: String) -> void:
	require(image.get_format() == Image.FORMAT_RGBA8, "%s must be RGBA8" % file)
	require(image.get_pixel(0, 0).a == 0.0, "%s top-left must be transparent" % file)
	var opaque := 0
	var low_alpha := 0
	var magenta_edge := 0
	var crowded_edge := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a > 0.9: opaque += 1
			if pixel.a > 0.0 and pixel.a <= 63.0 / 255.0: low_alpha += 1
			if pixel.a > 0.03 and pixel.a < 0.98 and minf(pixel.r, pixel.b) - pixel.g > 0.12: magenta_edge += 1
			if pixel.a > 0.04 and (x < 4 or y < 4 or x >= image.get_width() - 4 or y >= image.get_height() - 4): crowded_edge += 1
	require(opaque > 500, "%s must retain a meaningful opaque subject" % file)
	require(float(low_alpha) / float(image.get_width() * image.get_height()) <= 0.05, "%s has a broad low-alpha keyed background field" % file)
	require(magenta_edge == 0, "%s still has a hot-magenta silhouette fringe" % file)
	require(crowded_edge == 0, "%s subject crowds a crop edge; retain transparent safety margins" % file)
