class_name LevelSchema
## What can be placed in a level and which properties each thing has. The editor's inspector is
## built from these field lists, and new objects start from their defaults.
##
## Objects are dictionaries. Every one has `id` (unique, editable, what story scripts look up) and
## `kind` ("prop", "marker", "room" or "opening"). Props have `name`, `origin` (Vector3i, voxel min
## corner) and `facing`; markers have `type`, `position` (Vector3, voxel units) and `yaw` (degrees).
## Rooms and openings are the level's structure (editor v2): a room has `from` / `to` (Vector3i, its
## inside, the air, as [from, to)), `floor` / `wall` / `ceiling` materials lining it `thickness`
## voxels thick, and `order` (where linings overlap the newest wins). An opening is a box cut
## through linings (`from` / `to`), part of the wall of `room` (moves with it) and, if a door prop
## made it, linked to that `door`. Changing either goes through LevelEdits' structure edits, which
## rewrite only the voxels nobody painted (VoxelWorld.apply_structure). Build mode adds walls,
## floors, ceilings, the storeys and openings in walls (LevelBuild), changed the same way.
##
## Field types: "string", "text" (multi-line string), "int", "float", "bool", "color", "vector3i",
## "enum" (with `options`).

const P := preload("res://scripts/world/props.gd")

const FACINGS := ["north", "east", "south", "west"]

## What E does with a prop in play (the `use` field). See LevelPlay.
##   container       opens once and drops its `contents` in front of it
##   terminal        shows `text`, fires the `on_use` trigger the first time; `needs_power` refuses
##                   it on backup power. With `steps` it is an experiment: each SHIFT while reading
##                   runs the next step and prints its result; `on_use` fires after the last one
##   note            shows `text`
##   station_medkit  heals the user to full, `charges` times
##   station_ammo    20 rounds of `station_ammo_type` (empty: the user's loaded type), `charges` times
##   generator       on backup power: restores power, fires `on_use`, starts the director's finale
##                   for `finale_seconds`
##   glass_case      breaking any of its GLASS voxels (or E, which smashes it) drops its `contents`
##   switch          a lever, button, light switch, breaker or alarm pull: fires `on_use` every time
##                   (only the first time with `once`). With no `on_use`, a breaker panel, fuse box
##                   or light switch toggles the lights of the room it is in; an alarm pull also
##                   starts a horde (never while the director is dormant)
##   vendor          charges `price` to the payroll (the statement's purchases), drops `contents`
##                   and gives the user `buff` (speed or reload, for 20 s). A vending machine's
##                   glass shot out drops a snack too and bills it as damage
##   eyewash         clears Poisoned and Burning on the user; an emergency shower also douses fire
##                   around it
##   defib           revives a dead teammate within 3 m where they lie (before their replacement grows),
##                   else heals the user to full, `charges` times
##   extinguisher    E picks it up as a foam flask; shot or caught in fire it bursts into a foam
##                   cloud (slows enemies, clears spore and poison clouds, douses fire)
##   flip            swaps the prop for its `<name>_flipped` twin (cover), once
##   printer         prints `text` as a page (a `paper_<id>` pickup; picking it up reads it), once
##   radio           toggles a looping track that pulls enemies within 20 m who can't see a player
##   squeak          a squeak: enemies within 10 m who can't see a player go to it for 4 s
## Props that react by name in play, whatever their use: a gas cylinder shot vents and skids 6 m
## (knocking enemies back), shot again, burnt or blasted it explodes; a fragment of more than 50
## voxels coming loose (a hanging crate whose chain is shot) crushes what is under it.
const USES := ["none", "container", "terminal", "note", "station_medkit", "station_ammo", "generator", "glass_case",
		"switch", "vendor", "eyewash", "defib", "extinguisher", "flip", "printer", "radio", "squeak"]
## Buffs a vendor gives (Player statuses "hasted" and "caffeinated").
const BUFFS := ["none", "speed", "reload"]

