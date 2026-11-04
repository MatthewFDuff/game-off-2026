class_name Glass
extends Node3D
## Glass that goes as a pane, not voxel by voxel. When a carve (a shot, a blast, a swing) or a
## set_voxels batch takes glass away, the host flood-fills the glass still connected to the hole
## (6-connected, at most PANE_MAX voxels) and clears it in one WorldSync.set_voxels batch, with a
## one-voxel scatter of GLASS_SHARDS on the first surface under the pane. Every peer gets the batch
## (so the worlds match) and a crash with debris scaled by the pane.
##
## Tempered glass (GLASS_TEMPERED) survives TEMPERED_HITS - 1 hits: the first turns the whole pane
## to GLASS_CRACKED, the last shatters it. A blast (a carve of BLAST_RADIUS or more) shatters any
## glass at once. The host counts hits per pane, keyed by the pane's lowest voxel (y, then z, then
## x) as it stood before the hit.
##
## Shattering tells LevelPlay (glass_shattered): props that held the pane react by name (spore
## tanks vent, vats drain, fixtures go dark) and glass outside every prop goes on the payroll.
##
## The host does all of it, a frame after the hit, so the hit's own edit reaches the peers first.

## The node group (Glass.find).
const GROUP := "glass"
## Most voxels one pane can have; a bigger sheet breaks this much at a time.
const PANE_MAX := 6000
## Carves this big (meters) or bigger are blasts: any glass they touch shatters at once.
const BLAST_RADIUS := 0.5
## Hits that break a tempered pane (the ones before crack it).
const TEMPERED_HITS := 3
## Share of the columns under (and around) a pane that get a shard, how far around the pane the
## shards land (voxels), and how far down a shard looks for a surface.
const SHARD_COVER := 0.3
const SHARD_SPREAD := 3
const SHARD_DROP := 60
## Panes of at least this many voxels play the big crash.
const BIG_PANE := 300
## Dollars per voxel of glass that isn't part of a prop (props bill their own voxels as assets).
const PRICE := 1
const FACES := [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]

@export var lab: Lab
@export var world: VoxelWorld
@export var world_sync: WorldSync

## Host: tempered panes that took a hit: pane key -> {lowest: Vector3i, hits: int, carved: int}.
var _tempered := {}
## Host: hits waiting for the end of the frame.
var _queue: Array[Dictionary] = []
## Host: true while this node's own batch lands (it isn't a new hit).
var _own := false
## Host, for tests: the last pane that shattered {lowest: Vector3i, voxels: int, shards: int}, and
## how long the last flood fill took (milliseconds).
var last_shatter := {}
var last_fill_msec := 0.0


## Every peer: the level's Glass, or null.
static func find() -> Glass:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.get_first_node_in_group(GROUP) as Glass if tree else null


## Whether a material is pane glass (ordinary, tempered or cracked; not shards).
static func is_pane(material: int) -> bool:
	return material == VoxelMaterials.GLASS or material == VoxelMaterials.GLASS_TEMPERED or material == VoxelMaterials.GLASS_CRACKED


static func _key(p: Vector3i) -> int:
	return (p.x & 0xFFFF) | ((p.y & 0xFFFF) << 16) | ((p.z & 0xFFFF) << 32)


func _ready() -> void:
	add_to_group(GROUP)
	world_sync.carved.connect(_on_carved)
	world_sync.voxels_set.connect(_on_voxels_set)
	lab.mode_changed.connect(func(_mode: String) -> void: clear())


## Host: forgets every cracked pane's hits (leaving play).
func clear() -> void:
	_tempered.clear()
	_queue.clear()


func _playing() -> bool:
	return multiplayer.is_server() and lab.play != null and lab.play.active


static func _glass_count(removed: Dictionary) -> int:
	return int(removed.get(VoxelMaterials.GLASS, 0)) + int(removed.get(VoxelMaterials.GLASS_TEMPERED, 0)) \
			+ int(removed.get(VoxelMaterials.GLASS_CRACKED, 0))


# --- Hits (host) ---------------------------------------------------------------------------------

func _on_carved(center: Vector3, normal: Vector3, removed: Dictionary) -> void:
	var carved := _glass_count(removed)
	if carved == 0 or not _playing():
		return
	_enqueue({center = center, radius = world_sync.last_carve_radius, normal = normal, carved = carved, seeds = null})


## A batch took glass away (a fire, a story edit, another node): the glass next to it breaks too.
func _on_voxels_set(points: PackedInt32Array, materials: PackedByteArray, removed: Dictionary) -> void:
	if _own:
		return
	var carved := _glass_count(removed)
	if carved == 0 or not _playing():
		return
	var seeds: Array[Vector3i] = []
	var sum := Vector3.ZERO
	var count := 0
	for i in materials.size():
		if materials[i] != VoxelMaterials.AIR:
			continue
		var p := Vector3i(points[i * 3], points[i * 3 + 1], points[i * 3 + 2])
		sum += Vector3(p)
		count += 1
		for face: Vector3i in FACES:
			if is_pane(world.get_voxel(p + face)):
				seeds.append(p + face)
	var middle := Vector3i((sum / maxi(count, 1)).round())
	_enqueue({center = world.voxel_to_world(middle), radius = 0.0, normal = Vector3.UP, carved = carved, seeds = seeds})


