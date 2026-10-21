extends Node3D
## Arcade winch. The retained native player capsule is queried on every segment;
## no descent or cancellation is a teleport. The pilot owns transport until safe
## support is reached or the complete return into the cabin has finished.
const ACTION := &"helicopter_rope"
const SPEED_MPS := 2.0
const TRANSFER_MPS := 1.2
const SIDE_OFFSET := Vector3(2.35,.90,-.70)
var aircraft: Node3D
var state := "idle"
var reason := ""
var target: Dictionary = {}
var side_point := Vector3.ZERO
var cabin_point := Vector3.ZERO
var travelled_m := 0.0
var maximum_step_m := 0.0
var last_result := ""
var _held := false
var _require_release := true
var _queued := false
var _returning_to_cabin := false
var _line: MeshInstance3D
var _harness: MeshInstance3D
var _elapsed := 0.0

func setup(service: Node3D) -> void:
	aircraft=service;process_mode=Node.PROCESS_MODE_ALWAYS;process_physics_priority=3
	aircraft._bind_key(ACTION,KEY_R)
	var yellow: Material=aircraft._mat(Color(.97,.72,.10),.1)
	aircraft._tube(aircraft._proxy,"RescueWinchArm",Vector3(.9,2.25,-.7),Vector3(2.35,2.25,-.7),.055,yellow)
	aircraft._box(aircraft._proxy,"RescueWinch",Vector3(.25,.25,.28),Vector3(2.35,2.23,-.7),yellow)
	var line_mesh:=CylinderMesh.new();line_mesh.top_radius=.025;line_mesh.bottom_radius=.025;line_mesh.height=1.;line_mesh.radial_segments=8
	_line=aircraft._mesh(self,"VisibleWinchRope",line_mesh,yellow);_line.visible=false
	_harness=aircraft._box(self,"VisibleDescentHarness",Vector3(.47,.10,.32),Vector3.ZERO,yellow);_harness.visible=false

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo:return
	if event.physical_keycode!=KEY_R and event.keycode!=KEY_R:return
	if not event.pressed:
		_held=false;_require_release=false;return
	if _held:return
	_held=true
	if _require_release or not aircraft._context_ready() or not aircraft.riding:
		_require_release=true;return
	_queued=true

func active() -> bool:return state!="idle"
func on_boarded() -> void:
	_queued=false;_require_release=Input.is_action_pressed(ACTION);_held=_require_release
func cleanup() -> void:
	state="idle";target.clear();reason="";_queued=false;_line.visible=false;_harness.visible=false
	if is_instance_valid(aircraft.host.exploration_avatar):aircraft.host.exploration_avatar.set_activity("",0.)
func _event(kind: String,details: Dictionary={}) -> void:aircraft._event("rope_"+kind,details)
func _capsule_query(at: Vector3,exclude_aircraft: bool) -> PhysicsShapeQueryParameters3D:
	var capsule: CollisionShape3D=aircraft.host.player.get_node("CollisionShape")
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule.shape;query.transform=Transform3D(Basis.IDENTITY,at)*capsule.transform;query.collision_mask=1|2|4|8|32;query.exclude=[aircraft.host.player.get_rid()];query.margin=.004
	if exclude_aircraft:
		var exclusions: Array[RID]=query.exclude;exclusions.append(aircraft.body.get_rid());query.exclude=exclusions
	return query
func clear_at(at: Vector3,exclude_aircraft:=false) -> bool:
	return get_world_3d().direct_space_state.intersect_shape(_capsule_query(at,exclude_aircraft),1).is_empty()
func path_clear(a: Vector3,b: Vector3,exclude_aircraft:=false) -> bool:
	var query:=_capsule_query(a,exclude_aircraft)
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return false
	query.motion=b-a
	return get_world_3d().direct_space_state.cast_motion(query)[0]>.9999 and clear_at(b,exclude_aircraft)
