class_name FallingPieces
extends Node
## Loose pieces fall as objects and stay where they land. When a carve or a fire cuts something
## free (VoxelWorld.fragments_detached: a cabinet whose legs are shot out, a crate whose chain is
## cut), a piece of at least MIN_PIECE voxels doesn't crumble: it drops straight down, axis-aligned,
## until its underside meets solid voxels, and is stamped back there as voxels, which can be shot
## again like anything else. A piece resting on the floor is attached to it (the flood fill counts
## touching anything solid), so it doesn't fall again.
##
## A plate (a sign or a vent cover shot off a wall, a poster board, a door: at most TOPPLE_THICKNESS
## thick across x or z and TOPPLE_RATIO times taller than that) topples instead of landing on its
## edge: it turns a quarter about its bottom edge, toward whichever side has more air next to it
## (away from the wall it hung on), and falls lying flat on a face. With no room for it lying down
## on either side it drops straight like the rest.
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
## Plates: thinnest horizontal side at most this many voxels, and at least TOPPLE_RATIO times as tall.
const TOPPLE_THICKNESS := 4
const TOPPLE_RATIO := 3
## Shortest fall (seconds) of a piece that topples, so the quarter turn reads.
const TOPPLE_SECONDS := 0.35
## How far out from each face (voxels) a plate looks for air, in three columns at mid height.
const TOPPLE_PROBE := 6
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
## there; a plate topples over flat first (topple). Any source: a detached fragment, a broken
## ceiling tile.
func drop(origin: Vector3i, size: Vector3i, voxels: PackedByteArray) -> void:
	if not _playing():
		return
	var turn := topple(origin, size, voxels)
	var lying_origin: Vector3i = turn.get("origin", origin)
	var lying_size: Vector3i = turn.get("size", size)
	var lying: PackedByteArray = turn.get("voxels", voxels)
	var distance := drop_distance(lying_origin, lying_size, lying)
	if distance <= 0 and turn.is_empty():
		_settle(origin, size, voxels)
		return
	var landing := lying_origin + Vector3i(0, -distance, 0)
	var voxel := lab.world.voxel_size
	var duration := maxf(sqrt(2.0 * distance * voxel / FALL_ACCELERATION), MIN_FALL_SECONDS)
	if not turn.is_empty():
		duration = maxf(duration, TOPPLE_SECONDS)
	var count := 0
	var materials := {}
	for m in voxels:
		if m != 0:
			count += 1
			materials[m] = int(materials.get(m, 0)) + 1
	var box := AABB(lab.view.to_world(Vector3(origin)), Vector3(size) * voxel)
	var start := lab.view.to_world(Vector3(lying_origin))
	var bottom := lab.view.to_world(Vector3(landing))
	var extent := Vector3(lying_size) * voxel
	# A plate sweeps the square between standing and lying on its way down: the column covers both.
	var column := AABB(bottom, extent + Vector3(0, start.y - bottom.y, 0)).merge(box)
	piece_falling.emit({box = box, column = column, voxel_count = count, materials = materials})

	var id := _next_id
	_next_id += 1
	var pivot: Vector3 = turn.get("pivot", Vector3.ZERO)
	var axis: Vector3 = turn.get("axis", Vector3.ZERO)
	var packed := voxels.compress(FileAccess.COMPRESSION_ZSTD)
	if packed.size() <= MAX_SEND:
		_fall(id, origin, size, packed, voxels.size(), landing, duration, pivot, axis)
		for peer_id in lab.world_sync.synced_peers():
			_fall.rpc_id(peer_id, id, origin, size, packed, voxels.size(), landing, duration, pivot, axis)
	falling += 1
	# A Timer child, not an awaited SceneTreeTimer: a coroutine left waiting when the Lab goes (a
	# test quitting mid-fall, a shift left) leaked the timer and crashed on exit.
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = duration
	timer.timeout.connect(_on_fall_ended.bind(landing, lying_size, lying, _generation, timer))
	add_child(timer)
	timer.start()


## A plate's topple: a piece at most TOPPLE_THICKNESS thick across x or z (its thinner horizontal
## side) and at least TOPPLE_RATIO times as tall turns a quarter about the bottom edge of one face,
## so it lies flat where it stood, toward the side with more air next to it (the wall it hung on is
## on the other; a tie goes +x / +z). The other side is tried when the first has no room; {} when
## neither has (it drops straight) or the piece isn't a plate. Otherwise {origin, size, voxels (the
## piece lying down, same layout), pivot (voxel space: a point on the edge it turns about), axis
## (unit: a +90 degree turn about it takes the piece from standing to lying)}.
func topple(origin: Vector3i, size: Vector3i, voxels: PackedByteArray) -> Dictionary:
	var thin_z := size.z <= size.x
	var thickness := size.z if thin_z else size.x
	if thickness > TOPPLE_THICKNESS or size.y < TOPPLE_RATIO * thickness:
		return {}
	var sides := [1, -1] if _room(origin, size, thin_z, 1) >= _room(origin, size, thin_z, -1) else [-1, 1]
	for side: int in sides:
		var turned := _turned(origin, size, voxels, thin_z, side)
		if _fits(turned.origin, turned.size, turned.voxels):
			return turned
	return {}


