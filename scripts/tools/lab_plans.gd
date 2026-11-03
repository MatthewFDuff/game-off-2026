extends SceneTree
## Floor plans of a level as PNGs, one pixel per voxel, straight from its voxels (no window needed):
##   godot --headless --path . --script res://scripts/tools/lab_plans.gd -- <output_dir> [level] [y1,y2,...]
## For each floor height y the plan shows the layer y + 1 (waist height) in material colors, air as
## near-black, with markers drawn over it (spawns green, triggers yellow, spawners red, items
## violet, vats cyan, lights pale, speakers blue) and doors in orange. Default: the laboratory's
## floors (LabLayout.Y).

const M := preload("res://scripts/voxel/voxel_materials.gd")
const Layout := preload("res://scripts/tools/lab_layout.gd")
const MARKER_COLORS := {spawn = Color(0.3, 1.0, 0.4), trigger = Color(1.0, 0.9, 0.2), horde = Color(1.0, 0.25, 0.25),
		item = Color(0.85, 0.5, 1.0), clone_vat = Color(0.3, 1.0, 1.0), light = Color(0.9, 0.9, 0.7), speaker = Color(0.4, 0.6, 1.0),
		kill_zone = Color(1.0, 0.2, 0.6)}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else OS.get_user_data_dir()
	var level_name: String = args[1] if args.size() > 1 else "laboratory"
	var floors: Array = []
	if args.size() > 2:
		for part in str(args[2]).split(","):
			floors.append(int(part))
	else:
		for key in Layout.Y:
			floors.append(int(Layout.Y[key]))
	var level := LevelData.load_level(level_name)
	if level == null:
		print("lab_plans: no level ", level_name)
		quit(1)
		return
	var world := VoxelWorld.new()
	world.size_in_chunks = level.settings.size_in_chunks
	world.immediate_remesh_limit = 0
	world.detach_floating = false
	root.add_child(world)
	world.set_data(level.voxels)
	var size := world.get_size_in_voxels()
	for y in floors:
		var image := Image.create(size.x, size.z, false, Image.FORMAT_RGB8)
		for x in size.x:
			for z in size.z:
				var m := world.get_voxel(Vector3i(x, y + 1, z))
				var color := Color(0.05, 0.05, 0.06)
				if m != 0:
					color = M.DEFS[m].color if M.DEFS.has(m) else Color.MAGENTA
					# Floors seen from above at the layer below read darker than walls.
				elif world.get_voxel(Vector3i(x, y, z)) == 0:
					color = Color(0.0, 0.0, 0.0) # A hole: no floor under this air.
				image.set_pixel(x, z, color)
		for object in level.objects.values():
			if object.kind == "prop":
				var box: AABB = LevelSchema.prop_box(object)
				if box.position.y > y + Layout.H or box.end.y <= y:
					continue
				var tint := Color(1.0, 0.55, 0.1) if LevelSchema.is_door(object) else Color(0.55, 0.45, 0.35)
				_rect(image, box, tint)
			elif object.kind == "marker":
				var position: Vector3 = object.position
				if position.y < y - 6 or position.y > y + Layout.H:
					continue
				var tint: Color = MARKER_COLORS.get(object.type, Color.WHITE)
				if object.type == "trigger":
					_outline(image, LevelSchema.marker_box(object), tint)
				_dot(image, Vector2i(int(position.x), int(position.z)), tint, 2 if object.type != "light" else 1)
		var path := out.path_join("plan_%s_y%d.png" % [level_name, y])
		image.save_png(path)
		print("saved ", path)
	world.free()
	quit(0)


func _rect(image: Image, box: AABB, color: Color) -> void:
	for x in range(int(box.position.x), int(box.end.x)):
		for z in range(int(box.position.z), int(box.end.z)):
			if x >= 0 and z >= 0 and x < image.get_width() and z < image.get_height():
				image.set_pixel(x, z, color)


func _outline(image: Image, box: AABB, color: Color) -> void:
	for x in range(int(box.position.x), int(box.end.x)):
		for z in [int(box.position.z), int(box.end.z) - 1]:
			if x >= 0 and z >= 0 and x < image.get_width() and z < image.get_height():
				image.set_pixel(x, z, color)
	for z in range(int(box.position.z), int(box.end.z)):
		for x in [int(box.position.x), int(box.end.x) - 1]:
			if x >= 0 and z >= 0 and x < image.get_width() and z < image.get_height():
				image.set_pixel(x, z, color)


func _dot(image: Image, at: Vector2i, color: Color, radius: int) -> void:
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var p := at + Vector2i(dx, dz)
			if p.x >= 0 and p.y >= 0 and p.x < image.get_width() and p.y < image.get_height():
				image.set_pixel(p.x, p.y, color)
