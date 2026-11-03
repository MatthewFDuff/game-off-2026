extends Node
## Live reload for MagicaVoxel art and pattern images (`VoxWatch` autoload). Polls the .vox and
## .png files under `roots` and reports the ones that changed, once their modified time has held
## still for a poll, so a file that's still being saved isn't read half-written. Only runs from
## the editor binary: exported games can't have their files edited.

## res:// paths of the files that changed (or appeared) since the last report.
signal changed(paths: PackedStringArray)

const POLL_SECONDS := 0.4

var roots: PackedStringArray = ["res://assets/vox/", "res://assets/patterns/"]
var enabled := OS.has_feature("editor")

var _times := {}
var _pending := {}
var _timer := 0.0


func _ready() -> void:
	_scan(false)


func _process(delta: float) -> void:
	if not enabled:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = POLL_SECONDS
	_scan(true)


## Also watch dir (for tests, or levels kept elsewhere). Its current files count as already seen.
func watch(dir: String) -> void:
	if dir not in roots:
		roots.append(dir)
		for path in _files(dir):
			_times[path] = FileAccess.get_modified_time(path)


func _scan(report: bool) -> void:
	var ready := PackedStringArray()
	for root in roots:
		for path in _files(root):
			var time := FileAccess.get_modified_time(path)
			var known: int = _times.get(path, -1)
			if time == known:
				if _pending.has(path) and _pending[path] == time:
					_pending.erase(path)
					ready.append(path)
				continue
			_times[path] = time
			if report:
				_pending[path] = time # Report next poll if it hasn't moved again.
	if not ready.is_empty():
		print("vox changed: ", ", ".join(Array(ready).map(func(p: String) -> String: return p.get_file())))
		changed.emit(ready)


func _files(dir: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() in ["vox", "png"]:
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_files(dir.path_join(sub)))
	return found
