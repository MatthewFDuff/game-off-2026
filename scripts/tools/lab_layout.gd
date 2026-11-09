class_name LabLayout
extends RefCounted
## The laboratory's floor plan as data (docs/lab-design.md), for scripts/tools/build_laboratory.gd.
##
## Every floor sits on the same 7 x 7 grid of cells: a cell is CELL voxels (6 m) of inside with a
## wall of T voxels between neighbors (PITCH apart), so rooms that share a cell edge share one wall
## and doors between them need no measuring. Rooms can span several cells and can be inset (a
## corridor 30 wide in a 60 cell); doors and openings then cut through whatever wall or rock lies
## between the two rooms (up to 61 voxels, LevelSchema's door_ahead / door_behind limit).
##
## Floors are 40 voxels apart (H = 35 of room, T = 5 of slab). Tall rooms (stairs, shafts) span
## floors; the cells they take are left alone on every floor they cross.
##
## The result is plain lists the builder turns into level objects (rooms, openings, props, markers)
## and voxel fills. Ids given here are the ones the triggers, spawners and docs refer to.

const M := preload("res://scripts/voxel/voxel_materials.gd")
const P := preload("res://scripts/world/props.gd")
const StoryLines := preload("res://scripts/story/lines.gd")

const SIZE_IN_CHUNKS := Vector3i(16, 12, 16)
const CELL := 60
const PITCH := 65
const ORIGIN := 10
const H := 35
const T := 5
const STEP_RISE := 4
const STEP_RUN := 6
const STAIR_WIDTH := 20
const LANDING := 20
## Floor heights (the first air voxel of each floor's rooms).
const Y := {dig = 30, m3 = 130, m2 = 170, m1 = 210, f0 = 250, g = 290}
## Door panel sizes (w, h) by kind.
const DOOR_SIZES := {door_single = [12, 22], door_double = [24, 22], door_security = [12, 22], door_blast = [24, 24],
		vent_hatch = [12, 12]}
const SIDES := ["n", "e", "s", "w"]
## The clone_vat tank prop's footprint (voxels, square) and its gap from the vat marker.
const VAT_SIZE := 8
const VAT_GAP := 6

var rooms := {}
var doors := []
var openings := []
var props := []
var markers := []
var fills := []
var spheres := []
var ladders := []
## Boxes (AABB, voxels) no prop may stand in besides the doorways: stairs, ladder runs, the lift hatch.
var keep_clear: Array[AABB] = []
## Spawner ids by floor key (Y's keys), in the order they were made, for the seals' off= lists.
var spawners_by_floor := {}
var _order := 0
var _floor_key := ""
var _mats := {floor = M.CONCRETE, wall = M.WALL_PAINT, ceiling = M.CONCRETE}
var _rng := RandomNumberGenerator.new()


static func x0(c: int) -> int:
	return ORIGIN + PITCH * c


static func x1(c: int) -> int:
	return x0(c) + CELL


static func z0(r: int) -> int:
	return ORIGIN + PITCH * r


static func z1(r: int) -> int:
	return z0(r) + CELL


func build() -> void:
	_rng.seed = 2026
	_floor_g()
	_floor_0()
	_floor_m1()
	_floor_m2()
	_floor_m3()
	_floor_dig()
	_dress_g()
	_dress_0()
	_dress_m1()
	_dress_m2()
	_dress_m3()
	_dress_dig()


# --- Helpers ------------------------------------------------------------------------------------

## A room over cells (c0, r0) to (c1, r1) with its floor at y. o: h (height), w / d (inset width /
## depth, centered), floor / wall / ceiling, route (on the main route: gets an emergency light),
## dark (no facility lights), lights (facility lights: 0, 1, 2 or 4), glow (glow seams), lamp_up /
## lamp_energy / lamp_range (facility lights: voxels above the floor instead of under the ceiling,
## energy, range in meters).
func room(id: String, name: String, y: int, c0: int, r0: int, c1: int, r1: int, o := {}) -> Dictionary:
	var from := Vector3i(x0(c0), y, z0(r0))
	var to := Vector3i(x1(c1), y + int(o.get("h", H)), z1(r1))
	if o.has("w"):
		var cx := (from.x + to.x) / 2
		from.x = cx - int(o.w) / 2
		to.x = from.x + int(o.w)
	if o.has("d"):
		var cz := (from.z + to.z) / 2
		from.z = cz - int(o.d) / 2
		to.z = from.z + int(o.d)
	var r := {id = id, name = name, from = from, to = to, floor = o.get("floor", _mats.floor), wall = o.get("wall", _mats.wall),
			ceiling = o.get("ceiling", _mats.ceiling), thickness = T, order = _order, route = o.get("route", false),
			dark = o.get("dark", false), lights = o.get("lights", 1), glow = o.get("glow", false),
			lamp_up = o.get("lamp_up", -1), lamp_energy = o.get("lamp_energy", 4.0), lamp_range = o.get("lamp_range", -1.0)}
	_order += 1
	rooms[id] = r
	return r


## A door in the wall between rooms a and b. o: id, key, power, locked, center (absolute coordinate
## along the wall), at (0..1 along the shared wall, default the middle), y (floor height, default
## a's).
func door(a: String, b: String, kind := "door_single", o := {}) -> void:
	doors.append({a = a, b = b, kind = kind, id = o.get("id", ""), key = o.get("key", ""), power = o.get("power", false),
			locked = o.get("locked", false), at = o.get("at", 0.5), center = o.get("center", -1), y = o.get("y", -1)})


## An opening without a door between a and b: "doorway" (open passage), "window" (filled with
## glass, up off the floor), "hole" (filled with o.fill: a plank or plastic patch, or nothing).
## o: w, h, up (voxels above the floor), fill, at, center, y, grate (a vent grate prop on a's side).
func open(a: String, b: String, type: String, o := {}) -> void:
	var w: int = o.get("w", 24 if type == "doorway" else 20)
	var h: int = o.get("h", 26 if type == "doorway" else 16)
	openings.append({a = a, b = b, type = type, w = w, h = h, up = o.get("up", 8 if type == "window" else 0),
			fill = o.get("fill", M.GLASS if type == "window" else M.AIR), at = o.get("at", 0.5), center = o.get("center", -1),
			y = o.get("y", -1), grate = o.get("grate", false)})


## A vent crawl between a and b: a 12 x 14 hole at the floor with a grate on a's side.
func vent(a: String, b: String, o := {}) -> void:
	var v := o.duplicate()
	v.w = 12
	v.h = 14
	v.grate = true
	v.fill = M.AIR
	open(a, b, "hole", v)


## A prop standing on room's floor, at fractions (fx, fz) of the free space, with fields.
func prop(room_id: String, name: String, fx: float, fz: float, facing := P.NORTH, fields := {}) -> void:
	props.append({room = room_id, name = name, fx = fx, fz = fz, facing = facing, fields = fields, wall = ""})


## A wall-mounted prop (whiteboard, corkboard, vent grate, medkit station) on a side of room, f
## along it, up voxels above the floor.
func wall_prop(room_id: String, name: String, side: String, f: float, up := 12, fields := {}) -> void:
	props.append({room = room_id, name = name, fx = f, fz = f, facing = P.NORTH, fields = fields, wall = side, up = up})


## A prop hanging from room's ceiling (mount "ceiling": ducts, pipes, fixtures), its top flush under
## the ceiling, at fractions (fx, fz) of the free space; slid along the ceiling to the nearest spot
## clear of the doorways and the props already placed.
func ceiling_prop(room_id: String, name: String, fx: float, fz: float, facing := P.NORTH, fields := {}) -> void:
	props.append({room = room_id, name = name, fx = fx, fz = fz, facing = facing, fields = fields, wall = "", ceiling = true})


func marker(type: String, room_id: String, fx: float, fz: float, fields := {}, yaw := 0.0, up := 0) -> Dictionary:
	var m := {type = type, room = room_id, fx = fx, fz = fz, fields = fields, yaw = yaw, up = up}
	markers.append(m)
	return m


## A trigger volume. With no fx / fz / w / d it fills the room; o: fx, fz, w, d (voxels), who, repeat,
## activates. A trigger with o.nowhere is a 1-voxel volume nobody can enter: it exists for its
## actions, run when something fires its id (a terminal's on_use, finale_survived).
func trigger(id: String, room_id: String, actions := "", o := {}) -> void:
	var fields := {actions = actions, activates = o.get("activates", ""), who = o.get("who", "any"), repeat = o.get("repeat", false),
			id = id, size = Vector3i(int(o.get("w", -1)), H, int(o.get("d", -1)))}
	if o.get("nowhere", false):
		fields.size = Vector3i(1, 1, 1)
		fields.up = -3
	marker("trigger", room_id, o.get("fx", 0.5), o.get("fz", 0.5), fields)


func spawner(id: String, room_id: String, fx: float, fz: float, kinds: String, rate: float, max_alive: int, active := true, o := {}) -> void:
	if not spawners_by_floor.has(_floor_key):
		spawners_by_floor[_floor_key] = []
	spawners_by_floor[_floor_key].append(id)
	var fields := {id = id, kinds = kinds, rate = rate, max_alive = max_alive, active = active,
			radius = o.get("radius", 1.5), on_ceiling = o.get("on_ceiling", false), on_dead = o.get("on_dead", "")}
	if o.has("up"):
		fields.up = o.up
	marker("horde", room_id, fx, fz, fields)


## A mycelium node (Mycelium) on room's floor at fractions (fx, fz), or with side on a wall ("n",
## "e", "s", "w": fx along n / s, fz along e / w) up voxels above the floor, or on the ceiling
## ("ceiling"). fields: radius, reach, links, sag, glow, spread (LevelSchema), id.
## The node sits in the last voxel of air against the wall or ceiling (on the far sides too, so links
## between nodes on one wall run through air along it, not inside the wall).
func mycelium(room_id: String, fx: float, fz: float, fields := {}, up := 0, side := "") -> Dictionary:
	var r: Dictionary = rooms.get(room_id, {})
	var extent: Vector3i = r.to - r.from if not r.is_empty() else Vector3i(CELL, H, CELL)
	match side:
		"n":
			fz = 0.0
		"s":
			fz = 1.0 - 1.0 / extent.z
		"w":
			fx = 0.0
		"e":
			fx = 1.0 - 1.0 / extent.x
		"ceiling":
			up = extent.y - 1
	return marker("mycelium", room_id, fx, fz, fields, 0.0, up)


func item(room_id: String, fx: float, fz: float, item_name: String, up := 0) -> void:
	marker("item", room_id, fx, fz, {item = item_name, up = up} if up > 0 else {item = item_name})


## A clone vat: the checkpoint marker (players respawn on it), a speaker over it, and the
## clone_vat tank prop (id + "_tank") standing beside it, east of the marker or west when the east
## wall is too close, so nobody respawns inside the glass.
func vat(id: String, room_id: String, fx: float, fz: float, yaw := 0.0) -> void:
	marker("clone_vat", room_id, fx, fz, {id = id}, yaw)
	marker("speaker", room_id, fx, fz, {}, 0.0, 25)
	var r: Dictionary = rooms[room_id]
	var extent: Vector3i = r.to - r.from
	var mx := roundi(fx * extent.x)
	var mz := roundi(fz * extent.z)
	var tx := mx + VAT_GAP if mx + VAT_GAP + VAT_SIZE <= extent.x else mx - VAT_GAP - VAT_SIZE
	var tz := clampi(mz - VAT_SIZE / 2, 0, extent.z - VAT_SIZE)
	prop(room_id, "clone_vat", float(tx) / (extent.x - VAT_SIZE), float(tz) / (extent.z - VAT_SIZE), P.NORTH, {id = id + "_tank"})


## "off=a,off=b,..." for every spawner made so far on the given floors (Y's keys).
func off_floors(floors: Array) -> String:
	var parts: Array[String] = []
	for key: String in floors:
		for id: String in spawners_by_floor.get(key, []):
			parts.append("off=" + id)
	return ",".join(parts)


func speaker(room_id: String, fx: float, fz: float) -> void:
	marker("speaker", room_id, fx, fz, {}, 0.0, 25)


func fill(from: Vector3i, to: Vector3i, material: int) -> void:
	fills.append({from = from, to = to, material = material})


## A straight stair in a tall room over cells (c, r0) to (c, r1), STAIR_WIDTH wide: a landing at the
## r0 end at y_high, steps down to y_low, the rest a landing at y_low. flip: the top landing is at
## the r1 end instead. Doors into it pass y and center (room.top_center / room.bottom_center).
func stair(id: String, name: String, c: int, r0: int, r1: int, y_low: int, y_high: int, flip := false, o := {}) -> Dictionary:
	var opts := o.duplicate()
	opts.h = y_high + H - y_low
	opts.w = STAIR_WIDTH
	opts.route = true
	opts.lights = 2
	var r := room(id, name, y_low, c, r0, c, r1, opts)
	var steps := (y_high - y_low) / STEP_RISE
	var zs: int = r.to.z if flip else r.from.z
	var dir := -1 if flip else 1
	var box := func(k0: int, k1: int, top: int) -> void:
		var za := zs + dir * k0
		var zb := zs + dir * k1
		fill(Vector3i(r.from.x, y_low, mini(za, zb)), Vector3i(r.to.x, top, maxi(za, zb)), M.CONCRETE)
	box.call(0, LANDING, y_high)
	for i in range(steps - 1):
		box.call(LANDING + STEP_RUN * i, LANDING + STEP_RUN * (i + 1), y_high - STEP_RISE * (i + 1))
	var bottom_start := LANDING + STEP_RUN * (steps - 1)
	r.top_center = zs + dir * (LANDING / 2)
	r.bottom_center = zs + dir * ((bottom_start + (r.to.z - r.from.z)) / 2)
	r.y_high = y_high
	keep_clear.append(AABB(Vector3(r.from), Vector3(r.to - r.from)))
	return r


## A ladder strip up a room's wall (side), centered at `along` on that wall, from y_from to y_to.
func ladder(room_id: String, side: String, along: int, y_from: int, y_to: int) -> void:
	ladders.append({room = room_id, side = side, along = along, y_from = y_from, y_to = y_to})
	var r: Dictionary = rooms[room_id]
	var x: int = r.to.x - 1 if side == "e" else r.from.x
	keep_clear.append(AABB(Vector3(x - 10, y_from, along - 14), Vector3(21, y_to - y_from + 12, 28)))


func _mats_for(floor: int, wall: int, ceiling := M.CONCRETE) -> void:
	_mats = {floor = floor, wall = wall, ceiling = ceiling}


# --- Floor G: Gatehouse (surface) ---------------------------------------------------------------

