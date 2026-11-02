extends CanvasLayer
## The in-game HUD. Top centre: phase title, objective line, and at night a big timer and shroom
## counts. Top right: money and quota progress. Bottom left: health bar with the blast-charge count
## above it. Also the interaction prompt, director messages, crosshair hit markers, damage-direction
## wedges, the objective marker, the build-mode piece bar, the dawn shift summary and the game-over
## summary. Everything except the crosshair and capture hint is built in code.

@export var director: ShiftDirector
@export var state: GameState
@export var player: Player
@export var plant_tool: PlantTool
@export var shrooms: ShroomManager
@export var weapons: SandboxTools
## Read for the build bar and invalid-placement reason. Found through the director when unset.
@export var build_tool: BuildTool

const AMBER := Color(1.0, 0.72, 0.25)
const RED := Color(1.0, 0.3, 0.25)
const PROMPT_COLOR := Color(1.0, 0.95, 0.7)
const GREEN := Color(0.65, 1.0, 0.55)
const HURT_SECONDS := 0.6
const HIT_SECONDS := 0.12
const KILL_SECONDS := 0.22
## The objective marker hides when the player is this close to its target.
const MARKER_HIDE_DISTANCE := 2.5
## Keeps the edge arrow clear of the screen edges and the top-centre and top-right blocks.
const MARKER_MARGIN_SIDE := 48.0
const MARKER_MARGIN_TOP := 130.0
const MARKER_MARGIN_TOP_NIGHT := 200.0
const MARKER_MARGIN_BOTTOM := 60.0

@onready var crosshair: Label = $Crosshair
@onready var capture_hint: Label = $CaptureHint

var _phase := Label.new()
var _objective := Label.new()
var _timer := Label.new()
var _night_status := Label.new()
var _ping := Label.new()
var _money := Label.new()
var _progress := Label.new()
var _message := Label.new()
var _prompt := Label.new()
var _invalid := Label.new()
var _hurt := ColorRect.new()
## Draws the hit marker and damage wedges.
var _overlay := Control.new()
## Draws the objective marker: a diamond over the target, or an arrow at the screen edge.
var _marker := Control.new()
var _marker_font: Font = ThemeDB.fallback_font

var _health_bar := Control.new()
var _health_fill := ColorRect.new()
var _health_shimmer := ColorRect.new()
var _health_text := Label.new()
var _last_health := -1.0
var _regen_time := 0.0

var _build_bar := HBoxContainer.new()
var _build_slots: Array[PanelContainer] = []
var _slot_style := StyleBoxFlat.new()
var _slot_selected_style := StyleBoxFlat.new()

var _game_over := PanelContainer.new()
var _game_over_body := Label.new()

var _dawn := PanelContainer.new()
var _dawn_title := Label.new()
## Two columns: what was paid for, and how much.
var _dawn_rows := GridContainer.new()
var _dawn_next := Label.new()
var _dawn_continue := Label.new()

var _blasts := Label.new()

var _message_time := 0.0
var _ping_time := 0.0
var _hit_time := 0.0
var _hit_killed := false
## Recent hits on the player: {from: Vector3, time: float}.
var _damage: Array = []
var _clock := 0.0


static func _settings(size: int, color := Color.WHITE, outline := 5) -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font_size = size
	settings.font_color = color
	settings.outline_size = outline
	settings.outline_color = Color.BLACK
	return settings


