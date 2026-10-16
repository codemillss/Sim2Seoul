extends SceneTree
## Actual latest-player move_and_slide trials in an isolated metre fixture.
## Run with --path game --script ../tests/game/check_jump.gd -- --report=/absolute/file.json.
const ACTIONS := ["move_left","move_right","move_forward","move_backward","move_fast","jump"]
const PLAYER_SCRIPT := preload("res://scripts/player/free_roam_player.gd")
const ROUTER_SCRIPT := preload("res://scripts/input_router.gd")
var report_path := ""
var fixture: Node3D
var player: CharacterBody3D
var router: Node
var checks: Array = []
var trials: Array = []
var finished := false

class FixtureWorld extends Node3D:
	var private_cache: Array = []
	var connection := {"synthetic":true}
	func _contains(_point: Vector2, _polygons: Array) -> bool:return false
	func movement_contains(point: Vector2) -> bool:return Rect2(-10,-10,20,20).has_point(point)
	func volume_clear(_point: Vector3, _height: float, _radius: float) -> bool:return true
	func boundary_reason(_point: Vector2) -> String:return "synthetic_edge"

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
	if report_path.is_empty() or not report_path.is_absolute_path():
		push_error("check_jump requires --report=<absolute path>")
		quit(1)
		return
	# This process has no physical bindings, persistent settings or production UI.
	for action in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action)
		Input.action_release(action)
	Engine.physics_ticks_per_second=60
	create_timer(45.0,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _check(title: String, passed: bool, evidence: Dictionary = {}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":evidence})
	if not passed:push_warning("JUMP_CHECK_FAIL "+title)

func _v(point: Vector3) -> Array:return [point.x,point.y,point.z]

func _keys(actions: Array) -> void:
	for action in ACTIONS:Input.action_release(action)
	for action in actions:Input.action_press(action)

func _ticks(count: int) -> void:
	for index in range(count):await player.physics_stepped

func _solid(title: String, size: Vector3, point: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new()
	body.name=title
	body.position=point
	body.collision_layer=1
	body.collision_mask=2
	var collision:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=size
	collision.shape=box
	body.add_child(collision)
	fixture.add_child(body)
	return body

func _build() -> void:
	fixture=Node3D.new()
	fixture.name="JumpFixture"
	var world:=FixtureWorld.new()
	world.name="World"
	fixture.add_child(world)
	router=Node.new()
	router.name="InputRouter"
	router.set_script(ROUTER_SCRIPT)
	fixture.add_child(router)
	var camera:=Camera3D.new()
	camera.name="Camera"
	fixture.add_child(camera)
	player=CharacterBody3D.new()
	player.name="Player"
	player.set_script(PLAYER_SCRIPT)
	player.world_path=NodePath("../World")
	player.input_router_path=NodePath("../InputRouter")
	player.camera_path=NodePath("../Camera")
	player.free_roam_bounds=Rect2(-10,-10,20,20)
	player.walk_speed_mps=2.24
	player.run_speed_mps=5.6
	player.collision_layer=2
	player.collision_mask=1
	player.safe_margin=0.001
	player.floor_snap_length=0.1
	var collision:=CollisionShape3D.new()
	collision.name="CollisionShape"
	var capsule:=CapsuleShape3D.new()
	capsule.height=1.7
	capsule.radius=0.3
	collision.shape=capsule
	collision.position.y=0.85
	player.add_child(collision)
	var visual:=Node3D.new()
	visual.name="Visual"
	player.add_child(visual)
	fixture.add_child(player)
	root.add_child(fixture)
	_solid("Floor",Vector3(24,0.2,24),Vector3(0,-0.1,0))
	var regions: Array[Rect2]=[Rect2(-10,-10,20,20)]
	player.configure_recovery(Vector3(0,0.08,0),regions)
	player.position=Vector3(0,0.08,0)
	player.require_neutral_input()

func _pose(point := Vector3(0,0.08,0)) -> void:
	_keys([])
	player.global_transform=Transform3D(Basis.IDENTITY,point)
	player.velocity=Vector3.ZERO
	player.require_neutral_input()
	await _ticks(12)
	_check("placement.grounded",player.is_on_floor() and not player.input_latched,{"position":_v(player.global_position)})

func _flight(title: String, actions: Array, count := 130) -> Dictionary:
	var start: Vector3=player.global_position
	var before: int=player.recoveries
	var peak:=start.y
	var floor_ticks:=0
	var ascending_episodes:=0
	var was_ascending:=false
	var outside_ticks:=0
	var ceiling_ticks:=0
	_keys(actions)
	for index in range(count):
		await player.physics_stepped
		peak=maxf(peak,player.global_position.y)
		if player.is_on_floor():floor_ticks+=1
		if player.is_on_ceiling():ceiling_ticks+=1
		if not player._inside(player.global_position):outside_ticks+=1
		var ascending:=player.velocity.y>0.01
		if ascending and not was_ascending:ascending_episodes+=1
		was_ascending=ascending
	var row:={"name":title,"ticks":count,"start":_v(start),"end":_v(player.global_position),
		"apex_rise_m":peak-start.y,"floor_ticks":floor_ticks,"ending_grounded":player.is_on_floor(),
		"ascending_episodes":ascending_episodes,"outside_ticks":outside_ticks,"ceiling_ticks":ceiling_ticks,
		"recoveries":player.recoveries-before,"boundary_stops":player.boundary_stops}
	trials.append(row)
	return row

func _run() -> void:
	_build()
	await _pose()
	_check("defaults.3m_and_9_8",player.jump_height_m==3.0 and player.gravity_mps2==9.8)
	var row:=await _flight("space_held",["jump"])
	_check("jump.apex_3m",absf(float(row.apex_rise_m)-3.0)<0.12,row)
	_check("jump.grounded_landing",row.ending_grounded and row.recoveries==0,row)
	_check("jump.held_no_autorepeat",row.ascending_episodes==1 and row.floor_ticks>20,row)
	await _pose()
	_keys(["jump"])
	await _ticks(8)
	_keys([])
	await _ticks(3)
	_keys(["jump"])
	await _ticks(1)
	_check("jump.one_airborne_reboost",player.air_jumps_remaining()==0 and player.velocity.y>7.4,{"vertical_speed":player.velocity.y,"air_jumps_remaining":player.air_jumps_remaining()})
	_keys([]);await _ticks(2)
	var before_third: float=player.velocity.y
	_keys(["jump"]);await _ticks(1)
	_check("jump.third_press_rejected",player.air_jumps_remaining()==0 and player.velocity.y<before_third-.1,{"before":before_third,"after":player.velocity.y})
	row=await _flight("airborne_third_held",["jump"])
	_check("jump.airborne_hold_does_not_repeat_after_landing",row.ascending_episodes==1 and row.ending_grounded and row.floor_ticks>20,row)
	await _pose()
	_keys(["jump","move_right"])
	var start: Vector3=player.global_position
	await _ticks(30)
	var travelled:=player.global_position.x-start.x
	_check("jump.air_control_keeps_walk_speed",not player.is_on_floor() and absf(travelled-1.12)<0.04,{"distance_m":travelled,"position":_v(player.global_position)})
	await _pose(Vector3(9.3,0.08,0))
	row=await _flight("airborne_boundary",["jump","move_right","move_fast"])
	_check("jump.boundary_guards_air_motion",row.outside_ticks==0 and row.recoveries==0 and float(row.end[0])<=9.601 and row.boundary_stops>0,row)
	await _pose()
	var ceiling:=_solid("Ceiling",Vector3(3,0.3,3),Vector3(0,2.45,0))
	await _ticks(2)
	row=await _flight("ceiling",["jump"])
	_check("jump.ceiling_collision",row.ceiling_ticks>0 and row.apex_rise_m<=0.61 and row.ending_grounded and row.recoveries==0,row)
	ceiling.queue_free()
	await _pose()
	# Match the scene's menu sequence: block router, require neutral, pause;
	# held Space on return must remain blocked until it has been released.
	router.gameplay_enabled=false
	player.require_neutral_input()
	paused=true
	_keys(["jump"])
	start=player.global_position
	for index in range(4):await process_frame
	_check("menu.paused_no_drift",player.global_position==start)
	paused=false
	router.gameplay_enabled=true
	row=await _flight("resume_held_space",["jump"],20)
	_check("menu.resume_requires_jump_release",row.ascending_episodes==0 and player.input_latched and row.ending_grounded,row)
	_keys([])
	await _ticks(2)
	row=await _flight("resume_released_then_pressed",["jump"])
	_check("menu.release_restores_jump",row.ascending_episodes==1 and row.apex_rise_m>2.9 and row.ending_grounded,row)
	await _pose()
	_keys(["jump"])
	player.global_position=Vector3(0,-10,0)
	await _ticks(1)
	_check("recovery.clears_pending_jump",player.last_recovery_reason=="fall" and player.input_latched and player.velocity==Vector3.ZERO)
	row=await _flight("recovery_held_space",["jump"],20)
	_check("recovery.held_space_stays_blocked",row.ascending_episodes==0 and row.ending_grounded,row)
	await _pose()
	player.jump_height_m=4.0
	row=await _flight("configured_4m",["jump"],150)
	_check("jump.exported_height_works",absf(float(row.apex_rise_m)-4.0)<0.12 and row.ending_grounded,row)
	_finish()

func _timeout() -> void:
	if finished:return
	_check("bounded_runtime",false,{"timeout_seconds":45})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true
	_keys([])
	paused=false
	var failures:=0
	for check in checks:
		if not check.passed:failures+=1
	var result:={"schema_version":1,"task":"EXPLORATION_JUMP","passed":failures==0,"failed_checks":failures,
		"checks":checks,"trials":trials,"engine":{"version":Engine.get_version_info().string,"display":DisplayServer.get_name(),"physics_hz":Engine.physics_ticks_per_second},
		"scope":"Actual latest-player Input.action_press and move_and_slide in a synthetic floor/ceiling fixture with isolated physical input; no city route, camera, native human-input or performance acceptance."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:
		push_error("Cannot write jump report: "+report_path)
		quit(1)
		return
	file.store_string(JSON.stringify(result)+"\n")
	file.close()
	print("JUMP_TEST ","PASS" if failures==0 else "FAIL"," checks=",checks.size()," failed=",failures)
	quit(0 if failures==0 else 1)
