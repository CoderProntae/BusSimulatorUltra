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

@export var bus_path: NodePath
@export var camera_path: NodePath

var bus: Node = null
var camera_system: Node = null

var _steer_pad: Control = null
var _steer_knob: Control = null
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

	_apply_inputs()
	_update_readouts()

	if _notify_timer > 0.0:
		_notify_timer -= delta
		if _notify_timer <= 0.0 and _notify_label != null:
			_notify_label.text = ""


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
		steer = key_steer

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
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			_press_at(touch.index, touch.position)
		else:
			_release_index(touch.index)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		_drag_at(drag.index, drag.position)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_at(-1, mb.position)
			else:
				_release_index(-1)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if _touch_zones.has(-1):
			_drag_at(-1, mm.position)


func _zone_at(pos: Vector2) -> int:
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
		_update_steer_from_global(pos)
	_refresh_pedal_visuals()


func _drag_at(index: int, pos: Vector2) -> void:
	if not _touch_zones.has(index):
		return
	var zone: int = int(_touch_zones[index])
	if zone == ZONE_STEER:
		_update_steer_from_global(pos)


func _release_index(index: int) -> void:
	if not _touch_zones.has(index):
		return
	var zone: int = int(_touch_zones[index])
	_touch_zones.erase(index)
	if zone == ZONE_STEER and not _has_zone(ZONE_STEER):
		_steer_value = 0.0
		_move_knob()
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
	if _steer_pad == null:
		return
	var rect: Rect2 = _steer_pad.get_global_rect()
	var center_x: float = rect.position.x + rect.size.x * 0.5
	var max_dx: float = maxf(rect.size.x * 0.5 - 20.0, 1.0)
	_steer_value = clampf((global_pos.x - center_x) / max_dx, -1.0, 1.0)
	_move_knob()


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
	if _steer_knob == null or _steer_pad == null:
		return
	var size: Vector2 = _steer_pad.size
	var knob_size: Vector2 = _steer_knob.size
	var travel: float = size.x * 0.5 - knob_size.x * 0.5 - 10.0
	var x: float = size.x * 0.5 - knob_size.x * 0.5 + _steer_value * travel
	var y: float = size.y * 0.5 - knob_size.y * 0.5
	_steer_knob.position = Vector2(x, y)


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
	var pad: PanelContainer = PanelContainer.new()
	pad.name = "SteerPad"
	pad.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	pad.offset_left = 24.0
	pad.offset_right = 24.0 + PAD_SIZE
	pad.offset_top = -(PAD_SIZE * 0.52) - 24.0
	pad.offset_bottom = -24.0
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.10, 0.14, 0.42), 80))
	add_child(pad)
	_steer_pad = pad

	var hint: Label = Label.new()
	hint.text = "STEER"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(hint)

	var knob: Panel = Panel.new()
	knob.name = "Knob"
	knob.custom_minimum_size = Vector2(84.0, 84.0)
	knob.size = Vector2(84.0, 84.0)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	knob.add_theme_stylebox_override("panel", _make_panel_style(Color(0.85, 0.90, 1.0, 0.55), 42))
	pad.add_child(knob)
	_steer_knob = knob

	await get_tree().process_frame
	_move_knob()


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
