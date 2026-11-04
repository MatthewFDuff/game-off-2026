class_name Interactables
extends RefCounted
## What the local player can use with E: the nearest door or usable prop (LevelSchema.USES) whose
## box the camera's ray enters within LevelPlay.DOOR_REACH, unless a voxel is in the way, and the
## prompt to show for it ("[E] Open", "Locked: needs red keycard", "No power", ...). Owned by
## LevelPlay, which holds the state the prompts read; the host decides what using actually does.

var play: LevelPlay


func _init(level_play: LevelPlay) -> void:
	play = level_play


## The id of the door or prop in view, or "".
func in_view(camera: Camera3D) -> String:
	if camera == null or not play.active:
		return ""
	var from := camera.global_position
	var direction := -camera.global_basis.z
	var best := ""
	var best_distance := LevelPlay.DOOR_REACH
	# Every frame: every door (a few dozen, and they move), but only the usables in the chunks within
	# reach (LevelPlay.usables_near), and boxes out of reach are dropped before any ray test.
	for id: String in play._doors:
		var box := play.door_box(id)
		if from.clamp(box.position, box.end).distance_to(from) > LevelPlay.DOOR_REACH:
			continue
		var distance := 0.0
		if not box.has_point(from):
			var hit = box.intersects_ray(from, direction)
			if hit == null:
				continue
			distance = from.distance_to(hit)
		if distance < best_distance:
			best_distance = distance
			best = id
	for id: String in play.usables_near(from, LevelPlay.DOOR_REACH):
		var box: AABB = play._usables.get(id, AABB())
		if box.size == Vector3.ZERO or from.clamp(box.position, box.end).distance_to(from) > LevelPlay.DOOR_REACH:
			continue
		var distance := 0.0
		if not box.has_point(from):
			var hit = box.intersects_ray(from, direction)
			if hit == null:
				continue
			distance = from.distance_to(hit)
		if distance < best_distance:
			best_distance = distance
			best = id
	if best == "":
		return ""
	# Something solid in front of the box (a wall between the player and the prop) blocks it.
	var wall: Dictionary = play.lab.world.raycast(from, direction, best_distance)
	if wall.get("hit", false) and wall.distance < best_distance - 0.15:
		return ""
	return best


## {id, text} for the thing in view; text is "" when there's nothing to say.
func prompt_for(camera: Camera3D) -> Dictionary:
	var id := in_view(camera)
	return {id = id, text = prompt(id) if id != "" else ""}


## The prompt for a door or prop, from the state this peer knows.
func prompt(id: String) -> String:
	if play.is_door(id):
		var why := play.door_refusal(id)
		if why != "":
			return why
		return "[E] Close" if play.is_door_open(id) else "[E] Open"
	var object: Dictionary = play.lab.level.objects.get(id, {})
	var state := play.state_of(id)
	match str(object.get("use", "none")):
		"container":
			return "Empty" if state.used else "[E] Open"
		"note":
			return "[E] Read"
		"terminal":
			if object.get("needs_power", false) and play.power == "backup":
				return "No power"
			return "[E] Use terminal"
		"station_medkit":
			return "[E] Use medkit station (%d left)" % state.charges if state.charges > 0 else "Medkit station (empty)"
		"station_ammo":
			return "[E] Use ammo bench (%d left)" % state.charges if state.charges > 0 else "Ammo bench (empty)"
		"generator":
			if state.used or play.power == "restored":
				return "Running"
			return "[E] Start generator" if play.power == "backup" else "Generator (on standby)"
		"glass_case":
			return "" if state.used else "[E] Smash glass"
	return play.rules.prompt(id, object, state) # The newer uses (InteractRules).


## Why the local player can't use this right now, checked before asking the host (the host checks
## again), or "" to go ahead.
func local_refusal(id: String, player: Player) -> String:
	if play.is_door(id):
		return play.door_refusal(id)
	var object: Dictionary = play.lab.level.objects.get(id, {})
	var state := play.state_of(id)
	match str(object.get("use", "none")):
		"container":
			return "It's empty" if state.used else ""
		"terminal":
			return "No power" if object.get("needs_power", false) and play.power == "backup" else ""
		"station_medkit":
			if state.charges <= 0:
				return "It's empty"
			if player and player.health >= player.max_health:
				return "You're at full health"
		"station_ammo":
			return "It's empty" if state.charges <= 0 else ""
		"glass_case":
			return "It's already broken" if state.used else ""
	return play.rules.refusal(id, object, state)
