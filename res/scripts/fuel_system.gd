class_name FuelSystem
extends Node

@export var drain_per_second: float = 0.035
var game_state: GameState

func _process(delta: float) -> void:
	if game_state == null:
		return
	var bus := get_tree().get_first_node_in_group("bus")
	if bus != null and bus.speed_kph > 1.0:
		game_state.fuel = maxf(0.0, game_state.fuel - drain_per_second * delta * (1.0 + bus.speed_kph / 80.0))

func refuel() -> void:
	if game_state != null and game_state.spend(40):
		game_state.fuel = minf(100.0, game_state.fuel + 35.0)