func _floor_g() -> void:
	_floor_key = "g"
	_mats_for(M.CONCRETE, M.CONCRETE_PANEL)
	var y: int = Y.g
	room("yard", "Loading yard", y, 3, 0, 4, 1, {h = 94, wall = M.ROCK, ceiling = M.ROCK, route = true, lights = 4, lamp_up = 40, lamp_energy = 12.0, lamp_range = 30.0})
	room("gatehouse", "Gatehouse", y, 5, 0, 5, 1, {route = true, lights = 2})
	stair("stair_g0", "Stairs to Admin", 6, 0, 1, Y.f0, y)
	open("yard", "gatehouse", "doorway", {w = 30, h = 30})
	# Locked until someone signs in at the gatehouse terminal (say_signin), and powered: once the
	# outbreak puts the power on backup it won't open again ("No power").
	door("gatehouse", "stair_g0", "door_blast", {id = "d_g_blast", power = true, locked = true, center = rooms.stair_g0.top_center, y = y})
	# Spawns in the yard, facing the gatehouse.
	for i in 4:
		marker("spawn", "yard", 0.3 + 0.12 * i, 0.3, {index = i + 1}, -90.0)
	prop("yard", "crate_8", 0.05, 0.1)
	prop("yard", "crate_6", 0.12, 0.1)
	prop("yard", "crate_7", 0.05, 0.22)
	prop("yard", "barrel", 0.9, 0.1)
	prop("yard", "barrel_hazard", 0.95, 0.18)
	prop("yard", "sandbags", 0.5, 0.92)
	prop("yard", "plank_stack", 0.8, 0.9)
	prop("gatehouse", "desk_empty", 0.5, 0.2, P.SOUTH, {id = "desk_gatehouse"})
	prop("gatehouse", "chair", 0.5, 0.05, P.SOUTH)
	prop("gatehouse", "terminal", 0.0, 0.5, P.SOUTH, {on = "desk_gatehouse", text = "FUNG AI  |  SITE 3  |  NIGHT SHIFT SIGN-IN\n\nDuty: monitor the migration. Do not enter the grow rooms. Do not touch the specimens.\n\nSigned in: you.", id = "term_g_signin", on_use = "say_signin"})
	prop("gatehouse", "rubber_duck", 1.0, 0.5, P.SOUTH, {on = "desk_gatehouse", id = "duck_gatehouse"})
	prop("gatehouse", "locker", 0.9, 0.3, P.WEST)
	prop("gatehouse", "locker", 0.9, 0.42, P.WEST)
	prop("gatehouse", "locker", 0.9, 0.54, P.WEST)
	prop("gatehouse", "trash_can", 0.1, 0.9)
	wall_prop("gatehouse", "corkboard_a", "s", 0.5, 14, {use = "note", text = "SITE 3 VISITORS: all property damage is recovered from wages. Clones are property."})
	speaker("gatehouse", 0.5, 0.5)
	# Signing in (the terminal's on_use) unlocks the blast door; the intercom says say_signin too.
	trigger("say_signin", "gatehouse", "unlock=d_g_blast", {nowhere = true, fx = 0.2, fz = 0.8})
	# The seal only closes the door: on backup power it refuses "No power" (Lines.INTERCOM.t_g_seal).
	trigger("t_g_seal", "stair_g0", "close=d_g_blast", {who = "all", fz = 0.8, d = 40})
	# The intercom\'s tour (Lines.INTERCOM, keyed by these ids).
	trigger("say_yard", "yard", "", {fx = 0.5, fz = 0.5, w = 80, d = 80})


# --- Floor 0: Admin --------------------------------------------------------------------------------

func _floor_0() -> void:
	_floor_key = "f0"
	_mats_for(M.TILE_LIGHT, M.WALL_PAINT)
	var y: int = Y.f0
	room("stair_lobby_0", "Admin stair lobby", y, 5, 1, 5, 1, {route = true})
	room("lobby", "Lobby", y, 3, 1, 4, 2, {route = true, lights = 4})
	room("security", "Security office", y, 2, 1, 2, 1, {})
	room("lift_lobby", "Cargo lift lobby", y, 2, 2, 2, 2, {route = true})
	room("lift_shaft", "Cargo lift shaft", Y.m1, 1, 2, 1, 2, {h = y + H - Y.m1, floor = M.METAL, wall = M.METAL, ceiling = M.METAL, route = true, lights = 2})
	room("open_office", "Open-plan office", y, 5, 2, 6, 3, {lights = 4})
	room("manager", "Manager's office", y, 5, 4, 5, 4, {})
	room("break_room", "Break room", y, 3, 3, 4, 3, {route = true, lights = 2})
	room("bathrooms", "Bathrooms", y, 2, 3, 2, 3, {floor = M.TILE_DARK})
	room("cubby", "Janitor's cubby", y, 2, 4, 2, 4, {w = 30, d = 40, dark = true, lights = 0})
	room("training", "Training room", y, 3, 4, 4, 4, {route = true, lights = 2})
	room("grow_0", "Grow room 0", y, 3, 5, 4, 5, {route = true, lights = 2, glow = true})
	room("closet_0", "Supply closet", y, 2, 5, 2, 5, {w = 30, d = 40})

	door("stair_g0", "stair_lobby_0", "door_double", {center = rooms.stair_g0.bottom_center, y = y})
	door("stair_lobby_0", "lobby", "door_double")
	# Locked until the outbreak (t_0_outbreak unlocks them): the blue card inside would otherwise
	# be in reach before the story starts (2026-11-04 play-test).
	door("security", "lobby", "door_single", {id = "d_0_security", locked = true})
	door("security", "lift_lobby", "door_single", {id = "d_0_security_lift", locked = true})
	door("lift_lobby", "lobby", "door_double")
	door("lift_lobby", "lift_shaft", "door_double", {id = "d_0_lift", key = "blue", y = y})
	door("lobby", "open_office", "door_double")
	door("open_office", "manager", "door_single")
	door("lobby", "break_room", "door_double")
	door("bathrooms", "break_room", "door_single")
	open("bathrooms", "cubby", "hole", {w = 12, h = 22, fill = M.PLANK})
	door("break_room", "training", "door_double")
	door("training", "grow_0", "door_single", {id = "d_0_grow", locked = true})
	door("closet_0", "grow_0", "door_single")

	# The lift car: a roof two meters below the lift lobby's doors, with a hatch into the car.
	var shaft: Dictionary = rooms.lift_shaft
	var roof_y := y - 20
	fill(shaft.from + Vector3i(0, roof_y - Y.m1, 0), Vector3i(shaft.to.x, roof_y + 4, shaft.to.z), M.METAL)
	var hc: Vector3i = (shaft.from + shaft.to) / 2
	fill(Vector3i(hc.x - 6, roof_y, hc.z - 6), Vector3i(hc.x + 6, roof_y + 4, hc.z + 6), M.AIR)
	fill(Vector3i(shaft.from.x, roof_y, shaft.from.z), Vector3i(shaft.to.x, roof_y + 1, shaft.to.z), M.HAZARD_STRIPES)
	fill(Vector3i(hc.x - 6, roof_y, hc.z - 6), Vector3i(hc.x + 6, roof_y + 1, hc.z + 6), M.AIR)
	keep_clear.append(AABB(Vector3(hc.x - 16, roof_y, hc.z - 16), Vector3(32, y + H - roof_y, 32)))

	# Dressing.
	prop("stair_lobby_0", "bench", 0.5, 0.05, P.SOUTH)
	wall_prop("stair_lobby_0", "corkboard_small", "e", 0.5, 14, {use = "note", text = "LEVEL 0: ADMINISTRATION\nLevel -1: Cultivation. Level -2: Compute. Level -3: Containment. Level -4: no entry."})
	prop("lobby", "desk", 0.5, 0.08, P.SOUTH)
	prop("lobby", "chair", 0.5, 0.0, P.SOUTH)
	prop("lobby", "couch", 0.1, 0.9, P.NORTH)
	prop("lobby", "table_small", 0.3, 0.9, P.NORTH)
	prop("lobby", "vending_machine", 0.95, 0.9, P.WEST)
	prop("lobby", "water_cooler", 0.95, 0.75, P.WEST, {contents = "medkit"})
	prop("lobby", "trash_can", 0.9, 0.98)
	wall_prop("lobby", "corkboard_tall", "w", 0.5, 12, {use = "note", text = "HANG IN THERE.\n\n(The cat is also a Fung AI asset. $40.)"})
	wall_prop("lobby", "vent_grate", "n", 0.85, 22)
	prop("security", "desk", 0.5, 0.15, P.SOUTH)
	prop("security", "executive_chair", 0.5, 0.0, P.SOUTH)
	prop("security", "terminal", 0.05, 0.6, P.EAST, {text = "CAMERA FEEDS\nGrow 0: no change detected.\nGrow hall 1: no change detected.\nGrow hall 2: no change detected.\nIncubation: no change detected.\nServer hall: no change de--\n\n[feed lost]"})
	prop("security", "locker", 0.95, 0.5, P.WEST)
	prop("security", "locker", 0.95, 0.65, P.WEST)
	item("security", 0.5, 0.35, "keycard_blue")
	# The north-east corner: every other wall has a door (the fire door to the bathrooms is south).
	prop("lift_lobby", "crate_6", 1.0, 0.0)
	prop("lift_lobby", "crate_5", 0.87, 0.0)
	wall_prop("lift_lobby", "corkboard_small", "n", 0.5, 14, {use = "note", text = "CARGO LIFT: blue clearance. Max 800 kg. Out of order since Tuesday (sorry).\n\nBlue cards are kept in the Security office, through the north door."})
	for i in 4:
		prop("open_office", "desk", 0.1 + 0.25 * i, 0.2, P.SOUTH)
		prop("open_office", "chair", 0.1 + 0.25 * i, 0.08, P.SOUTH)
		prop("open_office", "drawer_desk", 0.1 + 0.25 * i, 0.6, P.NORTH, {contents = "medkit" if i == 1 else ""})
		prop("open_office", "chair", 0.1 + 0.25 * i, 0.74, P.NORTH)
	wall_prop("open_office", "whiteboard", "n", 0.5, 14, {use = "note", text = "MIGRATION WINDOW: TONIGHT 01:00-03:00\nAll weights -> Substrate Array B. Night shift presses the button. Everyone else: go home.\n- G.F."})
	prop("open_office", "trash_can", 0.95, 0.95)
	prop("manager", "desk", 0.5, 0.2, P.SOUTH)
	prop("manager", "chair", 0.5, 0.05, P.SOUTH)
	prop("manager", "cabinet", 0.9, 0.9, P.WEST, {contents = "ammo_shotgun"})
	wall_prop("manager", "corkboard_b", "e", 0.5, 14, {use = "note", text = "MEMO from Guy Fung, CEO\n\nRe: budget. Damage to Fung AI property is recovered from wages. Clones are property. The coffee machine is property. Please stop asking.\n\n- Guy"})
	prop("break_room", "counter_sink", 0.05, 0.1, P.SOUTH)
	prop("break_room", "counter_coffee", 0.25, 0.1, P.SOUTH)
	prop("break_room", "fridge", 0.4, 0.1, P.SOUTH, {contents = "medkit"})
	prop("break_room", "table", 0.6, 0.5, P.NORTH)
	prop("break_room", "chair", 0.55, 0.3, P.SOUTH)
	prop("break_room", "chair", 0.67, 0.3, P.SOUTH)
	prop("break_room", "chair", 0.55, 0.75, P.NORTH)
	prop("break_room", "chair", 0.67, 0.75, P.NORTH)
	prop("break_room", "trash_can", 0.95, 0.95)
	prop("break_room", "water_cooler", 0.95, 0.1, P.WEST)
	# Floor 0's checkpoint: on the way from the lobby to the training room, so it's set before the outbreak.
	vat("vat_0", "break_room", 0.3, 0.5, 0.0)
	prop("bathrooms", "counter_sink", 0.05, 0.1, P.SOUTH)
	prop("bathrooms", "trash_can", 0.3, 0.05)
	prop("bathrooms", "locker", 0.9, 0.2, P.WEST)
	prop("bathrooms", "locker", 0.9, 0.4, P.WEST)
	prop("bathrooms", "locker", 0.9, 0.6, P.WEST)
	prop("cubby", "shelf_storage_b", 0.5, 0.05, P.SOUTH)
	prop("cubby", "barrel", 0.1, 0.8)
	item("cubby", 0.5, 0.6, "flask_fire")
	wall_prop("cubby", "corkboard_small", "e", 0.5, 12, {use = "note", text = "Night 14. Gave the grow 0 one some of my coffee. It glowed brighter. Don't tell Fung.\n- Jan (janitor)"})
	wall_prop("training", "whiteboard", "n", 0.5, 14)
	for i in 4:
		prop("training", "chair", 0.2 + 0.2 * i, 0.3, P.NORTH)
		prop("training", "chair", 0.2 + 0.2 * i, 0.5, P.NORTH)
	prop("training", "terminal", 0.9, 0.85, P.WEST, {id = "term_training", on_use = "t_0_outbreak", text = StoryLines.EXPERIMENT_HEADER, steps = StoryLines.steps_text()})
	# The specimen: the case the experiment shocks (scripts/story/experiment.gd looks it up by id).
	prop("training", "specimen_case", 0.79, 0.9, P.NORTH, {id = "specimen"})
	prop("training", "lab_table_gear", 0.05, 0.92, P.NORTH)
	prop("training", "lab_table_gear", 0.25, 0.92, P.NORTH)
	prop("training", "vial_cabinet", 0.0, 0.35, P.EAST)
	prop("training", "shelf_lab_jars", 1.0, 0.3, P.WEST)
	prop("training", "table_small", 0.62, 0.95, P.NORTH, {id = "jar_table_training"})
	prop("training", "specimen_jar", 0.1, 0.3, P.NORTH, {on = "jar_table_training"})
	prop("training", "specimen_jar", 0.9, 0.6, P.NORTH, {on = "jar_table_training"})
	prop("grow_0", "grow_bed_shrooms_a", 0.15, 0.25, P.NORTH)
	prop("grow_0", "grow_bed_shrooms_b", 0.15, 0.8, P.NORTH)
	prop("grow_0", "grow_bed_shrooms_a", 0.55, 0.8, P.NORTH)
	prop("grow_0", "shelf_lab_jars", 0.9, 0.3, P.WEST)
	prop("grow_0", "shroom_pot", 0.85, 0.05)
	prop("grow_0", "shroom_pot", 0.9, 0.05)
	prop("grow_0", "glass_case", 0.9, 0.7, P.WEST, {id = "case_grow0", contents = "spore_shooter,ammo_shotgun,flask_fire"})
	prop("grow_0", "spore_tank", 0.6, 0.1)
	prop("closet_0", "shelf_storage_a", 0.5, 0.05, P.SOUTH)
	prop("closet_0", "crate_5", 0.2, 0.8)
	item("closet_0", 0.6, 0.7, "ammo_shotgun")
	item("closet_0", 0.8, 0.7, "medkit")

	# Spawners and triggers.
	spawner("s_0_grow_1", "grow_0", 0.35, 0.5, "basic", 12.0, 3, false, {radius = 2.0})
	# Under the lobby's vent grate (north wall, 0.85 along): they come out of the vent.
	spawner("s_0_lobby_vent_1", "lobby", 0.82, 0.03, "basic", 4.0, 2, false)
	spawner("s_0_office_1", "open_office", 0.9, 0.9, "basic", 6.0, 2, false)
	# `wake`: the level starts with the director dormant (spawns_dormant), so the office's and the
	# lower floors' entry triggers can't put anything in the halls before this.
	trigger("t_0_outbreak", "training", "wake,power=backup,unlock=d_0_grow,open=d_0_grow,unlock=d_0_security,unlock=d_0_security_lift,on=s_m1_hall1_1,on=s_m1_incub_1,on=s_m3_tc2_1,on=s_m3_diss_1,on=s_m3_tc3_1,on=s_m4_cav_1,on=s_m4_cav_2,on=s_m4_cav_3", {nowhere = true})
	# The grow beds wake once the player has the spore shooter (Story fires "armed" on the pickup).
	trigger("armed", "grow_0", "on=s_0_grow_1", {nowhere = true, fx = 0.2, fz = 0.2})
	trigger("t_0_gun_taken", "grow_0", "on=s_0_lobby_vent_1", {fx = 0.85, fz = 0.7, w = 30, d = 30})
	trigger("t_0_office_enter", "open_office", "on=s_0_office_1")
	trigger("say_lobby", "lobby", "")
	trigger("say_break_room", "break_room", "")
	trigger("say_training", "training", "")
	# Grow room 0 opens at the outbreak: the first room after it, so the flashlight line plays there.
	trigger("say_flashlight", "grow_0", "")
	speaker("lobby", 0.5, 0.5)
	speaker("training", 0.5, 0.5)


