extends Control

## Mobile HUD for landscape play: left steering pad, right gas/brake pedals,
## action buttons (horn / door / camera / headlights), digital speedometer,
## money, fuel bar, passenger count and a notification feed.
##
## Every control is built in code with anchors so it scales to any phone.

signal camera_cycle_requested()

const PAD_SIZE: float = 300.0
const PEDAL_W: float = 150.0
const PEDAL_H: float = 150.0
const BUTTON_SIZE: float = 92.0
## Full lock is 160 degrees of wheel rotation in each direction.
const MAX_WHEEL_ANGLE: float = 2.79
const WHEEL_SIZE: float = 260.0
## Radians per second the wheel graphic may travel. Caps how fast steering can
## change, which is what removes the twitchy "spins by itself" feel.
const WHEEL_FOLLOW_SPEED: float = 7.5
## Self-centring speed when the wheel is released.
const WHEEL_RETURN_SPEED: float = 4.2

@export var bus_path: NodePath
@export var camera_path: NodePath

var bus: Node = null
var camera_system: Node = null

var _steer_pad: Control = null
var _steer_knob: Control = null
var _wheel_texture: Node = null
var _wheel_angle: float = 0.0
var _steer_grab_angle: float = 0.0
var _steer_grabbed: bool = false
## Index of the ONE finger that owns the wheel. -99 means nobody.
var _steer_pointer: int = -99
var _wheel_target: float = 0.0
var _steer_value: float = 0.0

var _gas_button: PanelContainer = null
var _brake_button: PanelContainer = null

var _speed_label: Label = null
var _speed_unit: Label = null
var _money_label: Label = null
var _passenger_label: Label = null
var _clock_label: Label = null
var _fuel_bar: ProgressBar = null
var _fuel_label: Label = null
var _notify_label: Label = null
var _gear_label: Label = null
var _camera_button: Button = null
var _door_button: Button = null
var _light_button: Button = null

var _notify_timer: float = 0.0
var _settings_panel: Panel = null
var _fps_label: Label = null
var _settings_rows: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_resolve_refs()
	_build_top_bar()
	_build_speedometer()
	_build_steering_pad()
	_build_pedals()
	_build_action_buttons()
	_build_notifications()
	_build_fps_counter()
	_build_settings_menu()

	if GameState != null:
		GameState.money_changed.connect(_on_money_changed)
		GameState.fuel_changed.connect(_on_fuel_changed)
		GameState.passengers_changed.connect(_on_passengers_changed)
		GameState.notification_posted.connect(_on_notification)
		_on_money_changed(GameState.money)
		_on_fuel_changed(GameState.fuel, GameState.fuel_ratio())
		_on_passengers_changed(GameState.passengers_onboard, GameState.capacity)


func _resolve_refs() -> void:
	if bus_path != NodePath("") and has_node(bus_path):
		bus = get_node(bus_path)
	if bus == null:
		var buses: Array = get_tree().get_nodes_in_group("bus")
		if buses.size() > 0:
			bus = buses[0]
	if camera_path != NodePath("") and has_node(camera_path):
		camera_system = get_node(camera_path)


func _process(delta: float) -> void:
	if bus == null or not is_instance_valid(bus):
		_resolve_refs()

	_update_wheel_return(delta)
	_apply_inputs()
	_update_readouts()
	_update_fps()

	if _notify_timer > 0.0:
		_notify_timer -= delta
		if _notify_timer <= 0.0 and _notify_label != null:
			_notify_label.text = ""


func _update_wheel_return(delta: float) -> void:
	## Drives the visible wheel toward _wheel_target at a bounded speed, and
	## springs back to centre when nobody is holding it. Doing the motion here
	## (once per frame) instead of inside the input callback is what keeps the
	## wheel smooth no matter how many events arrive.
	var holding: bool = _steer_pointer != -99
	if not holding:
		_wheel_target = move_toward(_wheel_target, 0.0, WHEEL_RETURN_SPEED * delta)

	var max_step: float = WHEEL_FOLLOW_SPEED * delta
	_wheel_angle = _wheel_angle + clampf(_wheel_target - _wheel_angle, -max_step, max_step)
	_wheel_angle = clampf(_wheel_angle, -MAX_WHEEL_ANGLE, MAX_WHEEL_ANGLE)

	_steer_value = clampf(_wheel_angle / MAX_WHEEL_ANGLE, -1.0, 1.0)
	_move_knob()


