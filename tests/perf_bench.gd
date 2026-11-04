extends SceneTree
## Headless performance benchmark for the laboratory (see docs/perf-review-2026-11-04.md):
##   godot --headless --path . --script res://tests/perf_bench.gd -- --out=C:/abs/path/bench.json
## Plays the laboratory solo and measures, through the public surface where it can: level load,
## idle frames, shotgun / rocket carves (the calls plus the next frame, so deferred remeshing still
## counts), the voxels_changed rescans, the glass shatter scan, the shift save, the flow refresh,
## 50 enemy spawns and the enemy mesh cache, frames with 50 enemies and with homing shots, memory,
## the editor cursor pick and idle edit frames, and the SFX synthesis. Prints a table and writes a
## JSON dict (null for anything it could not measure). Headless has no GPU: only CPU costs are
## measured. Frame metrics:
##   *_frame_ms    median wall clock of main-loop iterations that ran a physics tick
##   *_tick_ms     median physics phase (physics_frame signal to the last _physics_process)
##   *_process_ms  median process phase (process_frame signal to the last _process)
##
## Game types are left untyped (see editor_test.gd). Never saves over the shipped level or the
## player's shift save (scratch folders under user://).

const M := preload("res://scripts/voxel/voxel_materials.gd")
const LEVEL := "laboratory"
const SCRATCH_LEVELS := "user://perf_bench_levels/"
const SCRATCH_SHIFT := "user://perf_bench_shift/"
const CHUNK := 32
const TIMEOUT_S := 900.0
## The room the carves, spawns and homing shots happen in (the player is moved there).
const CARVE_ROOM := "open_office"
## Built materials a carve should prefer over rock: concrete, paint, block, panel, tile.
const PREFERRED := [3, 14, 15, 40, 41, 42, 12, 13]

const HOOK_SOURCE := """extends Node
signal processed
var phys_end := 0
var proc_end := 0
var phys_count := 0
func _ready() -> void:
	process_priority = 2147483647
	process_physics_priority = 2147483647
	process_mode = Node.PROCESS_MODE_ALWAYS
func _process(_d: float) -> void:
	proc_end = Time.get_ticks_usec()
	processed.emit()
func _physics_process(_d: float) -> void:
	phys_end = Time.get_ticks_usec()
	phys_count += 1
"""

var results := {}
var notes: Array[String] = []
var _out := ""
var _hook
var _phys_start := 0
var _done := false

var lab
var me
var world
var play
var enemies
var world_sync


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	_watchdog()
	var script := GDScript.new()
	script.source_code = HOOK_SOURCE
	script.reload()
	_hook = Node.new()
	_hook.set_script(script)
	_hook.name = "PerfHook"
	root.add_child(_hook)
	physics_frame.connect(func() -> void: _phys_start = Time.get_ticks_usec())
	results.engine = Engine.get_version_info().string
	results.renderer = "headless (no GPU: GPU and draw costs are not measured)"
	LevelData.save_dir_override = SCRATCH_LEVELS # Nothing in the bench writes the shipped level.

	await _section("load", _bench_load)
	if lab == null:
		_finish(1)
		return
	await _section("idle", _bench_idle)
	await _section("voxels_changed", _bench_voxels_changed)
	await _section("glass", _bench_glass)
	await _section("save", _bench_save)
	await _section("flow", _bench_flow)
	await _section("carves", _bench_carves)
	await _section("spawn", _bench_spawn)
	await _section("enemy_tick", _bench_enemy_tick)
	await _section("homing", _bench_homing)
	await _section("memory", _bench_memory)
	await _section("editor", _bench_editor)
	await _section("sfx", _bench_sfx)
	_finish(0)


# --- Sections ------------------------------------------------------------------------------------