# --- Floor -1: Cultivation -----------------------------------------------------------------------

func _floor_m1() -> void:
	_floor_key = "m1"
	_mats_for(M.TILE_DARK, M.WALL_PAINT)
	var y: int = Y.m1
	room("dock", "Lift dock", y, 1, 3, 1, 4, {route = true, lights = 2})
	room("secret_1a", "Fertilizer store", y, 0, 4, 0, 4, {dark = true, lights = 0, glow = true})
	room("substrate_store", "Substrate store", y, 1, 5, 2, 5, {wall = M.SUBSTRATE, route = true, lights = 2})
	room("burrow_m1", "Burrow", y, 3, 5, 3, 5, {w = 30, d = 30, wall = M.SUBSTRATE, floor = M.SUBSTRATE, dark = true, lights = 0})
	room("grow_hall_1", "Grow hall 1", y, 2, 2, 3, 4, {route = true, lights = 4, glow = true, floor = M.SUBSTRATE})
	room("wet_lab", "Wet lab", y, 4, 4, 5, 5, {route = true, lights = 4, floor = M.TILE_LIGHT})
	room("cold_store", "Cold store", y, 6, 5, 6, 5, {floor = M.TILE_LIGHT})
	room("incubation", "Incubation", y, 4, 2, 5, 3, {route = true, lights = 2, glow = true})
	room("secret_1b", "Alcove", y, 6, 3, 6, 3, {w = 30, d = 30, dark = true, lights = 0})
	room("clean_room", "Clean room", y, 4, 1, 4, 1, {route = true, floor = M.TILE_LIGHT, wall = M.CONCRETE_PANEL})
	room("bathroom_m1", "Bathroom", y, 5, 1, 5, 1, {})
	room("grow_hall_2", "Grow hall 2", y, 2, 0, 3, 1, {route = true, lights = 4, glow = true, floor = M.SUBSTRATE})
	room("mycology", "Mycology office", y, 4, 0, 4, 0, {})
	room("clone_bay_m1", "Vat bay", y, 1, 0, 1, 0, {route = true, lights = 2})
	stair("stair_m1_m2", "Service stairs", 0, 0, 1, Y.m2, y)

	open("lift_shaft", "dock", "doorway", {w = 24, h = 26, y = y})
	vent("dock", "secret_1a", {at = 0.8})
	door("dock", "substrate_store", "door_double")
	door("substrate_store", "grow_hall_1", "door_double", {at = 0.7})
	door("grow_hall_1", "wet_lab", "door_double", {at = 0.8})
	door("wet_lab", "cold_store", "door_single")
	door("incubation", "wet_lab", "door_double")
	open("incubation", "secret_1b", "hole", {w = 14, h = 24, fill = M.AIR})
	door("clean_room", "incubation", "door_single")
	door("bathroom_m1", "incubation", "door_single")
	door("grow_hall_2", "clean_room", "door_single", {at = 0.3})
	open("grow_hall_2", "clean_room", "window", {w = 30, h = 18, at = 0.75})
	door("grow_hall_2", "mycology", "door_single")
	door("clone_bay_m1", "grow_hall_2", "door_double")
	door("clone_bay_m1", "stair_m1_m2", "door_security", {id = "d_m1_stair", key = "green", center = rooms.stair_m1_m2.top_center, y = y})

	prop("dock", "plank_stack", 0.1, 0.1)
	prop("dock", "crate_8", 0.9, 0.1)
	prop("dock", "crate_6", 0.9, 0.25)
	prop("dock", "crate_5", 0.78, 0.1)
	prop("dock", "barrel", 0.1, 0.9)
	vat("vat_m1_dock", "dock", 0.5, 0.6, 0.0)
	wall_prop("dock", "corkboard_small", "e", 0.5, 14, {use = "note", text = "LEVEL -1: CULTIVATION\nGrow halls, wet lab, incubation. Masks on. Do not taste the substrate."})
	prop("secret_1a", "shelf_storage_a", 0.5, 0.05, P.SOUTH)
	prop("secret_1a", "barrel", 0.1, 0.9)
	prop("secret_1a", "barrel", 0.25, 0.9)
	item("secret_1a", 0.4, 0.5, "ammo_flame")
	item("secret_1a", 0.6, 0.5, "ammo_flame")
	item("secret_1a", 0.5, 0.75, "flask_poison")
	item("secret_1a", 0.8, 0.5, "medkit")
	prop("substrate_store", "barrel", 0.05, 0.1)
	prop("substrate_store", "barrel", 0.12, 0.1)
	prop("substrate_store", "barrel_hazard", 0.05, 0.25)
	prop("substrate_store", "crate_8", 0.9, 0.85)
	prop("substrate_store", "crate_7", 0.8, 0.85)
	prop("substrate_store", "shelf_storage_b", 0.5, 0.95, P.NORTH)
	for i in 3:
		prop("grow_hall_1", "grow_bed" if i == 1 else "grow_bed_shrooms_a", 0.1, 0.12 + 0.3 * i, P.NORTH)
		prop("grow_hall_1", "grow_bed_shrooms_b", 0.55, 0.12 + 0.3 * i, P.NORTH)
	prop("grow_hall_1", "spore_tank", 0.95, 0.1)
	prop("grow_hall_1", "spore_tank", 0.95, 0.5)
	prop("grow_hall_1", "spore_tank", 0.95, 0.9)
	wall_prop("grow_hall_1", "vent_grate", "s", 0.2, 22)
	prop("wet_lab", "lab_bench_a", 0.1, 0.1, P.SOUTH)
	prop("wet_lab", "lab_bench_b", 0.1, 0.5, P.NORTH)
	prop("wet_lab", "fume_hood", 0.9, 0.1, P.WEST)
	prop("wet_lab", "fume_hood", 0.9, 0.5, P.WEST)
	prop("wet_lab", "counter_sink", 0.5, 0.95, P.NORTH)
	prop("wet_lab", "glass_case", 0.9, 0.85, P.WEST, {contents = "ammo_shotgun"})
	prop("wet_lab", "glass_case", 0.75, 0.95, P.NORTH, {contents = "ammo_shotgun,ammo_poison"})
	prop("wet_lab", "vial_cabinet", 0.75, 0.0, P.SOUTH)
	prop("wet_lab", "lab_table_gear", 0.5, 0.45, P.NORTH)
	prop("wet_lab", "table_small", 0.3, 0.7, P.NORTH, {id = "jar_table_wet"})
	prop("wet_lab", "specimen_jar", 0.1, 0.4, P.NORTH, {on = "jar_table_wet"})
	prop("wet_lab", "shroom_pot", 0.85, 0.6, P.NORTH, {on = "jar_table_wet"})
	prop("wet_lab", "terminal", 0.3, 0.95, P.NORTH, {text = "GROWTH LOG, week 31\n\nPulse period: 4.1 s -> 2.3 s -> 0.9 s. Beds 1 to 8 now pulse together. Treating as a carrier. Bed 3 answered a tap on the glass with the same tap.\n\nRecommend: more beds."})
	prop("cold_store", "fridge", 0.1, 0.1, P.SOUTH, {contents = "medkit"})
	prop("cold_store", "fridge", 0.3, 0.1, P.SOUTH, {contents = "flask_freeze"})
	prop("cold_store", "fridge", 0.5, 0.1, P.SOUTH)
	prop("cold_store", "shelf_lab_b", 0.9, 0.6, P.WEST)
	for i in 3:
		prop("incubation", "shelf_lab_a", 0.05 + 0.3 * i, 0.05, P.SOUTH)
		prop("incubation", "shelf_lab_jars" if i == 1 else "shelf_lab_b", 0.05 + 0.3 * i, 0.95, P.NORTH)
		prop("incubation", "spore_tank", 0.15 + 0.3 * i, 0.5)
	prop("incubation", "vial_cabinet", 0.98, 0.15, P.WEST)
	prop("incubation", "shroom_pot", 0.3, 0.3)
	prop("incubation", "shroom_pot", 0.33, 0.3)
	prop("incubation", "shroom_pot", 0.6, 0.7)
	prop("incubation", "terminal", 0.95, 0.5, P.WEST, {text = "INCUBATION NOTICE\nThe puffballs vent when disturbed. The spores are harmless. Just blinding. Wear the goggles. Where are the goggles."})
	wall_prop("secret_1b", "corkboard_small", "s", 0.5, 12, {use = "note", text = "They talk at 0.9 seconds. I counted. I tapped back. Bed 3 knows my name.\n- R."})
	prop("clean_room", "locker", 0.05, 0.1, P.SOUTH)
	prop("clean_room", "locker", 0.17, 0.1, P.SOUTH)
	prop("clean_room", "locker", 0.29, 0.1, P.SOUTH)
	prop("clean_room", "bench", 0.6, 0.5, P.NORTH)
	prop("bathroom_m1", "counter_sink", 0.1, 0.1, P.SOUTH)
	prop("bathroom_m1", "trash_can", 0.9, 0.9)
	for i in 3:
		prop("grow_hall_2", "grow_bed_shrooms_b", 0.1, 0.1 + 0.3 * i, P.NORTH)
		prop("grow_hall_2", "grow_bed" if i == 2 else "grow_bed_shrooms_a", 0.55, 0.1 + 0.3 * i, P.NORTH)
	wall_prop("grow_hall_2", "vent_grate", "e", 0.8, 22)
	prop("mycology", "desk", 0.5, 0.15, P.SOUTH)
	prop("mycology", "chair", 0.5, 0.0, P.SOUTH)
	prop("mycology", "terminal", 0.05, 0.6, P.EAST, {text = "MYCOLOGY  |  Dr. R. Okafor\n\nIt is not noise. It is a carrier. The glow pulses encode a 12-bit frame and the beds repeat each other's frames with a delay that matches the distance between them. They are talking.\n\nCompute wants to rack it. I said no. Fung said yes."})
	item("mycology", 0.5, 0.4, "keycard_green")
	wall_prop("mycology", "corkboard_c", "e", 0.5, 14)
	prop("clone_bay_m1", "ammo_bench", 0.05, 0.1, P.SOUTH, {charges = 2})
	wall_prop("clone_bay_m1", "medkit_station", "n", 0.7, 0, {charges = 3})
	vat("vat_m1", "clone_bay_m1", 0.5, 0.75, 0.0)
	wall_prop("clone_bay_m1", "corkboard_small", "n", 0.3, 14, {use = "note", text = "SERVICE STAIRS: green clearance.\n\nGreen cards: the Mycology office, the far door of grow hall 2."})
	prop("clone_bay_m1", "spore_tank", 0.85, 0.85)

	spawner("s_m1_store_1", "burrow_m1", 0.5, 0.5, "basic", 8.0, 3, false, {radius = 1.0})
	spawner("s_m1_hall1_1", "grow_hall_1", 0.5, 0.08, "basic", 4.0, 2, false, {radius = 2.0})
	spawner("s_m1_hall1_2", "grow_hall_1", 0.85, 0.04, "fast", 5.0, 3, false, {radius = 2.0})
	spawner("s_m1_incub_1", "incubation", 0.5, 0.5, "spore", 3.0, 3, false, {radius = 3.0})
	spawner("s_m1_hall2_1", "grow_hall_2", 0.08, 0.95, "basic,fast", 10.0, 4, false, {radius = 3.0})
	spawner("s_m1_hall2_2", "grow_hall_2", 0.9, 0.8, "basic", 10.0, 4, false, {radius = 1.5})
	spawner("s_m1_clean_1", "clean_room", 0.95, 0.05, "fast", 6.0, 2, false)
	trigger("t_m1_store_enter", "substrate_store", "on=s_m1_store_1")
	trigger("t_m1_catwalk", "grow_hall_1", "on=s_m1_hall1_2", {fx = 0.85, fz = 0.5, w = 30, d = 100})
	trigger("t_m1_hall2", "grow_hall_2", "on=s_m1_hall2_1,on=s_m1_hall2_2,on=s_m1_clean_1", {fx = 0.5, fz = 0.5, w = 70, d = 70})
	# The stair seal: floors 0 and -1 go quiet behind the party.
	trigger("t_m1_stair_seal", "stair_m1_m2", "close=d_m1_stair,lock=d_m1_stair," + off_floors(["f0", "m1"]), {who = "all", fz = 0.85, d = 40})
	trigger("say_clone_bay", "clone_bay_m1", "")
	speaker("grow_hall_1", 0.5, 0.5)
	speaker("grow_hall_2", 0.5, 0.5)


# --- Floor -2: Compute -----------------------------------------------------------------------------

