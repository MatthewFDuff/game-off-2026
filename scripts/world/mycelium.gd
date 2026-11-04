class_name Mycelium
extends Node3D
## Mycelium networks: `mycelium` markers (LevelSchema) are nodes that connect by themselves into
## root and tentacle shapes. The network is an isosurface sampled straight into voxels: every node
## is a sphere, every link a capsule tapering from one node's radius to the other's, and a voxel is
## solid where the smooth union of them (smooth-min) is inside, plus a little low-frequency noise so
## it isn't a tube. `sag` bows links downward (hanging tendrils). Material by depth: a ROOT core
## under a MYCELIUM skin, with MYCELIUM_GLOW veins spiralling along links and spotting the nodes
## (how much: `glow`). `spread` grows a one-voxel film of MYCELIUM with glowing filaments over the
## surface a node sits on (a random walk seeded by the node's id).
##
## Links: every node links to its nearest nodes (at most `links` each) within `reach` (either
## node's), nearest pairs first, never through a wall. Connected nodes make a cluster, voxelized
## into its bounding box; a cluster over MAX_CLUSTER voxels is split along its links.
##
## Edit mode: LevelView draws each cluster as a mesh (plan + cluster_models). Play: the host stamps
## the clusters into the voxels when play starts (plan_level before the props go in, so links see
## only the level's walls; stamp_level after, into air only), and the snapshot carries them to the
## peers. Everything after that goes through WorldSync:
##   pulse(strength)  host: the PULSING veins' travelling wave swells for PULSE_SECONDS on every
##                    peer (the terrain shader's pulse_amount). Intercom trigger lines and the
##                    mommy getting hurt pulse it; so does the trigger action `pulse[=strength]`.
##   wither()         host: every mycelium voxel turns MYCELIUM_DEAD, then over WITHER_SECONDS they
##                    are removed from the far ends inward (by distance from the nearest node), one
##                    set_voxels batch every WITHER_STEP, crumbling to grey debris (the trigger
##                    action `wither`).
## Hardness 1 and flammable (VoxelMaterials), so fire burns it and enemies dig it like substrate.

const M := preload("res://scripts/voxel/voxel_materials.gd")

const GROUP := "mycelium"
const TYPE := "mycelium"
## Most voxels in one cluster; a bigger one is split along its links.
const MAX_CLUSTER := 60000
## Smooth-min blend distance (voxels) where spheres and links meet.
const SMOOTH := 2.5
## Cells within this of a primitive (voxels) are evaluated: covers the blend and the noise.
const MARGIN := 5.0
## A link's radius against its nodes' (tapering from one to the other), how much it thins in the
## middle, and the thinnest a link gets.
const LINK_SCALE := 0.6
const NECK := 0.25
const MIN_LINK_RADIUS := 1.2
## Surface noise: amplitude (voxels, less on thin parts), frequency and seed.
const NOISE_AMP := 0.9
const NOISE_FREQUENCY := 0.08
const NOISE_SEED := 4127
## Voxels deeper than this under the surface are ROOT.
const SKIN := 1.6
## sag 1 drops a link's middle by this share of its length; sagging links are drawn in segments.
const SAG_DROP := 0.35
const SAG_SEGMENTS := 6
## Veins: stripes around a link, voxels per turn of the spiral, and the cell size of node spots.
const STRIPES := 3
const STRIPE_PITCH := 14.0
const SPOT_CELL := 3
## Solid voxels a link may pass through away from its two nodes (more: it's behind a wall).
const LOS_SOLID := 1
## Film walkers per node at most.
const FILM_MAX_WALKERS := 16
const WITHER_SECONDS := 10.0
const WITHER_STEP := 0.2
## pulse_amount at rest (the veins breathe gently) and how long a pulse takes to fade.
const PULSE_REST := 0.25
const PULSE_SECONDS := 3.0
const INTERCOM_PULSE := 0.6
const HURT_PULSE := 1.0
## Host: least seconds between hurt pulses (every hit on the mommy would be an RPC).
const HURT_GAP := 0.5