func _find_target() -> Dictionary:
	var ray:=PhysicsRayQueryParameters3D.create(side_point,side_point-Vector3.UP*float(aircraft.design.policy.maximum_altitude_above_terrain_m),1|32,[aircraft.body.get_rid(),aircraft.host.player.get_rid()])
	var hit:=get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y<cos(deg_to_rad(float(aircraft.design.policy.maximum_landing_grade_degrees))):reason="no_safe_support";return {}
	var support: Dictionary=aircraft._roof_support(hit,hit.position)
	if support.is_empty():
		if not aircraft._public_ground(hit.position):reason="private_water_or_boundary";return {}
		var terrain: Dictionary=aircraft._terrain_point(hit.position)
		if terrain.is_empty() or hit.rid!=terrain.rid or absf(hit.position.y-terrain.point.y)>.1:reason="not_native_public_ground_or_game_deck";return {}
		support=terrain
	var point: Vector3=support.point+Vector3.UP*.08
	if side_point.y-point.y<2.:reason="too_low_for_rope";return {}
	if not clear_at(side_point) or not path_clear(side_point,point):reason="full_capsule_descent_blocked";return {}
	if not path_clear(cabin_point,side_point,true):reason="cabin_to_winch_blocked";return {}
	return {"point":point,"support_rid":support.rid,"building_id":support.get("building_id",""),"support_kind":"game_roof_deck" if support.has("roof") else "native_public_terrain"}
func _same_support() -> bool:
	if target.is_empty():return false
	var support: Dictionary=aircraft._landing_support(target.point)
	return not support.is_empty() and support.rid==target.support_rid and absf(support.point.y+.08-target.point.y)<.04
func _begin() -> void:
	if aircraft._landed():aircraft._notice_message("로프는 공중에서 사용합니다. Space로 이륙한 뒤 R을 눌러주세요.");return
	state="braking";reason="";last_result="";travelled_m=0.;maximum_step_m=0.;_elapsed=0.;aircraft.exit_requested=false;_event("hover_requested")
func _deploy() -> void:
	side_point=aircraft.body.to_global(SIDE_OFFSET);cabin_point=aircraft.host.player.global_position
	target=_find_target()
	if target.is_empty():
		var rejection:=reason;state="idle";aircraft._notice_message("로프 하강 불가 · 아래의 평탄한 공공 지면이나 넓은 게임 옥상을 찾아주세요.");_event("rejected",{"reason":rejection});return
	state="transfer_out";_returning_to_cabin=false
	aircraft.host.exploration_avatar.visible=true;aircraft._passenger.visible=false
	aircraft.host.exploration_avatar.set_activity("rope",0.);_line.visible=true;_harness.visible=true
	aircraft.host.rig.pivot_height_m=1.;aircraft.host.rig.requested_distance=10.;aircraft.host.rig.current_distance=10.
	_event("deployed",{"target":target.point,"support_kind":target.support_kind,"building_id":target.building_id,"capsule_shape_id":aircraft.host.player.get_node("CollisionShape").shape.get_instance_id()})
func _cancel() -> void:
	if state=="retracting":return
	if state=="braking":cleanup();aircraft._neutral_required=true;last_result="cancelled_before_deploy";_event("cancelled_before_deploy");return
	_returning_to_cabin=state=="transfer_out";state="retracting";reason="";_event("retraction_requested")
func _advance(goal: Vector3,rate: float,delta: float,exclude_aircraft: bool) -> bool:
	var player: CharacterBody3D=aircraft.host.player;var before:=player.global_position
	var next:=before.move_toward(goal,rate*delta)
	if not path_clear(before,next,exclude_aircraft):reason="native_capsule_path_blocked";return false
	player.global_basis=Basis(Vector3.UP,aircraft._yaw)
	var contact:=player.move_and_collide(next-before,false,.001)
	player.velocity=Vector3.ZERO;player.physics_stepped.emit(delta)
	var step:=before.distance_to(player.global_position);travelled_m+=step;maximum_step_m=maxf(maximum_step_m,step)
	if contact!=null and player.global_position.distance_to(next)>.002:
		reason="native_capsule_contact";return false
	reason=""
	return player.global_position.distance_to(goal)<.001
