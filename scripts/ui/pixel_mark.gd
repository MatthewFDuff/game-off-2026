class_name PixelMark
extends Control
## A screen-center mark drawn as pixel art: whole-pixel blocks of `block` px (scaled up with the
## window height so it stays chunky), a 1-block black outline, no anti-aliasing. shape "cross" is
## the crosshair (a plus with a gap), "x" the hit marker (four diagonal arms).

@export var shape := "cross"
@export var color := Color.WHITE

## Block cells of the shape around the center cell (0, 0).
var _cells: Array[Vector2i] = []


static func create(mark_shape: String, mark_color := Color.WHITE) -> PixelMark:
	var mark := PixelMark.new()
	mark.shape = mark_shape
	mark.color = mark_color
	return mark


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	match shape:
		"x":
			for i in range(2, 5):
				for s: Vector2i in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
					_cells.append(s * i)
		_:
			_cells.append(Vector2i.ZERO)
			for i in range(2, 5):
				for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					_cells.append(d * i)
	resized.connect(queue_redraw)


## Pixels a block: 3 at 720p, 4-5 at 1080p, at least 2.
func block() -> int:
	return maxi(2, roundi(size.y / 240.0))


func _draw() -> void:
	var b := block()
	var center := Vector2i(floori(size.x * 0.5), floori(size.y * 0.5)) - Vector2i(b, b) / 2
	var outline := Color(0.0, 0.0, 0.0, color.a * 0.8)
	for cell in _cells:
		draw_rect(Rect2(center + cell * b - Vector2i.ONE, Vector2(b + 2, b + 2)), outline, true, -1.0, false)
	for cell in _cells:
		draw_rect(Rect2(center + cell * b, Vector2(b, b)), color, true, -1.0, false)
