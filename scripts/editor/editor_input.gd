class_name EditorInput
extends RefCounted
## Who gets the level editor's input. Highest first, and each layer keeps what it uses:
##   1. modals (help, menu, confirm): everything
##   2. a focused text field: every key (Enter commits, Esc reverts; both let go of it)
##   3. the mouse over editor UI: clicks and the wheel go to the panel, never the world
##   4. tool and editor shortcuts
##   5. camera and movement
## The GUI already eats clicks on controls, but polled input (Input.is_action_pressed) and keys
## don't care what the mouse is over, which is how Space in a menu used to fly you up. Anything
## that reads world input while editing asks here first.
##
## Static, like Puzzle Pals' ModalGate: a list and some questions, with no lifecycle. Freed owners
## are pruned, so a modal freed with its scene can't leave the editor deaf.

static var _modals: Array[Object] = []
## The editor HUD's root; "over UI" means over a control inside it.
static var ui_root: Control


static func open_modal(owner: Object) -> void:
	_prune()
	if owner != null and not _modals.has(owner):
		_modals.append(owner)


static func close_modal(owner: Object) -> void:
	_modals.erase(owner)
	_prune()


static func modal_open() -> bool:
	_prune()
	return not _modals.is_empty()


static func text_focused() -> bool:
	var focused := _viewport().gui_get_focus_owner() if _viewport() else null
	return focused is LineEdit or focused is TextEdit


## True while keys belong to the UI (a modal or a text field), so the world mustn't read them.
static func blocks_keyboard() -> bool:
	return modal_open() or text_focused()


## The free mouse is over an editor panel.
static func pointer_over_ui() -> bool:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not is_instance_valid(ui_root) or not ui_root.is_visible_in_tree():
		return false
	var hovered := _viewport().gui_get_hovered_control()
	return hovered != null and (hovered == ui_root or ui_root.is_ancestor_of(hovered))


## Whether a world-side handler (tool, camera) may use this event.
static func world_may_use(event: InputEvent) -> bool:
	if modal_open():
		return false
	if event is InputEventKey:
		return not text_focused()
	if event is InputEventMouseButton:
		return not pointer_over_ui()
	return true


static func _viewport() -> Viewport:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root if tree else null


static func _prune() -> void:
	for i in range(_modals.size() - 1, -1, -1):
		if not is_instance_valid(_modals[i]):
			_modals.remove_at(i)
