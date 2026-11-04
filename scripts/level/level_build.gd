class_name LevelBuild
## Build mode's structure (empty levels): storeys, walls, floors and ceilings, and openings in walls.
## Plan: docs/level-editor-build-mode.md. All of it goes through LevelEdits' structure edits like
## rooms do (LevelStructure packs it for VoxelWorld.apply_structure).
##
## - The `storeys` object (one per level, id "storeys"): `floor`, the top of storey 0's floor (voxel
##   y); `slab`, the thickness of floors and ceilings; `heights`, each storey's wall height. Storey
##   n + 1's floor is storey n's ceiling: the slab over its walls.
## - A wall (`kind = "wall"`): from grid point `a` to `b` (Vector3i, y unused) on `storey`, straight
##   or at 45°; `thickness` across, centered on the line; `height` (-1: the storey's); `material`, and
##   `inner` (0: none) for the left face (seen from above, going a -> b) of a wall 2 or more thick.
## - Floors and ceilings (`kind = "floor"` / `"ceiling"`, one per storey, id "floor_<n>" /
##   "ceiling_<n>"): `shapes`, painted in order, each [add (1 / 0), material, point count, x, z, ...]
##   (a polygon on grid points) or [add, material, -run count, z, x0, x1, ...] (runs of columns,
##   sorted by z, x1 exclusive: a filled enclosure); the last shape over a column decides. A floor is the slab under its
##   storey's floor top, a ceiling the slab over its walls. Where a ceiling and the floor above
##   share a slab, the ceiling's material shows on the bottom layer and the floor's above it.
## - An opening in a wall (an opening with `wall` set): `along` (voxels from a), `width`, `sill`
##   (from the floor) and `height`; it moves with the wall.

const KINDS := ["wall", "floor", "ceiling", "storeys"]
const STOREYS_ID := "storeys"
const DEFAULT_HEIGHT := 30
const DEFAULT_SLAB := 3

## Record types for apply_structure (voxel_world.cpp BuildType).
const WALL := 1
const SLAB := 2
const WALL_OPENING := 3


static func is_build(object: Dictionary) -> bool:
	return object.get("kind") in KINDS or (object.get("kind") == "opening" and str(object.get("wall", "")) != "")


static func new_storeys(floor: int, heights: Array = [DEFAULT_HEIGHT], slab := DEFAULT_SLAB) -> Dictionary:
	return {kind = "storeys", id = STOREYS_ID, floor = floor, slab = slab, heights = heights.duplicate()}


static func new_wall(storey: int, a: Vector3i, b: Vector3i, material: int, thickness := 2, height := -1, inner := 0) -> Dictionary:
	return {kind = "wall", storey = storey, a = Vector3i(a.x, 0, a.z), b = Vector3i(b.x, 0, b.z), material = material,
			thickness = thickness, height = height, inner = inner}


## An empty floor or ceiling for a storey (kind "floor" or "ceiling").
static func new_slab(kind: String, storey: int) -> Dictionary:
	return {kind = kind, id = "%s_%d" % [kind, storey], storey = storey, shapes = []}


static func slab_id(kind: String, storey: int) -> String:
	return "%s_%d" % [kind, storey]


## A slab shape: a polygon of grid points (Vector3i, y unused), painted (add) or erased.
static func shape(points: Array, material: int, add := true) -> Array:
	var out := [1 if add else 0, material, points.size()]
	for p: Vector3i in points:
		out.append_array([p.x, p.z])
	return out


## A runs shape: columns x0 <= x < x1 of row z for each [z, x0, x1] (sorted by z here).
static func runs_shape(runs: Array, material: int, add := true) -> Array:
	var sorted := runs.duplicate()
	sorted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out := [1 if add else 0, material, -sorted.size()]
	for run: Array in sorted:
		out.append_array([int(run[0]), int(run[1]), int(run[2])])
	return out


