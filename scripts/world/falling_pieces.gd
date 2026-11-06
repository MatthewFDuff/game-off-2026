class_name FallingPieces
extends Node
## Loose pieces fall as objects and stay where they land. When a carve or a fire cuts something
## free (VoxelWorld.fragments_detached: a cabinet whose legs are shot out, a crate whose chain is
## cut), a piece of at least MIN_PIECE voxels doesn't crumble: it drops straight down, axis-aligned,
## until its underside meets solid voxels, and is stamped back there as voxels, which can be shot
## again like anything else. A piece resting on the floor is attached to it (the flood fill counts
## touching anything solid), so it doesn't fall again.
##
## Ceiling tiles (VoxelMaterials.CEILING_TILE) go the same way: a shot that takes voxels out of a
## hanging tile breaks the rest of that tile loose (the connected run of tile voxels, bounded by the
## steel T-bars, at most TILE_MAX), and it falls as a flat sheet. The rule only applies to a tile
## that hangs: one with no solid voxel under any of its voxels. A tile lying on the floor (or on a
## desk) rests on something, so shooting it just carves it.
##
## The host decides everything and every peer draws it. Every peer's world replays the host's carve
## and detaches the same piece locally, but only the host acts on that: it works out the landing,
## tells every synced peer to slide a mesh of the piece down (_fall), and when the fall is over
## stamps the piece at the landing through WorldSync (so the peers get it in order with every other
## edit) and has every peer play the thud (_landed). Peers only puff a little dust at the detach
## (VoxelDebris). A peer that joins mid-fall gets a snapshot without the piece; it appears when the
## piece lands.
##
## A child of Lab ("FallingPieces", the same path on every peer).

## Detached pieces of fewer voxels crumble into debris as before (VoxelDebris).
const MIN_PIECE := 10
## Bigger pieces, or pieces whose box is bigger than MAX_BOX voxels, crumble too (the RPC carries
## the whole box).
const MAX_PIECE := 6000
const MAX_BOX := 131072
## Meters per second squared: a little more than gravity, so short drops read as a drop, not a float.
const FALL_ACCELERATION := 15.0
## Shortest fall (seconds), so a one-voxel drop still shows.
const MIN_FALL_SECONDS := 0.06
## Farthest a piece looks down for a landing (voxels); with nothing there it stops this far down.
const MAX_DROP := 600
## Most voxels one ceiling tile breaks loose as.
const TILE_MAX := 200
## Seconds the falling mesh stays after the fall, so the stamped voxels are there before it goes.
const LINGER := 0.1
## Compressed boxes bigger than this go without a mesh (the peers see the piece vanish and land): an
## RPC near ~48 KB is silently dropped by ENet (WorldSync.PART_SIZE).
const MAX_SEND := 32000
const FACES := [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]

## Host, as a piece starts to fall: {box: AABB (world space, where it was), column: AABB (the space
## it falls through, down to the landing), voxel_count: int, materials: Dictionary (id -> count)}.
## InteractRules crushes what is in the column.
signal piece_falling(fall: Dictionary)
## Host, once a piece is stamped where it landed: its box in voxels.
signal piece_landed(origin: Vector3i, size: Vector3i)

var lab: Lab
## Host: pieces in the air.
var falling := 0
## Every peer: falling piece id -> its MeshInstance3D, while it is drawn.
var meshes := {}

## Host: pieces and tile seeds waiting for the end of the frame, so the edit that caused them has
## gone out to the peers first.
var _queue: Array[Dictionary] = []
var _tile_seeds: Array[Vector3i] = []
## Host: true while this node's own set_voxels batch lands (it isn't a new hit).
var _own := false
var _next_id := 0
## Bumped when play stops, so falls in flight are dropped.
var _generation := 0


func _ready() -> void:
	lab.world.fragments_detached.connect(_on_fragments)
	lab.world_sync.carved.connect(_on_carved)
	lab.world_sync.voxels_set.connect(_on_voxels_set)
	lab.mode_changed.connect(func(_mode: String) -> void: clear())
	if lab.debris:
		lab.debris.pieces_fall = true


