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
## Dormant: a level whose `spawns_dormant` setting is true starts with the director dormant: nothing
## trickles and no horde starts whatever spawners triggers turn on (they stay on, and start once
## woken). The `wake` trigger action (the laboratory's outbreak) or the finale clears it, so a
## player who wanders into a side room before the story's outbreak meets nothing.
##
## Wake range: a spawner only trickles while the flow field (walking distance to the nearest living
## player, EnemyManager.refresh_flow) reaches it within wake_range meters, so a floor above or below
## through a slab is far away however close it is in a straight line. Only when the field is empty
## (no living player on a floor) does the straight-line distance stand in. Hordes and the finale's
## own spawners ignore it.
##
## Triggers: a trigger marker's `activates` field (comma-separated) turns on spawners by id, or
## starts a horde with "horde". Prop triggers (a terminal's or the generator's `on_use`) can also name
## a spawner or "horde" directly. The generator calls finale(its finale_seconds) itself. A trigger
## marker's `actions` (LevelPlay) can also turn spawners on and off (`on=` / `off=`). Turning one off
## also sinks its living enemies back into the floor (EnemyManager.sink: no death, no drops), so a
## sealed floor goes quiet.
##
## Hordes come from the spawners nearest the players by walking distance (the flow field), so a
## spawner on the floor above never counts as near through the slab; spawners with no path go
## last.
##
## A spawner's `on_dead` names a trigger id fired (once per play) when its last enemy dies: for
## placed bosses, so it only fires when the spawner can't just spawn another, i.e. it is inactive,
## its rate is 0 or its max_alive is 1.
##
## Fair spawns: an enemy never appears within spawn_safe_distance of a living player or in any
## player's view (within spawn_view_angle of the camera's forward and in line of sight); a spawner
## with no such spot within its radius (or twice it) waits SPAWN_RETRY and tries again, keeping its
## budget, and horde spawns go back in the queue. Spawned enemies emerge (Enemy.begin_emerge): out
## of the floor, or out of the ceiling for on_ceiling spawners.
##
## Player count: the level's rates and caps are tuned for two players; with scale_per_player > 0
## they scale by (1 - s + s x players) / (1 + s), so one player gets less and four get more.
##
## Finale: its spawners are the ones within finale_range_factor x wake_range of walking distance
## from the players when it starts (straight-line if the flow field is empty; every spawner if
## wake_range is 0), plus any whose id starts with FINALE_PREFIX wherever they are. Those turn on,
## ignore the wake range, their trickle rates ramp to finale_rate_multiplier x over the timer and
## their max_alive caps are finale_alive_multiplier x; every other spawner stays as it was (and keeps
## to its wake range). A burst fires every finale_burst_interval seconds (horde_size, x
## finale_burst_growth each time) from the spawners nearest the players. At zero: finale_survived
## (trigger id "finale_survived"), the finale's spawners go back as they were, enemies keep living.
## If every player is dead at once: finale_failed (trigger id "finale_failed"), spawners restored,
## every enemy despawned, power back to backup and the generator usable again. The timer is
## replicated once a second so every HUD counts down together; finale_event tells every peer when
## it started and how it ended.

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
## A spawner only trickles while a living player is within this many meters of walking of it (the
## flow field; straight line only when the field is empty). The finale's spawners ignore it. 0
## disables. Keeps far floors quiet until the party gets there.
@export var wake_range := 40.0
## The finale turns on the spawners within this many wake ranges of walking from the players.
@export var finale_range_factor := 2.0
## Fair spawns (_spawn_point, is_fair): no enemy appears within this many meters of a living
## player, or where a player would see it appear (within this many degrees of their view and in
## line of sight).
@export var spawn_safe_distance := 6.0
@export var spawn_view_angle := 55.0

## Random spots tried within a spawner's radius (and as many again within twice it).
const SPAWN_TRIES := 8
## Seconds before a spawner with no fair spot looks again (its budget kept).
const SPAWN_RETRY := 0.25
## Spawners with ids starting with this are always in the finale, however far (the generator hall's).
const FINALE_PREFIX := "s_m4_gen_"

