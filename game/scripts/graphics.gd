extends Node

## Small, local-only graphics settings service for the Godot 4.7.2 project.
## Hardware detection is a conservative heuristic; it does not promise FPS.

signal settings_applied(settings: Dictionary)

const RESOLUTIONS: Dictionary = {
	"960x600": Vector2i(960, 600),
	"1280x720": Vector2i(1280, 720),
	"1600x900": Vector2i(1600, 900),
	"1920x1080": Vector2i(1920, 1080),
}
const RENDER_SCALES: Array[float] = [0.5, 0.67, 0.85, 1.0]
const MSAA_VALUES: Array[int] = [0, 2, 4]
const FPS_VALUES: Array[int] = [30, 60, 120, 0]
var current_surface_settings: Dictionary = {}
var syncing_surface := false

func _ready() -> void:
	get_tree().root.size_changed.connect(_sync_surface)

func _sync_surface() -> void:
	if syncing_surface or current_surface_settings.is_empty() or DisplayServer.get_name()=="headless": return
	syncing_surface=true
	var window := get_tree().root
	var pixels := DisplayServer.window_get_size()
	# Never shrink UI below its normal size; enlarge it proportionally on HD displays.
	var base := Vector2i(1280,720) if pixels.x>=1280 and pixels.y>=720 else pixels
	if window.content_scale_mode != Window.CONTENT_SCALE_MODE_CANVAS_ITEMS: window.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if window.content_scale_aspect != Window.CONTENT_SCALE_ASPECT_EXPAND: window.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	if window.content_scale_size != base: window.content_scale_size=base
	var resolution: Vector2i=RESOLUTIONS[current_surface_settings.resolution]
	var scale := float(current_surface_settings.render_scale)
	if current_surface_settings.window_mode != "windowed":
		scale*=minf(1.0,minf(float(resolution.x)/maxi(pixels.x,1),float(resolution.y)/maxi(pixels.y,1)))
	window.scaling_3d_scale=scale
	syncing_surface=false

func hardware() -> Dictionary:
	var memory := OS.get_memory_info()
	var physical_bytes := int(memory.get("physical", 0))
	return {
		"cpu": OS.get_processor_name(),
		"threads": OS.get_processor_count(),
		"ram_gb": snappedf(float(physical_bytes) / 1073741824.0, 0.1),
		"gpu": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(),
	}

func recommended_preset() -> String:
	return String(recommendation().get("preset", "low"))

func recommendation() -> Dictionary:
	var spec := hardware()
	var gpu := String(spec.get("gpu", "")).to_lower()
	var vendor := String(spec.get("vendor", "")).to_lower()
	var ram_gb := float(spec.get("ram_gb", 0.0))
	if int(spec.get("threads", 0)) < 4 or (ram_gb > 0 and ram_gb < 8):
		return {"preset":"low", "reason":"CPU/メモリ構成検出：低負荷設定適用"}
	if gpu.is_empty() or vendor.is_empty():
		return {"preset": "low", "reason": "GPU情報取得不可：低負荷設定適用"}
	if _is_integrated_gpu(gpu):
		return {"preset": "low", "reason": "内蔵GPU検出：低負荷設定適用"}
	if ram_gb >= 16.0 and _is_high_gpu(gpu):
		return {"preset": "high", "reason": "高性能専用GPU・16GB以上メモリ検出"}
	if _is_known_discrete_gpu(gpu, vendor):
		return {"preset": "medium", "reason": "専用GPU検出：中設定適用"}
	return {"preset": "low", "reason": "GPU性能判定不可：低負荷設定適用"}

func preset_values(name: String) -> Dictionary:
	match name.to_lower():
		"medium":
			return {"quality": "medium", "render_scale": 0.85, "msaa": 2, "shadows": "low", "max_fps": 60, "vsync": true}
		"high":
			return {"quality": "high", "render_scale": 1.0, "msaa": 4, "shadows": "high", "max_fps": 60, "vsync": true}
		_:
			# Low is still a 60 FPS target; 30 FPS remains an explicit user choice.
			return {"quality": "low", "render_scale": 0.67, "msaa": 0, "shadows": "off", "max_fps": 60, "vsync": true}