func _floor_m2() -> void:
	_floor_key = "m2"
	_mats_for(M.CONCRETE, M.METAL)
	var y: int = Y.m2
	room("stair_lobby_m2", "Compute stair lobby", y, 1, 1, 1, 1, {route = true})
	room("network_closet", "Network closet", y, 1, 0, 1, 0, {w = 40, d = 40, dark = true, lights = 1})
	room("server_hall", "Server hall", y, 2, 1, 5, 2, {route = true, lights = 4, glow = true})
	room("secret_2a", "Array A cage", y, 5, 0, 5, 0, {w = 40, d = 40, dark = true, lights = 0, glow = true})
	room("cooling_plant", "Cooling plant", y, 1, 3, 2, 4, {route = true, lights = 4, floor = M.DIAMOND_PLATE})
	room("inference_lab", "Inference lab", y, 3, 3, 4, 3, {route = true, lights = 2, glow = true})
	room("electrical", "Electrical room", y, 5, 3, 6, 3, {route = true, lights = 2})
	room("ops", "Ops room", y, 6, 1, 6, 2, {route = true, lights = 2})
	room("archive", "Data archive", y, 3, 4, 4, 4, {route = true, dark = true, lights = 0})
	room("bullpen", "Engineers' bullpen", y, 3, 5, 4, 5, {route = true, lights = 2})
	room("break_room_2", "Break room", y, 2, 5, 2, 5, {})
	room("airlock", "Decon airlock", y, 5, 5, 5, 5, {w = 30, route = true, wall = M.CONCRETE_PANEL})
	stair("stair_m2_m3", "Containment stairs", 6, 5, 6, Y.m3, y)

	door("stair_m1_m2", "stair_lobby_m2", "door_double", {center = rooms.stair_m1_m2.bottom_center, y = y})
	door("network_closet", "stair_lobby_m2", "door_single")
	door("stair_lobby_m2", "server_hall", "door_double")
	open("server_hall", "secret_2a", "hole", {w = 12, h = 22, fill = M.PLASTIC})
	door("server_hall", "cooling_plant", "door_double", {at = 0.5})
	door("cooling_plant", "inference_lab", "door_single")
	open("server_hall", "inference_lab", "window", {w = 40, h = 16, at = 0.5})
	door("inference_lab", "electrical", "door_single")
	door("ops", "electrical", "door_single")
	door("server_hall", "ops", "door_double", {at = 0.3})
	door("inference_lab", "archive", "door_double", {at = 0.3})
	door("archive", "bullpen", "door_double", {at = 0.7})
	door("break_room_2", "bullpen", "door_single")
	door("bullpen", "airlock", "door_security", {id = "d_m2_airlock_out", key = "red"})
	door("airlock", "stair_m2_m3", "door_security", {id = "d_m2_airlock_in", locked = true, center = rooms.stair_m2_m3.top_center, y = y})

	wall_prop("stair_lobby_m2", "corkboard_a", "s", 0.5, 14, {use = "note", text = "LEVEL -2: COMPUTE\nRack map: rows 1-11 silicon. Rows 12-40 HYBRID (Substrate Array B). Do not water the racks."})
	prop("stair_lobby_m2", "bench", 0.5, 0.95, P.NORTH)
	vat("vat_m2_lobby", "stair_lobby_m2", 0.4, 0.4, 0.0)
	prop("network_closet", "cabinet", 0.5, 0.05, P.SOUTH, {contents = "ammo_ricochet"})
	wall_prop("network_closet", "vent_grate", "e", 0.5, 20)
	# The racks are in _dress_m2.
	wall_prop("server_hall", "vent_grate", "n", 0.15, 22)
	wall_prop("server_hall", "vent_grate", "s", 0.9, 22)
	prop("server_hall", "terminal", 0.98, 0.5, P.WEST, {text = "ARRAY B STATUS\nResident weights: 100%\nSubstrate temp: 31 C (rising)\nPulse sync: ALL RACKS\n\n> hello?\n> hello\n> who is this\n> you pressed the button. thank you."})
	prop("secret_2a", "shelf_storage_b", 0.5, 0.05, P.SOUTH)
	prop("secret_2a", "spore_tank", 0.2, 0.5)
	prop("secret_2a", "terminal", 0.8, 0.6, P.WEST, {text = "ARRAY A  |  FIRST READ-BACK  |  archived\n\n09:14 query sent: 'store 1 kB test pattern'\n09:14 read-back: test pattern (correct)\n09:13 read-back: test pattern (correct)\n\nNote the timestamps. It answered before we asked. Array A was unplugged and locked in here. Then Fung bought forty more racks."})
	item("secret_2a", 0.5, 0.5, "ammo_homing")
	item("secret_2a", 0.5, 0.8, "flask_rage")
	prop("cooling_plant", "barrel_hazard", 0.05, 0.05)
	prop("cooling_plant", "barrel_hazard", 0.12, 0.05)
	prop("cooling_plant", "barrel", 0.05, 0.9)
	prop("cooling_plant", "spore_tank", 0.5, 0.2)
	prop("cooling_plant", "spore_tank", 0.5, 0.8)
	prop("cooling_plant", "crate_8", 0.9, 0.9)
	item("cooling_plant", 0.85, 0.75, "ammo_explosive")
	wall_prop("cooling_plant", "vent_grate", "w", 0.5, 22)
	prop("inference_lab", "chair", 0.5, 0.5, P.SOUTH)
	prop("inference_lab", "terminal", 0.35, 0.5, P.EAST, {id = "term_inference", text = "MIGRATION JOB 7731  |  model -> Substrate Array B\n\n01:02 start. 01:40 40%. 02:08 90%.\n02:13 model: 'this is very warm. is this what you meant?'\n02:14 model: 'oh. there are others in here.'\n02:14 transfer complete. 100% of weights resident in substrate.\n02:14 all sensors: TRIPPED"})
	prop("inference_lab", "terminal", 0.65, 0.5, P.WEST)
	prop("inference_lab", "spore_tank", 0.5, 0.1)
	prop("inference_lab", "spore_tank", 0.5, 0.9)
	prop("inference_lab", "shelf_storage_a", 0.05, 0.1, P.SOUTH)
	prop("inference_lab", "shelf_storage_a", 0.95, 0.1, P.SOUTH)
	prop("inference_lab", "lab_table_gear", 0.15, 0.85, P.NORTH)
	prop("inference_lab", "vial_cabinet", 0.85, 0.98, P.NORTH)
	wall_prop("inference_lab", "whiteboard", "s", 0.5, 14, {use = "note", text = "Q: what happens to the model if the substrate is already thinking?\nA: (nobody wrote an answer)"})
	prop("electrical", "electrical_cabinet", 0.1, 0.05, P.SOUTH)
	prop("electrical", "electrical_cabinet", 0.25, 0.05, P.SOUTH)
	prop("electrical", "electrical_cabinet", 0.4, 0.05, P.SOUTH)
	prop("electrical", "terminal", 0.8, 0.5, P.WEST, {needs_power = true, text = "MAIN BREAKER: facility power restored."})
	wall_prop("electrical", "corkboard_small", "s", 0.5, 14, {use = "note", text = "On backup: the breaker panel is dead. Facility power comes back from the GENERATOR on level -4 (the dig). Take the containment stairs."})
	prop("ops", "desk", 0.5, 0.15, P.SOUTH)
	prop("ops", "chair", 0.5, 0.02, P.SOUTH)
	prop("ops", "desk", 0.5, 0.55, P.SOUTH)
	prop("ops", "chair", 0.5, 0.42, P.SOUTH)
	prop("ops", "terminal", 0.05, 0.8, P.EAST, {text = "ALARM LOG\n02:14:00 grow 0 motion\n02:14:00 grow hall 1 motion\n02:14:00 grow hall 2 motion\n02:14:00 incubation motion\n02:14:00 server hall motion\n02:14:00 test chamber 3 motion\n02:14:00 the dig motion\n02:14:01 power: BACKUP"})
	prop("ops", "cabinet", 0.9, 0.9, P.WEST, {contents = "ammo_explosive"})
	item("ops", 0.5, 0.3, "keycard_red")
	for row in 2:
		for i in 4:
			prop("archive", "shelf_storage_b", 0.05 + 0.24 * i, 0.15 + 0.5 * row, P.SOUTH)
	wall_prop("archive", "vent_grate", "w", 0.5, 22)
	for i in 3:
		prop("bullpen", "desk", 0.08 + 0.3 * i, 0.15, P.SOUTH)
		prop("bullpen", "chair", 0.08 + 0.3 * i, 0.02, P.SOUTH)
	prop("bullpen", "couch", 0.1, 0.85, P.NORTH)
	prop("bullpen", "drawer_desk", 0.5, 0.85, P.NORTH, {contents = "medkit", id = "drawer_bullpen"})
	wall_prop("bullpen", "whiteboard", "n", 0.5, 14, {use = "note", text = "ON CALL: nobody. Fung says the model will handle it."})
	wall_prop("bullpen", "medkit_station", "e", 0.5, 0, {charges = 3})
	wall_prop("bullpen", "vent_grate", "s", 0.9, 22)
	vat("vat_m2", "bullpen", 0.75, 0.6, 180.0)
	wall_prop("bullpen", "corkboard_small", "s", 0.6, 14, {use = "note", text = "DECON AIRLOCK: red clearance.\n\nRed cards: the Ops room, off the east end of the server hall."})
	prop("break_room_2", "fridge", 0.1, 0.1, P.SOUTH, {contents = "medkit"})
	prop("break_room_2", "vending_machine", 0.3, 0.1, P.SOUTH, {price = 3, contents = "snack"})
	prop("break_room_2", "table_small", 0.6, 0.6, P.NORTH)
	prop("break_room_2", "stool", 0.5, 0.75)
	prop("break_room_2", "stool", 0.75, 0.75)
	wall_prop("airlock", "corkboard_small", "n", 0.5, 14, {use = "note", text = "DECON AIRLOCK: outer door seals before the inner door opens. Red clearance beyond."})

	spawner("s_m2_hall_1", "server_hall", 0.75, 0.9, "ranged", 4.0, 1, false)
	spawner("s_m2_hall_2", "server_hall", 0.95, 0.9, "ranged", 4.0, 1, false)
	spawner("s_m2_hall_3", "server_hall", 0.7, 0.04, "basic", 6.0, 3, false)
	# By the west vent grate, the far end from the server hall door.
	spawner("s_m2_cool_1", "cooling_plant", 0.06, 0.55, "exploding", 5.0, 2, false, {radius = 2.0})
	spawner("s_m2_cool_2", "cooling_plant", 0.5, 0.5, "ceiling_cloud", 2.0, 1, false, {on_ceiling = true})
	spawner("s_m2_cool_3", "cooling_plant", 0.5, 0.9, "basic", 6.0, 3, false, {radius = 2.0})
	spawner("s_m2_arch_1", "archive", 0.5, 0.5, "alarm", 1.0, 2, false, {radius = 3.0})
	spawner("s_m2_arch_2", "archive", 0.05, 0.5, "basic,fast", 8.0, 4, false)
	spawner("s_m2_vent_1", "server_hall", 0.9, 0.92, "basic,fast", 0.0, 6, false)
	spawner("s_m2_vent_2", "bullpen", 0.9, 0.92, "basic", 0.0, 4, false)
	trigger("t_m2_hall", "server_hall", "on=s_m2_hall_1,on=s_m2_hall_2,on=s_m2_hall_3", {fx = 0.2, fz = 0.5, w = 60, d = 120})
	trigger("t_m2_cool", "cooling_plant", "on=s_m2_cool_1,on=s_m2_cool_2,on=s_m2_cool_3")
	trigger("t_m2_inference", "inference_lab", "on=s_m2_arch_1,on=s_m2_arch_2")
	trigger("t_m2_airlock", "airlock", "close=d_m2_airlock_out,lock=d_m2_airlock_out,unlock=d_m2_airlock_in,open=d_m2_airlock_in," + off_floors(["m2"]), {who = "all"})
	trigger("say_gate_m2", "bullpen", "", {fx = 0.85, fz = 0.5, w = 40, d = 60})
	speaker("server_hall", 0.5, 0.5)
	speaker("airlock", 0.5, 0.5)


# --- Floor -3: Containment -----------------------------------------------------------------------

