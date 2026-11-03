class_name HordeDirector
extends Node
## Host: decides when and where enemies spawn, from the level's horde spawner markers (see
## LevelSchema.MARKERS.horde: kinds, rate, max_alive, active, radius). Runs while in play.
##
## States:
##   calm    active spawners trickle enemies in, each up to its max_alive
##   horde   start_horde(count): a burst from the spawners nearest the players (ignoring
##           max_alive), back to calm once the burst is dead
##   finale  finale(duration): the generator finale (see below)
## The trickle keeps going in every state.
##
## Triggers: a trigger marker's `activates` field (comma-separated) turns on spawners by id, or
## starts a horde with "horde". Prop triggers (a terminal's or the generator's `on_use`) can also name
## a spawner or "horde" directly. The generator calls finale(its finale_seconds) itself. A trigger
## marker's `actions` (LevelPlay) can also turn spawners on and off (`on=` / `off=`).
##
## Hordes come from the spawners nearest the players by walking distance (the flow field), so a
## spawner on the floor above never counts as near through the slab; spawners with no path go
## last.
##
## A spawner's `on_dead` names a trigger id fired (once per play) when its last enemy dies: for
## placed bosses, so it only fires when the spawner can't just spawn another, i.e. it is inactive,
## its rate is 0 or its max_alive is 1.
##
## Player count: the level's rates and caps are tuned for two players; with scale_per_player > 0
## they scale by (1 - s + s x players) / (1 + s), so one player gets less and four get more.
##
## Finale: every spawner turns on, trickle rates ramp to finale_rate_multiplier x over the timer, a
## burst fires every finale_burst_interval seconds (horde_size, x finale_burst_growth each time) and
## max_alive caps are finale_alive_multiplier x. At zero: finale_survived (trigger id
## "finale_survived"), spawners go back as they were, enemies keep living. If every player is dead at
## once: finale_failed (trigger id "finale_failed"), spawners restored, every enemy despawned, power
## back to backup and the generator usable again. The timer is replicated once a second so every HUD
## counts down together; finale_event tells every peer when it started and how it ended.

signal state_changed(state: String)
## The finale timer ran out with someone still standing.
signal finale_survived
## Everyone died during the finale.
signal finale_failed
## Every peer: "started", "survived" or "failed" (HUD banners, stings).
signal finale_event(kind: String)

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
## Finale balance: the trickle rate reaches this multiple of the spawner's own rate by the end.
@export var finale_rate_multiplier := 4.0
## Seconds between finale bursts.
@export var finale_burst_interval := 20.0
## Each finale burst is this much bigger than the last (the first is horde_size).
@export var finale_burst_growth := 1.5
## max_alive caps are multiplied by this during the finale.
@export var finale_alive_multiplier := 2.0
## How much each player beyond the second adds to rates and caps (0: no scaling). See the top.
@export var scale_per_player := 0.25

var state := "calm"
var running := false
## id -> {object, active: bool, budget: float (spawns owed), alive: Array[int] (enemy ids),
## rate_mult, alive_mult (finale scaling), spawned (ever), dead_fired (on_dead went)}
var spawners := {}
## Every peer: the finale is running, and how many seconds are left (replicated each second).
var finale_active := false
var finale_left := 0.0

## Spawner ids, one entry per horde enemy still to spawn.
var _queue: Array[String] = []
var _burst_timer := 0.0
var _horde_ids: Array[int] = []
var _horde_time := 0.0
var _finale_time := 0.0
var _finale_duration := 0.0
var _finale_burst_timer := 0.0
var _finale_bursts := 0
var _finale_sync_timer := 0.0
## spawner id -> active before the finale.
var _saved_active := {}


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
			spawners[object.id] = {object = object, active = bool(object.get("active", true)), budget = 0.0, alive = [],
					rate_mult = 1.0, alive_mult = 1.0, spawned = false, dead_fired = false}
	_set_state("calm")


