extends SceneTree
## Headless checks for falling pieces and drop-ceiling tiles (FallingPieces):
##   godot --headless --path . --script res://tests/falling_test.gd
## Builds a scratch level (one concrete box room) and plays it solo:
##   1. A wooden crate with a sheet-metal lid on a thin steel pillar: carving the pillar's base
##      through WorldSync cuts it loose, a falling mesh shows, and once it has fallen the crate is
##      voxels again, lower down, resting on the floor, every material's count kept. Shooting it
##      there carves it, and it doesn't fall again.
##   2. A ceiling_tile_grid prop under the ceiling: carving one voxel of a tile drops the rest of
##      that tile to the floor as a sheet of CEILING_TILE, the T-bars and the other tiles stay up,
##      and shooting the sheet on the floor only carves it.
##   3. A piece smaller than FallingPieces.MIN_PIECE (a 2 x 2 x 2 cube hung on one steel voxel)
##      still crumbles: nothing falls, nothing is stamped.
##
## Game types are left unnamed (see editor_test.gd): naming them would compile those scripts before
## the autoloads they use are registered.

const SCRATCH := "user://falling_test_levels/"
const LEVEL := "falling_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const SIZE := Vector3i(4, 2, 4)
const FLOOR := 8
const CEILING := 40
## The room, in voxels [from, to).
const ROOM := [Vector3i(8, FLOOR, 8), Vector3i(120, CEILING, 120)]
const PLAYER_SPOT := Vector3(110.0, FLOOR, 110.0)
## The crate on its pillar: the pillar [PILLAR, PILLAR + (2, 14, 2)), the crate's wood on top of it
## and a one-voxel sheet-metal lid.
const PILLAR := Vector3i(30, FLOOR, 30)
const CRATE := [Vector3i(27, FLOOR + 14, 27), Vector3i(35, FLOOR + 19, 35)]
const LID := [Vector3i(27, FLOOR + 19, 27), Vector3i(35, FLOOR + 20, 35)]
## Where the crate's piece is looked for (voxels [from, to)).
const CRATE_AREA := [Vector3i(24, FLOOR, 24), Vector3i(38, FLOOR + 22, 38)]
## The ceiling tile panel's origin (its top layer against the ceiling).
const TILES := Vector3i(60, CEILING - 4, 60)
## The tiny cube, hung on one steel voxel under the ceiling.
const TINY := Vector3i(90, CEILING - 3, 90)