func _bench_load() -> void:
	var net = root.get_node("Net")
	var t0 := Time.get_ticks_usec()
	net.start_solo(LEVEL, "play")
	results.level_load_call_ms = _ms(t0)
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		var scene = current_scene
		if scene != null and scene.name == "Lab" and scene.local_player() != null and scene.play != null and scene.play.active:
			break
		await process_frame
	await physics_frame
	results.level_load_ms = _ms(t0)
	if current_scene == null or current_scene.name != "Lab":
		notes.append("the laboratory never loaded")
		return
	lab = current_scene
	me = lab.local_player()
	world = lab.world
	play = lab.play
	enemies = lab.enemies
	world_sync = lab.world_sync
	if lab.director:
		lab.director.scale_per_player = 0.0
	# Background remesh queue drained: the level is fully drawn.
	var settled := 0
	while _dirty() > 0 and settled < 1200:
		settled += 1
		await process_frame
	results.level_settle_ms = _ms(t0)
	results.level_settle_frames = settled
	results.chunks = _stat("chunks")
	results.objects = lab.level.objects.size()


func _bench_idle() -> void:
	await _frames(60)
	var sample := await _sample(120)
	_put_sample("idle", sample)


func _bench_voxels_changed() -> void:
	var feet: Vector3i = world.world_to_voxel(me.global_position)
	var small_from := Vector3i(feet.x / CHUNK * CHUNK, feet.y / CHUNK * CHUNK, feet.z / CHUNK * CHUNK)
	var small_to := small_from + Vector3i.ONE * (CHUNK - 1)
	var size: Vector3i = world.size_in_chunks * CHUNK
	var huge_from := Vector3i.ZERO
	var huge_to := size - Vector3i.ONE
	if play.has_method("_on_voxels_changed") and _arg_count(play, "_on_voxels_changed") == 2:
		results.voxels_changed_small_ms = _median_of(10, func() -> void: play._on_voxels_changed(small_from, small_to))
		results.voxels_changed_huge_ms = _median_of(10, func() -> void: play._on_voxels_changed(huge_from, huge_to))
	else:
		notes.append("LevelPlay._on_voxels_changed(from, to) is gone; voxels_changed_* not measured")
		results.voxels_changed_small_ms = null
		results.voxels_changed_huge_ms = null
	var rules = play.get("rules")
	if rules != null and rules.has_method("voxels_changed") and _arg_count(rules, "voxels_changed") == 1:
		var small_box := AABB(Vector3(small_from), Vector3(small_to - small_from + Vector3i.ONE))
		var huge_box := AABB(Vector3(huge_from), Vector3(size))
		results.rules_voxels_changed_small_ms = _median_of(10, func() -> void: rules.voxels_changed(small_box))
		results.rules_voxels_changed_huge_ms = _median_of(10, func() -> void: rules.voxels_changed(huge_box))
	else:
		notes.append("InteractRules.voxels_changed(aabb) is gone; rules_voxels_changed_* not measured")
		results.rules_voxels_changed_small_ms = null
		results.rules_voxels_changed_huge_ms = null
	await _frames(2)


func _bench_glass() -> void:
	results.glass_shatter_scan_ms = null
	var glass = play.get("_glass")
	if not play.has_method("glass_shattered") or not (glass is Dictionary) or glass.is_empty():
		notes.append("no glass case or LevelPlay.glass_shattered; glass_shatter_scan_ms skipped")
		return
	var entry: Dictionary = glass.values()[0]
	var center: Vector3 = Vector3(entry.origin) + Vector3(entry.size) * 0.5
	var at: Vector3 = lab.view.to_world(center)
	var voxel := Vector3i(center)
	results.glass_shatter_scan_ms = _median_of(5, func() -> void: play.glass_shattered([voxel], 0, at))
	await _frames(2)


