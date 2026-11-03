class_name VoxelFx
extends RefCounted
## Shared looks for effects, so everything reads as voxels: cube particles (CPUParticles3D, which
## the gl_compatibility renderer and the web build run everywhere) drawn by shaders/voxel_fx.gdshader
## (axis-aligned cubes snapped to a world grid and to size steps, flat face-shaded colors), stepped
## color ramps, ground stains and splats, one-shot cube bursts and blasts, and the pixel overlay
## material for fullscreen status effects. Effect cubes are opaque; the rare translucent one (the
## spore fog) is truly alpha-blended (alpha_material, shaders/voxel_fx_alpha.gdshader), never
## dithered.
##
## Meshes and materials are cached and shared: a burst costs one CPUParticles3D node for its
## lifetime, nothing else.

const SHADER := preload("res://shaders/voxel_fx.gdshader")
const ALPHA_SHADER := preload("res://shaders/voxel_fx_alpha.gdshader")
const OVERLAY_SHADER := preload("res://shaders/pixel_overlay.gdshader")
## Effect grid (meters): half a world voxel, so effects line up with the terrain's 0.1 m voxels.
const GRID := 0.05

static var _cubes := {}
static var _volumes := {}
static var _curves := {}


## The cube shader: snap makes each instance a grid-snapped cube of edge cube_size (at scale 1).
static func material(cube_size := 0.1, snap := true, tint := Color.WHITE) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("cube_size", cube_size)
	m.set_shader_parameter("snap", snap)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("grid", GRID)
	m.set_shader_parameter("size_step", GRID)
	return m


## The translucent cube shader (true alpha blending, sorted with the transparent pass): the same
## parameters as material(). Use it on few cubes.
static func alpha_material(cube_size := 0.1, snap := true, tint := Color.WHITE) -> ShaderMaterial:
	var m := material(cube_size, snap, tint)
	m.shader = ALPHA_SHADER
	return m


## A shared cube mesh of edge size with the snapping cube material (colors from instances).
static func cube(size: float) -> BoxMesh:
	var key := snappedf(size, 0.001)
	if not _cubes.has(key):
		var box := BoxMesh.new()
		box.size = Vector3.ONE * key
		box.material = material(key)
		_cubes[key] = box
	return _cubes[key]


## colors (Color, alpha included) in equal steps over a particle's life, with no blending between.
static func ramp(colors: Array) -> Gradient:
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var packed := PackedColorArray()
	for i in colors.size():
		offsets.append(float(i) / colors.size())
		packed.append(colors[i])
	gradient.offsets = offsets
	gradient.colors = packed
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	return gradient


