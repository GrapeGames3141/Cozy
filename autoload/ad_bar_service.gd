extends Node

## Bottom banner via Poing AdMob (Android). Config: res://config/admob.json
## (see admob.example.json). The overlay lives on the tree root so it survives
## scene changes, and Ambient Mode hides it along with the rest of the chrome.

const CONFIG_PATH := "res://config/admob.json"
const EXAMPLE_PATH := "res://config/admob.example.json"
const DISCLOSURE_HEIGHT := 14.0
const OVERLAY_LAYER := 100
const RELAYOUT_SETTLE_SECONDS := 0.22

# Closed-test / Play policy: serve Google's official test banner, not live ads.
const GOOGLE_TEST_ANDROID_BANNER_UNIT_ID := "ca-app-pub-3940256099942544/6300978111"
# TODO(ads-live): return the configured production unit from banner_unit_id()
# instead of the test unit when Cozy Fall leaves closed test.

## Emitted whenever the reserved banner height changes so the scene can keep its
## bottom chrome clear of the ad.
signal banner_height_changed(height: float)

var _config: Dictionary = {}
var _ad_view: AdView
var _disclosure: Label
var _overlay: CanvasLayer
var _overlay_root: Control
var _sdk_initialized := false
var _banner_logical_height := 60.0
var _loaded_placement := ""
var _relayout_generation := 0
var _suppressed := false


func _ready() -> void:
	_reload_config()
	call_deferred("_ensure_overlay")
	if _should_show_ads():
		set_process(true)
		_initialize_mobile_ads(_show_banner)
	else:
		set_process(false)
	_connect_layout_signals()


func _exit_tree() -> void:
	detach()


func _process(_delta: float) -> void:
	if not _should_show_ads() or _suppressed:
		return
	if _placement_signature() != _loaded_placement:
		_schedule_relayout()


func _reload_config() -> void:
	if FileAccess.file_exists(CONFIG_PATH):
		_config = _parse_json_file(CONFIG_PATH)
	elif FileAccess.file_exists(EXAMPLE_PATH):
		_config = _parse_json_file(EXAMPLE_PATH)
	else:
		_config = {}


func _parse_json_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func config() -> Dictionary:
	return _config


func ads_enabled() -> bool:
	if not bool(_config.get("ads_enabled", false)):
		return false
	match OS.get_name():
		"Android":
			return bool(_config.get("android_ads_enabled", true))
		_:
			return false


## Logical viewport pixels the scene must leave clear at the bottom.
func banner_height() -> float:
	if not _should_show_ads() or _suppressed:
		return 0.0
	return _banner_logical_height + DISCLOSURE_HEIGHT + _bottom_inset()


## Ambient Mode is a full-bleed, chrome-free view; hide the bar while it runs.
func set_suppressed(value: bool) -> void:
	if _suppressed == value:
		return
	_suppressed = value
	if _suppressed:
		_hide_native_banner()
		if is_instance_valid(_disclosure):
			_disclosure.visible = false
		banner_height_changed.emit(0.0)
	else:
		if is_instance_valid(_disclosure):
			_disclosure.visible = true
		sync_banner()
		banner_height_changed.emit(banner_height())


func sync_banner() -> void:
	if not _should_show_ads() or _suppressed:
		detach()
		return
	_ensure_overlay()
	_ensure_disclosure()
	if _sdk_initialized:
		_show_banner()
	else:
		_initialize_mobile_ads(_show_banner)


func detach() -> void:
	_loaded_placement = ""
	_relayout_generation += 1
	_destroy_banner()
	if is_instance_valid(_disclosure):
		_disclosure.queue_free()
	_disclosure = null


func _connect_layout_signals() -> void:
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_size_changed):
		viewport.size_changed.connect(_on_viewport_size_changed)
	var window := get_window()
	if window != null and not window.size_changed.is_connected(_on_window_size_changed):
		window.size_changed.connect(_on_window_size_changed)
	if window != null and not window.focus_entered.is_connected(_on_window_focus_entered):
		window.focus_entered.connect(_on_window_focus_entered)