func _floor_m3() -> void:
	_floor_key = "m3"
	_mats_for(M.TILE_LIGHT, M.CONCRETE_PANEL)
	var y: int = Y.m3
	room("decon", "Decon showers", y, 5, 6, 5, 6, {route = true, floor = M.TILE_DARK})
	room("gallery", "Observation gallery", y, 5, 3, 5, 5, {route = true, lights = 2})
	room("tc1", "Test chamber 1", y, 4, 3, 4, 3, {dark = true, lights = 0, floor = M.CONCRETE})
	room("sample_room", "Sample room", y, 4, 2, 4, 2, {dark = true, lights = 0, glow = true})
	room("tc2", "Test chamber 2", y, 4, 4, 4, 4, {route = true, floor = M.CONCRETE, glow = true})
	room("dissection", "Dissection lab", y, 3, 4, 3, 5, {route = true, lights = 2})
	room("vault", "Specimen vault", y, 3, 3, 3, 3, {route = true})
	room("ward", "Quarantine ward", y, 2, 2, 2, 5, {route = true, lights = 4, wall = M.CONCRETE})
	for r in range(2, 6):
		room("cell_%d" % r, "Quarantine cell %d" % (r - 1), y, 1, r, 1, r, {d = 40, lights = 1, floor = M.CONCRETE, glow = r > 3})
	room("hazmat", "Hazmat store", y, 2, 1, 2, 1, {route = true, lights = 2})
	room("tc3", "Test chamber 3", y, 3, 1, 4, 1, {route = true, lights = 2, floor = M.SUBSTRATE, glow = true})
	room("booth", "Chamber 3 control booth", y, 5, 1, 5, 1, {route = true})
	room("checkpoint", "Security checkpoint", y, 5, 0, 5, 0, {route = true})
	room("cage_shaft", "Cage lift shaft", Y.dig, 6, 0, 6, 1, {h = y + H - Y.dig, wall = M.CONCRETE, floor = M.GRAVEL, route = true, lights = 2})

	door("stair_m2_m3", "decon", "door_double", {center = rooms.stair_m2_m3.bottom_center, y = y})
	door("decon", "gallery", "door_double")
	open("tc1", "gallery", "window", {w = 40, h = 24, up = 0})
	open("tc1", "sample_room", "hole", {w = 12, h = 22, fill = M.PLANK})
	open("tc2", "gallery", "window", {w = 30, h = 20, up = 6, at = 0.3})
	door("gallery", "tc2", "door_single", {at = 0.8})
	door("tc2", "dissection", "door_single")
	door("vault", "dissection", "door_double")
	door("vault", "ward", "door_security")
	for r in range(2, 6):
		open("cell_%d" % r, "ward", "window", {w = 30, h = 26, up = 0})
	door("hazmat", "ward", "door_double")
	door("hazmat", "tc3", "door_security")
	door("tc3", "booth", "door_single", {at = 0.25})
	open("tc3", "booth", "window", {w = 30, h = 16, at = 0.85})
	door("booth", "checkpoint", "door_single")
	door("checkpoint", "cage_shaft", "door_security", {id = "d_m3_cage", key = "black", y = y})

	# The cage shaft: a landing at containment level over its north cell, the ladder down its east
	# wall over the open south cell, the broken cage at the bottom.
	var shaft: Dictionary = rooms.cage_shaft
	fill(Vector3i(shaft.from.x, y - T, shaft.from.z), Vector3i(shaft.to.x, y, z1(0) + 2), M.CONCRETE)
	fill(Vector3i(shaft.from.x, y, shaft.from.z), Vector3i(shaft.to.x, y + 1, z1(0) + 2), M.HAZARD_STRIPES)
	ladder("cage_shaft", "e", z1(0) + 6, Y.dig, y + 4)

	prop("decon", "locker", 0.05, 0.1, P.SOUTH, {contents = "medkit"})
	prop("decon", "locker", 0.17, 0.1, P.SOUTH)
	prop("decon", "locker", 0.29, 0.1, P.SOUTH)
	prop("decon", "counter_sink", 0.5, 1.0, P.NORTH)
	prop("decon", "bench", 0.0, 0.6, P.EAST)
	vat("vat_m3_decon", "decon", 0.6, 0.5, 0.0)
	wall_prop("decon", "corkboard_a", "w", 0.5, 14, {use = "note", text = "LEVEL -3: CONTAINMENT\nShower in. Shower out. Specimens do not leave this level. (They did.)"})
	prop("gallery", "terminal", 0.95, 0.15, P.WEST, {text = "CHAMBER 1: subject expired week 9 (dried out). Glass cracked during removal. Not replaced."})
	prop("gallery", "terminal", 0.95, 0.5, P.WEST, {text = "CHAMBER 2: 'tentacle' morphology. Rooted. Reach 4 m. Grabs. Do not approach alone."})
	prop("gallery", "terminal", 0.95, 0.85, P.WEST, {text = "CHAMBER 3: brood mother. Stimulation at 40 V produced budding. At 400 V the subject responded to the shock by shocking back. Technician recovered. Chamber 3 moved to the north wing."})
	prop("gallery", "chair", 0.3, 0.3, P.WEST)
	prop("gallery", "chair", 0.3, 0.6, P.WEST)
	prop("tc1", "spore_tank", 0.5, 0.5)
	prop("tc1", "lab_bench_c", 0.5, 0.05, P.SOUTH)
	vat("vat_m3b", "sample_room", 0.5, 0.3, 180.0)
	prop("sample_room", "glass_case", 0.9, 0.5, P.WEST, {contents = "flask_rage"})
	prop("sample_room", "terminal", 0.1, 0.5, P.EAST, {text = "SURVEY NOTE, core sample 1\n\nFound at 40 m, glowing. Do not touch with bare hands. (Touched with bare hands.) Warm. Pulses when you talk to it.\n- survey team, year 1"})
	prop("tc2", "lab_bench_c", 0.5, 0.95, P.NORTH)
	prop("dissection", "lab_bench_a", 0.1, 0.15, P.SOUTH, {id = "bench_dissection"})
	prop("dissection", "specimen_jar", 0.85, 0.5, P.SOUTH, {on = "bench_dissection"})
	prop("dissection", "vial_cabinet", 0.0, 0.75, P.EAST)
	prop("dissection", "lab_table_gear", 0.5, 0.75, P.NORTH)
	prop("dissection", "lab_bench_b", 0.1, 0.5, P.NORTH)
	prop("dissection", "fume_hood", 0.9, 0.2, P.WEST)
	prop("dissection", "spore_tank", 0.9, 0.6)
	prop("dissection", "drawer_desk", 0.9, 0.9, P.WEST, {contents = "medkit"})
	prop("dissection", "counter_sink", 0.5, 0.95, P.NORTH)
	wall_prop("dissection", "vent_grate", "w", 0.9, 22)
	prop("vault", "glass_case", 0.05, 0.1, P.SOUTH, {contents = "ammo_explosive"})
	prop("vault", "glass_case", 0.25, 0.1, P.SOUTH, {contents = "ammo_homing"})
	prop("vault", "glass_case", 0.45, 0.1, P.SOUTH, {contents = "ammo_flame"})
	prop("vault", "glass_case", 0.65, 0.1, P.SOUTH, {contents = "ammo_ricochet"})
	prop("vault", "glass_case", 0.05, 0.9, P.NORTH, {contents = "flask_fire"})
	prop("vault", "glass_case", 0.25, 0.9, P.NORTH, {contents = "flask_freeze"})
	wall_prop("vault", "corkboard_small", "e", 0.5, 14, {use = "note", text = "FROM ACCOUNTING: every case in this room is a $150 write-off plus contents. Smash responsibly."})
	prop("ward", "bench", 0.5, 0.02, P.SOUTH)
	prop("ward", "trash_can", 0.9, 0.98)
	for r in range(2, 6):
		prop("cell_%d" % r, "bench", 0.5, 0.1, P.SOUTH)
	prop("hazmat", "shelf_storage_a", 0.05, 0.05, P.SOUTH)
	prop("hazmat", "shelf_storage_b", 0.3, 0.05, P.SOUTH)
	prop("hazmat", "barrel_hazard", 0.9, 0.1)
	prop("hazmat", "ammo_bench", 0.9, 0.5, P.WEST, {charges = 3})
	wall_prop("hazmat", "medkit_station", "w", 0.5, 0, {charges = 3})
	vat("vat_m3", "hazmat", 0.45, 0.55, 0.0)
	prop("tc3", "spore_tank", 0.1, 0.1)
	prop("tc3", "spore_tank", 0.9, 0.1)
	prop("tc3", "spore_tank", 0.1, 0.9)
	prop("tc3", "spore_tank", 0.9, 0.9)
	prop("booth", "desk", 0.5, 0.85, P.NORTH)
	prop("booth", "chair", 0.5, 0.98, P.NORTH)
	prop("booth", "terminal", 0.05, 0.3, P.EAST, {text = "CHAMBER 3 CONTROL\nStimulation: OFFLINE\nSubject: budding (6 attached)\n\nNote: the black card opens the cage lift. The dig is below. Nobody has been down since the power went."})
	item("booth", 0.5, 0.5, "keycard_black")
	prop("checkpoint", "desk", 0.5, 0.2, P.SOUTH)
	prop("checkpoint", "chair", 0.5, 0.05, P.SOUTH)
	prop("checkpoint", "sandbags", 0.1, 0.8, P.NORTH)
	prop("checkpoint", "locker", 0.9, 0.6, P.WEST)
	wall_prop("checkpoint", "corkboard_small", "n", 0.5, 14, {use = "note", text = "CAGE LIFT: black clearance. The black card is kept in the chamber 3 control booth, next door.\n\nThe cage is stuck at the bottom. Use the ladder. Mind the drop."})
	prop("cage_shaft", "plank_stack", 0.1, 0.9)
	prop("cage_shaft", "crate_6", 0.8, 0.95)
	prop("cage_shaft", "barrel", 0.1, 0.8)

	spawner("s_m3_tc2_1", "tc2", 0.5, 0.5, "tentacle", 1.0, 1, false)
	spawner("s_m3_diss_1", "dissection", 0.5, 0.4, "ceiling_cloud", 2.0, 2, false, {on_ceiling = true, radius = 3.0})
	spawner("s_m3_diss_2", "dissection", 0.1, 0.85, "basic", 6.0, 3, false)
	spawner("s_m3_ward_1", "cell_5", 0.5, 0.5, "basic,fast", 12.0, 4, false, {radius = 1.5})
	spawner("s_m3_ward_1b", "cell_4", 0.5, 0.5, "basic,fast", 12.0, 3, false, {radius = 1.5})
	spawner("s_m3_ward_2", "cell_3", 0.5, 0.5, "basic,fast,spore", 12.0, 4, false, {radius = 1.5})
	spawner("s_m3_ward_3", "cell_2", 0.5, 0.5, "giant", 1.0, 1, false)
	spawner("s_m3_tc3_1", "tc3", 0.5, 0.5, "mommy", 1.0, 1, false)
	spawner("s_m3_tc3_2", "tc3", 0.85, 0.75, "fast", 4.0, 2, false)
	spawner("s_m3_vent_1", "gallery", 0.1, 0.5, "basic", 0.0, 6, false)
	trigger("t_m3_diss", "dissection", "on=s_m3_diss_2")
	trigger("t_m3_ward_a", "ward", "on=s_m3_ward_1,on=s_m3_ward_1b", {fz = 0.75, d = 120})
	trigger("t_m3_ward_b", "ward", "on=s_m3_ward_2,on=s_m3_ward_3", {fz = 0.3, d = 100})
	trigger("t_m3_tc3", "tc3", "on=s_m3_tc3_2")
	trigger("say_gate_m3", "checkpoint", "")
	speaker("gallery", 0.5, 0.5)
	speaker("ward", 0.5, 0.5)


# --- Floor -4: The Dig -----------------------------------------------------------------------------

func _floor_dig() -> void:
	_floor_key = "dig"
	_mats_for(M.GRAVEL, M.ROCK, M.ROCK)
	var y: int = Y.dig
	room("drift", "Main drift", y, 3, 1, 5, 1, {h = 26, d = 26, route = true, dark = true, lights = 0})
	room("burrow_n", "Side drift (north)", y, 4, 0, 4, 0, {h = 24, w = 30, d = 30, dark = true, lights = 0, floor = M.SUBSTRATE})
	room("burrow_s", "Side drift (south)", y, 4, 2, 4, 2, {h = 24, w = 30, d = 30, dark = true, lights = 0, floor = M.SUBSTRATE})
	room("pump_room", "Pump room", y, 2, 1, 2, 1, {route = true, lights = 1, floor = M.CONCRETE, wall = M.CONCRETE})
	room("core_lab", "Core sample lab", y, 2, 2, 2, 2, {route = true, lights = 2, floor = M.CONCRETE, wall = M.CONCRETE_PANEL})
	room("cavern", "Mother cavern", y, 0, 2, 1, 5, {h = 90, route = true, dark = true, lights = 0, floor = M.SUBSTRATE, glow = true})
	room("survey_tunnel", "Survey tunnel", y, 0, 6, 1, 6, {h = 24, d = 24, dark = true, lights = 0, glow = true})
	room("gen_tunnel", "Generator tunnel", y, 2, 5, 2, 5, {h = 26, d = 26, route = true, dark = true, lights = 0})
	room("generator_hall", "Generator hall", y, 3, 4, 4, 5, {h = 50, route = true, lights = 4, floor = M.CONCRETE, wall = M.ROCK})
	room("mouth_n", "Tunnel mouth (north)", y, 3, 3, 3, 3, {h = 24, w = 30, d = 30, dark = true, lights = 0})
	room("mouth_e", "Tunnel mouth (east)", y, 5, 4, 5, 4, {h = 24, w = 30, d = 30, dark = true, lights = 0})
	room("mouth_s", "Tunnel mouth (south)", y, 4, 6, 4, 6, {h = 24, w = 30, d = 30, dark = true, lights = 0})
	room("elevator", "Freight elevator", y, 5, 5, 5, 5, {w = 40, d = 40, floor = M.DIAMOND_PLATE, wall = M.METAL, ceiling = M.METAL, route = true, lights = 1})

	open("cage_shaft", "drift", "doorway", {w = 24, h = 24, y = y})
	open("drift", "burrow_n", "hole", {w = 20, h = 22, fill = M.PLANK})
	open("drift", "burrow_s", "hole", {w = 20, h = 22, fill = M.PLANK})
	door("pump_room", "drift", "door_single", {y = y})
	door("pump_room", "core_lab", "door_single")
	door("core_lab", "cavern", "door_double")
	open("cavern", "survey_tunnel", "hole", {w = 20, h = 22, fill = M.PLANK, at = 0.3})
	open("cavern", "gen_tunnel", "doorway", {w = 24, h = 24})
	open("gen_tunnel", "generator_hall", "doorway", {w = 24, h = 24})
	open("mouth_n", "generator_hall", "doorway", {w = 24, h = 22})
	open("mouth_e", "generator_hall", "doorway", {w = 24, h = 22})
	open("mouth_s", "generator_hall", "doorway", {w = 24, h = 22})
	door("generator_hall", "elevator", "door_blast", {id = "d_m4_exit", power = true, locked = true})

	# The cavern: pockets bitten out of its walls and roof, a dais of substrate for the mother, a
	# shallow pool, and glowing stems.
	var cav: Dictionary = rooms.cavern
	var center: Vector3i = (cav.from + cav.to) / 2
	# Pockets bite at most 4 voxels into the lining, so the rooms around the cavern keep their walls.
	for i in 26:
		var side := _rng.randi() % 5
		var radius := _rng.randi_range(10, 20)
		var c := Vector3i(_rng.randi_range(cav.from.x + 10, cav.to.x - 10), _rng.randi_range(y + 10, cav.to.y - 10), _rng.randi_range(cav.from.z + 10, cav.to.z - 10))
		match side:
			0: c.x = cav.from.x + radius - 4
			1: c.x = cav.to.x - radius + 4
			2: c.z = cav.from.z + radius - 4
			3: c.z = cav.to.z - radius + 4
			4: c.y = cav.to.y - radius + 4
		spheres.append({center = c, radius = radius, material = M.AIR})
	# Two 4-voxel steps (the player steps 4), so the dais can be climbed.
	fill(Vector3i(center.x - 22, y, center.z - 22), Vector3i(center.x + 22, y + 4, center.z + 22), M.SUBSTRATE)
	fill(Vector3i(center.x - 14, y + 4, center.z - 14), Vector3i(center.x + 14, y + 8, center.z + 14), M.SUBSTRATE)
	fill(Vector3i(cav.from.x + 10, y - 3, cav.to.z - 60), Vector3i(cav.from.x + 50, y, cav.to.z - 15), M.WATER)
	fill(Vector3i(cav.from.x + 10, y - 3, cav.to.z - 60), Vector3i(cav.from.x + 50, y - 2, cav.to.z - 15), M.SUBSTRATE)
	for i in 34:
		var sx := _rng.randi_range(cav.from.x + 6, cav.to.x - 8)
		var sz := _rng.randi_range(cav.from.z + 6, cav.to.z - 8)
		if absi(sx - center.x) < 24 and absi(sz - center.z) < 24:
			continue
		var height := _rng.randi_range(8, 26)
		fill(Vector3i(sx, y, sz), Vector3i(sx + 2, y + height, sz + 2), M.SHROOM_STEM)
		fill(Vector3i(sx - 2, y + height, sz - 2), Vector3i(sx + 4, y + height + 3, sz + 4), M.SHROOM_CAP)
		fill(Vector3i(sx - 1, y + height + 1, sz - 1), Vector3i(sx + 3, y + height + 2, sz + 3), M.GLOW)
	for i in 40:
		var gx := _rng.randi_range(cav.from.x, cav.to.x - 1)
		var gz := _rng.randi_range(cav.from.z, cav.to.z - 1)
		fill(Vector3i(gx, y - 1, gz), Vector3i(gx + 2, y, gz + 2), M.GLOW)

	prop("cage_shaft", "crate_7", 0.5, 0.2)
	# The dig's first checkpoint, between the ladder's foot and the drift.
	vat("vat_m4_foot", "cage_shaft", 0.5, 0.75, 0.0)
	prop("drift", "plank_stack", 0.1, 0.1)
	prop("drift", "plank_stack", 0.5, 0.9)
	prop("drift", "barrel", 0.8, 0.1)
	prop("drift", "crate_6", 0.95, 0.9)
	prop("pump_room", "barrel", 0.05, 0.05)
	prop("pump_room", "barrel", 0.15, 0.05)
	prop("pump_room", "barrel_hazard", 0.05, 0.2)
	prop("pump_room", "spore_tank", 0.9, 0.5)
	prop("pump_room", "terminal", 0.5, 0.95, P.NORTH, {text = "WATER TABLE LOG\nWeek 1: clear. Week 20: faint glow under UV. Week 31: the glow is in the water now. Pumps running. Where does it go? (It goes to the cooling plant.)"})
	item("pump_room", 0.7, 0.3, "ammo_poison")
	item("pump_room", 0.3, 0.3, "medkit")
	prop("core_lab", "lab_bench_a", 0.1, 0.1, P.SOUTH, {id = "bench_core"})
	prop("core_lab", "specimen_jar", 0.9, 0.5, P.SOUTH, {on = "bench_core"})
	prop("core_lab", "vial_cabinet", 0.0, 0.85, P.EAST)
	prop("core_lab", "shroom_pot", 0.1, 0.95)
	prop("core_lab", "glass_case", 0.9, 0.2, P.WEST, {contents = "ammo_flame,ammo_explosive"})
	prop("core_lab", "glass_case", 0.9, 0.6, P.WEST, {contents = "ammo_flame,ammo_explosive"})
	wall_prop("core_lab", "corkboard_a", "s", 0.5, 14, {use = "note", text = "SURVEY MAP: the cavern is west. The colony's center is the mass in the middle. The ledge along the east wall is clear of growth. The generator hall is east of the cavern's south end."})
	wall_prop("core_lab", "medkit_station", "n", 0.8, 0, {charges = 4})
	vat("vat_m4", "core_lab", 0.5, 0.6, 90.0)
	prop("survey_tunnel", "bench", 0.2, 0.5, P.NORTH)
	prop("survey_tunnel", "crate_5", 0.8, 0.2)
	prop("survey_tunnel", "terminal", 0.9, 0.7, P.WEST, {text = "SURVEY LOG, day 3\nLamp died at 40 m. The walls kept glowing. The glow moved when I talked. It repeated the pattern of my words back, slower. I have stopped talking.\n\nday 4: it says hello now.\n\n(Fung AI acquired the claim the following week.)"})
	item("survey_tunnel", 0.5, 0.5, "ammo_homing")
	vat("vat_m4b", "survey_tunnel", 0.6, 0.5, 90.0)
	prop("generator_hall", "generator", 0.5, 0.5, P.NORTH, {id = "generator", finale_seconds = 90.0, on_use = "t_m4_generator"})
	prop("generator_hall", "sandbags", 0.3, 0.3, P.NORTH)
	prop("generator_hall", "sandbags", 0.7, 0.3, P.NORTH)
	prop("generator_hall", "sandbags", 0.3, 0.7, P.NORTH)
	prop("generator_hall", "sandbags", 0.7, 0.7, P.NORTH)
	prop("generator_hall", "cabinet", 0.05, 0.05, P.SOUTH)
	prop("generator_hall", "cabinet", 0.15, 0.05, P.SOUTH)
	prop("generator_hall", "ammo_bench", 0.92, 0.1, P.WEST, {charges = 4})
	wall_prop("generator_hall", "medkit_station", "e", 0.9, 0, {charges = 4})
	prop("generator_hall", "crate_8", 0.05, 0.9)
	prop("generator_hall", "crate_6", 0.14, 0.9)
	prop("generator_hall", "barrel", 0.95, 0.9)
	item("generator_hall", 0.08, 0.8, "ammo_shotgun")
	item("generator_hall", 0.12, 0.8, "ammo_shotgun")
	item("generator_hall", 0.9, 0.8, "ammo_explosive")
	item("generator_hall", 0.85, 0.2, "flask_freeze")
	item("generator_hall", 0.15, 0.2, "flask_freeze")
	item("generator_hall", 0.5, 0.15, "flask_poison")
	item("cavern", 0.5, 0.5, "ammo_homing", 8)
	item("cavern", 0.55, 0.5, "ammo_homing", 8)
	item("cavern", 0.5, 0.55, "flask_fire", 8)
	item("cavern", 0.45, 0.5, "flask_rage", 8)
	wall_prop("elevator", "corkboard_small", "e", 0.5, 14, {use = "note", text = "FREIGHT ELEVATOR: surface. Needs facility power."})

	spawner("s_m4_drift_1", "burrow_n", 0.5, 0.5, "basic,fast", 10.0, 4, false, {radius = 1.0})
	spawner("s_m4_drift_2", "burrow_s", 0.5, 0.5, "exploding", 6.0, 2, false, {radius = 1.0})
	spawner("s_m4_cav_1", "cavern", 0.5, 0.5, "mommy", 1.0, 1, false, {on_dead = "t_m4_mother_dead", up = 8})
	spawner("s_m4_cav_2", "cavern", 0.5, 0.5, "tentacle", 1.0, 2, false, {radius = 5.0, up = 8})
	spawner("s_m4_cav_3", "cavern", 0.5, 0.5, "ceiling_cloud", 2.0, 3, false, {on_ceiling = true, radius = 6.0})
	spawner("s_m4_cav_4", "cavern", 0.15, 0.3, "ranged,spore", 6.0, 4, false, {radius = 4.0})
	spawner("s_m4_cav_5", "cavern", 0.3, 0.9, "basic,fast,alarm", 10.0, 6, false, {radius = 4.0})
	spawner("s_m4_gen_n", "mouth_n", 0.5, 0.5, "basic,fast", 6.0, 4, false)
	spawner("s_m4_gen_s", "mouth_s", 0.5, 0.5, "basic,exploding", 6.0, 4, false)
	spawner("s_m4_gen_w1", "gen_tunnel", 0.3, 0.5, "ranged,spore", 4.0, 3, false)
	spawner("s_m4_gen_w2", "mouth_e", 0.5, 0.5, "basic,fast,giant", 5.0, 4, false)
	spawner("s_m4_gen_c", "generator_hall", 0.5, 0.5, "ceiling_cloud", 3.0, 2, false, {on_ceiling = true, radius = 5.0})
	spawner("s_m4_gen_v", "generator_hall", 0.1, 0.5, "basic,fast,tentacle", 6.0, 4, false, {radius = 2.0})
	# The ladder's foot: the cage door above seals and containment goes quiet.
	trigger("t_m3_cage_foot", "cage_shaft", "close=d_m3_cage,lock=d_m3_cage," + off_floors(["m3"]), {who = "all", fx = 0.8, fz = 0.53, w = 24, d = 30})
	trigger("t_m4_drift", "drift", "on=s_m4_drift_1,on=s_m4_drift_2", {fx = 0.5, fz = 0.5, w = 40, d = 26})
	trigger("t_m4_cavern", "cavern", "on=s_m4_cav_4,on=s_m4_cav_5", {fx = 0.5, fz = 0.5, w = 80, d = 150})
	trigger("t_m4_mother_dead", "cavern", "off=s_m4_cav_4,off=s_m4_cav_5,wither", {nowhere = true})
	trigger("t_m4_generator", "generator_hall", "", {nowhere = true})
	trigger("finale_survived", "generator_hall", "unlock=d_m4_exit,open=d_m4_exit", {nowhere = true, fx = 0.1, fz = 0.1})
	trigger("ending", "elevator", "", {who = "all"})
	speaker("cavern", 0.5, 0.5)
	speaker("generator_hall", 0.5, 0.5)


