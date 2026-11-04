extends SceneTree
## Headless checks for mycelium networks (Mycelium):
##   godot --headless --path . --script res://tests/mycelium_test.gd
## Builds a scratch level (one big concrete room with mycelium nodes, a crate and a wither
## trigger), plays it solo, and checks: three nodes link into a Y (two links, not three) and the
## cluster is one connected solid; links taper from a big node to a small one; two nodes beyond
## reach stay apart; two ceiling nodes with sag bow below the straight line between them; spread
## grows a film only on the surface and only into air; the stamped network never overwrites a wall
## or a prop voxel; a player is stopped by a knot and steps over a ridge; the vein material pulses
## (palette, Mycelium.pulse and its fade); fire burns it; the `wither` action greys it all and
## removes it within 12 s, far ends first; a peer replaying the host's WorldSync edits from the
## play snapshot ends with the same voxels. Then, in edit mode, every cluster is drawn as meshes
## and moving one node redraws only its cluster. Prints how long a 10-node cluster takes.
##
## Game types are left unnamed where it matters (see editor_test.gd).

const SCRATCH := "user://mycelium_test_levels/"
const LEVEL := "mycelium_test"
const M := preload("res://scripts/voxel/voxel_materials.gd")
## Mycelium, loaded once the autoloads are up (naming it here compiles Lab too early).
var MY: GDScript
const SIZE := Vector3i(8, 3, 8)
const FLOOR := 8
const CEILING := 80
const ROOM := [Vector3i(8, FLOOR, 8), Vector3i(248, CEILING, 248)]
const LIVE := [M.ROOT, M.MYCELIUM, M.MYCELIUM_GLOW]
const CRATE := "crate_6"
const CRATE_AT := Vector3i(230, FLOOR, 208)

## id -> [position, fields]
const NODES := {
	y_a = [Vector3(40, 40, 60), {glow = 0.5}],
	y_b = [Vector3(65, 40, 85), {glow = 0.5}],
	y_c = [Vector3(65, 40, 35), {glow = 0.5}],
	taper_big = [Vector3(40, 40, 140), {radius = 8.0}],
	taper_small = [Vector3(70, 40, 140), {radius = 2.0}],
	apart_u = [Vector3(140, 40, 40), {}],
	apart_v = [Vector3(200, 40, 40), {}],
	sag_a = [Vector3(140, CEILING, 100), {radius = 3.0, sag = 1.0}],
	sag_b = [Vector3(175, CEILING, 100), {radius = 3.0, sag = 1.0}],
	film = [Vector3(215.5, FLOOR, 170.5), {radius = 3.0, spread = 25, glow = 0.5}],
	wall = [Vector3(240, 14, 215), {radius = 10.0}],
	knot = [Vector3(60.5, FLOOR, 210.5), {radius = 12.0}],
	ridge_a = [Vector3(120.5, FLOOR, 195.5), {radius = 3.0}],
	ridge_b = [Vector3(120.5, FLOOR, 230.5), {radius = 3.0}],
}