## Every peer: forgets the falls in flight and their meshes (leaving or restarting play).
func clear() -> void:
	_generation += 1
	falling = 0
	_queue.clear()
	_tile_seeds.clear()
	for mesh: MeshInstance3D in meshes.values():
		if is_instance_valid(mesh):
			mesh.queue_free()
	meshes.clear()


## Whether a detached fragment (VoxelWorld.fragments_detached) falls as a piece rather than
## crumbling: big enough to read as an object, small enough to send, and not mostly pane glass
## (a pane that comes loose shatters, as Glass would have it).
static func falls(fragment: Dictionary) -> bool:
	var count := int(fragment.voxel_count)
	if count < MIN_PIECE or count > MAX_PIECE:
		return false
	var voxels: PackedByteArray = fragment.get("voxels", PackedByteArray())
	var size: Vector3i = fragment.get("size", Vector3i.ZERO)
	if voxels.is_empty() or size.x * size.y * size.z > MAX_BOX:
		return false
	var materials: Dictionary = fragment.materials
	var glass := int(materials.get(VoxelMaterials.GLASS, 0)) + int(materials.get(VoxelMaterials.GLASS_TEMPERED, 0)) \
			+ int(materials.get(VoxelMaterials.GLASS_CRACKED, 0))
	return glass * 2 < count


func _playing() -> bool:
	return multiplayer.is_server() and lab.play != null and lab.play.active


# --- Sources (host) ------------------------------------------------------------------------------

func _on_fragments(fragments: Array) -> void:
	if not _playing():
		return
	for fragment: Dictionary in fragments:
		if falls(fragment):
			_enqueue({origin = fragment.origin, size = fragment.size, voxels = fragment.voxels})


func _on_carved(center: Vector3, _normal: Vector3, removed: Dictionary) -> void:
	if int(removed.get(VoxelMaterials.CEILING_TILE, 0)) == 0 or not _playing():
		return
	# The tile voxels around the hole (the carve already took the ones inside it).
	var reach := lab.world_sync.last_carve_radius + lab.world.voxel_size * 1.5
	var found := lab.world.find_in_sphere(center, reach, PackedByteArray([VoxelMaterials.CEILING_TILE]), false, 4096)
	for i in found.size() / 3:
		_tile_seeds.append(Vector3i(found[i * 3], found[i * 3 + 1], found[i * 3 + 2]))
	_enqueue({})


## A batch took tile voxels away (another node's set_voxels): the tile next to it breaks loose too.
func _on_voxels_set(points: PackedInt32Array, materials: PackedByteArray, removed: Dictionary) -> void:
	if _own or int(removed.get(VoxelMaterials.CEILING_TILE, 0)) == 0 or not _playing():
		return
	for i in materials.size():
		if materials[i] != VoxelMaterials.AIR:
			continue
		var p := Vector3i(points[i * 3], points[i * 3 + 1], points[i * 3 + 2])
		for face: Vector3i in FACES:
			if lab.world.get_voxel(p + face) == VoxelMaterials.CEILING_TILE:
				_tile_seeds.append(p + face)
	_enqueue({})


## piece: {origin, size, voxels}, or {} to just have the tile seeds looked at.
func _enqueue(piece: Dictionary) -> void:
	if _queue.is_empty():
		_drain.call_deferred()
	_queue.append(piece)


func _drain() -> void:
	var pieces := _queue
	var seeds := _tile_seeds
	_queue = []
	_tile_seeds = []
	if not _playing():
		return
	for piece in pieces:
		if not piece.is_empty():
			drop(piece.origin, piece.size, piece.voxels)
	var visited := {}
	for seed in seeds:
		if visited.has(seed) or lab.world.get_voxel(seed) != VoxelMaterials.CEILING_TILE:
			continue
		var tile := _tile_run(seed, visited)
		if tile.hanging:
			_break_tile(tile.voxels)


# --- Ceiling tiles (host) ------------------------------------------------------------------------

