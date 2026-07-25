class_name GameState
extends Node

var coins: int = 500
var fuel: float = 100.0
var passengers: int = 0
var delivered: int = 0

func earn(amount: int) -> void:
	coins += amount

func spend(amount: int) -> bool:
	if coins < amount:
		return false
	coins -= amount
	return true
