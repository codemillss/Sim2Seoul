extends "res://scripts/player/daehanmun_player.gd"
## Stop/slide at eligible-area edges; recovery handles teleports, falls and invalid states.
var step_delta := 1.0/60
var boundary_stops := 0

func _inside(point: Vector3) -> bool:
	return point.is_finite() and connection_world.movement_contains(Vector2(point.x,point.z))

func _physics_process(delta: float) -> void:
	step_delta=delta
	super._physics_process(delta)

func _direction(intent: Vector2) -> Vector3:
	var d: Vector3=super._direction(intent)
	if d.is_zero_approx() or not _inside(global_position):return d
	var speed:=run_speed_mps if router.fast_intent() else walk_speed_mps
	if _inside(global_position+d*speed*step_delta):return d
	boundary_stops+=1
	var along_x:=Vector3(d.x,0,0)
	var along_z:=Vector3(0,0,d.z)
	if not along_x.is_zero_approx() and _inside(global_position+along_x*speed*step_delta):return along_x
	if not along_z.is_zero_approx() and _inside(global_position+along_z*speed*step_delta):return along_z
	return Vector3.ZERO
