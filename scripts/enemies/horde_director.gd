class_name HordeDirector
extends Node
## Host: decides when and where enemies spawn, from the level's horde spawner markers (see
## LevelSchema.MARKERS.horde: kinds, rate, max_alive, active, radius). Runs while in play.
##
## States:
##   calm    active spawners trickle enemies in, each up to its max_alive
##   horde   start_horde(count): a burst from the spawners nearest the players (ignoring
##           max_alive), back to calm once the burst is dead
##   finale  finale(duration): every spawner on, a ramping horde, finale_survived when the timer
##           runs out (a stub; phase 6 adds power, the countdown and failing)
## The trickle keeps going in every state.
##
## Triggers: a trigger marker's `activates` field (comma-separated) turns on spawners by id, or
## starts a horde with "horde". Prop triggers (a terminal's or the generator's `on_use`) can also name
## a spawner or "horde" directly. The generator calls finale(its finale_seconds) itself.

signal state_changed(state: String)
## The finale timer ran out with someone still standing.
signal finale_survived

@export var lab: Lab
@export var enemies: EnemyManager
## Enemies in a horde started by a trigger.
@export var horde_size := 12
## How many of the nearest spawners a horde comes from.
@export var horde_spawners := 2
## Horde spawns per second, so a burst doesn't all land on one frame.
@export var burst_rate := 6.0
## A horde ends after this many seconds even if some of it is still alive.
@export var horde_timeout := 90.0
## Finale spawns per second at the start and at the end of the timer.
@export var finale_rate_start := 0.4
@export var finale_rate_end := 2.0

var state := "calm"
var running := false
## id -> {object, active: bool, budget: float (spawns owed), alive: Array[int] (enemy ids)}
var spawners := {}

## Spawner ids, one entry per horde enemy still to spawn.
var _queue: Array[String] = []
var _burst_timer := 0.0
var _horde_ids: Array[int] = []
var _horde_time := 0.0
var _finale_time := 0.0
var _finale_duration := 0.0
var _finale_budget := 0.0


func _ready() -> void:
	lab.mode_changed.connect(func(mode: String) -> void:
		if mode == "play":
			start()
		else:
			stop())
	lab.play.triggered.connect(_on_triggered)


## Host, when play begins: reads the spawners from the level.
func start() -> void:
	if not multiplayer.is_server() or running:
		return
	running = true
	spawners.clear()
	_queue.clear()
	_horde_ids.clear()
	for object: Dictionary in lab.level.objects.values():
		if object.kind == "marker" and object.type == "horde":
			spawners[object.id] = {object = object, active = bool(object.get("active", true)), budget = 0.0, alive = []}
	_set_state("calm")


func stop() -> void:
	running = false
	spawners.clear()
	_queue.clear()
	_horde_ids.clear()
	state = "calm"


## Host (story scripts, triggers): turns a spawner's trickle on or off.
func set_spawner_active(id: String, on: bool) -> void:
	if spawners.has(id):
		spawners[id].active = on
		spawners[id].budget = 0.0


## Host: a burst of count enemies from the spawners nearest the players.
func start_horde(count: int) -> void:
	if not running or spawners.is_empty():
		return
	var nearest := _spawners_by_distance()
	var sources := nearest.slice(0, maxi(horde_spawners, 1))
	for i in count:
		_queue.append(sources[i % sources.size()])
	_horde_time = 0.0
	if state != "finale":
		_set_state("horde")


## Host: the generator finale (stub). Every spawner turns on and a horde ramps up for duration
## seconds; then finale_survived.
func finale(duration: float) -> void:
	if not running:
		return
	for id: String in spawners:
		spawners[id].active = true
	_finale_time = 0.0
	_finale_duration = maxf(duration, 0.1)
	_finale_budget = 0.0
	_set_state("finale")


func _set_state(new_state: String) -> void:
	state = new_state
	state_changed.emit(state)


## A trigger fired: its `activates` list runs. Terminals and the generator fire their `on_use` id,
## which can name a trigger marker (its list runs), a spawner directly, or "horde".
func _on_triggered(id: String, _peer_id: int) -> void:
	if id == "horde":
		start_horde(horde_size)
		return
	if spawners.has(id):
		set_spawner_active(id, true)
		return
	var object: Dictionary = lab.level.objects.get(id, {})
	for part in str(object.get("activates", "")).split(",", false):
		var target := part.strip_edges()
		if target == "horde":
			start_horde(horde_size)
		elif spawners.has(target):
			set_spawner_active(target, true)
		elif target != "":
			push_warning("trigger %s activates '%s', which isn't a spawner" % [id, target])


