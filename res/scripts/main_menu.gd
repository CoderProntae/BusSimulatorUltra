extends Control

## Main menu shown before the game starts.
## Drive / Settings / Quit, plus the player's saved career totals.

signal play_pressed()

## Buttons must be TouchButton, not plain Button: with
## emulate_mouse_from_touch = false (needed to keep the steering wheel stable,
## HANDOVER.md 3.6) a stock Button never sees a finger tap on Android.
const TOUCH_BUTTON_SCRIPT: String = "res://scripts/touch_button.gd"

var _panel: Panel = null
var _settings_root: Control = null


func _ready() -> void:
	# MUST be set_anchors_AND_OFFSETS_preset here.
	#
	# set_anchors_preset() defaults to keep_offsets=false, which in Godot means
	# "recompute the offsets so the control keeps the rect it has right now".
	# This node is created with Control.new() (size 0x0) and the call happens
	# from _ready(), i.e. already inside the tree, so the engine dutifully
	# preserved 0x0: the whole menu collapsed into the top-left corner and the
	# backdrop was never visible. Setting the offsets too gives a real
	# full-screen rect.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader: Shader = Shader.new()
	shader.code = _menu_backdrop_shader()
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	bg.material = mat
	add_child(bg)

	var title: Label = Label.new()
	title.text = "BUS SIMULATOR"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -460.0
	title.offset_right = 460.0
	title.offset_top = 62.0
	title.offset_bottom = 150.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 68)
	title.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0.02, 0.12, 0.26))
	title.add_theme_constant_override("outline_size", 12)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "CITY ROUTES"
	subtitle.set_anchors_preset(Control.PRESET_CENTER_TOP)
	subtitle.offset_left = -460.0
	subtitle.offset_right = 460.0
	subtitle.offset_top = 142.0
	subtitle.offset_bottom = 176.0
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Color(0.45, 0.72, 1.0))
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(subtitle)

	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.offset_left = -190.0
	column.offset_right = 190.0
	column.offset_top = -30.0
	column.offset_bottom = 170.0
	column.add_theme_constant_override("separation", 16)
	add_child(column)

	var play: Button = _make_button("DRIVE", Color(0.10, 0.52, 0.30, 0.92), 30)
	play.pressed.connect(_on_play)
	column.add_child(play)

	var settings_button: Button = _make_button("SETTINGS", Color(0.14, 0.28, 0.46, 0.92), 24)
	settings_button.pressed.connect(_on_settings)
	column.add_child(settings_button)

	var quit_button: Button = _make_button("QUIT", Color(0.42, 0.16, 0.18, 0.92), 24)
	quit_button.pressed.connect(_on_quit)
	column.add_child(quit_button)

	var hint: Label = Label.new()
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -500.0
	hint.offset_right = 500.0
	hint.offset_top = -64.0
	hint.offset_bottom = -28.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.62, 0.70, 0.82))
	hint.text = "Pick up passengers, keep to the route, watch the fuel."
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)

	_build_quality_row()


func _build_quality_row() -> void:
	## Quick quality switch right on the menu, so a slow phone can be set up
	## before the city is ever built.
	var row: HBoxContainer = HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.offset_left = -230.0
	row.offset_right = 230.0
	row.offset_top = -130.0
	row.offset_bottom = -78.0
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	_settings_root = row

	var label: Label = Label.new()
	label.text = "QUALITY"
	label.custom_minimum_size = Vector2(120.0, 44.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.92))
	row.add_child(label)

	var button: Button = _make_button("MEDIUM", Color(0.16, 0.30, 0.44, 0.9), 18)
	button.custom_minimum_size = Vector2(180.0, 44.0)
	button.name = "QualityButton"
	button.pressed.connect(_on_quality)
	row.add_child(button)

	_refresh_quality()


func _refresh_quality() -> void:
	if _settings_root == null:
		return
	var button: Node = _settings_root.get_node_or_null("QualityButton")
	if button == null or not (button is Button):
		return
	if Settings == null:
		return
	(button as Button).text = Settings.quality_name()