func stop() -> void:
	running = false
	spawners.clear()
	_queue.clear()
	_horde_ids.clear()
	_saved_active.clear()
	finale_active = false
	finale_left = 0.0
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


## Host: the generator finale. Power is restored, every spawner turns on and the horde ramps up for
## duration seconds; then finale_survived (or finale_failed if everyone dies first).
func finale(duration: float) -> void:
	if not running or finale_active:
		return
	lab.play.set_power("restored")
	_saved_active.clear()
	for id: String in spawners:
		_saved_active[id] = spawners[id].active
		spawners[id].active = true
		spawners[id].alive_mult = finale_alive_multiplier
	_finale_time = 0.0
	_finale_duration = maxf(duration, 0.1)
	_finale_burst_timer = finale_burst_interval
	_finale_bursts = 0
	_finale_sync_timer = 1.0
	finale_active = true
	finale_left = _finale_duration
	_set_state("finale")
	_announce("started")


## Host: the finale is over ("survived" or "failed"); spawners go back to what they were.
func _end_finale(outcome: String) -> void:
	finale_active = false
	finale_left = 0.0
	_queue.clear()
	for id: String in spawners:
		spawners[id].active = _saved_active.get(id, spawners[id].active)
		spawners[id].alive_mult = 1.0
		spawners[id].rate_mult = 1.0
		spawners[id].budget = 0.0
	_saved_active.clear()
	_set_state("calm")
	if outcome == "survived":
		lab.notify("Power restored. You survived the shift.")
		_announce("survived")
		finale_survived.emit()
		lab.play.triggered.emit("finale_survived", 1)
		return
	for id: int in enemies.enemies.keys():
		enemies.despawn(id)
	for spawner: Dictionary in spawners.values():
		spawner.alive.clear()
	_horde_ids.clear()
	lab.notify("Everyone died. The company restarts the shift from the last clone.")
	lab.play.set_power("backup")
	for id: String in lab.level.objects:
		var object: Dictionary = lab.level.objects[id]
		if object.kind == "prop" and object.get("use") == "generator":
			lab.play.reset_prop(id)
	_announce("failed")
	finale_failed.emit()
	lab.play.triggered.emit("finale_failed", 1)


## Host: tells every peer (and this one) about the finale's start, end or just the timer ("").
func _announce(kind: String) -> void:
	for peer_id in lab.peers_in_level:
		if peer_id != 1:
			_finale_net.rpc_id(peer_id, finale_active, finale_left, kind)
	_apply_finale(finale_active, finale_left, kind)


@rpc("authority", "reliable")
func _finale_net(active: bool, left: float, kind: String) -> void:
	_apply_finale(active, left, kind)


func _apply_finale(active: bool, left: float, kind: String) -> void:
	finale_active = active
	finale_left = left
	if kind == "":
		return
	if kind == "started":
		Sfx.play("alarm")
	Sfx.play("sting_finale")
	finale_event.emit(kind)


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


## Peers count the replicated timer down between updates.
func _process(delta: float) -> void:
	if finale_active and not multiplayer.is_server():
		finale_left = maxf(finale_left - delta, 0.0)


func _physics_process(delta: float) -> void:
	if not running or not enemies.simulating:
		return
	for id: String in spawners:
		var spawner: Dictionary = spawners[id]
		var had: bool = not spawner.alive.is_empty()
		spawner.alive = spawner.alive.filter(func(e: int) -> bool: return enemies.enemies.has(e))
		if had and spawner.alive.is_empty():
			_on_spawner_empty(id, spawner)
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
			_tick_finale(delta)


