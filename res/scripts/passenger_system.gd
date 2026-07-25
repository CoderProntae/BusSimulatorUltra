class_name PassengerSystem
extends Node

var game_state: GameState
var stop_index: int = 0
var stop_names := ["Central Station", "Riverside", "Market Square", "University"]

func service_stop() -> String:
	if game_state == null:
		return "No route active"
	var message := ""
	if game_state.passengers > 0:
		var leaving := mini(game_state.passengers, 2)
		game_state.passengers -= leaving
		game_state.delivered += leaving
		var reward := leaving * 25
		game_state.earn(reward)
		message = str(leaving) + " passengers delivered +" + str(reward)
	else:
		var boarding := 1 + (stop_index % 3)
		game_state.passengers += boarding
		message = str(boarding) + " passengers boarded"
	stop_index = (stop_index + 1) % stop_names.size()
	return message
