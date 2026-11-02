class_name ShroomManager
extends Node3D
## Owns every planted spore and grown shroom: planting, night growth, the shared flow field toward
## the player, weapon hit tests, and harvest rewards.

signal harvested(shroom: Shroom)

@export var world: VoxelWorld
@export var player: Player
@export var debris: VoxelDebris
@export var state: GameState
@export var harvest_reward := 15
@export var flow_interval := 0.4
@export var flow_range := 70.0
@export var min_spore_spacing := 0.7

var spores: Array[Spore] = []
var shrooms: Array[Shroom] = []

var _flow_timer := 0.0
var _stem_material := StandardMaterial3D.new()
var _cap_material := StandardMaterial3D.new()


func _ready() -> void:
	_stem_material.albedo_color = Color(0.85, 0.82, 0.74)
	_stem_material.roughness = 0.8
	_cap_material.albedo_color = Color(0.45, 0.22, 0.55)
	_cap_material.emission_enabled = true
	_cap_material.emission = Color(0.3, 1.0, 0.8)
	set_glow(0.0)


## 0 = daytime (dull), 1 = full night glow.
func set_glow(amount: float) -> void:
	_cap_material.emission_energy_multiplier = amount * 0.9
	_stem_material.emission_enabled = amount > 0.0
	_stem_material.emission = Color(0.2, 0.6, 0.5)
	_stem_material.emission_energy_multiplier = amount * 0.15


func can_plant(at: Vector3) -> bool:
	for spore in spores:
		if spore.global_position.distance_to(at) < min_spore_spacing:
			return false
	return true


func plant(at: Vector3) -> Spore:
	var spore := Spore.new()
	add_child(spore)
	spore.global_position = at
	spore.setup(_stem_material, _cap_material)
	spore.matured.connect(_on_spore_matured)
	spores.append(spore)
	return spore


## Night begins: every spore starts growing, staggered so they don't all burst at once.
func begin_growth(first_delay: float, spread: float) -> void:
	for spore in spores:
		spore.start_growing(first_delay + randf() * spread)


## Spores and shrooms still alive tonight.
func remaining() -> int:
	return spores.size() + shrooms.size()


## Removes everything left at dawn.
func clear_all() -> void:
	for spore in spores:
		spore.queue_free()
	for shroom in shrooms:
		shroom.queue_free()
	spores.clear()
	shrooms.clear()


func _physics_process(delta: float) -> void:
	if shrooms.is_empty():
		return
	_flow_timer -= delta
	if _flow_timer <= 0.0:
		_flow_timer = flow_interval
		world.update_flow_field(player.global_position, flow_range)


func _on_spore_matured(spore: Spore) -> void:
	spores.erase(spore)
	var shroom := Shroom.new()
	shroom.world = world
	shroom.player = player
	shroom.manager = self
	add_child(shroom)
	shroom.global_position = spore.global_position
	shroom.setup(_stem_material, _cap_material)
	shroom.died.connect(_on_shroom_died)
	shrooms.append(shroom)
	spore.queue_free()
	if shrooms.size() == 1:
		_flow_timer = 0.0 # Get a field before the first one starts moving.


func _on_shroom_died(shroom: Shroom) -> void:
	shrooms.erase(shroom)
	debris.burst(shroom.get_center(), Vector3.UP, {VoxelMaterials.GLOW: 120})
	if state:
		state.harvested += 1
		state.earn(harvest_reward)
	harvested.emit(shroom)


## Nearest shroom along a normalized ray within max_distance: {shroom, distance}, or {} on a miss.
func raycast(origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	var best := {}
	for shroom in shrooms:
		var t := shroom.hit_test(origin, direction)
		if t >= 0.0 and t <= max_distance and (best.is_empty() or t < best.distance):
			best = {shroom = shroom, distance = t}
	return best


## Damages every shroom near center, falling off with distance.
func damage_sphere(center: Vector3, radius: float, damage: float) -> void:
	for shroom: Shroom in shrooms.duplicate():
		var offset := shroom.get_center() - center
		var distance := offset.length()
		if distance < radius:
			var falloff := 1.0 - distance / radius
			shroom.take_damage(damage * falloff, offset.normalized() * 6.0 * falloff + Vector3.UP * 3.0 * falloff)


## Push away from nearby shrooms so a crowd spreads out instead of stacking.
func separation(shroom: Shroom) -> Vector3:
	var push := Vector3.ZERO
	for other in shrooms:
		if other == shroom:
			continue
		var offset := shroom.global_position - other.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance < 0.9 and distance > 0.001:
			push += offset / distance * (0.9 - distance) / 0.9
	return push