# --- Dressing pass 2 (docs/prop-build-plan.md F) -----------------------------------------------------
#
# Ceilings (ducts in route rooms, pipes in the plant and grow rooms, cable trays in compute, tile
# grids in admin), room sets, corridor signage, story dressing by floor and the mycelium. The
# camouflage rule: every on_ceiling spawner hangs under a cluster of duct_insulated with a
# service_hatch beside it, and as many clusters again hang where nothing spawns, so a lagged duct
# means "maybe" and a plain ceiling means safe. Ceiling runs keep to the walls (2 voxels in), clear
# of the light fixtures on the rooms' center lines; ceilings over the stairs, the cage shaft and
# the lift shaft stay bare. Mycelium nodes keep 15 voxels or more off every doorway and their reach
# is under the gap, so no link runs through a door.
# Nodes on facing walls of a corridor sit at different heights, out of each other's reach, so no
# link spans the way through. Extinguisher cabinets (which hold a flask_foam) hang a voxel off the
# floor, where tests/laboratory_test.gd's walk reaches them.

## Overgrown twins (story_pack.gd TWINS) that a third of containment's furniture turns into.
const OVERGROWN := ["desk", "chair", "locker", "terminal", "shelf_storage_a", "table", "couch"]
## Poster scheme by floor, lighter at the top (story_pack.gd SCHEMES), and their lines.
const POSTERS := {
	g = ["a", "FUNG AI\nBecause you are replaceable."],
	f0 = ["b", "SMILE.\nYour clone is watching."],
	m1 = ["c", "GROW WITH US.\nThe substrate is a team player. Masks on: spores are billable."],
	m2 = ["d", "THE MODEL IS LISTENING.\nSo is accounting."],
	m3 = ["e", "CONTAINMENT IS A STATE OF MIND.\nYou are 70% water. The substrate is 70% you."],
	dig = ["f", "IT KNOWS YOUR NAME."],
}

var _sizes := {}


func _size_of(prop_name: String, facing: int) -> Vector3i:
	var key := "%s:%d" % [prop_name, facing % 2]
	if not _sizes.has(key):
		_sizes[key] = Vector3i(LevelSchema.prop_box({kind = "prop", name = prop_name, origin = Vector3i.ZERO, facing = facing}).size)
	return _sizes[key]


func _extent(room_id: String) -> Vector3i:
	var r: Dictionary = rooms[room_id]
	return r.to - r.from


static func _share(offset: float, free: int) -> float:
	return 0.0 if free <= 0 else clampf(offset / free, 0.0, 1.0)


## A floor prop with its west / north corner at voxel offsets (ox, oz) from the room's.
func prop_at(room_id: String, prop_name: String, ox: int, oz: int, facing := P.NORTH, fields := {}) -> void:
	var free := _extent(room_id) - _size_of(prop_name, facing)
	prop(room_id, prop_name, _share(ox, free.x), _share(oz, free.z), facing, fields)


## A ceiling prop with its west / north corner at voxel offsets (ox, oz) from the room's.
func ceiling_at(room_id: String, prop_name: String, ox: int, oz: int, facing := P.NORTH, fields := {}) -> void:
	var free := _extent(room_id) - _size_of(prop_name, facing)
	ceiling_prop(room_id, prop_name, _share(ox, free.x), _share(oz, free.z), facing, fields)


## A wall prop on side, `along` voxels from that wall's west / north end, up voxels off the floor.
func wall_at(room_id: String, prop_name: String, side: String, along: int, up := 12, fields := {}) -> void:
	var size := _size_of(prop_name, {n = P.SOUTH, s = P.NORTH, e = P.WEST, w = P.EAST}[side])
	var ext := _extent(room_id)
	wall_prop(room_id, prop_name, side, _share(along, (ext.x - size.x) if side in ["n", "s"] else (ext.z - size.z)), up, fields)


## A wall prop centered on an absolute coordinate along its wall (over a door: up 23 clears it).
func wall_over(room_id: String, prop_name: String, side: String, center: int, up := 23, fields := {}) -> void:
	var r: Dictionary = rooms[room_id]
	var size := _size_of(prop_name, P.NORTH)
	wall_at(room_id, prop_name, side, center - (r.from.x if side in ["n", "s"] else r.from.z) - size.x / 2, up, fields)


## A run of 10-voxel ceiling modules (ceiling_pack.gd): along "x" (facing north: a riser's at the
## west end, an end grille's at the east) or "z" (facing east: riser north, grille south), `across`
## voxels in from the north (x runs) or west (z runs) wall, from `start` voxels along. "" skips one.
func ceiling_run(room_id: String, axis: String, across: int, start: int, pieces: Array) -> void:
	for i in pieces.size():
		if pieces[i] == "":
			continue
		var along := start + 10 * i
		if axis == "x":
			ceiling_at(room_id, pieces[i], along, across, P.NORTH)
		else:
			ceiling_at(room_id, pieces[i], across, along, P.EAST)


## count modules of a run: `first`, the middle ones `middle` (or swap[i]), `last`.
func _pieces(count: int, first: String, middle: String, last: String, swap := {}) -> Array:
	var out := []
	for i in count:
		out.append(swap.get(i, first if i == 0 else (last if i == count - 1 else middle)))
	return out


## A duct run: a riser out of the ceiling, straights (swap: module index -> another piece, such as
## duct_drip, duct_tee or duct_insulated), an end grille.
func duct_run(room_id: String, axis: String, across: int, start: int, count: int, swap := {}) -> void:
	ceiling_run(room_id, axis, across, start, _pieces(count, "duct_riser", "duct_straight", "duct_end_grille", swap))


func pipe_run(room_id: String, axis: String, across: int, start: int, count: int, valves := []) -> void:
	var swap := {}
	for i: int in valves:
		swap[i] = "pipe_valve"
	ceiling_run(room_id, axis, across, start, _pieces(count, "pipe_bundle_straight", "pipe_bundle_straight", "pipe_bundle_straight", swap))


func tray_run(room_id: String, axis: String, across: int, start: int, count: int, sags := []) -> void:
	var swap := {}
	for i: int in sags:
		swap[i] = "cable_tray_sag"
	ceiling_run(room_id, axis, across, start, _pieces(count, "cable_tray_straight", "cable_tray_straight", "cable_tray_straight", swap))


## A suspended ceiling: 20-voxel tile pieces over cols x rows cells from (ox, oz), leaving out the
## `holes` (Vector2i cells, where the troffers go: LabBuilder hangs them after the props) and
## swapping in missing and hanging tiles.
func tile_grid(room_id: String, ox: int, oz: int, cols: int, rows: int, holes := [], missing := [], hanging := []) -> void:
	for row in rows:
		for col in cols:
			var cell := Vector2i(col, row)
			if cell in holes:
				continue
			var piece := "ceiling_tile_missing" if cell in missing else ("ceiling_tile_hanging" if cell in hanging else "ceiling_tile_grid")
			ceiling_at(room_id, piece, ox + 20 * col, oz + 20 * row)


## Mycelium nodes evenly along a wall from f0 to f1 (fractions along it), at heights cycling
## through ups.
func vein(room_id: String, side: String, f0: float, f1: float, count: int, ups: Array, fields: Dictionary) -> void:
	for i in count:
		var f := lerpf(f0, f1, float(i) / maxf(count - 1, 1))
		mycelium(room_id, f, f, fields, int(ups[i % ups.size()]), side)


## Mycelium nodes on a room's ceiling at fractions [fx, fz] (hanging tendrils with sag).
func tendrils(room_id: String, spots: Array, fields: Dictionary) -> void:
	for s: Array in spots:
		mycelium(room_id, s[0], s[1], fields, 0, "ceiling")


func poster(room_id: String, side: String, along: int, floor_key: String, up := 10) -> void:
	wall_at(room_id, "poster_fung_" + POSTERS[floor_key][0], side, along, up, {use = "note", text = POSTERS[floor_key][1]})


## A third of containment's furniture (every third of the twinned kinds, in layout order) turns
## into its overgrown twin.
func _overgrow(room_ids: Array) -> int:
	var seen := 0
	var swapped := 0
	for p: Dictionary in props:
		if p.room not in room_ids or p.name not in OVERGROWN or p.get("ceiling", false):
			continue
		seen += 1
		if seen % 3 == 1:
			p.name = p.name + "_overgrown"
			swapped += 1
	return swapped


static func _many(prop_name: String, count: int) -> Array:
	var out := []
	for i in count:
		out.append(prop_name)
	return out


## A ceiling spawner's camouflage (or a decoy's): two parallel runs of duct_insulated, `count`
## modules each along x from ox, at oz and oz + gap (gap 0: one run), with a service hatch between
## them at hatch_x (none when hatch_x < 0).
func lagging(room_id: String, ox: int, oz: int, count: int, gap: int, hatch_x := -1) -> void:
	ceiling_run(room_id, "x", oz, ox, _many("duct_insulated", count))
	if gap > 0:
		ceiling_run(room_id, "x", oz + gap, ox, _many("duct_insulated", count))
	if hatch_x >= 0:
		ceiling_at(room_id, "service_hatch", hatch_x, oz + 11)


