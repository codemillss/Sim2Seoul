extends Node3D
## Indoor game activities. Target metadata locates real authored equipment; all
## approaches retain the player's actual capsule and the existing room bodies.
const RANGE_M := 1.7
const USE_RANGE_M := .95
const SHOWER_RANGE_M := .55
const DEFAULT_DURATION := {"eat":6.0,"shower":12.0,"treadmill":16.0,"weights":12.0,"cycle":12.0,"rowing":12.0}
var host: Node3D
var visit: Node3D
var fullness := 35.0
var cleanliness := 30.0
var workout_distance_m := 0.0
var workout_repetitions := 0
var cycling_distance_m := 0.0
var cycling_revolutions := 0
var rowing_distance_m := 0.0
var rowing_strokes := 0
var completed_counts := {"eat":0,"shower":0,"treadmill":0,"weights":0,"cycle":0,"rowing":0}
var started_counts := {"eat":0,"shower":0,"treadmill":0,"weights":0,"cycle":0,"rowing":0}
var cancelled_counts := {"eat":0,"shower":0,"treadmill":0,"weights":0,"cycle":0,"rowing":0}
var rejected_count := 0
var external_cleanup_count := 0
var _active: Dictionary = {}
var _selected: Dictionary = {}
var _session: Dictionary = {}
var _last_session: Dictionary = {}
var _elapsed := 0.0
var _duration := 0.0
var _source_id := ""
var _room_id := 0
var _use_position := Vector3.ZERO
var _return_position := Vector3.ZERO
var _saved_visual := Transform3D.IDENTITY
var _return_pending := false
var _finish_requested := false
var _paused := false
var _notice := ""
var _notice_remaining := 0.0
var _visuals: Node3D
var _panel: PanelContainer
var _status: Label
var _marker: Label3D

func setup(host_scene: Node3D,visit_node: Node3D) -> bool:
	host=host_scene;visit=visit_node;name="FacilityInteraction"
	process_mode=Node.PROCESS_MODE_ALWAYS
	_panel=PanelContainer.new();_panel.name="FacilityActivityStatus";_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new();style.bg_color=Color(.035,.085,.10,.93)
	style.content_margin_left=12;style.content_margin_right=12;style.content_margin_top=7;style.content_margin_bottom=7
	style.corner_radius_top_left=6;style.corner_radius_top_right=6;style.corner_radius_bottom_left=6;style.corner_radius_bottom_right=6
	_panel.add_theme_stylebox_override("panel",style)
	_status=Label.new();_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_status.add_theme_font_size_override("font_size",15)
	_status.add_theme_color_override("font_color",Color(.91,.97,.88));_status.mouse_filter=Control.MOUSE_FILTER_IGNORE;_panel.add_child(_status)
	host.get_node("Interface").add_child(_panel);_panel.visible=false
	_marker=Label3D.new();_marker.name="NearestFacilityAction";_marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	_marker.font_size=25;_marker.pixel_size=.004;_marker.outline_size=6;_marker.outline_modulate=Color(.025,.075,.08)
	_marker.modulate=Color(.80,1.0,.78);_marker.visible=false;add_child(_marker)
	return true

func _targets() -> Array:
	if not is_instance_valid(visit.room) or visit.room.detail_kit==null or visit.room.detail_kit.facility_kit==null:return []
	return visit.room.detail_kit.facility_kit.interactions

func _context_ready() -> bool:
	return is_instance_valid(host) and is_instance_valid(visit) and visit.active and not visit.on_roof and not visit.in_elevator and not visit.elevator_open and is_instance_valid(visit.room)

func _world(point: Vector3) -> Vector3:return visit.room.to_global(point)

func _same_level(target: Dictionary) -> bool:
	return int(target.get("level",-1))==visit.room.floor_index_at(host.player.global_position) and absf(host.player.global_position.y-_world(target.use_point).y)<.40

