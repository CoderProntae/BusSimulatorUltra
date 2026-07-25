class_name UIManager
extends CanvasLayer

var game_state: GameState
var bus: BusController
var status: Label
var stats: Label

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	stats = Label.new()
	stats.position = Vector2(28, 25)
	stats.add_theme_font_size_override("font_size", 28)
	root.add_child(stats)
	status = Label.new()
	status.position = Vector2(28, 105)
	status.add_theme_font_size_override("font_size", 20)
	root.add_child(status)
	_make_button(root, "◀", Vector2(35, 560), func(): Input.action_press("steer_left"), func(): Input.action_release("steer_left"))
	_make_button(root, "▶", Vector2(155, 560), func(): Input.action_press("steer_right"), func(): Input.action_release("steer_right"))
	_make_button(root, "GAS", Vector2(1050, 520), func(): Input.action_press("accelerate"), func(): Input.action_release("accelerate"))
	_make_button(root, "BRAKE", Vector2(1050, 610), func(): Input.action_press("brake"), func(): Input.action_release("brake"))
	_make_button(root, "DOOR", Vector2(850, 630), _door, func(): pass)
	_make_button(root, "CAM", Vector2(720, 630), _camera, func(): pass)

func _make_button(parent: Control, text: String, pos: Vector2, pressed: Callable, released: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.position = pos
	button.size = Vector2(105, 75)
	button.modulate = Color(1, 1, 1, 0.82)
	button.add_theme_font_size_override("font_size", 21)
	button.button_down.connect(pressed)
	button.button_up.connect(released)
	parent.add_child(button)

func _door() -> void:
	if bus != null:
		bus.toggle_door()
		status.text = "Stop serviced: " + get_tree().get_first_node_in_group("passengers").service_stop()

func _camera() -> void:
	get_tree().get_first_node_in_group("camera_system").cycle()

func _process(_delta: float) -> void:
	if game_state != null and bus != null:
		stats.text = "€ " + str(game_state.coins) + "   FUEL " + str(roundi(game_state.fuel)) + "%   PASSENGERS " + str(game_state.passengers) + "\n" + str(roundi(bus.speed_kph)) + " km/h"
