class_name GameState
extends Node
## Run-wide numbers: money, which shift it is, and this shift's quota and progress.

signal changed

@export var starting_money := 60

var money := 0
var shift := 1
## Shrooms that must be harvested tonight. Also the minimum number of spores to plant today.
var quota := 0
var planted := 0
var harvested := 0


func _ready() -> void:
	money = starting_money


func can_afford(amount: int) -> bool:
	return money >= amount


func spend(amount: int) -> bool:
	if money < amount:
		return false
	money -= amount
	changed.emit()
	return true


func earn(amount: int) -> void:
	money += amount
	changed.emit()
