extends Node
## Camera-relative movement will be implemented in P01/P02; this returns intent only.
signal menu_toggle_requested
var gameplay_enabled := true

func movement_intent() -> Vector2:
	if not gameplay_enabled:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

func fast_intent() -> bool:
	return gameplay_enabled and Input.is_action_pressed("move_fast")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_menu") and not event.is_echo():
		menu_toggle_requested.emit()
		get_viewport().set_input_as_handled()