func _bench_save() -> void:
	results.save_shift_ms = null
	if not lab.has_method("save_shift"):
		notes.append("Lab.save_shift is gone; save_shift_ms skipped")
		return
	var shift_save = load("res://scripts/story/shift_save.gd")
	shift_save.set("dir_override", SCRATCH_SHIFT) # Never the player's own save.
	if shift_save.get("dir_override") != SCRATCH_SHIFT:
		notes.append("could not redirect ShiftSave; save_shift_ms skipped")
		return
	var net = root.get_node("Net")
	var had_shift: bool = net.session.has("shift")
	var was = net.session.get("shift")
	net.session.shift = true
	if not lab.in_shift():
		notes.append("Lab.in_shift() false even with session.shift; save_shift_ms skipped")
	else:
		var times := []
		for i in 3:
			var t0 := Time.get_ticks_usec()
			lab.save_shift()
			times.append(_ms(t0))
			await _frames(2)
		results.save_shift_ms = _median(times)
		results.save_shift_written = FileAccess.file_exists(SCRATCH_SHIFT.path_join("shift.json"))
	if had_shift:
		net.session.shift = was
	else:
		net.session.erase("shift")


func _bench_flow() -> void:
	results.flow_refresh_ms = null
	results.flow_refresh_call_ms = null
	if not enemies.has_method("refresh_flow"):
		notes.append("EnemyManager.refresh_flow is gone; flow not measured")
		return
	var stats_ms := []
	var call_ms := []
	for i in 5:
		await _frames(2)
		var t0 := Time.get_ticks_usec()
		enemies.refresh_flow()
		call_ms.append(_ms(t0))
		stats_ms.append(float(_stat("last_flow_ms", 0.0)))
	results.flow_refresh_ms = _median(stats_ms)
	results.flow_refresh_call_ms = _median(call_ms)
	results.flow_reached = _stat("flow_reached")


func _bench_carves() -> void:
	# Indoors, among painted walls and tile (the yard spawn is cut into rock).
	var office: Dictionary = lab.level.objects.get(CARVE_ROOM, {})
	if not office.is_empty():
		var extent: Vector3i = office.to - office.from
		me.teleport(lab.view.to_world(Vector3(office.from) + Vector3(extent.x * 0.5, 0.0, extent.z * 0.5)))
		await _frames(30)
	results.carve_room = CARVE_ROOM if not office.is_empty() else "spawn"
	var eye: Vector3 = me.camera.global_position
	var soft := _targets(eye, 3, 1.5, 14.0, [0.0, -10.0, -20.0, -30.0, -45.0])
	var hard := _targets_range(eye, 4, 6, 2.0, 14.0, [0.0, -10.0])
	var blast_walls := _targets(eye, 6, 4.0, 30.0, [0.0, 5.0])
	var shotgun = _ammo("shotgun")
	var explosive = _ammo("explosive")
	results.shotgun_carve_radius = shotgun.carve_radius
	results.shotgun_carve_power = shotgun.carve_power
	results.rocket_blast_radius = explosive.blast_radius
	results.rocket_blast_power = explosive.blast_power
	var removed := [0]
	var on_carve := func(_at: Vector3, _normal: Vector3, gone: Dictionary) -> void:
		for count: int in gone.values():
			removed[0] += count
	world_sync.carved.connect(on_carve)

	# Shotgun: 8 pellets spread like the real shot, into a carvable surface.
	if soft.is_empty():
		notes.append("no carvable (hardness <= 3) surface in reach for the shotgun")
	else:
		results.shotgun_target = soft[0].material_name
		var reps := []
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234
		for i in 5:
			var target: Dictionary = soft[i % soft.size()]
			var points := _pellet_hits(eye, target.direction, shotgun.spread, shotgun.pellets, shotgun.reach, rng)
			reps.append(await _carve_rep(points, shotgun.carve_radius, shotgun.carve_power, removed))
		_put_carves("shotgun_8_carves", reps)
	if hard.is_empty():
		notes.append("no concrete-hard surface for the no-removal shotgun case")
	else:
		results.shotgun_hard_target = hard[0].material_name
		var reps := []
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		for i in 5:
			var target: Dictionary = hard[i % hard.size()]
			var points := _pellet_hits(eye, target.direction, shotgun.spread, shotgun.pellets, shotgun.reach, rng)
			reps.append(await _carve_rep(points, shotgun.carve_radius, shotgun.carve_power, removed))
		_put_carves("shotgun_8_carves_hard", reps)

	# The real shotgun through Weapon.fire (whatever batching the weapon does), plus the next frame.
	var weapon = me.weapon
	if soft.is_empty() or weapon == null or not weapon.has_method("fire"):
		results.shotgun_fire_ms = null
	else:
		if me.has_method("set_armed"):
			me.set_armed(true)
		me.inventory.add("ammo_shotgun", 40)
		weapon.select("shotgun")
		var times := []
		var calls := []
		var builds := []
		for i in 5:
			await _frames(5)
			weapon._cooldown = 0.0
			var target: Dictionary = soft[(i + 2) % soft.size()]
			var built0 := int(_stat("meshes_built", 0))
			var t0 := Time.get_ticks_usec()
			var ok: bool = weapon.fire(target.direction)
			calls.append(_ms(t0))
			await process_frame
			times.append(_ms(t0))
			builds.append(int(_stat("meshes_built", 0)) - built0)
			if not ok:
				notes.append("shotgun fire %d refused" % i)
		results.shotgun_fire_call_ms = _median(calls)
		results.shotgun_fire_ms = _median(times)
		results.shotgun_fire_meshes_built = _median(builds)

	# Rocket: one blast-sized carve into a wall.
	if blast_walls.is_empty():
		notes.append("no wall for the rocket carve")
	else:
		results.rocket_target = blast_walls[0].material_name
		var reps := []
		for i in 3:
			var target: Dictionary = blast_walls[(i * 2) % blast_walls.size()]
			reps.append(await _carve_rep([[target.position, target.normal]], explosive.blast_radius, explosive.blast_power, removed))
		_put_carves("rocket_carve", reps)
	world_sync.carved.disconnect(on_carve)
	results.max_mesh_ms_after_carves = _stat("max_mesh_ms")


