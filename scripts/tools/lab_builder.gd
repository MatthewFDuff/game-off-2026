extends RefCounted
## Builds the laboratory level from LabLayout (docs/lab-design.md): the rooms and openings as level
## structure objects (so the editor can move them), doors as door props with their doorway and slot
## openings, every prop and marker, then the painted voxels on top: stairs, ladders, the lift car,
## glass and plank patches, the cavern's pockets and glow. scripts/tools/build_laboratory.gd runs
## it from the command line; tests/laboratory_test.gd runs it into a scratch folder and checks it.

const LEVEL_NAME := "laboratory"
## How thick a glass, plank or plastic patch is (voxels), whatever the gap it closes.
const FILL_DEPTH := 5
## How far (voxels) every prop stays from a doorway, an open passage or a crawl hole, on both sides
## of the wall and to either side of it, so nothing stands in front of a way through.
const CLEARANCE := 10
## Which wall a prop's back is against, by its facing (its front points away from it).
const BACK_WALL := {0: "s", 1: "w", 2: "n", 3: "e"}
const M := preload("res://scripts/voxel/voxel_materials.gd")
const P := preload("res://scripts/world/props.gd")
const Layout := preload("res://scripts/tools/lab_layout.gd")

## After build(): the level and the world it was carved in (the caller frees the world).
var level: LevelData
var world: VoxelWorld
## Props that couldn't be placed clear of the doorways (their names and rooms), for the tests.
var dropped: Array[String] = []
var _layout
## Boxes no prop may overlap (keep_out()), and the boxes of the props placed so far.
var _keep_out: Array[AABB] = []
var _placed: Array[AABB] = []


## Builds and saves the level (tests call this with LevelData.save_dir_override set). Returns the
## save error.
func build(parent: Node) -> Error:
	_layout = Layout.new()
	_layout.build()
	var size: Vector3i = Layout.SIZE_IN_CHUNKS
	world = VoxelWorld.new()
	world.size_in_chunks = size
	world.immediate_remesh_limit = 0
	world.detach_floating = false
	parent.add_child(world)
	FacilityBuilder.make_ground(world, 2026)

	level = LevelData.new()
	level.name = LEVEL_NAME
	level.settings = LevelData.default_settings(size, "rock")
	level.settings.room_thickness = Layout.T
	level.settings.start_power = "facility"
	level.settings.start_unarmed = true # The spore shooter is in grow room 0's case (docs/story.md).
	level.settings.ambient_energy = 0.18
	level.settings.fog_density = 0.025

	for room: Dictionary in _layout.rooms.values():
		var object := LevelSchema.new_room(room.from, room.to, room.floor, room.wall, room.ceiling, room.thickness, room.order)
		object.name = room.name
		_add(room.id, object)
	for d: Dictionary in _layout.doors:
		_door(d)
	for o: Dictionary in _layout.openings:
		_opening(o)
	_keep_out = keep_out(level.objects, _layout.keep_clear)
	for p: Dictionary in _layout.props:
		_prop(p)
	for m: Dictionary in _layout.markers:
		_marker(m)
	for room: Dictionary in _layout.rooms.values():
		_lights(room)

	var structural := level.objects.values().filter(func(o: Dictionary) -> bool: return LevelSchema.is_structure(o))
	var op := LevelStructure.op({}, level.objects, structural, level.settings, world.get_size_in_voxels())
	WorldSync.run_op(world, op)
	for f: Dictionary in _layout.fills:
		world.fill_box(f.from, f.to, f.material, false)
	for s: Dictionary in _layout.spheres:
		WorldSync.run_op(world, {type = "sphere", center = Vector3(s.center), radius = s.radius, material = s.material})
	for l: Dictionary in _layout.ladders:
		_ladder(l)

	level.voxels = world.get_data()
	var error := level.save()
	return error


func _add(id: String, object: Dictionary) -> void:
	object.id = id if id != "" else level.new_id(object.get("type", object.get("kind", "o")))
	if level.objects.has(object.id):
		push_error("build_laboratory: duplicate id %s" % object.id)
	level.objects[object.id] = object


