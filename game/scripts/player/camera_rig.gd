extends Node3D
## Follow after player movement, cast at priority 1, publish safe pose at priority 2.
signal camera_stepped(delta_seconds: float)
@export var target_path: NodePath
@export var pivot_height_m := 1.3
@export var sensitivity_radians_per_pixel := 0.0025
@export var pitch_min_degrees := -55.0
@export var pitch_max_degrees := 15.0
@export var default_pitch_degrees := -15.0
@export var distance_min_m := 2.0
@export var distance_max_m := 6.0
@export var default_distance_m := 4.5
@export var zoom_step_m := 0.35
@export var expansion_mps := 6.0
var yaw := 0.0
var pitch := deg_to_rad(-15.0)
var requested_distance := 4.5
var current_distance := 4.5
var input_enabled := false
var skip_motion := true
var previous_recoveries := 0
var follow_ticks := 0
var observed_ticks := 0
var automatic_probe := false
var clearance_corrections := 0
@onready var target: CharacterBody3D = get_node(target_path)
@onready var arm: SpringArm3D = $SpringArm
@onready var camera: Camera3D = $SpringArm/Camera

func _ready() -> void:
	automatic_probe = "--automatic-probe" in OS.get_cmdline_user_args()
	arm.add_excluded_object(target.get_rid())
	previous_recoveries = target.recoveries
	target.physics_stepped.connect(_after_player_step)
	reset_orientation()
	global_position = target.global_position+Vector3.UP*pivot_height_m
	rotation = Vector3(pitch,yaw,0)

func reset_orientation() -> void:
	yaw = 0
	pitch = deg_to_rad(default_pitch_degrees)
	requested_distance = clampf(default_distance_m,distance_min_m,distance_max_m)
	current_distance = requested_distance
	arm.spring_length = requested_distance
	skip_motion = true

func set_capture(enabled: bool) -> void:
	input_enabled = enabled
	skip_motion = true
	# Browsers only grant pointer lock during a real click. The initial async
	# city load and an Escape-menu return must wait for that gesture.
	if OS.has_feature("web") and enabled and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	if OS.has_feature("web") and input_enabled and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		skip_motion = true
		get_viewport().set_input_as_handled()
		return
	var simulated_capture := automatic_probe and DisplayServer.get_name()=="headless"
	# Embedded browsers may refuse pointer lock. A held drag still supplies
	# relative motion, so retain a usable view control without capture.
	var web_drag: bool = OS.has_feature("web") and event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if not input_enabled or (Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED and not simulated_capture and not web_drag):return
	# Reproducible injected events in automatic probes; native human input in normal play.
	if automatic_probe and event.device!=42:return
	if event is InputEventMouseMotion:
		if skip_motion:
			skip_motion = false
		else:
			yaw = wrapf(yaw-event.screen_relative.x*sensitivity_radians_per_pixel,-PI,PI)
			pitch = clampf(pitch-event.screen_relative.y*sensitivity_radians_per_pixel,deg_to_rad(pitch_min_degrees),deg_to_rad(pitch_max_degrees))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:requested_distance = maxf(distance_min_m,requested_distance-zoom_step_m)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:requested_distance = minf(distance_max_m,requested_distance+zoom_step_m)
		else:return
		get_viewport().set_input_as_handled()

func _after_player_step(_delta: float) -> void:
	if target.recoveries!=previous_recoveries:
		previous_recoveries = target.recoveries
		reset_orientation()
	global_position = target.global_position+Vector3.UP*pivot_height_m
	rotation = Vector3(pitch,yaw,0)
	arm.spring_length = requested_distance
	follow_ticks += 1

func _physics_process(delta: float) -> void:
	# Retraction is immediate. Expansion stays inside the newest complete sweep.
	var safe_length := maxf(arm.get_hit_length(),0.0)
	current_distance = minf(safe_length,current_distance+expansion_mps*delta)
	# A final overlap query catches transient corner contact missed by the motion sweep.
	if _overlaps_at(current_distance):
		var low := 0.0
		var high := current_distance
		for iteration in range(14):
			var middle := (low+high)/2.0
			if _overlaps_at(middle):high = middle
			else:low = middle
		current_distance = maxf(low-0.005,0.0)
		clearance_corrections += 1
	camera.position = Vector3(0,0,current_distance)
	# Hysteresis prevents the near camera from showing the inside of its own body.
	if current_distance<1.5:target.get_node("Visual").visible = false
	elif current_distance>1.8:target.get_node("Visual").visible = true
	observed_ticks += 1
	camera_stepped.emit(delta)

func _overlaps_at(distance: float) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = arm.shape
	query.transform = Transform3D(Basis.IDENTITY,arm.global_position+arm.global_basis.z*distance)
	query.collision_mask = arm.collision_mask
	query.exclude = [target.get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func snapshot() -> Dictionary:
	var t := camera.global_transform
	var size := get_viewport().get_visible_rect().size
	return {"pivot":[global_position.x,global_position.y,global_position.z],
		"camera":[t.origin.x,t.origin.y,t.origin.z],"basis":[[t.basis.x.x,t.basis.x.y,t.basis.x.z],[t.basis.y.x,t.basis.y.y,t.basis.y.z],[t.basis.z.x,t.basis.z.y,t.basis.z.z]],
		"yaw":yaw,"pitch":pitch,"requested_distance":requested_distance,"distance":current_distance,
		"hit_length":arm.get_hit_length(),"follow_ticks":follow_ticks,"observed_ticks":observed_ticks,
		"mouse_mode":Input.mouse_mode,"input_enabled":input_enabled,"near":camera.near,"fov":camera.fov,
		"aspect":size.x/size.y,"probe_radius":arm.shape.radius,"mask":arm.collision_mask,"clearance_corrections":clearance_corrections}
