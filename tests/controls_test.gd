extends SceneTree
## Checks the input actions and the F1 controls description. Headless:
##   godot --headless --path . --script res://tests/controls_test.gd


func _initialize() -> void:
	var failures := 0
	InputSetup.ensure_actions()
	for action in ["melee", "cycle_ammo", "ammo_1", "ammo_4", "cycle_flask", "show_controls", "fire", "alt_fire"]:
		if not InputMap.has_action(action):
			print("FAIL missing action ", action)
			failures += 1
	if InputMap.has_action("sprint"):
		print("FAIL sprint still exists")
		failures += 1
	var rows := InputSetup.describe_play_controls()
	var by_label := {}
	for row in rows:
		by_label[row.label] = row.keys
		print("%s: %s" % [row.label, row.keys])
	if by_label.get("Melee") != "MMB" or by_label.get("Throw flask") != "RMB" or by_label.get("Cycle flask") != "Q":
		print("FAIL wrong bindings")
		failures += 1
	if not "SHIFT" in String(by_label.get("Change ammo (SHIFT)", "")).to_upper():
		print("FAIL ammo keys")
		failures += 1
	print("controls_test: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)