## Prop fields shown in the inspector, with their defaults (props saved before a field existed get
## these). Door fields only matter when `door` is on; `use` fields only for that use.
const PROP_FIELDS := [
	{key = "id", type = "string"},
	{key = "facing", type = "enum", options = FACINGS},
	{key = "value", type = "int", min = 0, max = 1000000, label = "Asset value ($, 0 = not an asset)"},
	{key = "door", type = "bool", default = false, label = "Is a door"},
	{key = "door_offset", type = "vector3i", default = Vector3i(0, 0, 0), label = "Door opens by (voxels)"},
	{key = "door_speed", type = "float", min = 0.1, max = 20.0, default = 2.0, label = "Door speed (m/s)"},
	{key = "door_locked", type = "bool", default = false, label = "Door locked"},
	{key = "door_key", type = "string", default = "", label = "Door keycard (red, blue, ...; empty = none)"},
	{key = "door_power", type = "bool", default = false, label = "Door needs power (not on backup)"},
	{key = "door_ahead", type = "int", min = 0, max = 30, default = 0, label = "Door: wall in front (voxels)"},
	{key = "door_behind", type = "int", min = 0, max = 30, default = 0, label = "Door: wall behind (voxels)"},
	{key = "use", type = "enum", options = USES, default = "none", label = "Use (E)"},
	{key = "contents", type = "string", default = "", label = "Contents (pickups, comma-separated)"},
	{key = "text", type = "text", default = "", label = "Text (terminal / note)"},
	{key = "steps", type = "text", default = "", label = "Steps (terminal: 'prompt -> result | result' per line, SHIFT advances)"},
	{key = "on_use", type = "string", default = "", label = "On use fires trigger"},
	{key = "needs_power", type = "bool", default = false, label = "Needs power (terminal)"},
	{key = "charges", type = "int", min = 0, max = 99, default = 3, label = "Charges (station)"},
	{key = "station_ammo_type", type = "string", default = "", label = "Ammo type (empty = loaded)"},
	{key = "finale_seconds", type = "float", min = 1.0, max = 1800.0, default = 120.0, label = "Finale (s, generator)"},
	{key = "once", type = "bool", default = false, label = "Works once (switch)"},
	{key = "price", type = "int", min = 0, max = 10000, default = 0, label = "Price ($, vendor)"},
	{key = "buff", type = "enum", options = BUFFS, default = "none", label = "Buff (vendor, 20 s)"},
]

## Default `use` by prop name prefix (the longest matching prefix wins).
const DEFAULT_USES := {
	"cabinet": "container", "drawer_desk": "container", "fridge": "container", "water_cooler": "vendor",
	"locker": "container", "terminal": "terminal", "generator": "generator", "glass_case": "glass_case",
	"medkit_station": "station_medkit", "ammo_bench": "station_ammo",
}

const MARKERS := {
	spawn = {label = "Player spawn", color = Color(0.3, 0.9, 0.4), fields = [
		{key = "index", type = "int", min = 1, max = 4, default = 1, label = "Player"},
	]},
	trigger = {label = "Trigger", color = Color(0.95, 0.8, 0.2), fields = [
		{key = "size", type = "vector3i", default = Vector3i(20, 20, 20), label = "Size (voxels)"},
		{key = "repeat", type = "bool", default = false, label = "Fires every time"},
		{key = "who", type = "enum", options = ["any", "all"], default = "any", label = "Players needed"},
		{key = "activates", type = "string", default = "", label = "Activates (spawner ids, or horde)"},
		{key = "actions", type = "string", default = "", label = "Actions (power=backup, lock=<door>, ...)"},
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
		{key = "on_ceiling", type = "bool", default = false, label = "Spawns on the ceiling (ceiling_cloud)"},
		{key = "on_dead", type = "string", default = "", label = "Fires trigger when its last enemy dies (bosses: max 1 or rate 0)"},
	]},
	clone_vat = {label = "Growth vat", color = Color(0.4, 1.0, 0.8), fields = []},
	kill_zone = {label = "Kill zone", color = Color(1.0, 0.2, 0.6), fields = [
		{key = "size", type = "vector3i", default = Vector3i(20, 30, 20), label = "Size (voxels)"},
	]},
	item = {label = "Item spot", color = Color(0.85, 0.6, 1.0), fields = [
		{key = "item", type = "string", default = "medkit", label = "Item (medkit, ammo_<type>, flask_<type>, keycard_<color>)"},
	]},
	# A mycelium node (Mycelium): nodes link up by themselves into roots and tendrils.
	mycelium = {label = "Mycelium node", color = Color(0.45, 0.95, 0.85), fields = [
		{key = "radius", type = "float", min = 1.0, max = 12.0, default = 4.0, label = "Radius (voxels)"},
		{key = "reach", type = "float", min = 0.0, max = 200.0, default = 40.0, label = "Links to nodes within (voxels)"},
		{key = "links", type = "int", min = 0, max = 8, default = 3, label = "Most links"},
		{key = "sag", type = "float", min = 0.0, max = 1.0, default = 0.0, label = "Sag (links droop)"},
		{key = "glow", type = "float", min = 0.0, max = 1.0, default = 0.3, label = "Glowing veins"},
		{key = "spread", type = "int", min = 0, max = 30, default = 0, label = "Film on its surface (voxels)"},
	]},
}