func _bench_spawn() -> void:
	var enemy_script = load("res://scripts/enemies/enemy.gd")
	var models = load("res://scripts/enemies/enemy_models.gd")
	results.basic_model_files = models.paths("basic").size() if models.has_method("paths") else null
	var cache_before = _mesh_cache_size(enemy_script)
	results.mesh_cache_entries_before = cache_before
	var spots := _spawn_spots(50)
	var t0 := Time.get_ticks_usec()
	var spawned := 0
	for spot: Vector3 in spots:
		var enemy = enemies.spawn("basic", spot, 0.0)
		if enemy != null:
			spawned += 1
	results.spawn_50_call_ms = _ms(t0)
	await process_frame
	results.spawn_50_ms = _ms(t0)
	results.spawned = spawned
	results.mesh_cache_entries = _mesh_cache_size(enemy_script)
	for enemy in enemies.enemies.values():
		enemy.damage = 0.0
		enemy.max_health = 1000000.0
		enemy.health = 1000000.0
		enemy.knockback_scale = 0.0


func _bench_enemy_tick() -> void:
	await _frames(30)
	_put_sample("enemy_tick_50", await _sample(120))
	results.enemies_alive_after_tick = enemies.enemies.size()


func _bench_homing() -> void:
	var weapon = me.weapon
	results.homing_frame_ms = null
	if weapon == null or not me.inventory:
		return
	if me.has_method("set_armed"):
		me.set_armed(true)
	me.inventory.add("ammo_homing", 40)
	if not weapon.select("homing"):
		notes.append("could not select homing ammo")
		return
	# Fire into the longest free line (projectiles live reach / speed seconds) toward the crowd.
	var eye: Vector3 = me.camera.global_position
	var crowd := Vector3.ZERO
	for enemy in enemies.enemies.values():
		crowd += enemy.global_position
	crowd /= maxf(1.0, enemies.enemies.size())
	var aim := _longest_ray(eye)
	var fired := 0
	for i in 15:
		weapon._cooldown = 0.0
		if weapon.fire(_free_direction(eye, aim)):
			fired += 1
	results.homing_fired = fired
	# Keep about 15 in flight: top up (one shot per frame at most) as they land.
	var live := []
	var refills := [0]
	var sample := await _sample(60, func() -> void:
		live.append(weapon._projectiles.size())
		if weapon._projectiles.size() < 15:
			me.inventory.add("ammo_homing", 5)
			weapon._cooldown = 0.0
			if weapon.fire(_free_direction(me.camera.global_position, aim)):
				refills[0] += 1)
	_put_sample("homing", sample)
	results.homing_live_median = _median(live)
	results.homing_refills = refills[0]