## The x / z box of one shape as Rect2i (position x, z; size), from its points or runs.
static func shape_rect(s: Array) -> Rect2i:
	var count := int(s[2])
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := -lo
	if count >= 0:
		for i in count:
			var p := Vector2i(int(s[3 + i * 2]), int(s[4 + i * 2]))
			lo = lo.min(p)
			hi = hi.max(p)
	else:
		for i in -count:
			var z := int(s[3 + i * 3])
			lo = lo.min(Vector2i(int(s[4 + i * 3]), z))
			hi = hi.max(Vector2i(int(s[5 + i * 3]), z + 1))
	if hi.x < lo.x:
		return Rect2i()
	return Rect2i(lo, hi - lo)


## A rectangle shape over [from, to) in x and z.
static func rect_shape(from: Vector3i, to: Vector3i, material: int, add := true) -> Array:
	var lo := from.min(to)
	var hi := from.max(to)
	return shape([Vector3i(lo.x, 0, lo.z), Vector3i(hi.x, 0, lo.z), Vector3i(hi.x, 0, hi.z), Vector3i(lo.x, 0, hi.z)], material, add)


static func is_diagonal_ok(a: Vector3i, b: Vector3i) -> bool:
	var d := b - a
	return (d.x == 0) != (d.z == 0) or (absi(d.x) == absi(d.z) and d.x != 0)


# --- Storeys -------------------------------------------------------------------------------------

## The level's storeys object, or the default for one storey on the starter slab.
static func storeys(objects: Dictionary) -> Dictionary:
	return objects.get(STOREYS_ID, new_storeys(DEFAULT_SLAB))


## A storey's wall height (storeys past the list use the last one's, or the default).
static func storey_height(st: Dictionary, storey: int) -> int:
	var heights: Array = st.heights
	if heights.is_empty():
		return DEFAULT_HEIGHT
	return int(heights[clampi(storey, 0, heights.size() - 1)])


## The top of a storey's floor (voxel y): what its walls stand on.
static func floor_y(st: Dictionary, storey: int) -> int:
	var y := int(st.floor)
	for i in maxi(storey, 0):
		y += storey_height(st, i) + int(st.slab)
	return y


## The top of a storey's walls: the bottom of its ceiling.
static func top_y(st: Dictionary, storey: int) -> int:
	return floor_y(st, storey) + storey_height(st, storey)


static func wall_height(wall: Dictionary, st: Dictionary) -> int:
	return int(wall.height) if int(wall.height) > 0 else storey_height(st, int(wall.storey))


# --- Geometry ------------------------------------------------------------------------------------

## A wall's box in voxels (a little bigger than its cells).
static func wall_box(wall: Dictionary, st: Dictionary) -> AABB:
	var a: Vector3i = wall.a
	var b: Vector3i = wall.b
	var grow := int(wall.thickness) / 2 + 2
	var y := floor_y(st, int(wall.storey))
	var lo := Vector3(mini(a.x, b.x) - grow, y, mini(a.z, b.z) - grow)
	var hi := Vector3(maxi(a.x, b.x) + grow, y + wall_height(wall, st), maxi(a.z, b.z) + grow)
	return AABB(lo, hi - lo)


## The y range [y0, y1) a floor or ceiling slab of a storey fills.
static func slab_range(kind: String, storey: int, st: Dictionary) -> Vector2i:
	if kind == "floor":
		var top := floor_y(st, storey)
		return Vector2i(top - int(st.slab), top)
	var bottom := top_y(st, storey)
	return Vector2i(bottom, bottom + int(st.slab))


## The x / z box of a slab's shapes ({} AABB when it has none), over its y range.
static func slab_box(slab: Dictionary, st: Dictionary) -> AABB:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := -lo
	for s: Array in slab.shapes:
		var rect := shape_rect(s)
		if rect.size == Vector2i.ZERO:
			continue
		lo = lo.min(rect.position)
		hi = hi.max(rect.end)
	if hi.x < lo.x:
		return AABB()
	var y := slab_range(slab.kind, int(slab.storey), st)
	return AABB(Vector3(lo.x, y.x, lo.y), Vector3(hi.x - lo.x, y.y - y.x, hi.y - lo.y))