func _apply_inputs() -> void:
	if bus == null or not is_instance_valid(bus):
		return

	# Keyboard fallback merges with touch input (handy for desktop testing).
	var key_steer: float = 0.0
	if Input.is_action_pressed("steer_left"):
		key_steer -= 1.0
	if Input.is_action_pressed("steer_right"):
		key_steer += 1.0

	var steer: float = _steer_value
	if absf(key_steer) > 0.01:
		# Keyboard drives the same wheel so the graphic stays in sync.
		_wheel_target = clampf(
			_wheel_target + key_steer * MAX_WHEEL_ANGLE * 1.2 * get_process_delta_time(),
			-MAX_WHEEL_ANGLE,
			MAX_WHEEL_ANGLE
		)
		steer = _steer_value

	var throttle: float = 0.0
	if _has_zone(ZONE_GAS):
		throttle = 1.0
	if Input.is_action_pressed("accelerate"):
		throttle = 1.0

	var braking: float = 0.0
	if _has_zone(ZONE_BRAKE):
		braking = 1.0
	if Input.is_action_pressed("brake"):
		braking = 1.0

	bus.set("steer_input", steer)
	bus.set("throttle_input", throttle)
	bus.set("brake_input", braking)


func _update_readouts() -> void:
	if bus != null and is_instance_valid(bus) and _speed_label != null:
		var speed: float = 0.0
		var raw: Variant = bus.get("speed_kmh")
		if raw != null:
			speed = float(raw)
		_speed_label.text = str(int(round(absf(speed))))

		if _gear_label != null:
			var gear_text: String = "N"
			if speed > 2.0:
				gear_text = "D"
			elif speed < -2.0:
				gear_text = "R"
			var doors: Variant = bus.get("doors_open")
			if doors != null and bool(doors):
				gear_text = "DOOR"
			_gear_label.text = gear_text

	if _clock_label != null and GameState != null:
		_clock_label.text = GameState.clock_text()

	if _camera_button != null and camera_system != null and is_instance_valid(camera_system):
		if camera_system.has_method("mode_name"):
			_camera_button.text = str(camera_system.call("mode_name"))


# ---------------------------------------------------------------------------
# TRUE MULTI-TOUCH input.
#
# Godot only forwards ONE finger to Control/Button nodes (mouse emulation),
# so steering while holding the gas pedal would not work with plain Buttons.
# Instead every finger is tracked here by its touch index and hit-tested
# against the pad / pedal rectangles. A mouse (index -1) is supported too so
# the game is still playable on desktop.
# ---------------------------------------------------------------------------

const ZONE_NONE: int = 0
const ZONE_STEER: int = 1
const ZONE_GAS: int = 2
const ZONE_BRAKE: int = 3

var _touch_zones: Dictionary = {}


func _input(event: InputEvent) -> void:
	# Touch only. emulate_touch_from_mouse=true turns desktop clicks into
	# touch events, and emulate_mouse_from_touch=false stops a finger from
	# also generating a mouse event, so every pointer is counted exactly once.
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			_press_at(touch.index, touch.position)
		else:
			_release_index(touch.index)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		_drag_at(drag.index, drag.position)


func _zone_at(pos: Vector2) -> int:
	# While the settings panel is open the driving controls are inert, so
	# tapping a menu button cannot also yank the steering wheel.
	if _settings_panel != null and _settings_panel.visible:
		return ZONE_NONE
	if _steer_pad != null and _steer_pad.get_global_rect().has_point(pos):
		return ZONE_STEER
	if _gas_button != null and _gas_button.get_global_rect().has_point(pos):
		return ZONE_GAS
	if _brake_button != null and _brake_button.get_global_rect().has_point(pos):
		return ZONE_BRAKE
	return ZONE_NONE


func _press_at(index: int, pos: Vector2) -> void:
	var zone: int = _zone_at(pos)
	if zone == ZONE_NONE:
		return
	_touch_zones[index] = zone
	if zone == ZONE_STEER:
		# Ignore extra fingers landing on the wheel while one already holds it.
		if _steer_pointer != -99:
			return
		_steer_pointer = index
		_steer_grabbed = false
		_update_steer_from_global(pos)
	_refresh_pedal_visuals()