func _on_viewport_size_changed() -> void:
	_layout_disclosure()
	_schedule_relayout()


func _on_window_size_changed() -> void:
	_schedule_relayout()


func _on_window_focus_entered() -> void:
	_schedule_relayout()


func _schedule_relayout() -> void:
	if not _should_show_ads() or _suppressed:
		return
	_relayout_generation += 1
	var generation := _relayout_generation
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(RELAYOUT_SETTLE_SECONDS).timeout.connect(
		func() -> void:
			if generation != _relayout_generation:
				return
			_relayout_banner()
	)


func _relayout_banner() -> void:
	if not _should_show_ads() or _suppressed:
		return
	if _ad_view != null and _placement_signature() == _loaded_placement:
		_anchor_banner()
		_layout_disclosure()
		return
	sync_banner()


func _placement_signature() -> String:
	var window_size := DisplayServer.window_get_size()
	var visible := Vector2.ZERO
	var viewport := get_viewport()
	if viewport != null:
		visible = viewport.get_visible_rect().size
	return "%d,%d|%.0f,%.0f|%d" % [
		window_size.x,
		window_size.y,
		visible.x,
		visible.y,
		DisplayServer.screen_get_orientation(),
	]


func _banner_ad_size() -> AdSize:
	# Android can report its previous orientation briefly while a sensor rotation
	# is settling. The window dimensions in the placement signature are what this
	# banner must actually fill, so select the matching adaptive size explicitly
	# instead of asking the SDK for its potentially stale "current" orientation.
	if _is_landscape_window(DisplayServer.window_get_size()):
		return AdSize.get_landscape_anchored_adaptive_banner_ad_size(AdSize.FULL_WIDTH)
	return AdSize.get_portrait_anchored_adaptive_banner_ad_size(AdSize.FULL_WIDTH)


func _is_landscape_window(window_size: Vector2i) -> bool:
	return window_size.x >= window_size.y


func _should_show_ads() -> bool:
	return ads_enabled() and _platform_supports_ads()


func _platform_supports_ads() -> bool:
	return OS.get_name() == "Android"


func banner_unit_id() -> String:
	# TODO(ads-live): return the configured production unit instead of Google's
	# test banner when leaving closed test.
	return GOOGLE_TEST_ANDROID_BANNER_UNIT_ID


func configured_banner_unit_id() -> String:
	return str(_config.get("android_banner_unit_id", "")).strip_edges()


func _ensure_overlay() -> void:
	if is_instance_valid(_overlay) and is_instance_valid(_overlay_root):
		return
	var root := get_tree().root
	if root == null:
		return
	_overlay = CanvasLayer.new()
	_overlay.name = "AdBarOverlay"
	_overlay.layer = OVERLAY_LAYER
	_overlay_root = Control.new()
	_overlay_root.name = "AdBarRoot"
	_overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_overlay)
	_overlay.add_child(_overlay_root)


func _initialize_mobile_ads(on_ready: Callable = Callable()) -> void:
	if _sdk_initialized:
		if on_ready.is_valid():
			on_ready.call()
		return

	if not Engine.has_singleton("PoingGodotAdMob"):
		push_warning(
			"AdBarService: PoingGodotAdMob singleton missing — AdMob Android binaries were not packaged"
		)

	var request_config := RequestConfiguration.new()
	if bool(_config.get("child_directed", false)):
		request_config.tag_for_child_directed_treatment = (
			RequestConfiguration.TagForChildDirectedTreatment.TRUE
		)
	if bool(_config.get("tag_for_under_age_of_consent", false)):
		request_config.tag_for_under_age_of_consent = (
			RequestConfiguration.TagForUnderAgeOfConsent.TRUE
		)
	match str(_config.get("max_ad_content_rating", "G")):
		"PG":
			request_config.max_ad_content_rating = RequestConfiguration.MAX_AD_CONTENT_RATING_PG
		"T":
			request_config.max_ad_content_rating = RequestConfiguration.MAX_AD_CONTENT_RATING_T
		"MA":
			request_config.max_ad_content_rating = RequestConfiguration.MAX_AD_CONTENT_RATING_MA
		_:
			request_config.max_ad_content_rating = RequestConfiguration.MAX_AD_CONTENT_RATING_G

	MobileAds.set_request_configuration(request_config)

	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = func(_status: InitializationStatus) -> void:
		_sdk_initialized = true
		print("AdBarService: MobileAds initialized")
		if on_ready.is_valid():
			on_ready.call()

	MobileAds.initialize(listener)


