class_name GearModels
## Weapon and pickup models: MagicaVoxel files in assets/vox/weapons/<name>.vox and
## assets/vox/items/<item name>.vox. The files are the source of truth; the generators here only
## write the placeholders (scripts/tools/export_vox.gd) and stand in when a file is missing.
##
## Models face -Z (MagicaVoxel's front). GLOW voxels are drawn in a tint color instead of their
## own (the shooter's ammo tank, a pickup's item color), so one model serves every color. A
## weapon's muzzle is the middle of its front-most (lowest z) voxels.

const M := preload("res://scripts/voxel/voxel_materials.gd")
const WEAPON_DIR := "res://assets/vox/weapons/"
const ITEM_DIR := "res://assets/vox/items/"
const WEAPONS := ["shroom_shooter", "axe"]
## Every pickup with a placeholder (the item marker names these).
const ITEMS := ["medkit", "ammo_shotgun", "ammo_flame", "ammo_explosive", "ammo_ricochet", "ammo_homing",
		"ammo_poison", "flask_fire", "flask_poison", "flask_rage", "flask_freeze", "flask_foam", "keycard_red", "keycard_blue",
		"keycard_green", "keycard_black", "spore_shooter", "snack", "paper"]
const ITEM_COLORS := {
	medkit = Color(1.0, 0.25, 0.25), flask_fire = Color(1.0, 0.5, 0.15), flask_poison = Color(0.45, 1.0, 0.3),
	flask_rage = Color(1.0, 0.2, 0.3), flask_freeze = Color(0.55, 0.85, 1.0), flask_foam = Color(0.93, 0.95, 0.97),
	keycard_red = Color(1.0, 0.2, 0.2),
	keycard_blue = Color(0.25, 0.5, 1.0), keycard_green = Color(0.3, 1.0, 0.4), keycard_black = Color(0.12, 0.12, 0.14),
}

## Render layer of weapon models only (not pickups). The player's flashlight (player.tscn) leaves it
## out of its cull mask, so the gun right next to the lamp isn't blown out into a flat grey panel.
const WEAPON_LAYER := 1 << 19

## path -> model, loaded once and dropped on live reload.
static var _cache := {}
## Glow tint (already lightened) -> its unshaded material, shared by every model in that color.
static var _glow_materials := {}


static func weapon(weapon_name: String) -> Dictionary:
	var model := _load(WEAPON_DIR + weapon_name + ".vox", weapon_name)
	if not model.is_empty():
		model.weapon = true
	return model


static func item(item_name: String) -> Dictionary:
	if item_name.begins_with("paper_"):
		item_name = "paper" # A printed page (LevelPlay): every one looks the same.
	return _load(ITEM_DIR + item_name + ".vox", item_name)


## The tint for an item's GLOW voxels.
static func item_color(item_name: String) -> Color:
	if item_name.begins_with("ammo_"):
		var type := AmmoType.by_name(item_name.trim_prefix("ammo_"))
		if type:
			return type.color
	if item_name == "spore_shooter":
		var basic := AmmoType.by_name("basic")
		if basic:
			return basic.color # Its tank shows the ammo it comes loaded with.
	return ITEM_COLORS.get(item_name, Color(0.9, 0.9, 0.9))


## Live reload: forgets a file. Returns its model name, or "" if it isn't a weapon or item.
static func forget(path: String) -> String:
	if not (path.begins_with(WEAPON_DIR) or path.begins_with(ITEM_DIR)):
		return ""
	_cache.erase(path)
	return path.get_file().get_basename()


static func _load(path: String, model_name: String) -> Dictionary:
	if not _cache.has(path):
		var loaded := VoxFile.load_model(path) if FileAccess.file_exists(path) else {}
		_cache[path] = loaded if not loaded.is_empty() else generate(model_name)
	return _cache[path]


## Builds a model as a Node3D: the body in the world's voxel material, GLOW voxels in tint
## (meshes "Body" and "Glow"; recolor with set_tint). voxel is the drawn size of one voxel in
## meters; the node's origin is the model's min corner unless centered on offset (in voxels).
## The body and glow meshes are built once per model (and world) and shared: they're kept on the
## model itself (`_meshes`), so a live reload's forget drops them with it.
static func build(world: VoxelWorld, model: Dictionary, tint: Color, voxel: float, offset := Vector3.ZERO) -> Node3D:
	var root := Node3D.new()
	if model.is_empty() or world == null:
		return root
	var scale := voxel / world.voxel_size
	root.scale = Vector3.ONE * scale
	var meshes := _meshes_of(world, model)
	var shift := -offset * world.voxel_size
	var body_mesh := MeshInstance3D.new()
	body_mesh.name = "Body"
	body_mesh.mesh = meshes[0]
	body_mesh.position = shift
	if model.get("weapon", false):
		body_mesh.layers = WEAPON_LAYER
	root.add_child(body_mesh)
	if meshes[1] != null:
		var glow_mesh := MeshInstance3D.new()
		glow_mesh.name = "Glow"
		glow_mesh.mesh = meshes[1]
		glow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow_mesh.position = shift
		root.add_child(glow_mesh)
	set_tint(root, tint)
	return root