func _physics_process(delta: float) -> void:
	if not running or not enemies.simulating:
		return
	for id: String in spawners:
		var spawner: Dictionary = spawners[id]
		spawner.alive = spawner.alive.filter(func(e: int) -> bool: return enemies.enemies.has(e))
		_trickle(id, spawner, delta)
	_horde_ids.assign(_horde_ids.filter(func(e: int) -> bool: return enemies.enemies.has(e)))

	_burst_timer -= delta
	while _burst_timer <= 0.0 and not _queue.is_empty():
		_burst_timer += 1.0 / maxf(burst_rate, 0.1)
		var enemy := _spawn_from(_queue.pop_front())
		if enemy:
			_horde_ids.append(enemy.id)
	if _queue.is_empty():
		_burst_timer = maxf(_burst_timer, 0.0)

	match state:
		"horde":
			_horde_time += delta
			if _queue.is_empty() and (_horde_ids.is_empty() or _horde_time > horde_timeout):
				_set_state("calm")
		"finale":
			_finale_time += delta
			var ramp := clampf(_finale_time / _finale_duration, 0.0, 1.0)
			_finale_budget += lerpf(finale_rate_start, finale_rate_end, ramp) * delta
			if _finale_budget >= 1.0:
				_finale_budget -= 1.0
				var nearest := _spawners_by_distance()
				if not nearest.is_empty():
					_queue.append(nearest[randi() % mini(nearest.size(), maxi(horde_spawners, 1))])
			if _finale_time >= _finale_duration:
				_queue.clear()
				_set_state("calm")
				finale_survived.emit()


## Calm spawning: rate per minute while active, never more than max_alive of its own at once.
func _trickle(id: String, spawner: Dictionary, delta: float) -> void:
	var object: Dictionary = spawner.object
	var rate := float(object.get("rate", 6.0))
	if not spawner.active or rate <= 0.0:
		return
	spawner.budget = minf(spawner.budget + rate / 60.0 * delta, 1.0)
	if spawner.budget < 1.0 or spawner.alive.size() >= int(object.get("max_alive", 4)):
		return
	spawner.budget -= 1.0
	_spawn_from(id)


## Spawns one enemy at a spawner: a random kind from its list, somewhere on the floor within its
## radius. Counts it against the spawner.
func _spawn_from(id: String) -> Enemy:
	var spawner: Dictionary = spawners.get(id, {})
	if spawner.is_empty():
		return null
	var object: Dictionary = spawner.object
	var kinds := Array(str(object.get("kinds", "basic")).split(",", false)).map(func(k: String) -> String: return k.strip_edges())
	var kind: String = kinds.pick_random() if not kinds.is_empty() else "basic"
	var enemy := enemies.spawn(kind, _spawn_point(object))
	if enemy:
		spawner.alive.append(enemy.id)
	return enemy


## A clear floor spot within the marker's radius, else the marker itself.
func _spawn_point(object: Dictionary) -> Vector3:
	var world := lab.world
	var base := lab.view.to_world(object.position)
	var radius := float(object.get("radius", 1.5))
	for attempt in 8:
		var angle := randf() * TAU
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * radius * sqrt(randf())
		var probe := base + offset + Vector3.UP * 1.0
		var down: Dictionary = world.raycast(probe, Vector3.DOWN, 3.0)
		if not down.hit or down.distance < 0.05:
			continue
		var feet: Vector3 = down.position
		if not world.box_overlaps_solid(AABB(feet + Vector3(-0.35, 0.02, -0.35), Vector3(0.7, 1.2, 0.7))):
			return feet
	return base + Vector3.UP * 0.05


## Spawner ids, nearest to any target player first.
func _spawners_by_distance() -> Array[String]:
	var ids: Array[String] = []
	var distance := {}
	for id: String in spawners:
		var at := lab.view.to_world(spawners[id].object.position)
		distance[id] = enemies.nearest_player_distance(at)
		ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool: return distance[a] < distance[b])
	return ids