var state := "calm"
## Host: nothing spawns while true (the level's `spawns_dormant` setting, cleared by wake()).
var dormant := false
## Host: spawns put off for want of a fair spot (for tests and tuning).
var deferred_spawns := 0
var running := false
## id -> {object, active: bool, budget: float (spawns owed), alive: Array[int] (enemy ids),
## rate_mult, alive_mult (finale scaling), finale (one of the finale's spawners right now),
## spawned (ever), dead_fired (on_dead went)}
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
	dormant = bool(lab.level.settings.get("spawns_dormant", false))
	spawners.clear()
	_queue.clear()
	_horde_ids.clear()
	for object: Dictionary in lab.level.objects.values():
		if object.kind == "marker" and object.type == "horde":
			spawners[object.id] = {object = object, active = bool(object.get("active", true)), budget = 0.0, alive = [],
					rate_mult = 1.0, alive_mult = 1.0, finale = false, spawned = false, dead_fired = false}
	_set_state("calm")


func stop() -> void:
	running = false
	dormant = false
	spawners.clear()
	_queue.clear()
	_horde_ids.clear()
	_saved_active.clear()
	finale_active = false
	finale_left = 0.0
	state = "calm"


## Host: what a shift save keeps (docs/shift-save.md; not `state`, which is the state name):
## {dormant, spawners: {id: {active, spawned, dead_fired}}}. Enemies alive now are not kept; a resume
## starts the spawners fresh from this.
func save_state() -> Dictionary:
	var out := {}
	for id: String in spawners:
		var spawner: Dictionary = spawners[id]
		out[id] = {active = bool(spawner.active), spawned = bool(spawner.spawned), dead_fired = bool(spawner.dead_fired)}
	return {dormant = dormant, spawners = out}


## Host, resuming a shift after start(): dormant and each saved spawner's active / spawned /
## dead_fired. A boss spawner (one with `on_dead`) whose boss was alive at the save gets spawned
## cleared, so it can grow its boss again: the enemy wasn't saved, and on_dead must still be able to
## fire.
func restore(saved: Dictionary) -> void:
	if not multiplayer.is_server() or not running:
		return
	dormant = bool(saved.get("dormant", dormant))
	var states: Dictionary = saved.get("spawners", {})
	for id: String in states:
		if not spawners.has(id):
			continue
		var spawner: Dictionary = spawners[id]
		var entry: Dictionary = states[id]
		spawner.active = bool(entry.get("active", spawner.active))
		spawner.dead_fired = bool(entry.get("dead_fired", false))
		var boss := str(spawner.object.get("on_dead", "")).strip_edges() != ""
		spawner.spawned = bool(entry.get("spawned", false)) and not (boss and not spawner.dead_fired)
		spawner.budget = 0.0
		spawner.alive = []


## Host (story scripts, triggers): turns a spawner's trickle on or off. Off also sinks its living
## enemies (EnemyManager.sink: gone without a death, so no drops and no on_dead) and drops its
## queued horde spawns. During the finale the change also stands after it (what the finale
## restores).
func set_spawner_active(id: String, on: bool) -> void:
	if not spawners.has(id):
		return
	var spawner: Dictionary = spawners[id]
	spawner.active = on
	spawner.budget = 0.0
	if finale_active and _saved_active.has(id):
		_saved_active[id] = on
	if on:
		return
	# Ones already killed this frame stay listed, so their spawner still notices it emptied (on_dead).
	var killed: Array = []
	for enemy_id: int in spawner.alive:
		if enemies.enemies.has(enemy_id):
			enemies.sink(enemy_id)
		else:
			killed.append(enemy_id)
	spawner.alive = killed
	_queue.assign(_queue.filter(func(source: String) -> bool: return source != id))


## Host (the `wake` trigger action): spawning begins; active spawners trickle from here on.
func wake() -> void:
	dormant = false


