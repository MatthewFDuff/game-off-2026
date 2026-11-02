extends CanvasLayer
## Crosshair while the mouse is captured, a prompt to click in while it isn't.

@onready var crosshair: Label = $Crosshair
@onready var capture_hint: Label = $CaptureHint


func _process(_delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	crosshair.visible = captured
	capture_hint.visible = not captured
