extends Control

## REAL loading screen - the progress bar reflects actual work.
##
## Two genuine sources of progress:
##  1. ResourceLoader.load_threaded_get_status() while the world/bus/HUD scenes
##     stream in on a background thread (real engine progress, 0..1 per scene)
##  2. the city build itself, which reports how many stages it has finished
##
## Nothing here is on a timer: if the device is slow the bar genuinely waits,
## and if loading finishes early the bar jumps ahead and we move on.

signal loading_finished()

const SCENES: Array[String] = [
	"res://scenes/World.tscn",
	"res://scenes/Bus.tscn",
	"res://scenes/HUD.tscn",
	"res://scenes/BusStop.tscn",
	"res://scenes/TrafficCar.tscn",
]

const STAGE_TEXT: Array[String] = [
	"Warming up the engine",
	"Streaming city assets",
	"Paving the roads",
	"Parking the traffic",
	"Opening the depot",
]

var _bar: ProgressBar = null
var _percent: Label = null
var _stage: Label = null
var _tip: Label = null
var _spinner: Control = null
var _bus_icon: Control = null

var _requested: Array[String] = []
var _loaded: Dictionary = {}
var _index: int = 0
var _display_progress: float = 0.0
var _real_progress: float = 0.0
var _spin_time: float = 0.0
var _finished: bool = false
var _hold_timer: float = 0.0

const TIPS: Array[String] = [
	"Open the doors at a stop to let passengers on and off.",
	"The brake pedal reverses the bus once you are nearly stopped.",
	"Refuel before the tank runs dry - an empty bus will not move.",
	"Street lights come on by themselves once night falls.",
	"Tap CAMERA to switch between chase, cockpit and top-down views.",
	"Turn the wheel further to take tighter corners.",
]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_start_loading()


func _build_ui() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.06, 0.10)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Subtle animated backdrop
	var grad: ColorRect = ColorRect.new()
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader: Shader = Shader.new()
	shader.code = _backdrop_shader()
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	grad.material = mat
	add_child(grad)

	var title: Label = Label.new()
	title.text = "BUS SIMULATOR"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -420.0
	title.offset_right = 420.0
	title.offset_top = 96.0
	title.offset_bottom = 172.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 62)
	title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0.02, 0.10, 0.22))
	title.add_theme_constant_override("outline_size", 10)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	# Animated bus that drives along with the progress bar
	_bus_icon = _make_bus_icon()
	add_child(_bus_icon)

	_bar = ProgressBar.new()
	_bar.set_anchors_preset(Control.PRESET_CENTER)
	_bar.offset_left = -340.0
	_bar.offset_right = 340.0
	_bar.offset_top = 40.0
	_bar.offset_bottom = 68.0
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false
	var bg_style: StyleBoxFlat = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.10, 0.13, 0.18)
	bg_style.corner_radius_top_left = 14
	bg_style.corner_radius_top_right = 14
	bg_style.corner_radius_bottom_left = 14
	bg_style.corner_radius_bottom_right = 14
	var fill_style: StyleBoxFlat = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.25, 0.72, 1.0)
	fill_style.corner_radius_top_left = 14
	fill_style.corner_radius_top_right = 14
	fill_style.corner_radius_bottom_left = 14
	fill_style.corner_radius_bottom_right = 14
	_bar.add_theme_stylebox_override("background", bg_style)
	_bar.add_theme_stylebox_override("fill", fill_style)
	add_child(_bar)

	_percent = Label.new()
	_percent.set_anchors_preset(Control.PRESET_CENTER)
	_percent.offset_left = -340.0
	_percent.offset_right = 340.0
	_percent.offset_top = 76.0
	_percent.offset_bottom = 108.0
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_percent.add_theme_font_size_override("font_size", 24)
	_percent.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	_percent.text = "0%"
	add_child(_percent)

	_stage = Label.new()
	_stage.set_anchors_preset(Control.PRESET_CENTER)
	_stage.offset_left = -420.0
	_stage.offset_right = 420.0
	_stage.offset_top = -8.0
	_stage.offset_bottom = 28.0
	_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage.add_theme_font_size_override("font_size", 22)
	_stage.add_theme_color_override("font_color", Color(0.85, 0.90, 0.97))
	_stage.text = "Loading"
	add_child(_stage)

	_spinner = Control.new()
	_spinner.set_anchors_preset(Control.PRESET_CENTER)
	_spinner.offset_left = -22.0
	_spinner.offset_right = 22.0
	_spinner.offset_top = 122.0
	_spinner.offset_bottom = 166.0
	_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_spinner)

	var wheel: ColorRect = ColorRect.new()
	wheel.size = Vector2(44.0, 44.0)
	wheel.pivot_offset = Vector2(22.0, 22.0)
	var wshader: Shader = Shader.new()
	wshader.code = _spinner_shader()
	var wmat: ShaderMaterial = ShaderMaterial.new()
	wmat.shader = wshader
	wheel.material = wmat
	wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spinner.add_child(wheel)

	_tip = Label.new()
	_tip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tip.offset_left = -460.0
	_tip.offset_right = 460.0
	_tip.offset_top = -86.0
	_tip.offset_bottom = -40.0
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_font_size_override("font_size", 19)
	_tip.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88))
	_tip.text = TIPS[randi() % TIPS.size()]
	add_child(_tip)