## Full size until hold (0..1 of the life), then shrinking to nothing; the shader turns the shrink
## into whole grid steps.
static func shrink(hold := 0.5) -> Curve:
	var key := snappedf(hold, 0.01)
	if not _curves.has(key):
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 1.0), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
		curve.add_point(Vector2(key, 1.0), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
		curve.add_point(Vector2(1.0, 0.0), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
		_curves[key] = curve
	return _curves[key]


## A cube emitter: size meters a side, stepping through colors, shrinking out after hold. Not yet
## emitting; set the shape, direction and speeds on it.
static func particles(size: float, colors: Array, hold := 0.5) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = cube(size)
	p.color_ramp = ramp(colors)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.0
	p.scale_amount_curve = shrink(hold)
	p.local_coords = false
	p.emitting = false
	return p


## A cube emitter like particles() whose cubes are translucent (colors' alpha, truly blended) and
## drawn back to front. A few big cubes, not a swarm.
static func alpha_particles(size: float, colors: Array, hold := 0.5) -> CPUParticles3D:
	var p := particles(size, colors, hold)
	p.material_override = alpha_material(snappedf(size, 0.001))
	p.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	return p


## A one-shot burst of cubes from a point in every direction (speed m/s), freed when done.
static func burst(parent: Node, at: Vector3, colors: Array, amount: int, speed: float, size := 0.1,
		lifetime := 0.5, gravity := Vector3.ZERO, damping := 0.0) -> CPUParticles3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var p := particles(size, colors, 0.4)
	p.amount = maxi(1, amount)
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.85
	p.initial_velocity_max = speed
	p.gravity = gravity
	p.damping_min = damping
	p.damping_max = damping
	p.top_level = true
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## An explosion: an expanding shell of hot cubes out to about radius, and slower dark-grey smoke
## cubes that rise and shrink away in steps.
static func blast(parent: Node, at: Vector3, radius: float, color := Color(1.0, 0.55, 0.2)) -> void:
	var hot := [Color(1.0, 1.0, 0.85), Color(1.0, 0.85, 0.35), color, color.darkened(0.45)]
	burst(parent, at, hot, clampi(int(radius * 20.0), 24, 64), radius * 5.0, 0.2, 0.4, Vector3.ZERO, radius * 7.0)
	var smoke := [Color(0.35, 0.32, 0.3), Color(0.25, 0.23, 0.22), Color(0.18, 0.17, 0.17)]
	burst(parent, at, smoke, clampi(int(radius * 10.0), 12, 32), radius * 2.0, 0.2, 0.9, Vector3(0.0, 1.0, 0.0), radius * 2.0)


## A mesh of cubes (cell meters a side) at the given Vector3i cells, outer faces only, centered on
## cell (0, 0, 0).
static func cluster(cells: Array, cell: float) -> ArrayMesh:
	var filled := {}
	for c: Vector3i in cells:
		filled[c] = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]
	for c: Vector3i in filled:
		for f: Vector3i in faces:
			if not filled.has(c + f):
				_face(st, (Vector3(c) - Vector3.ONE * 0.5) * cell, cell, Vector3(f))
	return st.commit()


## A flat splat on a surface: square cells (cell meters) inside a ragged disc of radius, top faces
## only, lying on its local XZ plane.
static func splat(radius: float, cell := 0.05) -> ArrayMesh:
	radius = snappedf(radius, cell)
	var key := "splat:%.2f:%.2f" % [radius, cell]
	if _volumes.has(key):
		return _volumes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := ceili(radius / cell)
	for x in range(-n, n):
		for z in range(-n, n):
			var c := (Vector2(x, z) + Vector2.ONE * 0.5) * cell
			var r := radius * (0.7 + 0.3 * absf(sin(atan2(c.y, c.x) * 3.0 + radius * 17.0)))
			if c.length() <= r:
				_face(st, Vector3(x * cell, -cell, z * cell), cell, Vector3.UP)
	var mesh := st.commit()
	_volumes[key] = mesh
	return mesh


## A cloud's ground stain: a ragged disc of radius made of cell-sized square tiles (top faces only,
## on its local XZ plane at y 0), each tile one of two shades (vertex colors, white and light
## grey, so the tint shows as a mottled patch). variant varies the outline and the mottling.
static func stain(radius: float, cell := 0.1, variant := 0) -> ArrayMesh:
	radius = maxf(cell, snappedf(radius, cell))
	var key := "stain:%.2f:%.2f:%d" % [radius, cell, variant]
	if _volumes.has(key):
		return _volumes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := ceili(radius / cell)
	var lobes := 3.0 + float(variant % 3)
	for x in range(-n, n):
		for z in range(-n, n):
			var c := (Vector2(x, z) + Vector2.ONE * 0.5) * cell
			var angle := atan2(c.y, c.x)
			var r := radius * (0.78 + 0.14 * sin(angle * lobes + variant * 1.7) + 0.08 * sin(angle * 7.0 + variant))
			if c.length() > r:
				continue
			# Speckled near the rim: some edge tiles drop out so the border is ragged, not a curve.
			var h := absi(hash(Vector3i(x, z, variant)))
			if c.length() > r - cell * 1.5 and h % 3 == 0:
				continue
			st.set_color(Color.WHITE if (h >> 3) % 3 != 0 else Color(0.78, 0.78, 0.78))
			_face(st, Vector3(x * cell, -cell, z * cell), cell, Vector3.UP)
	var mesh := st.commit()
	_volumes[key] = mesh
	return mesh


## The face of the cell at corner (size a side) facing normal.
static func _face(st: SurfaceTool, corner: Vector3, size: float, normal: Vector3) -> void:
	var axis := 0 if normal.x != 0.0 else (1 if normal.y != 0.0 else 2)
	var u := Vector3.ZERO
	var v := Vector3.ZERO
	u[(axis + 1) % 3] = size
	v[(axis + 2) % 3] = size
	var origin := corner
	if normal[axis] > 0.0:
		origin[axis] += size
	var quad := [origin, origin + u, origin + u + v, origin + v]
	# Godot's front faces wind clockwise seen from outside.
	var order := [0, 1, 2, 0, 2, 3] if u.cross(v).dot(normal) < 0.0 else [0, 2, 1, 0, 3, 2]
	for i: int in order:
		st.set_normal(normal)
		st.add_vertex(quad[i])


## The pixel overlay material for a fullscreen ColorRect: dithered edge rings from inner in cell px
## blocks, or (inner below 0) a flat, truly blended tint over the whole screen with a ragged
## border of solid blocks (the blinded fog).
static func overlay(inner := 0.45, cell := 4.0, levels := 4.0, max_alpha := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = OVERLAY_SHADER
	m.set_shader_parameter("inner", inner)
	m.set_shader_parameter("cell", cell)
	m.set_shader_parameter("levels", levels)
	m.set_shader_parameter("max_alpha", max_alpha)
	m.set_shader_parameter("amount", 1.0)
	return m