func _bench_memory() -> void:
	results.memory_static_mb = OS.get_static_memory_usage() / 1048576.0
	results.memory_static_peak_mb = OS.get_static_memory_peak_usage() / 1048576.0
	results.object_count = Performance.get_monitor(Performance.OBJECT_COUNT)
	results.node_count = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	results.resource_count = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)


func _bench_editor() -> void:
	results.editor_pick_ms = null
	lab.request_mode("edit")
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline and not (lab.mode == "edit" and me.editing):
		await process_frame
	if lab.mode != "edit":
		notes.append("never reached edit mode; editor not measured")
		return
	await _frames(10)
	var tool = me.get_node_or_null("EditorTool")
	if tool == null or not tool.has_method("_update_cursor"):
		notes.append("no EditorTool._update_cursor; editor pick not measured")
		return
	tool.set_view(false) # First person: the aim is the crosshair, fixed.
	me.flying = true
	# From the spawn, 2 m up, looking toward the middle of the level and slightly down.
	var size: Vector3 = Vector3(world.size_in_chunks * CHUNK) * world.voxel_size
	var middle: Vector3 = world.global_position + size * 0.5
	var feet: Vector3 = me.global_position + Vector3.UP * 2.0
	me.teleport(feet)
	var flat := Vector3(middle.x - feet.x, 0.0, middle.z - feet.z)
	me.rotation.y = atan2(-flat.x, -flat.z)
	me.head.rotation.x = -0.2
	await _frames(5)
	results.editor_level_objects = lab.level.objects.size()
	var counts := {}
	for tool_id: int in [0, 2]: # Tool.SELECT, Tool.BOX
		tool.set_tool(tool_id)
		await _frames(3)
		counts[tool_id] = _median_of(100, func() -> void: tool._update_cursor())
	results.editor_pick_ms = counts[0]
	results.editor_pick_box_ms = counts[2]
	# After the editor fix, _update_cursor skips the pick when nothing changed; time the forced pick
	# too so the real cost of a frame where the aim moved is still visible.
	results.editor_pick_forced_ms = null
	if tool.has_method("_work_out_cursor"):
		tool.set_tool(0)
		await _frames(3)
		results.editor_pick_forced_ms = _median_of(100, func() -> void: tool._work_out_cursor(tool._aim_from, tool._aim_direction, true))
	results.editor_has_cursor = tool.has_cursor
	results.editor_object_under = tool.object_under
	tool.set_tool(0)
	results.editor_tool_process_ms = _median_of(100, func() -> void: tool._process(1.0 / 60.0))
	await _frames(10)
	var sample := await _sample(120)
	_put_sample("editor_idle", sample)


