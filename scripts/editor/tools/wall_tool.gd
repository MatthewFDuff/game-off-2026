class_name WallTool
extends BuildTools
## Build mode's Wall tool (EditorTool): press, drag, release on the storey's floor (in a rock level,
## the floor aimed at when pressing) draws a wall from the press. Its direction snaps to the nearest of 8 (along X, along Z, 45°) and
## its end to the grid along it, unless a wall end, a point on a wall or a floor corner / edge lies
## on that line (BuildTools.snap_point), which wins. While dragging, the wheel sets its height and
## typing sets its length (Tab: the height). Ctrl+drag draws a rectangle of four walls (with its
## floor and ceiling); Shift+drag erases the parts of walls it runs along, splitting them.

## The 8 directions a wall can take, in grid steps.
const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]

## Ctrl+drag: four walls around the dragged rectangle.
var rect_mode := false
## This wall's height while dragging (voxels), and the storey's (what -1 means; 0 in rock levels,
## where walls keep their own).
var height := 30
var storey_height := 30
## The end the drag reaches this frame, and its direction (one of DIRECTIONS).
var end := Vector2i.ZERO
var direction := Vector2i(1, 0)
## Typed size: the text so far, whether it's the height (else the length), and a length already
## typed (voxels, -1 none) that holds while the height is typed.
var typed := ""
var typing_height := false
var fixed_length := -1.0


func begin(shift: bool, ctrl: bool, start_height: int) -> void:
	if not has_aim:
		return
	dragging = true
	erase = shift
	rect_mode = ctrl and not shift
	start = snapped
	end = start
	height = start_height
	typed = ""
	typing_height = false
	fixed_length = -1.0


func cancel() -> void:
	dragging = false
	typed = ""


## Works out the end for this frame's aim (after update_aim), with the grid (voxels).
func update_end(grid: int) -> void:
	if not dragging:
		return
	if rect_mode:
		end = snapped
		return
	var d := aim - Vector2(start)
	var length := _typed_length()
	if d.length() < 0.5 and length < 0.0:
		end = start
		return
	if d.length() >= 0.5:
		var best := -2.0
		for candidate in DIRECTIONS:
			var dot := Vector2(candidate).normalized().dot(d.normalized())
			if dot > best:
				best = dot
				direction = candidate
	var unit := Vector2(direction)
	if length >= 0.0:
		end = start + direction * roundi(length / unit.length())
		return
	# Something to snap to on one of the 8 lines from the start, close to where it's heading, wins.
	if snapped_to != "grid" and snapped != start:
		var s := snapped - start
		if s.x == 0 or s.y == 0 or absi(s.x) == absi(s.y):
			var along := Vector2i(signi(s.x), signi(s.y))
			if Vector2(along).normalized().dot(d.normalized()) > 0.95:
				direction = along
				end = snapped
				return
	var steps := d.dot(unit) / unit.length_squared()
	end = start + direction * maxi(roundi(steps / grid) * grid, 0)


## The walls being drawn this frame, as [a, b] pairs (Vector2i): one, or four for a rectangle.
func segments() -> Array:
	if not dragging:
		return []
	if rect_mode:
		var lo := start.min(end)
		var hi := start.max(end)
		if lo.x == hi.x or lo.y == hi.y:
			return []
		var corners := [lo, Vector2i(hi.x, lo.y), hi, Vector2i(lo.x, hi.y)]
		return [0, 1, 2, 3].map(func(i: int) -> Array: return [corners[i], corners[(i + 1) % 4]])
	if end == start:
		return []
	return [[start, end]]


## The wall's length in voxels (Euclidean).
func length() -> float:
	return Vector2(end - start).length()


## Mouse wheel: taller or shorter by a grid step.
func nudge_height(steps: int, grid: int) -> void:
	_apply_typed()
	height = clampi(height + steps * grid, 1, 1024)


## Typing a size: digits, "." and "v" (voxels); Backspace erases.
func type_char(character: String) -> void:
	typed += character


func erase_char() -> void:
	typed = typed.left(-1)


## Tab: keeps what's typed and switches between the length and the height.
func next_size() -> void:
	_apply_typed()
	typing_height = not typing_height


## Enter: keeps what's typed.
func apply_typed() -> void:
	_apply_typed()


func _apply_typed() -> void:
	if typed == "":
		return
	var voxels := _parse(typed)
	typed = ""
	if voxels < 0.0:
		return
	if typing_height:
		height = clampi(roundi(voxels), 1, 1024)
	else:
		fixed_length = voxels


## The length that's typed or was typed (voxels), -1 when none.
func _typed_length() -> float:
	if typed != "" and not typing_height:
		return _parse(typed)
	return fixed_length