func _ready() -> void:
	if not build_tool and director:
		build_tool = director.build_tool

	_hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt.color = Color(0.8, 0.0, 0.0, 0.0)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hurt)
	move_child(_hurt, 0)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	add_child(_marker)
	move_child(_marker, _overlay.get_index())

	# Top centre: title, objective, night timer, night status, uproot ping.
	_add_centered(_phase, _settings(30), 10.0)
	_add_centered(_objective, _settings(20, PROMPT_COLOR), 50.0)
	_add_centered(_timer, _settings(52, Color.WHITE, 8), 76.0)
	_add_centered(_night_status, _settings(20), 142.0)
	_add_centered(_ping, _settings(20, AMBER), 168.0)

	# Top right: money and quota progress.
	for label: Label in [_money, _progress]:
		add_child(label)
		label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_money.label_settings = _settings(30, GREEN)
	_progress.label_settings = _settings(22)
	_progress.position.y += 42.0

	# Director messages, above the build bar.
	_message.label_settings = _settings(22)
	add_child(_message)
	_message.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_message.offset_top = -120.0
	_message.offset_bottom = -120.0
	_message.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Interaction prompt and invalid-placement reason, under the crosshair.
	_add_under_crosshair(_prompt, _settings(22, PROMPT_COLOR), 40.0)
	_add_under_crosshair(_invalid, _settings(20, RED), 72.0)

	_build_health_bar()
	_build_build_bar()
	_build_game_over()
	_build_dawn()

	if director:
		director.message_posted.connect(_show_message)
		director.phase_changed.connect(func(_phase_value: ShiftDirector.Phase) -> void:
			_update_game_over()
			_update_dawn())
	if player:
		player.damaged.connect(_on_player_damaged)
	if shrooms:
		shrooms.harvested.connect(_on_harvested)
		shrooms.spore_matured.connect(_on_spore_matured)
	if weapons:
		weapons.shroom_hit.connect(_on_shroom_hit)
		weapons.blasts_changed.connect(_on_blasts_changed)
		weapons.blast_refused.connect(func(reason: String) -> void: _show_message(reason, 2.0))
	if build_tool:
		build_tool.toggle_refused.connect(func() -> void: _show_message("Can't build during the night shift", 2.0))


func _add_centered(label: Label, settings: LabelSettings, top: float) -> void:
	label.label_settings = settings
	add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	label.offset_top = top
	label.offset_bottom = top
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _add_under_crosshair(label: Label, settings: LabelSettings, offset: float) -> void:
	label.label_settings = settings
	add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_HCENTER_WIDE)
	label.offset_top = offset
	label.offset_bottom = offset
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_health_bar() -> void:
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_bar.clip_contents = true
	add_child(_health_bar)
	_health_bar.anchor_top = 1.0
	_health_bar.anchor_bottom = 1.0
	_health_bar.offset_left = 16.0
	_health_bar.offset_right = 296.0
	_health_bar.offset_top = -50.0
	_health_bar.offset_bottom = -18.0

	var back := ColorRect.new()
	back.color = Color(0.0, 0.0, 0.0, 0.6)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for rect: ColorRect in [back, _health_fill, _health_shimmer]:
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_health_bar.add_child(rect)
	_health_fill.position = Vector2(2, 2)
	_health_shimmer.color = Color(1.0, 1.0, 1.0, 0.0)
	_health_text.label_settings = _settings(20)
	_health_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_health_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_health_bar.add_child(_health_text)

	# Blast charges, just above the health bar.
	_blasts.label_settings = _settings(22)
	add_child(_blasts)
	_blasts.anchor_top = 1.0
	_blasts.anchor_bottom = 1.0
	_blasts.offset_left = 18.0
	_blasts.offset_top = -84.0
	_blasts.offset_bottom = -54.0
	_blasts.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM


func _build_build_bar() -> void:
	_slot_style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	_slot_style.set_corner_radius_all(6)
	_slot_style.set_content_margin_all(8)
	_slot_style.set_border_width_all(2)
	_slot_style.border_color = Color(1.0, 1.0, 1.0, 0.15)
	_slot_selected_style = _slot_style.duplicate()
	_slot_selected_style.bg_color = Color(0.25, 0.2, 0.05, 0.75)
	_slot_selected_style.border_color = AMBER

	_build_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_bar.add_theme_constant_override("separation", 6)
	add_child(_build_bar)
	_build_bar.anchor_left = 0.5
	_build_bar.anchor_right = 0.5
	_build_bar.anchor_top = 1.0
	_build_bar.anchor_bottom = 1.0
	_build_bar.offset_bottom = -14.0
	_build_bar.offset_top = -14.0
	# Nudged right of centre so it clears the health bar.
	_build_bar.offset_left = 90.0
	_build_bar.offset_right = 90.0
	_build_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_build_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var slot_text := _settings(18, Color.WHITE, 4)
	for i in BuildPieces.PIECES.size():
		var piece: Dictionary = BuildPieces.PIECES[i]
		var slot := PanelContainer.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.custom_minimum_size.x = 110.0
		var label := Label.new()
		label.label_settings = slot_text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text = "%d  %s\n$%d" % [i + 1, piece.name, piece.cost]
		slot.add_child(label)
		_build_bar.add_child(slot)
		_build_slots.append(slot)
	var turn := Label.new()
	turn.label_settings = slot_text
	turn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turn.size_flags_vertical = Control.SIZE_FILL
	turn.text = " [R] turn\n [Q] exit"
	_build_bar.add_child(turn)
	_build_bar.visible = false