func step(delta: float) -> void:
	if _queued:
		_queued=false
		if active():_cancel()
		elif aircraft.riding:_begin()
	if not active():return
	_elapsed+=delta
	if state=="braking":
		if absf(aircraft.speed_mps)<.05 and absf(aircraft.vertical_speed_mps)<.05 and aircraft.rotor_fraction>.9:_deploy()
		return
	if state=="transfer_out":
		if _advance(side_point,TRANSFER_MPS,delta,true):state="lowering";_event("lowering_started")
	elif state=="lowering":
		if not _same_support():state="blocked";reason="landing_support_changed";_event("paused",{"reason":reason});return
		if _advance(target.point,SPEED_MPS,delta,false):
			var at: Vector3=aircraft.host.player.global_position
			if not _same_support() or not clear_at(at):state="blocked";reason="landing_no_longer_safe";return
			var result:=target.duplicate();cleanup();last_result="completed";aircraft.host.player.global_basis=Basis.IDENTITY;aircraft._restore_player(true);aircraft.return_pending=true;aircraft._return_elapsed=0.;aircraft._notice_message("로프 하강 완료 · 기체는 게임 착륙장으로 회수됩니다.");_event("completed",{"point":at,"support_kind":result.support_kind,"building_id":result.building_id,"travelled_m":travelled_m,"maximum_step_m":maximum_step_m,"aircraft_recovery":"certified_clear_home_recall_not_physical_flight"})
		elif not reason.is_empty():state="blocked";_event("paused",{"reason":reason})
	elif state=="retracting":
		var goal:=cabin_point if _returning_to_cabin else side_point
		if _advance(goal,TRANSFER_MPS if _returning_to_cabin else SPEED_MPS,delta,_returning_to_cabin):
			if not _returning_to_cabin:_returning_to_cabin=true
			else:
				cleanup();last_result="cancelled_back_in_cabin";aircraft.host.exploration_avatar.visible=false;aircraft._passenger.visible=true;aircraft._neutral_required=true;aircraft._event("rope_retracted_to_pilot");aircraft._notice_message("로프를 회수했습니다. 조종을 계속할 수 있습니다.")
	# A newly occupied path holds the retained capsule where it was. R chooses
	# retraction, whose own swept segments can also pause without crossing it.
func _physics_process(_delta: float) -> void:
	if not is_instance_valid(aircraft) or not aircraft.loaded:return
	if get_tree().paused or aircraft.host.menu.visible:
		_queued=false
		if _held or Input.is_action_pressed(ACTION):_require_release=true
		return
	if active() and state!="braking":
		var avatar: Node3D=aircraft.host.exploration_avatar
		avatar._arm_to("Left",Vector3(-.10,1.58,-.08));avatar._arm_to("Right",Vector3(.10,1.52,-.08))
func update_visual() -> void:
	if not _line.visible:return
	var top: Vector3=aircraft._proxy.to_global(Vector3(2.35,2.23,-.7));var foot: Vector3=aircraft.host.player.global_position;var bottom:=foot+Vector3.UP*1.2
	_line.global_position=(top+bottom)*.5;_line.global_basis=Basis(Quaternion(Vector3.UP,(top-bottom).normalized()));_line.scale=Vector3(1.,maxf(.02,top.distance_to(bottom)),1.)
	_harness.global_transform=Transform3D(Basis(Vector3.UP,aircraft._yaw),foot+Vector3.UP*.82)
func prompt() -> String:
	if state=="braking":return "로프 준비 · 제동 후 제자리 비행\nR · 취소"
	if state=="blocked" or not reason.is_empty():return "로프 정지 · 아래 공간이나 경로가 막혔습니다\nR · 안전한 경로로 기체 복귀 · 메뉴에서 장소 이동 가능"
	if state=="retracting":return "로프 회수 중 · 기체로 올라가는 중\nR · 회수 유지"
	return "로프 하강 중 · %.1fm 남음\nR · 하강 취소하고 기체로 올라가기"%maxf(0.,aircraft.host.player.global_position.y-float(target.get("point",Vector3.ZERO).y))
func snapshot() -> Dictionary:
	return {"state":state,"reason":reason,"target":target.duplicate(),"side_point":side_point,"travelled_m":travelled_m,"maximum_step_m":maximum_step_m,"last_result":last_result,"line_visible":is_instance_valid(_line) and _line.visible,"harness_visible":is_instance_valid(_harness) and _harness.visible,"key_requires_release":_require_release,"descent_mps":SPEED_MPS}