## [body mesh, glow mesh or null] of a model, built once and kept on the model (for the latest
## world it was built in).
static func _meshes_of(world: VoxelWorld, model: Dictionary) -> Array:
	var key := world.get_instance_id()
	var built: Dictionary = model.get("_meshes", {})
	if built.has(key):
		return built[key]
	built = {}
	var body := PackedByteArray(model.voxels)
	var glow := PackedByteArray()
	glow.resize(body.size())
	var any_glow := false
	for i in body.size():
		if body[i] == M.GLOW:
			glow[i] = M.GLOW
			body[i] = M.AIR
			any_glow = true
	var meshes := [world.build_model_mesh(model.size, body), world.build_model_mesh(model.size, glow) if any_glow else null]
	built[key] = meshes
	model["_meshes"] = built
	return meshes


## Recolors a built model's GLOW voxels (a shared material per color).
static func set_tint(root: Node3D, tint: Color) -> void:
	var glow := root.get_node_or_null("Glow") as MeshInstance3D
	if glow:
		glow.material_override = glow_material(tint.lightened(0.15))


## The unshaded GLOW material in a color, shared by every model tinted that color.
static func glow_material(color: Color) -> StandardMaterial3D:
	if not _glow_materials.has(color):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.disable_fog = true
		material.albedo_color = color
		_glow_materials[color] = material
	return _glow_materials[color]


## Muzzle of a weapon model, in voxels: the middle of its front-most voxels.
static func muzzle(model: Dictionary) -> Vector3:
	if model.is_empty():
		return Vector3.ZERO
	var size: Vector3i = model.size
	var voxels: PackedByteArray = model.voxels
	for z in size.z:
		var sum := Vector2.ZERO
		var n := 0
		for y in size.y:
			for x in size.x:
				if voxels[x + y * size.x + z * size.x * size.y] != 0:
					sum += Vector2(x + 0.5, y + 0.5)
					n += 1
		if n > 0:
			return Vector3(sum.x / n, sum.y / n, z)
	return Vector3(size) * 0.5


# --- Placeholders --------------------------------------------------------------------------------

static func generate(model_name: String) -> Dictionary:
	if model_name == "shroom_shooter":
		return _shroom_shooter()
	if model_name == "axe":
		return _axe()
	if model_name == "medkit":
		return _medkit()
	if model_name == "spore_shooter":
		return _spore_shooter_item()
	if model_name == "ammo_flame":
		return _canister()
	if model_name.begins_with("ammo_"):
		return _ammo_box(model_name)
	if model_name.begins_with("flask_"):
		return _flask()
	if model_name.begins_with("keycard_"):
		return _keycard()
	if model_name == "snack":
		return _snack()
	if model_name == "paper":
		return _paper()
	push_warning("no placeholder model for '%s'" % model_name)
	return _ammo_box(model_name)