func _room(id: String) -> Dictionary:
	if not _layout.rooms.has(id):
		push_error("build_laboratory: no room %s" % id)
		return {}
	return _layout.rooms[id]


## The wall between rooms a and b: the axis it lies across, the gap [gap_lo, gap_hi) it fills and the
## span [lo, hi) the rooms share along the wall. {} if they don't face each other.
func _wall(a: Dictionary, b: Dictionary) -> Dictionary:
	for axis in [0, 2]:
		var other := 2 if axis == 0 else 0
		var lo: int = maxi(a.from[other], b.from[other])
		var hi: int = mini(a.to[other], b.to[other])
		if hi - lo < 10:
			continue
		if a.to[axis] <= b.from[axis] and b.from[axis] - a.to[axis] <= 61:
			return {axis = axis, other = other, gap_lo = a.to[axis], gap_hi = b.from[axis], lo = lo, hi = hi, a_low = true}
		if b.to[axis] <= a.from[axis] and a.from[axis] - b.to[axis] <= 61:
			return {axis = axis, other = other, gap_lo = b.to[axis], gap_hi = a.from[axis], lo = lo, hi = hi, a_low = false}
	push_error("build_laboratory: %s and %s don't share a wall" % [a.id, b.id])
	return {}


func _center(wall: Dictionary, at: float, center: int, w: int) -> int:
	var c := center if center >= 0 else int(lerp(float(wall.lo), float(wall.hi), at))
	return clampi(c, wall.lo + w / 2 + 3, wall.hi - w / 2 - 3)


func _door(d: Dictionary) -> void:
	var a := _room(d.a)
	var b := _room(d.b)
	var wall := _wall(a, b)
	if wall.is_empty():
		return
	var w: int = Layout.DOOR_SIZES[d.kind][0]
	var h: int = Layout.DOOR_SIZES[d.kind][1]
	var center := _center(wall, d.at, d.center, w)
	var y: int = d.y if d.y >= 0 else a.from.y
	var depth: int = wall.gap_hi - wall.gap_lo
	var ahead := (depth - 1) / 2
	var origin := Vector3i.ZERO
	origin[wall.axis] = wall.gap_lo + ahead
	origin[wall.other] = center - w / 2
	origin.y = y
	var facing: int = P.EAST if wall.axis == 0 else P.NORTH
	var prop := LevelSchema.new_prop(d.kind, origin, facing)
	var offset := Vector3i.ZERO
	offset[wall.other] = w if center + w / 2 + w + 2 <= wall.hi else -w
	prop.door_offset = offset
	prop.door_ahead = ahead
	prop.door_behind = depth - 1 - ahead
	prop.door_key = d.key
	prop.door_power = d.power
	prop.door_locked = d.locked
	prop.value = 0
	_add(d.id if d.id != "" else level.new_id("door"), prop)
	var size := Vector3i.ONE
	size[wall.other] = w
	size.y = h
	var through_from := origin
	through_from[wall.axis] = wall.gap_lo
	var through_to := origin + size
	through_to[wall.axis] = wall.gap_hi
	var doorway := LevelSchema.new_opening(through_from, through_to, "", "doorway", prop.id)
	doorway.room = LevelStructure.room_at(level.objects, LevelSchema.prop_box(prop))
	_add("", doorway)
	var slot := LevelSchema.new_opening(origin + offset, origin + offset + size, doorway.room, "slot", prop.id)
	_add("", slot)


