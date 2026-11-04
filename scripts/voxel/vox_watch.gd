extends Node
## Live reload for MagicaVoxel art and pattern images (`VoxWatch` autoload). Polls the .vox and
## .png files under `roots` and reports the ones that changed, once their modified time has held
## still for a poll, so a file that's still being saved isn't read half-written. Only runs from
## the editor binary: exported games can't have their files edited.
##
## A poll is spread over frames: each frame lists at most one directory and checks at most
## FILES_PER_FRAME files, so the few hundred stats of a pass never land in one frame. The first
## pass only records the files (nothing is reported for it).

## res:// paths of the files that changed (or appeared) since the last report.
signal changed(paths: PackedStringArray)

## Seconds between the end of one pass and the start of the next.
const POLL_SECONDS := 0.4
const FILES_PER_FRAME := 24

var roots: PackedStringArray = ["res://assets/vox/", "res://assets/patterns/"]
var enabled := OS.has_feature("editor")

var _times := {}
var _pending := {}
var _timer := 0.0
## The pass in progress: directories still to list, files still to check, files that held still.
var _dirs: PackedStringArray = []
var _queue: PackedStringArray = []
var _ready_paths := PackedStringArray()
var _in_pass := false
## False until the first pass has recorded every file.
var _primed := false


func _process(delta: float) -> void:
	if not enabled:
		return
	if not _in_pass:
		_timer -= delta
		if _timer > 0.0 and _primed:
			return
		_dirs = roots.duplicate()
		_queue.clear()
		_ready_paths.clear()
		_in_pass = true
	_step()


## One frame of the pass: a directory listing if no files are queued, then up to FILES_PER_FRAME
## file checks. Finishes the pass when nothing is left.
func _step() -> void:
	if _queue.is_empty() and not _dirs.is_empty():
		var dir := _dirs[0]
		_dirs.remove_at(0)
		for file in DirAccess.get_files_at(dir):
			if file.get_extension() in ["vox", "png"]:
				_queue.append(dir.path_join(file))
		for sub in DirAccess.get_directories_at(dir):
			_dirs.append(dir.path_join(sub))
	var n := mini(FILES_PER_FRAME, _queue.size())
	for i in n:
		_check(_queue[i], _primed)
	_queue = _queue.slice(n)
	if _queue.is_empty() and _dirs.is_empty():
		_finish_pass()


func _check(path: String, report: bool) -> void:
	var time := FileAccess.get_modified_time(path)
	var known: int = _times.get(path, -1)
	if time == known:
		if _pending.has(path) and _pending[path] == time:
			_pending.erase(path)
			_ready_paths.append(path)
		return
	_times[path] = time
	# Files seen before (watch(), or an earlier pass) report even during the first pass.
	if report or known != -1:
		_pending[path] = time # Report next poll if it hasn't moved again.


func _finish_pass() -> void:
	_in_pass = false
	_primed = true
	_timer = POLL_SECONDS
	if _ready_paths.is_empty():
		return
	var ready := _ready_paths
	_ready_paths = PackedStringArray()
	print("vox changed: ", ", ".join(Array(ready).map(func(p: String) -> String: return p.get_file())))
	changed.emit(ready)


## Also watch dir (for tests, or levels kept elsewhere). Its current files count as already seen.
func watch(dir: String) -> void:
	if dir not in roots:
		roots.append(dir)
		for path in _files(dir):
			_times[path] = FileAccess.get_modified_time(path)


## Every file under dir, in one go (watch only).
func _files(dir: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() in ["vox", "png"]:
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_files(dir.path_join(sub)))
	return found