func _drag_at(index: int, pos: Vector2) -> void:
	if not _touch_zones.has(index):
		return
	var zone: int = int(_touch_zones[index])
	if zone == ZONE_STEER:
		if index != _steer_pointer:
			return
		_update_steer_from_global(pos)


func _release_index(index: int) -> void:
	if not _touch_zones.has(index):
		return
	var zone: int = int(_touch_zones[index])
	_touch_zones.erase(index)
	if zone == ZONE_STEER and index == _steer_pointer:
		# Let go of the wheel: it self-centres in _process().
		_steer_pointer = -99
		_steer_grabbed = false
	_refresh_pedal_visuals()


func _has_zone(zone: int) -> bool:
	var values: Array = _touch_zones.values()
	var i: int = 0
	while i < values.size():
		if int(values[i]) == zone:
			return true
		i += 1
	return false


func _update_steer_from_global(global_pos: Vector2) -> void:
	## A REAL steering wheel: the finger grabs a point on the rim and the wheel
	## follows the angle of the drag around the hub.
	##
	## This only sets a TARGET angle. _update_wheel_return() eases the wheel
	## toward it at a bounded rate, so a jumpy or duplicated event can never
	## make the wheel snap around.
	if _steer_pad == null:
		return
	var rect: Rect2 = _steer_pad.get_global_rect()
	var center: Vector2 = rect.position + rect.size * 0.5
	var offset: Vector2 = global_pos - center

	# Too close to the hub: no reliable angle.
	if offset.length() < 26.0:
		return

	var angle: float = atan2(offset.y, offset.x)

	if not _steer_grabbed:
		_steer_grabbed = true
		# Anchor the grab so the wheel does not jump to the finger.
		_steer_grab_angle = angle - _wheel_target
		return

	var desired: float = angle - _steer_grab_angle
	# Unwrap into the continuous range around the current target.
	desired = _wheel_target + angle_difference(_wheel_target, desired)
	_wheel_target = clampf(desired, -MAX_WHEEL_ANGLE, MAX_WHEEL_ANGLE)


func _refresh_pedal_visuals() -> void:
	# No inline-if expressions here on purpose: plain branches only.
	var lit: Color = Color(1.35, 1.35, 1.35)
	var normal: Color = Color(1.0, 1.0, 1.0)

	if _gas_button != null:
		if _has_zone(ZONE_GAS):
			_gas_button.modulate = lit
		else:
			_gas_button.modulate = normal

	if _brake_button != null:
		if _has_zone(ZONE_BRAKE):
			_brake_button.modulate = lit
		else:
			_brake_button.modulate = normal


func _move_knob() -> void:
	# Spin the wheel texture to match the current steering angle.
	if _wheel_texture == null or not is_instance_valid(_wheel_texture):
		return
	_wheel_texture.rotation = _wheel_angle


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		_on_camera_pressed()
	elif event.is_action_pressed("toggle_door"):
		_on_door_pressed()
	elif event.is_action_pressed("toggle_lights"):
		_on_light_pressed()
	elif event.is_action_pressed("horn"):
		_on_horn_pressed()


# ---------------------------------------------------------------------------
# Button callbacks
# ---------------------------------------------------------------------------

func _on_horn_pressed() -> void:
	if bus != null and is_instance_valid(bus) and bus.has_method("honk"):
		bus.call("honk")


func _on_door_pressed() -> void:
	if bus != null and is_instance_valid(bus) and bus.has_method("toggle_doors"):
		bus.call("toggle_doors")
		var open: Variant = bus.get("doors_open")
		if GameState != null and open != null:
			if bool(open):
				GameState.notify("Doors open")
			else:
				GameState.notify("Doors closed")
		if _door_button != null:
			if open != null and bool(open):
				_door_button.text = "CLOSE"
			else:
				_door_button.text = "DOOR"


func _on_light_pressed() -> void:
	if bus != null and is_instance_valid(bus) and bus.has_method("toggle_headlights"):
		bus.call("toggle_headlights")
		var on: Variant = bus.get("headlights_on")
		if _light_button != null and on != null:
			if bool(on):
				_light_button.text = "LIGHTS"
				_light_button.modulate = Color(1.0, 0.95, 0.6)
			else:
				_light_button.text = "LIGHTS"
				_light_button.modulate = Color(1.0, 1.0, 1.0)


