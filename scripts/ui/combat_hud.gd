class_name CombatHud
extends Control
## Play-mode combat feedback for the local player: a health bar in the bottom left, the ammo
## readout in the bottom right (loaded type in its color, rounds or infinity, the type Shift loads
## next), the selected flask left of it (its name in its color and the count, Q to cycle), a toast
## with the type's name when it changes, a hit marker on the crosshair when one of this peer's
## shots lands on an enemy, a red screen flash when the player takes damage, and a vignette while
## a status is on the player (green poisoned, orange burning), and during the generator finale a
## "SURVIVE m:ss" countdown at the top with "power restoring" under it (pulsing in the last 10 s)
## and SURVIVE / SHIFT SURVIVED / SHIFT FAILED banners. Hidden while editing and while LabHud
## suppresses it (the ending's statement). Added by LabHud.

const BAR_SIZE := Vector2(220, 14)
const HIT_MARKER_TIME := 0.12
const DAMAGE_FLASH_TIME := 0.4
const AMMO_TOAST_TIME := 1.5
const BANNER_TIME := 6.0
const FINALE_COLOR := Color(1.0, 0.35, 0.2)
## Player status -> vignette color, strongest first.
const STATUS_VIGNETTES := {burning = Color(1.0, 0.45, 0.1), poisoned = Color(0.35, 0.95, 0.25)}

var lab: Lab
## Set by LabHud while the ending's statement shows: the whole combat HUD hides.
var suppressed := false

var _flash := ColorRect.new()
var _flash_material := VoxelFx.overlay(0.35, 4.0, 3.0)
var _bar_back := ColorRect.new()
var _bar_fill := ColorRect.new()
var _bar_label := Label.new()
var _hit_marker := PixelMark.create("x")
var _hit_time := 0.0
var _flash_time := 0.0
var _last_health := -1.0
var _last_player: Player
var _ammo_box := VBoxContainer.new()
var _ammo_name := Label.new()
var _ammo_count := Label.new()
var _ammo_next := Label.new()
var _ammo_toast := Label.new()
var _ammo_toast_time := 0.0
var _last_ammo := ""
var _flask_box := VBoxContainer.new()
var _flask_name := Label.new()
var _flask_count := Label.new()
var _vignette := ColorRect.new()
var _vignette_material := VoxelFx.overlay(0.5, 6.0, 4.0)
var _blind_material := VoxelFx.overlay(-1.0, 3.0, 4.0)
var _finale_label := Label.new()
var _finale_note := Label.new()
var _banner := Label.new()
var _banner_time := 0.0


static func create(level: Lab) -> CombatHud:
	var hud := CombatHud.new()
	hud.lab = level
	return hud


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Status vignette and damage flash: pixel overlays (VoxelFx.overlay), blocky dithered rings and
	# an even dither, never a smooth gradient.
	_vignette.color = Color.WHITE
	_vignette.material = _vignette_material
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.visible = false
	add_child(_vignette)

	_flash.color = Color(0.8, 0.0, 0.0, 1.0)
	_flash.material = _flash_material
	_flash.visible = false
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

	_hit_marker.visible = false
	add_child(_hit_marker)

	_build_ammo()
	_build_finale()

	if lab.enemies:
		lab.enemies.local_hit.connect(func(_enemy: Enemy, _point: Vector3) -> void:
			_hit_time = HIT_MARKER_TIME)


func _process(delta: float) -> void:
	var me := lab.local_player()
	visible = me != null and lab.mode == "play" and not me.editing and not suppressed
	if not visible:
		return
	# Damage is any drop in health (regen only ever raises it).
	if me != _last_player:
		_last_player = me
		_last_health = me.health
	if me.health < _last_health - 0.01:
		_flash_time = DAMAGE_FLASH_TIME
	_last_health = me.health
	# The health bar belongs to combat: nothing to show before the spore shooter is in hand.
	_bar_back.visible = me.has_weapon
	var fraction := clampf(me.health / maxf(me.max_health, 1.0), 0.0, 1.0)
	# In 4 px steps, so the bar drops in hard blocks.
	_bar_fill.size.x = floorf((BAR_SIZE.x - 4) * fraction / 4.0) * 4.0
	_bar_label.text = "%d" % ceili(me.health)

	_flash_time = maxf(0.0, _flash_time - delta)
	_flash.visible = _flash_time > 0.0
	_flash_material.set_shader_parameter("amount", ceilf(4.0 * _flash_time / DAMAGE_FLASH_TIME) / 4.0 * 0.5)
	_hit_time = maxf(0.0, _hit_time - delta)
	_hit_marker.visible = _hit_time > 0.0
	_update_ammo(me, delta)
	_update_flask(me)
	_update_vignette(me)
	_update_finale(delta)


