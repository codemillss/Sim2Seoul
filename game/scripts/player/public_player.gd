extends "res://scripts/player/palace_player.gd"
## Shared movement/recovery; surface limits report why an intended step was stopped.
var last_boundary_reason := ""
func _direction(intent: Vector2) -> Vector3:
	var before:=boundary_stops
	var result: Vector3=super._direction(intent)
	if boundary_stops==before:
		last_boundary_reason=""
		return result
	var forward: Vector3=-movement_camera.global_basis.z;forward.y=0;forward=forward.normalized()
	var right:=forward.cross(Vector3.UP).normalized()
	var intended: Vector3=(right*intent.x-forward*intent.y).limit_length(1)
	var speed:=run_speed_mps if router.fast_intent() else walk_speed_mps
	var p:=global_position+intended*speed*step_delta
	last_boundary_reason=connection_world.boundary_reason(Vector2(p.x,p.z))
	return result
