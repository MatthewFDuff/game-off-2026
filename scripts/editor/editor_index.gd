extends RefCounted
## The level editor's index over the level's objects, so per-frame picking doesn't walk all of them
## (a laboratory has about 2000): each object's box worked out once per change (voxel space and
## world space), the objects by kind (in the level's order), and a coarse grid over x / z that a
## cursor ray or a prop's box only has to look into where it is.
##
## Kept in step with LevelEdits.object_set (one object at a time); rebuilt whole when it can't be
## sure it is (a new level or snapshot, the world moved, an object count that doesn't match, or a
## change LevelEdits made that this hasn't heard about yet). version goes up on every change, so
## what's derived from it (walls on a storey, openings in a wall) is cached per version.
##
## The editor's index (EditorTool sets `current`) also answers the static *_of helpers for the
## level's own objects Dictionary; anything else (a copy, a test's table) gets LevelBuild's full
## scans, so the answers are the same either way.
##
## Not a class_name: preload it (headless runs don't rescan the global class list).

## Grid cell size in meters (x and z).
const CELL := 8.0
## Objects go into every cell their box touches grown by this (meters), so a ray along a cell
## border or through a corner can't slip past one.
const MARGIN := 0.25

## The editor's index, for the static helpers (null: they do full scans).
static var current = null

var lab  # The Lab (untyped: this loads before the autoloads that Lab needs, from PropPlacement).
## Goes up whenever the indexed objects change.
var version := 0

var _level = null
var _objects: Dictionary
var _count := -1
var _edits_version := -1
var _origin := Vector3.ZERO
var _voxel := 0.0
## kind -> {id: object}, in the level's order (an object that changes goes to the end, as in
## LevelEdits._object_set).
var _kinds := {}
## Pickable objects (not rooms, not build pieces): id -> box in voxels (LevelSchema.box_of) and in
## world space; id -> place in the level's order.
var _boxes := {}
var _world_boxes := {}
var _order := {}
var _next_order := 0
## Vector2i cell -> Array of ids; id -> the cells it's in.
var _cells := {}
var _cells_of := {}
var _has_cells := false
var _lo := Vector2i.ZERO
var _hi := Vector2i.ZERO
## Derived lookups for this version.
var _cache := {}
var _cache_version := -1


func _init(of_lab = null) -> void:
	lab = of_lab


## Listens to the level's edits; call once the Lab is ready.
func attach() -> void:
	if lab and lab.edits and not lab.edits.object_set.is_connected(_on_object_set):
		lab.edits.object_set.connect(_on_object_set)


func detach() -> void:
	if lab and is_instance_valid(lab) and lab.edits and lab.edits.object_set.is_connected(_on_object_set):
		lab.edits.object_set.disconnect(_on_object_set)
	if current == self:
		current = null


## Rebuilds if the level, the world's placement or the objects changed behind its back.
func sync() -> void:
	if lab == null or not is_instance_valid(lab) or lab.level == null:
		if _level != null:
			_clear()
			_level = null
			version += 1
		return
	var level = lab.level
	var world: Node3D = lab.world
	if not is_same(level, _level) or not is_same(level.objects, _objects) or level.objects.size() != _count \
			or world.global_position != _origin or world.voxel_size != _voxel or _edits_changed():
		_rebuild()


## True when objects is the level's own (and this is in step with it): the index's answers are
## LevelBuild's for it.
func covers(objects: Dictionary) -> bool:
	if not is_same(objects, _objects):
		return false
	sync()
	return is_same(objects, _objects)


func _edits_changed() -> bool:
	return lab.edits != null and "objects_version" in lab.edits and lab.edits.objects_version != _edits_version


func _clear() -> void:
	_objects = {}
	_count = -1
	_kinds.clear()
	_boxes.clear()
	_world_boxes.clear()
	_order.clear()
	_cells.clear()
	_cells_of.clear()
	_has_cells = false
	_cache.clear()


func _rebuild() -> void:
	_clear()
	_level = lab.level
	_objects = _level.objects
	_origin = lab.world.global_position
	_voxel = lab.world.voxel_size
	_next_order = 0
	for object: Dictionary in _objects.values():
		_add(object)
	_count = _objects.size()
	if lab.edits and "objects_version" in lab.edits:
		_edits_version = lab.edits.objects_version
	version += 1


func _on_object_set(remove_id: String, object: Dictionary) -> void:
	if lab == null or lab.level == null or not is_same(lab.level, _level) or not is_same(lab.level.objects, _objects):
		_count = -1 # Not the level indexed: rebuild on the next sync.
		return
	if remove_id != "":
		_remove(remove_id)
	if not object.is_empty():
		_remove(str(object.id))
		_add(object)
	_count = _objects.size()
	if lab.edits and "objects_version" in lab.edits:
		_edits_version = lab.edits.objects_version
	version += 1