func _on_camera_pressed() -> void:
	emit_signal("camera_cycle_requested")
	if camera_system != null and is_instance_valid(camera_system):
		if camera_system.has_method("cycle_mode"):
			camera_system.call("cycle_mode")


func _on_money_changed(amount: int) -> void:
	if _money_label != null:
		_money_label.text = str(amount)


func _on_fuel_changed(litres: float, ratio: float) -> void:
	if _fuel_bar != null:
		_fuel_bar.value = ratio * 100.0
		var fill: StyleBoxFlat = _fuel_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill != null:
			if ratio < 0.15:
				fill.bg_color = Color(0.95, 0.25, 0.15)
			elif ratio < 0.35:
				fill.bg_color = Color(0.98, 0.70, 0.15)
			else:
				fill.bg_color = Color(0.25, 0.85, 0.45)
	if _fuel_label != null:
		_fuel_label.text = str(int(round(litres))) + " L"


func _on_passengers_changed(onboard: int, capacity: int) -> void:
	if _passenger_label != null:
		_passenger_label.text = str(onboard) + " / " + str(capacity)


func _on_notification(text: String) -> void:
	if _notify_label != null:
		_notify_label.text = text
		_notify_timer = 3.4


# ---------------------------------------------------------------------------
# HUD construction
# ---------------------------------------------------------------------------

func _make_panel_style(color: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _style_button(button: Button, color: Color) -> void:
	var normal: StyleBoxFlat = _make_panel_style(color, 22)
	var pressed: StyleBoxFlat = _make_panel_style(color.lightened(0.25), 22)
	var hover: StyleBoxFlat = _make_panel_style(color.lightened(0.1), 22)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", normal)
	button.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	button.add_theme_font_size_override("font_size", 24)


func _build_top_bar() -> void:
	var bar: PanelContainer = PanelContainer.new()
	bar.name = "TopBar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 16.0
	bar.offset_right = -16.0
	bar.offset_top = 12.0
	bar.offset_bottom = 78.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.07, 0.11, 0.55), 18))
	add_child(bar)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(row)

	_money_label = _add_stat(row, "COINS", "500", Color(1.0, 0.85, 0.35))
	_passenger_label = _add_stat(row, "PASSENGERS", "0 / 24", Color(0.55, 0.85, 1.0))

	var fuel_box: VBoxContainer = VBoxContainer.new()
	fuel_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fuel_box.custom_minimum_size = Vector2(240.0, 0.0)
	row.add_child(fuel_box)

	var fuel_title: Label = Label.new()
	fuel_title.text = "FUEL"
	fuel_title.add_theme_font_size_override("font_size", 14)
	fuel_title.add_theme_color_override("font_color", Color(0.75, 0.80, 0.88))
	fuel_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fuel_box.add_child(fuel_title)

	var fuel_row: HBoxContainer = HBoxContainer.new()
	fuel_row.add_theme_constant_override("separation", 10)
	fuel_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fuel_box.add_child(fuel_row)

	_fuel_bar = ProgressBar.new()
	_fuel_bar.custom_minimum_size = Vector2(160.0, 20.0)
	_fuel_bar.min_value = 0.0
	_fuel_bar.max_value = 100.0
	_fuel_bar.value = 100.0
	_fuel_bar.show_percentage = false
	_fuel_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg: StyleBoxFlat = _make_panel_style(Color(0.12, 0.14, 0.18, 0.9), 8)
	var fill: StyleBoxFlat = _make_panel_style(Color(0.25, 0.85, 0.45), 8)
	_fuel_bar.add_theme_stylebox_override("background", bg)
	_fuel_bar.add_theme_stylebox_override("fill", fill)
	fuel_row.add_child(_fuel_bar)

	_fuel_label = Label.new()
	_fuel_label.text = "300 L"
	_fuel_label.add_theme_font_size_override("font_size", 18)
	_fuel_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fuel_row.add_child(_fuel_label)

	_clock_label = _add_stat(row, "TIME", "08:00", Color(0.85, 0.88, 0.95))


func _add_stat(parent: Node, title: String, value: String, color: Color) -> Label:
	var box: VBoxContainer = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)

	var title_label: Label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color(0.75, 0.80, 0.88))
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title_label)

	var value_label: Label = Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 26)
	value_label.add_theme_color_override("font_color", color)
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(value_label)

	return value_label