func _line_clear(from: Vector3,to: Vector3) -> bool:
	var space := host.get_world_3d().direct_space_state
	for height in [.72,1.35]:
		var query := PhysicsRayQueryParameters3D.create(from+Vector3.UP*height,to+Vector3.UP*height,host.player.collision_mask,[host.player.get_rid()])
		if not space.intersect_ray(query).is_empty():return false
	return true

func _equipment_visible(target: Dictionary) -> bool:
	# Seeing a standing marker is insufficient when a screen separates it
	# from the actual food or machine. Inspect the equipment anchor as well.
	var from: Vector3=host.player.global_position+Vector3.UP*1.15
	var to: Vector3=_world(target.anchor_point)
	var query := PhysicsRayQueryParameters3D.create(from,to,host.player.collision_mask,[host.player.get_rid()])
	return host.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _capsule_clear(point: Vector3) -> bool:
	if not point.is_finite() or not host.player.interior_bounds.has_point(point):return false
	var shape_node: CollisionShape3D=host.player.get_node("CollisionShape")
	var query := PhysicsShapeQueryParameters3D.new();query.shape=shape_node.shape
	query.transform=Transform3D(Basis.IDENTITY,point)*shape_node.transform
	query.collision_mask=host.player.collision_mask;query.exclude=[host.player.get_rid()]
	return host.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _supported(point: Vector3,allowance := .26) -> bool:
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.08,point-Vector3.UP*.35,host.player.collision_mask,[host.player.get_rid()])
	var hit: Dictionary=host.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.normal.y>=.70 and point.y-hit.position.y>=-.015 and point.y-hit.position.y<=allowance

func _walk_segment_clear(from: Vector3,to: Vector3,raised_step := false) -> bool:
	if from.distance_to(to)>RANGE_M+.10 or absf(to.y-from.y)>.24:return false
	if not _line_clear(from,to):return false
	# The treadmill is a 10cm physical deck. Inspect the complete raised
	# capsule corridor and support below it, rather than crossing its solid side.
	var high := maxf(from.y,to.y)+(.018 if raised_step else 0.0)
	var count := maxi(1,int(ceil(from.distance_to(to)/.06)))
	for index in range(count+1):
		var at := from.lerp(to,float(index)/float(count))
		if raised_step:at.y=high
		if not _capsule_clear(at) or not _supported(at):return false
	return _capsule_clear(to) and visit._indoor_target_clear(to)

func _nearest_target() -> Dictionary:
	if not _context_ready() or _paused or not host.player.is_on_floor() or host.player.input_latched:return {}
	var nearest := RANGE_M*RANGE_M
	var result: Dictionary={}
	for target: Dictionary in _targets():
		if not target.has_all(["id","kind","title","level","use_point","anchor_point"]):continue
		if not DEFAULT_DURATION.has(String(target.kind)) or not _same_level(target):continue
		var point: Vector3=_world(target.use_point)
		var offset: Vector3=point-host.player.global_position
		var distance := Vector2(offset.x,offset.z).length_squared()
		if distance>nearest or not _line_clear(host.player.global_position,point) or not _equipment_visible(target):continue
		if not _capsule_clear(point) or not visit._indoor_target_clear(point):continue
		nearest=distance;result=target
	return result

func step(delta: float,paused: bool) -> void:
	_paused=paused
	if is_using():
		var externally_moved: bool=not host.player.facility_control or not _context_ready() or visit.room.get_instance_id()!=_room_id or String(visit.current_spec.get("id",""))!=_source_id
		if not externally_moved:externally_moved=not _same_level(_active) or host.player.global_position.distance_to(_use_position)>.40
		if externally_moved:
			external_cleanup_count+=1;_end(false,false)
	if paused:
		_selected={};_layout();return
	var tick := maxf(0.0,delta)
	_notice_remaining=maxf(0.0,_notice_remaining-tick)
	if _notice_remaining<=0.0:_notice=""
	if is_using():
		if not _return_pending:
			var previous := _elapsed
			_elapsed=minf(_duration,_elapsed+tick) if String(_active.kind)=="eat" else _elapsed+tick
			_update_activity(_elapsed-previous)
			if is_instance_valid(_visuals):_visuals.animate(_elapsed,clampf(_elapsed/maxf(.01,_duration),0.0,1.0),_session)
			_avatar_activity(String(_active.kind),_elapsed)
			_pose()
			if String(_active.kind)=="eat" and _elapsed>=_duration:
				_finish_requested=true
				if not _end(true,true):_return_pending=true
	else:_selected=_nearest_target()
	_layout()

