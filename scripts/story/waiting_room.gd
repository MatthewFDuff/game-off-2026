class_name WaitingRoom
extends Node
## Play-time logic of the waiting room level (docs/story.md): the host counts who has signed in at
## the reception terminal (its `prop_used`, once per player), rewrites the terminal's text on every
## peer ("Signed in: 2 of 3 connected"), and repeats hold lines over the intercom. Once every
## connected player has signed in, the host's terminal offers "Begin shift [E]" (the others read
## "Waiting for the host"); the host's next E on it admits the party: the admittance door opens, the
## intercom says so, and ADMIT_DELAY seconds later the session's level changes to NEXT_LEVEL
## (Net.change_level). Alone, the host signs in and then begins the shift the same way. Lab adds
## this node (named "WaitingRoom", so RPC paths match) when play starts in a level called
## `waiting_room`.

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
const HEADER := "FUNG AI  |  SITE 3  |  RECEPTION"

var lab: Lab
## Every peer (the host decides): peer ids that have signed in, and how many players are connected.
var signed: Array[int] = []
var total := 1
## Every peer (the host decides): the party is admitted (the door is open, the level change is
## coming).
var admitted := false

var _hold_left := HOLD_INTERVAL * 0.5
var _hold_index := 0
var _admit_left := -1.0


func _ready() -> void:
	if not multiplayer.is_server():
		return
	lab.play.prop_used.connect(_on_prop_used)
	lab.peer_entered.connect(func(peer_id: int) -> void: _state.rpc_id(peer_id, signed, total, admitted))
	Net.players_changed.connect(_recount)
	_recount()


func _process(delta: float) -> void:
	if not multiplayer.is_server() or lab.mode != "play":
		return
	_hold_left -= delta
	if _hold_left <= 0.0 and not admitted:
		_hold_left = HOLD_INTERVAL
		_say(HOLD_LINES[_hold_index % HOLD_LINES.size()])
		_hold_index += 1
	if _admit_left > 0.0:
		_admit_left -= delta
		if _admit_left <= 0.0:
			Net.change_level(NEXT_LEVEL)


## Host: E while reading the terminal closes it (Lab), so "Begin shift [E]" is taken here too.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and lab.mode == "play" and lab.play.reading == TERMINAL \
			and InputSetup.is_playing() and can_begin():
		begin_shift()


## Every peer: everyone connected has signed in, and the host hasn't admitted them yet.
func all_signed() -> bool:
	return not admitted and total > 0 and signed.size() >= total


## Host: the host may begin the shift now (everyone signed in, the host included).
func can_begin() -> bool:
	return multiplayer.is_server() and all_signed() and multiplayer.get_unique_id() in signed


## Host: a use of the terminal: signs the player in, or (the host, once everyone has) begins.
func _on_prop_used(id: String, peer_id: int) -> void:
	if id != TERMINAL:
		return
	if peer_id not in signed:
		signed.append(peer_id)
		Sfx.play("ui_pop", -6.0, 0.0)
		_recount()
	elif peer_id == multiplayer.get_unique_id() and can_begin():
		begin_shift()


## Host: admits the party: opens the admittance door, says so, and changes level ADMIT_DELAY later.
func begin_shift() -> void:
	if not can_begin():
		return
	admitted = true
	lab.play.set_door_locked(DOOR, false)
	lab.play.set_door(DOOR, true)
	_say(ADMIT_LINE)
	Sfx.play("power_up", -8.0, 0.0)
	_admit_left = ADMIT_DELAY
	_broadcast()


## Host: the party may have changed (someone joined, left or signed in); updates everyone.
func _recount() -> void:
	if not multiplayer.is_server():
		return
	total = maxi(Net.players.size(), 1)
	for peer_id in signed.duplicate():
		if not Net.players.has(peer_id):
			signed.erase(peer_id)
	_broadcast()


func _broadcast() -> void:
	for peer_id in lab.peers_in_level:
		if peer_id != 1:
			_state.rpc_id(peer_id, signed, total, admitted)
	_apply(signed, total, admitted)


@rpc("authority", "reliable")
func _state(who: Array, party: int, is_admitted: bool) -> void:
	_apply(who, party, is_admitted)


## Every peer: remembers the count and rewrites the terminal's text (what E shows), refreshing it
## if it's on screen.
func _apply(who: Array, party: int, is_admitted: bool) -> void:
	signed.assign(who)
	total = party
	admitted = is_admitted
	var terminal: Dictionary = lab.level.objects.get(TERMINAL, {})
	if terminal.is_empty():
		return
	terminal.text = terminal_text()
	if lab.play.reading == TERMINAL:
		lab.play.reading_changed.emit(TERMINAL)


## This peer's view of the terminal: who has signed in, and what to do next.
func terminal_text() -> String:
	var names: PackedStringArray = []
	for peer_id in signed:
		names.append(str(Net.players.get(peer_id, {}).get("name", "Expendable")))
	var count := "Signed in: %d of %d connected.%s" % [signed.size(), total,
			"" if names.is_empty() else "  (" + ", ".join(names) + ")"]
	var me := multiplayer.get_unique_id()
	var next := "Press E to sign in."
	if admitted:
		next = "Admitted. Please proceed through the door."
	elif me in signed and all_signed():
		next = "Everyone is signed in.\n\nBegin shift [E]" if multiplayer.is_server() else "Everyone is signed in. Waiting for the host to begin the shift."
	elif me in signed:
		next = "Please wait for the others to sign in. Your shift is important to us."
	return "%s\n\n%s\n\n%s" % [HEADER, count, next]


## Host: an intercom line everyone reads (Intercom.say_text when it has one, else a toast).
func _say(text: String) -> void:
	var story := lab.find_child("Story", true, false) as Story
	if story and story.intercom and story.intercom.has_method("say_text"):
		story.intercom.call("say_text", text)
	else:
		lab.notify(text)
