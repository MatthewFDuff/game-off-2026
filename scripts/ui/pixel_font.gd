class_name PixelFont
extends RefCounted
## The game's pixel font: Silkscreen (Jason Kottke, SIL Open Font License; assets/ui/fonts), designed
## on an 8 px grid, so it is drawn only at whole multiples of 8 px and every glyph pixel is a square
## block. HUD text gets it through settings() (LabHud._settings, the intro's labels); the nodes
## showing it draw with nearest filtering (nearest()). Characters it lacks fall back to the
## engine's default font.

## Pixels a line.
const SIZE := 8
const ASCENT := 7

static var _font: FontFile
static var _theme: Theme


## The font (loaded once).
static func font() -> FontFile:
	if _font:
		return _font
	var f: FontFile = load("res://assets/ui/fonts/Silkscreen-Regular.ttf").duplicate()
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.multichannel_signed_distance_field = false
	f.generate_mipmaps = false
	f.force_autohinter = false
	f.oversampling = 1.0
	f.fallbacks = [ThemeDB.fallback_font]
	_font = f
	return f


## A font size on the pixel grid: the nearest whole multiple of SIZE, at least minimum times.
static func snap(size: int, minimum := 2) -> int:
	return SIZE * maxi(minimum, roundi(float(size) / SIZE))


## Label settings in the pixel font at about size px: a hard one-block drop shadow stands in for an
## outline (outline > 0), since pixel glyphs have no outline.
static func settings(size: int, color := Color.WHITE, outline := 5, minimum := 2) -> LabelSettings:
	var s := LabelSettings.new()
	s.font = font()
	s.font_size = snap(size, minimum)
	s.font_color = color
	if outline > 0:
		var block := s.font_size / SIZE
		s.shadow_size = 0
		s.shadow_color = Color(0.0, 0.0, 0.0, 0.85)
		s.shadow_offset = Vector2(block, block)
	return s


## A theme whose default font is the pixel font at 16 px (buttons, panels' plain labels).
static func theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_theme.default_font = font()
		_theme.default_font_size = SIZE * 2
	return _theme


## Nearest filtering for a canvas item and (by inheritance) everything under it, so pixel text and
## shapes stay hard-edged when the window scales the canvas.
## Controls without a theme also get theme(), so their buttons use the pixel font.
static func nearest(item: CanvasItem) -> void:
	item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if item is Control and (item as Control).theme == null:
		(item as Control).theme = theme()