## The spore shooter: a compact gun of dark gunmetal (HATCH) with brass fittings (LADDER): a short
## barrel with a brass muzzle ring and band, a boxy receiver with brass trim, a small glass-rimmed
## tank on top holding the loaded ammo (its GLOW voxels, the only tinted part), a rubber grip, a
## brass trigger guard and a stubby stock with a rubber butt pad. Nothing about it is shroom-shaped
## or shroom-colored.
static func _shroom_shooter() -> Dictionary:
	var model := _empty(Vector3i(7, 12, 15))
	_box(model, Vector3i(2, 4, 0), Vector3i(5, 7, 6), M.HATCH) # Barrel.
	_box(model, Vector3i(3, 5, 0), Vector3i(4, 6, 1), M.RUBBER) # Bore.
	_box(model, Vector3i(1, 3, 1), Vector3i(6, 8, 2), M.LADDER) # Muzzle ring.
	_box(model, Vector3i(2, 4, 1), Vector3i(5, 7, 2), M.HATCH)
	_box(model, Vector3i(1, 3, 4), Vector3i(6, 8, 5), M.LADDER) # Barrel band.
	_box(model, Vector3i(2, 4, 4), Vector3i(5, 7, 5), M.HATCH)
	_box(model, Vector3i(1, 2, 5), Vector3i(6, 8, 13), M.HATCH) # Receiver.
	_box(model, Vector3i(1, 7, 5), Vector3i(2, 8, 7), M.LADDER) # Brass trim at the front corners.
	_box(model, Vector3i(5, 7, 5), Vector3i(6, 8, 7), M.LADDER)
	_box(model, Vector3i(1, 4, 9), Vector3i(2, 5, 10), M.LADDER) # Rivets.
	_box(model, Vector3i(5, 4, 9), Vector3i(6, 5, 10), M.LADDER)
	# The tank: ammo-colored liquid in a brass-posted frame (the liquid shows through every face),
	# glass along its top edges, a brass valve.
	_box(model, Vector3i(2, 8, 7), Vector3i(5, 11, 12), M.GLOW)
	for corner: Vector2i in [Vector2i(2, 7), Vector2i(4, 7), Vector2i(2, 11), Vector2i(4, 11)]:
		_box(model, Vector3i(corner.x, 8, corner.y), Vector3i(corner.x + 1, 12, corner.y + 1), M.LADDER)
	_box(model, Vector3i(2, 11, 8), Vector3i(3, 12, 11), M.GLASS)
	_box(model, Vector3i(4, 11, 8), Vector3i(5, 12, 11), M.GLASS)
	_box(model, Vector3i(3, 11, 7), Vector3i(4, 12, 12), M.GLASS)
	_put(model, 3, 11, 9, M.LADDER)
	_box(model, Vector3i(2, 0, 10), Vector3i(5, 2, 13), M.RUBBER) # Grip.
	_box(model, Vector3i(2, 0, 13), Vector3i(5, 1, 14), M.RUBBER)
	_box(model, Vector3i(3, 0, 7), Vector3i(4, 1, 10), M.LADDER) # Trigger guard.
	_box(model, Vector3i(3, 1, 7), Vector3i(4, 2, 8), M.LADDER)
	_box(model, Vector3i(3, 1, 8), Vector3i(4, 2, 9), M.STEEL) # Trigger.
	_box(model, Vector3i(2, 3, 13), Vector3i(5, 7, 15), M.HATCH) # Stock.
	_box(model, Vector3i(2, 3, 14), Vector3i(5, 4, 15), M.RUBBER) # Butt pad.
	return model


## The fire axe (melee): a wooden haft standing up the Y axis with a rubber grip at the bottom, a
## steel head at the top whose blade faces -Z, and a red-painted cheek. The grip is the model's
## handle (Weapon holds it at AXE_GRIP).
static func _axe() -> Dictionary:
	var model := _empty(Vector3i(3, 22, 10))
	_box(model, Vector3i(1, 0, 7), Vector3i(2, 22, 8), M.WOOD) # Haft.
	_box(model, Vector3i(0, 1, 6), Vector3i(3, 6, 9), M.RUBBER) # Grip.
	_box(model, Vector3i(0, 16, 6), Vector3i(3, 21, 10), M.STEEL) # Eye of the head, poll behind.
	for y in range(14, 22):
		var depth := 6 - mini(absi(y - 18), 3) # The blade flares toward its edge.
		_box(model, Vector3i(1, y, 6 - depth), Vector3i(2, y + 1, 6), M.STEEL)
		_put(model, 1, y, 6 - depth, M.METAL) # Edge.
	_box(model, Vector3i(0, 17, 3), Vector3i(3, 20, 6), M.WARNING) # Painted cheeks.
	_box(model, Vector3i(1, 17, 3), Vector3i(2, 20, 6), M.STEEL)
	return model


## A metal ammo box with a glowing band in the ammo color and a rubber lid.
static func _ammo_box(item_name: String) -> Dictionary:
	var model := _empty(Vector3i(7, 5, 5))
	_box(model, Vector3i(0, 0, 0), Vector3i(7, 4, 5), M.STEEL)
	_box(model, Vector3i(0, 1, 0), Vector3i(7, 3, 1), M.GLOW)
	_box(model, Vector3i(0, 1, 4), Vector3i(7, 3, 5), M.GLOW)
	_box(model, Vector3i(0, 4, 0), Vector3i(7, 5, 5), M.RUBBER)
	if item_name == "ammo_explosive":
		_box(model, Vector3i(2, 4, 1), Vector3i(5, 5, 4), M.WARNING)
	return model


## A fuel canister: a glowing tank with a steel cap and handle.
static func _canister() -> Dictionary:
	var model := _empty(Vector3i(5, 8, 5))
	for y in 6:
		for z in 5:
			for x in 5:
				if Vector2(x - 2.0, z - 2.0).length() <= 2.3:
					_put(model, x, y, z, M.GLOW if y in [1, 2, 3, 4] and (x == 0 or x == 4 or z == 0 or z == 4) else M.STEEL)
	_box(model, Vector3i(2, 6, 2), Vector3i(3, 7, 3), M.STEEL)
	_box(model, Vector3i(1, 7, 2), Vector3i(4, 8, 3), M.RUBBER)
	return model