## "2.5" is meters, "25v" voxels; -1 when it isn't a number.
func _parse(text: String) -> float:
	var voxels := text.ends_with("v")
	var number := text.trim_suffix("v")
	if not number.is_valid_float():
		return -1.0
	return number.to_float() if voxels else number.to_float() / world.voxel_size


## The wall object for a segment, with the tool's settings (in rock, standing on plane_y).
func make_wall(a: Vector2i, b: Vector2i, material: int, thickness: int, inner: int) -> Dictionary:
	return LevelBuild.new_wall(storey, Vector3i(a.x, 0, a.y), Vector3i(b.x, 0, b.y), material, thickness,
			-1 if height == storey_height and storey >= 0 else height, inner, plane_y)


## Ends the drag: builds the wall (or the rectangle, with its floor and ceiling if slabs), or erases
## along it. Returns the toast to show ("" none).
func finish(objects: Dictionary, material: int, thickness: int, inner: int, slabs: bool, floor_material: int, ceiling_material: int) -> String:
	if not dragging:
		return ""
	_apply_typed()
	var drawn := segments()
	dragging = false
	if drawn.is_empty():
		return ""
	if erase:
		var puts := erase_along(objects, drawn[0][0], drawn[0][1])
		if puts.is_empty():
			return "No wall along that line"
		edits.put_objects(puts)
		return ""
	if not rect_mode:
		edits.put_object(make_wall(drawn[0][0], drawn[0][1], material, thickness, inner))
		return ""
	var lo := start.min(end)
	var hi := start.max(end)
	edits.begin_group()
	edits.put_objects(drawn.map(func(s: Array) -> Array: return ["", make_wall(s[0], s[1], material, thickness, inner)]))
	if slabs:
		# In rock: the floor under the walls, the ceiling on top of them.
		edits.add_slab_shape("floor", storey, LevelBuild.rect_shape(Vector3i(lo.x, 0, lo.y), Vector3i(hi.x, 0, hi.y), floor_material), plane_y)
		edits.add_slab_shape("ceiling", storey, LevelBuild.rect_shape(Vector3i(lo.x, 0, lo.y), Vector3i(hi.x, 0, hi.y), ceiling_material),
				plane_y + height)
	edits.end_group()
	return ""


## Shift+drag: put_objects pairs that take the span p -> q out of every wall on the storey it runs
## along (parallel, within half the wall's thickness of its line). A wall keeps the part before the
## span and a new wall gets the part after; openings stay where they are in the world, on whichever
## part holds them, and go with the span when it covers them.
func erase_along(objects: Dictionary, p: Vector2i, q: Vector2i) -> Array:
	var puts: Array = []
	var dp := Vector2(q - p).normalized()
	for wall in LevelBuild.walls_on(objects, storey, plane_y):
		var a := Vector2i(wall.a.x, wall.a.z)
		var b := Vector2i(wall.b.x, wall.b.z)
		var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
		if steps == 0:
			continue
		var unit := Vector2(b - a) / steps
		var dw := unit.normalized()
		if absf(dw.cross(dp)) > 0.01:
			continue # Not parallel.
		var off := Vector2(p - a)
		if absf(off.x * dw.y - off.y * dw.x) > int(wall.thickness) * 0.5 + 0.01:
			continue # Not on its line.
		var tp := Vector2(p - a).dot(unit) / unit.length_squared()
		var tq := Vector2(q - a).dot(unit) / unit.length_squared()
		var lo := clampi(roundi(minf(tp, tq)), 0, steps)
		var hi := clampi(roundi(maxf(tp, tq)), 0, steps)
		if hi <= lo:
			continue
		var step_length := unit.length()
		var removed := Vector2(lo * step_length, hi * step_length)
		var first := wall.duplicate()
		first.b = Vector3i(a.x + roundi(unit.x * lo), 0, a.y + roundi(unit.y * lo))
		var keep_first := lo > 0
		var keep_second := hi < steps
		puts.append([wall.id, first if keep_first else {}])
		var second_index := -1
		if keep_second:
			var second := wall.duplicate()
			second.erase("id")
			second.a = Vector3i(a.x + roundi(unit.x * hi), 0, a.y + roundi(unit.y * hi))
			second_index = puts.size()
			puts.append(["", second])
		for opening: Dictionary in objects.values():
			if opening.kind != "opening" or str(opening.get("wall", "")) != wall.id:
				continue
			var o0 := float(opening.along)
			var o1 := o0 + int(opening.width)
			if o1 > removed.x and o0 < removed.y:
				puts.append([opening.id, {}]) # Cut away with the span.
			elif o0 >= removed.y and keep_second:
				var moved := opening.duplicate()
				moved.along = roundi(o0 - removed.y)
				moved.wall = "$%d" % second_index
				puts.append([opening.id, moved])
			elif o1 <= removed.x and not keep_first:
				puts.append([opening.id, {}])
	return puts
