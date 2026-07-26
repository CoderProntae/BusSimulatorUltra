extends Node

## Global game state singleton (autoload "GameState").
## Holds economy, fuel, passenger counters and the shared day/night factor.
## No file loading happens here, so it can never crash on a missing asset.

signal money_changed(amount: int)
signal fuel_changed(litres: float, ratio: float)
signal passengers_changed(onboard: int, capacity: int)
signal delivered_changed(total: int)
signal notification_posted(text: String)
signal night_factor_changed(night: float)
signal time_of_day_changed(hours: float)
## Emitted whenever the set of destinations onboard changes, so the HUD map
## and the objective banner can update.
signal destinations_changed()

const START_MONEY: int = 500
const FUEL_CAPACITY: float = 300.0
const BUS_CAPACITY: int = 24
const FARE_MIN: int = 10
const FARE_MAX: int = 50
const FUEL_PRICE_PER_LITRE: float = 1.4

var money: int = START_MONEY
var fuel: float = FUEL_CAPACITY
var passengers_onboard: int = 0
var passengers_delivered: int = 0
var capacity: int = BUS_CAPACITY

## 0.0 = full day, 1.0 = full night. Driven by day_night_cycle.gd.
var night_factor: float = 0.0
## Clock in hours (0-24) purely for HUD display.
var clock_hours: float = 8.0

var _notify_history: Array[String] = []

## Every bus stop in the city, registered by BusStop nodes as they spawn.
## Each entry: { "name": String, "position": Vector3, "node": Node }
var stops: Array[Dictionary] = []
## How many onboard passengers are travelling to each stop name.
## Key: stop name (String) -> value: passenger count (int).
var destinations: Dictionary = {}


func _ready() -> void:
	reset()


func reset() -> void:
	money = START_MONEY
	fuel = FUEL_CAPACITY
	passengers_onboard = 0
	passengers_delivered = 0
	destinations.clear()
	_notify_history.clear()
	emit_signal("money_changed", money)
	emit_signal("fuel_changed", fuel, fuel_ratio())
	emit_signal("passengers_changed", passengers_onboard, capacity)
	emit_signal("delivered_changed", passengers_delivered)
	emit_signal("destinations_changed")


# ---------------------------------------------------------------------------
# Stop registry + passenger destinations (drives the HUD map)
# ---------------------------------------------------------------------------

func register_stop(stop_name: String, position: Vector3, node: Node) -> void:
	var entry: Dictionary = {}
	entry["name"] = stop_name
	entry["position"] = position
	entry["node"] = node
	stops.append(entry)


func clear_stops() -> void:
	stops.clear()
	destinations.clear()
	emit_signal("destinations_changed")


func stop_position(stop_name: String) -> Vector3:
	var i: int = 0
	while i < stops.size():
		var entry: Dictionary = stops[i]
		if String(entry.get("name", "")) == stop_name:
			return entry.get("position", Vector3.ZERO)
		i += 1
	return Vector3.ZERO


func pick_destination(exclude_name: String) -> String:
	## Chooses a stop for a boarding passenger, never the one they are
	## standing at.
	if stops.is_empty():
		return ""
	var candidates: Array[String] = []
	var i: int = 0
	while i < stops.size():
		var entry: Dictionary = stops[i]
		var name_value: String = String(entry.get("name", ""))
		if name_value != "" and name_value != exclude_name:
			candidates.append(name_value)
		i += 1
	if candidates.is_empty():
		return ""
	return candidates[randi() % candidates.size()]


func add_destination(stop_name: String, count: int) -> void:
	if stop_name == "" or count <= 0:
		return
	var current: int = int(destinations.get(stop_name, 0))
	destinations[stop_name] = current + count
	emit_signal("destinations_changed")


func passengers_for(stop_name: String) -> int:
	return int(destinations.get(stop_name, 0))


func take_destination(stop_name: String, count: int) -> int:
	## Removes up to `count` passengers bound for this stop, returning how
	## many were actually there.
	var current: int = int(destinations.get(stop_name, 0))
	var taken: int = mini(count, current)
	if taken <= 0:
		return 0
	var left: int = current - taken
	if left > 0:
		destinations[stop_name] = left
	else:
		destinations.erase(stop_name)
	emit_signal("destinations_changed")
	return taken


func next_destination_name() -> String:
	## The stop the HUD should point the driver at: whichever onboard
	## destination is nearest, resolved by the caller passing positions in.
	var names: Array = destinations.keys()
	if names.is_empty():
		return ""
	return String(names[0])


func fuel_ratio() -> float:
	if FUEL_CAPACITY <= 0.0:
		return 0.0
	return clampf(fuel / FUEL_CAPACITY, 0.0, 1.0)


func add_money(amount: int) -> void:
	money += amount
	if money < 0:
		money = 0
	emit_signal("money_changed", money)


func spend_money(amount: int) -> bool:
	if amount <= 0:
		return true
	if money < amount:
		return false
	money -= amount
	emit_signal("money_changed", money)
	return true


func consume_fuel(litres: float) -> void:
	if litres <= 0.0:
		return
	fuel = clampf(fuel - litres, 0.0, FUEL_CAPACITY)
	emit_signal("fuel_changed", fuel, fuel_ratio())


func add_fuel(litres: float) -> float:
	var before: float = fuel
	fuel = clampf(fuel + litres, 0.0, FUEL_CAPACITY)
	var added: float = fuel - before
	if added > 0.0:
		emit_signal("fuel_changed", fuel, fuel_ratio())
	return added


func has_fuel() -> bool:
	return fuel > 0.05


func free_seats() -> int:
	var seats: int = capacity - passengers_onboard
	if seats < 0:
		seats = 0
	return seats


func board_passengers(count: int) -> int:
	var allowed: int = mini(count, free_seats())
	if allowed <= 0:
		return 0
	passengers_onboard += allowed
	emit_signal("passengers_changed", passengers_onboard, capacity)
	return allowed


func alight_passengers(count: int) -> int:
	var allowed: int = mini(count, passengers_onboard)
	if allowed <= 0:
		return 0
	passengers_onboard -= allowed
	passengers_delivered += allowed
	var earned: int = 0
	var i: int = 0
	while i < allowed:
		earned += randi_range(FARE_MIN, FARE_MAX)
		i += 1
	add_money(earned)
	emit_signal("passengers_changed", passengers_onboard, capacity)
	emit_signal("delivered_changed", passengers_delivered)
	return earned


func set_night_factor(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 1.0)
	if absf(clamped - night_factor) < 0.001:
		return
	night_factor = clamped
	emit_signal("night_factor_changed", night_factor)


func set_clock(hours: float) -> void:
	clock_hours = fposmod(hours, 24.0)
	emit_signal("time_of_day_changed", clock_hours)


func clock_text() -> String:
	var h: int = int(floor(clock_hours))
	var m: int = int(floor(fposmod(clock_hours, 1.0) * 60.0))
	var hh: String = str(h)
	if h < 10:
		hh = "0" + hh
	var mm: String = str(m)
	if m < 10:
		mm = "0" + mm
	return hh + ":" + mm


func notify(text: String) -> void:
	_notify_history.append(text)
	if _notify_history.size() > 20:
		_notify_history.pop_front()
	emit_signal("notification_posted", text)
