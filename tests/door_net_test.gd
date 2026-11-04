extends SceneTree
## One side of the two-process door test; run both with `tools/net_test.sh door_net_test`.
##
## The host plays the waiting room and the client joins. The host unlocks and opens the admittance
## door; both check the door's voxels left the doorway and landed in its pocket, and that their door
## records agree (open, where it is). The client then closes it by request_use (its E), and both
## check again. Then the host moves the session to the laboratory (Net.change_level, the story's
## way) and, as soon as the client has the new world but before it has confirmed its entry, opens a
## door, so the client enters while it slides (a late joiner's view of a moving door). Last, the
## client signs in at the gatehouse terminal (unlocking the blast door) and opens the blast door by
## E, and both check it. Each step prints a HASH of the door's region, which must match.
##
## Game types are left untyped (see net_test.gd).

const PORT := 24713
const ADMIT := "d_admit"
const BLAST := "d_g_blast"
const SIGNIN := "term_g_signin"

var _failures := 0
var _port := PORT


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var role := "host"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
		elif arg.begins_with("--port="):
			_port = int(arg.trim_prefix("--port="))
	var net: Node = root.get_node("Net")
	if role == "host":
		await _host(net)
	else:
		await _client(net)
	print("%s: %s" % [role.to_upper(), "PASS" if _failures == 0 else "FAIL (%d)" % _failures])
	quit(1 if _failures > 0 else 0)


func _host(net: Node) -> void:
	net.player_name = "Host"
	_check("host starts", net.host(_port, "waiting_room", "play") == OK)
	var lab = await _wait_for_lab(null)
	if lab == null:
		return
	print("READY")
	if not await _wait_until(func() -> bool: return lab.peers_in_level.size() == 2, 120.0):
		_check("client entered the waiting room", false)
		return
	await _wait_seconds(1.0)
	lab.play.set_door_locked(ADMIT, false)
	lab.play.set_door(ADMIT, true)
	await _wait_until(func() -> bool: return not lab.play._doors[ADMIT].moving, 20.0)
	await _wait_seconds(0.5)
	_check_door(lab, ADMIT, true, "admit opened")
	# The client closes it (its E).
	_check("the client's E closes it", await _wait_until(func() -> bool: return not lab.play._doors[ADMIT].open and not lab.play._doors[ADMIT].moving, 30.0))
	await _wait_seconds(0.5)
	_check_door(lab, ADMIT, false, "admit closed by the client")
	await _wait_seconds(1.0)

	# The story's level change, and a door opened while the client is still entering.
	net.change_level("laboratory")
	var old = lab
	lab = await _wait_for_lab(old)
	if lab == null:
		return
	var moving := _moving_door(lab)
	if not await _wait_until(func() -> bool: return lab.world_sync.synced_peers().size() == 1, 120.0):
		_check("client asked to enter the laboratory", false)
		return
	_check("the client isn't in yet as the door opens", lab.peers_in_level.size() == 1)
	# Slowed (here only: the host times the slide), so the client's entry lands mid-slide.
	lab.play._doors[moving].object.door_speed = 0.1
	lab.play.set_door(moving, true)
	if not await _wait_until(func() -> bool: return lab.peers_in_level.size() == 2, 120.0):
		_check("client entered the laboratory", false)
		return
	_check("the client entered while the door slid", lab.play._doors[moving].moving)
	await _wait_until(func() -> bool: return not lab.play._doors[moving].moving, 20.0)
	await _wait_seconds(2.0)
	_check_door(lab, moving, true, "door opened during the entry")

	# The client signs in and opens the blast door.
	_check("the client's sign-in unlocks the blast door", await _wait_until(func() -> bool: return not lab.play._doors[BLAST].object.door_locked, 30.0))
	_check("the client's E opens it", await _wait_until(func() -> bool: return lab.play._doors[BLAST].open and not lab.play._doors[BLAST].moving, 30.0))
	await _wait_seconds(1.0)
	_check_door(lab, BLAST, true, "blast door opened by the client")
	# A stale "open" from the client (it hadn't seen the door open yet) leaves it open.
	await _wait_seconds(3.0)
	_check_door(lab, BLAST, true, "blast door after a stale open")
	await _wait_seconds(4.0) # Stay up until the client is done.