## The materials a network is made of (wither turns these to MYCELIUM_DEAD).
const LIVE := [M.ROOT, M.MYCELIUM, M.MYCELIUM_GLOW]

@export var lab: Lab
@export var world: VoxelWorld
@export var world_sync: WorldSync

## Every peer: the shader's pulse_amount now.
var pulse_amount := PULSE_REST
## Host: voxels stamped this play (x, y, z each) and their distance from the nearest node.
var stamped_points := PackedInt32Array()
var stamped_dist := PackedFloat32Array()
## Host: true while withering.
var withering := false

var _plan := {}
var _pulse_peak := PULSE_REST
var _pulse_time := PULSE_SECONDS
var _shader_amount := -1.0
var _hurt_at := -1000.0
## Host, withering: buckets of point indices (far first), the next one, and the time to it.
var _buckets: Array = []
var _bucket := 0
var _wither_timer := 0.0

static var _noise: FastNoiseLite


## Every peer: the level's Mycelium, or null.
static func find() -> Mycelium:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.get_first_node_in_group(GROUP) as Mycelium if tree else null


func _ready() -> void:
	add_to_group(GROUP)
	if lab == null:
		return
	# Play stamps (stamp_level) before mode_changed goes out; only leaving play forgets the voxels.
	lab.mode_changed.connect(func(mode: String) -> void:
		if mode != "play":
			_reset())
	world_sync.voxels_set.connect(_on_voxels_set)
	if lab.play:
		lab.play.triggered.connect(func(id: String, _peer: int) -> void:
			if Lines.INTERCOM.has(id):
				pulse(INTERCOM_PULSE))
	if lab.enemies:
		lab.enemies.enemy_damaged.connect(func(enemy: Enemy, _amount: float, _zone: String) -> void:
			if enemy.kind == "mommy" and Time.get_ticks_msec() / 1000.0 - _hurt_at >= HURT_GAP:
				_hurt_at = Time.get_ticks_msec() / 1000.0
				pulse(HURT_PULSE))


func _reset() -> void:
	stamped_points = PackedInt32Array()
	stamped_dist = PackedFloat32Array()
	withering = false
	_buckets.clear()
	_pulse_peak = PULSE_REST
	_pulse_time = PULSE_SECONDS


# --- Play: stamping ------------------------------------------------------------------------------

## Host, entering play, before the props are stamped: links the level's nodes against its walls.
func plan_level() -> void:
	_plan = plan(lab.level.objects, world)


## Host, entering play, after the props: stamps every cluster into air (never into walls or props)
## and remembers the voxels for wither. The snapshot sent next carries them to the peers.
func stamp_level() -> void:
	_reset()
	if _plan.is_empty():
		plan_level()
	var started := Time.get_ticks_msec()
	for cluster: Dictionary in clusters(_plan):
		for model: Dictionary in cluster_models(_plan, cluster, world):
			world.stamp(model.origin, model.size, model.voxels, true)
			_track(model)
	if not stamped_dist.is_empty():
		print("mycelium: %d voxels stamped in %d ms" % [stamped_dist.size(), Time.get_ticks_msec() - started])
	_plan = {}


func _track(model: Dictionary) -> void:
	var size: Vector3i = model.size
	var origin: Vector3i = model.origin
	var voxels: PackedByteArray = model.voxels
	var dist: PackedFloat32Array = model.dist
	for i in voxels.size():
		var material := voxels[i]
		if material == 0:
			continue
		var p := origin + Vector3i(i % size.x, (i / size.x) % size.y, i / (size.x * size.y))
		if world.get_voxel(p) != material:
			continue
		stamped_points.append(p.x)
		stamped_points.append(p.y)
		stamped_points.append(p.z)
		stamped_dist.append(dist[i])


# --- Pulse ---------------------------------------------------------------------------------------

## Host: the veins pulse harder (strength 0..1) on every peer, fading over PULSE_SECONDS.
func pulse(strength: float) -> void:
	if not multiplayer.is_server():
		return
	_apply_pulse(strength)
	for peer_id in world_sync.synced_peers():
		_apply_pulse.rpc_id(peer_id, strength)