var _failures := 0
var lab
var me
var _peer: VoxelWorld
var _edits := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	LevelData.save_dir_override = SCRATCH
	MY = load("res://scripts/world/mycelium.gd")
	_make_level()
	root.get_node("Net").start_solo(LEVEL, "play")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	lab = current_scene
	me = lab.local_player()
	lab.fire.seed_rng(20261103)
	lab.items.drop_chance = 0.0
	lab.director.set_process(false)
	lab.director.set_physics_process(false)
	# The peer: the world as the host would send it, then every WorldSync voxel batch in order.
	_peer = VoxelWorld.new()
	_peer.size_in_chunks = SIZE
	_peer.immediate_remesh_limit = 0
	_peer.material_hardness = M.build_hardness()
	root.add_child(_peer)
	_peer.set_data(lab.world.get_data())
	_peer.detach_floating = lab.world.detach_floating
	_peer.max_fragment_voxels = lab.world.max_fragment_voxels
	lab.world_sync.voxels_set.connect(func(points: PackedInt32Array, materials: PackedByteArray, _removed: Dictionary) -> void:
		_edits += 1
		_peer.set_voxels(points, materials))
	await _frames(5)
	_check("the lab has a mycelium node", lab.mycelium != null and lab.mycelium == MY.find())

	_links()
	_y_solid()
	_taper()
	_apart()
	_sag()
	_film()
	_walls_and_props()
	_obstacles()
	_timing()
	await _pulse()
	await _burn()
	await _wither()
	_check("a peer replaying the host's edits has the same voxels", _edits > 0 and _peer.get_data() == lab.world.get_data(), "%d batches" % _edits)
	await _editor()

	print("mycelium test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _links() -> void:
	var plan: Dictionary = MY.plan(lab.level.objects, null)
	var ids := {}
	for link: Vector2i in plan.links:
		var pair := [plan.nodes[link.x].id, plan.nodes[link.y].id]
		pair.sort()
		ids["-".join(pair)] = true
	_check("the Y links its stem to both arms", ids.has("y_a-y_b") and ids.has("y_a-y_c"), str(ids.keys()))
	_check("but not the arms to each other (beyond reach)", not ids.has("y_b-y_c"))
	_check("nodes beyond reach stay apart", not ids.has("apart_u-apart_v"))
	_check("the sagging pair and the ridge pair link", ids.has("sag_a-sag_b") and ids.has("ridge_a-ridge_b"))
	_check("no link twice, links are symmetric", plan.links.size() == ids.size())
	var again: Dictionary = MY.plan(lab.level.objects, null)
	_check("planning is deterministic", again.links == plan.links)
	_check("clusters", MY.clusters(plan).size() == 9, str(MY.clusters(plan).size()))


func _y_solid() -> void:
	var from := Vector3i(25, 25, 20)
	var to := Vector3i(85, 56, 100)
	var total := _count(from, to, LIVE)
	var start := Vector3i(40, 40, 60)
	_check("the Y's stem node is solid", lab.world.get_voxel(start) in LIVE)
	var reached := _flood(start, from, to)
	_check("the Y is one connected solid", total > 500 and reached == total, "%d of %d" % [reached, total])
	_check("with a dark root core and glowing veins", _count(from, to, [M.ROOT]) > 0 and _count(from, to, [M.MYCELIUM_GLOW]) > 0)
	var midpoint := Vector3i(52, 40, 72)
	_check("the link reaches between the nodes", lab.world.get_voxel(midpoint) in LIVE)


func _taper() -> void:
	var near := _count(Vector3i(52, 25, 125), Vector3i(53, 56, 156), LIVE)
	var far := _count(Vector3i(64, 25, 125), Vector3i(65, 56, 156), LIVE)
	_check("a link tapers from the big node to the small one", near > far * 1.3 and far > 0, "%d near, %d far" % [near, far])


func _apart() -> void:
	_check("both apart nodes are there", lab.world.get_voxel(Vector3i(140, 40, 40)) in LIVE and lab.world.get_voxel(Vector3i(200, 40, 40)) in LIVE)
	_check("with nothing between them", _count(Vector3i(155, 25, 25), Vector3i(185, 56, 56), LIVE) == 0)


func _sag() -> void:
	var below := _count(Vector3i(154, FLOOR, 90), Vector3i(162, 72, 110), LIVE)
	_check("a sagging link bows below the straight line", below > 0, str(below))
	_check("and still reaches both ceiling nodes", lab.world.get_voxel(Vector3i(140, CEILING - 1, 100)) in LIVE and lab.world.get_voxel(Vector3i(175, CEILING - 1, 100)) in LIVE)


func _film() -> void:
	var base := _edit_world()
	var film := 0
	var off_surface := 0
	var not_air := 0
	var glow := 0
	var center := Vector2(215.5, 170.5)
	for z in range(140, 200):
		for x in range(185, 247):
			for y in range(FLOOR, FLOOR + 14):
				var p := Vector3i(x, y, z)
				var material: int = lab.world.get_voxel(p)
				if not material in LIVE:
					continue
				if base.get_voxel(p) != 0:
					not_air += 1
				if Vector2(x + 0.5, z + 0.5).distance_to(center) < 3.0 + 4.0:
					continue
				if (x - 240) * (x - 240) + (y - 14) * (y - 14) + (z - 215) * (z - 215) < 18 * 18:
					continue # The wall node's own sphere.
				film += 1
				if material == M.MYCELIUM_GLOW:
					glow += 1
				var under: int = lab.world.get_voxel(p + Vector3i.DOWN)
				if under == 0 or under in LIVE:
					off_surface += 1
	base.free()
	_check("spread grows a film around its node", film > 40, str(film))
	_check("with glowing filaments", glow > 5, str(glow))
	_check("only on the surface (one voxel, solid under it)", off_surface == 0, "%d of %d" % [off_surface, film])
	_check("and only into air", not_air == 0, str(not_air))


func _walls_and_props() -> void:
	var base := _edit_world()
	var wall_from := Vector3i(248, FLOOR - 4, 200)
	var wall_to := Vector3i(252, 30, 230)
	var changed := 0
	for p in _cells(wall_from, wall_to):
		if lab.world.get_voxel(p) != base.get_voxel(p):
			changed += 1
	base.free()
	_check("the wall node grew against the wall", _count(Vector3i(240, FLOOR, 205), Vector3i(248, 25, 226), LIVE) > 100)
	_check("but never into the wall", changed == 0, str(changed))
	var model: Dictionary = Props.orient(Props.load_prop(CRATE), 0)
	var solid: int = model.voxels.size() - model.voxels.count(0)
	_check("or into the crate", lab.world.count_matching(CRATE_AT, model.size, model.voxels) == solid)
	var touching := 0
	for p in _cells(CRATE_AT - Vector3i.ONE, CRATE_AT + model.size + Vector3i.ONE):
		if lab.world.get_voxel(p) in LIVE:
			touching += 1
	_check("which it wraps around", touching > 0, str(touching))


func _obstacles() -> void:
	var size: Vector3 = me.get_body_size()
	var step: float = me.step_height
	var feet: Vector3 = lab.view.to_world(Vector3(108, FLOOR, 212))
	var top := feet.y
	for i in 80:
		var r: Dictionary = lab.world.move_box(feet, size, Vector3(0.05, -0.03, 0.0), step, true)
		feet = r.position
		top = maxf(top, feet.y)
	_check("a player steps over a root ridge", feet.x > lab.view.to_world(Vector3(126, 0, 0)).x and top > lab.view.to_world(Vector3(0, FLOOR, 0)).y + 0.05,
			"at %s" % feet)
	feet = lab.view.to_world(Vector3(36, FLOOR, 210.5))
	for i in 80:
		var r: Dictionary = lab.world.move_box(feet, size, Vector3(0.05, -0.03, 0.0), step, true)
		feet = r.position
	_check("but is stopped by a knot", feet.x < lab.view.to_world(Vector3(50, 0, 0)).x, "at %s" % feet)
	var height := 0
	for y in range(FLOOR, FLOOR + 20):
		if lab.world.get_voxel(Vector3i(60, y, 210)) in LIVE:
			height = y - FLOOR + 1
	_check("taller than a jump", height * 0.1 > 0.85, str(height))


func _timing() -> void:
	var objects := {}
	for i in 10:
		var marker := LevelSchema.new_marker("mycelium", Vector3(100 + 20 * (i % 5), 50, 128 + 20 * (i / 5)), 0.0)
		marker.id = "time_%d" % i
		marker.glow = 0.4
		objects[marker.id] = marker
	var started := Time.get_ticks_usec()
	var plan: Dictionary = MY.plan(objects, lab.world)
	var clusters: Array = MY.clusters(plan)
	var voxels := 0
	for cluster: Dictionary in clusters:
		for model: Dictionary in MY.cluster_models(plan, cluster, lab.world):
			voxels += model.count
	var ms := (Time.get_ticks_usec() - started) / 1000.0
	print("  10-node cluster: %d links, %d voxels, voxelized in %.1f ms" % [plan.links.size(), voxels, ms])
	_check("ten nodes make one cluster", clusters.size() == 1 and voxels > 0)
	var parts: Array = MY.cluster_models(plan, clusters[0], lab.world, 2000)
	var split := 0
	for model: Dictionary in parts:
		split += model.count
	_check("a cluster over the cap is split along its links", parts.size() > 1 and split > voxels * 0.8, "%d parts, %d voxels" % [parts.size(), split])


func _pulse() -> void:
	var palette: Image = M.build_palette().get_image()
	_check("veins are in the pulsing group", palette.get_pixel(M.MYCELIUM_GLOW, 2).b > 0.9 and palette.get_pixel(M.LAMP, 2).b < 0.1
			and palette.get_pixel(M.SHROOM_SPOT, 2).b < 0.1)
	var mycelium = lab.mycelium
	_check("at rest the veins breathe gently", absf(mycelium.pulse_amount - MY.PULSE_REST) < 0.01, str(mycelium.pulse_amount))
	mycelium.pulse(1.0)
	await _frames(2)
	var shader: ShaderMaterial = lab.world.material
	_check("a pulse swells them", mycelium.pulse_amount > 0.9 and float(shader.get_shader_parameter("pulse_amount")) > 0.9,
			str(mycelium.pulse_amount))
	await _wait_seconds(MY.PULSE_SECONDS + 0.3)
	_check("and fades back", absf(mycelium.pulse_amount - MY.PULSE_REST) < 0.01, str(mycelium.pulse_amount))
	lab.play.triggered.emit("t_pulse", 1)
	await _frames(2)
	_check("the pulse trigger action pulses", mycelium.pulse_amount > 0.6, str(mycelium.pulse_amount))


func _burn() -> void:
	var from := Vector3i(46, FLOOR, 196)
	var to := Vector3i(76, FLOOR + 16, 226)
	var before := _count(from, to, LIVE)
	lab.fire.ignite(lab.view.to_world(Vector3(60.5, FLOOR + 10.5, 210.5)), 0.4, 40, false)
	var caught: bool = await _wait_until(func() -> bool: return not lab.fire.burning.is_empty(), 2.0)
	await _wait_seconds(4.0)
	var after := _count(from, to, LIVE)
	_check("fire catches the knot", caught)
	_check("and burns it away", after < before - 50, "%d -> %d" % [before, after])


func _wither() -> void:
	var everything := [Vector3i(8, FLOOR, 8), Vector3i(248, CEILING, 248)]
	lab.play.triggered.emit("t_wither", 1)
	await _frames(1)
	var dead := _count(everything[0], everything[1], [M.MYCELIUM_DEAD])
	_check("wither greys every living voxel at once", _count(everything[0], everything[1], LIVE) == 0 and dead > 1000, "%d dead" % dead)
	var started := Time.get_ticks_msec()
	await _wait_seconds(MY.WITHER_SECONDS * 0.5)
	# The film node (on the floor, so nothing of it falls loose): its knot stays, its film's far
	# edge is gone. (Nodes hanging in the air drop as loose pieces once their links are gone.)
	var stem := _count(Vector3i(214, FLOOR, 169), Vector3i(218, FLOOR + 3, 173), [M.MYCELIUM_DEAD])
	var edge := 0
	for z in range(140, 200):
		for x in range(185, 247):
			if Vector2(x + 0.5, z + 0.5).distance_to(Vector2(215.5, 170.5)) > 20.0 and lab.world.get_voxel(Vector3i(x, FLOOR, z)) == M.MYCELIUM_DEAD:
				edge += 1
	_check("from the far ends inward", stem > 0 and edge == 0, "%d at the node, %d at the film's edge" % [stem, edge])
	var gone: bool = await _wait_until(func() -> bool: return _count(everything[0], everything[1], [M.MYCELIUM_DEAD]) == 0, 12.0 - MY.WITHER_SECONDS * 0.5)
	_check("and removes it all within 12 s", gone, "%d left after %d ms" % [_count(everything[0], everything[1], [M.MYCELIUM_DEAD]), Time.get_ticks_msec() - started])
	await _wait_until(func() -> bool: return lab.fire.burning.is_empty(), 20.0)


func _editor() -> void:
	lab.request_mode("edit")
	await _frames(3)
	var meshes: Dictionary = lab.view.mycelium_meshes
	_check("edit mode draws every cluster as meshes", meshes.size() == 9, str(meshes.size()))
	var before := {}
	for key: String in meshes:
		before[key] = meshes[key].duplicate()
	var moved: Dictionary = lab.level.objects["taper_small"].duplicate()
	moved.position = moved.position + Vector3(0, 0, 3)
	lab.edits.put_object(moved, "taper_small")
	await _frames(3)
	meshes = lab.view.mycelium_meshes
	var kept := 0
	var fresh := 0
	for key: String in meshes:
		if before.has(key) and meshes[key] == before[key]:
			kept += 1
		else:
			fresh += 1
	_check("moving a node redraws only its cluster", meshes.size() == 9 and kept == 8 and fresh == 1, "%d kept, %d new" % [kept, fresh])
	_check("the edit world has no mycelium voxels", _count(Vector3i(8, FLOOR, 8), Vector3i(248, CEILING, 248), LIVE + [M.MYCELIUM_DEAD]) == 0)


# --- Helpers -------------------------------------------------------------------------------------

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
	level.voxels = world.get_data()
	world.free()
	var spawn := LevelSchema.new_marker("spawn", Vector3(180, FLOOR, 200), 0.0)
	spawn.id = "spawn_1"
	level.objects[spawn.id] = spawn
	for id: String in NODES:
		var marker := LevelSchema.new_marker("mycelium", NODES[id][0], 0.0)
		marker.id = id
		for key: String in NODES[id][1]:
			marker[key] = NODES[id][1][key]
		level.objects[id] = marker
	for action in ["wither", "pulse=0.7"]:
		var trigger := LevelSchema.new_marker("trigger", Vector3(2, 2, 2), 0.0)
		trigger.id = "t_" + action.get_slice("=", 0)
		trigger.size = Vector3i(1, 1, 1)
		trigger.actions = action
		level.objects[trigger.id] = trigger
	var crate := LevelSchema.new_prop(CRATE, CRATE_AT, 0)
	crate.id = "crate"
	crate.value = 0
	level.objects[crate.id] = crate
	_check("level saves", level.save() == OK)


## The edit-mode world (before the props and the mycelium were stamped). Free it after.
func _edit_world() -> VoxelWorld:
	var world := VoxelWorld.new()
	world.size_in_chunks = SIZE
	world.immediate_remesh_limit = 0
	root.add_child(world)
	world.set_data(lab._edit_base)
	return world


func _cells(from: Vector3i, to: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for z in range(from.z, to.z):
		for y in range(from.y, to.y):
			for x in range(from.x, to.x):
				out.append(Vector3i(x, y, z))
	return out


func _count(from: Vector3i, to: Vector3i, ids: Array) -> int:
	var box: PackedByteArray = lab.world.get_box(from, to)
	var n := 0
	for id: int in ids:
		n += box.count(id)
	return n


## Live voxels reached from start through faces, inside [from, to).
func _flood(start: Vector3i, from: Vector3i, to: Vector3i) -> int:
	var seen := {start: true}
	var queue: Array[Vector3i] = [start]
	var faces := [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		for f: Vector3i in faces:
			var q := p + f
			if seen.has(q) or q.x < from.x or q.y < from.y or q.z < from.z or q.x >= to.x or q.y >= to.y or q.z >= to.z:
				continue
			if lab.world.get_voxel(q) in LIVE:
				seen[q] = true
				queue.append(q)
	return queue.size()


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
