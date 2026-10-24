extends Node3D
## One shared E dispatcher owns interactions. This controller never reads E.
## Roof-local rooms are authored game amenities, not surveyed hotel interiors.
const SHOWER_SECONDS:=4.0
const FRESHNESS_SECONDS:=90.0
const SHOWER_CLEANLINESS_GAIN:=20.0
const FRESH_SWIM_BONUS:=.10
const SWIMWEAR_SWIM_BONUS:=.15
var host: Node3D
var loaded:=false
var load_error:=""
var pool_id:=""
var showered:=false
var freshness_remaining_s:=0.0
var last_shower_cleanliness_gain:=0.0
var total_shower_cleanliness_gain:=0.0
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
func _bar_choice(roof: Node3D) -> Dictionary:
	if not is_instance_valid(roof) or not roof.has_method("pool_bar"):return {}
	var bar: Dictionary=roof.pool_bar()
	if not bar.has("drink_options"):return {}
	if bar.stage!="idle":return bar.drink_options[int(bar.selected_drink_index)]
	var best: Dictionary={};var gap:=INF
	for choice: Dictionary in bar.drink_options:
		var distance: float=host.player.global_position.distance_squared_to(choice.use_point)
		if distance<gap:best=choice;gap=distance
	return best

func _near_bar(roof: Node3D) -> bool:
	if not is_instance_valid(roof) or not roof.has_method("pool_bar"):return false
	var bar: Dictionary=roof.pool_bar()
	var choice:=_bar_choice(roof)
	if choice.is_empty():return false
	var point: Vector3=choice.use_point;var local: Vector3=roof.frame.affine_inverse()*host.player.global_position
	if absf(local.y)>.16 or host.player.is_swimming() or host.player.global_position.distance_to(point)>1.05:return false
	if _safe_point(host.player.global_position).is_empty():return false
	var ray:=PhysicsRayQueryParameters3D.create(host.player.global_position+Vector3.UP,point+Vector3.UP,host.player.collision_mask,[host.player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func can_interact() -> bool:
	if _busy():return false
	if showering:return true
	var roof:=_at_roof()
	return is_instance_valid(roof) and (_near_station(roof,"changing") or _near_station(roof,"shower") or _near_station(roof,"gate") or _near_bar(roof))
func interaction_distance_m() -> float:
	if showering:return 0.
	var roof:=_at_roof()
	if not is_instance_valid(roof):return INF
	var distance:=INF;var points: Dictionary=roof.pool_preparation_points()
	for kind: String in ["changing","shower","gate"]:distance=minf(distance,host.player.global_position.distance_to(points[kind]))
	if roof.has_method("pool_bar") and roof.pool_bar().has("use_point"):distance=minf(distance,host.player.global_position.distance_to(roof.pool_bar().use_point))
	return distance
func handle_interact() -> bool:
	if not can_interact():return false
	var tick:=Engine.get_physics_frames()
	if tick==_last_interact_tick:return true
	_last_interact_tick=tick
	if showering:_finish_shower(false);_tell("샤워 취소 · 새 보상 없이 자유롭게 수영할 수 있습니다.");return true
	var roof:=_at_roof();var id:=String(roof.spec.id)
	if _near_bar(roof):
		_tell(roof.interact_pool_bar(int(_bar_choice(roof).id)));_event("nonalcohol_bar_interaction",{"roof_id":id,"bar":roof.pool_bar()});return true
	if _near_station(roof,"changing"):
		pool_id=id;_roof=roof
		if host.shop_visit_service.swimwear_active:
			host.shop_visit_service.end_swimwear();_tell("원래 옷으로 갈아입었습니다 · 수영복 +15% 해제")
		elif host.shop_visit_service.begin_swimwear():
			_tell("수영복 착용 · 이 풀에서 수영 속도 +15% · 샤워는 선택입니다.");_event("swimwear_changed")
		return true
	if _near_station(roof,"shower"):
		pool_id=id;_roof=roof;showering=true;shower_elapsed=0.;_saved_facility=host.player.facility_control;host.player.set_facility_control(true);roof.set_pool_shower_running(true);_event("shower_started",{"swimwear_required":false});return true
	_tell("바로 입수할 수 있습니다 · 수영복 +15% / 샤워 상쾌함 +10%는 선택입니다.")
	return true
func interact() -> bool:return handle_interact()
func _finish_shower(complete: bool) -> void:
	if not showering:return
	showering=false
	if complete:
		completed_showers+=1;freshness_remaining_s=FRESHNESS_SECONDS;showered=true
		var wellbeing: Node3D=host.interior_visit.facility_interaction
		last_shower_cleanliness_gain=minf(SHOWER_CLEANLINESS_GAIN,maxf(0.,100.-float(wellbeing.cleanliness)))
		wellbeing.cleanliness+=last_shower_cleanliness_gain;total_shower_cleanliness_gain+=last_shower_cleanliness_gain
	else:cancelled_showers+=1
	if is_instance_valid(_roof):_roof.set_pool_shower_running(false)
	host.exploration_avatar.set_activity("",0.);host.player.set_facility_control(_saved_facility);host.player.require_neutral_input();_event("shower_completed" if complete else "shower_cancelled",{"freshness_remaining_s":freshness_remaining_s,"cleanliness_gain":last_shower_cleanliness_gain if complete else 0.,"refreshes_duration_instead_of_stacking":true})
func water_access_allowed(roof: Node3D) -> bool:
	return loaded and is_instance_valid(roof) and roof.profile_id=="outdoor_pool"
func enforce_player_water_access() -> bool:
	# Clothing and hygiene are optional activities. The original player owns
	# physical water/float/exit validation; never relocate a casual-clothes swim.
	return true
func swimming_speed_multiplier() -> float:
	var current:=_at_roof()
	if not loaded or not is_instance_valid(current) or current!=_roof or pool_id!=String(current.spec.id):return 1.
	return 1.+(FRESH_SWIM_BONUS if freshness_remaining_s>0. else 0.)+(SWIMWEAR_SWIM_BONUS if host.shop_visit_service.swimwear_active else 0.)
func _benefits_text() -> String:
	var parts: PackedStringArray=[]
	if host.shop_visit_service.swimwear_active:parts.append("수영복 +15%")
	if freshness_remaining_s>0.:parts.append("상쾌함 %d초 · 수영 +10%%"%ceili(freshness_remaining_s))
	if parts.is_empty():parts.append("추가 효과 없음 · 준비 없이 입수 가능")
	return " / ".join(parts)+" · 수영 %.2fm/s · 청결 %.0f/100"%[host.player.swimming_speed_limit_mps(),float(host.interior_visit.facility_interaction.cleanliness)]
func cancel_for_transition() -> void:
	if showering:_finish_shower(false)
	if is_instance_valid(_roof):_roof.set_pool_access_authorized(true);_roof.set_pool_shower_running(false)
	if loaded and host.shop_visit_service.swimwear_active:host.shop_visit_service.end_swimwear()
	if not pool_id.is_empty():_event("preparation_session_released")
	pool_id="";showered=false;freshness_remaining_s=0.;shower_elapsed=0.;_roof=null;_last_safe.clear();_notice="";_notice_until=0.
func prompt_text() -> String:
	if _busy():return ""
	var roof:=_at_roof()
	if not is_instance_valid(roof):return ""
	var benefits:=_benefits_text()
	if showering:return "샤워 중 · %d%% · E 취소\n완료 시 청결 +20(100 상한) · 상쾌함90초 수영 +10%%\n"%mini(100,roundi(shower_elapsed/SHOWER_SECONDS*100.))+benefits
	if _clock<_notice_until:return _notice+"\n"+benefits
	if _near_bar(roof):
		var bar: Dictionary=roof.pool_bar()
		return ("바텐더가 음료 준비 중 · 잠시 기다려 주세요" if bar.stage=="preparing" else ("E · "+String(bar.drink)+" 받기 · 무알코올 · 무료" if bar.stage=="ready" else "E · "+String(_bar_choice(roof).title)+" 주문 · 무알코올 · 무료"))+"\n"+benefits
	if _near_station(roof,"changing"):return ("E · 원래 옷으로 갈아입기" if host.shop_visit_service.swimwear_active else "E · 수영복 착용 · 선택 · 수영 +15%")+"\n"+benefits
	if _near_station(roof,"shower"):return "E · 샤워4초 · 복장 무관 · 청결 +20 / 상쾌함90초 수영 +10%\n"+benefits
	if _near_station(roof,"gate"):return "바로 입수 가능 · 계단으로 입수 / Space 물 밖으로\n"+benefits
	if host.player.is_swimming():return "수영 중 · WASD 이동 / Space 물 밖으로 점프\n"+benefits
	if host.interior_visit._elevator_near() or is_instance_valid(host.interior_visit.outdoor_roof_lift_candidate()):return ""
	return "자유 입수 · 탈의/샤워는 선택 · E로 이용\n"+benefits
func _physics_process(delta: float) -> void:
	if not loaded:return
	var current:=_at_roof()
	if not pool_id.is_empty() and current!=_roof:cancel_for_transition()
	if get_tree().paused or host.menu.visible:return
	_clock+=delta;freshness_remaining_s=maxf(0.,freshness_remaining_s-delta);showered=freshness_remaining_s>0.
	if showering:
		if _busy() or not is_instance_valid(_roof):return
		if not _near_station(_roof,"shower"):_finish_shower(false)
		else:
			shower_elapsed+=delta;host.exploration_avatar.set_activity("shower",shower_elapsed)
			if shower_elapsed>=SHOWER_SECONDS:_finish_shower(true);_tell("샤워 완료 · 청결 +%.0f · 상쾌함90초 수영 +10%%"%last_shower_cleanliness_gain)
	for roof: Node3D in _roofs():
		roof.set_pool_access_authorized(water_access_allowed(roof))
		if roof.has_method("update_pool_lounge"):roof.update_pool_lounge(String(host.get("time_id") if host.get("time_id")!=null else "day"),roof==current,delta)
	if is_instance_valid(current):
		var local: Vector3=current.frame.affine_inverse()*host.player.global_position
		if absf(local.y)<.16 and not current.pool_water_region().rect.grow(.30).has_point(Vector2(local.x,local.z)):
			var safe:=_safe_point(host.player.global_position)
			if not safe.is_empty() and current==_roof:_last_safe=safe
func snapshot() -> Dictionary:
	var rooms: Array=[]
	if loaded:
		for roof: Node3D in _roofs():rooms.append({"id":roof.spec.id,"points":roof.pool_preparation_points(),"authorized":water_access_allowed(roof),"gate_layer":roof._pool_gate_body.collision_layer,"shower_water_visible":roof._pool_shower_water.visible,"lounge":roof.pool_lounge_snapshot() if roof.has_method("pool_lounge_snapshot") else {}})
	return {"loaded":loaded,"error":load_error,"pool_id":pool_id,"swimwear_active":host.shop_visit_service.swimwear_active if loaded else false,"showering":showering,"shower_elapsed_s":shower_elapsed,"showered":showered,"entry_requires_preparation":false,"freshness_remaining_s":freshness_remaining_s,"freshness_duration_s":FRESHNESS_SECONDS,"last_shower_cleanliness_gain":last_shower_cleanliness_gain,"total_shower_cleanliness_gain":total_shower_cleanliness_gain,"cleanliness":float(host.interior_visit.facility_interaction.cleanliness) if loaded else 0.,"swimming_speed_multiplier":swimming_speed_multiplier() if loaded else 1.,"swimming_speed_limit_mps":host.player.swimming_speed_limit_mps() if loaded else 0.,"completed_showers":completed_showers,"cancelled_showers":cancelled_showers,"rejected_water_entries":rejected_water_entries,"rooms":rooms,"events":events.duplicate(true),"scope":"Authored roof-local optional changing/shower benefits. Casual clothes may enter/swim directly; freshness90 game seconds gives +10% swim speed, swimsuit +15%, additive cap25%; completed shower gives capped cleanliness+20. Timed effects and outfit restore on leaving, cleanliness remains an existing session wellbeing stat. No real hotel amenity or surveyed interior claim."}
