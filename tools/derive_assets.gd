## Deterministic runtime asset derivation. Source originals remain untouched.
extends SceneTree

const DECOR_NAMES := ["pumpkin_cluster", "single_pumpkin", "apple_basket", "hay_bale", "corn_stalk_bundle", "wreath", "leaf_garland", "lantern", "pillar_candles", "welcome_sign", "porch_rug", "plaid_blanket", "porch_pillows", "orange_mums", "yellow_mums", "bench", "rocking_chair", "acorn_bowl", "bird_feeder", "string_lights"]
const VISITOR_NAMES := ["squirrel", "rabbit", "fox", "raccoon", "black_cat", "white_maltipoo"]

func _init() -> void:
	derive_background()
	derive_decor()
	derive_visitors()
	print("Cozy Fall asset derivation complete.")
	quit()

func load_source(file_name: String) -> Image:
	var image := Image.load_from_file("res://source_assets/generated/" + file_name)
	assert(not image.is_empty(), "Missing immutable source asset: " + file_name)
	return image

func derive_background() -> void:
	var image := load_source("cozyfall_background_original.png")
	image.save_png("res://assets/backgrounds/cottage_yard.png")
	var banner := image.duplicate()
	banner.resize(320, 180, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://android/template-overlay/res/drawable-nodpi"))
	banner.save_png("res://android/template-overlay/res/drawable-nodpi/cozyfall_tv_banner.png")

func derive_decor() -> void:
	var source := load_source("cozyfall_decor_atlas_original.png")
	var folder := DirAccess.open("res://assets/decor")
	for file in folder.get_files():
		if file.ends_with(".png") or file.ends_with(".png.import"): folder.remove(file)
	for row in 4:
		for col in 5:
			var index := row * 5 + col
			var x0 := roundi(float(col) * source.get_width() / 5.0)
			var x1 := roundi(float(col + 1) * source.get_width() / 5.0)
			var y0 := roundi(float(row) * source.get_height() / 4.0)
			var y1 := roundi(float(row + 1) * source.get_height() / 4.0)
			var cut := source.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))
			trim_alpha(cut, 8).save_png("res://assets/decor/%02d_%s.png" % [index + 1, DECOR_NAMES[index]])

func derive_visitors() -> void:
	var source := load_source("cozyfall_visitors_magenta_original.png")
	for row in 2:
		for col in 3:
			var index := row * 3 + col
			var x0 := col * 512
			var y0 := row * 512
			var cut := source.get_region(Rect2i(x0, y0, 512, 512))
			remove_magenta(cut)
			keep_primary_component(cut)
			trim_alpha(cut, 12).save_png("res://assets/visitors/%02d_%s.png" % [index + 1, VISITOR_NAMES[index]])

func remove_magenta(image: Image) -> void:
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			# Estimate how much flat #ff00ff key is in the observed edge pixel.
			var spill: float = maxf(0.0, minf(pixel.r, pixel.b) - pixel.g)
			var alpha: float = clampf(1.0 - spill, 0.0, 1.0)
			if alpha <= 0.03:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			elif alpha < 0.995:
				# Un-composite against key=(1,0,1), then retain smooth coverage.
				var subject := Color(clampf((pixel.r - (1.0 - alpha)) / alpha, 0.0, 1.0), clampf(pixel.g / alpha, 0.0, 1.0), clampf((pixel.b - (1.0 - alpha)) / alpha, 0.0, 1.0), alpha)
				image.set_pixel(x, y, subject)

func keep_primary_component(image: Image) -> void:
	# Atlas cell seams can include a disconnected edge of a neighboring animal.
	var width := image.get_width()
	var height := image.get_height()
	var visited := PackedByteArray(); visited.resize(width * height)
	var best: Array[Vector2i] = []
	var neighbors := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
	for y in height:
		for x in width:
			var start_index := y * width + x
			if visited[start_index] != 0 or image.get_pixel(x, y).a <= 0.30: continue
			var queue: Array[Vector2i] = [Vector2i(x, y)]
			var component: Array[Vector2i] = []
			visited[start_index] = 1
			var cursor := 0
			while cursor < queue.size():
				var point := queue[cursor]; cursor += 1; component.append(point)
				for offset in neighbors:
					var next: Vector2i = point + offset
					if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height: continue
					var next_index: int = next.y * width + next.x
					if visited[next_index] != 0 or image.get_pixel(next.x, next.y).a <= 0.30: continue
					visited[next_index] = 1; queue.append(next)
			if component.size() > best.size(): best = component
	var keep := PackedByteArray(); keep.resize(width * height)
	for point in best:
		for offset in neighbors + [Vector2i.ZERO]:
			var edge: Vector2i = point + offset
			if edge.x >= 0 and edge.y >= 0 and edge.x < width and edge.y < height: keep[edge.y * width + edge.x] = 1
	for y in height:
		for x in width:
			if keep[y * width + x] == 0:
				var color: Color = image.get_pixel(x, y)
				image.set_pixel(x, y, Color(color.r, color.g, color.b, 0.0))

func trim_alpha(image: Image, padding: int) -> Image:
	image.convert(Image.FORMAT_RGBA8)
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.04:
				min_x = mini(min_x, x); min_y = mini(min_y, y)
				max_x = maxi(max_x, x); max_y = maxi(max_y, y)
	if max_x < 0:
		return image
	min_x = maxi(0, min_x - padding); min_y = maxi(0, min_y - padding)
	max_x = mini(image.get_width() - 1, max_x + padding); max_y = mini(image.get_height() - 1, max_y + padding)
	return image.get_region(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))