var _failures := 0
var lab


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	LevelData.save_dir_override = SCRATCH
	_make_level()
	root.get_node("Net").start_solo(LEVEL, "play")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	lab = current_scene
	await _frames(10)
	_check("playing, with falling pieces", lab.play.active and lab.falling != null and lab.world.detach_floating)
	var started := []
	lab.falling.piece_falling.connect(func(fall: Dictionary) -> void: started.append(fall))

	await _crate()
	await _tiles()
	await _tiny(started)

	print("falling test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## 1. The crate on a pillar.
func _crate() -> void:
	var wood := _count(CRATE_AREA, M.WOOD)
	var metal := _count(CRATE_AREA, M.METAL)
	var steel := _count(CRATE_AREA, M.STEEL)
	_check("the crate stands on its pillar", wood == 8 * 5 * 8 and metal == 64 and steel == 2 * 14 * 2, "%d wood, %d metal, %d steel" % [wood, metal, steel])
	var base: Vector3 = lab.view.to_world(Vector3(PILLAR) + Vector3(1.0, 1.5, 1.0))
	lab.world_sync.carve_sphere(base, 0.15, 3, Vector3.UP)
	_check("carving the pillar's base cuts the crate loose", _count(CRATE_AREA, M.WOOD) == 0 and _count(CRATE_AREA, M.STEEL) == 0
			and lab.world.get_voxel(Vector3i(PILLAR.x, FLOOR - 1, PILLAR.z)) == M.CONCRETE, "%d wood left in place" % _count(CRATE_AREA, M.WOOD))
	await _frames(2)
	_check("a mesh of the piece falls", lab.falling.meshes.size() == 1 and lab.falling.falling == 1,
			"%d meshes, %d falling" % [lab.falling.meshes.size(), lab.falling.falling])
	var landed := await _wait_until(func() -> bool: return lab.falling.falling == 0 and lab.falling.meshes.is_empty(), 3.0)
	_check("and lands", landed)
	var cut := steel - _count(CRATE_AREA, M.STEEL)
	_check("as voxels again, every material kept (but the cut steel)", _count(CRATE_AREA, M.WOOD) == wood and _count(CRATE_AREA, M.METAL) == metal
			and cut > 0 and cut <= 12, "%d wood, %d metal, %d steel" % [_count(CRATE_AREA, M.WOOD), _count(CRATE_AREA, M.METAL), _count(CRATE_AREA, M.STEEL)])
	var low: int = _lowest(CRATE_AREA, M.WOOD)
	_check("lower down, the pillar on the floor", low < CRATE[0].y and lab.world.get_voxel(Vector3i(PILLAR.x, FLOOR, PILLAR.z)) == M.STEEL,
			"lowest wood y %d" % low)
	_check("right under where it was", _count([Vector3i(CRATE[0].x, FLOOR, CRATE[0].z), Vector3i(CRATE[1].x, FLOOR + 22, CRATE[1].z)], M.WOOD) == wood)

	# Shot where it lies: it carves, and stays put.
	var top: int = _highest(CRATE_AREA, M.METAL)
	lab.world_sync.carve_sphere(lab.view.to_world(Vector3(31.0, top + 1.0, 31.0)), 0.2, 8, Vector3.UP) # Sheet metal is hardness 8.
	var carved := metal - _count(CRATE_AREA, M.METAL)
	await _frames(3)
	_check("the landed crate can be shot", carved > 0, "%d metal" % _count(CRATE_AREA, M.METAL))
	_check("and doesn't fall again", lab.falling.falling == 0 and lab.falling.meshes.is_empty() and _lowest(CRATE_AREA, M.WOOD) == low,
			"%d falling, lowest wood %d" % [lab.falling.falling, _lowest(CRATE_AREA, M.WOOD)])


## 2. A ceiling tile panel.
func _tiles() -> void:
	var panel := [TILES, TILES + Vector3i(20, 4, 20)]
	var tile := [TILES + Vector3i(1, 0, 1), TILES + Vector3i(10, 1, 10)]
	var tiles_before := _count(panel, M.CEILING_TILE)
	var bars_before := _count(panel, M.STEEL)
	_check("the panel hangs: four tiles of CEILING_TILE on steel bars", tiles_before == 4 * 81 and bars_before > 0,
			"%d tile, %d steel" % [tiles_before, bars_before])
	var hit := TILES + Vector3i(5, 0, 5)
	lab.world_sync.carve_sphere(lab.world.voxel_to_world(hit), lab.world.voxel_size * 0.4, 1, Vector3.DOWN)
	_check("the shot takes one voxel", lab.world.get_voxel(hit) == M.AIR and _count(panel, M.CEILING_TILE) == tiles_before - 1)
	await _frames(2)
	_check("the rest of that tile breaks loose", _count(tile, M.CEILING_TILE) == 0 and lab.falling.falling == 1,
			"%d left, %d falling" % [_count(tile, M.CEILING_TILE), lab.falling.falling])
	await _wait_until(func() -> bool: return lab.falling.falling == 0 and lab.falling.meshes.is_empty(), 3.0)
	var sheet := [Vector3i(tile[0].x, FLOOR, tile[0].z), Vector3i(tile[1].x, FLOOR + 1, tile[1].z)]
	_check("and lies on the floor as a sheet", _count(sheet, M.CEILING_TILE) == 80, "%d on the floor" % _count(sheet, M.CEILING_TILE))
	_check("the bars and the other tiles stay up", _count(panel, M.STEEL) == bars_before and _count(panel, M.CEILING_TILE) == 3 * 81,
			"%d steel, %d tile" % [_count(panel, M.STEEL), _count(panel, M.CEILING_TILE)])

	# Shot on the floor, it rests there: the shot carves it and nothing more goes.
	lab.world_sync.carve_sphere(lab.world.voxel_to_world(Vector3i(hit.x + 2, FLOOR, hit.z)), lab.world.voxel_size * 0.4, 1, Vector3.DOWN) # Not the first shot's hole.
	await _frames(3)
	_check("a tile on the floor only carves", _count(sheet, M.CEILING_TILE) == 79 and lab.falling.falling == 0 and lab.falling.meshes.is_empty(),
			"%d on the floor, %d falling" % [_count(sheet, M.CEILING_TILE), lab.falling.falling])


## 3. A piece too small to fall.
func _tiny(started: Array) -> void:
	var before := started.size()
	var area := [Vector3i(TINY.x, FLOOR, TINY.z), Vector3i(TINY.x + 2, CEILING, TINY.z + 2)]
	_check("the tiny cube hangs", _count(area, M.CONCRETE) == 8)
	lab.world_sync.carve_sphere(lab.world.voxel_to_world(TINY + Vector3i(0, 2, 0)), lab.world.voxel_size * 0.4, 3, Vector3.DOWN)
	await _frames(3)
	_check("a tiny piece crumbles: it's gone", _count(area, M.CONCRETE) == 0)
	await _wait_seconds(0.5)
	_check("nothing falls, nothing is stamped", started.size() == before and lab.falling.meshes.is_empty() and _count(area, M.CONCRETE) == 0,
			"%d falls" % (started.size() - before))


func _make_level() -> void:
	var level := LevelData.new()
	level.name = LEVEL
	level.settings = LevelData.default_settings(SIZE, "rock")
	var world := VoxelWorld.new()
	world.size_in_chunks = SIZE
	world.immediate_remesh_limit = 0
	world.detach_floating = false
	root.add_child(world)
	world.fill_all(M.CONCRETE)
	world.fill_box(ROOM[0], ROOM[1], M.AIR, false)
	world.fill_box(PILLAR, PILLAR + Vector3i(2, 14, 2), M.STEEL, false)
	world.fill_box(CRATE[0], CRATE[1], M.WOOD, false)
	world.fill_box(LID[0], LID[1], M.METAL, false)
	world.fill_box(TINY + Vector3i(0, 2, 0), TINY + Vector3i(1, 3, 1), M.STEEL, false)
	world.fill_box(TINY, TINY + Vector3i(2, 2, 2), M.CONCRETE, false)
	level.voxels = world.get_data()
	world.free()

	var spawn := LevelSchema.new_marker("spawn", PLAYER_SPOT, 0.0)
	spawn.id = "spawn_1"
	level.objects[spawn.id] = spawn
	var tiles := LevelSchema.new_prop("ceiling_tile_grid", TILES, 0)
	tiles.id = "tiles"
	level.objects[tiles.id] = tiles
	_check("level saves", level.save() == OK)


## Voxels of material in box [from, to).
func _count(box: Array, material: int) -> int:
	var n := 0
	for y in range(box[0].y, box[1].y):
		for z in range(box[0].z, box[1].z):
			for x in range(box[0].x, box[1].x):
				n += int(lab.world.get_voxel(Vector3i(x, y, z)) == material)
	return n


func _lowest(box: Array, material: int) -> int:
	for y in range(box[0].y, box[1].y):
		for z in range(box[0].z, box[1].z):
			for x in range(box[0].x, box[1].x):
				if lab.world.get_voxel(Vector3i(x, y, z)) == material:
					return y
	return -1


func _highest(box: Array, material: int) -> int:
	for y in range(box[1].y - 1, box[0].y - 1, -1):
		for z in range(box[0].z, box[1].z):
			for x in range(box[0].x, box[1].x):
				if lab.world.get_voxel(Vector3i(x, y, z)) == material:
					return y
	return -1


func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await physics_frame
	return true


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(label: String, ok: bool, detail := "") -> void:
	print("  [%s] %s %s" % ["ok" if ok else "FAIL", label, "" if ok or detail == "" else detail])
	if not ok:
		_failures += 1