@rpc("authority", "reliable")
func _apply_pulse(strength: float) -> void:
	_pulse_peak = maxf(pulse_amount, clampf(strength, 0.0, 1.0))
	_pulse_time = 0.0


func _process(delta: float) -> void:
	_pulse_time += delta
	var fade := clampf(1.0 - _pulse_time / PULSE_SECONDS, 0.0, 1.0)
	pulse_amount = PULSE_REST + maxf(_pulse_peak - PULSE_REST, 0.0) * fade
	if world and absf(pulse_amount - _shader_amount) > 0.001:
		_shader_amount = pulse_amount
		var shader := world.material as ShaderMaterial
		if shader:
			shader.set_shader_parameter("pulse_amount", pulse_amount)
	if withering and multiplayer.is_server():
		_wither_timer -= delta
		while withering and _wither_timer <= 0.0:
			_wither_timer += WITHER_STEP
			_wither_step()


# --- Wither --------------------------------------------------------------------------------------

## Host: the colony dies. Every mycelium voxel greys at once, then crumbles away from the far ends
## inward over WITHER_SECONDS.
func wither() -> void:
	if not multiplayer.is_server() or withering:
		return
	var count := stamped_dist.size()
	var points := PackedInt32Array()
	var keep := PackedInt32Array()
	var max_dist := 0.0
	for i in count:
		var p := Vector3i(stamped_points[i * 3], stamped_points[i * 3 + 1], stamped_points[i * 3 + 2])
		if world.get_voxel(p) in LIVE:
			points.append_array([p.x, p.y, p.z])
			keep.append(i)
			max_dist = maxf(max_dist, stamped_dist[i])
	var dead := PackedByteArray()
	dead.resize(keep.size())
	dead.fill(M.MYCELIUM_DEAD)
	if not keep.is_empty():
		world_sync.set_voxels(points, dead)
	var steps := maxi(1, int(round(WITHER_SECONDS / WITHER_STEP)))
	_buckets.clear()
	for b in steps:
		_buckets.append([])
	for i in keep:
		var share := 1.0 - stamped_dist[i] / maxf(max_dist, 0.001)
		var b := clampi(int(share * steps), 0, steps - 1)
		_buckets[b].append(i)
	_bucket = 0
	_wither_timer = WITHER_STEP
	withering = true


func _wither_step() -> void:
	if _bucket >= _buckets.size():
		withering = false
		return
	var points := PackedInt32Array()
	for i: int in _buckets[_bucket]:
		var p := Vector3i(stamped_points[i * 3], stamped_points[i * 3 + 1], stamped_points[i * 3 + 2])
		if world.get_voxel(p) == M.MYCELIUM_DEAD:
			points.append_array([p.x, p.y, p.z])
	_bucket += 1
	if not points.is_empty():
		var air := PackedByteArray()
		air.resize(points.size() / 3)
		world_sync.set_voxels(points, air)
	if _bucket >= _buckets.size():
		withering = false


## Every peer: withered voxels crumbling make grey debris and a dry crumble.
func _on_voxels_set(points: PackedInt32Array, _materials: PackedByteArray, removed: Dictionary) -> void:
	var count: int = removed.get(M.MYCELIUM_DEAD, 0)
	if count == 0 or points.is_empty():
		return
	var center := Vector3.ZERO
	var samples := mini(points.size() / 3, 32)
	for i in samples:
		var at := (points.size() / 3) * i / samples
		center += Vector3(points[at * 3], points[at * 3 + 1], points[at * 3 + 2])
	center = world.voxel_to_world(Vector3i((center / samples).floor()))
	if lab and lab.debris:
		lab.debris.burst(center, Vector3.UP, {M.MYCELIUM_DEAD: count})
	Sfx.play_at("chip", center, -8.0, 0.3, 0.6)


# --- The network (static: LevelView uses it in edit mode) ---------------------------------------