func _build_speedometer() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Speedometer"
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -95.0
	panel.offset_right = 95.0
	panel.offset_top = -120.0
	panel.offset_bottom = -14.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.06, 0.10, 0.60), 20))
	add_child(panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	_speed_label = Label.new()
	_speed_label.text = "0"
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_label.add_theme_font_size_override("font_size", 54)
	_speed_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.85))
	_speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_speed_label)

	_speed_unit = Label.new()
	_speed_unit.text = "km/h"
	_speed_unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_unit.add_theme_font_size_override("font_size", 16)
	_speed_unit.add_theme_color_override("font_color", Color(0.70, 0.78, 0.86))
	_speed_unit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_speed_unit)

	_gear_label = Label.new()
	_gear_label.text = "N"
	_gear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gear_label.add_theme_font_size_override("font_size", 20)
	_gear_label.add_theme_color_override("font_color", Color(1.0, 0.80, 0.35))
	_gear_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_gear_label)


func _build_steering_pad() -> void:
	## A real steering wheel drawn with a shader: outer rim, three spokes and a
	## hub. The whole texture rotates with _wheel_angle.
	var pad: Control = Control.new()
	pad.name = "SteerWheel"
	pad.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	pad.offset_left = 20.0
	pad.offset_right = 20.0 + WHEEL_SIZE
	pad.offset_top = -WHEEL_SIZE - 18.0
	pad.offset_bottom = -18.0
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pad)
	_steer_pad = pad

	var wheel: ColorRect = ColorRect.new()
	wheel.name = "WheelGraphic"
	wheel.size = Vector2(WHEEL_SIZE, WHEEL_SIZE)
	wheel.position = Vector2.ZERO
	wheel.pivot_offset = Vector2(WHEEL_SIZE * 0.5, WHEEL_SIZE * 0.5)
	wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader: Shader = Shader.new()
	shader.code = _wheel_shader_code()
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	wheel.material = mat

	pad.add_child(wheel)
	_wheel_texture = wheel
	_steer_knob = wheel


func _wheel_shader_code() -> String:
	var lines: Array[String] = [
		"shader_type canvas_item;",
		"",
		"// Procedural bus steering wheel: rim, hub and three spokes.",
		"",
		"void fragment() {",
		"\tvec2 p = UV - vec2(0.5);",
		"\tfloat r = length(p) * 2.0;",
		"\tfloat a = atan(p.y, p.x);",
		"",
		"\tfloat aa = fwidth(r) * 2.0;",
		"",
		"\t// outer rim",
		"\tfloat rim = smoothstep(1.0, 1.0 - aa, r) * smoothstep(0.74 - aa, 0.74, r);",
		"",
		"\t// hub in the middle",
		"\tfloat hub = smoothstep(0.30, 0.30 - aa, r);",
		"",
		"\t// three spokes: two lower, one upper",
		"\tfloat spokes = 0.0;",
		"\tfloat band = 0.16;",
		"\tfloat sa = abs(sin(a * 1.5));",
		"\tfloat spoke_mask = smoothstep(band, band - 0.05, abs(cos(a * 1.5)));",
		"\tspokes = spoke_mask * smoothstep(0.78, 0.74, r) * smoothstep(0.24, 0.30, r);",
		"",
		"\tfloat wheel = clamp(rim + hub + spokes, 0.0, 1.0);",
		"",
		"\t// shading: lighter at the top for a rubbery highlight",
		"\tvec3 dark = vec3(0.07, 0.075, 0.09);",
		"\tvec3 light = vec3(0.24, 0.25, 0.29);",
		"\tvec3 col = mix(dark, light, clamp(0.5 - p.y * 1.4, 0.0, 1.0));",
		"",
		"\t// chrome ring accent on the hub",
		"\tfloat ring = smoothstep(0.30, 0.28, r) * smoothstep(0.20, 0.22, r);",
		"\tcol = mix(col, vec3(0.55, 0.58, 0.64), ring * 0.9);",
		"",
		"\tCOLOR = vec4(col, wheel * 0.88);",
		"}",
		"",
	]
	return "\n".join(lines)