## The CEILING_TILE voxels 6-connected to start (at most TILE_MAX), and whether the tile hangs: no
## voxel of it has a solid voxel under it that isn't part of the tile. {voxels: Array[Vector3i], hanging}
func _tile_run(start: Vector3i, visited: Dictionary) -> Dictionary:
	var voxels: Array[Vector3i] = [start]
	var mine := {start: true}
	visited[start] = true
	var i := 0
	while i < voxels.size() and voxels.size() < TILE_MAX:
		var p := voxels[i]
		i += 1
		for face: Vector3i in FACES:
			var q: Vector3i = p + face
			if visited.has(q) or lab.world.get_voxel(q) != VoxelMaterials.CEILING_TILE:
				continue
			visited[q] = true
			mine[q] = true
			voxels.append(q)
			if voxels.size() >= TILE_MAX:
				break
	var hanging := true
	for p in voxels:
		var below := p + Vector3i.DOWN
		if not mine.has(below) and (below.y < 0 or lab.world.get_voxel(below) != VoxelMaterials.AIR):
			hanging = false
			break
	return {voxels = voxels, hanging = hanging}


## Takes a tile's voxels out everywhere (one set_voxels batch) and drops them as a piece.
func _break_tile(voxels: Array[Vector3i]) -> void:
	var lo := voxels[0]
	var hi := voxels[0]
	for p in voxels:
		lo = lo.min(p)
		hi = hi.max(p)
	var size := hi - lo + Vector3i.ONE
	var box := PackedByteArray()
	box.resize(size.x * size.y * size.z)
	var points := PackedInt32Array()
	var air := PackedByteArray()
	air.resize(voxels.size())
	for p in voxels:
		var local := p - lo
		box[local.x + local.y * size.x + local.z * size.x * size.y] = VoxelMaterials.CEILING_TILE
		points.append(p.x)
		points.append(p.y)
		points.append(p.z)
	_own = true
	lab.world_sync.set_voxels(points, air)
	_own = false
	drop(lo, size, box)


# --- Falling (host) ------------------------------------------------------------------------------

## Host: drops a box of voxels (origin and size in voxels, voxels dense in VoxelWorld.stamp's
## layout, 0 = air) that is no longer in the world: straight down to where it lands, then stamped
## there. Any source: a detached fragment, a broken ceiling tile.
func drop(origin: Vector3i, size: Vector3i, voxels: PackedByteArray) -> void:
	if not _playing():
		return
	var distance := drop_distance(origin, size, voxels)
	if distance <= 0:
		_settle(origin, size, voxels)
		return
	var landing := origin + Vector3i(0, -distance, 0)
	var voxel := lab.world.voxel_size
	var duration := maxf(sqrt(2.0 * distance * voxel / FALL_ACCELERATION), MIN_FALL_SECONDS)
	var count := 0
	var materials := {}
	for m in voxels:
		if m != 0:
			count += 1
			materials[m] = int(materials.get(m, 0)) + 1
	var start := lab.view.to_world(Vector3(origin))
	var bottom := lab.view.to_world(Vector3(landing))
	var extent := Vector3(size) * voxel
	piece_falling.emit({box = AABB(start, extent), column = AABB(bottom, extent + Vector3(0, start.y - bottom.y, 0)),
			voxel_count = count, materials = materials})

	var id := _next_id
	_next_id += 1
	var packed := voxels.compress(FileAccess.COMPRESSION_ZSTD)
	if packed.size() <= MAX_SEND:
		_fall(id, origin, size, packed, voxels.size(), landing, duration)
		for peer_id in lab.world_sync.synced_peers():
			_fall.rpc_id(peer_id, id, origin, size, packed, voxels.size(), landing, duration)
	falling += 1
	# A Timer child, not an awaited SceneTreeTimer: a coroutine left waiting when the Lab goes (a
	# test quitting mid-fall, a shift left) leaked the timer and crashed on exit.
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = duration
	timer.timeout.connect(_on_fall_ended.bind(landing, size, voxels, _generation, timer))
	add_child(timer)
	timer.start()


