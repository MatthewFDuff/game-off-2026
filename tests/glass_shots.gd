extends SceneTree
## Screenshots of see-through glass in the laboratory, in play (needs a window, not --headless):
##   godot --path . --script res://tests/glass_shots.gd -- <output_dir>
## Works on a scratch copy of res://levels/laboratory. Shoots the first two glass cases (glass_case
## props, stamped for play: the case's inside behind the pane) and the first two window openings
## (the room beyond) through a camera of its own, set back from a pane along its open side, with a
## work light: glass_case.png, glass_case_2.png, glass_window.png, glass_window_2.png.
##
## Game types are left untyped (see editor_test.gd).

const SCRATCH := "user://glass_shots_levels/"
const LEVEL := "glass_shots"
const M := preload("res://scripts/voxel/voxel_materials.gd")
const SIDES := [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]

var _out := ""
var lab
var _camera := Camera3D.new()
## A work light at the camera: the lab's rooms can be dark at the start of a shift.
var _light := OmniLight3D.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	root.size = Vector2i(1280, 800)
	LevelData.save_dir_override = SCRATCH
	var to := SCRATCH.path_join(LEVEL)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to))
	for file in ["level.json", "voxels.bin"]:
		FileAccess.open(to.path_join(file), FileAccess.WRITE).store_buffer(FileAccess.get_file_as_bytes("res://levels/laboratory".path_join(file)))
	root.get_node("Net").start_solo(LEVEL, "play")
	while current_scene == null or current_scene.name != "Lab" or current_scene.local_player() == null:
		await process_frame
	lab = current_scene
	await _frames(30)
	_camera.fov = 60.0
	root.add_child(_camera)
	_light.omni_range = 8.0
	_light.light_energy = 2.5
	root.add_child(_light)

	var shots := 0
	for object: Dictionary in lab.level.objects.values():
		if object.kind != "prop" or object.name != "glass_case" or shots >= 2:
			continue
		var face := _glass_face(LevelBuild.box_of(object, lab.level.objects))
		if not face.is_empty() and await _aim(face.voxel, 1.4, face.side):
			shots += 1
			await _shot("glass_case" if shots == 1 else "glass_case_2")

	var windows := 0
	for object: Dictionary in lab.level.objects.values():
		if object.kind != "opening" or object.type != "window" or windows >= 2:
			continue
		var face := _glass_face(AABB(Vector3(object.from), Vector3(object.to) - Vector3(object.from)))
		if not face.is_empty() and await _aim(face.voxel, 3.0, face.side):
			windows += 1
			await _shot("glass_window" if windows == 1 else "glass_window_2")
	quit(0)


## Points the camera at voxel from distance meters out along an open side (the given one, or the
## first whose camera spot is air and whose ray to the voxel first hits glass). False when none is.
func _aim(voxel: Vector3i, distance: float, side := Vector3i.ZERO) -> bool:
	var target: Vector3 = lab.world.voxel_to_world(voxel)
	for face: Vector3i in ([side] if side != Vector3i.ZERO else SIDES):
		var spot: Vector3 = target + Vector3(face) * distance + Vector3(0.0, 0.25, 0.0)
		if lab.world.get_voxel(lab.world.world_to_voxel(spot)) != M.AIR:
			continue
		var hit: Dictionary = lab.world.raycast(spot, (target - spot).normalized(), distance * 1.5)
		if not hit.hit or not M.TRANSLUCENT.has(int(hit.material)):
			continue
		_camera.look_at_from_position(spot, target)
		_light.global_position = spot + Vector3(0.0, 0.6, 0.0)
		print("aiming from ", spot, " at ", target, " through ", M.DEFS[int(hit.material)].name)
		_camera.make_current()
		await _frames(30)
		return true
	return false


## A see-through voxel of the box (voxel space) near the middle of its height, with open air out
## along a horizontal side: {voxel, side} or {}.
func _glass_face(box: AABB) -> Dictionary:
	var lo := Vector3i(box.position)
	var hi := Vector3i(box.end)
	var mid := (lo.y + hi.y) / 2
	for dy in [0, 2, -2, 4, -4]:
		for z in range(lo.z, hi.z):
			for x in range(lo.x, hi.x):
				var p := Vector3i(x, mid + dy, z)
				if not M.TRANSLUCENT.has(lab.world.get_voxel(p)):
					continue
				for side: Vector3i in SIDES:
					if lab.world.get_voxel(p + side) == M.AIR and lab.world.get_voxel(p + side * 16) == M.AIR:
						return {voxel = p - side * 2, side = side}
	return {}


## Saves the view to <name>.png with every CanvasLayer hidden (the HUD, and the pause panel the
## unfocused window brings up).
func _shot(name: String) -> void:
	for layer: CanvasLayer in root.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	await _frames(3)
	var path := _out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)


## Waits count frames.
func _frames(count: int) -> void:
	for i in count:
		await process_frame