func _build_game_over() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.02, 0.02, 0.82)
	style.border_color = Color(0.7, 0.15, 0.1)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(32)
	_game_over.add_theme_stylebox_override("panel", style)
	_game_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	var title := Label.new()
	title.label_settings = _settings(40, RED, 6)
	title.text = "GAME OVER"
	_game_over_body.label_settings = _settings(22)
	var restart := Label.new()
	restart.label_settings = _settings(24, AMBER)
	restart.text = "Press [R] to restart"
	for label: Label in [title, _game_over_body, restart]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
	_game_over.add_child(column)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_game_over)
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_over.visible = false


func _build_dawn() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.02, 0.82)
	style.border_color = Color(0.45, 0.75, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(32)
	_dawn.add_theme_stylebox_override("panel", style)
	_dawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_dawn_title.label_settings = _settings(40, GREEN, 6)
	_dawn_rows.columns = 2
	_dawn_rows.add_theme_constant_override("h_separation", 48)
	_dawn_rows.add_theme_constant_override("v_separation", 6)
	_dawn_rows.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_dawn_next.label_settings = _settings(22, PROMPT_COLOR)
	_dawn_continue.label_settings = _settings(24, AMBER)
	column.add_child(_dawn_title)
	column.add_child(_dawn_rows)
	column.add_child(_dawn_next)
	column.add_child(_dawn_continue)
	for label: Label in [_dawn_title, _dawn_next, _dawn_continue]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dawn.add_child(column)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_dawn)
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Centred between the top block and the message line, so "Power restored." stays readable.
	center.offset_top = 90.0
	center.offset_bottom = -130.0
	_dawn.visible = false


## Shows the shift summary while the director holds at dawn, filled from this shift's tallies.
func _update_dawn() -> void:
	var dawn := director != null and director.phase == ShiftDirector.Phase.DAWN and state != null
	_dawn.visible = dawn
	if not dawn:
		return
	var reward := shrooms.harvest_reward if shrooms else 0
	var survived := state.shift - 1
	_dawn_title.text = "SHIFT %d SURVIVED" % survived
	for child in _dawn_rows.get_children():
		child.queue_free()
	var quota_harvests := state.shift_harvested - state.shift_extra
	_add_dawn_row("Harvested %d × $%d" % [quota_harvests, reward], "$%d" % (quota_harvests * reward))
	if state.shift_extra > 0:
		_add_dawn_row("Extra harvests %d × $%d" % [state.shift_extra, reward], "$%d" % (state.shift_extra * reward))
	_add_dawn_row("Survival bonus", "$%d" % director.survival_bonus)
	_add_dawn_row("Total", "+$%d" % state.shift_earned, true)
	_dawn_next.text = "Next shift: plant and harvest %d" % director.quota_for(state.shift)
	_update_dawn_countdown()


func _add_dawn_row(what: String, amount: String, total := false) -> void:
	var left := Label.new()
	var right := Label.new()
	left.label_settings = _settings(26 if total else 22, AMBER if total else Color.WHITE)
	right.label_settings = _settings(26 if total else 22, GREEN)
	left.text = what
	right.text = amount
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dawn_rows.add_child(left)
	_dawn_rows.add_child(right)


func _update_dawn_countdown() -> void:
	_dawn_continue.text = "Press [E] to start day %d (or wait %d s)" % [state.shift, maxi(0, ceili(director.dawn_time_left))]


func _update_game_over() -> void:
	var over := director != null and director.phase == ShiftDirector.Phase.GAME_OVER
	_game_over.visible = over
	if not over or not state:
		return
	_game_over_body.text = "%s\n\nShifts survived: %d\nShrooms harvested: %d\nMoney earned: $%d" % [
		director.game_over_cause, state.shift - 1, state.total_harvested, state.total_earned]


func _show_message(text: String, seconds: float) -> void:
	_message.text = text
	_message_time = seconds


func _on_player_damaged(_amount: float, from: Vector3) -> void:
	_hurt.color.a = 0.18
	_damage.append({from = from, time = HURT_SECONDS})
	if _damage.size() > 6:
		_damage.pop_front()