## The voxels a build object shapes, given the level's objects (for its storey and, for an opening,
## its wall). AABB() when it shapes none (a slab with no shapes, an opening whose wall is gone).
static func bounds(object: Dictionary, objects: Dictionary) -> AABB:
	var st := storeys(objects)
	match object.kind:
		"wall":
			return wall_box(object, st)
		"floor", "ceiling":
			return slab_box(object, st)
		"opening":
			var wall: Dictionary = objects.get(object.wall, {})
			return wall_box(wall, st) if wall.get("kind") == "wall" else AABB()
		"storeys":
			# Every storey moves: everything built.
			var box := AABB()
			for other: Dictionary in objects.values():
				if other.kind in ["wall", "floor", "ceiling"]:
					var b := bounds(other, objects)
					if b.has_volume():
						box = b if not box.has_volume() else box.merge(b)
			return box
	return AABB()


## The lowest voxel y whose structure can differ between two storeys objects: everything from the
## first storey whose height changed up, from the bottom of its ceiling (the lowest of before and
## after), or from the ground floor's slab if the floor or slab changed.
static func changed_from(before: Dictionary, after: Dictionary) -> int:
	if int(before.floor) != int(after.floor) or int(before.slab) != int(after.slab):
		return mini(int(before.floor), int(after.floor)) - maxi(int(before.slab), int(after.slab))
	var count := maxi(before.heights.size(), after.heights.size())
	for i in count:
		if storey_height(before, i) != storey_height(after, i):
			return mini(top_y(before, i), top_y(after, i))
	return mini(top_y(before, count), top_y(after, count))


## Whether a wall covers column (x, z), by the same rule as VoxelWorld's: across [-t/2, t/2) from
## its line, along it and t/2 past each end.
static func wall_has(wall: Dictionary, x: int, z: int) -> bool:
	var a: Vector3i = wall.a
	var d := Vector2(wall.b.x - a.x, wall.b.z - a.z)
	var length := d.length()
	var u := d / length if length > 0.0 else Vector2(1, 0)
	var c := Vector2(x + 0.5 - a.x, z + 0.5 - a.z)
	var along := c.dot(u)
	var across := c.x * u.y - c.y * u.x
	var half := int(wall.thickness) * 0.5
	return across >= -half and across < half and along >= -half and along < length + half


## A wall's ends (voxel x, z).
static func ends(wall: Dictionary) -> Array[Vector2i]:
	return [Vector2i(wall.a.x, wall.a.z), Vector2i(wall.b.x, wall.b.z)]


## A wall's unit direction (a -> b) and length in voxels.
static func wall_unit(wall: Dictionary) -> Vector2:
	var d := Vector2(wall.b.x - wall.a.x, wall.b.z - wall.a.z)
	return d.normalized() if d.length() > 0.0 else Vector2(1, 0)


static func wall_length(wall: Dictionary) -> float:
	return Vector2(wall.b.x - wall.a.x, wall.b.z - wall.a.z).length()


## How far along a wall (voxels from a) a point (voxel x, z) is, and how far across (left < 0).
static func along_of(wall: Dictionary, p: Vector2) -> float:
	return (p - Vector2(wall.a.x, wall.a.z)).dot(wall_unit(wall))


static func across_of(wall: Dictionary, p: Vector2) -> float:
	var u := wall_unit(wall)
	var c := p - Vector2(wall.a.x, wall.a.z)
	return c.x * u.y - c.y * u.x


## The 8 corners (voxel space) of a prism from a to b (voxel x, z): thickness across, extend past
## each end, from y0 to y1. Bit 0: along, bit 1: up, bit 2: across (LevelView.draw_corners).
static func prism_corners(a: Vector2, b: Vector2, thickness: float, y0: float, y1: float, extend: float) -> Array[Vector3]:
	var d := b - a
	var u := d.normalized() if d.length() > 0.0 else Vector2(1, 0)
	var across := Vector2(u.y, -u.x)
	var half := thickness * 0.5
	var out: Array[Vector3] = []
	for i in 8:
		var along := d.length() + extend if i & 1 else -extend
		var side := half if i & 4 else -half
		var p := a + u * along + across * side
		out.append(Vector3(p.x, y1 if i & 2 else y0, p.y))
	return out


