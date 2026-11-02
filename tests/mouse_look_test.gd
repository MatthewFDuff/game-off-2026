extends SceneTree
## Injects mouse motion into the test world and checks the player turns. Needs a window:
##   godot --path . --script res://tests/mouse_look_test.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: Node3D = load("res://scenes/test_world.tscn").instantiate()
	root.add_child(scene)
	var player: Player = scene.get_node("Player")
	await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await process_frame
	print("mouse mode: ", Input.mouse_mode)

	var event := InputEventMouseMotion.new()
	event.relative = Vector2(100, 40)
	event.screen_relative = Vector2(100, 40)
	event.position = Vector2(root.size) * 0.5
	event.global_position = event.position
	Input.parse_input_event(event)
	for i in 3:
		await process_frame

	print("yaw %.3f  pitch %.3f" % [player.rotation.y, player.get_node("Head").rotation.x])

	# Only relative set, as delivered by the editor's embedded game window.
	var relative_only := InputEventMouseMotion.new()
	relative_only.relative = Vector2(100, 0)
	Input.parse_input_event(relative_only)
	for i in 3:
		await process_frame
	print("after relative-only event: yaw %.3f" % player.rotation.y)

	Input.action_press("look_left")
	for i in 30:
		await process_frame
	Input.action_release("look_left")
	print("after holding left arrow: yaw %.3f" % player.rotation.y)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	quit()