func _enqueue(hit: Dictionary) -> void:
	if _queue.is_empty():
		_drain.call_deferred()
	_queue.append(hit)


## Host, at the end of the frame (after the carve went out to the peers): every queued hit.
func _drain() -> void:
	var hits := _queue
	_queue = []
	for hit in hits:
		if _playing():
			_hit(hit)


func _hit(hit: Dictionary) -> void:
	var seeds: Array[Vector3i] = []
	if hit.seeds != null:
		seeds = hit.seeds
	else:
		var ids := PackedByteArray([VoxelMaterials.GLASS, VoxelMaterials.GLASS_TEMPERED, VoxelMaterials.GLASS_CRACKED])
		var found := world.find_in_sphere(hit.center, float(hit.radius) + world.voxel_size * 1.5, ids, false, 4096)
		for i in found.size() / 3:
			seeds.append(Vector3i(found[i * 3], found[i * 3 + 1], found[i * 3 + 2]))
	var visited := {}
	var carved: int = hit.carved
	var any := false
	for start in seeds:
		if visited.has(_key(start)) or not is_pane(world.get_voxel(start)):
			continue
		var pane := _fill(start, visited)
		any = true
		_pane_hit(pane, hit, carved)
		carved = 0 # The hole counts once, with the first pane.
	if not any:
		# The hit took the whole (small) pane: only the crash, and the bill.
		_tell_effects(hit.center, hit.normal, hit.carved, VoxelMaterials.GLASS, AABB(hit.center, Vector3.ZERO))
		lab.play.glass_shattered([], hit.carved, hit.center)