func _on_shroom_hit(killed: bool) -> void:
	_hit_killed = killed
	_hit_time = KILL_SECONDS if killed else HIT_SECONDS


func _on_blasts_changed(_count: int) -> void:
	_blasts.pivot_offset = Vector2(0.0, _blasts.size.y * 0.5)
	var pulse := _blasts.create_tween()
	pulse.tween_property(_blasts, "scale", Vector2.ONE * 1.3, 0.08)
	pulse.tween_property(_blasts, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_blasts(hidden: bool) -> void:
	_blasts.visible = weapons != null and not hidden
	if not _blasts.visible:
		return
	var count := weapons.blast_charges
	var text := "Blast ×%d" % count
	if director and director.phase == ShiftDirector.Phase.DAY:
		text += "   [B] +1 for $%d" % weapons.blast_cost
	_blasts.text = text
	_blasts.modulate = RED if count <= 0 else Color.WHITE


func _on_spore_matured(_shroom: Shroom) -> void:
	_ping.text = "A shroom has uprooted!"
	_ping_time = 1.8
	_night_status.modulate = Color(2.0, 1.4, 0.6)


func _on_harvested(_shroom: Shroom) -> void:
	var reward := shrooms.harvest_reward if shrooms else 0
	var floater := Label.new()
	floater.label_settings = _settings(28, Color(0.65, 1.0, 0.55), 6)
	floater.text = "+$%d" % reward
	add_child(floater)
	floater.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	floater.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	floater.position.y = 112.0
	var rise := floater.create_tween().set_parallel()
	rise.tween_property(floater, "position:y", 52.0, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	rise.tween_property(floater, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN)
	rise.chain().tween_callback(floater.queue_free)

	_progress.pivot_offset = Vector2(_progress.size.x, _progress.size.y * 0.5)
	var pulse := _progress.create_tween()
	pulse.tween_property(_progress, "scale", Vector2.ONE * 1.35, 0.08)
	pulse.tween_property(_progress, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_clock += delta
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var over := director != null and director.phase == ShiftDirector.Phase.GAME_OVER
	# A summary panel is up: no crosshair, prompts or marker over it.
	var panel := over or _dawn.visible
	crosshair.visible = captured and not panel
	capture_hint.visible = not captured and not panel
	if _dawn.visible:
		_update_dawn_countdown()

	_message_time -= delta
	_message.visible = _message_time > 0.0 and not over
	_hurt.color.a = move_toward(_hurt.color.a, 0.0, delta * 0.5)
	_ping_time -= delta
	_ping.visible = _ping_time > 0.0
	_night_status.modulate = _night_status.modulate.lerp(Color.WHITE, minf(1.0, delta * 3.0))

	_phase.visible = not over
	_objective.visible = not over
	_update_top(delta)
	_update_prompt(captured and not panel)
	_update_health(delta)
	_update_blasts(over)
	_update_build()
	_marker.visible = not panel

	_hit_time -= delta
	for hit in _damage:
		hit.time -= delta
	_damage = _damage.filter(func(hit: Dictionary) -> bool: return hit.time > 0.0)
	_overlay.queue_redraw()
	_marker.queue_redraw()


func _update_top(_delta: float) -> void:
	var night := false
	if director:
		var title := director.get_phase_name()
		if director.phase == ShiftDirector.Phase.DAY and state:
			title += " %d" % state.shift
		_phase.text = title
		_objective.text = director.get_objective()
		night = director.phase == ShiftDirector.Phase.NIGHT
	_timer.visible = night
	_night_status.visible = night and shrooms != null
	if night:
		var left := director.night_time_left
		var t := maxi(0, ceili(left))
		_timer.text = "%d:%02d" % [t / 60, t % 60]
		var color := Color.WHITE
		var pulse := 1.0
		if left <= 10.0:
			var beat := 0.5 + 0.5 * sin(_clock * TAU * 2.0)
			color = RED.lerp(Color(1.0, 0.6, 0.55), beat)
			pulse = 1.0 + 0.1 * beat
		elif left <= 30.0:
			color = AMBER
		_timer.modulate = color
		_timer.pivot_offset = _timer.size * 0.5
		_timer.scale = Vector2.ONE * pulse
		if shrooms:
			_night_status.text = "Growing %d  ·  Hunting %d" % [shrooms.growing(), shrooms.hunting()]
	if state:
		_money.text = "$%d" % state.money
		var progress := "Planted %d / %d" % [state.planted, state.quota]
		if director and director.phase >= ShiftDirector.Phase.CLOSING and director.phase <= ShiftDirector.Phase.DAWN:
			progress = "Harvested %d / %d" % [state.harvested, state.quota]
		_progress.text = progress
		var met := state.harvested >= state.quota if director and director.phase >= ShiftDirector.Phase.CLOSING \
				else state.planted >= state.quota
		_progress.modulate = Color(0.65, 1.0, 0.55) if met else Color.WHITE


func _update_prompt(can_show: bool) -> void:
	var prompt := director.get_prompt() if director else ""
	if prompt.is_empty() and plant_tool:
		prompt = plant_tool.get_prompt()
	_prompt.text = prompt
	_prompt.visible = can_show and not prompt.is_empty()
	var reason := build_tool.get_invalid_reason() if build_tool and build_tool.active else ""
	_invalid.text = reason
	_invalid.visible = can_show and not reason.is_empty()


func _update_health(delta: float) -> void:
	if not player:
		_health_bar.visible = false
		return
	var fraction := clampf(player.health / player.max_health, 0.0, 1.0)
	var inner := _health_bar.size - Vector2(4, 4)
	_health_fill.size = Vector2(inner.x * fraction, inner.y)
	var color := Color(0.35, 0.85, 0.35)
	if fraction <= 0.35:
		color = Color(0.9, 0.2, 0.15)
	elif fraction <= 0.6:
		color = Color(0.95, 0.7, 0.2)
	_health_text.text = "HP %d" % ceili(player.health)

	# Regen shimmer: a soft highlight sweeping along the fill while health is rising.
	if _last_health >= 0.0 and player.health > _last_health + 0.0001:
		_regen_time = 0.25
	_last_health = player.health
	_regen_time -= delta
	var regen := _regen_time > 0.0
	_health_fill.color = color.lightened(0.15 * (0.5 + 0.5 * sin(_clock * 6.0))) if regen else color
	_health_shimmer.color.a = move_toward(_health_shimmer.color.a, 0.35 if regen else 0.0, delta * 3.0)
	var sweep := 48.0
	_health_shimmer.size = Vector2(sweep, inner.y)
	_health_shimmer.position = Vector2(2.0 + fmod(_clock * 160.0, maxf(1.0, _health_fill.size.x + sweep)) - sweep, 2.0)


func _update_build() -> void:
	var shown := build_tool != null and build_tool.active
	_build_bar.visible = shown
	if not shown:
		return
	for i in _build_slots.size():
		var style := _slot_selected_style if i == build_tool.piece_index else _slot_style
		_build_slots[i].add_theme_stylebox_override("panel", style)


func _draw_overlay() -> void:
	var center := _overlay.size * 0.5
	if _hit_time > 0.0:
		var gap := 9.0 if _hit_killed else 7.0
		var length := 10.0 if _hit_killed else 6.0
		var width := 3.0 if _hit_killed else 2.0
		var color := RED if _hit_killed else Color.WHITE
		for corner: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			var d := corner.normalized()
			_overlay.draw_line(center + d * gap, center + d * (gap + length), color, width, true)

	if not player:
		return
	var radii := center - Vector2(20, 20)
	for hit in _damage:
		var local: Vector3 = player.global_basis.inverse() * (hit.from - player.global_position)
		# 0 is straight ahead (top of the screen), increasing clockwise.
		var angle := atan2(local.x, -local.z)
		var alpha: float = clampf(hit.time / HURT_SECONDS, 0.0, 1.0) * 0.8
		var outer := PackedVector2Array()
		var inner := PackedVector2Array()
		var steps := 10
		for i in steps + 1:
			var a := angle + lerpf(-0.32, 0.32, float(i) / steps)
			var dir := Vector2(sin(a), -cos(a))
			outer.append(center + dir * radii)
			inner.append(center + dir * (radii - Vector2(34, 34)))
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		for p in outer:
			points.append(p)
			colors.append(Color(1.0, 0.1, 0.05, alpha))
		for i in range(inner.size() - 1, -1, -1):
			points.append(inner[i])
			colors.append(Color(1.0, 0.1, 0.05, 0.0))
		_overlay.draw_polygon(points, colors)


func _draw_marker() -> void:
	if not director or not player or not player.camera:
		return
	var target := director.get_objective_target()
	if target.is_empty():
		return
	var world_pos: Vector3 = target.position
	var distance := player.global_position.distance_to(world_pos)
	if distance <= MARKER_HIDE_DISTANCE:
		return
	var camera := player.camera
	var dim: bool = target.get("dim", false)
	var color := Color(0.75, 1.0, 0.6, 0.6) if dim else AMBER
	var outline := Color(0.0, 0.0, 0.0, color.a * 0.8)
	var text := "%s  ·  %d m" % [target.label, roundi(distance)]
	var font_size := 16 if dim else 18

	var screen_size := _marker.size
	var top := MARKER_MARGIN_TOP_NIGHT if director.phase == ShiftDirector.Phase.NIGHT else MARKER_MARGIN_TOP
	var bounds := Rect2(Vector2(MARKER_MARGIN_SIDE, top), screen_size - Vector2(MARKER_MARGIN_SIDE * 2.0, top + MARKER_MARGIN_BOTTOM))
	var behind := camera.is_position_behind(world_pos)
	var screen := camera.unproject_position(world_pos)
	if not behind and bounds.has_point(screen):
		# On screen: a diamond over the target, the label above it.
		var r := 7.0 if dim else 9.0
		var diamond := PackedVector2Array([screen + Vector2(0, -r), screen + Vector2(r, 0), screen + Vector2(0, r), screen + Vector2(-r, 0)])
		var closed := diamond.duplicate()
		closed.append(diamond[0])
		_marker.draw_polyline(closed, outline, 5.0, true)
		_marker.draw_colored_polygon(diamond, Color(color, color.a * 0.35))
		_marker.draw_polyline(closed, color, 2.0, true)
		_draw_marker_text(text, screen + Vector2(0, -r - 8.0), font_size, color, outline)
		return

	# Off screen: an arrow on the edge of the bounds, pointing the way to turn. In front, camera-space
	# x/y match the screen. Behind, the projection flips, so map it top-down instead: behind is down,
	# leaning towards the side to turn to.
	var local := camera.global_transform.affine_inverse() * world_pos
	var dir := Vector2(local.x, -local.y)
	if behind or local.z > 0.0:
		dir = Vector2(local.x, local.z)
	if dir.length_squared() < 0.0001:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var center := bounds.get_center()
	var half := bounds.size * 0.5
	var reach := minf(half.x / maxf(absf(dir.x), 0.0001), half.y / maxf(absf(dir.y), 0.0001))
	var tip := center + dir * reach
	var side := Vector2(-dir.y, dir.x)
	var length := 18.0 if dim else 22.0
	var width := 10.0 if dim else 13.0
	var base := tip - dir * length
	var arrow := PackedVector2Array([tip, base + side * width, base + dir * length * 0.3, base - side * width])
	var closed_arrow := arrow.duplicate()
	closed_arrow.append(arrow[0])
	_marker.draw_polyline(closed_arrow, outline, 5.0, true)
	_marker.draw_colored_polygon(arrow, color)
	# Label tucked inside the arrow, towards the screen centre. Arrows along the bottom put it beside
	# them instead, clear of the message line above.
	var text_size := _marker_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var anchor := base - dir * (12.0 + absf(dir.x) * text_size.x * 0.5 + absf(dir.y) * text_size.y * 0.5)
	if dir.y > 0.7:
		var beside := 1.0 if tip.x + width + 12.0 + text_size.x < bounds.end.x else -1.0
		anchor = Vector2(tip.x + beside * (width + 10.0 + text_size.x * 0.5), tip.y - 6.0)
	_draw_marker_text(text, anchor + Vector2(0, text_size.y * 0.5), font_size, color, outline)


## Draws text centred horizontally on `bottom_center`, with its baseline-ish bottom there.
func _draw_marker_text(text: String, bottom_center: Vector2, font_size: int, color: Color, outline: Color) -> void:
	var text_size := _marker_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var at := bottom_center + Vector2(-text_size.x * 0.5, -_marker_font.get_descent(font_size))
	_marker.draw_string_outline(_marker_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, outline)
	_marker.draw_string(_marker_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
