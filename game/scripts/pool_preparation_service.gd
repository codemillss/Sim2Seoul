extends Node3D
## One shared E dispatcher owns interactions. This controller never reads E.
## Roof-local rooms are authored game amenities, not surveyed hotel interiors.
const SHOWER_SECONDS:=4.0
var host: Node3D
var loaded:=false
var load_error:=""
var pool_id:=""
var showered:=false
var showering:=false
var shower_elapsed:=0.0
var completed_showers:=0
var rejected_water_entries:=0
var cancelled_showers:=0
var events: Array[Dictionary]=[]
var _roof: Node3D
var _last_safe: Dictionary={}
var _saved_facility:=false
var _notice:=""
var _notice_until:=0.0
var _clock:=0.0
var _last_interact_tick:=-100
func setup(scene: Node3D) -> bool:
	if loaded or not is_instance_valid(scene) or not is_inside_tree():return false
	host=scene;process_mode=Node.PROCESS_MODE_PAUSABLE;process_physics_priority=-1
	if not is_instance_valid(host.get("shop_visit_service")) or not host.shop_visit_service.has_method("begin_swimwear"):
		load_error="수영복 의상 서비스가 준비되지 않았습니다.";return false
	host.player.pool_preparation_guard=self;loaded=true;return true
func _event(kind: String,details: Dictionary={}) -> void:
	if events.size()>=100:events.pop_front()
	events.append({"event":kind,"clock_s":_clock,"pool_id":pool_id,"details":details})
func _tell(message: String) -> void:_notice=message;_notice_until=_clock+3.5
func _roofs() -> Array[Node3D]:
	var result: Array[Node3D]=[]
	var access: Node3D=host.get("exploration_rooftop_access")
	if is_instance_valid(access):
		for roof: Node3D in access.roofs.values():
			if is_instance_valid(roof) and roof.profile_id=="outdoor_pool" and not roof.pool_preparation_points().is_empty():result.append(roof)
	var interior: Node3D=host.interior_visit
	if is_instance_valid(interior.rooftop) and interior.rooftop.profile_id=="outdoor_pool" and not result.has(interior.rooftop):result.append(interior.rooftop)
	return result
func _at_roof() -> Node3D:
	var best: Node3D;var gap:=INF
	for roof: Node3D in _roofs():
		var local: Vector3=roof.frame.affine_inverse()*host.player.global_position
		if not roof.walkable_rect.grow(.6).has_point(Vector2(local.x,local.z)) or local.y<-1.7:continue
		if absf(local.y)<gap:best=roof;gap=absf(local.y)
	return best
func _busy() -> bool:
	if not loaded or not host.runtime_ok or get_tree().paused or host.menu.visible:return true
	if host.has_method("_street_transport_riding") and host._street_transport_riding():return true
	if host.has_method("_shop_active") and host._shop_active():return true
	if host.shop_visit_service.ui_open or host.shop_visit_service.inventory_open:return true
	if host.player.facility_control and not showering:return true
	return host.interior_visit.in_elevator or host.interior_visit.elevator_open
func _safe_point(point: Vector3) -> Dictionary:
	if not point.is_finite():return {}
	var player: CharacterBody3D=host.player;var mask: int=player.collision_mask
	var ray:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*.35,point-Vector3.UP*.35,mask,[player.get_rid()]);var hit:=get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y<cos(player.floor_max_angle):return {}
	var safe:=Vector3(point.x,hit.position.y+.08,point.z);var capsule: CollisionShape3D=player.get_node("CollisionShape")
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule.shape;query.collision_mask=mask;query.exclude=[player.get_rid()];query.margin=.001;query.transform=Transform3D(Basis.IDENTITY,safe)*capsule.transform
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return {}
	return {"point":safe}
