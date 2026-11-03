extends SceneTree
## Headless checks for the generated laboratory (scripts/tools/lab_builder.gd, docs/lab-design.md):
##   godot --headless --path . --script res://tests/laboratory_test.gd
## Builds the level into a scratch folder and checks the result without playing it: every door has
## its doorway and slot, props stand in air (none buried in a wall), floor markers stand on floors,
## and a walk over the voxels from the spawn (steps up to 4 voxels, any drop, ladders, crouching
## through vents, keycard doors opening only once their card has been walked to, story-locked doors
## opening at their event) reaches every floor's clone vat, every keycard, the generator and, after
## the finale, the elevator. With glass, plank and plastic patches passable too, it reaches every
## pickup and secret.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://laboratory_test_levels/"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const Builder := preload("res://scripts/tools/lab_builder.gd")
const HEADROOM := 12
const STEP := 4
const DROP := 24
const BREAKABLE := [M.GLASS, M.PLANK, M.PLASTIC, M.WOOD]
## Story-locked doors and what opens them: a prop (terminal used) or a room entered.
const UNLOCKS := {d_0_grow = {prop = "term_training"}, d_m2_airlock_in = {room = "airlock"}, d_m4_exit = {prop = "generator"}}
const ROUTE_VATS := ["vat_m1", "vat_m2", "vat_m3", "vat_m4"]
const SECRET_VATS := ["vat_m3b", "vat_m4b"]

