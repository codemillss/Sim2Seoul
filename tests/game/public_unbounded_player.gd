extends "res://scripts/player/public_player.gd"
## Test-only actual faulty controller: no centre-domain stop/recovery guard.
func _inside(point: Vector3) -> bool:return point.is_finite()
func _direction(intent: Vector2) -> Vector3:
	var forward: Vector3=-movement_camera.global_basis.z;forward.y=0;forward=forward.normalized()
	var right:=forward.cross(Vector3.UP).normalized()
	return (right*intent.x-forward*intent.y).limit_length(1)
