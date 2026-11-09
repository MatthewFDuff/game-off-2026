class_name PanelFit
extends RefCounted
## Keeps the HUD's floating panels (the reader, the intercom and cubicle subtitles, the controls
## sheet, the pause panel, the cubicle's reader, email and clock-out prompt) inside the viewport.
## A word-wrapped Label reports the minimum height of its text wrapped at the width it last had, so
## a panel sized from it before it was laid out took the height of one word per line (the intercom's
## first line came out 1945 px tall, its top far above the screen: the 2026-11-06 play-test).
## wrap() lays such a label out at its real width first; body_cap() gives a scrolling body the
## height left over; place() and center() size a panel to its contents and clamp it on screen.

## Pixels kept between a panel and the viewport's edges.
const MARGIN := 12.0


## Sets an autowrapped label's width and lays its text out at it, so its minimum height is the
## wrapped text's; returns that height.
static func wrap(label: Label, width: float) -> float:
	label.custom_minimum_size.x = width
	label.size = Vector2(width, label.size.y)
	# The resize reshapes the text, but the cached minimum (the label's and its parents') stays
	# the old one until told.
	label.update_minimum_size()
	return label.get_combined_minimum_size().y


## The most a panel's scrolling body may take: the viewport's height (times share) less the
## panel's other contents (chrome: title, hint, margins) and the margins, at least floor.
static func body_cap(viewport: Vector2, chrome: float, share := 1.0, floor := 80.0) -> float:
	return maxf(floor, viewport.y * share - chrome - 2.0 * MARGIN)


## A position for a rect of size near wanted that keeps it inside viewport with margin on every side
## (the top-left corner wins when it can't fit: its title stays readable).
static func clamp_position(wanted: Vector2, size: Vector2, viewport: Vector2, margin := MARGIN) -> Vector2:
	var most := (viewport - size - Vector2(margin, margin)).max(Vector2(margin, margin))
	return wanted.clamp(Vector2(margin, margin), most)


## Sizes panel to its contents and puts its top-left at wanted, clamped inside its viewport.
static func place(panel: Control, wanted: Vector2, margin := MARGIN) -> void:
	var viewport := panel.get_viewport_rect().size
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var size := panel.get_combined_minimum_size()
	panel.size = size
	panel.position = clamp_position(wanted, size, viewport, margin)


## Sizes panel to its contents and centers it in its viewport, clamped inside it.
static func center(panel: Control, margin := MARGIN) -> void:
	var viewport := panel.get_viewport_rect().size
	place(panel, (viewport - panel.get_combined_minimum_size()) * 0.5, margin)