## Host: the fall's time is up. Something may have been carved out from under the landing while it
## fell: it keeps going; otherwise it settles.
func _on_fall_ended(landing: Vector3i, size: Vector3i, voxels: PackedByteArray, generation: int, timer: Timer) -> void:
	timer.queue_free()
	if generation != _generation or not _playing():
		return
	falling -= 1
	if drop_distance(landing, size, voxels) > 0:
		drop(landing, size, voxels)
		return
	_settle(landing, size, voxels)


## Host: stamps the piece at origin everywhere, leaving out voxels that are solid there already
## (something built in its way while it fell), and plays the landing on every peer.
func _settle(origin: Vector3i, size: Vector3i, voxels: PackedByteArray) -> void:
	var placed := voxels.duplicate()
	var count := 0
	var layer := size.x * size.y
	for i in placed.size():
		if placed[i] == 0:
			continue
		var p := origin + Vector3i(i % size.x, (i / size.x) % size.y, i / layer)
		if lab.world.get_voxel(p) != VoxelMaterials.AIR:
			placed[i] = 0
		else:
			count += 1
	if count == 0:
		return
	lab.world_sync.stamp_model(origin, size, placed)
	var box := AABB(lab.view.to_world(Vector3(origin)), Vector3(size) * lab.world.voxel_size)
	_landed(box, count)
	for peer_id in lab.world_sync.synced_peers():
		_landed.rpc_id(peer_id, box, count)
	piece_landed.emit(origin, size)


## How many voxels the box can drop straight down before one of its voxels would enter a solid
## voxel (the box's own cells are air in the world: it has been taken out). Only each voxel with
## nothing of the piece directly under it needs a look, down to the best drop found so far.
func drop_distance(origin: Vector3i, size: Vector3i, voxels: PackedByteArray) -> int:
	var best := MAX_DROP
	var layer := size.x * size.y
	for i in voxels.size():
		if voxels[i] == 0:
			continue
		var y := (i / size.x) % size.y
		if y > 0 and voxels[i - size.x] != 0:
			continue
		var p := origin + Vector3i(i % size.x, y, i / layer)
		var d := 0
		while d < best:
			var below := p.y - d - 1
			if below < 0 or lab.world.get_voxel(Vector3i(p.x, below, p.z)) != VoxelMaterials.AIR:
				break
			d += 1
		best = d
		if best == 0:
			return 0
	return best


# --- Looks (every peer) --------------------------------------------------------------------------

## Every peer: a mesh of the piece slides from origin down to landing over duration, speeding up
## as it goes (constant acceleration), and lingers LINGER past the end while the host's stamp lands.
@rpc("authority", "reliable")
func _fall(id: int, origin: Vector3i, size: Vector3i, packed: PackedByteArray, raw_size: int, landing: Vector3i, duration: float) -> void:
	var voxels := packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if voxels.size() != size.x * size.y * size.z:
		return
	var mesh := MeshInstance3D.new()
	mesh.mesh = lab.world.build_model_mesh(size, voxels)
	mesh.material_override = lab.world.material
	mesh.position = lab.view.to_world(Vector3(origin))
	lab.view.add_child(mesh)
	meshes[id] = mesh
	var tween := mesh.create_tween()
	tween.tween_property(mesh, "position", lab.view.to_world(Vector3(landing)), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_interval(LINGER)
	tween.tween_callback(func() -> void:
		meshes.erase(id)
		mesh.queue_free())


## Every peer: a piece of count voxels came to rest in box (world space): the thud, and some dust.
@rpc("authority", "reliable")
func _landed(box: AABB, count: int) -> void:
	var at := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	Sfx.play_at("thud", at, clampf(-14.0 + count / 20.0, -14.0, 2.0), 0.15)
	if lab.debris:
		lab.debris.dust(AABB(box.position, Vector3(box.size.x, lab.world.voxel_size, box.size.z)), {VoxelMaterials.CONCRETE: count}, count)
