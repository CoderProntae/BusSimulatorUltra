extends Button

## A Button that ALSO reacts to real finger taps.
##
## WHY THIS EXISTS
## ---------------
## Godot's BaseButton::gui_input() only acts on InputEventMouseButton (or the
## "ui_accept" action). It has no InputEventScreenTouch branch at all. Normally
## that is invisible, because the project setting
## input_devices/pointing/emulate_mouse_from_touch turns a finger into a
## synthetic mouse click and the button reacts to that.
##
## This project must keep emulate_mouse_from_touch = FALSE, because the
## synthetic mouse pointer used to fight the real touch pointer for ownership
## of the steering wheel (the wheel latched on release and jerked on the next
## grab). See HANDOVER.md 3.6.
##
## With that emulation off, every Button in the game became dead on Android.
## Turning the emulation back on is NOT an option either: Godot only emulates
## the mouse for the FIRST finger down (Input::mouse_from_touch_index), so
## while a finger holds the gas pedal, tapping HORN would do nothing.
##
## So the button reads the touch stream itself. Any finger works, at any time,
## in parallel with steering and the pedals.

## Touch indices currently held down inside this button.
var _touch_down: Dictionary = {}
var _base_modulate: Color = Color(1, 1, 1, 1)


func _ready() -> void:
	_base_modulate = modulate


func _input(event: InputEvent) -> void:
	if disabled:
		return
	if not is_visible_in_tree():
		return

	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		# device == DEVICE_ID_EMULATION means this "touch" was synthesised from
		# a real mouse click (emulate_touch_from_mouse = true, used so the game
		# is playable on desktop). The genuine mouse event is already handled
		# by BaseButton, so acting on this too would fire the button twice.
		if touch.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if touch.pressed:
			_touch_press(touch.index, touch.position)
		else:
			_touch_release(touch.index, touch.position)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_touch_drag(drag.index, drag.position)


func _touch_press(index: int, pos: Vector2) -> void:
	if not get_global_rect().has_point(pos):
		return
	if _blocked_by_modal():
		return
	_touch_down[index] = true
	_apply_press_tint(true)
	accept_event()


func _touch_drag(index: int, pos: Vector2) -> void:
	if not _touch_down.has(index):
		return
	# Sliding the finger off the button cancels the press, matching how a
	# mouse-driven Button behaves.
	var inside: bool = get_global_rect().has_point(pos)
	_apply_press_tint(inside)


func _touch_release(index: int, pos: Vector2) -> void:
	if not _touch_down.has(index):
		return
	_touch_down.erase(index)
	_apply_press_tint(false)
	if not get_global_rect().has_point(pos):
		return
	accept_event()
	emit_signal("pressed")


func _apply_press_tint(down: bool) -> void:
	if down:
		modulate = Color(
			_base_modulate.r * 1.25,
			_base_modulate.g * 1.25,
			_base_modulate.b * 1.25,
			_base_modulate.a
		)
		return
	modulate = _base_modulate


func _blocked_by_modal() -> bool:
	## A visible node in the "touch_modal" group (the in-game settings panel)
	## swallows taps meant for whatever sits behind it. Plain Buttons get this
	## for free from the GUI stack; hit-testing by hand does not, so it is done
	## explicitly here.
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	var blockers: Array = tree.get_nodes_in_group("touch_modal")
	var i: int = 0
	while i < blockers.size():
		var node: Node = blockers[i] as Node
		i += 1
		if node == null:
			continue
		if not (node is CanvasItem):
			continue
		if not (node as CanvasItem).is_visible_in_tree():
			continue
		if node == self:
			continue
		if node.is_ancestor_of(self):
			continue
		return true
	return false