func _build_pedals() -> void:
	# Pedals are Panels, not Buttons: touch is handled manually in _input()
	# so gas + steering can be held at the same time (real multi-touch).
	_brake_button = _make_pedal("BRAKE", Color(0.72, 0.18, 0.16, 0.72), 26)
	_brake_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_brake_button.offset_left = -(PEDAL_W * 2.0) - 46.0
	_brake_button.offset_right = -PEDAL_W - 46.0
	_brake_button.offset_top = -PEDAL_H - 24.0
	_brake_button.offset_bottom = -24.0
	add_child(_brake_button)

	_gas_button = _make_pedal("GAS", Color(0.14, 0.58, 0.30, 0.72), 30)
	_gas_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_gas_button.offset_left = -PEDAL_W - 24.0
	_gas_button.offset_right = -24.0
	_gas_button.offset_top = -PEDAL_H - 24.0
	_gas_button.offset_bottom = -24.0
	add_child(_gas_button)


func _make_pedal(text: String, color: Color, font_size: int) -> PanelContainer:
	var pedal: PanelContainer = PanelContainer.new()
	pedal.name = text + "Pedal"
	pedal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pedal.add_theme_stylebox_override("panel", _make_panel_style(color, 28))

	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pedal.add_child(label)
	return pedal


func _build_action_buttons() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.name = "ActionButtons"
	column.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	column.offset_left = -(BUTTON_SIZE + 24.0)
	column.offset_right = -24.0
	column.offset_top = -170.0
	column.offset_bottom = 90.0
	column.add_theme_constant_override("separation", 12)
	add_child(column)

	var horn: Button = _make_action_button("HORN", Color(0.20, 0.32, 0.55, 0.72))
	horn.pressed.connect(_on_horn_pressed)
	column.add_child(horn)

	_door_button = _make_action_button("DOOR", Color(0.32, 0.24, 0.55, 0.72))
	_door_button.pressed.connect(_on_door_pressed)
	column.add_child(_door_button)

	_camera_button = _make_action_button("CHASE", Color(0.18, 0.42, 0.48, 0.72))
	_camera_button.pressed.connect(_on_camera_pressed)
	column.add_child(_camera_button)

	_light_button = _make_action_button("LIGHTS", Color(0.48, 0.38, 0.14, 0.72))
	_light_button.pressed.connect(_on_light_pressed)
	column.add_child(_light_button)


func _make_action_button(text: String, color: Color) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(BUTTON_SIZE + 24.0, BUTTON_SIZE * 0.62)
	_style_button(button, color)
	button.add_theme_font_size_override("font_size", 18)
	return button


func _build_notifications() -> void:
	_notify_label = Label.new()
	_notify_label.name = "Notification"
	_notify_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notify_label.offset_left = -320.0
	_notify_label.offset_right = 320.0
	_notify_label.offset_top = 92.0
	_notify_label.offset_bottom = 132.0
	_notify_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notify_label.add_theme_font_size_override("font_size", 22)
	_notify_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	_notify_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_notify_label.add_theme_constant_override("outline_size", 6)
	_notify_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notify_label.text = ""
	add_child(_notify_label)


# ---------------------------------------------------------------------------
# FPS counter + graphics settings menu
# ---------------------------------------------------------------------------

func _build_fps_counter() -> void:
	_fps_label = Label.new()
	_fps_label.name = "FpsLabel"
	_fps_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_fps_label.offset_left = 22.0
	_fps_label.offset_top = 86.0
	_fps_label.offset_right = 200.0
	_fps_label.offset_bottom = 112.0
	_fps_label.add_theme_font_size_override("font_size", 18)
	_fps_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_fps_label.add_theme_constant_override("outline_size", 5)
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.visible = false
	add_child(_fps_label)


func _update_fps() -> void:
	if _fps_label == null:
		return
	var want: bool = false
	if Settings != null:
		want = Settings.show_fps
	_fps_label.visible = want
	if not want:
		return
	_fps_label.text = str(Engine.get_frames_per_second()) + " FPS"


