extends "res://scripts/player/idle_support.gd"
## P02 movement in metres; visual heading is separate from capsule orientation.
@export var input_router_path: NodePath
@export var camera_path: NodePath
@export var walk_speed_mps := 1.4
@export var run_speed_mps := 3.5
@export var turn_speed_radians := TAU
@export var fall_limit_y := -3.0
var allowed_regions: Array[Rect2] = []
var spawn_transform := Transform3D.IDENTITY
var configured := false
var spawn_valid := false
var input_latched := false
var recoveries := 0
var last_recovery_reason := ""
var last_direction := Vector3.ZERO
@onready var router: Node = get_node(input_router_path)
@onready var movement_camera: Camera3D = get_node(camera_path)
@onready var visual: Node3D = $Visual

func configure_recovery(point: Vector3, regions: Array[Rect2]) -> void:
	spawn_transform = Transform3D(Basis.IDENTITY,point)
	allowed_regions = regions
	configured = true
	spawn_valid = false

func _inside(point: Vector3) -> bool:
	if not point.is_finite():return false
	for region in allowed_regions:
		if region.has_point(Vector2(point.x,point.z)):return true
	return false

func _valid_spawn() -> bool:
	var point := spawn_transform.origin
	if not _inside(point) or not spawn_transform.basis.is_finite():return false
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP,point-Vector3(0,0.25,0),collision_mask,[get_rid()])
	var ground := space.intersect_ray(ray)
	if ground.is_empty() or ground.normal.dot(Vector3.UP)<cos(floor_max_angle):return false
	var gap: float = point.y-ground.position.y
	if gap<0.005 or gap>0.20:return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = $CollisionShape.shape
	query.transform = spawn_transform * $CollisionShape.transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return space.intersect_shape(query,1).is_empty()

func require_neutral_input() -> void:
	input_latched = true
	velocity = Vector3.ZERO

func recover(reason: String) -> bool:
	spawn_valid = _valid_spawn()
	if not spawn_valid:
		velocity = Vector3.ZERO
		return false
	global_transform = spawn_transform
	visual.rotation = Vector3.ZERO
	recoveries += 1
	last_recovery_reason = reason
	require_neutral_input()
	return true

func _direction(intent: Vector2) -> Vector3:
	var right := movement_camera.global_basis.x
	right.y = 0
	var forward := -movement_camera.global_basis.z
	forward.y = 0
	if forward.length_squared()<0.000001:
		forward = Vector3.FORWARD
		right = Vector3.RIGHT
	else:
		forward = forward.normalized()
		right = forward.cross(Vector3.UP).normalized()
	return (right*intent.x-forward*intent.y).limit_length(1.0)

func _physics_process(delta: float) -> void:
	if not configured:
		velocity = Vector3.ZERO
		physics_stepped.emit(delta)
		return
	if not spawn_valid:spawn_valid = _valid_spawn()
	if not spawn_valid:
		velocity = Vector3.ZERO
		physics_stepped.emit(delta)
		return
	if not global_position.is_finite() or global_position.y<fall_limit_y:
		recover("fall")
		physics_stepped.emit(delta)
		return
	elif not _inside(global_position):
		recover("outside_test_area")
		physics_stepped.emit(delta)
		return
	var intent: Vector2 = router.movement_intent().limit_length(1.0)
	var fast: bool = router.fast_intent()
	if input_latched:
		if intent.length_squared()<0.000001 and not fast:input_latched = false
		intent = Vector2.ZERO
		fast = false
	last_direction = _direction(intent)
	var speed := run_speed_mps if fast else walk_speed_mps
	velocity.x = last_direction.x*speed
	velocity.z = last_direction.z*speed
	if is_on_floor():velocity.y = 0.0
	velocity.y -= gravity_mps2*delta
	if last_direction.length_squared()>0.000001:
		visual.rotation.y = rotate_toward(visual.rotation.y,atan2(-last_direction.x,-last_direction.z),turn_speed_radians*delta)
	move_and_slide()
	physics_stepped.emit(delta)