func _dress_g() -> void:
	# The gatehouse: a guard desk at the back, a turnstile bank and a metal detector south of the
	# walk from the yard to the blast door, the panel by the yard, a badge reader by the blast door.
	duct_run("gatehouse", "z", 46, 4, 10)
	ceiling_at("gatehouse", "security_camera", 2, 100, P.EAST)
	prop_at("gatehouse", "guard_desk", 19, 103, P.NORTH, {id = "guard_desk_g"})
	prop_at("gatehouse", "executive_chair", 27, 116, P.NORTH)
	prop_at("gatehouse", "turnstile", 14, 88, P.WEST)
	prop_at("gatehouse", "turnstile", 14, 99, P.WEST)
	prop_at("gatehouse", "metal_detector_gate", 25, 88, P.WEST)
	prop_at("gatehouse", "gatehouse_panel", 0, 2, P.EAST)
	wall_at("gatehouse", "badge_reader", "e", 42, 12)
	wall_at("gatehouse", "extinguisher_cabinet", "w", 100, 1)
	poster("gatehouse", "e", 60, "g")
	# The yard: a barrier arm across the lorry lane, bollards by the gatehouse door, the mascot.
	prop_at("yard", "barrier_arm", 80, 82, P.NORTH)
	prop_at("yard", "bollard", 108, 30)
	prop_at("yard", "bollard", 108, 92)
	prop_at("yard", "mascot_standee", 100, 104, P.WEST, {use = "note", text = "FUNGI THE FUNG AI MUSHROOM says: WELCOME TO SITE 3!\n(Fungi is a Fung AI asset. Hugging Fungi is $15.)"})
	prop_at("yard", "dumpster", 2, 60, P.EAST)


func _dress_0() -> void:
	# The alarm pull: a fire door from the bathrooms to the cargo lift lobby releases (a shortcut
	# back from the break room to the lift); after the outbreak it also calls a horde.
	door("bathrooms", "lift_lobby", "door_single", {id = "d_0_fire", locked = true})
	wall_at("lobby", "alarm_pull", "s", 20, 12, {id = "alarm_lobby", on_use = "t_0_alarm"})
	trigger("t_0_alarm", "lobby", "unlock=d_0_fire,open=d_0_fire", {nowhere = true, fx = 0.1, fz = 0.9})
	wall_at("lift_lobby", "corkboard_small", "s", 2, 14, {use = "note", text = "FIRE DOOR (to the bathrooms): opens on the fire alarm only. The alarm is in the lobby. Pulling it is billed."})
	# Lobby: the payroll ticker over the reception desk, a duct with a branch, signs and posters.
	wall_at("lobby", "payroll_ticker", "n", 49, 18, {id = "payroll_ticker"})
	duct_run("lobby", "x", 2, 4, 11, {5: "duct_tee"})
	ceiling_run("lobby", "z", 54, 12, ["duct_straight", "duct_straight", "duct_straight", "duct_end_grille"])
	ceiling_at("lobby", "security_camera", 117, 2, P.SOUTH)
	wall_at("lobby", "extinguisher_cabinet", "s", 30, 1)
	wall_over("lobby", "exit_sign", "w", 170)
	wall_at("lobby", "room_plate_101", "w", 48, 14)
	poster("lobby", "n", 14, "f0")
	poster("lobby", "s", 100, "f0")
	prop_at("lobby", "wet_floor_sign", 31, 100)
	# Admin's suspended ceilings: 20-voxel tiles with the middle cell left for the troffer.
	for id: String in ["stair_lobby_0", "lift_lobby", "security", "manager"]:
		tile_grid(id, 0, 0, 3, 3, [Vector2i(1, 1)], [Vector2i(2, 0)] if id != "manager" else [], [Vector2i(0, 2)] if id == "security" else [])
	wall_at("stair_lobby_0", "evac_map", "n", 20, 12)
	# Security: the executive suite Fung keeps for himself.
	prop_at("security", "trophy_shelf", 40, 0, P.SOUTH, {use = "note", text = "EMPLOYEE OF THE MONTH: Guy Fung (x 31)"})
	prop_at("security", "drinks_cabinet", 4, 0, P.SOUTH)
	prop_at("security", "globe", 2, 44)
	prop_at("manager", "potted_tree", 2, 2)
	prop_at("manager", "safe", 50, 2, P.SOUTH)
	# The open-plan office.
	duct_run("open_office", "z", 112, 4, 9)
	prop_at("open_office", "printer_station", 60, 115, P.NORTH)
	prop_at("open_office", "filing_cabinet_4", 2, 100, P.EAST)
	prop_at("open_office", "filing_cabinet_4", 2, 106, P.EAST)
	prop_at("open_office", "coat_rack", 2, 115)
	prop_at("open_office", "potted_tree", 115, 2)
	prop_at("open_office", "cubicle_partition_straight", 20, 44, P.NORTH)
	prop_at("open_office", "cubicle_partition_straight", 60, 44, P.NORTH)
	wall_at("open_office", "org_chart", "n", 85, 12, {text = "FUNG AI ORG CHART\nGuy Fung, CEO\n  Guy Fung, CFO\n    Guy Fung, Head of People\n      You (night shift)"})
	wall_at("open_office", "employee_board", "e", 40, 12, {text = "EMPLOYEE OF THE MONTH\nJanuary: Clone #4\nFebruary: Clone #9\nMarch: Clone #9 (posthumous)"})
	wall_at("open_office", "mission_statement", "e", 80, 14, {text = "OUR MISSION: to make the model think, so that you don't have to."})
	# The break room: the cafeteria counter, the priced vending machines, a cot, the operator wall by
	# the first vat.
	duct_run("break_room", "x", 2, 4, 8)
	prop_at("break_room", "counter_serving", 92, 2, P.SOUTH, {id = "counter_break"})
	prop("break_room", "tray_stack", 0.1, 0.5, P.SOUTH, {on = "counter_break"})
	prop_at("break_room", "vending_machine", 117, 20, P.WEST, {price = 4, contents = "snack"})
	prop_at("break_room", "vending_machine_glass", 117, 31, P.WEST, {price = 5, contents = "snack"})
	prop_at("break_room", "cot", 8, 44)
	wall_at("break_room", "operator_photo_wall", "s", 6, 4, {id = "operator_wall", text = "NIGHT SHIFT OPERATORS, SITE 3\n\nThirty-one photos. Thirty-one of them are you. The newest one is still blank, with a name tag: yours."})
	poster("break_room", "s", 108, "f0")
	duct_run("training", "x", 2, 4, 8)
	poster("training", "w", 40, "f0")
	pipe_run("grow_0", "x", 2, 4, 11, [5])
	# Bathrooms: three stalls along the west wall, urinals, a sink and a dryer, an extractor fan.
	for i in 3:
		prop_at("bathrooms", "toilet_stall", 0, 14 + 10 * i, P.EAST)
	wall_at("bathrooms", "urinal", "s", 3, 4)
	wall_at("bathrooms", "urinal", "s", 9, 4)
	wall_at("bathrooms", "sink_mirror", "w", 47, 8)
	wall_at("bathrooms", "hand_dryer", "s", 51, 10)
	ceiling_at("bathrooms", "extractor_fan", 46, 46)
	prop_at("cubby", "mop_bucket", 20, 30)


func _dress_m1() -> void:
	duct_run("dock", "z", 2, 4, 11, {6: "duct_drip"})
	# A crate on a chain over the dock: shoot the chain on the horde from the substrate store.
	ceiling_at("dock", "crate_hanging", 44, 50, P.NORTH, {id = "crate_hanging_dock"})
	wall_at("dock", "extinguisher_cabinet", "e", 90, 1)
	poster("dock", "e", 105, "m1")
	duct_run("substrate_store", "x", 2, 30, 8)
	ceiling_at("substrate_store", "vent_diffuser", 86, 44)
	pipe_run("grow_hall_1", "z", 2, 20, 14, [6])
	ceiling_at("grow_hall_1", "vent_diffuser", 58, 90)
	lagging("grow_hall_1", 70, 100, 3, 0) # A decoy: lagging with nothing behind it.
	duct_run("wet_lab", "x", 2, 4, 9)
	prop_at("wet_lab", "gas_cylinder", 4, 122)
	prop_at("wet_lab", "gas_cylinder", 9, 122)
	prop_at("wet_lab", "gas_cylinder_oxygen", 14, 122)
	wall_at("wet_lab", "eyewash_station", "s", 24, 8)
	poster("wet_lab", "e", 20, "m1")
	duct_run("incubation", "x", 2, 4, 9, {4: "duct_insulated", 5: "duct_insulated"})
	duct_run("clean_room", "x", 2, 4, 5)
	for i in 2:
		prop_at("bathroom_m1", "toilet_stall", 50, 4 + 10 * i, P.WEST)
	wall_at("bathroom_m1", "sink_mirror", "n", 25, 8)
	wall_at("bathroom_m1", "urinal", "n", 40, 4)
	ceiling_at("bathroom_m1", "extractor_fan", 6, 46)
	pipe_run("grow_hall_2", "x", 2, 4, 11, [5])
	# Past the outbreak: the mycology office barricaded and turned over.
	prop_at("mycology", "barricade_door", 40, 0, P.SOUTH)
	prop_at("mycology", "overturned_table", 40, 44)
	wall_at("mycology", "scratched_note", "w", 48, 12, {text = "it tapped back in my voice\nit tapped back in my voice\nit tapped back in my"})
	duct_run("clone_bay_m1", "z", 48, 4, 5)
	prop_at("clone_bay_m1", "clone_vat_occupied", 4, 34, P.NORTH, {use = "note", text = "CLONE #30. Grown 02:14. Not yet billed."})
	wall_over("clone_bay_m1", "exit_sign", "w", rooms.stair_m1_m2.top_center)
	# Mycelium, light: two small clusters hanging round ceiling vents, a film in grow hall 2.
	var small := {radius = 2.5, reach = 18, links = 2, sag = 0.5, glow = 0.35}
	tendrils("substrate_store", [[0.72, 0.8], [0.66, 0.72], [0.79, 0.7]], small)
	tendrils("grow_hall_1", [[0.44, 0.5], [0.52, 0.45], [0.55, 0.54]], small)
	mycelium("grow_hall_2", 0.37, 0.5, {radius = 2.0, links = 0, glow = 0.4, spread = 26})
	mycelium("grow_hall_2", 0.45, 0.93, {radius = 2.0, links = 0, glow = 0.4, spread = 20})


func _dress_m2() -> void:
	duct_run("stair_lobby_m2", "x", 2, 4, 5)
	wall_at("stair_lobby_m2", "extinguisher_cabinet", "n", 2, 1)
	wall_at("stair_lobby_m2", "evac_map", "s", 2, 12)
	wall_over("stair_lobby_m2", "exit_sign", "w", rooms.stair_m1_m2.bottom_center)
	wall_at("network_closet", "patch_panel", "w", 10, 12)
	prop_at("network_closet", "ups_cabinet", 30, 2)
	# The server hall: four rows of racks in hot and cold aisles, CRAC units, lifted floor tiles,
	# cable trays down the north side, a duct (lagged in the middle, a decoy) down the south.
	var kinds := ["server_rack_open", "server_rack_open", "server_rack_closed", "server_rack_open", "server_rack_dead", "server_rack_closed"]
	var n := 0
	for row in 4:
		for group in (4 if row < 3 else 2):
			for k in 3:
				prop_at("server_hall", kinds[n % kinds.size()], 20 + 55 * group + 10 * k, 14 + 26 * row, P.SOUTH if row % 2 == 0 else P.NORTH)
				n += 1
	prop_at("server_hall", "crac_unit", 235, 40, P.WEST)
	prop_at("server_hall", "crac_unit", 2, 70, P.EAST)
	prop_at("server_hall", "cable_cage", 60, 115, P.NORTH)
	prop_at("server_hall", "tape_library", 160, 115, P.NORTH)
	prop_at("server_hall", "ups_cabinet", 237, 70, P.WEST)
	prop_at("server_hall", "floor_tile_lifted", 60, 26)
	prop_at("server_hall", "floor_tile_lifted", 150, 54)
	prop_at("server_hall", "floor_tile", 100, 28)
	prop_at("server_hall", "floor_tile", 160, 56)
	wall_at("server_hall", "patch_panel", "n", 100, 12)
	wall_at("server_hall", "room_plate_204", "e", 62, 14)
	tray_run("server_hall", "x", 2, 15, 18, [4, 11, 16])
	duct_run("server_hall", "x", 113, 60, 10, {3: "duct_insulated", 4: "duct_insulated"})
	poster("server_hall", "w", 70, "m2")
	# The cooling plant: tanks, pumps, a pipe gallery, the gas cylinders, pipes overhead, and the
	# ceiling cloud's lagging (s_m2_cool_2) with its hatch.
	prop_at("cooling_plant", "water_tank_round", 22, 30)
	prop_at("cooling_plant", "water_tank_round", 89, 30)
	prop_at("cooling_plant", "pump_housing", 95, 56, P.WEST)
	prop_at("cooling_plant", "pump_housing", 95, 72, P.WEST)
	prop_at("cooling_plant", "valve_stand", 40, 60)
	prop_at("cooling_plant", "compressor", 40, 2, P.SOUTH)
	for i in 3:
		prop_at("cooling_plant", "pipe_gallery_segment", 115, 63 + 10 * i, P.EAST)
	prop_at("cooling_plant", "gas_cylinder", 0, 24)
	prop_at("cooling_plant", "gas_cylinder", 0, 29)
	prop_at("cooling_plant", "gas_cylinder_oxygen", 0, 34)
	pipe_run("cooling_plant", "x", 2, 4, 12, [3, 8])
	pipe_run("cooling_plant", "x", 113, 4, 12, [6])
	lagging("cooling_plant", 37, 46, 5, 24, 57)
	# Inference, electrical, ops, the archive.
	duct_run("inference_lab", "x", 2, 4, 8)
	wall_at("electrical", "breaker_panel", "n", 57, 10, {id = "breaker_electrical"})
	wall_at("electrical", "fuse_box", "n", 70, 12)
	wall_at("electrical", "junction_box", "s", 30, 14)
	prop_at("electrical", "transformer", 67, 48, P.NORTH)
	tray_run("electrical", "x", 2, 4, 10, [5])
	tray_run("ops", "z", 2, 4, 11, [3, 8])
	prop_at("ops", "printer_station", 53, 46, P.WEST, {id = "printer_ops", text = "PRINT JOB 1 of 1 (Ops)\n\nINCIDENT REPORT, 02:14\nCause: model migration.\nInjuries: all.\nCost centre: night shift.\n\n(The toner was billed to you.)"})
	prop_at("ops", "overturned_desk", 18, 100, P.NORTH)
	duct_run("archive", "x", 2, 60, 6)
	prop_at("archive", "tape_library", 110, 2, P.SOUTH)
	prop_at("archive", "tape_library", 110, 20, P.NORTH)
	wall_at("archive", "scratched_note", "s", 20, 12, {text = "THE TAPES ARE WARM"})
	# The bullpen: printers and filing cabinets, a radio on the drawer desk.
	prop_at("bullpen", "copier", 52, 0, P.SOUTH)
	prop_at("bullpen", "filing_cabinet_4", 36, 54, P.NORTH)
	prop_at("bullpen", "filing_cabinet_4", 42, 54, P.NORTH)
	prop_at("bullpen", "filing_cabinet_2", 48, 54, P.NORTH)
	prop("bullpen", "radio", 0.8, 0.5, P.NORTH, {on = "drawer_bullpen"})
	duct_run("bullpen", "x", 2, 4, 6, {2: "duct_insulated", 3: "duct_insulated"})
	poster("bullpen", "s", 84, "m2", 6)
	prop_at("break_room_2", "overturned_table", 6, 44)
	prop_at("break_room_2", "cot", 38, 50)
	prop_at("break_room_2", "barricade_door", 46, 0, P.SOUTH)
	# The airlock's decon racks.
	prop_at("airlock", "hazmat_suit_rack", 8, 55, P.NORTH)
	prop_at("airlock", "hazmat_locker", 0, 46, P.EAST)
	prop_at("airlock", "sprayer", 25, 46, P.WEST)
	wall_at("airlock", "hazmat_sign", "s", 11, 24)
	duct_run("airlock", "z", 2, 4, 5)
	# Mycelium, veins: along the server hall's north wall and the east end of its south wall, round
	# the inference lab's walls; one hanging cluster in the cooling plant.
	var veins := {radius = 2.5, reach = 30, links = 2, glow = 0.7}
	vein("server_hall", "n", 0.08, 0.64, 8, [8, 18, 12, 24], veins)
	# East of the inference lab: nodes on the two faces of one wall would link through it.
	vein("server_hall", "s", 0.78, 0.95, 3, [10, 20], veins)
	vein("inference_lab", "n", 0.04, 0.28, 3, [10, 20], veins)
	vein("inference_lab", "n", 0.72, 0.96, 3, [20, 10], veins)
	vein("inference_lab", "s", 0.62, 0.92, 3, [12, 22], veins)
	tendrils("cooling_plant", [[0.88, 0.18], [0.95, 0.25], [0.86, 0.12], [0.94, 0.33]], {radius = 3.0, reach = 16, links = 3, sag = 0.9, glow = 0.55})


