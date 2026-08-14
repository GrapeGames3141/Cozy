extends SceneTree

func _init() -> void:
	var decor: Array[String] = []
	var visitors: Array[String] = []
	for file in DirAccess.get_files_at("res://assets/decor"):
		if file.ends_with(".png"): decor.append(file)
	for file in DirAccess.get_files_at("res://assets/visitors"):
		if file.ends_with(".png"): visitors.append(file)
	assert(decor.size() == 20, "Expected 20 decor cutouts")
	var expected := ["01_pumpkin_cluster.png", "02_single_pumpkin.png", "03_apple_basket.png", "04_hay_bale.png", "05_corn_stalk_bundle.png", "06_wreath.png", "07_leaf_garland.png", "08_lantern.png", "09_pillar_candles.png", "10_welcome_sign.png", "11_porch_rug.png", "12_plaid_blanket.png", "13_porch_pillows.png", "14_orange_mums.png", "15_yellow_mums.png", "16_bench.png", "17_rocking_chair.png", "18_acorn_bowl.png", "19_bird_feeder.png", "20_string_lights.png"]
	for file in expected: assert(decor.has(file), "Missing correctly mapped decor cutout: " + file)
	assert(visitors.size() == 6, "Expected six visitor cutouts")
	for file in visitors:
		var image := Image.load_from_file("res://assets/visitors/" + file)
		assert(image.get_format() == Image.FORMAT_RGBA8, "%s must be RGBA8" % file)
		assert(image.get_pixel(0, 0).a == 0.0, "%s top-left must be transparent" % file)
		var opaque := 0
		var magenta_edge := 0
		for y in image.get_height():
			for x in image.get_width():
				var pixel: Color = image.get_pixel(x, y)
				if pixel.a > 0.9: opaque += 1
				if pixel.a > 0.03 and pixel.a < 0.98 and minf(pixel.r, pixel.b) - pixel.g > 0.12: magenta_edge += 1
		assert(opaque > 500, "%s must retain a meaningful opaque subject" % file)
		assert(magenta_edge == 0, "%s still has a hot-magenta silhouette fringe" % file)
	print("Asset validation passed: 20 decor, 6 RGBA visitor cutouts with transparent corners and subject coverage.")
	quit()