func _add(object: Dictionary) -> void:
	var id := str(object.get("id", ""))
	var kind := str(object.get("kind", ""))
	_kinds.get_or_add(kind, {})[id] = object
	_order[id] = _next_order
	_next_order += 1
	if kind == "room" or LevelBuild.is_build(object):
		return
	var box := LevelSchema.box_of(object)
	var world_box := AABB(_origin + box.position * _voxel, box.size * _voxel)
	_boxes[id] = box
	_world_boxes[id] = world_box
	var lo := _cell(world_box.position - Vector3.ONE * MARGIN)
	var hi := _cell(world_box.end + Vector3.ONE * MARGIN)
	var cells: Array[Vector2i] = []
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			var c := Vector2i(x, z)
			_cells.get_or_add(c, []).append(id)
			cells.append(c)
	_cells_of[id] = cells
	if not _has_cells:
		_lo = lo
		_hi = hi
		_has_cells = true
	else:
		_lo = _lo.min(lo)
		_hi = _hi.max(hi)


func _remove(id: String) -> void:
	if not _order.has(id):
		return
	_order.erase(id)
	for kind: String in _kinds:
		_kinds[kind].erase(id)
	_boxes.erase(id)
	_world_boxes.erase(id)
	for c: Vector2i in _cells_of.get(id, []):
		var list: Array = _cells.get(c, [])
		list.erase(id)
		if list.is_empty():
			_cells.erase(c)
	_cells_of.erase(id)


func _cell(world_point: Vector3) -> Vector2i:
	return Vector2i(floori((world_point.x - _origin.x) / CELL), floori((world_point.z - _origin.z) / CELL))


# --- Queries (call sync first, or go through covers) -------------------------------------------------

## The level's objects of a kind ({id: object}, in the level's order). Don't change it.
func of_kind(kind: String) -> Dictionary:
	return _kinds.get(kind, {})


## A pickable object's box in voxels (LevelSchema.box_of); AABB() for rooms and build pieces.
func box(id: String) -> AABB:
	return _boxes.get(id, AABB())


## The pickable object (not a room, not a build piece) whose box the ray (world space) meets first:
## {id, distance} (id "" for none). skip: an id to leave out; openings: room openings count;
## cut_layer >= 0: boxes from that voxel layer up are cut away. Ties go to the earlier object in the
## level's order, as a walk over all of them would.
func pick(from: Vector3, direction: Vector3, skip: String, openings: bool, cut_layer := -1) -> Dictionary:
	var best_id := ""
	var best := INF
	var best_order := 0
	var seen := {}
	for c in _ray_cells(from, direction):
		for id: String in _cells.get(c, []):
			if seen.has(id):
				continue
			seen[id] = true
			if id == skip:
				continue
			if not openings and _kinds.get("opening", {}).has(id):
				continue
			var voxel_box: AABB = _boxes[id]
			if cut_layer >= 0 and voxel_box.position.y >= cut_layer:
				continue
			var world_box: AABB = _world_boxes[id]
			var hit = world_box.intersects_ray(from, direction)
			if hit == null:
				continue
			var distance := from.distance_to(hit)
			var order: int = _order[id]
			if distance < best or (distance == best and order < best_order):
				best = distance
				best_id = id
				best_order = order
	return {id = best_id, distance = best}


## Whether a box (voxels) overlaps a prop other than ignore (PropPlacement's rule).
func hits_prop(box: AABB, ignore: String) -> bool:
	var props: Dictionary = _kinds.get("prop", {})
	if props.is_empty():
		return false
	var world_box := AABB(_origin + box.position * _voxel, box.size * _voxel)
	var lo := _cell(world_box.position - Vector3.ONE * MARGIN)
	var hi := _cell(world_box.end + Vector3.ONE * MARGIN)
	if _has_cells:
		lo = lo.max(_lo)
		hi = hi.min(_hi)
	var seen := {}
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			for id: String in _cells.get(Vector2i(x, z), []):
				if seen.has(id) or id == ignore or not props.has(id):
					continue
				seen[id] = true
				var prop_box: AABB = _boxes[id]
				if prop_box.intersects(box):
					return true
	return false