## Air voxels out from the plate's face on side (+1: the +x / +z face), up to TOPPLE_PROBE deep, in
## three columns along it at mid height.
func _room(origin: Vector3i, size: Vector3i, thin_z: bool, side: int) -> int:
	var y := origin.y + size.y / 2
	var length := size.x if thin_z else size.z
	var room := 0
	for k in 3:
		var along := length * (2 * k + 1) / 6
		for d in TOPPLE_PROBE:
			var p: Vector3i
			if thin_z:
				p = Vector3i(origin.x + along, y, origin.z + size.z + d if side > 0 else origin.z - 1 - d)
			else:
				p = Vector3i(origin.x + size.x + d if side > 0 else origin.x - 1 - d, y, origin.z + along)
			if lab.world.get_voxel(p) != VoxelMaterials.AIR:
				break
			room += 1
	return room


## The plate turned a quarter toward side about its bottom edge on that side (see topple): thin in z,
## size (x, y, z) becomes (x, z, y) lying along z; thin in x, (y, x, z) lying along x.
func _turned(origin: Vector3i, size: Vector3i, voxels: PackedByteArray, thin_z: bool, side: int) -> Dictionary:
	var t := size.z if thin_z else size.x
	var h := size.y
	var lying_size := Vector3i(size.x, t, h) if thin_z else Vector3i(h, t, size.z)
	var lying_origin := origin
	var pivot := Vector3(origin)
	if thin_z:
		lying_origin.z = origin.z + t if side > 0 else origin.z - h
		pivot.z = origin.z + t if side > 0 else origin.z
	else:
		lying_origin.x = origin.x + t if side > 0 else origin.x - h
		pivot.x = origin.x + t if side > 0 else origin.x
	var lying := PackedByteArray()
	lying.resize(voxels.size())
	var layer := size.x * size.y
	var lying_layer := lying_size.x * lying_size.y
	for i in voxels.size():
		var m := voxels[i]
		if m == 0:
			continue
		var x := i % size.x
		var y := (i / size.x) % size.y
		var z := i / layer
		# The face on side ends up underneath, the top farthest out.
		var q: Vector3i
		if thin_z:
			q = Vector3i(x, t - 1 - z, y) if side > 0 else Vector3i(x, z, h - 1 - y)
		else:
			q = Vector3i(y, t - 1 - x, z) if side > 0 else Vector3i(h - 1 - y, x, z)
		lying[q.x + q.y * lying_size.x + q.z * lying_layer] = m
	var direction := Vector3(0, 0, side) if thin_z else Vector3(side, 0, 0)
	return {origin = lying_origin, size = lying_size, voxels = lying, pivot = pivot, axis = Vector3.UP.cross(direction)}


## Whether every voxel of the box at origin lands on air inside the world.
func _fits(origin: Vector3i, size: Vector3i, voxels: PackedByteArray) -> bool:
	var world_size := lab.world.get_size_in_voxels()
	var end := origin + size
	if origin.x < 0 or origin.y < 0 or origin.z < 0 or end.x > world_size.x or end.y > world_size.y or end.z > world_size.z:
		return false
	var layer := size.x * size.y
	for i in voxels.size():
		if voxels[i] != 0 and lab.world.get_voxel(origin + Vector3i(i % size.x, (i / size.x) % size.y, i / layer)) != VoxelMaterials.AIR:
			return false
	return true


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
## A plate that topples (axis not zero) also turns a quarter about axis through pivot (voxel space,
## falling with it), faster as it goes, and ends lying where the host stamps it (landing is then the
## lying box's origin). The mesh carries its own surface materials (VoxelWorld.build_model_mesh).
@rpc("authority", "reliable")
func _fall(id: int, origin: Vector3i, size: Vector3i, packed: PackedByteArray, raw_size: int, landing: Vector3i, duration: float,
		pivot: Vector3, axis: Vector3) -> void:
	var voxels := packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if voxels.size() != size.x * size.y * size.z:
		return
	var mesh := MeshInstance3D.new()
	mesh.mesh = lab.world.build_model_mesh(size, voxels)
	mesh.position = lab.view.to_world(Vector3(origin))
	lab.view.add_child(mesh)
	meshes[id] = mesh
	var tween := mesh.create_tween()
	if axis.is_zero_approx():
		tween.tween_property(mesh, "position", lab.view.to_world(Vector3(landing)), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		var hinge := lab.view.to_world(pivot)
		var arm := mesh.position - hinge
		var fall := Vector3(0.0, float(landing.y - origin.y) * lab.world.voxel_size, 0.0)
		var place := func(t: float) -> void:
			var turn := Basis(axis, PI * 0.5 * t * t)
			mesh.transform = Transform3D(turn, hinge + fall * t * t + turn * arm)
		tween.tween_method(place, 0.0, 1.0, duration)
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