func _near_station(roof: Node3D,kind: String) -> bool:
	if not is_instance_valid(roof):return false
	var points: Dictionary=roof.pool_preparation_points();var local: Vector3=roof.frame.affine_inverse()*host.player.global_position
	if absf(local.y)>.16 or absf(host.player.velocity.y)>.30:return false
	if kind in ["changing","shower"] and not points[kind+"_rect"].grow(-.30).has_point(Vector2(local.x,local.z)):return false
	if host.player.global_position.distance_to(points[kind])>1.25:return false
	if _safe_point(host.player.global_position).is_empty():return false
	var ray:=PhysicsRayQueryParameters3D.create(host.player.global_position+Vector3.UP,points[kind]+Vector3.UP,host.player.collision_mask,[host.player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
func can_interact() -> bool:
	if _busy():return false
	if showering:return true
	var roof:=_at_roof()
	return is_instance_valid(roof) and (_near_station(roof,"changing") or _near_station(roof,"shower") or _near_station(roof,"gate"))
func interaction_distance_m() -> float:
	if showering:return 0.
	var roof:=_at_roof()
	if not is_instance_valid(roof):return INF
	var distance:=INF;var points: Dictionary=roof.pool_preparation_points()
	for kind: String in ["changing","shower","gate"]:distance=minf(distance,host.player.global_position.distance_to(points[kind]))
	return distance
func handle_interact() -> bool:
	if not can_interact():return false
	var tick:=Engine.get_physics_frames()
	if tick==_last_interact_tick:return true
	_last_interact_tick=tick
	if showering:_finish_shower(false);_tell("샤워가 취소됐습니다. 끝까지 샤워한 뒤 입장하세요.");return true
	var roof:=_at_roof();var id:=String(roof.spec.id)
	if _near_station(roof,"changing"):
		if host.shop_visit_service.swimwear_active:
			cancel_for_transition();_tell("원래 옷으로 갈아입었습니다. 다시 이용하려면 수영복과 샤워를 준비하세요.")
		elif host.shop_visit_service.begin_swimwear():
			pool_id=id;_roof=roof;showered=false;_last_safe=_safe_point(host.player.global_position);_tell("수영복으로 갈아입었습니다. 옆 샤워실에서 E를 눌러 샤워하세요.");_event("swimwear_changed")
		return true
	if _near_station(roof,"shower"):
		if pool_id!=id or not host.shop_visit_service.swimwear_active:_tell("탈의실에서 먼저 수영복으로 갈아입으세요.");return true
		showered=false;showering=true;shower_elapsed=0.;_saved_facility=host.player.facility_control;host.player.set_facility_control(true);roof.set_pool_shower_running(true);_event("shower_started");return true
	_tell("준비 완료 · 계단을 따라 입수하세요." if water_access_allowed(roof) else "탈의실 수영복 → 샤워실 샤워를 마친 뒤 입장할 수 있습니다.")
	return true
func interact() -> bool:return handle_interact()
func _finish_shower(complete: bool) -> void:
	if not showering:return
	showering=false;showered=complete
	if complete:completed_showers+=1
	else:cancelled_showers+=1
	if is_instance_valid(_roof):_roof.set_pool_shower_running(false)
	host.exploration_avatar.set_activity("",0.);host.player.set_facility_control(_saved_facility);host.player.require_neutral_input();_event("shower_completed" if complete else "shower_cancelled")
func water_access_allowed(roof: Node3D) -> bool:
	return loaded and is_instance_valid(roof) and pool_id==String(roof.spec.id) and showered and not showering and host.shop_visit_service.swimwear_active
func enforce_player_water_access() -> bool:
	if not loaded or (host.has_method("_street_transport_riding") and host._street_transport_riding()):return true
	for roof: Node3D in _roofs():
		var region: Dictionary=roof.pool_water_region();var local: Vector3=roof.frame.affine_inverse()*host.player.global_position
		if not region.rect.has_point(Vector2(local.x,local.z)) or local.y>float(region.surface_y)+.05 or local.y<float(region.floor_y)-.30:continue
		if water_access_allowed(roof):return true
		var safe: Dictionary={}
		if is_instance_valid(_roof) and _roof==roof and not _last_safe.is_empty():safe=_safe_point(_last_safe.point)
		if safe.is_empty():safe=_safe_point(roof.pool_preparation_points().arrival)
		if safe.is_empty():safe=_safe_point(roof.pool_preparation_points().changing)
		rejected_water_entries+=1;_tell("수영복과 샤워를 먼저 준비하세요. 안전한 준비 구역으로 돌아갑니다.")
		if not safe.is_empty():
			host.player.global_transform=Transform3D(Basis.IDENTITY,safe.point);host.player.velocity=Vector3.ZERO;host.player.last_direction=Vector3.ZERO;host.player.require_neutral_input();host.player.reset_physics_interpolation();host.player._water_contacting=false;host.player._swimming=false;host.player._water_jump_locked=false;host.player._air_jumps_used=0;host.rig.snap_to_target_pose()
		else:host.player.recover("pool_preparation_required")
		_event("unprepared_water_entry_rejected",{"safe_point":safe.get("point"),"scope":"Native current capsule support/overlap query; original source colliders retained."});return false
	return true
func cancel_for_transition() -> void:
	if showering:_finish_shower(false)
	if is_instance_valid(_roof):_roof.set_pool_access_authorized(false);_roof.set_pool_shower_running(false)
	if loaded and host.shop_visit_service.swimwear_active:host.shop_visit_service.end_swimwear()
	if not pool_id.is_empty():_event("preparation_session_released")
	pool_id="";showered=false;shower_elapsed=0.;_roof=null;_last_safe.clear()
func prompt_text() -> String:
	if _busy():return ""
	if _clock<_notice_until:return _notice
	if showering:return "샤워 중 · %d%%\nE · 취소 · 끝까지 씻으면 수영장 입장 가능"%mini(100,roundi(shower_elapsed/SHOWER_SECONDS*100.))
	var roof:=_at_roof()
	if not is_instance_valid(roof):return ""
	if _near_station(roof,"changing"):return "E · 원래 옷으로 갈아입기" if host.shop_visit_service.swimwear_active else "E · 수영복으로 갈아입기"
	if _near_station(roof,"shower"):return "E · 샤워하기 · 4초" if host.shop_visit_service.swimwear_active and pool_id==String(roof.spec.id) else "탈의실에서 수영복으로 갈아입은 뒤 샤워하세요."
	if _near_station(roof,"gate"):return "입장 가능 · 계단으로 입수 / Space 물 밖으로" if water_access_allowed(roof) else "입장 준비 · 탈의실 수영복 → 샤워실 샤워"
	if host.player.is_swimming():return "수영 중 · WASD 이동 / Space 물 밖으로 점프\n이용 후 탈의실에서 E · 원래 옷"
	if host.interior_visit._elevator_near() or is_instance_valid(host.interior_visit.outdoor_roof_lift_candidate()):return ""
	return "수영장 준비 · 탈의실 → 샤워실 → 입장" if not water_access_allowed(roof) else "수영장 이용 가능 · 계단으로 입수 / Space 물 밖으로"
func _physics_process(delta: float) -> void:
	if not loaded:return
	_clock+=delta
	var current:=_at_roof()
	if not pool_id.is_empty() and current!=_roof:cancel_for_transition()
	if showering:
		if _busy() or not is_instance_valid(_roof):return
		if not _near_station(_roof,"shower"):_finish_shower(false)
		else:
			shower_elapsed+=delta;host.exploration_avatar.set_activity("shower",shower_elapsed)
			if shower_elapsed>=SHOWER_SECONDS:_finish_shower(true);_tell("샤워 완료 · 수영장 게이트가 열렸습니다.")
	for roof: Node3D in _roofs():roof.set_pool_access_authorized(water_access_allowed(roof))
	if is_instance_valid(current):
		var local: Vector3=current.frame.affine_inverse()*host.player.global_position
		if absf(local.y)<.16 and not current.pool_water_region().rect.grow(.30).has_point(Vector2(local.x,local.z)):
			var safe:=_safe_point(host.player.global_position)
			if not safe.is_empty() and current==_roof:_last_safe=safe
func snapshot() -> Dictionary:
	var rooms: Array=[]
	if loaded:
		for roof: Node3D in _roofs():rooms.append({"id":roof.spec.id,"points":roof.pool_preparation_points(),"authorized":water_access_allowed(roof),"gate_layer":roof._pool_gate_body.collision_layer,"shower_water_visible":roof._pool_shower_water.visible})
	return {"loaded":loaded,"error":load_error,"pool_id":pool_id,"swimwear_active":host.shop_visit_service.swimwear_active if loaded else false,"showering":showering,"shower_elapsed_s":shower_elapsed,"showered":showered,"completed_showers":completed_showers,"cancelled_showers":cancelled_showers,"rejected_water_entries":rejected_water_entries,"rooms":rooms,"events":events.duplicate(true),"scope":"Authored roof-local changing/shower rooms and native gate; completed preparation required for actual water entry including jumps/falls. No real hotel amenity or surveyed interior claim."}