## The level's mycelium nodes, sorted by id, with their fields clamped.
static func nodes_of(objects: Dictionary) -> Array:
	var ids: Array = []
	for id: String in objects:
		var object: Dictionary = objects[id]
		if object.get("kind") == "marker" and object.get("type") == TYPE:
			ids.append(id)
	ids.sort()
	var nodes: Array = []
	for id: String in ids:
		var o: Dictionary = objects[id]
		nodes.append({id = id, at = Vector3(o.position), radius = clampf(float(o.get("radius", 4)), 1.0, 12.0),
				reach = maxf(float(o.get("reach", 40)), 0.0), links = maxi(int(o.get("links", 3)), 0),
				sag = clampf(float(o.get("sag", 0.0)), 0.0, 1.0), glow = clampf(float(o.get("glow", 0.3)), 0.0, 1.0),
				spread = clampi(int(o.get("spread", 0)), 0, 30)})
	return nodes


## The nodes and their links: {nodes, links: Array of Vector2i (node indices, x < y)}. Pairs within
## either node's reach are taken nearest first while both nodes have links to spare, and only when
## the link doesn't pass through a wall. Deterministic.
static func plan(objects: Dictionary, voxel_world: VoxelWorld) -> Dictionary:
	var nodes := nodes_of(objects)
	var candidates: Array = []
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			var d: float = nodes[i].at.distance_to(nodes[j].at)
			if d <= maxf(nodes[i].reach, nodes[j].reach) and d > 0.0:
				candidates.append([d, i, j])
	candidates.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] if a[0] != b[0] else (a[1] < b[1] if a[1] != b[1] else a[2] < b[2]))
	var degree := PackedInt32Array()
	degree.resize(nodes.size())
	var links: Array = []
	for c: Array in candidates:
		var i: int = c[1]
		var j: int = c[2]
		if degree[i] >= nodes[i].links or degree[j] >= nodes[j].links:
			continue
		if voxel_world and not _clear_path(voxel_world, nodes[i], nodes[j]):
			continue
		degree[i] += 1
		degree[j] += 1
		links.append(Vector2i(i, j))
	return {nodes = nodes, links = links}


## A link's middle drops this many voxels.
static func sag_drop(a: Dictionary, b: Dictionary) -> float:
	return (a.sag + b.sag) * 0.5 * a.at.distance_to(b.at) * SAG_DROP


static func curve(a: Vector3, b: Vector3, drop: float, t: float) -> Vector3:
	return a.lerp(b, t) + Vector3.DOWN * drop * 4.0 * t * (1.0 - t)


static func _clear_path(voxel_world: VoxelWorld, a: Dictionary, b: Dictionary) -> bool:
	var drop := sag_drop(a, b)
	var length: float = a.at.distance_to(b.at) + drop
	var samples := maxi(2, ceili(length))
	var solid := 0
	for s in range(1, samples):
		var p := curve(a.at, b.at, drop, float(s) / samples)
		if p.distance_to(a.at) <= a.radius + 1.0 or p.distance_to(b.at) <= b.radius + 1.0:
			continue
		if voxel_world.get_voxel(Vector3i(p.floor())) != 0:
			solid += 1
			if solid > LOS_SOLID:
				return false
	return true


## Connected nodes: Array of {nodes: Array[int], links: Array[Vector2i], key: String}, ordered by
## their first node. key changes whenever anything that shapes the cluster does (LevelView).
static func clusters(the_plan: Dictionary) -> Array:
	var nodes: Array = the_plan.nodes
	var parent := range(nodes.size())
	var root := func(i: int) -> int:
		while parent[i] != i:
			parent[i] = parent[parent[i]]
			i = parent[i]
		return i
	for link: Vector2i in the_plan.links:
		var a: int = root.call(link.x)
		var b: int = root.call(link.y)
		if a != b:
			parent[maxi(a, b)] = mini(a, b)
	var by_root := {}
	var order: Array = []
	for i in nodes.size():
		var r: int = root.call(i)
		if not by_root.has(r):
			by_root[r] = {nodes = [], links = [], key = ""}
			order.append(r)
		by_root[r].nodes.append(i)
	for link: Vector2i in the_plan.links:
		by_root[root.call(link.x)].links.append(link)
	var out: Array = []
	for r: int in order:
		var cluster: Dictionary = by_root[r]
		var parts: Array = []
		for i: int in cluster.nodes:
			parts.append(nodes[i])
		cluster.key = JSON.stringify([parts, cluster.links.map(func(l: Vector2i) -> Array: return [nodes[l.x].id, nodes[l.y].id])])
		out.append(cluster)
	return out