func _opening(o: Dictionary) -> void:
	var a := _room(o.a)
	var b := _room(o.b)
	var wall := _wall(a, b)
	if wall.is_empty():
		return
	var center := _center(wall, o.at, o.center, o.w)
	var y: int = (o.y if o.y >= 0 else a.from.y) + int(o.up)
	var from := Vector3i.ZERO
	from[wall.axis] = wall.gap_lo
	from[wall.other] = center - o.w / 2
	from.y = y
	var to := from
	to[wall.axis] = wall.gap_hi
	to[wall.other] = center + o.w / 2
	to.y = y + o.h
	var opening := LevelSchema.new_opening(from, to, a.id, o.type)
	_add("", opening)
	if o.fill != M.AIR:
		# The patch is a board at the near face (a's side), FILL_DEPTH thick; the rest of the cut stays open.
		var patch_from := from
		var patch_to := to
		if wall.a_low:
			patch_to[wall.axis] = mini(to[wall.axis], from[wall.axis] + FILL_DEPTH)
		else:
			patch_from[wall.axis] = maxi(from[wall.axis], to[wall.axis] - FILL_DEPTH)
		_layout.fills.append({from = patch_from, to = patch_to, material = o.fill})
	if o.grate:
		var facing: int
		var origin := Vector3i.ZERO
		if wall.axis == 0:
			facing = P.WEST if wall.a_low else P.EAST
			origin.x = wall.gap_lo - 1 if wall.a_low else wall.gap_hi
		else:
			facing = P.NORTH if wall.a_low else P.SOUTH
			origin.z = wall.gap_lo - 1 if wall.a_low else wall.gap_hi
		origin[wall.other] = center - 5
		origin.y = y + 1
		_add("", LevelSchema.new_prop("vent_grate", origin, facing))


## Where props may not go: every doorway, open passage and crawl hole grown by CLEARANCE across
## and along its wall (not up), every door's slot grown by a voxel, and the extra boxes the layout
## keeps clear (stairs, ladders, the lift hatch). tests/laboratory_test.gd checks props against it.
static func keep_out(objects: Dictionary, extra: Array) -> Array[AABB]:
	var boxes: Array[AABB] = []
	for object: Dictionary in objects.values():
		if object.get("kind") != "opening":
			continue
		var box := LevelSchema.box_of(object)
		match str(object.type):
			"doorway", "hole":
				boxes.append(AABB(box.position - Vector3(CLEARANCE, 0, CLEARANCE), box.size + Vector3(CLEARANCE, 0, CLEARANCE) * 2.0))
			"slot":
				boxes.append(box.grow(1))
	for box: AABB in extra:
		boxes.append(box)
	return boxes


## A prop whose model has nothing on its bottom layer hangs off the floor (a glass case, a medkit
## station: drawn 1 m up in their own frame), so it has to be backed against a wall.
static func hangs(prop_name: String) -> bool:
	var model := P.load_prop(prop_name)
	if model.is_empty():
		return false
	var size: Vector3i = model.size
	var voxels: PackedByteArray = model.voxels
	for z in size.z:
		for x in size.x:
			if voxels[x + z * size.x * size.y] != 0:
				return false
	return true


func _prop(p: Dictionary) -> void:
	var r := _room(p.room)
	if r.is_empty():
		return
	var facing: int = p.facing
	var fields: Dictionary = p.fields
	var side: String = p.wall
	var up: int = int(p.get("up", 0))
	if side == "" and str(fields.get("on", "")) == "" and hangs(p.name):
		# Floor props that hang (cases, stations) go flush against the wall behind them.
		side = BACK_WALL[facing]
	if side != "":
		facing = {n = P.SOUTH, s = P.NORTH, e = P.WEST, w = P.EAST}[side]
	var size := Vector3i(LevelSchema.prop_box({kind = "prop", name = p.name, origin = Vector3i.ZERO, facing = facing}).size)
	var origin := Vector3i.ZERO
	var on: String = fields.get("on", "")
	if on != "":
		_add(fields.get("id", ""), _prop_object(p.name, _on_top(on, p, size, facing), facing, fields))
		return
	var free: Vector3i = r.to - r.from - size
	origin.y = r.from.y + up
	var f_along: float = p.fx if side in ["n", "s"] else p.fz
	match side:
		"":
			origin.x = r.from.x + roundi(float(p.fx) * free.x)
			origin.z = r.from.z + roundi(float(p.fz) * free.z)
		"n":
			origin.z = r.from.z
			origin.x = r.from.x + roundi(f_along * free.x)
		"s":
			origin.z = r.to.z - size.z
			origin.x = r.from.x + roundi(f_along * free.x)
		"e":
			origin.x = r.to.x - size.x
			origin.z = r.from.z + roundi(f_along * free.z)
		"w":
			origin.x = r.from.x
			origin.z = r.from.z + roundi(f_along * free.z)
	origin = origin.clamp(r.from, (r.to - size).max(r.from))
	var spot: Variant = _clear_spot(r, origin, size, side)
	if spot == null:
		push_warning("build_laboratory: dropped %s in %s, no spot clear of the doorways" % [p.name, p.room])
		dropped.append("%s in %s" % [p.name, p.room])
		return
	if spot != origin:
		print("build_laboratory: moved %s in %s by %s to clear a doorway" % [p.name, p.room, Vector3i(spot) - origin])
	_placed.append(AABB(Vector3(spot), Vector3(size)))
	_add(fields.get("id", ""), _prop_object(p.name, spot, facing, fields))


