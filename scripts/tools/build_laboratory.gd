extends SceneTree
## Builds res://levels/laboratory/ (see scripts/tools/lab_builder.gd and docs/lab-design.md). Refuses
## to overwrite an existing level unless --force is given.
##   godot --headless --path . --script res://scripts/tools/build_laboratory.gd [-- --force]

const Builder := preload("res://scripts/tools/lab_builder.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var existing := LevelData.RES_DIR.path_join(Builder.LEVEL_NAME).path_join("level.json")
	if FileAccess.file_exists(existing) and "--force" not in OS.get_cmdline_user_args():
		print("build_laboratory: %s exists; pass --force to overwrite" % existing)
		quit(1)
		return
	var builder := Builder.new()
	var error: Error = builder.build(root)
	print("build_laboratory: saved %s (%d objects): %s" % [Builder.LEVEL_NAME, builder.level.objects.size(), error_string(error)])
	builder.world.free()
	quit(0 if error == OK else 1)