## Host: a burst of count enemies from the spawners nearest the players. Nothing while dormant.
func start_horde(count: int) -> void:
	if not running or dormant or spawners.is_empty():
		return
	var nearest := _spawners_by_distance()
	var sources := nearest.slice(0, maxi(horde_spawners, 1))
	for i in count:
		_queue.append(sources[i % sources.size()])
	_horde_time = 0.0
	if state != "finale":
		_set_state("horde")


## Host: the generator finale. Power is restored, the spawners near the players (and the
## FINALE_PREFIX ones) turn on and the horde ramps up for duration seconds; then finale_survived
## (or finale_failed if everyone dies first). See the top for which spawners take part.
func finale(duration: float) -> void:
	if not running or finale_active:
		return
	dormant = false
	lab.play.set_power("restored")
	_saved_active.clear()
	enemies.refresh_flow()
	var reach := wake_range * finale_range_factor
	for id: String in spawners:
		var spawner: Dictionary = spawners[id]
		var near := wake_range <= 0.0 or walk_distance(spawner.object) <= reach
		spawner.finale = near or id.begins_with(FINALE_PREFIX)
		if not spawner.finale:
			continue
		_saved_active[id] = spawner.active
		spawner.active = true
		spawner.alive_mult = finale_alive_multiplier
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
		var spawner: Dictionary = spawners[id]
		if not spawner.finale:
			continue
		spawner.finale = false
		spawner.active = _saved_active.get(id, spawner.active)
		spawner.alive_mult = 1.0
		spawner.rate_mult = 1.0
		spawner.budget = 0.0
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
		var source: String = _queue.pop_front()
		var enemy := _spawn_from(source)
		if enemy:
			_horde_ids.append(enemy.id)
		elif spawners.has(source) and spawners[source].get("deferred", false):
			# No fair spot there right now: back of the queue, tried again later.
			_queue.append(source)
			break
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
		if spawner.finale:
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
	if dormant or not spawner.active or rate <= 0.0:
		return
	if not spawner.finale and wake_range > 0.0 and walk_distance(object) > wake_range:
		return
	if float(spawner.get("retry", 0.0)) > 0.0:
		spawner.retry = float(spawner.retry) - delta
	spawner.budget = minf(spawner.budget + rate / 60.0 * delta, 1.0)
	if spawner.budget < 1.0 or spawner.alive.size() >= alive_cap(spawner) or float(spawner.get("retry", 0.0)) > 0.0:
		return
	if _spawn_from(id) == null and spawner.get("deferred", false):
		# No fair spot (every one near or in view of a player): keep the budget, look again soon.
		spawner.retry = SPAWN_RETRY
		return
	spawner.budget -= 1.0


## Spawns one enemy at a spawner: a random kind from its list, somewhere on the floor within its
## radius that is fair to the players (_spawn_point). It emerges out of the floor (or the ceiling,
## for on_ceiling spawners). Counts it against the spawner. Returns null when there's no fair spot
## (the spawner's `deferred` is then true, and deferred_spawns counts it) or the enemy cap is hit.
func _spawn_from(id: String) -> Enemy:
	var spawner: Dictionary = spawners.get(id, {})
	if spawner.is_empty():
		return null
	var object: Dictionary = spawner.object
	var point := _spawn_point(object)
	spawner.deferred = point.is_empty()
	if point.is_empty():
		deferred_spawns += 1
		return null
	var kinds := Array(str(object.get("kinds", "basic")).split(",", false)).map(func(k: String) -> String: return k.strip_edges())
	var kind: String = kinds.pick_random() if not kinds.is_empty() else "basic"
	var enemy := enemies.spawn(kind, point.position, randf() * TAU, point.emerge)
	if enemy:
		spawner.alive.append(enemy.id)
		spawner.spawned = true
	return enemy