const ROOM_FIELDS := [
	{key = "id", type = "string"},
	{key = "name", type = "string", default = ""},
	{key = "thickness", type = "int", min = 1, max = 10, default = 3, label = "Lining thickness (voxels)"},
	{key = "from", type = "vector3i", label = "Inside from (voxels)"},
	{key = "to", type = "vector3i", label = "Inside to (voxels)"},
]

## "slot" is the pocket a sliding door goes into (made by the door, not the Opening tool).
const OPENING_TYPES := ["doorway", "window", "hole", "slot"]

const OPENING_FIELDS := [
	{key = "id", type = "string"},
	{key = "type", type = "enum", options = OPENING_TYPES, default = "doorway"},
	{key = "from", type = "vector3i", label = "From (voxels)"},
	{key = "to", type = "vector3i", label = "To (voxels)"},
]

## An opening in a build mode wall: measured along the wall (LevelBuild).
const WALL_OPENING_FIELDS := [
	{key = "id", type = "string"},
	{key = "type", type = "enum", options = OPENING_TYPES, default = "doorway"},
	{key = "along", type = "int", min = 0, max = 4096, default = 0, label = "From the wall's start (voxels)"},
	{key = "width", type = "int", min = 1, max = 4096, default = 12, label = "Width (voxels)"},
	{key = "sill", type = "int", min = 0, max = 1024, default = 0, label = "Sill (voxels off the floor)"},
	{key = "height", type = "int", min = 1, max = 1024, default = 22, label = "Height (voxels)"},
]

const WALL_FIELDS := [
	{key = "id", type = "string"},
	{key = "storey", type = "int", min = 0, max = 64, default = 0, label = "Storey"},
	{key = "thickness", type = "int", min = 1, max = 10, default = 2, label = "Thickness (voxels)"},
	{key = "height", type = "int", min = -1, max = 1024, default = -1, label = "Height (voxels, -1 = the storey's)"},
	{key = "material", type = "int", min = 1, max = 255, default = 1, label = "Material"},
	{key = "inner", type = "int", min = 0, max = 255, default = 0, label = "Left face material (0 = same)"},
]

const STOREY_FIELDS := [
	{key = "floor", type = "int", min = 1, max = 1024, default = 3, label = "Ground floor top (voxels)"},
	{key = "slab", type = "int", min = 1, max = 10, default = 3, label = "Floor / ceiling thickness (voxels)"},
]

## Placeholder asset prices for the payroll, by prop name prefix. Change freely, or per prop in the
## editor.
const ASSET_VALUES := {
	"fume_hood": 4000, "lab_bench": 2500, "shelf_lab": 1200, "spore_tank": 6000, "vending_machine": 1500,
	"fridge": 900, "desk": 600, "counter": 1100, "water_cooler": 200, "whiteboard": 150, "corkboard": 40,
	"couch": 500, "locker": 250, "table": 300, "chair": 50, "stool": 40, "bench": 120, "shelf_storage": 300,
	"crate": 30, "barrel": 60, "trash_can": 20, "grow_bed": 800, "plank_stack": 25, "sandbags": 30,
	"terminal": 2000, "cabinet": 300, "drawer_desk": 600, "medkit_station": 400, "ammo_bench": 800,
	"generator": 20000, "glass_case": 150, "vent_grate": 20, "vent_duct": 80,
	"specimen_case": 25000, "vial_cabinet": 1800, "specimen_jar": 350, "grow_bed_shrooms": 1400, "lab_table_gear": 3200,
	"shroom_pot": 90, "clone_vat": 12000,
}


static func default_value(prop_name: String) -> int:
	return _by_prefix(PropCatalog.merged("VALUES", ASSET_VALUES), prop_name, 100) # Plus the prop packs'.


static func default_use(prop_name: String) -> String:
	return _by_prefix(PropCatalog.merged("USES", DEFAULT_USES), prop_name, "none") # Plus the prop packs'.


static func _by_prefix(table: Dictionary, prop_name: String, fallback: Variant) -> Variant:
	var best := ""
	for prefix: String in table:
		if prop_name.begins_with(prefix) and prefix.length() > best.length():
			best = prefix
	return table.get(best, fallback)


static func new_prop(prop_name: String, origin: Vector3i, facing: int) -> Dictionary:
	var prop := {kind = "prop", name = prop_name, origin = origin, facing = facing, value = default_value(prop_name)}
	fill_defaults(prop)
	# The prop packs' per-name field defaults (a vending machine's price and snack, ...).
	prop.merge(_by_prefix(PropCatalog.merged("FIELDS", {}), prop_name, {}), true)
	if PropCatalog.mount_of(prop_name) == "door":
		prop.door = true
		prop.door_speed = 0.8 if prop_name.contains("blast") else 2.5
	return prop