func _build_ammo() -> void:
	_ammo_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ammo_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ammo_box.position = Vector2(-16, -16)
	_ammo_box.alignment = BoxContainer.ALIGNMENT_END
	_ammo_box.add_theme_constant_override("separation", 0)
	_ammo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ammo_box)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ammo_box.add_child(row)
	_flask_box.alignment = BoxContainer.ALIGNMENT_END
	_flask_box.add_theme_constant_override("separation", 0)
	_flask_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_flask_box)
	var flask_row := HBoxContainer.new()
	flask_row.add_theme_constant_override("separation", 6)
	flask_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flask_box.add_child(flask_row)
	_flask_name.label_settings = LabHud._settings(16)
	flask_row.add_child(_flask_name)
	_flask_count.label_settings = LabHud._settings(20)
	flask_row.add_child(_flask_count)
	var flask_hint := Label.new()
	flask_hint.text = "Q / RMB"
	flask_hint.label_settings = LabHud._settings(10, Color(0.75, 0.75, 0.75))
	_flask_box.add_child(flask_hint)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(18, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	_ammo_name.label_settings = LabHud._settings(20)
	row.add_child(_ammo_name)
	_ammo_count.label_settings = LabHud._settings(26)
	row.add_child(_ammo_count)
	_ammo_next.label_settings = LabHud._settings(12, Color(0.8, 0.8, 0.8))
	_ammo_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_box.add_child(_ammo_next)

	_ammo_toast.label_settings = LabHud._settings(24)
	_ammo_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_ammo_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ammo_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ammo_toast.position.y += 70
	_ammo_toast.visible = false
	add_child(_ammo_toast)


func _update_ammo(me: Player, delta: float) -> void:
	var weapon: Weapon = me.weapon
	if weapon == null or weapon.ammo == null or not me.has_weapon:
		_ammo_box.visible = false
		_flask_box.visible = false
		return
	_ammo_box.visible = true
	var type := weapon.ammo
	_ammo_name.text = type.label.to_upper()
	if _ammo_name.label_settings.font_color != type.color:
		_ammo_name.label_settings.font_color = type.color
	var rounds: int = me.inventory.count(type.name) if me.inventory else -1
	_ammo_count.text = "∞" if rounds < 0 else str(rounds)
	var next := weapon.next_ammo()
	# SHIFT on keys, Y on a pad.
	var key := "Y" if Pad.active else "SHIFT"
	_ammo_next.text = "" if next == type.name else "%s: %s" % [key, AmmoType.by_name(next).label]
	if _last_ammo != "" and _last_ammo != type.name:
		_ammo_toast.text = type.label
		if _ammo_toast.label_settings.font_color != type.color:
			_ammo_toast.label_settings.font_color = type.color
		_ammo_toast_time = AMMO_TOAST_TIME
	_last_ammo = type.name
	_ammo_toast_time = maxf(0.0, _ammo_toast_time - delta)
	_ammo_toast.visible = _ammo_toast_time > 0.0
	_ammo_toast.modulate.a = clampf(_ammo_toast_time / 0.4, 0.0, 1.0)


## The selected flask's name in its color and how many; hidden when none is carried.
func _update_flask(me: Player) -> void:
	var weapon: Weapon = me.weapon
	var type := AmmoType.flask_type(weapon.flask) if weapon and weapon.flask != "" else null
	_flask_box.visible = type != null and me.inventory != null
	if not _flask_box.visible:
		return
	_flask_name.text = "%s FLASK" % type.label.to_upper()
	if _flask_name.label_settings.font_color != type.color:
		_flask_name.label_settings.font_color = type.color
	_flask_count.text = "x%d" % me.inventory.flask_count(weapon.flask)


## A pulsing edge glow in the color of the strongest status on the player.
func _update_vignette(me: Player) -> void:
	_pixel_blind(me)
	_vignette.visible = false
	for status: String in STATUS_VIGNETTES:
		if me.statuses.has(status):
			# The pulse moves the rings in a block at a time.
			var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.006)
			_vignette.modulate = Color(STATUS_VIGNETTES[status], 1.0)
			_vignette_material.set_shader_parameter("amount", ceilf(pulse * 4.0) / 4.0 * 0.65)
			_vignette_material.set_shader_parameter("inner", 0.5 - 0.1 * ceilf(pulse * 4.0) / 4.0)
			_vignette.visible = true
			return


## The blinded fog (Player's own fullscreen overlay) drawn as a dither of pixel blocks.
func _pixel_blind(me: Player) -> void:
	var fog := me.get_node_or_null("BlindLayer/BlindOverlay") as CanvasItem
	if fog and fog.material != _blind_material:
		fog.material = _blind_material
		PixelFont.nearest(fog)


func _build_finale() -> void:
	_finale_label.label_settings = LabHud._settings(28, FINALE_COLOR, 4)
	_finale_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_finale_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_finale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_finale_label.position.y = 14
	_finale_label.visible = false
	add_child(_finale_label)
	_finale_note.text = "power restoring"
	_finale_note.label_settings = LabHud._settings(16, FINALE_COLOR, 3)
	_finale_note.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_finale_note.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_finale_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_finale_note.position.y = 52
	_finale_note.visible = false
	add_child(_finale_note)
	_banner.label_settings = LabHud._settings(54, FINALE_COLOR, 6)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.position.y -= 120
	_banner.visible = false
	add_child(_banner)
	if lab.director:
		lab.director.finale_event.connect(_on_finale_event)


func _on_finale_event(kind: String) -> void:
	_banner.text = {started = "SURVIVE", survived = "SHIFT SURVIVED", failed = "SHIFT FAILED"}.get(kind, "")
	_banner.label_settings.font_color = Color(0.4, 1.0, 0.5) if kind == "survived" else FINALE_COLOR
	_banner_time = BANNER_TIME


## The finale countdown (the director's replicated timer) and the start/end banner.
func _update_finale(delta: float) -> void:
	var director := lab.director
	_finale_label.visible = director != null and director.finale_active
	_finale_note.visible = _finale_label.visible
	if _finale_label.visible:
		var left := ceili(director.finale_left)
		_finale_label.text = "SURVIVE %d:%02d" % [left / 60, left % 60]
		var pulse := 1.0
		if director.finale_left <= 10.0:
			pulse = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
		_finale_label.modulate.a = pulse
		_finale_note.modulate.a = pulse
	_banner_time = maxf(0.0, _banner_time - delta)
	_banner.visible = _banner_time > 0.0
	_banner.modulate.a = clampf(_banner_time / 0.6, 0.0, 1.0)