func apply_settings(settings: Dictionary) -> Dictionary:
	var applied := preset_values(String(settings.get("quality", "low")))
	for key in ["quality", "shadows"]:
		if settings.has(key):
			applied[key] = String(settings[key])
	if settings.has("render_scale"):
		applied["render_scale"] = _nearest_float(float(settings["render_scale"]), RENDER_SCALES)
	if settings.has("msaa"):
		applied["msaa"] = _nearest_int(int(settings["msaa"]), MSAA_VALUES)
	if settings.has("max_fps"):
		applied["max_fps"] = _nearest_int(int(settings["max_fps"]), FPS_VALUES)
	applied["vsync"] = bool(settings.get("vsync", applied.get("vsync", true)))
	applied["mouse_sensitivity"] = clampf(float(settings.get("mouse_sensitivity", 1.0)), 0.1, 3.0)
	applied["window_mode"] = _safe_window_mode(String(settings.get("window_mode", "windowed")))
	applied["resolution"] = _safe_resolution(String(settings.get("resolution", "1280x720")))
	applied["fov"] = clampf(float(settings.get("fov", 75.0)), 60.0, 90.0)
	current_surface_settings=applied.duplicate(true)
	if DisplayServer.get_name() != "headless":
		_apply_window(applied["window_mode"], RESOLUTIONS[applied["resolution"]])
		_sync_surface()
	else: get_tree().root.scaling_3d_scale=float(applied.render_scale)
	Engine.max_fps = int(applied["max_fps"])
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if applied["vsync"] else DisplayServer.VSYNC_DISABLED)
	settings_applied.emit(applied.duplicate(true))
	return applied

func reset_position() -> void:
	var usable := DisplayServer.screen_get_usable_rect()
	var size := DisplayServer.window_get_size()
	var pos := usable.position + (usable.size - size) / 2
	pos.x = maxi(pos.x, usable.position.x)
	pos.y = maxi(pos.y, usable.position.y)
	DisplayServer.window_set_position(pos)

func _apply_window(mode: String, resolution: Vector2i) -> void:
	match mode:
		"fullscreen":
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			if not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS): DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			if DisplayServer.window_get_size() != DisplayServer.screen_get_size(): DisplayServer.window_set_size(DisplayServer.screen_get_size())
		_:
			if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS): DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			if DisplayServer.window_get_size() != _clamp_resolution(resolution): DisplayServer.window_set_size(_clamp_resolution(resolution))
	if mode == "windowed": reset_position()
	elif mode == "borderless": DisplayServer.window_set_position(DisplayServer.screen_get_position())

func _clamp_resolution(requested: Vector2i) -> Vector2i:
	var usable := DisplayServer.screen_get_usable_rect().size - Vector2i(12,42)
	return Vector2i(mini(requested.x, usable.x), mini(requested.y, usable.y))

func _safe_window_mode(value: String) -> String:
	return value if value in ["windowed", "borderless", "fullscreen"] else "windowed"

func _safe_resolution(value: String) -> String:
	return value if RESOLUTIONS.has(value) else "1280x720"

func _is_integrated_gpu(gpu: String) -> bool:
	if "arc" in gpu:
		return false
	return "integrated" in gpu or "uhd graphics" in gpu or "iris" in gpu or "intel hd" in gpu or "vega  " in gpu or "radeon graphics" in gpu

func _is_known_discrete_gpu(gpu: String, vendor: String) -> bool:
	return "nvidia" in vendor or "geforce" in gpu or "quadro" in gpu or "radeon rx" in gpu or "rx " in gpu or "arc" in gpu

func _is_high_gpu(gpu: String) -> bool:
	return "rx 9070" in gpu or "rx 7900" in gpu or "rx 7800" in gpu or "rtx 4080" in gpu or "rtx 4090" in gpu or "rtx 50" in gpu

func _nearest_float(value: float, choices: Array[float]) -> float:
	var best := choices[0]
	for choice in choices:
		if absf(value - choice) < absf(value - best):
			best = choice
	return best

func _nearest_int(value: int, choices: Array[int]) -> int:
	var best := choices[0]
	for choice in choices:
		if absi(value - choice) < absi(value - best):
			best = choice
	return best