## A fair spot for a spawner's next enemy: {position (feet; for ceiling spawners just under the
## ceiling), emerge (1 floor, -1 ceiling)}, or {} when there's none right now. Up to SPAWN_TRIES
## random spots within the marker's radius, then as many within twice it, then the marker itself;
## the first clear one that is_fair wins.
func _spawn_point(object: Dictionary) -> Dictionary:
	var base := lab.view.to_world(object.position)
	var ceiling_spawner: bool = object.get("on_ceiling", false)
	var radius := float(object.get("radius", 1.5))
	for attempt in SPAWN_TRIES * 2 + 1:
		var offset := Vector3.ZERO
		if attempt < SPAWN_TRIES * 2:
			var angle := randf() * TAU
			var reach := radius * (1.0 if attempt < SPAWN_TRIES else 2.0)
			offset = Vector3(cos(angle), 0.0, sin(angle)) * reach * sqrt(randf())
		var spot := _ceiling_spot(base + offset) if ceiling_spawner else _floor_spot(base + offset, attempt == SPAWN_TRIES * 2)
		if spot.is_empty():
			continue
		var body: Vector3 = spot.position + (Vector3.ZERO if ceiling_spawner else Vector3.UP * 0.6)
		if is_fair(spot.position, body):
			return spot
	return {}


## A clear floor spot under at (the marker itself, last: anywhere it stands), or {}.
func _floor_spot(at: Vector3, is_marker: bool) -> Dictionary:
	var world := lab.world
	var down: Dictionary = world.raycast(at + Vector3.UP * 1.0, Vector3.DOWN, 3.0)
	if down.hit and down.distance >= 0.05:
		var feet: Vector3 = down.position
		if not world.box_overlaps_solid(AABB(feet + Vector3(-0.35, 0.02, -0.35), Vector3(0.7, 1.2, 0.7))):
			return {position = feet, emerge = 1}
	if is_marker:
		return {position = at + Vector3.UP * 0.05, emerge = 1}
	return {}


## Under the nearest ceiling voxel above at (ceiling spawners hang their enemies there), or {}.
func _ceiling_spot(at: Vector3) -> Dictionary:
	var ceiling: Dictionary = enemies.ceiling_point(at)
	if ceiling.is_empty():
		return {}
	return {position = ceiling.position - Vector3.UP * 0.5, emerge = -1}


## Whether an enemy can appear with its feet at feet (body: its middle) without being unfair: no
## living player within spawn_safe_distance of it, and none who would see it appear (body within
## spawn_view_angle of their camera's forward and in line of sight, Combat.can_see).
func is_fair(feet: Vector3, body: Vector3) -> bool:
	var view_cos := cos(deg_to_rad(spawn_view_angle))
	for player: Player in enemies.targets():
		if player.global_position.distance_to(feet) < spawn_safe_distance:
			return false
		var camera: Camera3D = player.camera
		if camera == null or not camera.is_inside_tree():
			continue
		var eye := camera.global_position
		var to := body - eye
		if to.length() < 0.01:
			return false
		if (-camera.global_basis.z).dot(to.normalized()) > view_cos and Combat.can_see(lab.world, eye, body):
			return false
	return true


## Host: meters from a spawner marker to the nearest living player, for the wake range and the
## finale: walking distance by the flow field (INF where it doesn't reach), or the straight line
## when the field is empty. The marker's own spot is tried first, then four around it within its
## radius (up to a meter), in case the marker stands in a wall or a prop.
func walk_distance(object: Dictionary) -> float:
	var at := lab.view.to_world(object.position)
	if enemies.flow_reached <= 0:
		return enemies.nearest_player_distance(at)
	var reach := clampf(float(object.get("radius", 1.5)), 0.2, 1.0)
	var best := INF
	for offset: Vector3 in [Vector3.ZERO, Vector3.RIGHT * reach, Vector3.LEFT * reach, Vector3.FORWARD * reach, Vector3.BACK * reach]:
		var flow: Dictionary = lab.world.get_flow(at + offset + Vector3.UP * 0.05)
		if flow.get("valid", false):
			best = minf(best, float(flow.distance))
		if offset == Vector3.ZERO and best < INF:
			break
	return best


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