func _bench_sfx() -> void:
	var sfx = root.get_node_or_null("SfxBank")
	results.sfx_first_play_ms = null
	results.sfx_synth_ms = null
	results.sfx_ready_ms = null
	if sfx == null:
		notes.append("no SfxBank autoload")
		return
	results.sfx_bus_count = AudioServer.get_bus_count()
	var streams = sfx.get("_streams")
	results.sfx_streams_at_end = streams.size() if streams is Dictionary else null
	# A sound nothing in the bench plays.
	var sound := "sting_gameover"
	var t0 := Time.get_ticks_usec()
	sfx.play(sound)
	results.sfx_first_play_ms = _ms(t0)
	t0 = Time.get_ticks_usec()
	sfx.play(sound)
	results.sfx_second_play_ms = _ms(t0)
	if sfx.has_method("_synthesize_all"):
		t0 = Time.get_ticks_usec()
		var samples = sfx._synthesize_all()
		results.sfx_synth_ms = _ms(t0)
		results.sfx_samples = samples
	else:
		notes.append("Sfx._synthesize_all is gone; sfx_synth_ms not measured")
	# _ready of a fresh SfxBank (the autoload's own ran before this script; see its log line).
	var script = sfx.get_script()
	var fresh = script.new()
	t0 = Time.get_ticks_usec()
	root.add_child(fresh)
	results.sfx_ready_ms = _ms(t0)
	root.remove_child(fresh)
	fresh.free()
	script.set("_instance", sfx)


# --- Measuring -----------------------------------------------------------------------------------

## Runs the main loop until `ticks` physics ticks have run (or 60 s), timing each iteration.
func _sample(ticks: int, each := Callable()) -> Dictionary:
	var walls := []
	var phys := []
	var procs := []
	await process_frame
	var last := Time.get_ticks_usec()
	var last_count: int = _hook.phys_count
	var deadline := Time.get_ticks_msec() + 60000
	while phys.size() < ticks and Time.get_ticks_msec() < deadline:
		await process_frame
		var now := Time.get_ticks_usec()
		procs.append((_hook.proc_end - last) / 1000.0)
		if _hook.phys_count != last_count:
			phys.append((_hook.phys_end - _phys_start) / 1000.0)
			walls.append((now - last) / 1000.0)
			last_count = _hook.phys_count
		if each.is_valid():
			each.call()
		last = now
	return {frame = _median(walls), tick = _median(phys), process = _median(procs), p95 = _percentile(walls, 0.95), frames = procs.size(), ticks = phys.size()}


func _put_sample(prefix: String, sample: Dictionary) -> void:
	results[prefix + "_frame_ms"] = sample.frame
	results[prefix + "_tick_ms"] = sample.tick
	results[prefix + "_process_ms"] = sample.process
	results[prefix + "_frame_p95_ms"] = sample.p95
	results[prefix + "_frames"] = sample.frames


## One batch of carves (points: [[position, normal], ...]) through WorldSync: the calls, the calls
## plus the rest of that frame and the next tick (deferred remeshing included), and until the
## remesh queue is back where it was.
func _carve_rep(points: Array, radius: float, power: int, removed: Array) -> Dictionary:
	await _frames(5)
	var dirty0 := _dirty()
	var built0 := int(_stat("meshes_built", 0))
	removed[0] = 0
	var t0 := Time.get_ticks_usec()
	for p: Array in points:
		world_sync.carve_sphere(p[0], radius, power, p[1])
	var call_ms := _ms(t0)
	await process_frame
	var next_ms := _ms(t0)
	var stats: Dictionary = world.get_stats()
	var built := int(stats.get("meshes_built", 0)) - built0
	var frames := 1
	while _dirty() > dirty0 and frames < 240:
		frames += 1
		await process_frame
	return {call = call_ms, next = next_ms, settle = _ms(t0), settle_frames = frames, built = built,
			built_settled = int(_stat("meshes_built", 0)) - built0, last_mesh = stats.get("last_mesh_ms"),
			max_mesh = stats.get("max_mesh_ms"), removed = removed[0], count = points.size()}