func _make_bus_icon() -> Control:
	var holder: Control = Control.new()
	holder.set_anchors_preset(Control.PRESET_CENTER)
	holder.offset_left = -340.0
	holder.offset_right = 340.0
	holder.offset_top = -14.0
	holder.offset_bottom = 34.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bus: ColorRect = ColorRect.new()
	bus.name = "BusSprite"
	bus.size = Vector2(74.0, 34.0)
	bus.position = Vector2(0.0, 0.0)
	bus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader: Shader = Shader.new()
	shader.code = _bus_shader()
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	bus.material = mat
	holder.add_child(bus)
	return holder


func _backdrop_shader() -> String:
	var lines: Array[String] = [
		"shader_type canvas_item;",
		"",
		"void fragment() {",
		"\tvec2 uv = UV;",
		"\tvec3 top = vec3(0.05, 0.09, 0.18);",
		"\tvec3 bottom = vec3(0.02, 0.04, 0.07);",
		"\tvec3 col = mix(top, bottom, uv.y);",
		"\t// slow drifting light streaks, like passing headlights",
		"\tfloat streak = sin(uv.x * 8.0 - TIME * 0.6) * 0.5 + 0.5;",
		"\tstreak *= smoothstep(0.62, 0.42, abs(uv.y - 0.52));",
		"\tcol += vec3(0.05, 0.12, 0.22) * streak * 0.35;",
		"\tCOLOR = vec4(col, 1.0);",
		"}",
		"",
	]
	return "\n".join(lines)


func _spinner_shader() -> String:
	var lines: Array[String] = [
		"shader_type canvas_item;",
		"",
		"void fragment() {",
		"\tvec2 p = UV - vec2(0.5);",
		"\tfloat r = length(p) * 2.0;",
		"\tfloat a = atan(p.y, p.x) + TIME * 4.0;",
		"\tfloat ring = smoothstep(1.0, 0.92, r) * smoothstep(0.55, 0.68, r);",
		"\tfloat sweep = fract(a / 6.2831853);",
		"\tfloat alpha = ring * smoothstep(0.0, 0.85, sweep);",
		"\tCOLOR = vec4(vec3(0.35, 0.78, 1.0), alpha);",
		"}",
		"",
	]
	return "\n".join(lines)