## The corners (voxel space) of a wall's cells, or of an opening's cut in its wall; [] for anything
## else (or an opening whose wall is gone).
static func corners_of(object: Dictionary, objects: Dictionary) -> Array[Vector3]:
	var st := storeys(objects)
	if object.get("kind") == "wall":
		var y := floor_y(st, int(object.storey))
		var e := ends(object)
		return prism_corners(Vector2(e[0]), Vector2(e[1]), int(object.thickness), y, y + wall_height(object, st), int(object.thickness) * 0.5)
	if object.get("kind") == "opening" and str(object.get("wall", "")) != "":
		var wall: Dictionary = objects.get(object.wall, {})
		if wall.get("kind") != "wall":
			return []
		var a := Vector2(wall.a.x, wall.a.z)
		var u := wall_unit(wall)
		var y := floor_y(st, int(wall.storey)) + int(object.sill)
		return prism_corners(a + u * int(object.along), a + u * (int(object.along) + int(object.width)), int(wall.thickness) + 2, y,
				y + int(object.height), 0.0)
	return []


## An object's box in voxels: build pieces from their corners (walls, openings in walls) or bounds
## (floors, ceilings), anything else LevelSchema.box_of.
static func box_of(object: Dictionary, objects: Dictionary) -> AABB:
	if not is_build(object):
		return LevelSchema.box_of(object)
	var corners := corners_of(object, objects)
	if corners.is_empty():
		return bounds(object, objects)
	var box := AABB(corners[0], Vector3.ZERO)
	for c in corners:
		box = box.expand(c)
	return box


## The wall whose cells hold a voxel ("" none): one on prefer_storey wins, then the newest id.
static func wall_at(objects: Dictionary, voxel: Vector3i, prefer_storey := -1) -> String:
	var st := storeys(objects)
	var best := ""
	var best_rank := -1
	for object: Dictionary in objects.values():
		if object.kind != "wall" or not is_diagonal_ok(object.a, object.b):
			continue
		var y := floor_y(st, int(object.storey))
		if voxel.y < y or voxel.y >= y + wall_height(object, st) or not wall_has(object, voxel.x, voxel.z):
			continue
		var rank := 1 if int(object.storey) == prefer_storey else 0
		if rank > best_rank or (rank == best_rank and str(object.id) > best):
			best = object.id
			best_rank = rank
	return best


## The opening in a wall that holds a voxel (its cut, a voxel past each face), "" none.
static func opening_at(objects: Dictionary, voxel: Vector3i) -> String:
	var st := storeys(objects)
	var c := Vector2(voxel.x + 0.5, voxel.z + 0.5)
	for object: Dictionary in objects.values():
		if object.kind != "opening" or str(object.get("wall", "")) == "":
			continue
		var wall: Dictionary = objects.get(object.wall, {})
		if wall.get("kind") != "wall":
			continue
		var y := floor_y(st, int(wall.storey)) + int(object.sill)
		var along := along_of(wall, c)
		if voxel.y >= y and voxel.y < y + int(object.height) and along >= int(object.along) and along < int(object.along) + int(object.width) \
				and absf(across_of(wall, c)) < int(wall.thickness) * 0.5 + 1.0:
			return object.id
	return ""