## A cluster as stamp-ready models (more than one when it's over MAX_CLUSTER), each {origin, size,
## voxels, dist (per voxel: distance from the nearest node), count}. Only the world's air is filled.
static func cluster_models(the_plan: Dictionary, cluster: Dictionary, voxel_world: VoxelWorld, cap := MAX_CLUSTER) -> Array:
	var model := voxelize(the_plan.nodes, cluster.nodes, cluster.links, voxel_world)
	if model.count <= cap or cluster.nodes.size() < 2:
		return [model] if model.count > 0 else []
	# Split along the links: the first half of the nodes in walk order, and the rest.
	var adjacent := {}
	for link: Vector2i in cluster.links:
		adjacent.get_or_add(link.x, []).append(link.y)
		adjacent.get_or_add(link.y, []).append(link.x)
	var walk: Array = [cluster.nodes[0]]
	var seen := {cluster.nodes[0]: true}
	var next := 0
	while next < walk.size():
		var around: Array = adjacent.get(walk[next], [])
		around.sort()
		for other: int in around:
			if not seen.has(other) and other in cluster.nodes:
				seen[other] = true
				walk.append(other)
		next += 1
	for i: int in cluster.nodes:
		if not seen.has(i):
			walk.append(i)
	var first := walk.slice(0, walk.size() / 2)
	var second := walk.slice(walk.size() / 2)
	var a := {nodes = first, links = [], key = ""}
	var b := {nodes = second, links = [], key = ""}
	for link: Vector2i in cluster.links:
		(b if link.x in second and link.y in second else a).links.append(link)
	return cluster_models(the_plan, a, voxel_world, cap) + cluster_models(the_plan, b, voxel_world, cap)


static func _link_radius(ra: float, rb: float, t: float) -> float:
	return maxf(MIN_LINK_RADIUS, lerpf(ra, rb, t) * LINK_SCALE * (1.0 - NECK * sin(PI * t)))


