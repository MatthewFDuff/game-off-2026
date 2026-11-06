class_name Lines
## Every line the story says in the laboratory, in one place so the team can rewrite them:
## the intercom (keyed by the trigger id or event that plays it), the training experiment's steps,
## and the payroll ending. Placeholder text from docs/story.md.

## Intercom lines by trigger id / event. The Intercom plays each once, except REPEATABLE ones.
## The seals (t_g_seal, t_m1_stair_seal, t_m2_airlock, t_m3_cage_foot) are keyed by their trigger
## ids. `hint_<door id>` is a keycard door's own refusal line, played on its first refusal instead
## of gate_locked (the same hint is on a note beside each door). say_training_nudge isn't a
## trigger: the Intercom plays it about 30 s after say_training unless the experiment has started.
const INTERCOM := {
	say_yard = "Welcome to Fung AI Site 3. You are the night shift. Please sign in at the desk.",
	say_signin = "Thank you. Your supervisor tonight is the model. Follow its instructions on any screen. Please proceed to Level 0.",
	say_lobby = "This is Administration. The grow rooms are off limits to expendable staff, except tonight.",
	say_break_room = "The coffee machine is Fung AI property. Coffee is $4.",
	say_training = "Your station is the terminal by the specimen. Press E to begin.",
	say_training_nudge = "Reminder: your station is the terminal by the specimen. Press E to begin. Idle time is unpaid.",
	say_flashlight = "Emergency lighting is minimal. Flashlights (T) are company property.",
	t_0_outbreak = "Facility power has failed. Backup power is running the intercom and emergency lighting. The exit is locked. Please restore facility power at the generator, Level -4. Fung AI thanks you for your flexibility.",
	t_g_seal = "Blast door closed behind you. Please proceed to Level 0.",
	t_m1_stair_seal = "Fire door sealed behind you. Thank you for not going back.",
	t_m2_airlock = "Decontamination seal engaged. Level -2 is now behind you. Thank you for not going back.",
	t_m3_cage_foot = "Cage door sealed above you. Containment thanks you for not going back.",
	say_clone_bay = "A growth vat. Should you die, a replacement is grown here and billed to you.",
	say_gate_m2 = "Decontamination ahead. Red clearance required beyond this point.",
	say_gate_m3 = "The cage lift is black clearance only. The dig is not a staff area.",
	gate_locked = "Clearance required.",
	hint_d_0_lift = "Blue clearance is issued from the Security office, beside the lift lobby.",
	hint_d_m1_stair = "Green clearance is held by the Mycology office, off grow hall 2.",
	hint_d_m2_airlock_out = "Red clearance is kept in the Ops room, at the east end of the server hall.",
	hint_d_m3_cage = "Black clearance is kept in the chamber 3 control booth.",
	gate_open = "Clearance accepted. Thank you.",
	t_m4_generator = "Generator start detected. Please hold.",
	finale_survived = "Facility power restored. The freight elevator is available. Please proceed to the surface for debrief.",
	finale_failed = "All staff lost. Growing replacements.",
	armed = "You have armed yourself with Fung AI property. It has been noted.",
}

## Lines that can play again (door refusals and the like).
const REPEATABLE := ["gate_locked", "gate_open"]

## The training terminal's experiment: the screen's prompt, then the lines it prints after SHIFT.
## The last step's results are revealed one at a time. `effect` names what the spore tank does.
const EXPERIMENT := [
	{prompt = "Subject: specimen 0-1.\nStep 1: prod the specimen.", results = ["no change detected"], effect = "prod"},
	{prompt = "Step 2: illuminate the specimen.", results = ["no change detected"], effect = "light"},
	{prompt = "Step 3: water the specimen.", results = ["no change detected"], effect = "water"},
	{prompt = "Step 4: apply 40 volts.", results = ["no change detected"], effect = "zap"},
	{prompt = "Step 5: apply 400 volts.", results = ["no change- wait.", "data detected...", "deciphering...", "thoughts detected.", "> ow"], effect = "zap"},
]
## The screen's header and what it says once the crash has happened.
const EXPERIMENT_HEADER := "SUBSTRATE MONITOR  |  Grow 0 / specimen 0-1\nPress SHIFT to perform each step."
const EXPERIMENT_DONE := "[CRASH]\n\nplease go and look."
## Seconds between the last step's revealed lines.
const REVEAL_SECONDS := 0.8

## The payroll ending.
const ENDING := {
	title = "FUNG AI  |  PAYROLL STATEMENT  |  SITE 3 NIGHT SHIFT",
	wages = 180,
	clone_cost = 5000,
	note = "From: Guy Fung, CEO\n\nThanks for your service. Your next shift starts tomorrow at 22:00. Please bring your own coffee.",
}


## The experiment as the training terminal's `steps` text: one line per step, `prompt -> result | result`.
static func steps_text() -> String:
	var lines: Array[String] = []
	for step: Dictionary in EXPERIMENT:
		lines.append("%s -> %s" % [str(step.prompt).replace("\n", " / "), " | ".join(step.results)])
	return "\n".join(lines)


## Parses a `steps` field back into [{prompt, results}].
static func parse_steps(text: String) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	for line in text.split("\n", false):
		var parts := line.split("->", true, 1)
		var prompt := parts[0].strip_edges().replace(" / ", "\n")
		var results: Array[String] = []
		if parts.size() > 1:
			for result in parts[1].split("|"):
				results.append(result.strip_edges())
		steps.append({prompt = prompt, results = results})
	return steps
