extends SceneTree
## Build mode's structure (LevelBuild) through LevelEdits, headless:
##   godot --headless --path . --script res://tests/build_model_test.gd
## A new empty level starts with storeys and a starter floor; straight and 45° walls (two-tone,
## airtight on the diagonal), an opening along a wall, floor shapes painted and erased, a ceiling
## and the floor above sharing a slab, a taller storey moving walls and slabs (and undoing), hand
## paint surviving a new wall material, deleting and undoing a wall, saving and reloading.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://build_model_test_levels/"
const LEVEL := "build_model_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	LevelData.save_dir_override = SCRATCH
	var holder := Node.new()
	root.add_child(holder)
	var level = LevelData.create(LEVEL, Vector3i(8, 4, 8), "empty", holder)
	_check("level saves", level.save() == OK)
	holder.free()
	root.get_node("Net").start_solo(LEVEL, "edit")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	var lab = current_scene
	var world = lab.world
	var edits = lab.edits
	var objects: Dictionary = lab.level.objects
	await _frames(5)

	# The starter: one storey, its floor top at 3, a concrete slab under it.
	var center := Vector3i(128, 0, 128)
	_check("a new empty level has storeys", objects.has("storeys") and objects.storeys.floor == 3 and objects.storeys.heights == [30])
	_check("...and a starter floor", objects.has("floor_0") and world.get_voxel(center + Vector3i(0, 2, 0)) == M.CONCRETE
			and world.get_voxel(center + Vector3i(0, 3, 0)) == M.AIR)

	# A straight wall along x at z = 100, two thick (z 99 and 100), with a tiled left face (z 100).
	edits.put_object(LevelBuild.new_wall(0, Vector3i(100, 0, 100), Vector3i(140, 0, 100), M.WALL_PAINT, 2, -1, M.TILE_LIGHT))
	var wall: Dictionary = _find(objects, "wall")
	_check("a wall object", not wall.is_empty())
	_check("the wall stands on the floor, 3 m tall", world.get_voxel(Vector3i(120, 3, 99)) == M.WALL_PAINT and world.get_voxel(Vector3i(120, 32, 99)) == M.WALL_PAINT
			and world.get_voxel(Vector3i(120, 33, 99)) == M.AIR)
	_check("...two voxels thick", world.get_voxel(Vector3i(120, 10, 98)) == M.AIR and world.get_voxel(Vector3i(120, 10, 101)) == M.AIR)
	_check("...with its left face tiled", world.get_voxel(Vector3i(120, 10, 100)) == M.TILE_LIGHT, str(world.get_voxel(Vector3i(120, 10, 100))))
	_check("...and its ends closed past the points", world.get_voxel(Vector3i(99, 10, 99)) == M.WALL_PAINT and world.get_voxel(Vector3i(140, 10, 99)) == M.WALL_PAINT
			and world.get_voxel(Vector3i(141, 10, 99)) == M.AIR)

	# A 45° wall: airtight (cells share faces, not just corners).
	edits.put_object(LevelBuild.new_wall(0, Vector3i(160, 0, 100), Vector3i(200, 0, 140), M.CONCRETE, 2))
	var airtight := true
	for k in range(1, 39):
		var on: bool = world.get_voxel(Vector3i(160 + k, 10, 100 + k)) == M.CONCRETE
		var beside: bool = world.get_voxel(Vector3i(161 + k, 10, 100 + k)) == M.CONCRETE
		var past: bool = world.get_voxel(Vector3i(162 + k, 10, 100 + k)) == M.AIR
		airtight = airtight and on and beside and past
	_check("a 45° wall is built, airtight and no wider", airtight)
	edits.put_object(LevelBuild.new_wall(0, Vector3i(160, 0, 160), Vector3i(163, 0, 161), M.CONCRETE, 2))
	_check("a wall at another angle builds nothing", world.get_voxel(Vector3i(161, 10, 160)) == M.AIR)

	# An opening along the straight wall: along 10, 12 wide, 22 high from the floor.
	edits.put_object(LevelSchema.new_wall_opening(wall.id, 10, 12, 0, 22))
	_check("the opening cuts through", _all(world, Vector3i(110, 3, 99), Vector3i(122, 25, 101), M.AIR))
	_check("...and no more", world.get_voxel(Vector3i(109, 10, 99)) == M.WALL_PAINT and world.get_voxel(Vector3i(122, 10, 99)) == M.WALL_PAINT
			and world.get_voxel(Vector3i(115, 25, 99)) == M.WALL_PAINT)
	# Moving the wall takes the opening along.
	var moved := wall.duplicate()
	moved.a += Vector3i(0, 0, 20)
	moved.b += Vector3i(0, 0, 20)
	edits.put_object(moved, wall.id)
	_check("a moved wall leaves air behind", world.get_voxel(Vector3i(130, 10, 99)) == M.AIR)
	_check("...and stands where it went, its opening with it", world.get_voxel(Vector3i(130, 10, 119)) == M.WALL_PAINT and world.get_voxel(Vector3i(115, 10, 119)) == M.AIR)
	edits.undo()
	_check("undo puts it back", world.get_voxel(Vector3i(130, 10, 99)) == M.WALL_PAINT and world.get_voxel(Vector3i(130, 10, 119)) == M.AIR)

	# Floor shapes: paint a tile floor, erase a square out of it.
	edits.add_slab_shape("floor", 0, LevelBuild.rect_shape(Vector3i(0, 0, 0), Vector3i(60, 0, 60), M.TILE_LIGHT))
	_check("a painted floor", world.get_voxel(Vector3i(30, 1, 30)) == M.TILE_LIGHT and world.get_voxel(Vector3i(30, 2, 59)) == M.TILE_LIGHT
			and world.get_voxel(Vector3i(30, 2, 60)) == M.AIR)
	edits.add_slab_shape("floor", 0, LevelBuild.rect_shape(Vector3i(10, 0, 10), Vector3i(20, 0, 20), 0, false))
	_check("erasing cuts it back", world.get_voxel(Vector3i(15, 1, 15)) == M.AIR and world.get_voxel(Vector3i(25, 1, 25)) == M.TILE_LIGHT)
	edits.add_slab_shape("floor", 0, LevelBuild.shape([Vector3i(40, 0, 0), Vector3i(50, 0, 0), Vector3i(40, 0, 10)], M.METAL))
	_check("a triangle on top of it", world.get_voxel(Vector3i(41, 1, 1)) == M.METAL and world.get_voxel(Vector3i(49, 1, 8)) == M.TILE_LIGHT)

	# A ceiling over the wall's storey and the next storey's floor share the slab.
	edits.add_slab_shape("ceiling", 0, LevelBuild.rect_shape(Vector3i(90, 0, 80), Vector3i(150, 0, 110), M.CONCRETE))
	edits.add_slab_shape("floor", 1, LevelBuild.rect_shape(Vector3i(90, 0, 80), Vector3i(150, 0, 110), M.TILE_LIGHT))
	_check("the ceiling sits on the walls", world.get_voxel(Vector3i(120, 33, 90)) == M.CONCRETE)
	_check("...and the floor above it", world.get_voxel(Vector3i(120, 34, 90)) == M.TILE_LIGHT and world.get_voxel(Vector3i(120, 35, 90)) == M.TILE_LIGHT
			and world.get_voxel(Vector3i(120, 36, 90)) == M.AIR)

	# A taller storey: walls grow, the slab rises.
	var storeys: Dictionary = objects.storeys.duplicate(true)
	storeys.heights = [40]
	edits.put_object(storeys, "storeys")
	_check("a taller storey: the wall grows", world.get_voxel(Vector3i(120, 42, 99)) == M.WALL_PAINT and world.get_voxel(Vector3i(120, 43, 99)) == M.CONCRETE)
	_check("...the slab moves up", world.get_voxel(Vector3i(120, 34, 90)) == M.AIR and world.get_voxel(Vector3i(120, 43, 90)) == M.CONCRETE
			and world.get_voxel(Vector3i(120, 45, 90)) == M.TILE_LIGHT)
	edits.undo()
	_check("...and undoes", world.get_voxel(Vector3i(120, 34, 90)) == M.TILE_LIGHT and world.get_voxel(Vector3i(120, 40, 99)) == M.AIR)

	# Hand paint on a wall survives a new wall material.
	wall = objects[wall.id]
	edits.voxel_op({type = "box", from = Vector3i(130, 10, 99), to = Vector3i(131, 11, 100), material = M.METAL})
	var repainted := wall.duplicate()
	repainted.material = M.GLASS
	edits.put_object(repainted, wall.id)
	_check("a new wall material repaints the wall", world.get_voxel(Vector3i(131, 10, 99)) == M.GLASS)
	_check("...but not hand paint on it", world.get_voxel(Vector3i(130, 10, 99)) == M.METAL)

	# Deleting a wall clears it; undo brings it back.
	edits.remove_object(wall.id)
	_check("a deleted wall is gone", world.get_voxel(Vector3i(131, 10, 99)) == M.AIR and world.get_voxel(Vector3i(131, 10, 100)) == M.AIR)
	edits.undo()
	_check("...and undo brings it back", world.get_voxel(Vector3i(131, 10, 99)) == M.GLASS and objects.has(wall.id))

	# Saving and reloading keeps it all.
	lab.request_save()
	var saved = LevelData.load_level(LEVEL)
	_check("the level reloads", saved != null)
	if saved != null:
		_check("...with the same voxels", saved.voxels == world.get_data())
		_check("...the storeys", saved.objects.get("storeys", {}).get("heights") == [30])
		_check("...the floor's shapes, as ints", saved.objects.get("floor_0", {}).get("shapes") == objects.floor_0.shapes, str(saved.objects.get("floor_0")))
		_check("...and the walls", saved.objects.has(wall.id) and saved.objects[wall.id].a == objects[wall.id].a)
		# Re-applying everything from the saved objects onto an empty world gives the same voxels.
		var fresh := VoxelWorld.new()
		fresh.size_in_chunks = Vector3i(8, 4, 8)
		fresh.immediate_remesh_limit = 0
		root.add_child(fresh)
		fresh.fill_all(M.AIR)
		var built: Array = saved.objects.values().filter(func(o: Dictionary) -> bool: return LevelBuild.is_build(o))
		WorldSync.run_op(fresh, LevelStructure.op({}, saved.objects, built, saved.settings, fresh.get_size_in_voxels()))
		fresh.fill_box(Vector3i(130, 10, 99), Vector3i(131, 11, 100), M.METAL, false)
		_check("...and the objects alone rebuild the same voxels", fresh.get_data() == world.get_data())
		fresh.free()
	_finish()


func _find(objects: Dictionary, kind: String) -> Dictionary:
	for object: Dictionary in objects.values():
		if object.kind == kind:
			return object
	return {}


func _all(world, from: Vector3i, to: Vector3i, material: int) -> bool:
	for z in range(from.z, to.z):
		for y in range(from.y, to.y):
			for x in range(from.x, to.x):
				if world.get_voxel(Vector3i(x, y, z)) != material:
					return false
	return true


func _finish() -> void:
	print("build model test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("%s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  (%s)" % detail])