func _bus_shader() -> String:
	var lines: Array[String] = [
		"shader_type canvas_item;",
		"",
		"void fragment() {",
		"\tvec2 uv = UV;",
		"\tvec3 body = vec3(0.93, 0.94, 0.96);",
		"\tvec3 band = vec3(0.06, 0.28, 0.62);",
		"\tvec3 glass = vec3(0.13, 0.20, 0.30);",
		"",
		"\tfloat a = step(0.06, uv.y) * step(uv.y, 0.80);",
		"\tvec3 col = body;",
		"\tif (uv.y > 0.52 && uv.y < 0.72 && uv.x > 0.08 && uv.x < 0.94) { col = glass; }",
		"\tif (uv.y > 0.30 && uv.y < 0.42) { col = band; }",
		"",
		"\t// wheels",
		"\tfloat w1 = step(length((uv - vec2(0.24, 0.86)) * vec2(1.0, 1.6)), 0.10);",
		"\tfloat w2 = step(length((uv - vec2(0.76, 0.86)) * vec2(1.0, 1.6)), 0.10);",
		"\tfloat wheels = clamp(w1 + w2, 0.0, 1.0);",
		"\tcol = mix(col, vec3(0.06), wheels);",
		"\ta = clamp(a + wheels, 0.0, 1.0);",
		"",
		"\tCOLOR = vec4(col, a);",
		"}",
		"",
	]
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# Real loading
# ---------------------------------------------------------------------------

func _start_loading() -> void:
	var i: int = 0
	while i < SCENES.size():
		var path: String = SCENES[i]
		if ResourceLoader.exists(path):
			var err: int = ResourceLoader.load_threaded_request(path)
			if err == OK:
				_requested.append(path)
		i += 1
	if _requested.is_empty():
		_real_progress = 1.0


func _process(delta: float) -> void:
	_spin_time += delta
	if _spinner != null and _spinner.get_child_count() > 0:
		var wheel: Node = _spinner.get_child(0)
		if wheel is Control:
			(wheel as Control).rotation = _spin_time * 2.0

	_poll_loading()

	# Ease the displayed bar toward the real value so it never jitters
	# backwards, but never let it overtake real progress either.
	_display_progress = move_toward(_display_progress, _real_progress, delta * 0.9)
	if _display_progress > _real_progress:
		_display_progress = _real_progress

	var pct: float = clampf(_display_progress, 0.0, 1.0)
	if _bar != null:
		_bar.value = pct * 100.0
	if _percent != null:
		_percent.text = str(int(round(pct * 100.0))) + "%"
	if _stage != null:
		var stage_index: int = clampi(int(pct * float(STAGE_TEXT.size())), 0, STAGE_TEXT.size() - 1)
		_stage.text = STAGE_TEXT[stage_index]

	# Drive the little bus along the bar.
	if _bus_icon != null and _bus_icon.get_child_count() > 0:
		var sprite: Node = _bus_icon.get_child(0)
		if sprite is Control:
			var track: float = 680.0 - 74.0
			var ctrl: Control = sprite as Control
			ctrl.position = Vector2(track * pct, sin(_spin_time * 8.0) * 1.5)

	if _finished:
		return
	if _real_progress >= 1.0 and _display_progress >= 0.999:
		_hold_timer += delta
		# One extra beat so the player sees 100%, then hand over.
		if _hold_timer > 0.25:
			_finished = true
			emit_signal("loading_finished")


func _poll_loading() -> void:
	if _requested.is_empty():
		return
	var total: float = float(_requested.size())
	var done: float = 0.0

	var i: int = 0
	while i < _requested.size():
		var path: String = _requested[i]
		if _loaded.has(path):
			done += 1.0
			i += 1
			continue

		var progress: Array = []
		var status: int = ResourceLoader.load_threaded_get_status(path, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_loaded[path] = ResourceLoader.load_threaded_get(path)
			done += 1.0
		elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if progress.size() > 0:
				done += clampf(float(progress[0]), 0.0, 1.0)
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			# Count it as done: the game guards every load and falls back.
			_loaded[path] = null
			done += 1.0
		i += 1

	# Scene streaming is 85% of the bar; the last 15% is the city build,
	# which Main reports through report_build_progress().
	_real_progress = maxf(_real_progress, (done / total) * 0.85)


func report_build_progress(value: float) -> void:
	## Called by Main while the city is generated (0..1 across build stages).
	_real_progress = maxf(_real_progress, 0.85 + clampf(value, 0.0, 1.0) * 0.15)


func get_loaded(path: String) -> Resource:
	if _loaded.has(path):
		var res: Variant = _loaded[path]
		if res is Resource:
			return res as Resource
	return null