func _show_banner() -> void:
	if not _should_show_ads() or _suppressed:
		return

	var unit_id := banner_unit_id()
	if unit_id.is_empty():
		push_warning("AdBarService: banner unit ID is missing")
		return

	if not Engine.has_singleton("PoingGodotAdMobAdView"):
		push_warning("AdBarService: PoingGodotAdMobAdView missing — cannot show banner on this build")
		return

	_destroy_banner()
	_loaded_placement = _placement_signature()
	_ensure_overlay()
	_ensure_disclosure()

	var ad_size := _banner_ad_size()
	_ad_view = AdView.new(unit_id, ad_size, AdPosition.BOTTOM)

	var ad_listener := AdListener.new()
	ad_listener.on_ad_loaded = _on_banner_loaded
	ad_listener.on_ad_failed_to_load = func(error: LoadAdError) -> void:
		_loaded_placement = ""
		push_warning("AdBarService: banner failed: %s" % error.message)

	_ad_view.ad_listener = ad_listener
	var window_size := DisplayServer.window_get_size()
	print(
		"AdBarService: loading banner unit %s (%s window %dx%d, adaptive %dx%d)"
		% [
			unit_id,
			"landscape" if _is_landscape_window(window_size) else "portrait",
			window_size.x,
			window_size.y,
			ad_size.width,
			ad_size.height,
		]
	)
	_ad_view.load_ad(AdRequest.new())


func _on_banner_loaded() -> void:
	if _ad_view == null:
		return
	if _suppressed:
		_hide_native_banner()
		return
	_anchor_banner()
	_ad_view.show()
	var px := float(_ad_view.get_height_in_pixels())
	if px > 0.0:
		_banner_logical_height = _pixels_to_viewport_y(px)
	_ensure_disclosure()
	banner_height_changed.emit(banner_height())
	print("AdBarService: banner loaded (height_px=%.0f)" % px)


func _anchor_banner() -> void:
	if _ad_view == null:
		return
	_ad_view.set_position(AdPosition.BOTTOM)


func _hide_native_banner() -> void:
	if _ad_view != null:
		_ad_view.hide()


func _destroy_banner() -> void:
	if _ad_view != null:
		_ad_view.destroy()
	_ad_view = null


func _ensure_disclosure() -> void:
	_ensure_overlay()
	if not is_instance_valid(_overlay_root):
		return
	if is_instance_valid(_disclosure) and _disclosure.get_parent() == _overlay_root:
		_layout_disclosure()
		return
	if is_instance_valid(_disclosure):
		_disclosure.queue_free()
	_disclosure = Label.new()
	_disclosure.name = "AdDisclosure"
	_disclosure.text = "Ad"
	_disclosure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disclosure.add_theme_font_size_override("font_size", 10)
	_disclosure.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	_overlay_root.add_child(_disclosure)
	_layout_disclosure()


func _layout_disclosure() -> void:
	if not is_instance_valid(_disclosure):
		return
	_disclosure.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_disclosure.offset_top = -DISCLOSURE_HEIGHT - _bottom_inset()
	_disclosure.offset_bottom = -_bottom_inset()


func _pixels_to_viewport_y(pixels: float) -> float:
	var window_h := float(DisplayServer.window_get_size().y)
	if window_h <= 0.0:
		return pixels
	var viewport_h := float(get_viewport().get_visible_rect().size.y)
	return pixels * (viewport_h / window_h)


func _bottom_inset() -> float:
	var safe := DisplayServer.get_display_safe_area()
	var window_h := DisplayServer.window_get_size().y
	if window_h <= 0:
		return 0.0
	return maxf(0.0, float(window_h - safe.end.y))