## A room around the inside box [from, to).
static func new_room(from: Vector3i, to: Vector3i, floor: int, wall: int, ceiling: int, thickness: int, order: int) -> Dictionary:
	return {kind = "room", name = "", from = from.min(to), to = from.max(to), floor = floor, wall = wall, ceiling = ceiling,
			thickness = thickness, order = order}


static func new_opening(from: Vector3i, to: Vector3i, room: String, type := "doorway", door := "") -> Dictionary:
	return {kind = "opening", type = type, from = from.min(to), to = from.max(to), room = room, door = door, wall = ""}


## An opening in a build mode wall (LevelBuild): along the wall from its start, off its floor.
static func new_wall_opening(wall: String, along: int, width: int, sill: int, height: int, type := "doorway") -> Dictionary:
	return {kind = "opening", type = type, wall = wall, along = along, width = width, sill = sill, height = height,
			from = Vector3i.ZERO, to = Vector3i.ZERO, room = "", door = ""}


## Rooms, openings and build mode's pieces: changed through structure edits.
static func is_structure(object: Dictionary) -> bool:
	return object.get("kind") in ["room", "opening", "wall", "floor", "ceiling", "storeys"]


## A prop that's a door (it cuts its own opening).
static func is_door(object: Dictionary) -> bool:
	return object.get("kind") == "prop" and object.get("door", false)


## A room's inside plus its lining.
static func room_outer(room: Dictionary) -> AABB:
	var t := Vector3.ONE * int(room.thickness)
	return AABB(Vector3(room.from) - t, Vector3(room.to - room.from) + t * 2.0)


static func new_marker(type: String, position: Vector3, yaw := 0.0) -> Dictionary:
	var marker := {kind = "marker", type = type, position = position, yaw = yaw}
	for field: Dictionary in MARKERS[type].fields:
		marker[field.key] = field.default
	return marker


## Fills in fields an object is missing (level files saved before the field existed) with defaults.
static func fill_defaults(object: Dictionary) -> void:
	var fields: Array
	if object.get("kind") == "prop":
		fields = PROP_FIELDS
		if not object.has("use"):
			object.use = default_use(str(object.get("name", "")))
	elif object.get("kind") == "marker" and MARKERS.has(object.get("type")):
		fields = MARKERS[object.type].fields
	elif object.get("kind") == "room":
		fields = ROOM_FIELDS
		for key in ["floor", "wall", "ceiling", "order"]:
			if object.get(key) is float:
				object[key] = int(object[key])
	elif object.get("kind") == "opening":
		fields = OPENING_FIELDS
		object.room = str(object.get("room", ""))
		object.door = str(object.get("door", ""))
		object.wall = str(object.get("wall", ""))
		if object.wall != "":
			fields = WALL_OPENING_FIELDS
	elif object.get("kind") == "wall":
		fields = WALL_FIELDS
		if object.has("base"):
			object.base = int(object.base) # A rock level wall's floor (LevelBuild).
	elif object.get("kind") == "storeys":
		fields = STOREY_FIELDS
		object.heights = object.get("heights", []).map(func(h: Variant) -> int: return int(h))
	elif object.get("kind") in ["floor", "ceiling"]:
		object.storey = int(object.get("storey", 0))
		if object.has("y"):
			object.y = int(object.y) # A rock level floor's or ceiling's plane (LevelBuild).
		object.shapes = object.get("shapes", []).map(func(s: Array) -> Array: return s.map(func(v: Variant) -> int: return int(v)))
	for field: Dictionary in fields:
		if not field.has("default"):
			continue
		if not object.has(field.key):
			object[field.key] = field.default
		elif field.type == "int" and object[field.key] is float:
			object[field.key] = int(object[field.key]) # JSON numbers come back as floats.


## Inspector fields for an object.
static func fields_for(object: Dictionary) -> Array:
	if object.kind == "prop":
		return PROP_FIELDS
	if object.kind == "room":
		return ROOM_FIELDS
	if object.kind == "opening":
		return WALL_OPENING_FIELDS if str(object.get("wall", "")) != "" else OPENING_FIELDS
	if object.kind == "wall":
		return WALL_FIELDS
	if object.kind == "storeys":
		return STOREY_FIELDS
	if object.kind in ["floor", "ceiling"]:
		return []
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
	if object.kind == "prop":
		return prop_box(object)
	if object.has("from") and object.has("to"):
		return AABB(Vector3(object.from), Vector3(object.to - object.from))
	if is_structure(object):
		return AABB() # Build mode pieces: LevelBuild.bounds, which needs the storeys.
	return marker_box(object)
