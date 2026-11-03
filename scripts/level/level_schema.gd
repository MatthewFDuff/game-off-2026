class_name LevelSchema
## What can be placed in a level and which properties each thing has. The editor's inspector is
## built from these field lists, and new objects start from their defaults.
##
## Objects are dictionaries. Every one has `id` (unique, editable, what story scripts look up) and
## `kind` ("prop" or "marker"). Props have `name`, `origin` (Vector3i, voxel min corner) and
## `facing`; markers have `type`, `position` (Vector3, voxel units) and `yaw` (degrees).
##
## Field types: "string", "int", "float", "bool", "color", "vector3i", "enum" (with `options`).

const P := preload("res://scripts/world/props.gd")

const FACINGS := ["north", "east", "south", "west"]

## Prop fields shown in the inspector. Door fields only matter when `door` is on.
const PROP_FIELDS := [
	{key = "id", type = "string"},
	{key = "facing", type = "enum", options = FACINGS},
	{key = "value", type = "int", min = 0, max = 1000000, label = "Asset value ($, 0 = not an asset)"},
	{key = "door", type = "bool", label = "Is a door"},
	{key = "door_offset", type = "vector3i", label = "Door opens by (voxels)"},
	{key = "door_speed", type = "float", min = 0.1, max = 20.0, label = "Door speed (m/s)"},
	{key = "door_locked", type = "bool", label = "Door locked"},
]

const MARKERS := {
	spawn = {label = "Player spawn", color = Color(0.3, 0.9, 0.4), fields = [
		{key = "index", type = "int", min = 1, max = 4, default = 1, label = "Player"},
	]},
	trigger = {label = "Trigger", color = Color(0.95, 0.8, 0.2), fields = [
		{key = "size", type = "vector3i", default = Vector3i(20, 20, 20), label = "Size (voxels)"},
		{key = "repeat", type = "bool", default = false, label = "Fires every time"},
		{key = "who", type = "enum", options = ["any", "all"], default = "any", label = "Players needed"},
		{key = "activates", type = "string", default = "", label = "Activates (spawner ids, or horde)"},
	]},
	speaker = {label = "Intercom speaker", color = Color(0.4, 0.75, 1.0), fields = []},
	light = {label = "Light", color = Color(1.0, 0.95, 0.7), fields = [
		{key = "light", type = "enum", options = ["omni", "spot"], default = "omni", label = "Shape"},
		{key = "color", type = "color", default = Color(1.0, 0.9, 0.75)},
		{key = "energy", type = "float", min = 0.0, max = 16.0, default = 1.5},
		{key = "range", type = "float", min = 0.5, max = 60.0, default = 10.0, label = "Range (m)"},
		{key = "angle", type = "float", min = 5.0, max = 89.0, default = 40.0, label = "Spot angle"},
		{key = "pitch", type = "float", min = -90.0, max = 90.0, default = -90.0, label = "Spot pitch"},
		{key = "shadows", type = "bool", default = false},
		{key = "flicker", type = "enum", options = ["none", "subtle", "broken"], default = "none"},
		{key = "power", type = "enum", options = ["facility", "emergency"], default = "facility", label = "Powered by"},
	]},
	horde = {label = "Horde spawner", color = Color(0.9, 0.3, 0.3), fields = [
		{key = "kinds", type = "string", default = "basic", label = "Enemy kinds (comma-separated)"},
		{key = "rate", type = "float", min = 0.0, max = 120.0, default = 6.0, label = "Spawns per minute"},
		{key = "max_alive", type = "int", min = 0, max = 50, default = 4, label = "Most alive at once"},
		{key = "active", type = "bool", default = true, label = "Active from the start"},
		{key = "radius", type = "float", min = 0.0, max = 10.0, default = 1.5, label = "Spawn radius (m)"},
	]},
	clone_vat = {label = "Clone vat", color = Color(0.4, 1.0, 0.8), fields = []},
	kill_zone = {label = "Kill zone", color = Color(1.0, 0.2, 0.6), fields = [
		{key = "size", type = "vector3i", default = Vector3i(20, 30, 20), label = "Size (voxels)"},
	]},
	item = {label = "Item spot", color = Color(0.85, 0.6, 1.0), fields = [
		{key = "item", type = "string", default = "medkit", label = "Item (medkit, ammo_<type>, flask_<type>, keycard_<color>)"},
	]},
}

## Placeholder asset prices for the payroll, by prop name prefix. Change freely, or per prop in the
## editor.
const ASSET_VALUES := {
	"fume_hood": 4000, "lab_bench": 2500, "shelf_lab": 1200, "spore_tank": 6000, "vending_machine": 1500,
	"fridge": 900, "desk": 600, "counter": 1100, "water_cooler": 200, "whiteboard": 150, "corkboard": 40,
	"couch": 500, "locker": 250, "table": 300, "chair": 50, "stool": 40, "bench": 120, "shelf_storage": 300,
	"crate": 30, "barrel": 60, "trash_can": 20, "grow_bed": 800, "plank_stack": 25, "sandbags": 30,
}


static func default_value(prop_name: String) -> int:
	var best := ""
	for prefix: String in ASSET_VALUES:
		if prop_name.begins_with(prefix) and prefix.length() > best.length():
			best = prefix
	return ASSET_VALUES.get(best, 100)


static func new_prop(prop_name: String, origin: Vector3i, facing: int) -> Dictionary:
	return {kind = "prop", name = prop_name, origin = origin, facing = facing, value = default_value(prop_name),
			door = false, door_offset = Vector3i(0, 0, 0), door_speed = 2.0, door_locked = false}


static func new_marker(type: String, position: Vector3, yaw := 0.0) -> Dictionary:
	var marker := {kind = "marker", type = type, position = position, yaw = yaw}
	for field: Dictionary in MARKERS[type].fields:
		marker[field.key] = field.default
	return marker


## Fills in fields a marker is missing (level files saved before the field existed) with defaults.
static func fill_defaults(object: Dictionary) -> void:
	if object.get("kind") != "marker" or not MARKERS.has(object.get("type")):
		return
	for field: Dictionary in MARKERS[object.type].fields:
		if not object.has(field.key):
			object[field.key] = field.default
		elif field.type == "int" and object[field.key] is float:
			object[field.key] = int(object[field.key]) # JSON numbers come back as floats.


## Inspector fields for an object.
static func fields_for(object: Dictionary) -> Array:
	if object.kind == "prop":
		return PROP_FIELDS
	return [{key = "id", type = "string"}, {key = "yaw", type = "float", min = -180.0, max = 180.0}] + MARKERS[object.type].fields


## A prop's box in voxel space: AABB from its origin with its turned model's size.
static func prop_box(object: Dictionary) -> AABB:
	var model := P.load_prop(object.name)
	if model.is_empty():
		return AABB(Vector3(object.origin), Vector3.ONE)
	var size: Vector3i = model.size
	if object.facing == P.EAST or object.facing == P.WEST:
		size = Vector3i(size.z, size.y, size.x)
	return AABB(Vector3(object.origin), Vector3(size))


## A marker's box in voxel space: its volume for triggers and kill zones, a small cube otherwise.
static func marker_box(object: Dictionary) -> AABB:
	var position: Vector3 = object.position
	if object.has("size"):
		var size := Vector3(object.size)
		return AABB(position - Vector3(size.x * 0.5, 0.0, size.z * 0.5), size)
	return AABB(position - Vector3(2, 0, 2), Vector3(4, 4, 4))


static func box_of(object: Dictionary) -> AABB:
	return prop_box(object) if object.kind == "prop" else marker_box(object)
