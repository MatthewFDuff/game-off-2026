class_name PropThumbnails
extends Node
## Renders a small picture of each prop for the editor's prop list in an offscreen viewport, and
## keeps them. The ones the list shows right now (want_now) go first, one a frame; the rest follow
## in the background, one every BACKGROUND_FRAMES frames, so opening the catalog doesn't hitch for
## hundreds of frames. Does nothing without a display (headless runs).

signal rendered(prop_name: String, texture: Texture2D)

const SIZE := 72
## Frames between background renders (pictures nobody's looking at yet).
const BACKGROUND_FRAMES := 3

var view: LevelView
var _textures := {}
var _queue: Array[String] = []
## Wanted now (in view): rendered before _queue, one a frame.
var _urgent: Array[String] = []
var _wait := 0
var _viewport := SubViewport.new()
var _camera := Camera3D.new()
var _mesh := MeshInstance3D.new()
var _busy := false


func _ready() -> void:
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	environment.ambient_light_energy = 0.8
	_camera.environment = environment
	_camera.fov = 30.0
	var sun := DirectionalLight3D.new()
	# From over the camera's shoulder: props face -Z and the camera looks at their front.
	sun.rotation_degrees = Vector3(-50.0, 210.0, 0.0)
	_viewport.add_child(sun)
	_viewport.add_child(_camera)
	_viewport.add_child(_mesh)
	add_child(_viewport)


## The prop's picture, or null until it's rendered (it's queued). urgent: it's on screen, so it
## goes ahead of the background ones.
func get_texture(prop_name: String, urgent := true) -> Texture2D:
	if not _textures.has(prop_name) and DisplayServer.get_name() != "headless":
		if urgent:
			if prop_name not in _urgent:
				_urgent.append(prop_name)
		elif prop_name not in _queue and prop_name not in _urgent:
			_queue.append(prop_name)
	return _textures.get(prop_name)


## The props in view right now: theirs are rendered next (one a frame), in this order.
func want_now(prop_names: Array[String]) -> void:
	for prop_name in _urgent:
		if prop_name not in _queue:
			_queue.append(prop_name) # Out of view now: still drawn, in the background.
	_urgent.clear()
	if DisplayServer.get_name() == "headless":
		return
	for prop_name in prop_names:
		if not _textures.has(prop_name):
			_urgent.append(prop_name)


## Pictures still to render.
func pending() -> int:
	return _urgent.size() + _queue.size()


## Live reload: draw it again.
func forget(prop_name: String) -> void:
	_textures.erase(prop_name)


func _process(_delta: float) -> void:
	if _busy:
		return
	while not _urgent.is_empty():
		var prop_name: String = _urgent.pop_front()
		if _textures.has(prop_name):
			continue
		_queue.erase(prop_name)
		_render(prop_name)
		return
	if _queue.is_empty():
		return
	_wait -= 1
	if _wait > 0:
		return
	_wait = BACKGROUND_FRAMES
	var next: String = _queue.pop_front()
	if not _textures.has(next):
		_render(next)


func _render(prop_name: String) -> void:
	var mesh := view.prop_mesh(prop_name, 0)
	if mesh == null:
		_textures[prop_name] = null # No picture: don't keep trying.
		return
	_busy = true
	_mesh.mesh = mesh
	_mesh.material_override = view.lab.world.material
	var box := mesh.get_aabb()
	var center := box.get_center()
	var distance := box.size.length() * 2.1
	# Three-quarter view of the front (props face -Z).
	_camera.position = center + Vector3(-0.55, 0.45, -1.0).normalized() * distance
	_camera.look_at(center)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var texture := ImageTexture.create_from_image(_viewport.get_texture().get_image())
	_textures[prop_name] = texture
	_busy = false
	rendered.emit(prop_name, texture)