func handle_interact() -> bool:
	if _paused or not _context_ready():return false
	if is_using():
		if String(_active.kind)!="eat" and _elapsed>=.5:_finish_requested=true
		cancel();return true
	_selected=_nearest_target()
	if _selected.is_empty():return false
	var point: Vector3=_world(_selected.use_point)
	var treadmill: bool=String(_selected.kind)=="treadmill"
	var seated: bool=String(_selected.kind) in ["cycle","rowing"]
	var offset: Vector3=point-host.player.global_position
	var use_range := SHOWER_RANGE_M if String(_selected.kind)=="shower" else USE_RANGE_M
	if (not treadmill and Vector2(offset.x,offset.z).length()>use_range) or not _walk_segment_clear(host.player.global_position,point,treadmill):
		rejected_count+=1;_tell("설비 앞 표시 가까이 이동한 뒤 E를 눌러주세요.");return true
	if not host.player.is_on_floor() or host.player.input_latched:return false
	_return_position=host.player.global_position
	_saved_visual=host.player.get_node("Visual").transform
	_active=_selected.duplicate(true);_selected={};_elapsed=0.0
	var kind := String(_active.kind)
	_duration=clampf(float(_active.get("data",{}).get("duration_seconds",DEFAULT_DURATION[kind])),2.0,60.0)
	_session={"id":String(_active.id),"kind":kind,"bites":0,"repetitions":0,"distance_m":0.0,"fullness_gain":0.0,"cleanliness_gain":0.0,"revolutions":0,"strokes":0,"completed":false,"cancelled":false}
	_source_id=String(visit.current_spec.get("id",""));_room_id=visit.room.get_instance_id()
	if treadmill or seated:
		host.player.global_position=point;host.player.reset_physics_interpolation()
	_use_position=host.player.global_position;_return_pending=false;_finish_requested=false
	host.player.set_facility_control(true)
	var yaw := float(_active.get("data",{}).get("facing_yaw",0.0))
	host.player.get_node("Visual").rotation=Vector3(0,yaw,0)
	_visuals=preload("res://scripts/facility_activity_visuals.gd").new();add_child(_visuals)
	_visuals.build(kind,host.player,visit.room,_active)
	_avatar_activity(kind,0.0)
	started_counts[kind]=int(started_counts[kind])+1
	_layout();return true

func _update_activity(delta: float) -> void:
	var kind := String(_active.kind)
	match kind:
		"eat":
			var bites := mini(3,int(floor(_elapsed/(_duration/3.0))))
			while int(_session.bites)<bites:
				_session.bites=int(_session.bites)+1
				var gain := minf(8.0,100.0-fullness);fullness+=gain;_session.fullness_gain=float(_session.fullness_gain)+gain
		"shower":
			var gain := minf(delta*5.0,100.0-cleanliness);cleanliness+=gain;_session.cleanliness_gain=float(_session.cleanliness_gain)+gain
		"treadmill":
			var distance := delta*(6.0/3.6);workout_distance_m+=distance;_session.distance_m=float(_session.distance_m)+distance
		"cycle":
			var distance := delta*(18.0/3.6);cycling_distance_m+=distance;_session.distance_m=float(_session.distance_m)+distance
			var revolutions := int(floor(_elapsed));var gained := revolutions-int(_session.revolutions)
			cycling_revolutions+=maxi(0,gained);_session.revolutions=revolutions
		"rowing":
			var strokes := int(floor(_elapsed/2.4));var gained := maxi(0,strokes-int(_session.strokes))
			rowing_strokes+=gained;rowing_distance_m+=float(gained)*8.0
			_session.strokes=strokes;_session.distance_m=float(_session.distance_m)+float(gained)*8.0
		"weights":
			var repetitions := int(floor(_elapsed/2.0))
			var gained := repetitions-int(_session.repetitions)
			if gained>0:workout_repetitions+=gained;_session.repetitions=repetitions