func _on_quality() -> void:
	if Settings == null:
		return
	var next: int = Settings.quality + 1
	if next > 2:
		next = 0
	Settings.set_quality(next)
	_refresh_quality()


func _make_button(text: String, color: Color, font_size: int) -> Button:
	var button: Button = Button.new()
	if ResourceLoader.exists(TOUCH_BUTTON_SCRIPT):
		var script: Resource = load(TOUCH_BUTTON_SCRIPT)
		if script is Script:
			button.set_script(script)
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 58.0)

	var normal: StyleBoxFlat = _style(color, 16)
	var hover: StyleBoxFlat = _style(color.lightened(0.12), 16)
	var pressed: StyleBoxFlat = _style(color.lightened(0.24), 16)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", normal)
	button.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	button.add_theme_font_size_override("font_size", font_size)
	return button


func _style(color: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _menu_backdrop_shader() -> String:
	var lines: Array[String] = [
		"shader_type canvas_item;",
		"",
		"// Stylised city skyline at dusk, drawn procedurally.",
		"",
		"float hash(float x) {",
		"\treturn fract(sin(x * 127.1) * 43758.5453);",
		"}",
		"",
		"void fragment() {",
		"\tvec2 uv = UV;",
		"\tvec3 sky_top = vec3(0.04, 0.07, 0.16);",
		"\tvec3 sky_low = vec3(0.28, 0.20, 0.30);",
		"\tvec3 col = mix(sky_top, sky_low, pow(uv.y, 1.6));",
		"",
		"\t// distant skyline",
		"\tfloat ground = 0.72;",
		"\tfor (int layer = 0; layer < 2; layer++) {",
		"\t\tfloat fl = float(layer);",
		"\t\tfloat scale = 14.0 + fl * 9.0;",
		"\t\tfloat cell = floor(uv.x * scale);",
		"\t\tfloat h = 0.10 + hash(cell + fl * 31.0) * 0.20;",
		"\t\tfloat top = ground - h - fl * 0.03;",
		"\t\tfloat build = step(top, uv.y);",
		"\t\tvec3 bcol = mix(vec3(0.06, 0.08, 0.14), vec3(0.10, 0.12, 0.20), fl);",
		"\t\tcol = mix(col, bcol, build * (1.0 - fl * 0.25));",
		"",
		"\t\t// lit windows",
		"\t\tvec2 g = vec2(uv.x * scale * 4.0, (uv.y - top) * 26.0);",
		"\t\tvec2 f = fract(g);",
		"\t\tfloat lit = step(0.55, hash(floor(g.x) * 7.3 + floor(g.y) * 3.1 + fl));",
		"\t\tfloat win = step(0.25, f.x) * step(f.x, 0.75) * step(0.30, f.y) * step(f.y, 0.70);",
		"\t\tcol += vec3(1.0, 0.78, 0.36) * win * lit * build * 0.32;",
		"\t}",
		"",
		"\t// road at the bottom",
		"\tfloat road = step(ground, uv.y);",
		"\tcol = mix(col, vec3(0.05, 0.05, 0.06), road);",
		"\tfloat dash = step(0.86, uv.y) * step(uv.y, 0.90);",
		"\tfloat dashx = step(0.5, fract(uv.x * 18.0 - TIME * 1.2));",
		"\tcol += vec3(0.9, 0.9, 0.85) * dash * dashx * 0.55;",
		"",
		"\t// vignette",
		"\tfloat v = distance(uv, vec2(0.5)) * 1.1;",
		"\tcol *= 1.0 - v * 0.55;",
		"",
		"\tCOLOR = vec4(col, 1.0);",
		"}",
		"",
	]
	return "\n".join(lines)


func _on_play() -> void:
	emit_signal("play_pressed")


func _on_settings() -> void:
	if GameState != null:
		GameState.notify("Use the SETTINGS button in game for full options")
	_on_quality()


func _on_quit() -> void:
	get_tree().quit()