## Voxelizes the spheres of nodes `indices` and the links into their bounding box (see the top).
static func voxelize(nodes: Array, indices: Array, links: Array, voxel_world: VoxelWorld) -> Dictionary:
	var empty := {origin = Vector3i.ZERO, size = Vector3i.ZERO, voxels = PackedByteArray(), dist = PackedFloat32Array(), count = 0}
	# Primitives: [a, b, ra, rb, glow, kind (0 node, 1 link), link length, t0, t1, u, v1, v2, center]
	var prims: Array = []
	for i: int in indices:
		var n: Dictionary = nodes[i]
		prims.append([n.at, n.at, n.radius, n.radius, n.glow, 0, 0.0, 0.0, 0.0, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, n.at])
	for link: Vector2i in links:
		var na: Dictionary = nodes[link.x]
		var nb: Dictionary = nodes[link.y]
		var drop := sag_drop(na, nb)
		var segments := 1 if drop < 0.5 else SAG_SEGMENTS
		var chord: Vector3 = nb.at - na.at
		var u := chord.normalized()
		var v1 := u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized()
		var v2 := u.cross(v1)
		var glow: float = (na.glow + nb.glow) * 0.5
		for s in segments:
			var t0 := float(s) / segments
			var t1 := float(s + 1) / segments
			prims.append([curve(na.at, nb.at, drop, t0), curve(na.at, nb.at, drop, t1), _link_radius(na.radius, nb.radius, t0),
					_link_radius(na.radius, nb.radius, t1), glow, 1, chord.length(), t0, t1, u, v1, v2, na.at])
	if prims.is_empty():
		return empty

	# Film: each spreading node's surface (the normal away from it) and in-plane axes.
	var films: Array = []
	for i: int in indices:
		var n: Dictionary = nodes[i]
		if n.spread <= 0:
			continue
		var normal := surface_of(voxel_world, n.at, ceili(n.radius) + 3)
		if normal != Vector3i.ZERO:
			films.append([n, normal])

	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p: Array in prims:
		var r := maxf(p[2], p[3]) + MARGIN
		lo = lo.min(p[0].min(p[1]) - Vector3.ONE * r)
		hi = hi.max(p[0].max(p[1]) + Vector3.ONE * r)
	for f: Array in films:
		var reach: Vector3 = Vector3.ONE * (f[0].spread + 3)
		lo = lo.min(f[0].at - reach)
		hi = hi.max(f[0].at + reach)
	var world_size := voxel_world.get_size_in_voxels()
	var origin := Vector3i(lo.floor()).clamp(Vector3i.ZERO, world_size)
	var end := Vector3i(hi.ceil()).clamp(Vector3i.ZERO, world_size)
	var size := end - origin
	if size.x <= 0 or size.y <= 0 or size.z <= 0:
		return empty
	var sx := size.x
	var sxy := size.x * size.y
	var total := sxy * size.z

	var field := PackedFloat32Array()
	field.resize(total)
	field.fill(1e6)
	var best := field.duplicate()
	var owner := PackedInt32Array()
	owner.resize(total)
	owner.fill(-1)
	var param := PackedFloat32Array()
	param.resize(total)
	var touched := PackedInt32Array()

	for pi in prims.size():
		var p: Array = prims[pi]
		var a: Vector3 = p[0]
		var b: Vector3 = p[1]
		var ra: float = p[2]
		var rb: float = p[3]
		var w := b - a
		var l2 := w.length_squared()
		var bound := maxf(ra, rb) + MARGIN
		var plo := (Vector3i((a.min(b) - Vector3.ONE * bound).floor()) - origin).clamp(Vector3i.ZERO, size)
		var phi := (Vector3i((a.max(b) + Vector3.ONE * bound).ceil()) - origin).clamp(Vector3i.ZERO, size)
		for z in range(plo.z, phi.z):
			var cz := origin.z + z + 0.5
			for y in range(plo.y, phi.y):
				var cy := origin.y + y + 0.5
				var span := _row_span(a, b, bound, cy, cz)
				if span.x > span.y:
					continue
				var x0 := maxi(plo.x, ceili(span.x - 0.5) - origin.x)
				var x1 := mini(phi.x - 1, floori(span.y - 0.5) - origin.x)
				var row := y * sx + z * sxy
				for x in range(x0, x1 + 1):
					var c := Vector3(origin.x + x + 0.5, cy, cz)
					var t := 0.0
					var d: float
					if l2 < 1e-6:
						d = c.distance_to(a) - ra
					else:
						t = clampf((c - a).dot(w) / l2, 0.0, 1.0)
						d = c.distance_to(a + w * t) - lerpf(ra, rb, t)
					var i := row + x
					var f := field[i]
					if f >= 1e5:
						touched.append(i)
						field[i] = d
					else:
						var h := maxf(SMOOTH - absf(f - d), 0.0) / SMOOTH
						field[i] = minf(f, d) - h * h * SMOOTH * 0.25
					if d < best[i]:
						best[i] = d
						owner[i] = pi
						param[i] = t

	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.seed = NOISE_SEED
		_noise.frequency = NOISE_FREQUENCY
	var here := voxel_world.get_box(origin, end)
	var voxels := PackedByteArray()
	voxels.resize(total)
	var dist := PackedFloat32Array()
	dist.resize(total)
	var count := 0
	for i in touched:
		var f := field[i]
		if f > NOISE_AMP or here[i] != 0:
			continue
		var p: Array = prims[owner[i]]
		var c := Vector3(origin.x + i % sx + 0.5, origin.y + (i / sx) % size.y + 0.5, origin.z + i / sxy + 0.5)
		var r_here := lerpf(p[2], p[3], param[i])
		var v := f + NOISE_AMP * clampf(r_here / 3.0, 0.3, 1.0) * _noise.get_noise_3d(c.x, c.y, c.z)
		if v >= 0.0:
			continue
		var material := M.ROOT if -v > SKIN else M.MYCELIUM
		var glow: float = p[4]
		if p[5] == 0:
			dist[i] = c.distance_to(p[12])
			if material == M.MYCELIUM and glow > 0.0:
				var spot := Vector3i((c / SPOT_CELL).floor())
				if _hash01(spot) < glow * 0.4:
					material = M.MYCELIUM_GLOW
		else:
			var along := lerpf(p[7], p[8], param[i])
			dist[i] = p[6] * minf(along, 1.0 - along)
			if material == M.MYCELIUM and glow > 0.0:
				var q: Vector3 = c - (p[0] as Vector3).lerp(p[1], param[i])
				var angle := atan2(q.dot(p[11]), q.dot(p[10]))
				var band := fposmod(angle / TAU * STRIPES + along * p[6] / STRIPE_PITCH, 1.0)
				if band < glow * 0.5:
					material = M.MYCELIUM_GLOW
		voxels[i] = material
		count += 1

	for film: Array in films:
		count += _grow_film(film[0], film[1], voxel_world, origin, size, here, voxels, dist)
	return {origin = origin, size = size, voxels = voxels, dist = dist, count = count}