func _pose() -> void:
	if is_instance_valid(_avatar_node()):return
	var avatar: Node3D=host.player.get_node("Visual")
	match String(_active.kind):
		"eat":avatar.position.y=_saved_visual.origin.y+sin(_elapsed*PI)*.012
		"shower":avatar.rotation.z=sin(_elapsed*2.1)*.025
		"treadmill":avatar.position.y=_saved_visual.origin.y+absf(sin(_elapsed*10.0))*.035;avatar.rotation.z=sin(_elapsed*10.0)*.025
		"weights":avatar.rotation.x=-.035*(1.-cos(_elapsed*PI))*.5

func _avatar_node() -> Node3D:
	var avatar: Node3D=host.get("exploration_avatar") as Node3D
	return avatar if is_instance_valid(avatar) and avatar.has_method("set_activity") else null

func _avatar_activity(kind: String,elapsed: float) -> void:
	var avatar := _avatar_node()
	if is_instance_valid(avatar):avatar.set_activity(kind,elapsed)

func is_using() -> bool:return not _active.is_empty()

func cancel() -> bool:
	if not is_using():return true
	if _end(_finish_requested,true):return true
	_return_pending=true;_tell("돌아갈 자리가 막혀 있습니다. E로 다시 확인합니다.");_layout();return false

func _end(completed: bool,return_to_start: bool) -> bool:
	if not is_using():return true
	var kind := String(_active.kind)
	if return_to_start and kind in ["treadmill","cycle","rowing"]:
		if not _walk_segment_clear(host.player.global_position,_return_position,kind=="treadmill"):return false
		host.player.global_position=_return_position;host.player.reset_physics_interpolation()
	if is_instance_valid(_visuals):
		remove_child(_visuals);_visuals.queue_free()
	_visuals=null
	host.player.get_node("Visual").transform=_saved_visual
	_avatar_activity("",0.0)
	host.player.set_facility_control(false)
	_session["completed"]=completed;_session["cancelled"]=not completed;_session["elapsed"]=_elapsed
	_last_session=_session.duplicate(true)
	if completed:completed_counts[kind]=int(completed_counts[kind])+1
	else:cancelled_counts[kind]=int(cancelled_counts[kind])+1
	var outcome := {"eat":"식사를 마쳤습니다 · 포만감 +%.0f"%float(_session.fullness_gain),"shower":"샤워를 마쳤습니다 · 청결 +%.0f"%float(_session.cleanliness_gain),"treadmill":"운동을 마쳤습니다 · %.1f m"%float(_session.distance_m),"weights":"근력 운동 완료 · %d회"%int(_session.repetitions),"cycle":"사이클 완료 · %.1f m / %d회전"%[float(_session.distance_m),int(_session.revolutions)],"rowing":"로잉 완료 · %.1f m / %d스트로크"%[float(_session.distance_m),int(_session.strokes)]}
	if completed:_tell(String(outcome[kind]))
	else:_tell("이용을 멈췄습니다. 얻은 활동 기록은 유지됩니다.")
	_active={};_session={};_return_pending=false;_finish_requested=false;_selected={}
	return true

func prompt_text() -> String:
	if _paused or not _context_ready():return ""
	if is_using():return "E · 안전한 자리로 돌아가기 재시도" if _return_pending else "E · 이용 멈추기"
	if not _selected.is_empty():
		var offset: Vector3=_world(_selected.use_point)-host.player.global_position
		var use_range := SHOWER_RANGE_M if String(_selected.kind)=="shower" else USE_RANGE_M
		if String(_selected.kind)!="treadmill" and Vector2(offset.x,offset.z).length()>use_range:return "조금 더 가까이 · %s"%String(_selected.title)
		return "E · %s"%String(_selected.title)
	return ""

