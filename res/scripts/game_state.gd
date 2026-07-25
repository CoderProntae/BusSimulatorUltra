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


func _ready() -> void:
	reset()


func reset() -> void:
	money = START_MONEY
	fuel = FUEL_CAPACITY
	passengers_onboard = 0
	passengers_delivered = 0
	_notify_history.clear()
	emit_signal("money_changed", money)
	emit_signal("fuel_changed", fuel, fuel_ratio())
	emit_signal("passengers_changed", passengers_onboard, capacity)
	emit_signal("delivered_changed", passengers_delivered)


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
