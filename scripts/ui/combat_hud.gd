class_name CombatHud
extends Control
## Play-mode combat feedback for the local player: a health bar in the bottom left, a hit marker
## on the crosshair when one of this peer's shots lands on an enemy, and a red screen flash when
## the player takes damage. Hidden while editing. Added by LabHud.

const BAR_SIZE := Vector2(220, 14)
const HIT_MARKER_TIME := 0.12
const DAMAGE_FLASH_TIME := 0.4

var lab: Lab

var _flash := ColorRect.new()
var _bar_back := ColorRect.new()
var _bar_fill := ColorRect.new()
var _bar_label := Label.new()
var _hit_marker := Label.new()
var _hit_time := 0.0
var _flash_time := 0.0
var _last_health := -1.0
var _last_player: Player


static func create(level: Lab) -> CombatHud:
	var hud := CombatHud.new()
	hud.lab = level
	return hud


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_flash.color = Color(0.8, 0.0, 0.0, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_bar_back.color = Color(0.0, 0.0, 0.0, 0.55)
	_bar_back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_bar_back.position = Vector2(16, -16 - BAR_SIZE.y)
	_bar_back.size = BAR_SIZE
	_bar_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_back)
	_bar_fill.color = Color(0.85, 0.2, 0.18)
	_bar_fill.position = Vector2(2, 2)
	_bar_fill.size = BAR_SIZE - Vector2(4, 4)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_back.add_child(_bar_fill)
	_bar_label.label_settings = LabHud._settings(12)
	_bar_label.position = Vector2(BAR_SIZE.x + 8, -5)
	_bar_back.add_child(_bar_label)

	_hit_marker.text = "x"
	_hit_marker.label_settings = LabHud._settings(26, Color(1.0, 1.0, 1.0), 4)
	_hit_marker.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_hit_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hit_marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hit_marker.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hit_marker.grow_vertical = Control.GROW_DIRECTION_BOTH
	_hit_marker.visible = false
	add_child(_hit_marker)

	if lab.enemies:
		lab.enemies.local_hit.connect(func(_enemy: Enemy, _point: Vector3) -> void:
			_hit_time = HIT_MARKER_TIME)


func _process(delta: float) -> void:
	var me := lab.local_player()
	visible = me != null and lab.mode == "play" and not me.editing
	if not visible:
		return
	# Damage is any drop in health (regen only ever raises it).
	if me != _last_player:
		_last_player = me
		_last_health = me.health
	if me.health < _last_health - 0.01:
		_flash_time = DAMAGE_FLASH_TIME
	_last_health = me.health
	var fraction := clampf(me.health / maxf(me.max_health, 1.0), 0.0, 1.0)
	_bar_fill.size.x = (BAR_SIZE.x - 4) * fraction
	_bar_label.text = "%d" % ceili(me.health)

	_flash_time = maxf(0.0, _flash_time - delta)
	_flash.color.a = 0.35 * _flash_time / DAMAGE_FLASH_TIME
	_hit_time = maxf(0.0, _hit_time - delta)
	_hit_marker.visible = _hit_time > 0.0