func _build_settings_menu() -> void:
	# Gear button, top-right corner.
	var gear: Button = Button.new()
	gear.name = "SettingsButton"
	gear.text = "SETTINGS"
	gear.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	gear.offset_left = -150.0
	gear.offset_right = -18.0
	gear.offset_top = 86.0
	gear.offset_bottom = 130.0
	_style_button(gear, Color(0.16, 0.18, 0.24, 0.8))
	gear.add_theme_font_size_override("font_size", 16)
	gear.pressed.connect(_toggle_settings)
	add_child(gear)

	var panel: Panel = Panel.new()
	panel.name = "SettingsPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -260.0
	panel.offset_right = 260.0
	panel.offset_top = -215.0
	panel.offset_bottom = 215.0
	panel.add_theme_stylebox_override("panel",
		_make_panel_style(Color(0.05, 0.06, 0.09, 0.96), 18))
	panel.visible = false
	add_child(panel)
	_settings_panel = panel

	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 18.0
	box.offset_right = -18.0
	box.offset_top = 14.0
	box.offset_bottom = -14.0
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title: Label = Label.new()
	title.text = "GRAPHICS SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
	box.add_child(title)

	_add_setting_row(box, "quality", "Quality", _on_quality_pressed)
	_add_setting_row(box, "scale", "Resolution", _on_scale_pressed)
	_add_setting_row(box, "shadows", "Shadows", _on_shadows_pressed)
	_add_setting_row(box, "glow", "Bloom / Glow", _on_glow_pressed)
	_add_setting_row(box, "fog", "Fog", _on_fog_pressed)
	_add_setting_row(box, "fps_cap", "FPS Limit", _on_fps_cap_pressed)
	_add_setting_row(box, "fps_show", "Show FPS", _on_fps_show_pressed)

	var close: Button = Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(0.0, 46.0)
	_style_button(close, Color(0.35, 0.16, 0.18, 0.85))
	close.pressed.connect(_toggle_settings)
	box.add_child(close)

	_refresh_settings_labels()


func _add_setting_row(parent: Node, key: String, label_text: String,
		handler: Callable) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var name_label: Label = Label.new()
	name_label.text = label_text
	name_label.custom_minimum_size = Vector2(210.0, 40.0)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	row.add_child(name_label)

	var value_button: Button = Button.new()
	value_button.text = "-"
	value_button.custom_minimum_size = Vector2(230.0, 40.0)
	value_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(value_button, Color(0.14, 0.28, 0.42, 0.85))
	value_button.add_theme_font_size_override("font_size", 17)
	value_button.pressed.connect(handler)
	row.add_child(value_button)

	_settings_rows[key] = value_button


func _toggle_settings() -> void:
	if _settings_panel == null:
		return
	_settings_panel.visible = not _settings_panel.visible
	if _settings_panel.visible:
		_refresh_settings_labels()


func _on_off_text(value: bool) -> String:
	if value:
		return "ON"
	return "OFF"


func _refresh_settings_labels() -> void:
	if Settings == null:
		return
	if _settings_rows.has("quality"):
		_settings_rows["quality"].text = Settings.quality_name()
	if _settings_rows.has("scale"):
		var pct: int = int(round(Settings.render_scale * 100.0))
		_settings_rows["scale"].text = str(pct) + " %"
	if _settings_rows.has("shadows"):
		_settings_rows["shadows"].text = _on_off_text(Settings.shadows_enabled)
	if _settings_rows.has("glow"):
		_settings_rows["glow"].text = _on_off_text(Settings.glow_enabled)
	if _settings_rows.has("fog"):
		_settings_rows["fog"].text = _on_off_text(Settings.fog_enabled)
	if _settings_rows.has("fps_cap"):
		_settings_rows["fps_cap"].text = Settings.fps_label()
	if _settings_rows.has("fps_show"):
		_settings_rows["fps_show"].text = _on_off_text(Settings.show_fps)


func _on_quality_pressed() -> void:
	if Settings == null:
		return
	var next: int = Settings.quality + 1
	if next > 2:
		next = 0
	Settings.set_quality(next)
	_refresh_settings_labels()
	if GameState != null:
		GameState.notify("Quality: " + Settings.quality_name())


func _on_scale_pressed() -> void:
	if Settings == null:
		return
	Settings.cycle_render_scale()
	_refresh_settings_labels()


func _on_shadows_pressed() -> void:
	if Settings == null:
		return
	Settings.toggle_shadows()
	_refresh_settings_labels()


func _on_glow_pressed() -> void:
	if Settings == null:
		return
	Settings.toggle_glow()
	_refresh_settings_labels()


func _on_fog_pressed() -> void:
	if Settings == null:
		return
	Settings.toggle_fog()
	_refresh_settings_labels()


func _on_fps_cap_pressed() -> void:
	if Settings == null:
		return
	Settings.cycle_target_fps()
	_refresh_settings_labels()


func _on_fps_show_pressed() -> void:
	if Settings == null:
		return
	Settings.toggle_fps_counter()
	_refresh_settings_labels()
