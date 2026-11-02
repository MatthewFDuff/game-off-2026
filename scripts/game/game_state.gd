class_name GameState
extends Node
## Run-wide numbers: money, which shift it is, this shift's quota and progress, and run totals for
## the game-over summary.

signal changed

@export var starting_money := 60

var money := 0
var shift := 1
## Shrooms that must be harvested tonight. Also the minimum number of spores to plant today.
var quota := 0
var planted := 0
var harvested := 0
## This shift's tallies for the dawn summary. Reset when each day shift starts.
var shift_harvested := 0
## Harvests beyond the quota this shift.
var shift_extra := 0
## Money earned this shift: harvest rewards plus the survival bonus.
var shift_earned := 0
## Run totals, never reset between shifts.
var total_harvested := 0
var total_earned := 0


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
	shift_earned += amount
	total_earned += amount
	changed.emit()


## Counts a harvest towards the shift tally and the run total. Called after the shroom manager has
## bumped `harvested`, so anything past the quota counts as extra.
func record_harvest() -> void:
	shift_harvested += 1
	if harvested > quota:
		shift_extra += 1
	total_harvested += 1


## Clears the per-shift tallies at the start of a day shift.
func reset_shift_tallies() -> void:
	shift_harvested = 0
	shift_extra = 0
	shift_earned = 0