## A white case with a glowing cross on the front and back.
static func _medkit() -> Dictionary:
	var model := _empty(Vector3i(7, 5, 3))
	_box(model, Vector3i(0, 0, 0), Vector3i(7, 5, 3), M.PLASTIC)
	for z in [0, 2]:
		_box(model, Vector3i(3, 1, z), Vector3i(4, 4, z + 1), M.GLOW)
		_box(model, Vector3i(2, 2, z), Vector3i(5, 3, z + 1), M.GLOW)
	return model


## A round-bottomed flask of glowing liquid with a glass neck and a cork.
static func _flask() -> Dictionary:
	var model := _empty(Vector3i(5, 8, 5))
	for y in 5:
		for z in 5:
			for x in 5:
				if Vector3(x - 2.0, y - 2.0, z - 2.0).length() <= 2.4:
					_put(model, x, y, z, M.GLOW)
	_box(model, Vector3i(2, 5, 2), Vector3i(3, 7, 3), M.GLASS)
	_box(model, Vector3i(2, 7, 2), Vector3i(3, 8, 3), M.WOOD)
	return model


## The spore shooter as a pickup: the same gunmetal and brass gun lying on its side (length along
## X, muzzle at +X), the ammo tank on top.
static func _spore_shooter_item() -> Dictionary:
	var model := _empty(Vector3i(12, 7, 3))
	_box(model, Vector3i(0, 2, 0), Vector3i(2, 5, 3), M.HATCH) # Stock.
	_box(model, Vector3i(0, 2, 0), Vector3i(1, 5, 3), M.LADDER) # Butt plate.
	_box(model, Vector3i(2, 1, 0), Vector3i(8, 5, 3), M.HATCH) # Receiver.
	_box(model, Vector3i(2, 4, 0), Vector3i(8, 5, 1), M.LADDER) # Trim.
	_box(model, Vector3i(2, 4, 2), Vector3i(8, 5, 3), M.LADDER)
	_box(model, Vector3i(8, 2, 1), Vector3i(12, 4, 2), M.HATCH) # Barrel.
	_box(model, Vector3i(10, 1, 0), Vector3i(11, 5, 3), M.LADDER) # Muzzle ring.
	_box(model, Vector3i(4, 5, 0), Vector3i(5, 7, 3), M.LADDER) # Tank end plates.
	_box(model, Vector3i(7, 5, 0), Vector3i(8, 7, 3), M.LADDER)
	_box(model, Vector3i(5, 5, 0), Vector3i(7, 7, 3), M.GLOW) # Tank.
	_box(model, Vector3i(5, 6, 0), Vector3i(7, 7, 1), M.GLASS)
	_box(model, Vector3i(5, 6, 2), Vector3i(7, 7, 3), M.GLASS)
	_box(model, Vector3i(3, 0, 1), Vector3i(5, 1, 2), M.RUBBER) # Grip.
	return model


## A flat plastic card with a glowing stripe.
static func _keycard() -> Dictionary:
	var model := _empty(Vector3i(6, 4, 1))
	_box(model, Vector3i(0, 0, 0), Vector3i(6, 4, 1), M.PLASTIC)
	_box(model, Vector3i(0, 2, 0), Vector3i(6, 3, 1), M.GLOW)
	_box(model, Vector3i(4, 0, 0), Vector3i(5, 1, 1), M.SCREEN)
	return model


## A vending machine snack: a bar in a bright wrapper with crimped ends.
static func _snack() -> Dictionary:
	var model := _empty(Vector3i(6, 2, 3))
	_box(model, Vector3i(1, 0, 0), Vector3i(5, 2, 3), M.WARNING)
	_box(model, Vector3i(0, 0, 1), Vector3i(6, 1, 2), M.PLASTIC)
	_box(model, Vector3i(2, 1, 1), Vector3i(4, 2, 2), M.GLOW)
	return model


## A printed page: a white sheet with rows of black type.
static func _paper() -> Dictionary:
	var model := _empty(Vector3i(5, 1, 7))
	_box(model, Vector3i(0, 0, 0), Vector3i(5, 1, 7), M.PLASTIC)
	for z in range(1, 6, 2):
		_box(model, Vector3i(1, 0, z), Vector3i(4, 1, z + 1), M.RUBBER)
	return model


static func _empty(size: Vector3i) -> Dictionary:
	var voxels := PackedByteArray()
	voxels.resize(size.x * size.y * size.z)
	return {size = size, voxels = voxels}


static func _put(model: Dictionary, x: int, y: int, z: int, id: int) -> void:
	var size: Vector3i = model.size
	model.voxels[x + y * size.x + z * size.x * size.y] = id


## Fills [from, to) with a material.
static func _box(model: Dictionary, from: Vector3i, to: Vector3i, id: int) -> void:
	for z in range(from.z, to.z):
		for y in range(from.y, to.y):
			for x in range(from.x, to.x):
				_put(model, x, y, z, id)