## The grid cells the ray's x / z track crosses inside the indexed area, in order.
func _ray_cells(from: Vector3, direction: Vector3) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not _has_cells:
		return out
	var o := Vector2(from.x - _origin.x, from.z - _origin.z) / CELL
	var d := Vector2(direction.x, direction.z) / CELL
	var lo := Vector2(_lo)
	var hi := Vector2(_hi + Vector2i.ONE)
	var t0 := 0.0
	var t1 := INF
	for a in 2:
		if absf(d[a]) < 1e-9:
			if o[a] < lo[a] or o[a] > hi[a]:
				return out
			continue
		var ta := (lo[a] - o[a]) / d[a]
		var tb := (hi[a] - o[a]) / d[a]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t0 > t1:
		return out
	var p := o + d * t0
	var c := Vector2i(floori(p.x), floori(p.y)).clamp(_lo, _hi)
	if t1 == INF:
		out.append(c) # Straight down or up: one column.
		return out
	var step := Vector2i.ZERO
	var t_max := Vector2(INF, INF)
	var t_delta := Vector2(INF, INF)
	for a in 2:
		if absf(d[a]) < 1e-9:
			continue
		step[a] = 1 if d[a] > 0.0 else -1
		t_delta[a] = 1.0 / absf(d[a])
		var boundary: float = (c[a] + 1) if d[a] > 0.0 else c[a]
		t_max[a] = t0 + (boundary - p[a]) / d[a]
	var limit := (_hi.x - _lo.x) + (_hi.y - _lo.y) + 4
	for i in limit:
		out.append(c)
		var a := 0 if t_max.x < t_max.y else 1
		if t_max[a] > t1:
			break
		c[a] += step[a]
		if c[a] < _lo[a] or c[a] > _hi[a]:
			break
		t_max[a] += t_delta[a]
	return out


## A storey's walls (LevelBuild.walls_on), cached for this version. Don't change it.
func walls_on(storey: int, base := 0) -> Array[Dictionary]:
	var key := "walls_on:%d:%d" % [storey, base]
	var cache := _derived()
	if not cache.has(key):
		cache[key] = LevelBuild.walls_on_among(_kinds.get("wall", {}).values(), storey, base)
	return cache[key]


## A wall's openings (LevelBuild.openings_in), cached for this version. Don't change it.
func openings_in(wall_id: String) -> Array[Dictionary]:
	var cache := _derived()
	if not cache.has("openings_by_wall"):
		var by_wall := {}
		for opening: Dictionary in _kinds.get("opening", {}).values():
			var on := str(opening.get("wall", ""))
			if not by_wall.has(on):
				var list: Array[Dictionary] = []
				by_wall[on] = list
			by_wall[on].append(opening)
		cache.openings_by_wall = by_wall
	var found: Array[Dictionary] = []
	return cache.openings_by_wall.get(wall_id, found)


## Door props in a wall (LevelBuild.doors_in), looking only at props.
func doors_in(wall: Dictionary) -> Array[Dictionary]:
	return LevelBuild.doors_in_among(_objects, _kinds.get("prop", {}).values(), wall)


func wall_at(voxel: Vector3i, prefer_storey := -1) -> String:
	return LevelBuild.wall_at_among(_objects, _kinds.get("wall", {}).values(), voxel, prefer_storey)


func opening_at(voxel: Vector3i) -> String:
	return LevelBuild.opening_at_among(_objects, _kinds.get("opening", {}).values(), voxel)


func room_at(box_in_voxels: AABB) -> String:
	return LevelStructure.room_at_among(_kinds.get("room", {}).values(), box_in_voxels)


func _derived() -> Dictionary:
	if _cache_version != version:
		_cache.clear()
		_cache_version = version
	return _cache


# --- Static helpers: the editor's index when it covers objects, else LevelBuild's scans ----------

static func _for(objects: Dictionary):
	if current != null and current.covers(objects):
		return current
	return null


static func walls_on_of(objects: Dictionary, storey: int, base := 0) -> Array[Dictionary]:
	var index = _for(objects)
	return index.walls_on(storey, base) if index else LevelBuild.walls_on(objects, storey, base)


static func walls_with_of(objects: Dictionary, wall: Dictionary) -> Array[Dictionary]:
	return walls_on_of(objects, int(wall.storey), int(wall.get("base", 0)))


static func openings_in_of(objects: Dictionary, wall_id: String) -> Array[Dictionary]:
	var index = _for(objects)
	return index.openings_in(wall_id) if index else LevelBuild.openings_in(objects, wall_id)


static func doors_in_of(objects: Dictionary, wall: Dictionary) -> Array[Dictionary]:
	var index = _for(objects)
	return index.doors_in(wall) if index else LevelBuild.doors_in(objects, wall)


static func wall_at_of(objects: Dictionary, voxel: Vector3i, prefer_storey := -1) -> String:
	var index = _for(objects)
	return index.wall_at(voxel, prefer_storey) if index else LevelBuild.wall_at(objects, voxel, prefer_storey)


static func opening_at_of(objects: Dictionary, voxel: Vector3i) -> String:
	var index = _for(objects)
	return index.opening_at(voxel) if index else LevelBuild.opening_at(objects, voxel)


static func room_at_of(objects: Dictionary, box_in_voxels: AABB) -> String:
	var index = _for(objects)
	return index.room_at(box_in_voxels) if index else LevelStructure.room_at(objects, box_in_voxels)


## PropPlacement's prop overlap test through the grid; null when the index doesn't cover objects.
static func hits_prop_of(objects: Dictionary, box: AABB, ignore: String) -> Variant:
	var index = _for(objects)
	return index.hits_prop(box, ignore) if index else null
