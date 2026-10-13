extends "res://scripts/input_router.gd"
## Only automatic test copies use this helper. Normal play keeps authored bindings.
var movement_bindings: Array[InputEvent]=[]
var external_movement_events := 0
func isolate_movement_bindings() -> void:
	for action in ["move_left","move_right","move_forward","move_backward","move_fast"]:
		movement_bindings.append_array(InputMap.action_get_events(action))
		InputMap.action_erase_events(action)
		Input.action_release(action)
func _input(event: InputEvent) -> void:
	# Aggregate gameplay-binding events only; never record raw user keys or text.
	if event is InputEventKey and not event.get_meta("w01_probe",false):
		for binding in movement_bindings:
			if binding.is_match(event):
				external_movement_events+=1
				break
func _unhandled_input(event: InputEvent) -> void:
	if event.get_meta("w01_probe",false):super._unhandled_input(event)
