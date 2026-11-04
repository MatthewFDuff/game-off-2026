class_name PaperPalette
extends RefCounted
## The colour tokens of the level editor's paper UI (ported from Puzzle Pals, with a dark
## blue-gray accent), for code that builds its own styles. Controls take their look from
## res://assets/ui/editor_theme.tres through a theme type variation; reach for these only where the
## theme can't, such as a stylebox tinted by a player's color. The values match the theme's, so
## change both together.

## Surfaces.
const PAPER := Color(0.984, 0.973, 0.949)
const PAPER_RAISED := Color(1.0, 0.992, 0.976)
const WELL := Color(0.953, 0.933, 0.898)
const WELL_DEEP := Color(0.91, 0.878, 0.824)

## Edges.
const RIM := Color(0.925, 0.902, 0.855)
const RIM_STRONG := Color(0.89, 0.855, 0.792)
const RIM_HOVER := Color(0.839, 0.784, 0.69)

## Text.
const INK := Color(0.078, 0.196, 0.247)
const INK_MUTED := Color(0.369, 0.486, 0.545)
const INK_FAINT := Color(0.588, 0.663, 0.702)

## The editor's dark blue-gray.
const ACCENT := Color(0.169, 0.271, 0.325)
const ACCENT_LIGHT := Color(0.227, 0.345, 0.408)
const ACCENT_DARK := Color(0.11, 0.188, 0.231)
const ACCENT_TITLE := Color(0.133, 0.224, 0.29)
const ACCENT_WASH := Color(0.882, 0.906, 0.918)

## States.
const FOCUS := Color(0.95, 0.68, 0.16)
const DANGER := Color(0.702, 0.153, 0.153)
const SUCCESS := Color(0.129, 0.475, 0.259)
const WARNING := Color(0.722, 0.459, 0.118)

## The drop shadow under paper, and its offset.
const SHADOW := Color(0.09, 0.19, 0.25, 0.22)
const SHADOW_OFFSET := Vector2(0, 4)
## Behind modals.
const SCRIM := Color(0.078, 0.196, 0.247, 0.5)

const RIM_SHEET := 5
const RIM_TILE := 3
const RADIUS_SHEET := 18
const RADIUS_TILE := 12
const RADIUS_CHIP := 10


## A paper stylebox like the theme's PaperCard, for code that needs its own (to tint its rim, say).
static func card(radius := RADIUS_SHEET, rim := RIM_SHEET) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PAPER
	box.border_color = RIM
	box.set_border_width_all(rim)
	box.set_corner_radius_all(radius)
	box.shadow_color = SHADOW
	box.shadow_size = 1
	box.shadow_offset = SHADOW_OFFSET
	box.set_content_margin_all(6.0)
	return box