func _client(net: Node) -> void:
	net.player_name = "Zack"
	_check("client connects", net.join("127.0.0.1", _port) == OK)
	var lab = await _wait_for_lab(null)
	if lab == null:
		return
	if not await _wait_until(func() -> bool: return _entered(lab), 120.0):
		_check("entered the waiting room", false)
		return
	_check("the admit door opens here", await _wait_until(func() -> bool: return _settled_at(lab, ADMIT, true), 30.0))
	await _wait_seconds(0.5)
	_check_door(lab, ADMIT, true, "admit opened")
	_check("the prompt offers to close it", lab.play.interactables.prompt(ADMIT) == "[E] Close", lab.play.interactables.prompt(ADMIT))
	await _stand_by(lab, lab.local_player(), ADMIT)
	lab.play.request_use(ADMIT)
	_check("the admit door closes here", await _wait_until(func() -> bool: return _settled_at(lab, ADMIT, false), 30.0))
	await _wait_seconds(0.5)
	_check_door(lab, ADMIT, false, "admit closed by the client")

	var old = lab
	lab = await _wait_for_lab(old)
	if lab == null:
		return
	if not await _wait_until(func() -> bool: return _entered(lab), 180.0):
		_check("entered the laboratory", false)
		return
	var moving := _moving_door(lab)
	_check("the door opened during the entry arrives open", await _wait_until(func() -> bool: return _settled_at(lab, moving, true), 30.0))
	await _wait_seconds(2.0)
	_check_door(lab, moving, true, "door opened during the entry")

	await _stand_by(lab, lab.local_player(), SIGNIN)
	lab.play.request_use(SIGNIN)
	_check("the blast door unlocks here", await _wait_until(func() -> bool: return not lab.play.is_door_locked(BLAST), 30.0))
	await _stand_by(lab, lab.local_player(), BLAST)
	lab.play.request_use(BLAST)
	_check("the blast door opens here", await _wait_until(func() -> bool: return _settled_at(lab, BLAST, true), 30.0))
	await _wait_seconds(1.0)
	_check_door(lab, BLAST, true, "blast door opened by the client")
	await _stand_by(lab, lab.local_player(), BLAST)
	lab.play._request_door.rpc_id(1, BLAST, true)
	await _wait_seconds(3.0)
	_check_door(lab, BLAST, true, "blast door after a stale open")


## The client is in: play runs, its player is spawned and the host has it in the level.
func _entered(lab) -> bool:
	return lab.level != null and lab.play.active and lab.local_player() != null and multiplayer_id(lab) in lab.peers_in_level


func multiplayer_id(lab) -> int:
	return lab.multiplayer.get_unique_id()


## A door (not the blast door) for the mid-entry test: the first by id with a slide.
func _moving_door(lab) -> String:
	var ids: Array = lab.play._doors.keys()
	ids.sort()
	for id: String in ids:
		if id != BLAST and lab.play._doors[id].object.door_offset != Vector3i.ZERO:
			return id
	return ""


## The door's voxels are all at its open (or closed) spot and none at the other.
func _settled_at(lab, id: String, open: bool) -> bool:
	var door: Dictionary = lab.play._doors.get(id, {})
	if door.is_empty():
		return false
	var closed: Vector3i = door.object.origin
	var at: Vector3i = closed + door.object.door_offset if open else closed
	var away: Vector3i = closed if open else closed + door.object.door_offset
	var solid: int = door.model.voxels.size() - door.model.voxels.count(0)
	return lab.world.count_matching(at, door.model.size, door.model.voxels) == solid \
			and lab.world.count_matching(away, door.model.size, door.model.voxels) == 0


func _check_door(lab, id: String, open: bool, stage: String) -> void:
	var door: Dictionary = lab.play._doors.get(id, {})
	if door.is_empty():
		_check(stage + ": the door exists", false, id)
		return
	var closed: Vector3i = door.object.origin
	var target: Vector3i = closed + door.object.door_offset if open else closed
	_check(stage + ": voxels where they should be", _settled_at(lab, id, open),
			"at closed %d, at open %d, solid %d" % [lab.world.count_matching(closed, door.model.size, door.model.voxels),
			lab.world.count_matching(closed + door.object.door_offset, door.model.size, door.model.voxels),
			door.model.voxels.size() - door.model.voxels.count(0)])
	_check(stage + ": the record says " + ("open" if open else "closed"), door.open == open and not door.moving, "open %s moving %s" % [door.open, door.moving])
	_check(stage + ": the record is where the voxels are", door.origin == target, "%s vs %s" % [door.origin, target])
	var lo: Vector3i = closed.min(closed + door.object.door_offset) - Vector3i.ONE * 2
	var hi: Vector3i = closed.max(closed + door.object.door_offset) + door.model.size + Vector3i.ONE * 2
	print("HASH %s %s %s" % [stage.replace(" ", "_"), id, _hash(lab.world.get_box(lo, hi))])

## Moves the client's player next to a usable thing and waits for the host's copy to follow (the
## host only honours a use request from within reach).
func _stand_by(lab, me, id: String) -> void:
	var box: AABB = lab.play.box_of(id)
	var c := box.get_center()
	me.teleport(Vector3(c.x + box.size.x * 0.5 + 1.0, box.position.y + 0.1, c.z))
	await _wait_seconds(0.4)


func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode().left(16)


## The Lab scene once it's loaded and isn't `old` (the level before a change).
func _wait_for_lab(old):
	var old_id: int = old.get_instance_id() if old else 0
	var ok := await _wait_until(func() -> bool:
		return current_scene != null and current_scene.name == "Lab" and current_scene.get_instance_id() != old_id and current_scene.level != null, 120.0)
	if not ok:
		_check("level loaded", false, str(current_scene))
		return null
	return current_scene


func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await process_frame
	return true


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
	print("%s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or detail == "" else "  (%s)" % detail])