## The openings in a wall.
static func openings_in(objects: Dictionary, wall_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for object: Dictionary in objects.values():
		if object.kind == "opening" and str(object.get("wall", "")) == wall_id:
			out.append(object)
	return out


## Door props standing in a wall (their middle in its cells, on its storey).
static func doors_in(objects: Dictionary, wall: Dictionary) -> Array[Dictionary]:
	var st := storeys(objects)
	var y := floor_y(st, int(wall.storey))
	var out: Array[Dictionary] = []
	for object: Dictionary in objects.values():
		if not LevelSchema.is_door(object):
			continue
		var center := LevelSchema.prop_box(object).get_center()
		if center.y >= y and center.y < y + wall_height(wall, st) and wall_has(wall, floori(center.x), floori(center.z)):
			out.append(object)
	return out


## A storey's walls (valid ones).
static func walls_on(objects: Dictionary, storey: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for object: Dictionary in objects.values():
		if object.kind == "wall" and int(object.storey) == storey and is_diagonal_ok(object.a, object.b):
			out.append(object)
	return out


## The columns closed in by a storey's walls around a start column: {ok, runs ([z, x0, x1], under
## the walls too, out to their far side), reason}. Not ok if the start is in a wall or the space
## reaches past the walls (it isn't closed in).
static func enclosure(objects: Dictionary, storey: int, start: Vector2i) -> Dictionary:
	var grid := _wall_grid(objects, storey)
	if grid.is_empty():
		return {ok = false, reason = "Not enclosed by walls"}
	var lo: Vector2i = grid.lo
	var size: Vector2i = grid.size
	if start.x <= lo.x or start.y <= lo.y or start.x >= lo.x + size.x - 1 or start.y >= lo.y + size.y - 1:
		return {ok = false, reason = "Not enclosed by walls"}
	var first := (start.x - lo.x) + (start.y - lo.y) * size.x
	if grid.state[first] != 0:
		return {ok = false, reason = "Click inside the walls, not on one"}
	var cells := _flood(grid, first, 2)
	if cells.is_empty():
		return {ok = false, reason = "Not enclosed by walls"}
	_reach_under_walls(grid, cells, 2)
	return {ok = true, runs = _runs(grid, 2)}


## Every space a storey's walls close in, each as runs (like enclosure's).
static func enclosures(objects: Dictionary, storey: int) -> Array:
	var grid := _wall_grid(objects, storey)
	if grid.is_empty():
		return []
	var state: PackedByteArray = grid.state
	var regions: Array = []
	var label := 2
	for i in state.size():
		if state[i] != 0:
			continue
		var cells := _flood(grid, i, label)
		if cells.is_empty():
			continue # Open: _flood marked it so it isn't tried again.
		_reach_under_walls(grid, cells, label)
		regions.append(_runs(grid, label))
		label += 1
		if label > 250:
			break
	return regions


## The storey's walls drawn into a grid over their box (a voxel per column): {lo, size, state, thickest},
## state 0 open, 1 wall. {} without walls.
static func _wall_grid(objects: Dictionary, storey: int) -> Dictionary:
	var walls := walls_on(objects, storey)
	if walls.is_empty():
		return {}
	var st := storeys(objects)
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := -lo
	var thickest := 1
	for wall in walls:
		var grow := int(wall.thickness) / 2 + 2
		lo = lo.min(Vector2i(mini(wall.a.x, wall.b.x) - grow, mini(wall.a.z, wall.b.z) - grow))
		hi = hi.max(Vector2i(maxi(wall.a.x, wall.b.x) + grow, maxi(wall.a.z, wall.b.z) + grow))
		thickest = maxi(thickest, int(wall.thickness))
	var size := hi - lo
	var state := PackedByteArray()
	state.resize(size.x * size.y)
	for wall in walls:
		var box := wall_box(wall, st)
		for z in range(maxi(int(box.position.z), lo.y), mini(int(box.end.z), hi.y)):
			for x in range(maxi(int(box.position.x), lo.x), mini(int(box.end.x), hi.x)):
				if wall_has(wall, x, z):
					state[(x - lo.x) + (z - lo.y) * size.x] = 1
	return {lo = lo, size = size, state = state, thickest = thickest}


## Floods the open columns from first with label. Returns them, or [] if the flood got out to the
## grid's edge (not closed in; those columns are left marked 255 so they aren't flooded again).
static func _flood(grid: Dictionary, first: int, label: int) -> PackedInt32Array:
	var state: PackedByteArray = grid.state
	var width: int = grid.size.x
	var height: int = grid.size.y
	var queue := PackedInt32Array([first])
	state[first] = label
	var head := 0
	var open := false
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % width
		var z := i / width
		if x == 0 or z == 0 or x == width - 1 or z == height - 1:
			open = true
			continue
		for n in [i - 1, i + 1, i - width, i + width]:
			if state[n] == 0:
				state[n] = label
				queue.append(n)
	if open:
		for i in queue:
			state[i] = 255
		return PackedInt32Array()
	return queue


## Takes the walls around a flooded space into it, out to their far side (so the floor runs under
## them), up to the thickest wall's thickness.
static func _reach_under_walls(grid: Dictionary, cells: PackedInt32Array, label: int) -> void:
	var state: PackedByteArray = grid.state
	var width: int = grid.size.x
	var height: int = grid.size.y
	var edge := cells
	for step in int(grid.thickest) + 1:
		var next := PackedInt32Array()
		for i in edge:
			var x := i % width
			var z := i / width
			for n in [i - 1 if x > 0 else -1, i + 1 if x < width - 1 else -1, i - width if z > 0 else -1, i + width if z < height - 1 else -1]:
				if n >= 0 and state[n] == 1:
					state[n] = label
					next.append(n)
		edge = next


## The columns labelled label, as runs [z, x0, x1] in voxels.
static func _runs(grid: Dictionary, label: int) -> Array:
	var state: PackedByteArray = grid.state
	var lo: Vector2i = grid.lo
	var width: int = grid.size.x
	var runs: Array = []
	for z in int(grid.size.y):
		var x := 0
		while x < width:
			if state[x + z * width] != label:
				x += 1
				continue
			var x0 := x
			while x < width and state[x + z * width] == label:
				x += 1
			runs.append([z + lo.y, x0 + lo.x, x + lo.x])
	return runs


# --- Packing for apply_structure -----------------------------------------------------------------

## Build records for apply_structure: everything built that touches region (voxels). Order: ceilings'
## upper layers, floors, ceilings' bottom layers, walls (by id), wall openings.
static func pack(objects: Dictionary, region: AABB) -> PackedInt32Array:
	var st := storeys(objects)
	var slabs: Array[Dictionary] = []
	var walls: Array[Dictionary] = []
	var openings: Array[Dictionary] = []
	for object: Dictionary in objects.values():
		match object.kind:
			"floor", "ceiling":
				if not object.shapes.is_empty() and slab_box(object, st).intersects(region):
					slabs.append(object)
			"wall":
				if is_diagonal_ok(object.a, object.b) and wall_box(object, st).intersects(region):
					walls.append(object)
			"opening":
				if str(object.get("wall", "")) != "" and objects.has(object.wall):
					openings.append(object)
	var by_id := func(x: Dictionary, y: Dictionary) -> bool: return str(x.id) < str(y.id)
	slabs.sort_custom(by_id)
	walls.sort_custom(by_id)
	openings.sort_custom(by_id)
	var out := PackedInt32Array()
	# A ceiling and the floor above share a slab: the ceiling shows underneath, the floor on top.
	for slab in slabs:
		if slab.kind == "ceiling":
			var y := slab_range("ceiling", int(slab.storey), st)
			if y.y - y.x > 1:
				_pack_slab(out, slab, y.x + 1, y.y)
	for slab in slabs:
		if slab.kind == "floor":
			var y := slab_range("floor", int(slab.storey), st)
			_pack_slab(out, slab, y.x, y.y)
	for slab in slabs:
		if slab.kind == "ceiling":
			var y := slab_range("ceiling", int(slab.storey), st)
			_pack_slab(out, slab, y.x, y.x + 1)
	for wall in walls:
		var y := floor_y(st, int(wall.storey))
		out.append_array([WALL, 9, wall.a.x, wall.a.z, wall.b.x, wall.b.z, y, y + wall_height(wall, st),
				int(wall.thickness), int(wall.material), int(wall.inner)])
	for opening in openings:
		var wall: Dictionary = objects[opening.wall]
		if wall.get("kind") != "wall" or not wall_box(wall, st).intersects(region):
			continue
		var y := floor_y(st, int(wall.storey)) + int(opening.sill)
		out.append_array([WALL_OPENING, 9, wall.a.x, wall.a.z, wall.b.x, wall.b.z, y, y + int(opening.height),
				int(wall.thickness), int(opening.along), int(opening.along) + int(opening.width)])
	return out


static func _pack_slab(out: PackedInt32Array, slab: Dictionary, y0: int, y1: int) -> void:
	var payload := PackedInt32Array([y0, y1, slab.shapes.size()])
	for s: Array in slab.shapes:
		for value in s:
			payload.append(int(value))
	out.append_array([SLAB, payload.size()])
	out.append_array(payload)
