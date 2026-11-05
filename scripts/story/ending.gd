class_name Ending
extends Control
## The end of the shift: the host works out the payroll statement from the night's accounts (begin:
## wages, every broken asset by name, purchases by name (vending machines, coffee), clones grown,
## doors forced, the total owed) and sends it to every peer;
## each peer leaves it in Net.pending_statement / pending_total at once, fades to black over
## FADE_SECONDS and leaves the session, landing in its own cubicle, which rolls the statement on
## the computer (docs/cubicle-menu.md, section 5). The lines are "left|right" ("Shift wages|+$40");
## the cubicle rolls them in that format. Setting the statement first means a peer whose fade is
## cut short by the host's server closing still has it. It covers the whole viewport (LabHud hides
## the HUD under it), and a mode change (the editor's F5 replay) resets it so the next play can
## end again. In a level-editor session the fade lifts instead of leaving. On the host, a story
## shift's statement clears the shift save (ShiftSave) and Net.session.shift, so it can't be resumed.

const FADE_SECONDS := 2.0

var lab: Lab
var shown := false
var total := 0
## Whether the fade ends by leaving the session (tests turn it off to stay in the lab).
var leave_after_fade := true
var _lines: Array[String] = []
var _black := ColorRect.new()
var _tween: Tween


func _ready() -> void:
	name = "Ending"
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The offsets too: inside the tree, set_anchors_preset alone keeps the old 0 x 0 rect.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_black.color = Color(0, 0, 0, 0)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_black)
	if lab:
		lab.mode_changed.connect(func(_mode: String) -> void: reset())


## Clears the ending (a mode change: the editor's replay ends the night afresh). A statement already
## handed to Net stays there.
func reset() -> void:
	if _tween:
		_tween.kill()
	shown = false
	total = 0
	_lines.clear()
	visible = false
	_black.color = Color(0, 0, 0, 0)


## Host: works the statement out and shows it everywhere. clones is how many respawns the night took.
func begin(clones: int) -> void:
	if not multiplayer.is_server() or shown:
		return
	var play := lab.play
	var lines: Array[String] = []
	var wages := int(Lines.ENDING.wages)
	lines.append("Shift wages|+$%d" % wages)
	var owed := 0
	var names: Array = play.damage_by_name.keys()
	names.sort()
	if names.is_empty():
		lines.append("Property damage|$0")
	else:
		lines.append("Property damage:|")
		for asset_name: String in names:
			var dollars := int(play.damage_by_name[asset_name])
			owed += dollars
			lines.append("   %s|-$%d" % [asset_name.replace("_", " "), dollars])
	var bought: Array = play.purchases.keys()
	bought.sort()
	if not bought.is_empty():
		lines.append("Purchases:|")
		for what: String in bought:
			var dollars := int(play.purchases[what])
			owed += dollars
			lines.append("   %s|-$%d" % [what.replace("_", " "), dollars])
	var clone_cost := clones * int(Lines.ENDING.clone_cost)
	owed += clone_cost
	lines.append("Clones grown: %d x $%d|-$%d" % [clones, int(Lines.ENDING.clone_cost), clone_cost])
	var forced := play.forced_doors.size()
	owed += forced * LevelPlay.FORCED_DOOR_FEE
	lines.append("Doors forced: %d x $%d|-$%d" % [forced, LevelPlay.FORCED_DOOR_FEE, forced * LevelPlay.FORCED_DOOR_FEE])
	var net := wages - owed
	lines.append("TOTAL OWED TO FUNG AI|-$%d" % (-net) if net < 0 else "NET PAY|+$%d" % net)
	for peer_id in Net.players:
		if peer_id != multiplayer.get_unique_id() and lab.players.has(peer_id):
			_show.rpc_id(peer_id, lines, net)
	_show(lines, net)


@rpc("authority", "reliable")
func _show(lines: Array, net: int) -> void:
	if shown:
		return
	shown = true
	total = net
	_lines.assign(lines)
	# The shift is paid out: the clone on file goes, and nothing saves it again.
	if multiplayer.is_server() and Net.session.get("shift", false):
		ShiftSave.clear()
		Net.session.shift = false
	Net.pending_statement = lines.duplicate()
	Net.pending_total = net
	visible = true
	InputSetup.release_play()
	_tween = create_tween()
	_tween.tween_property(_black, "color", Color(0, 0, 0, 1), FADE_SECONDS)
	_tween.tween_callback(_leave)


func _leave() -> void:
	if not leave_after_fade:
		return
	# A test play inside the level editor (the editor's play mode) stays in the editor session: the
	# black lifts and the statement is dropped.
	if str(Net.session.get("mode", "play")) == "edit":
		Net.pending_statement = []
		Net.pending_total = 0
		reset()
		return
	# Deferred: the scene change frees this node, which mustn't happen inside its own tween step.
	Net.leave.call_deferred()
