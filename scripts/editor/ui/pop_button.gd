class_name PopButton
extends Button
## A button that pops as the pointer arrives: a quick punch up in scale, a small tilt it holds, and a
## soft pop sound. Leaving puts it back. Ported from Puzzle Pals.
##
## The pointer area stays the button's resting rectangle however it's tilted (_has_point), so the
## tilt can't move the button out from under a still pointer and start an enter / exit loop. Coming
## straight back after clipping an edge glides to the hover pose instead of popping again.

const POP_SCALE := 1.12
const HOVER_SCALE := 1.04
const TILT_DEGREES := 4.0
const PUNCH_SECONDS := 0.09
const SETTLE_SECONDS := 0.22
const RELEASE_SECONDS := 0.16
const REARRIVAL_GRACE := 0.35

var _tween: Tween
var _left_at := -1.0


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	_center_pivot()
	resized.connect(_center_pivot)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	visibility_changed.connect(_on_visibility_changed)


func _center_pivot() -> void:
	pivot_offset = size * 0.5


func _has_point(point: Vector2) -> bool:
	var parent_item := get_parent() as CanvasItem
	var rest := Rect2(position, size)
	if parent_item:
		rest = parent_item.get_global_transform() * rest
	return rest.has_point(get_global_transform() * point)


func _on_mouse_entered() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var returning := _left_at >= 0.0 and now - _left_at < REARRIVAL_GRACE
	_restart_tween()
	if returning:
		_tween.tween_property(self, "scale", Vector2.ONE * HOVER_SCALE, RELEASE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "rotation_degrees", TILT_DEGREES, RELEASE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		return
	Sfx.play("ui_pop", -16.0, 0.05)
	_tween.tween_property(self, "scale", Vector2.ONE * POP_SCALE, PUNCH_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE * HOVER_SCALE, SETTLE_SECONDS).set_delay(PUNCH_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "rotation_degrees", TILT_DEGREES, PUNCH_SECONDS + SETTLE_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_mouse_exited() -> void:
	_left_at = Time.get_ticks_msec() / 1000.0
	_restart_tween()
	_tween.tween_property(self, "scale", Vector2.ONE, RELEASE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "rotation_degrees", 0.0, RELEASE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## A panel swapping out from under the pointer sends no mouse_exited, so drop the pose outright.
func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		return
	if _tween:
		_tween.kill()
	scale = Vector2.ONE
	rotation_degrees = 0.0
	_left_at = -1.0


func _restart_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