## The x range [x, y] where a row (at height cy, depth cz, cell centers) comes within bound of the
## segment a..b (x > y: it misses). The capsule is convex, so its two end spheres and the cylinder
## between them make one interval.
static func _row_span(a: Vector3, b: Vector3, bound: float, cy: float, cz: float) -> Vector2:
	var lo := INF
	var hi := -INF
	for end: Vector3 in [a, b]:
		var q := bound * bound - (cy - end.y) * (cy - end.y) - (cz - end.z) * (cz - end.z)
		if q >= 0.0:
			var s := sqrt(q)
			lo = minf(lo, end.x - s)
			hi = maxf(hi, end.x + s)
	var w := b - a
	var l2 := w.length_squared()
	if l2 > 1e-6:
		# Points a + (s, dy, dz): the part off the axis is s * pe + po.
		var o := Vector3(0.0, cy - a.y, cz - a.z)
		var pe := Vector3.RIGHT - w * (w.x / l2)
		var po := o - w * (o.dot(w) / l2)
		var qa := pe.length_squared()
		var qb := 2.0 * pe.dot(po)
		var qc := po.length_squared() - bound * bound
		var c0 := -INF
		var c1 := INF
		if qa > 1e-9:
			var disc := qb * qb - 4.0 * qa * qc
			if disc < 0.0:
				c0 = INF
				c1 = -INF
			else:
				var root := sqrt(disc)
				c0 = (-qb - root) / (2.0 * qa)
				c1 = (-qb + root) / (2.0 * qa)
		elif qc > 0.0:
			c0 = INF
			c1 = -INF
		# Between the end planes: 0 <= (s, dy, dz) . w <= l2.
		var ow := o.dot(w)
		if absf(w.x) > 1e-9:
			var s0 := (0.0 - ow) / w.x
			var s1 := (l2 - ow) / w.x
			c0 = maxf(c0, minf(s0, s1))
			c1 = minf(c1, maxf(s0, s1))
		elif ow < 0.0 or ow > l2:
			c0 = INF
			c1 = -INF
		if c0 <= c1:
			lo = minf(lo, a.x + c0)
			hi = maxf(hi, a.x + c1)
	return Vector2(lo, hi)


## The axis direction pointing away from the surface a point sits on (the nearest solid along the
## six axes within reach voxels), or ZERO when it floats.
static func surface_of(voxel_world: VoxelWorld, at: Vector3, reach: int) -> Vector3i:
	var dirs := [Vector3i.DOWN, Vector3i.UP, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]
	var start := Vector3i(at.floor())
	if voxel_world.get_voxel(start) != 0:
		for dir: Vector3i in dirs:
			if voxel_world.get_voxel(start - dir) == 0:
				return -dir
		return Vector3i.ZERO
	var best := Vector3i.ZERO
	var nearest := reach + 1
	for dir: Vector3i in dirs:
		for s in range(1, mini(reach, nearest - 1) + 1):
			if voxel_world.get_voxel(start + dir * s) != 0:
				if s < nearest:
					nearest = s
					best = -dir
				break
	return best