## Host, each physics frame of the finale: ramp, bursts, replication, wipe and end checks.
func _tick_finale(delta: float) -> void:
	_finale_time += delta
	finale_left = maxf(_finale_duration - _finale_time, 0.0)
	var ramp := clampf(_finale_time / _finale_duration, 0.0, 1.0)
	for spawner: Dictionary in spawners.values():
		spawner.rate_mult = lerpf(1.0, finale_rate_multiplier, ramp)
	_finale_burst_timer -= delta
	if _finale_burst_timer <= 0.0:
		_finale_burst_timer += finale_burst_interval
		start_horde(roundi(horde_size * pow(finale_burst_growth, _finale_bursts)))
		_finale_bursts += 1
	_finale_sync_timer -= delta
	if _finale_sync_timer <= 0.0:
		_finale_sync_timer += 1.0
		_announce("")
	if _everyone_dead():
		_end_finale("failed")
	elif _finale_time >= _finale_duration:
		_end_finale("survived")


## Host: a spawner's last enemy went. Fires its `on_dead` trigger once if it's a placed boss
## (inactive, rate 0 or max_alive 1), not a trickle that will just spawn another.
func _on_spawner_empty(id: String, spawner: Dictionary) -> void:
	var object: Dictionary = spawner.object
	var target := str(object.get("on_dead", "")).strip_edges()
	if target == "" or spawner.dead_fired or not spawner.spawned:
		return
	var boss: bool = not spawner.active or float(object.get("rate", 6.0)) <= 0.0 or int(object.get("max_alive", 4)) <= 1
	if not boss:
		return
	spawner.dead_fired = true
	lab.play.triggered.emit(target, 1)


## Rates and caps are tuned for two players; this is the multiplier for the players in the level.
func player_factor() -> float:
	if scale_per_player <= 0.0:
		return 1.0
	var count := maxi(lab.players.size(), 1)
	return (1.0 - scale_per_player + scale_per_player * count) / (1.0 + scale_per_player)


## A spawner's cap right now: max_alive x finale multiplier x player factor, never below 1 when
## it has any.
func alive_cap(spawner: Dictionary) -> int:
	var base := int(spawner.object.get("max_alive", 4))
	if base <= 0:
		return 0
	return maxi(1, roundi(base * float(spawner.alive_mult) * player_factor()))


## Players are in the level and none of them is alive.
func _everyone_dead() -> bool:
	var any := false
	for player: Player in lab.players.values():
		if is_instance_valid(player):
			any = true
			if not player.is_dead:
				return false
	return any


## Calm spawning: rate per minute while active, never more than max_alive of its own at once.
func _trickle(id: String, spawner: Dictionary, delta: float) -> void:
	var object: Dictionary = spawner.object
	var rate: float = float(object.get("rate", 6.0)) * float(spawner.rate_mult) * player_factor()
	if not spawner.active or rate <= 0.0:
		return
	spawner.budget = minf(spawner.budget + rate / 60.0 * delta, 1.0)
	if spawner.budget < 1.0 or spawner.alive.size() >= alive_cap(spawner):
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
		spawner.spawned = true
	return enemy


## A clear floor spot within the marker's radius, else the marker itself.
func _spawn_point(object: Dictionary) -> Vector3:
	var world := lab.world
	var base := lab.view.to_world(object.position)
	if object.get("on_ceiling", false):
		# Ceiling spawners hang their enemies from the nearest ceiling voxel above the marker.
		var ceiling: Dictionary = enemies.ceiling_point(base)
		if not ceiling.is_empty():
			return ceiling.position - Vector3.UP * 0.5
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


## Spawner ids, nearest to any target player first: by walking distance (the flow field, which
## reaches FLOW_RANGE m around the players), unreached ones last, straight-line as the tie-break.
func _spawners_by_distance() -> Array[String]:
	var ids: Array[String] = []
	var walk := {}
	var straight := {}
	enemies.refresh_flow()
	for id: String in spawners:
		var at := lab.view.to_world(spawners[id].object.position)
		straight[id] = enemies.nearest_player_distance(at)
		var flow: Dictionary = lab.world.get_flow(at + Vector3.UP * 0.05)
		walk[id] = float(flow.distance) if flow.get("valid", false) else INF
		ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		if walk[a] != walk[b]:
			return walk[a] < walk[b]
		return straight[a] < straight[b])
	return ids