func _put_carves(prefix: String, reps: Array) -> void:
	var pick := func(key: String) -> Array: return reps.map(func(r: Dictionary): return r[key])
	results[prefix + "_call_ms"] = _median(pick.call("call"))
	results[prefix + "_ms"] = _median(pick.call("next"))
	results[prefix + "_settle_ms"] = _median(pick.call("settle"))
	results[prefix + "_settle_frames"] = _median(pick.call("settle_frames"))
	results[prefix + "_meshes_built"] = _median(pick.call("built"))
	results[prefix + "_meshes_built_settled"] = _median(pick.call("built_settled"))
	results[prefix + "_last_mesh_ms"] = _median(pick.call("last_mesh"))
	results[prefix + "_max_mesh_ms"] = pick.call("max_mesh").max()
	results[prefix + "_removed"] = _median(pick.call("removed"))
	results[prefix + "_calls"] = reps[0].count


## Median ms of `count` synchronous calls.
func _median_of(count: int, body: Callable) -> float:
	var times := []
	for i in count:
		var t0 := Time.get_ticks_usec()
		body.call()
		times.append(_ms(t0))
	return _median(times)


# --- Targets -------------------------------------------------------------------------------------

## Surfaces in reach whose material a carve of `power` can cut: [{direction, position, normal,
## material_name}], one per yaw, nearest first.
func _targets(eye: Vector3, power: int, near: float, far: float, pitches: Array) -> Array:
	return _targets_range(eye, 0, power, near, far, pitches)


func _targets_range(eye: Vector3, min_hardness: int, max_hardness: int, near: float, far: float, pitches: Array) -> Array:
	var found := []
	for yaw_step in 24:
		var yaw := deg_to_rad(yaw_step * 15.0)
		for pitch: float in pitches:
			var p := deg_to_rad(pitch)
			var direction := Vector3(-sin(yaw) * cos(p), sin(p), -cos(yaw) * cos(p))
			var hit: Dictionary = world.raycast(eye, direction, far)
			if not hit.hit or float(hit.distance) < near:
				continue
			var material := int(hit.material)
			var hardness := int(M.DEFS.get(material, {}).get("hardness", 255))
			if hardness < min_hardness or hardness > max_hardness:
				continue
			found.append({direction = direction, position = hit.position, normal = Vector3(hit.normal),
					material_name = "%s (%d, hardness %d, %.1f m)" % [M.get_material_name(material), material, hardness, hit.distance],
					distance = float(hit.distance), preferred = material in PREFERRED})
			break
	# Built surfaces (walls, tile) first, then the nearest.
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.preferred != b.preferred:
			return a.preferred
		return a.distance < b.distance)
	return found


## Where `pellets` rays spread over `spread` degrees around direction land: [[position, normal]].
func _pellet_hits(eye: Vector3, direction: Vector3, spread: float, pellets: int, reach: float, rng: RandomNumberGenerator) -> Array:
	var out := []
	var side := direction.cross(Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT).normalized()
	var up := side.cross(direction).normalized()
	for i in pellets:
		var angle := deg_to_rad(spread) * sqrt(rng.randf())
		var turn := rng.randf() * TAU
		var d := (direction * cos(angle) + (side * cos(turn) + up * sin(turn)) * sin(angle)).normalized()
		var hit: Dictionary = world.raycast(eye, d, reach)
		if hit.hit:
			out.append([hit.position, Vector3(hit.normal)])
	return out


## The horizontal direction with the most free space in front of eye (so shots stay in flight).
func _longest_ray(eye: Vector3) -> Vector3:
	var best := Vector3.FORWARD
	var best_distance := -1.0
	for yaw_step in 36:
		var yaw := deg_to_rad(yaw_step * 10.0)
		var direction := Vector3(-sin(yaw), 0.05, -cos(yaw)).normalized()
		var hit: Dictionary = world.raycast(eye, direction, 80.0)
		var distance: float = float(hit.distance) if hit.hit else 80.0
		if distance > best_distance:
			best_distance = distance
			best = direction
	results.homing_free_distance = best_distance
	return best


