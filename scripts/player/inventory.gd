class_name Inventory
extends Node
## What a player carries: ammo per type (basic is infinite), flasks per type (Weapon throws them)
## and keycards (doors check them in phase 5). Each peer keeps its own player's inventory; pickups
## reach it through ItemManager, which the host runs.
##
## Item names (the item marker's string, and pickups): `medkit`, `ammo_<type>` (AmmoType.ORDER),
## `flask_<fire|poison|rage|freeze|foam>`, `keycard_<color>`, `spore_shooter` (arms the player;
## LevelPlay.arm_party arms the rest of the party), `snack` (a vending machine's: SNACK_HEAL health)
## and `paper_<printer id>` (a printed page: LevelPlay shows its text; nothing is carried).

## Any count changed (ammo, flasks, keycards).
signal changed

const FLASKS := ["fire", "poison", "rage", "freeze", "foam"]
const MAX_FLASKS := 5
## Health a medkit gives back.
const MEDKIT_HEAL := 50.0
## Health a snack gives back.
const SNACK_HEAL := 15.0

## ammo type name -> rounds (basic is never stored: it's infinite)
var ammo := {}
## flask type -> count
var flasks := {}
var keycards: Array[String] = []


## Rounds of an ammo type; -1 for infinite.
func count(ammo_name: String) -> int:
	var type := AmmoType.by_name(ammo_name)
	if type and type.infinite:
		return -1
	return ammo.get(ammo_name, 0)


func has_ammo(ammo_name: String) -> bool:
	return count(ammo_name) != 0


## Spends rounds; false (and nothing spent) when there aren't enough. Infinite types always work.
func use_ammo(ammo_name: String, amount := 1) -> bool:
	var have := count(ammo_name)
	if have < 0:
		return true
	if have < amount:
		return false
	ammo[ammo_name] = have - amount
	changed.emit()
	return true


## Gives an item: amount rounds of ammo, flasks or (medkit) health; -1 is the item's usual amount
## (an ammo type's pickup size, one flask, MEDKIT_HEAL). Returns false for unknown item names.
func add(item_name: String, amount := -1) -> bool:
	if item_name == "spore_shooter":
		var player := get_parent() as Player
		if player:
			player.set_armed(true)
		changed.emit()
		return true
	if item_name == "medkit":
		var player := get_parent() as Player
		if player:
			player.health = minf(player.max_health, player.health + (MEDKIT_HEAL if amount < 0 else float(amount)))
		changed.emit()
		return true
	if item_name == "snack":
		var player := get_parent() as Player
		if player:
			player.health = minf(player.max_health, player.health + (SNACK_HEAL if amount < 0 else float(amount)))
		changed.emit()
		return true
	if item_name.begins_with("paper_"):
		return true # Read, not carried (LevelPlay shows it).
	if item_name.begins_with("ammo_"):
		var type := AmmoType.by_name(item_name.trim_prefix("ammo_"))
		if type == null:
			return false
		if not type.infinite:
			ammo[type.name] = mini(count(type.name) + (type.pickup if amount < 0 else amount), type.max_count)
		changed.emit()
		return true
	if item_name.begins_with("flask_"):
		var flask := item_name.trim_prefix("flask_")
		if flask not in FLASKS:
			return false
		flasks[flask] = mini(int(flasks.get(flask, 0)) + (1 if amount < 0 else amount), MAX_FLASKS)
		changed.emit()
		return true
	if item_name.begins_with("keycard_"):
		var card := item_name.trim_prefix("keycard_")
		if card not in keycards:
			keycards.append(card)
		changed.emit()
		return true
	return false


## Flasks of a type (FLASKS) carried.
func flask_count(flask: String) -> int:
	return int(flasks.get(flask, 0))


## Spends one flask; false (nothing spent) when there's none.
func use_flask(flask: String) -> bool:
	if flask_count(flask) <= 0:
		return false
	flasks[flask] = flask_count(flask) - 1
	changed.emit()
	return true


func has_keycard(color: String) -> bool:
	return color in keycards


## Empties everything (a new play session).
func clear() -> void:
	ammo.clear()
	flasks.clear()
	keycards.clear()
	changed.emit()
