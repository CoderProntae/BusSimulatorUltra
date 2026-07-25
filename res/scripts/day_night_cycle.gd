class_name DayNightCycle
extends Node

@export var cycle_seconds: float = 300.0
var sun: DirectionalLight3D
var time_of_day: float = 0.30
var night_amount: float = 0.0

func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / cycle_seconds, 1.0)
	var angle := time_of_day * TAU - PI * 0.5
	night_amount = clampf((-sin(angle) + 0.12) * 1.4, 0.0, 1.0)
	if sun != null:
		sun.rotation_degrees.x = rad_to_deg(angle)
		sun.light_energy = lerpf(0.08, 1.3, 1.0 - night_amount)
	for lamp in get_tree().get_nodes_in_group("street_lamp"):
		lamp.visible = night_amount > 0.35
	for bus in get_tree().get_nodes_in_group("bus"):
		bus.set_night_lights(night_amount > 0.35)