func _prop_object(prop_name: String, origin: Vector3i, facing: int, fields: Dictionary) -> Dictionary:
	var prop := LevelSchema.new_prop(prop_name, origin, facing)
	for key in fields:
		if key not in ["id", "on"]:
			prop[key] = fields[key]
	return prop


## A small prop standing on another one (fields.on, a prop id): at fractions (fx, fz) of the free
## space on that prop's footprint, on the highest voxel of the base's model under it.
func _on_top(base_id: String, p: Dictionary, size: Vector3i, facing: int) -> Vector3i:
	var base: Dictionary = level.objects.get(base_id, {})
	if base.is_empty():
		push_error("build_laboratory: %s stands on %s, which isn't placed yet" % [p.name, base_id])
		return Vector3i.ZERO
	var model := P.orient(P.load_prop(base.name), int(base.facing))
	var bsize: Vector3i = model.size
	var origin: Vector3i = base.origin
	var at := Vector3i(roundi(float(p.fx) * maxi(bsize.x - size.x, 0)), 0, roundi(float(p.fz) * maxi(bsize.z - size.z, 0)))
	var top := 0
	for z in range(at.z, mini(at.z + size.z, bsize.z)):
		for x in range(at.x, mini(at.x + size.x, bsize.x)):
			for y in range(bsize.y - 1, -1, -1):
				if model.voxels[x + y * bsize.x + z * bsize.x * bsize.y] != 0:
					top = maxi(top, y + 1)
					break
	return origin + Vector3i(at.x, top, at.z)


## origin if the prop's box there is clear of the keep-out boxes, else the nearest clear spot sliding
## along its wall (a wall prop's own wall, or the wall a floor prop is nearest), else pushed into the
## room away from that wall (floor props only), clear of the props already placed too. null: none.
func _clear_spot(r: Dictionary, origin: Vector3i, size: Vector3i, side: String) -> Variant:
	if _clear(origin, size, false):
		return origin
	var wall := side
	if wall == "":
		var gaps := {n = origin.z - r.from.z, s = r.to.z - origin.z - size.z, w = origin.x - r.from.x, e = r.to.x - origin.x - size.x}
		wall = "n"
		for k: String in gaps:
			if gaps[k] < gaps[wall]:
				wall = k
	var along := 0 if wall in ["n", "s"] else 2
	var lo: Vector3i = r.from
	var hi: Vector3i = (r.to - size).max(r.from)
	for d in range(1, r.to[along] - r.from[along]):
		for sign in [1, -1]:
			var o := origin
			o[along] += sign * d
			if o[along] >= lo[along] and o[along] <= hi[along] and _clear(o, size, true):
				return o
	if side != "":
		return null
	var across := 2 if along == 0 else 0
	var inward := 1 if wall in ["n", "w"] else -1
	for d in range(1, (r.to[across] - r.from[across]) / 2):
		var o := origin
		o[across] += inward * d
		if o[across] >= lo[across] and o[across] <= hi[across] and _clear(o, size, true):
			return o
	return null


