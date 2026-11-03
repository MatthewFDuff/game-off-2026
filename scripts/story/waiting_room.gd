class_name WaitingRoom
extends Node
## Play-time logic of the waiting room level (docs/story.md): the host counts who has signed in at
## the reception terminal (its `prop_used`, once per player), rewrites the terminal's text on every
## peer ("Signed in: 2 of 3"), repeats hold lines from the intercom, and once every connected player
## has signed in it opens the admittance door, says so, and ADMIT_DELAY seconds later changes the
## session's level to NEXT_LEVEL (Net.change_level). Lab adds this node (named "WaitingRoom", so
## RPC paths match) when play starts in a level called `waiting_room`.

const TERMINAL := "reception"
const DOOR := "d_admit"
const NEXT_LEVEL := "laboratory"
const ADMIT_DELAY := 4.0
const HOLD_INTERVAL := 20.0
const HOLD_LINES := [
	"Your shift is important to us. Please hold.",
	"Please do not lick the specimens.",
	"Fung AI: growing tomorrow, today.",
	"Clones are property. Thank you for your understanding.",
	"The vending machine is out of order. This has been deducted.",
]
const ADMIT_LINE := "Site 3 is ready for you. Please proceed through the door."

var lab: Lab
## Every peer: peer ids that have signed in, and how many players the party has.
var signed: Array[int] = []
var total := 1
## Host: the party is admitted (the door is open and the level change is coming).
var admitted := false

var _hold_left := HOLD_INTERVAL * 0.5
var _hold_index := 0
var _admit_left := -1.0


func _ready() -> void:
	if not multiplayer.is_server():
		return
	lab.play.prop_used.connect(_on_prop_used)
	lab.peer_entered.connect(func(peer_id: int) -> void: _state.rpc_id(peer_id, signed, total))
	Net.players_changed.connect(_recount)
	_recount()


func _process(delta: float) -> void:
	if not multiplayer.is_server() or lab.mode != "play":
		return
	_hold_left -= delta
	if _hold_left <= 0.0 and not admitted:
		_hold_left = HOLD_INTERVAL
		lab.notify(HOLD_LINES[_hold_index % HOLD_LINES.size()])
		_hold_index += 1
	if _admit_left > 0.0:
		_admit_left -= delta
		if _admit_left <= 0.0:
			Net.change_level(NEXT_LEVEL)


## Host: a sign-in at the terminal.
func _on_prop_used(id: String, peer_id: int) -> void:
	if id != TERMINAL or peer_id in signed:
		return
	signed.append(peer_id)
	Sfx.play("ui_pop", -6.0, 0.0)
	_recount()


## Host: the party may have changed; updates everyone and admits when everyone has signed.
func _recount() -> void:
	if not multiplayer.is_server():
		return
	total = maxi(Net.players.size(), 1)
	for peer_id in signed.duplicate():
		if not Net.players.has(peer_id):
			signed.erase(peer_id)
	for peer_id in lab.peers_in_level:
		if peer_id != 1:
			_state.rpc_id(peer_id, signed, total)
	_apply(signed, total)
	if not admitted and signed.size() >= total:
		admitted = true
		lab.play.set_door_locked(DOOR, false)
		lab.play.set_door(DOOR, true)
		lab.notify(ADMIT_LINE)
		Sfx.play("power_up", -8.0, 0.0)
		_admit_left = ADMIT_DELAY


@rpc("authority", "reliable")
func _state(who: Array, party: int) -> void:
	_apply(who, party)


## Every peer: remembers the count and rewrites the terminal's text (what E shows).
func _apply(who: Array, party: int) -> void:
	signed.assign(who)
	total = party
	var terminal: Dictionary = lab.level.objects.get(TERMINAL, {})
	if terminal.is_empty():
		return
	var names: PackedStringArray = []
	for peer_id in signed:
		names.append(str(Net.players.get(peer_id, {}).get("name", "Expendable")))
	var mine := multiplayer.get_unique_id() in signed
	terminal.text = "FUNG AI  |  SITE 3  |  RECEPTION\n\nSigned in: %d of %d.%s\n\n%s" % [signed.size(), total,
			("" if names.is_empty() else "  (" + ", ".join(names) + ")"),
			("Please wait to be admitted. Your shift is important to us." if mine else "Press E to sign in.")]