## Host: the glass connected to start of the same kind (ordinary, or tempered and cracked), 6-connected,
## at most PANE_MAX voxels. {voxels: Array[Vector3i], lowest: Vector3i, tempered: bool, material}
func _fill(start: Vector3i, visited: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var material := world.get_voxel(start)
	var tempered := material != VoxelMaterials.GLASS
	var voxels: Array[Vector3i] = [start]
	var lowest := start
	visited[_key(start)] = true
	var i := 0
	while i < voxels.size() and voxels.size() < PANE_MAX:
		var p := voxels[i]
		i += 1
		for face: Vector3i in FACES:
			var q: Vector3i = p + face
			var k := _key(q)
			if visited.has(k):
				continue
			var m := world.get_voxel(q)
			var same := (m == VoxelMaterials.GLASS_TEMPERED or m == VoxelMaterials.GLASS_CRACKED) if tempered else m == VoxelMaterials.GLASS
			if not same:
				continue
			visited[k] = true
			voxels.append(q)
			if q.y < lowest.y or (q.y == lowest.y and (q.z < lowest.z or (q.z == lowest.z and q.x < lowest.x))):
				lowest = q
			if voxels.size() >= PANE_MAX:
				break
	last_fill_msec = (Time.get_ticks_usec() - started) / 1000.0
	return {voxels = voxels, lowest = lowest, tempered = tempered, material = material}


## Host: a pane took a hit. Ordinary glass and blasts shatter it; tempered glass counts the hit.
func _pane_hit(pane: Dictionary, hit: Dictionary, carved: int) -> void:
	if not pane.tempered or float(hit.radius) >= BLAST_RADIUS:
		_shatter(pane, hit, carved)
		return
	var lowest: Vector3i = pane.lowest
	var key := _key(lowest)
	var record: Dictionary = _tempered.get(key, {})
	if record.is_empty():
		# The hit may have carved away the pane's lowest voxel: a record whose voxel is gone, where
		# the hit landed.
		var center := world.world_to_voxel(hit.center)
		var reach := float(hit.radius) / world.voxel_size + 2.0
		for other: int in _tempered:
			var at: Vector3i = _tempered[other].lowest
			if not is_pane(world.get_voxel(at)) and Vector3(at - center).length() <= reach:
				record = _tempered[other]
				_tempered.erase(other)
				break
	else:
		_tempered.erase(key)
	var hits: int = record.get("hits", 0) + 1
	var carved_total: int = record.get("carved", 0) + carved
	if hits >= TEMPERED_HITS:
		_shatter(pane, hit, carved_total)
		return
	_tempered[key] = {lowest = lowest, hits = hits, carved = carved_total}
	var points := PackedInt32Array()
	var materials := PackedByteArray()
	for p: Vector3i in pane.voxels:
		if world.get_voxel(p) == VoxelMaterials.GLASS_TEMPERED:
			points.append_array([p.x, p.y, p.z])
			materials.append(VoxelMaterials.GLASS_CRACKED)
	_apply_batch(points, materials)
	_cracked(hit.center)
	for peer_id in world_sync.synced_peers():
		_cracked.rpc_id(peer_id, hit.center)


## Host: the whole pane goes in one batch, shards land under it, and LevelPlay hears of it.
func _shatter(pane: Dictionary, hit: Dictionary, carved: int) -> void:
	var voxels: Array[Vector3i] = pane.voxels
	var in_pane := {}
	var lo: Vector3i = voxels[0]
	var hi: Vector3i = voxels[0]
	for p in voxels:
		in_pane[_key(p)] = true
		lo = lo.min(p)
		hi = hi.max(p)
	# key -> [Vector3i, material]
	var edits := {}
	for p in voxels:
		edits[_key(p)] = [p, VoxelMaterials.AIR]
	var shards := 0
	var pane_key: int = _key(pane.lowest)
	for z in range(lo.z - SHARD_SPREAD, hi.z + SHARD_SPREAD + 1):
		for x in range(lo.x - SHARD_SPREAD, hi.x + SHARD_SPREAD + 1):
			if _roll(pane_key, x, z) >= SHARD_COVER:
				continue
			var land := _landing(Vector3i(x, lo.y, z), in_pane)
			if land.y >= 0:
				edits[_key(land)] = [land, VoxelMaterials.GLASS_SHARDS]
				shards += 1
	var points := PackedInt32Array()
	var materials := PackedByteArray()
	points.resize(edits.size() * 3)
	materials.resize(edits.size())
	var i := 0
	for edit: Array in edits.values():
		var p: Vector3i = edit[0]
		points[i * 3] = p.x
		points[i * 3 + 1] = p.y
		points[i * 3 + 2] = p.z
		materials[i] = edit[1]
		i += 1
	_tempered.erase(pane_key)
	last_shatter = {lowest = pane.lowest, voxels = voxels.size(), shards = shards}
	_apply_batch(points, materials)
	var box := AABB(world.voxel_to_world(lo), Vector3(hi - lo + Vector3i.ONE) * world.voxel_size)
	var count := voxels.size() + carved
	_tell_effects(hit.center, hit.normal, count, pane.material, box)
	lab.play.glass_shattered(voxels, carved, hit.center)


## Deterministic 0..1 from the pane and a column, for the shard scatter.
static func _roll(pane_key: int, x: int, z: int) -> float:
	var h := (x * 73856093) ^ (z * 19349663) ^ (pane_key * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return posmod(h ^ (h >> 16), 1000) / 1000.0


## Where a shard dropped in column (from.x, from.z) at from.y comes to rest: the air voxel on the
## first solid voxel below (the pane counts as air), or y -1 if it starts in something solid or
## finds nothing within SHARD_DROP.
func _landing(from: Vector3i, in_pane: Dictionary) -> Vector3i:
	var p := from
	if world.get_voxel(p) != VoxelMaterials.AIR and not in_pane.has(_key(p)):
		return Vector3i(0, -1, 0)
	for step in SHARD_DROP:
		var below := p + Vector3i.DOWN
		if below.y < 0:
			break
		var m := world.get_voxel(below)
		if m != VoxelMaterials.AIR and not in_pane.has(_key(below)):
			return p
		p = below
	return Vector3i(0, -1, 0)


func _apply_batch(points: PackedInt32Array, materials: PackedByteArray) -> void:
	if materials.is_empty():
		return
	_own = true
	world_sync.set_voxels(points, materials)
	_own = false


# --- Looks (every peer) --------------------------------------------------------------------------

## Host: the crash here and on every peer.
func _tell_effects(at: Vector3, normal: Vector3, count: int, material: int, box: AABB) -> void:
	_effects(at, normal, count, material, box)
	for peer_id in world_sync.synced_peers():
		_effects.rpc_id(peer_id, at, normal, count, material, box)


## Every peer: a pane shattered (count voxels of material over box, hit at at).
@rpc("authority", "reliable")
func _effects(at: Vector3, normal: Vector3, count: int, material: int, box: AABB) -> void:
	var big := count >= BIG_PANE
	Sfx.play_at("glass_shatter_big" if big else "glass_shatter", at, 2.0 if big else 0.0, 0.1)
	if lab.debris == null:
		return
	# A burst at the hit, and more across a big pane so it reads as the whole sheet going.
	lab.debris.burst(at, normal, {material: count})
	var extra := clampi(count / 150, 0, 6)
	for i in extra:
		var across := fposmod(i * 0.618 + 0.31, 1.0)
		var spot := box.position + box.size * Vector3(across, fposmod(i * 0.382 + 0.5, 1.0), across)
		lab.debris.burst(spot, normal, {material: maxi(count / (extra + 1), 1)})


## Every peer: a tempered pane cracked.
@rpc("authority", "reliable")
func _cracked(at: Vector3) -> void:
	Sfx.play_at("glass_crack", at, 0.0, 0.1)