func _clear(origin: Vector3i, size: Vector3i, check_props: bool) -> bool:
	var box := AABB(Vector3(origin), Vector3(size))
	for k: AABB in _keep_out:
		if box.intersects(k):
			return false
	if check_props:
		for b: AABB in _placed:
			if box.intersects(b):
				return false
	return true


func _marker(m: Dictionary) -> void:
	var r := _room(m.room)
	if r.is_empty():
		return
	var extent: Vector3i = r.to - r.from
	var position := Vector3(r.from) + Vector3(float(m.fx) * extent.x, float(m.up), float(m.fz) * extent.z)
	var fields: Dictionary = m.fields
	if fields.has("up"):
		position.y = r.from.y + float(fields.up)
	var marker := LevelSchema.new_marker(m.type, position, m.yaw)
	var id: String = fields.get("id", "")
	for key in fields:
		if key in ["id", "up"]:
			continue
		marker[key] = fields[key]
	if m.type == "trigger":
		var s: Vector3i = marker.size
		marker.size = Vector3i(extent.x if s.x < 0 else s.x, s.y, extent.z if s.z < 0 else s.z)
	_add(id, marker)


## Facility lights from the room's `lights` count, an emergency light on route rooms, a soft glow
## light in glow rooms (both of those are emergency-powered: they come on when the power goes).
func _lights(room: Dictionary) -> void:
	var extent: Vector3i = room.to - room.from
	var top := float(room.to.y - 4) if int(room.get("lamp_up", -1)) < 0 else float(room.from.y + int(room.lamp_up))
	var spots: Array = []
	if not room.dark and int(room.lights) > 0:
		match int(room.lights):
			1:
				spots = [Vector2(0.5, 0.5)]
			2:
				spots = [Vector2(0.5, 0.25), Vector2(0.5, 0.75)] if extent.z >= extent.x else [Vector2(0.25, 0.5), Vector2(0.75, 0.5)]
			_:
				spots = [Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.25, 0.75), Vector2(0.75, 0.75)]
	var range := clampf(maxf(extent.x, extent.z) / 10.0 * 0.8, 8.0, 18.0)
	if float(room.get("lamp_range", -1.0)) > 0.0:
		range = float(room.lamp_range)
	for s: Vector2 in spots:
		var light := LevelSchema.new_marker("light", Vector3(room.from.x + s.x * extent.x, top, room.from.z + s.y * extent.z))
		light.color = Color(1.0, 0.92, 0.78)
		light.energy = float(room.get("lamp_energy", 4.0))
		light.range = range
		_add("", light)
	if room.route:
		var red := LevelSchema.new_marker("light", Vector3(room.from.x + 0.5 * extent.x, top, room.from.z + 0.5 * extent.z))
		red.color = Color(1.0, 0.18, 0.12)
		red.energy = 2.0
		red.range = clampf(maxf(extent.x, extent.z) / 10.0 * 0.7, 6.0, 12.0)
		red.power = "emergency"
		_add("", red)
	if room.glow:
		var glow := LevelSchema.new_marker("light", Vector3(room.from.x + 0.5 * extent.x, float(room.from.y + 8), room.from.z + 0.5 * extent.z))
		glow.color = Color(0.4, 1.0, 0.75)
		glow.energy = 1.5
		glow.range = clampf(maxf(extent.x, extent.z) / 10.0, 6.0, 16.0)
		glow.power = "emergency"
		_add("", glow)


## A ladder strip (two rails and a rung every 3 voxels) flat against a wall.
func _ladder(l: Dictionary) -> void:
	var r := _room(l.room)
	var x: int = r.to.x - 1 if l.side == "e" else r.from.x
	var along: int = l.along
	for z in [along - 4, along + 3]:
		world.fill_box(Vector3i(x, l.y_from, z), Vector3i(x + 1, l.y_to, z + 1), M.LADDER)
	for y in range(l.y_from + 2, l.y_to, 3):
		world.fill_box(Vector3i(x, y, along - 3), Vector3i(x + 1, y + 1, along + 3), M.LADDER)