var _failures := 0
var _level: LevelData
var _world: VoxelWorld
var _size: Vector3i
var _breakables_pass := false
var _doors := {}
var _reached := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	LevelData.save_dir_override = SCRATCH
	var builder = Builder.new()
	var started := Time.get_ticks_msec()
	var error: Error = builder.build(root)
	_check("builder saves the level", error == OK, error_string(error))
	_level = builder.level
	_world = builder.world
	_size = _world.get_size_in_voxels()
	print("laboratory_test: built %d objects in %.1f s" % [_level.objects.size(), (Time.get_ticks_msec() - started) / 1000.0])
	var reloaded = LevelData.load_level("laboratory")
	_check("the saved level loads back with every object", reloaded != null and reloaded.objects.size() == _level.objects.size())

	_check_doors()
	_check_props()
	_check_markers()

	_breakables_pass = false
	_walk()
	for id in ROUTE_VATS:
		_check("walk reaches %s" % id, _reached_marker(id), _where(id))
	for color in ["blue", "green", "red", "black"]:
		_check("walk reaches the %s keycard" % color, _reached_item("keycard_" + color))
	_check("walk reaches the generator", _reached_prop("generator"))
	_check("walk reaches the elevator after the finale", _reached_room("elevator"))
	for id in SECRET_VATS:
		_check("secret %s is NOT on the plain walk" % id, not _reached_marker(id))
	var route_cells := _reached.size()

	_breakables_pass = true
	_walk()
	for id in SECRET_VATS:
		_check("breaking glass and planks reaches %s" % id, _reached_marker(id), _where(id))
	var missing := []
	for object in _level.objects.values():
		if object.kind == "marker" and object.type == "item" and not _reached_cell(_cell_of(object.position)):
			missing.append("%s (%s)" % [object.id, object.item])
	_check("every pickup can be walked to", missing.is_empty(), ", ".join(missing))
	missing.clear()
	for object in _level.objects.values():
		if object.kind == "prop" and str(object.get("contents", "")) != "" and not _reached_near(LevelSchema.prop_box(object)):
			missing.append(object.id)
	_check("every container and case can be walked to", missing.is_empty(), ", ".join(missing))
	print("laboratory_test: %d floor cells on the route, %d with secrets" % [route_cells, _reached.size()])
	var unreached := []
	for object in _level.objects.values():
		if object.kind == "room" and not _reached_room(object.id):
			unreached.append(object.id)
	print("laboratory_test: rooms never walked into: %s" % ("none" if unreached.is_empty() else ", ".join(unreached)))

	_world.free()
	print("laboratory_test: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


# --- Objects --------------------------------------------------------------------------------------

func _check_doors() -> void:
	var doors := 0
	var bad := []
	for object in _level.objects.values():
		if not LevelSchema.is_door(object):
			continue
		doors += 1
		var linked := {}
		for other in _level.objects.values():
			if other.kind == "opening" and other.door == object.id:
				linked[other.type] = other
		if not linked.has("doorway") or not linked.has("slot"):
			bad.append(object.id)
			continue
		var box: AABB = LevelSchema.box_of(linked.doorway)
		if _solid_in(box, false) > 0:
			bad.append("%s (doorway not clear)" % object.id)
		_doors[object.id] = {box = box, key = str(object.get("door_key", "")), locked = bool(object.get("door_locked", false))}
	_check("every door has a clear doorway and a slot (%d doors)" % doors, bad.is_empty(), ", ".join(bad))


func _check_props() -> void:
	var buried := []
	var props := 0
	for object in _level.objects.values():
		if object.kind != "prop" or LevelSchema.is_door(object):
			continue
		props += 1
		var box: AABB = LevelSchema.prop_box(object)
		var solid := _solid_in(box, true)
		if solid > 0:
			buried.append("%s %s (%d voxels)" % [object.id, object.name, solid])
	_check("props stand in air (%d props)" % props, buried.is_empty(), ", ".join(buried.slice(0, 12)))


func _check_markers() -> void:
	var floating := []
	for object in _level.objects.values():
		if object.kind != "marker" or object.type not in ["spawn", "item", "clone_vat", "horde"]:
			continue
		if object.type == "horde" and object.get("on_ceiling", false):
			continue
		var cell := _cell_of(object.position)
		if _voxel(cell) != M.AIR or _voxel(cell + Vector3i.DOWN) == M.AIR:
			floating.append("%s at %s" % [object.id, cell])
	_check("floor markers stand on floors", floating.is_empty(), ", ".join(floating.slice(0, 12)))


# --- The walk ---------------------------------------------------------------------------------------

## Breadth-first over floor cells from the spawn, re-run as keys and events open doors.
func _walk() -> void:
	var spawn := _cell_of(_level.objects.values().filter(func(o) -> bool: return o.kind == "marker" and o.type == "spawn")[0].position)
	var open := {}
	for i in 8:
		_reached.clear()
		_flood(spawn, open)
		var changed := false
		for id in _doors:
			if open.has(id):
				continue
			var door: Dictionary = _doors[id]
			var opens := true
			if door.key != "" and not _reached_item("keycard_" + door.key):
				opens = false
			if door.locked:
				var rule: Dictionary = UNLOCKS.get(id, {})
				if rule.has("prop"):
					opens = opens and _reached_prop(rule.prop)
				elif rule.has("room"):
					opens = opens and _reached_room(rule.room)
				else:
					opens = false
			if opens:
				open[id] = true
				changed = true
		if not changed:
			break


func _flood(start: Vector3i, open: Dictionary) -> void:
	var queue: Array[Vector3i] = [start]
	_reached[_key(start)] = true
	var closed_doors: Array[AABB] = []
	for id in _doors:
		if not open.has(id):
			closed_doors.append(_doors[id].box)
	while not queue.is_empty():
		var cell: Vector3i = queue.pop_back()
		var on_ladder := _beside_ladder(cell)
		for direction: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var next := cell + direction
			var landed := Vector3i(next.x, -1, next.z)
			if _passable(next):
				# Open at this level: walk on, or fall until a floor (or hang on a ladder).
				var fell := 0
				var y := next.y
				while fell <= DROP and _passable(Vector3i(next.x, y - 1, next.z)):
					y -= 1
					fell += 1
				var candidate := Vector3i(next.x, y, next.z)
				if fell <= DROP and _walkable(candidate):
					landed = candidate
				elif _walkable_on_ladder(next):
					landed = next
			else:
				# A ledge: step up to STEP voxels, with room above the current cell to do it.
				for dy in range(1, STEP + 1):
					var candidate := next + Vector3i(0, dy, 0)
					if _air_column(cell + Vector3i(0, 1, 0), dy + HEADROOM - 1) and _walkable(candidate):
						landed = candidate
						break
			if landed.y >= 0 and not _reached.has(_key(landed)) and not _in_closed_door(landed, closed_doors):
				_reached[_key(landed)] = true
				queue.append(landed)
		# Ladders: climb up or down one voxel beside a ladder strip.
		if on_ladder:
			for dy in [1, -1]:
				var rung := cell + Vector3i(0, dy, 0)
				if _passable(rung) and _beside_ladder(rung) and not _reached.has(_key(rung)):
					_reached[_key(rung)] = true
					queue.append(rung)


func _walkable(cell: Vector3i) -> bool:
	if not _passable(cell):
		return false
	var below := _voxel(cell + Vector3i.DOWN)
	if below == M.AIR or below == M.LADDER:
		return false
	return _air_column(cell + Vector3i(0, 1, 0), HEADROOM - 1)


## A cell with no floor that a ladder runs past: the player hangs on the ladder there.
func _walkable_on_ladder(cell: Vector3i) -> bool:
	return _passable(cell) and _beside_ladder(cell) and _air_column(cell + Vector3i(0, 1, 0), HEADROOM - 1)


func _passable(cell: Vector3i) -> bool:
	if cell.y < 0 or cell.y >= _size.y or cell.x < 0 or cell.z < 0 or cell.x >= _size.x or cell.z >= _size.z:
		return false
	var m := _voxel(cell)
	return m == M.AIR or (_breakables_pass and m in BREAKABLE)


func _air_column(from: Vector3i, count: int) -> bool:
	for y in count:
		if not _passable(from + Vector3i(0, y, 0)):
			return false
	return true


func _beside_ladder(cell: Vector3i) -> bool:
	for direction: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		for y in range(0, 12):
			if _voxel(cell + direction + Vector3i(0, y, 0)) == M.LADDER:
				return true
	return false


func _in_closed_door(cell: Vector3i, doors: Array[AABB]) -> bool:
	for box in doors:
		if box.has_point(Vector3(cell) + Vector3(0.5, 0.5, 0.5)):
			return true
	return false


# --- Lookups ----------------------------------------------------------------------------------------

func _voxel(cell: Vector3i) -> int:
	return _world.get_voxel(cell)


func _key(cell: Vector3i) -> int:
	return cell.x | (cell.z << 10) | (cell.y << 20)


func _cell_of(position: Vector3) -> Vector3i:
	return Vector3i(position.floor())


func _reached_cell(cell: Vector3i) -> bool:
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for dy in range(-1, 2):
				if _reached.has(_key(cell + Vector3i(dx, dy, dz))):
					return true
	return false


func _reached_near(box: AABB) -> bool:
	var from := Vector3i(box.position) - Vector3i(2, 1, 2)
	var to := Vector3i(box.end) + Vector3i(2, 1, 2)
	for x in range(from.x, to.x):
		for z in range(from.z, to.z):
			for y in range(from.y, to.y):
				if _reached.has(_key(Vector3i(x, y, z))):
					return true
	return false


func _reached_marker(id: String) -> bool:
	var object: Dictionary = _level.objects.get(id, {})
	return not object.is_empty() and _reached_cell(_cell_of(object.position))


func _reached_item(item: String) -> bool:
	for object in _level.objects.values():
		if object.kind == "marker" and object.type == "item" and object.item == item and _reached_cell(_cell_of(object.position)):
			return true
	return false


func _reached_prop(id: String) -> bool:
	var object: Dictionary = _level.objects.get(id, {})
	return not object.is_empty() and _reached_near(LevelSchema.prop_box(object))


func _reached_room(id: String) -> bool:
	var room: Dictionary = _level.objects.get(id, {})
	if room.is_empty():
		return false
	var from: Vector3i = room.from
	var to: Vector3i = room.to
	for x in range(from.x, to.x, 2):
		for z in range(from.z, to.z, 2):
			for y in range(from.y, from.y + 6):
				if _reached.has(_key(Vector3i(x, y, z))):
					return true
	return false


func _where(id: String) -> String:
	var object: Dictionary = _level.objects.get(id, {})
	return "" if object.is_empty() else str(object.get("position", object.get("origin", "")))


## Solid voxels inside a box; with soft_only, breakable patches don't count.
func _solid_in(box: AABB, soft_only: bool) -> int:
	var count := 0
	var from := Vector3i(box.position)
	var to := Vector3i(box.end)
	for x in range(from.x, to.x):
		for y in range(from.y, to.y):
			for z in range(from.z, to.z):
				var m := _voxel(Vector3i(x, y, z))
				if m != M.AIR and not (soft_only and m in BREAKABLE):
					count += 1
	return count


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok   %s" % name)
	else:
		_failures += 1
		print("  FAIL %s%s" % [name, "" if detail == "" else ": " + detail])