## Grows a node's film into voxels (see the top). Returns the voxels added.
static func _grow_film(node: Dictionary, normal: Vector3i, voxel_world: VoxelWorld, origin: Vector3i, size: Vector3i,
		here: PackedByteArray, voxels: PackedByteArray, dist: PackedFloat32Array) -> int:
	var axes: Array[Vector3i] = []
	for axis: Vector3i in [Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)]:
		if axis * normal == Vector3i.ZERO:
			axes.append(axis)
	var sx := size.x
	var sxy := size.x * size.y
	var index := func(c: Vector3i) -> int:
		var l := c - origin
		if l.x < 0 or l.y < 0 or l.z < 0 or l.x >= size.x or l.y >= size.y or l.z >= size.z:
			return -1
		return l.x + l.y * sx + l.z * sxy
	# A film cell: air, inside the box, with solid on the surface side.
	var walkable := func(c: Vector3i) -> bool:
		var i: int = index.call(c)
		if i < 0 or here[i] != 0:
			return false
		var under: int = index.call(c - normal)
		return (here[under] if under >= 0 else voxel_world.get_voxel(c - normal)) != 0
	var start := Vector3i(node.at.floor())
	for s in 3:
		if voxel_world.get_voxel(start) == 0:
			break
		start += normal
	for s in ceili(node.radius) + 3:
		if walkable.call(start) or voxel_world.get_voxel(start - normal) != 0:
			break
		start -= normal
	if not walkable.call(start):
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(node.id)
	var spread: float = node.spread
	var filament := M.MYCELIUM_GLOW if node.glow > 0.0 else M.MYCELIUM
	var walkers: Array = []
	var first := 2 + int(spread / 8.0)
	for k in first:
		walkers.append([Vector2.ZERO, TAU * k / first + rng.randf_range(-0.4, 0.4), 0])
	var added := 0
	var made := walkers.size()
	while not walkers.is_empty():
		var walker: Array = walkers.pop_front()
		var pos: Vector2 = walker[0]
		var angle: float = walker[1]
		var lift: int = walker[2]
		for step in int(spread * 2.0):
			angle += rng.randf_range(-0.5, 0.5)
			pos += Vector2(cos(angle), sin(angle))
			var out := pos.length()
			if out > spread:
				break
			var base := start + axes[0] * roundi(pos.x) + axes[1] * roundi(pos.y) + normal * lift
			var cell := base
			var found := false
			for climb: int in [0, 1, -1]:
				if walkable.call(base + normal * climb):
					cell = base + normal * climb
					lift += climb
					found = true
					break
			if not found:
				break
			var width := roundi(2.0 * (1.0 - out / spread))
			for du in range(-width, width + 1):
				for dv in range(-width, width + 1):
					if du * du + dv * dv > width * width:
						continue
					var around: Vector3i = cell + axes[0] * du + axes[1] * dv
					var i: int = index.call(around)
					if i >= 0 and voxels[i] == 0 and walkable.call(around):
						voxels[i] = M.MYCELIUM
						dist[i] = node.radius + out
						added += 1
			var j: int = index.call(cell)
			if voxels[j] == 0:
				added += 1
				dist[j] = node.radius + out
			if voxels[j] == 0 or voxels[j] == M.MYCELIUM:
				voxels[j] = filament
			if made < FILM_MAX_WALKERS and rng.randf() < 0.07:
				made += 1
				walkers.append([pos, angle + (0.8 if rng.randf() < 0.5 else -0.8), lift])
	return added


static func _hash01(p: Vector3i) -> float:
	var h := (p.x * 73856093) ^ (p.y * 19349663) ^ (p.z * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xFFFF) / 65536.0