func _tell(value: String) -> void:_notice=value;_notice_remaining=3.0

func _layout() -> void:
	var show: bool=_context_ready() and not _paused
	_panel.visible=show
	_marker.visible=show and not is_using() and not _selected.is_empty()
	if _marker.visible:
		_marker.global_position=_world(_selected.use_point)+Vector3.UP*.65
		_marker.text=prompt_text()
	if not show:return
	var line := "포만감 %.0f · 청결 %.0f  |  운동 %.1f m · 근력 %d회"%[fullness,cleanliness,workout_distance_m,workout_repetitions]
	line+="\n사이클 %.1f m · %d회전  |  로잉 %.0f m · %d스트로크"%[cycling_distance_m,cycling_revolutions,rowing_distance_m,rowing_strokes]
	if is_using():
		var activity := {"eat":"식사","shower":"샤워","treadmill":"러닝머신","weights":"덤벨 운동","cycle":"실내 사이클","rowing":"로잉머신"}
		var count := " · %d / 3 입"%int(_session.bites) if String(_active.kind)=="eat" else (" · %d회"%int(_session.repetitions) if String(_active.kind)=="weights" else "")
		var timing := "%.1f / %.1f초"%[_elapsed,_duration] if String(_active.kind)=="eat" else "%.1f초 이용 중 · E로 종료"%_elapsed
		line="%s · %s%s\n%s"%[String(activity[String(_active.kind)]),timing,count,line]
		if _return_pending:line+="\n복귀 자리 확인 대기 · E로 재시도"
	elif not _notice.is_empty():line=_notice+"\n"+line
	_status.text=line
	var view: Vector2=host.get_viewport().get_visible_rect().size
	_panel.custom_minimum_size.x=minf(480.0,maxf(1.0,view.x-32.0))
	_panel.size=Vector2(_panel.custom_minimum_size.x,_panel.get_combined_minimum_size().y)
	var bottom := view.y-16.0
	if is_instance_valid(host.attribution_label) and host.attribution_label.is_visible_in_tree():
		bottom=minf(bottom,host.attribution_label.get_global_rect().position.y-10.0)
	_panel.position=Vector2(16.0,maxf(0.0,bottom-_panel.size.y))

func status_rect() -> Rect2:
	return _panel.get_global_rect() if is_instance_valid(_panel) and _panel.is_visible_in_tree() else Rect2()

func snapshot() -> Dictionary:
	return {"active":is_using(),"kind":String(_active.get("kind","")),"target_id":String(_active.get("id","")),"elapsed":_elapsed,"duration":_duration,"fullness":fullness,"cleanliness":cleanliness,"workout_distance_m":workout_distance_m,"workout_repetitions":workout_repetitions,
		"cycling_distance_m":cycling_distance_m,"cycling_revolutions":cycling_revolutions,"rowing_distance_m":rowing_distance_m,"rowing_strokes":rowing_strokes,"completed_counts":completed_counts.duplicate(),"started_counts":started_counts.duplicate(),"cancelled_counts":cancelled_counts.duplicate(),"rejected_count":rejected_count,"external_cleanup_count":external_cleanup_count,"session":_session.duplicate(true),"last_session":_last_session.duplicate(true),
		"selected_target_id":String(_selected.get("id","")),"targets":_targets().duplicate(true),"visual":_visuals.snapshot() if is_instance_valid(_visuals) else {},"control_locked":host.player.facility_control if is_instance_valid(host) else false,"return_pending":_return_pending,"paused":_paused,"use_position":_use_position,"return_position":_return_position,"prompt":prompt_text(),"status_text":_status.text if is_instance_valid(_status) else "","status_rect":status_rect(),"notice":_notice}

func _exit_tree() -> void:
	if is_instance_valid(_panel):_panel.queue_free()
	if is_instance_valid(host) and is_instance_valid(host.player) and is_using():
		host.player.get_node("Visual").transform=_saved_visual;_avatar_activity("",0.0);host.player.set_facility_control(false)