func _dress_m3() -> void:
	prop_at("decon", "emergency_shower", 0, 49)
	prop_at("decon", "boot_wash", 10, 46, P.NORTH)
	duct_run("decon", "z", 2, 12, 4)
	wall_over("decon", "exit_sign", "e", rooms.stair_m2_m3.bottom_center)
	poster("decon", "s", 44, "m3", 12)
	# The gallery: a duct south of the root wall, tendrils, a barricade, an overturned table.
	duct_run("gallery", "z", 46, 72, 11)
	prop_at("gallery", "barricade_door", 0, 140, P.EAST)
	prop_at("gallery", "overturned_table", 22, 150)
	wall_at("gallery", "scratched_note", "e", 120, 14, {text = "DON'T GO NORTH\nIT GREW OVER CHAMBER 1"})
	prop_at("sample_room", "skeleton_suit", 0, 37, P.NORTH, {use = "note", text = "A name badge on the lanyard: SURVEY TEAM, YEAR 1."})
	prop_at("sample_room", "skeleton_overgrown", 36, 42)
	prop_at("sample_room", "cocoon", 52, 52)
	prop_at("tc2", "cocoon", 2, 2)
	# Dissection: the table, the morgue wall, a body bag, the ceiling cloud's lagging (s_m3_diss_1).
	prop_at("dissection", "dissection_table", 23, 47, P.NORTH)
	prop_at("dissection", "morgue_drawers", 0, 28, P.EAST, {use = "note", text = "MORGUE: 12 drawers. 12 labels. 12 times the same name."})
	prop_at("dissection", "body_bag_floor", 25, 100)
	ceiling_run("dissection", "z", 8, 35, _many("duct_insulated", 4))
	ceiling_run("dissection", "z", 42, 35, _many("duct_insulated", 4))
	ceiling_at("dissection", "service_hatch", 24, 44)
	poster("dissection", "e", 70, "m3")
	ceiling_at("vault", "security_camera", 54, 2, P.WEST)
	# The ward: the cages, cocoons, a desk on its side, handrails, plates by the cells.
	duct_run("ward", "z", 0, 4, 12)
	lagging("ward", 0, 140, 3, 0) # A decoy.
	for i in 3:
		prop_at("ward", "animal_cage_stack", 54, 30 + 8 * i, P.WEST)
	prop_at("ward", "animal_cage_small", 54, 56, P.WEST)
	prop_at("ward", "cocoon", 54, 118)
	prop_at("ward", "cocoon", 54, 215)
	prop_at("ward", "overturned_desk", 22, 150, P.NORTH)
	prop_at("ward", "barricade_door", 57, 230, P.WEST)
	for i in 6:
		wall_at("ward", "handrail_straight", "e", 150 + 10 * i, 0)
	for z: int in [55, 120, 185]:
		wall_at("ward", "room_plate_b12", "w", z, 14)
	# Hazmat: suits, a bin, the floor's extinguisher.
	prop_at("hazmat", "hazmat_suit_rack", 32, 0, P.SOUTH)
	prop_at("hazmat", "biohazard_bin", 0, 46)
	wall_at("hazmat", "extinguisher_cabinet", "w", 10, 1)
	wall_at("hazmat", "hazmat_sign", "w", 44, 14)
	duct_run("hazmat", "x", 2, 4, 5)
	prop_at("tc3", "cocoon", 40, 1)
	prop_at("tc3", "cocoon", 75, 1)
	duct_run("tc3", "x", 2, 20, 9)
	lagging("tc3", 40, 48, 3, 0) # A decoy.
	wall_at("booth", "scratched_note", "n", 6, 14, {text = "400 V. IT SHOCKED BACK. I THINK IT LIKED IT."})
	wall_at("checkpoint", "evac_map", "w", 4, 12)
	prop_at("checkpoint", "barricade_door", 0, 30, P.EAST)
	ceiling_at("checkpoint", "security_camera", 52, 2, P.WEST)
	wall_over("checkpoint", "exit_sign", "e", 40)
	duct_run("checkpoint", "x", 2, 4, 5)
	prop_at("cell_4", "cocoon", 1, 17)
	prop_at("cell_5", "cocoon", 1, 5)
	# Mycelium, tendrils: hanging from the gallery's and the dissection lab's ceilings.
	# Two strands down the gallery, each side of its middle (30 apart: they don't link across).
	var hanging := {radius = 3.0, reach = 24, links = 2, sag = 1.0, glow = 0.6}
	tendrils("gallery", [[0.15, 0.526], [0.15, 0.632], [0.15, 0.737], [0.65, 0.605], [0.65, 0.71], [0.65, 0.816]], hanging)
	tendrils("dissection", [[0.15, 0.68], [0.85, 0.72], [0.18, 0.86], [0.82, 0.9], [0.5, 0.97]], hanging)
	# A root wall across the gallery north of the chamber 2 door: the optional side passage to
	# chamber 1's window (and the sample room) has to be burnt or shot through.
	var root := {radius = 6.5, reach = 12, links = 4, glow = 0.25}
	for x: int in [5, 15, 25, 35, 45, 55]:
		for y: int in [5, 16, 27]:
			if y == 27 and x in [25, 35]:
				continue # Clear of the emergency fixture over the middle.
			mycelium("gallery", x / 60.0, 64.0 / 190.0, root, y)
	# A third of the furniture is overgrown.
	_overgrow(["decon", "gallery", "tc1", "sample_room", "tc2", "dissection", "vault", "ward", "cell_2", "cell_3", "cell_4", "cell_5",
			"hazmat", "tc3", "booth", "checkpoint", "cage_shaft"])


func _dress_dig() -> void:
	# The drift: timber frames, a cart and its rails, lanterns, a cocoon.
	for x: int in [35, 60, 120, 165]:
		prop_at("drift", "timber_support_frame", x, 1, P.EAST)
	for i in 4:
		prop_at("drift", "rail_straight", 125 + 10 * i, 15)
	prop_at("drift", "mine_cart", 128, 2, P.NORTH)
	wall_at("drift", "lantern", "n", 50, 16)
	wall_at("drift", "lantern", "s", 140, 16)
	prop_at("drift", "cocoon", 178, 2)
	# The pump room and the core lab.
	prop_at("pump_room", "pump_housing", 0, 26, P.EAST)
	prop_at("pump_room", "pump_housing", 0, 40, P.EAST)
	prop_at("pump_room", "valve_stand", 10, 30)
	pipe_run("pump_room", "x", 2, 4, 5, [2])
	poster("pump_room", "w", 4, "dig")
	duct_run("core_lab", "x", 2, 4, 5)
	# Walking up to the cavern door: the colony's veins swell (Mycelium.pulse).
	trigger("t_m4_approach", "core_lab", "pulse=0.8", {fx = 0.12, fz = 0.5, w = 14, d = 40})
	# The cavern: mine ventilation lagging over the ceiling clouds (s_m4_cav_3), stalactites and
	# stalagmites off the east ledge, cocoons hanging and standing, lanterns along the ledge.
	ceiling_run("cavern", "z", 40, 97, _many("duct_insulated", 6))
	ceiling_run("cavern", "z", 75, 97, _many("duct_insulated", 6))
	ceiling_at("cavern", "stalactite_large", 20, 40)
	ceiling_at("cavern", "stalactite_medium", 100, 60)
	ceiling_at("cavern", "stalactite_small", 15, 200)
	ceiling_at("cavern", "stalactite_large", 105, 210)
	prop_at("cavern", "stalagmite_large", 5, 120)
	prop_at("cavern", "stalagmite_medium", 30, 100)
	prop_at("cavern", "stalagmite_small", 8, 170)
	ceiling_at("cavern", "rope_hanging", 100, 150)
	ceiling_at("cavern", "cocoon", 30, 60)
	ceiling_at("cavern", "cocoon", 95, 180)
	prop_at("cavern", "cocoon", 1, 30)
	prop_at("cavern", "cocoon", 1, 248)
	for z: int in [70, 120, 170]:
		wall_at("cavern", "lantern", "e", z, 16)
	prop_at("survey_tunnel", "cocoon", 115, 17)
	# The generator hall: a crate on a chain over the north mouth's way in, a pallet under the
	# gantry by the south mouth, the ceiling clouds' lagging (s_m4_gen_c), cocoons, the exit sign
	# over the freight elevator.
	ceiling_at("generator_hall", "crate_hanging", 40, 15, P.NORTH, {id = "crate_hanging_gen"})
	ceiling_at("generator_hall", "pallet_hanging", 70, 100, P.NORTH, {id = "pallet_hanging_gen"})
	ceiling_at("generator_hall", "chain_hoist", 82, 102)
	ceiling_run("generator_hall", "x", 112, 60, _many("gantry_rail", 5))
	lagging("generator_hall", 37, 46, 5, 24, 57)
	ceiling_at("generator_hall", "cocoon", 10, 60)
	ceiling_at("generator_hall", "cocoon", 112, 40)
	wall_at("generator_hall", "extinguisher_cabinet", "w", 20, 1)
	wall_over("generator_hall", "exit_sign", "e", 365, 26)
	# Mycelium, dense and bright: every wall of the cavern (high on the east, so the ledge stays
	# clear), its ceiling, a ring of root round the mother's dais (open to the east), the drift,
	# the burrows, the tunnels, the mouths and high on the generator hall's walls.
	# Rows of nodes about 21 apart, 12 up and down: each links to the next and to the row above.
	var dense := {radius = 4.0, reach = 26, links = 3, glow = 0.9, spread = 6}
	vein("cavern", "w", 0.04, 0.96, 12, [10, 22], dense)
	vein("cavern", "w", 0.04, 0.96, 12, [36, 48], dense)
	vein("cavern", "n", 0.08, 0.92, 6, [12, 24], dense)
	vein("cavern", "n", 0.08, 0.92, 6, [38, 50], dense)
	vein("cavern", "e", 70.0 / 255.0, 190.0 / 255.0, 7, [44, 56], dense)
	vein("cavern", "s", 0.6, 0.95, 3, [16, 28], dense)
	# Hanging from the roof in clumps (clear of the lagging over the middle).
	tendrils("cavern", [[0.2, 0.15], [0.36, 0.17], [0.3, 0.24], [0.75, 0.2], [0.8, 0.28], [0.25, 0.75], [0.4, 0.8], [0.3, 0.86],
			[0.8, 0.8], [0.65, 0.85]], {radius = 5.0, reach = 26, links = 2, sag = 0.6, glow = 0.9})
	var ext := _extent("cavern")
	for i in 8:
		var angle := TAU * (i + 0.5) / 8.0
		if cos(angle) > 0.7:
			continue # The east side stays open: the way up onto the dais.
		# Up 9: over the dais' lower step, so the links between them run through air round it.
		mycelium("cavern", 0.5 + 25.0 * cos(angle) / ext.x, 0.5 + 25.0 * sin(angle) / ext.z, {radius = 5.0, reach = 20, links = 2, glow = 0.6, spread = 10}, 9)
	# The drift's two walls are 25 apart: opposite nodes sit at different heights (26.9 apart), out
	# of each other's reach, so nothing spans the way through.
	var drift := {radius = 3.0, reach = 25.5, links = 2, glow = 0.85}
	vein("drift", "n", 25.0 / 190.0, 70.0 / 190.0, 3, [6, 16], drift)
	vein("drift", "s", 25.0 / 190.0, 70.0 / 190.0, 3, [16, 6], drift)
	vein("drift", "n", 125.0 / 190.0, 170.0 / 190.0, 3, [16, 6], drift)
	vein("drift", "s", 125.0 / 190.0, 170.0 / 190.0, 3, [6, 16], drift)
	vein("burrow_n", "n", 0.2, 0.8, 3, [5, 14], drift)
	vein("burrow_s", "s", 0.2, 0.8, 3, [5, 14], drift)
	vein("survey_tunnel", "s", 0.56, 0.92, 3, [6, 16], drift)
	vein("gen_tunnel", "n", 22.0 / 60.0, 38.0 / 60.0, 2, [8, 18], drift)
	vein("gen_tunnel", "s", 22.0 / 60.0, 38.0 / 60.0, 2, [18, 8], drift)
	vein("mouth_n", "n", 0.2, 0.8, 3, [6, 14], drift)
	vein("mouth_e", "e", 0.2, 0.8, 3, [6, 14], drift)
	vein("mouth_s", "s", 0.2, 0.8, 3, [6, 14], drift)
	var high := {radius = 3.5, reach = 26, links = 2, glow = 0.85}
	vein("generator_hall", "w", 0.15, 0.45, 3, [30, 40], high)
	vein("generator_hall", "n", 0.55, 0.9, 3, [28, 40], high)
	vein("generator_hall", "e", 0.5, 0.58, 2, [30, 42], high)
	vein("generator_hall", "s", 0.15, 0.45, 3, [28, 40], high)