## aim jittered a little.
func _free_direction(_eye: Vector3, aim: Vector3) -> Vector3:
	return (aim + Vector3(randf_range(-0.08, 0.08), randf_range(-0.02, 0.06), randf_range(-0.08, 0.08))).normalized()


## Feet positions on a grid around the player, in open air on the player's floor.
func _spawn_spots(count: int) -> Array:
	var spots := []
	var base: Vector3 = me.global_position
	var ring := 3.0
	while spots.size() < count and ring < 20.0:
		var steps := int(TAU * ring / 1.0)
		for i in steps:
			var a := TAU * i / steps
			var feet := base + Vector3(cos(a), 0.0, sin(a)) * ring
			var cell: Vector3i = world.world_to_voxel(feet + Vector3.UP * 0.3)
			var head: Vector3i = world.world_to_voxel(feet + Vector3.UP * 1.0)
			if world.get_voxel(cell) == M.AIR and world.get_voxel(head) == M.AIR:
				spots.append(feet)
				if spots.size() >= count:
					break
		ring += 1.0
	while spots.size() < count:
		spots.append(base + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0)))
	return spots


# --- Helpers -------------------------------------------------------------------------------------

func _ammo(ammo_name: String):
	return load("res://scripts/weapons/ammo_type.gd").by_name(ammo_name)


func _mesh_cache_size(enemy_script):
	for key in ["_meshes", "_mesh_cache", "meshes"]:
		var cache = enemy_script.get(key)
		if cache is Dictionary:
			return cache.size()
	notes.append("no static mesh cache found on Enemy")
	return null


func _stat(key: String, fallback = null):
	return world.get_stats().get(key, fallback)


func _dirty() -> int:
	return int(_stat("chunks_dirty", 0))


func _arg_count(object: Object, method: String) -> int:
	for info: Dictionary in object.get_method_list():
		if info.name == method:
			return info.args.size()
	return -1


func _section(label: String, body: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	print("perf_bench: %s..." % label)
	await body.call()
	print("perf_bench: %s done in %.0f ms" % [label, _ms(t0)])
	_write()


func _ms(t0: int) -> float:
	return (Time.get_ticks_usec() - t0) / 1000.0


func _median(values: Array):
	var clean := values.filter(func(v) -> bool: return v != null)
	if clean.is_empty():
		return null
	clean.sort()
	var n := clean.size()
	return clean[n / 2] if n % 2 == 1 else (clean[n / 2 - 1] + clean[n / 2]) / 2.0


func _percentile(values: Array, q: float):
	if values.is_empty():
		return null
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(ceil(q * sorted.size())) - 1, 0, sorted.size() - 1)]


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _watchdog() -> void:
	await create_timer(TIMEOUT_S, true, false, true).timeout
	if not _done:
		notes.append("timed out after %d s" % TIMEOUT_S)
		_finish(2)


func _write() -> void:
	results.notes = notes
	if _out == "":
		return
	var file := FileAccess.open(_out, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(results, "\t", true))
	else:
		push_error("perf_bench: cannot write %s" % _out)


func _finish(code: int) -> void:
	if _done:
		return
	_done = true
	_write()
	print("")
	print("perf_bench results (headless: CPU only, GPU and draw costs are not measured)")
	print("%-44s %s" % ["key", "value"])
	var keys := results.keys().map(func(k) -> String: return str(k))
	keys.sort()
	for key: String in keys:
		if key == "notes":
			continue
		var value = results[key]
		var text := "null" if value == null else ("%.3f" % value if value is float else str(value))
		print("%-44s %s" % [key, text])
	for note in notes:
		print("note: " + note)
	if _out != "":
		print("written to " + _out)
	quit(code)
