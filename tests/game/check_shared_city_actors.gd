extends SceneTree
## Full production city in one of two independent headless processes. Only
## ordinary movement actions are supplied; the manager owns join handoff.
const SCENE := "res://scenes/world/explore_walk.tscn"
const ACTIONS := ["move_forward","move_backward","move_left","move_right","move_fast"]
const USER_SETTINGS := ["user://sim2seoul_quality.json","user://sim2seoul_exploration.json","user://sim2seoul_exploration.json.time.json","user://sim2seoul_character.json"]
var _role:=""
var _peer:=""
var _coord_url:=""
var _report:=""
var _scene: Node3D
var _manager: Node
var _client: Node
var _coord_http: HTTPRequest
var _checks: Array=[]
var _settings_before: Dictionary={}
var _initial_counts: Dictionary={}
var _movement: Dictionary={}
var _remote_before: Dictionary={}
var _remote_after: Dictionary={}
var _remote_rejoin: Dictionary={}
var _started:=0
var _physics_start:=0
var _ai_start:=0.
var _done:=false
var _finishing:=false
var _invite_memory:=""
var _capture_enabled:=false
var _captures: Array=[]

var _context: Dictionary={}
var _restore_before: Dictionary={}
var _restore_after: Dictionary={}
var _action_observations: Array=[]
var _catalog_digest:=""
var _precreate_capsule_writes:=0
var _walk_steps:=0
var _e_presses:=0
var _last_server_ms:=-1.
var _production_stationary_setters:=false
var _input_traces: Array=[]
var _fixture_menu_resumes:=0
var _pause_menu_baseline: Dictionary={}
var _walk_observations: Array=[]

func _trace_input(stage: String) -> void:
	var nearest: Dictionary=_manager.npcs._nearest()
	var npc_distance: float=_manager.npcs.interaction_distance_m();var car_distance: float=_manager.vehicles.interaction_distance_m()
	var trace: Dictionary={"stage":stage,"elapsed_ms":Time.get_ticks_msec()-_started,"paused":paused,"menu":_scene.menu.visible,"gameplay":_scene.input_router.gameplay_enabled,"window_focus":root.has_focus(),"queued_actions":_client._actions.size(),"player":_scene.player.global_position,"on_floor":_scene.player.is_on_floor(),"npc_nearest_id":nearest.get("id",""),"npc_nearest_kind":nearest.get("kind",""),"npc_distance":npc_distance if is_finite(npc_distance) else -1.,"car_distance":car_distance if is_finite(car_distance) else -1.,"interact_held":Input.is_action_pressed("interact"),"e_requires_release":_scene.interior_visit.e_requires_release,"observed_actions":_action_observations.duplicate(true),"client_state":_client.diagnostic()}
	_input_traces.append(trace);print("SHARED_ACTOR_INPUT_TRACE ",JSON.stringify(_json(trace)))

func _resume_fixture_gameplay() -> void:
	if _capture_enabled and _scene.menu.visible:
		_scene.toggle_menu();_fixture_menu_resumes+=1
		_trace_input("normal_menu_resume");await _wait(200)

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--test-role="):_role=argument.trim_prefix("--test-role=")
		if argument.begins_with("--test-coord="):_coord_url=argument.trim_prefix("--test-coord=")
		if argument.begins_with("--test-report="):_report=argument.trim_prefix("--test-report=")
		if argument=="--test-owner-graphics":_capture_enabled=true
	if _role not in ["a","b"] or not _coord_url.begins_with("http://127.0.0.1:") or not _report.is_absolute_path():quit(2);return
	_peer="b" if _role=="a" else "a"
	Engine.max_fps=60
	_run.call_deferred()

func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:result[str(key)]=_json(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for entry: Variant in value:result.append(_json(entry))
		return result
	return value

func _check(name_: String,passed: bool) -> bool:
	_checks.append({"name":name_,"passed":passed})
	if not passed:push_warning("SHARED_CITY_WORLD_CHECK_FAIL role="+_role+" case="+name_)
	return passed

func _settings() -> Dictionary:
	var result: Dictionary={}
	for path: String in USER_SETTINGS:result[path]={"exists":FileAccess.file_exists(path),"sha256":FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""}
	return result

func _wait(milliseconds: int) -> void:
	var until:=Time.get_ticks_msec()+milliseconds
	while not _done and Time.get_ticks_msec()<until:await process_frame

func _until(predicate: Callable,timeout_ms:=10000) -> bool:
	var until:=Time.get_ticks_msec()+timeout_ms
	while not _done and Time.get_ticks_msec()<until:
		if predicate.call():return true
		await process_frame
	return bool(predicate.call())

func _coord(path: String,method:=HTTPClient.METHOD_GET,body: Dictionary={}) -> Dictionary:
	var headers:=PackedStringArray(["Content-Type: application/json","Origin: "+_coord_url])
	var error:=_coord_http.request(_coord_url+path,headers,method,JSON.stringify(body) if method==HTTPClient.METHOD_POST else "")
	if error!=OK:return {}
	var response: Array=await _coord_http.request_completed
	if response[0]!=HTTPRequest.RESULT_SUCCESS or response[1]!=200:return {}
	var parser:=JSON.new()
	if parser.parse((response[3] as PackedByteArray).get_string_from_utf8())!=OK or not parser.data is Dictionary:return {}
	return parser.data

func _stage(value: String) -> bool:
	var result: Dictionary=await _coord("/state",HTTPClient.METHOD_POST,{"role":_role,"stage":value})
	return bool(result.get("stored",false))

func _peer_stage(value: String,timeout_ms:=12000) -> bool:
	var until:=Time.get_ticks_msec()+timeout_ms
	while not _done and Time.get_ticks_msec()<until:
		var state: Dictionary=await _coord("/state")
		var row: Dictionary=state.get(_peer,{})
		if row.get("stages",[]).has("failed"):return false
		if row.get("stages",[]).has(value):return true
		await _wait(200)
	return false

func _remote_ready() -> bool:
	if _manager.remotes.size()!=1:return false
	var remote: Node3D=_manager.remotes.values()[0]
	if not is_instance_valid(remote) or not remote._ready_remote or not is_instance_valid(remote.avatar):return false
	var skin: Dictionary=remote.avatar.textured_model_snapshot(false)
	return bool(skin.get("loaded",false)) and int(skin.get("skeleton_bone_count",0))>0

func _remote_state() -> Dictionary:
	if not _remote_ready():return {}
	var remote: Node3D=_manager.remotes.values()[0]
	var skin: Dictionary=remote.avatar.textured_model_snapshot(false)
	var accepted: Dictionary=remote._samples.back()
	return {"ready":remote._ready_remote,"instance_id":remote.get_instance_id(),"accepted_sequence":remote._last_sequence,"accepted_position":accepted.position,"displayed_position":remote.global_position,"skin_loaded":skin.loaded,"bones":skin.skeleton_bone_count,"physics_processing":remote.is_physics_processing(),"collision_layer":remote.collision_layer,"collision_mask":remote.collision_mask}

func _release_actions() -> void:
	for action: String in ACTIONS:Input.action_release(action)

func _capture_pair(stage: String,target: Node3D=null) -> void:
	if not _capture_enabled:return
	await _resume_fixture_gameplay()
	var safe_ui: bool=not _manager.ui_open and not _manager._overlay.visible and not _manager._invite_output.is_visible_in_tree() and not _scene.menu.visible
	if not _check(stage+"_capture_has_native_display_and_no_invite_ui",DisplayServer.get_name()!="headless" and safe_ui and _remote_ready()):return
	var remote: Node3D=_manager.remotes.values()[0]
	var points: Array[Vector3]=[_scene.player.global_position,remote.global_position]
	if is_instance_valid(target):points.append(target.global_position)
	var focus:=Vector3.ZERO;var span:=0.
	for point: Vector3 in points:focus+=point
	focus=focus/float(points.size())+Vector3.UP*.9
	for left: Vector3 in points:
		for right: Vector3 in points:span=maxf(span,left.distance_to(right))
	var radius:=maxf(5.5,span*1.2+3.)
	var original: Camera3D=root.get_camera_3d()
	var camera:=Camera3D.new();camera.name="FixturePairCaptureCamera";camera.fov=55.;camera.near=.08;camera.far=1400.;_scene.add_child(camera)
	var chosen:=false
	for direction: Vector3 in [Vector3.BACK,Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3(1,0,1).normalized(),Vector3(-1,0,1).normalized(),Vector3(1,0,-1).normalized(),Vector3(-1,0,-1).normalized()]:
		var eye: Vector3=focus+direction*radius+Vector3.UP*2.2
		var clear:=true
		for point: Vector3 in points:
			var query:=PhysicsRayQueryParameters3D.create(eye,point+Vector3.UP*.9,1|32)
			clear=clear and _scene.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
		camera.global_position=eye;camera.look_at(focus)
		for point: Vector3 in points:clear=clear and camera.is_position_in_frustum(point) and camera.is_position_in_frustum(point+Vector3.UP*2.2)
		if clear:chosen=true;break
	if not _check(stage+"_capture_camera_frames_both_physical_actors",chosen):camera.queue_free();return
	var markers: Array[Label3D]=[]
	for index in range(points.size()):
		var marker:=Label3D.new();marker.name="FixtureActorMarker"+str(index);marker.text="LOCAL (test)" if index==0 else "REMOTE (test)" if index==1 else "SHARED TARGET (test)"
		marker.font_size=36;marker.outline_size=8;marker.pixel_size=.004;marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		marker.modulate=Color(.2,.85,1.) if index==0 else Color(1.,.7,.2)
		_scene.add_child(marker);marker.global_position=points[index]+Vector3.UP*(2.8 if index==2 else 2.05);markers.append(marker)
	camera.make_current()
	for frame in range(3):await process_frame
	await RenderingServer.frame_post_draw
	var path:=_report.get_basename()+"_"+stage+".png"
	var image:=root.get_texture().get_image()
	var saved:=image.save_png(path)==OK
	_check(stage+"_original_native_viewport_png_saved",saved and image.get_width()>0 and image.get_height()>0)
	if saved:_captures.append({"stage":stage,"path":path,"sha256":FileAccess.get_sha256(path),"width":image.get_width(),"height":image.get_height(),"camera_position":camera.global_position,"look_at":focus,"actor_positions":points,"remote_skin_loaded":true,"fixture_camera_and_local_remote_markers":true,"product_camera_transform_written":false,"invite_ui_visible":false,"scope":"Original native GPU viewport. Original viewport with a temporary fixture camera and explicit test labels framing both real avatars and, when supplied, the shared NPC or car. Product camera transforms stay unchanged; original camera is restored."})
	if is_instance_valid(original):original.make_current()
	for marker: Label3D in markers:marker.queue_free()
	camera.queue_free();await process_frame
	_check(stage+"_product_camera_restored",root.get_camera_3d()==original)

func _restore_state() -> Dictionary:
	var result: Dictionary={"cars":{},"npcs":{},"player_layer":_scene.player.collision_layer,"player_mask":_scene.player.collision_mask,"camera":root.get_camera_3d().get_instance_id()}
	for id: String in _manager.vehicles._cars:
		var body: CharacterBody3D=_manager.vehicles._cars[id]
		result.cars[id]=[body.collision_layer,body.collision_mask,body.is_physics_processing(),body.process_mode]
	for row: Dictionary in _manager.npcs._actors:
		result.npcs[row.id]=[row.body.collision_layer,row.body.collision_mask,row.body.is_physics_processing(),row.body.process_mode]
	return result

func _entity(id: String) -> Dictionary:
	for row: Dictionary in _client.world.get("entities",[]):
		if row.id==id:return row
	return {}

func _point(value: Array) -> Vector3:return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _choose_context() -> Dictionary:
	var best: Dictionary={};var score:=INF
	for dog: Dictionary in _manager.npcs._actors:
		if dog.kind!="dog":continue
		var human: Dictionary={};var human_distance:=INF
		for row: Dictionary in _manager.npcs._actors:
			if row.kind!="npc":continue
			var distance: float=row.body.global_position.distance_to(dog.body.global_position)
			if distance<human_distance:human=row;human_distance=distance
		if human.is_empty():continue
		var car_id:="";var car_distance:=INF
		for id: String in _manager.vehicles._cars:
			var distance: float=_manager.vehicles._cars[id].global_position.distance_to(dog.body.global_position)
			if distance<car_distance:car_id=id;car_distance=distance
		for direction: Vector3 in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
			var target: Vector3=human.body.global_position+direction*1.8
			var safe: Dictionary=_scene._exploration_destination(target)
			if safe.is_empty() or safe.point.distance_to(target)>1.:continue
			var candidate: float=car_distance+human_distance+safe.point.distance_to(human.body.global_position)
			if candidate<score:
				score=candidate;best={"carId":car_id,"npcId":human.id,"dogId":dog.id,"spawn":[safe.point.x,safe.point.y,safe.point.z]}
	return best

func _fresh_e() -> void:
	await _resume_fixture_gameplay()
	_release_actions();Input.action_release("interact");await _wait(180)
	var event:=InputEventKey.new();event.physical_keycode=KEY_E;event.keycode=KEY_E;event.device=-1;event.pressed=true
	Input.parse_input_event(event);await _wait(120);event=InputEventKey.new();event.physical_keycode=KEY_E;event.keycode=KEY_E;event.device=-1;event.pressed=false
	Input.parse_input_event(event);await _wait(120);_e_presses+=1

func _walk_to(target: Callable,radius:=1.5,timeout_ms:=25000,arrival: Callable=Callable(),minimum_travel_m:=0.0,label: String="point") -> bool:
	await _resume_fixture_gameplay()
	var started:=Time.get_ticks_msec();var until:=started+timeout_ms
	var start: Vector3=_scene.player.global_position;var previous:=start;var travelled:=0.0;var steps_before:=_walk_steps
	var goal:=start;var path: Array=[];var path_at:=0;var reached:=false
	var progress_at:=started;var progress_anchor:=start;var waypoint:=Vector3.INF;var detours: Array=[];var obstruction_traces: Array=[]
	_release_actions();await _wait(180)
	while Time.get_ticks_msec()<until and _client.connected:
		# Focus-loss pause is production behavior, including while this fixture
		# walks. Resume using the normal menu rather than overwriting pause/input.
		await _resume_fixture_gameplay()
		var current: Vector3=_scene.player.global_position
		travelled+=Vector2(current.x-previous.x,current.z-previous.z).length();previous=current
		goal=target.call()
		if Time.get_ticks_msec()>=path_at:
			path.append({"at_ms":Time.get_ticks_msec()-started,"player":current,"goal":goal if goal.is_finite() else null,"paused":paused,"menu":_scene.menu.visible})
			path_at=Time.get_ticks_msec()+500
			while path.size()>60:path.pop_front()
		if not goal.is_finite():_release_actions();await _wait(130);continue
		var difference: Vector3=goal-current;difference.y=0.
		if Vector2(current.x-progress_anchor.x,current.z-progress_anchor.z).length()>.25:
			progress_anchor=current;progress_at=Time.get_ticks_msec()
		if waypoint.is_finite() and Vector2(current.x-waypoint.x,current.z-waypoint.z).length()<.6:waypoint=Vector3.INF
		# A 45m city route is not assumed to be empty. Probe the actual player
		# capsule and production boundary, then walk a bounded local detour.
		# The fixture never writes the actor transform or removes a collider.
		if not waypoint.is_finite() and difference.length()>1.0 and Time.get_ticks_msec()-progress_at>850 and detours.size()<4:
			var obstruction: Dictionary=_walk_obstruction(current,goal)
			obstruction["at_ms"]=Time.get_ticks_msec()-started;obstruction_traces.append(obstruction)
			waypoint=_walk_detour(current,goal,detours)
			if waypoint.is_finite():
				detours.append({"from":current,"waypoint":waypoint,"goal":goal,"obstruction":obstruction});progress_at=Time.get_ticks_msec();progress_anchor=current
		if waypoint.is_finite():difference=waypoint-current;difference.y=0.
		var accepted: bool=bool(arrival.call()) if arrival.is_valid() else Vector2(goal.x-current.x,goal.z-current.z).length()<=radius
		if accepted and travelled>=minimum_travel_m and (minimum_travel_m<=0.0 or _walk_steps>steps_before):
			_release_actions();await _wait(300)
			if not arrival.is_valid() or bool(arrival.call()):reached=true;break
		var camera: Camera3D=_scene.player.movement_camera
		var right:=camera.global_basis.x;right.y=0.;right=right.normalized()
		var forward: Vector3=-camera.global_basis.z;forward.y=0.;forward=forward.normalized()
		var direction:=difference.normalized();var horizontal:=direction.dot(right);var depth:=direction.dot(forward)
		_release_actions()
		if absf(horizontal)>.18:Input.action_press("move_right" if horizontal>0. else "move_left",absf(horizontal))
		if absf(depth)>.18:Input.action_press("move_forward" if depth>0. else "move_backward",absf(depth))
		_walk_steps+=1;await _wait(130)
	_release_actions()
	var final_position: Vector3=_scene.player.global_position
	travelled+=Vector2(final_position.x-previous.x,final_position.z-previous.z).length()
	var nearest: Dictionary=_manager.npcs._nearest()
	var observation: Dictionary={"label":label,"result":"PASS" if reached else "FAIL","start":start,"end":_scene.player.global_position,"last_goal":goal if goal.is_finite() else null,"actual_travelled_xz_m":travelled,"net_xz_m":Vector2(_scene.player.global_position.x-start.x,_scene.player.global_position.z-start.z).length(),"minimum_travel_m":minimum_travel_m,"actual_input_steps":_walk_steps-steps_before,"elapsed_ms":Time.get_ticks_msec()-started,"nearest_id":nearest.get("id",""),"nearest_distance_m":_scene.player.global_position.distance_to(nearest.body.global_position) if not nearest.is_empty() else -1.,"paused":paused,"menu":_scene.menu.visible,"window_focus":root.has_focus(),"path":path,"detours":detours,"obstruction_traces":obstruction_traces}
	_walk_observations.append(observation);print("SHARED_ACTOR_WALK_TRACE ",JSON.stringify(_json(observation)))
	return reached

func _walk_obstruction(origin: Vector3,goal: Vector3) -> Dictionary:
	var contacts: Array=[]
	for index in range(_scene.player.get_slide_collision_count()):
		var hit: KinematicCollision3D=_scene.player.get_slide_collision(index)
		var normal: Vector3=hit.get_normal()
		if absf(normal.y)<.7:
			var body: Object=hit.get_collider()
			contacts.append({"path":str(body.get_path()) if body is Node else str(body),"normal":normal,"kind":"actual_slide_contact"})
	var probe: Dictionary=_walk_capsule_probe(origin,origin+(goal-origin).limit_length(3.0))
	var nearby: Array=[]
	for actor: Dictionary in _manager.npcs._actors:
		if actor.body.global_position.distance_to(origin)<3.0:nearby.append({"id":actor.id,"position":actor.body.global_position,"distance_m":actor.body.global_position.distance_to(origin),"layer":actor.body.collision_layer})
	return {"origin":origin,"goal":goal,"slide_contacts":contacts,"prospective_capsule":probe,"nearby_actors":nearby,"inside_current":_scene.player._inside(origin),"inside_ahead":_scene.player._inside(origin+(goal-origin).normalized()*.2),"motion":_scene.player.locomotion_snapshot(),"paused":paused,"menu":_scene.menu.visible}

func _walk_capsule_probe(origin: Vector3,point: Vector3) -> Dictionary:
	var from: Transform3D=_scene.player.global_transform;from.origin=origin+Vector3.UP*.08
	var motion: Vector3=point-origin;motion.y=0.
	var result:=PhysicsTestMotionResult3D.new()
	var hit: bool=_scene.player.test_move(from,motion,result,.001,false,16)
	var blockers: Array=[]
	if hit:
		for index in range(result.get_collision_count()):
			var normal: Vector3=result.get_collision_normal(index)
			if absf(normal.y)>=.7:continue
			var body: Object=result.get_collider(index)
			blockers.append({"path":str(body.get_path()) if body is Node else str(body),"normal":normal,"class":body.get_class(),"layer":body.collision_layer if body is CollisionObject3D else -1})
	return {"clear":blockers.is_empty(),"native_hit":hit,"blockers":blockers}

func _walk_detour(origin: Vector3,goal: Vector3,previous: Array) -> Vector3:
	var forward: Vector3=goal-origin;forward.y=0.;forward=forward.normalized()
	var selected:=Vector3.INF;var score:=INF
	for radius_: float in [2.5,4.0,6.0]:
		for angle: float in [PI/3.,-PI/3.,PI/2.,-PI/2.,PI*2./3.,-PI*2./3.]:
			var requested: Vector3=origin+forward.rotated(Vector3.UP,angle)*radius_
			var safe: Dictionary=_scene._exploration_destination(requested)
			if safe.is_empty() or safe.point.distance_to(requested)>.5:continue
			var point: Vector3=safe.point
			var inside:=true
			for step in range(1,int(ceil(radius_/.2))+1):
				if not _scene.player._inside(origin.lerp(point,float(step)/ceil(radius_/.2))):inside=false;break
			if not inside or not bool(_walk_capsule_probe(origin,point).clear):continue
			var seen:=false
			for entry: Dictionary in previous:
				if point.distance_to(entry.waypoint)<1.0:seen=true;break
			if seen:continue
			var candidate_score: float=point.distance_to(goal)+radius_*.25
			if candidate_score<score:score=candidate_score;selected=point
	return selected

func _walk_to_actor(id: String,other_id: String) -> bool:
	var arrival: Callable=func()->bool:
		var nearest: Dictionary=_manager.npcs._nearest()
		return not nearest.is_empty() and nearest.id==id and _scene.player.global_position.distance_to(nearest.body.global_position)<=2.5
	return await _walk_to(func()->Vector3:return _actor_walk_goal(id,other_id),0.0,25000,arrival,.2,id)

func _actor_walk_goal(id: String,other_id: String) -> Vector3:
	var row: Dictionary=_manager.npcs._by_id[id];var other: Dictionary=_manager.npcs._by_id[other_id]
	var centre: Vector3=row.body.global_position;var current: Vector3=_scene.player.global_position
	var away: Vector3=centre-other.body.global_position;away.y=0.
	if away.length()<.2:away=Vector3.RIGHT
	away=away.normalized()
	var collider: CollisionShape3D=_manager.npcs._collider(row.body)
	var player_collider: CollisionShape3D=_manager.npcs._collider(_scene.player)
	var actor_radius:=.35;var player_radius:=.35
	if collider!=null and collider.shape is CapsuleShape3D:actor_radius=collider.shape.radius
	if player_collider!=null and player_collider.shape is CapsuleShape3D:player_radius=player_collider.shape.radius
	var clearance:=actor_radius+player_radius+.3
	var candidates: Array=[];var preferred:=Vector3.INF;var preferred_score:=INF
	for ring: float in [maxf(1.4,clearance),maxf(1.9,clearance),maxf(2.25,clearance)]:
		if ring>2.4:continue
		for direction: int in range(8):
			var requested: Vector3=centre+away.rotated(Vector3.UP,TAU*float(direction)/8.)*ring
			var safe: Dictionary=_scene._exploration_destination(requested)
			if safe.is_empty() or safe.point.distance_to(requested)>.5 or safe.point.distance_to(current)<.35:continue
			var point: Vector3=safe.point
			var target_distance: float=point.distance_to(centre)
			if target_distance>2.5 or target_distance<clearance:continue
			var nearest_target:=true
			for actor: Dictionary in _manager.npcs._actors:
				if actor.id!=id and point.distance_to(actor.body.global_position)<=target_distance+.05:nearest_target=false;break
			if nearest_target and point.distance_to(current)<preferred_score:preferred=point;preferred_score=point.distance_to(current)
			# Native full capsule sweep; a small floor clearance avoids treating
			# the standing contact itself as a route obstacle. Actual walking still
			# uses the unchanged grounded controller and collision geometry.
			var from: Transform3D=_scene.player.global_transform;from.origin.y+=.08
			var clear: bool=not _scene.player.test_move(from,point-current)
			candidates.append({"point":point,"nearest_target":nearest_target,"clear":clear})
	var selected:=Vector3.INF;var best:=INF
	for candidate: Dictionary in candidates:
		if not candidate.clear:continue
		var point: Vector3=candidate.point
		var score: float=point.distance_to(current) if candidate.nearest_target else 100.+point.distance_to(preferred)+point.distance_to(current)*.25 if preferred.is_finite() else INF
		if score<best:selected=point;best=score
	return selected

func _npc_goal(id: String,other_id: String) -> Vector3:
	var row: Dictionary=_manager.npcs._by_id[id];var other: Dictionary=_manager.npcs._by_id[other_id]
	var away: Vector3=row.body.global_position-other.body.global_position;away.y=0.
	if away.length()<.2:away=Vector3.RIGHT
	return row.body.global_position+away.normalized()*1.25

func _car_goal() -> Vector3:
	var car: CharacterBody3D=_manager.vehicles._cars[_context.carId]
	var left: Vector3=car.to_global(Vector3(-1.8,0,-.38));var right: Vector3=car.to_global(Vector3(1.8,0,-.38))
	return left if left.distance_to(_scene.player.global_position)<right.distance_to(_scene.player.global_position) else right

func _reaction(kind: String) -> bool:
	for row: Dictionary in _client.world.get("entities",[]):
		if row.reactionKind==kind and float(row.reactionUntilMs)>_last_server_ms:return true
	return false

func _replica_matches() -> bool:
	for row: Dictionary in _manager.npcs._actors:
		var accepted: Dictionary=_entity(row.id)
		if accepted.is_empty() or row.body.global_position.distance_to(_point(accepted.position))>.4:return false
	return true

func _run() -> void:
	_started=Time.get_ticks_msec();_settings_before=_settings()
	_coord_http=HTTPRequest.new();_coord_http.process_mode=Node.PROCESS_MODE_ALWAYS;_coord_http.timeout=3.;_coord_http.body_size_limit=16384;_coord_http.max_redirects=0;root.add_child(_coord_http)
	_scene=load(SCENE).instantiate();var prefix:=_report.get_basename()+"_absent_settings"
	_scene.exploration_settings_path=prefix+"_exploration.json";_scene.quality_settings_path=prefix+"_quality.json";_scene.character_settings_path=prefix+"_character.json"
	root.add_child(_scene)
	for frame in range(3):await process_frame
	for tick in range(6):await physics_frame
	if _scene.menu.visible:_scene.toggle_menu()
	_manager=_scene.shared_city_walk
	if not _check("production_manager_initialized",is_instance_valid(_manager)):
		await _finish();return
	_client=_manager.client
	_client.action_result.connect(func(value: Dictionary):_action_observations.append(value.duplicate(true)))
	_client.snapshot_received.connect(func(value: Dictionary):_last_server_ms=float(value.serverNowMs))
	if not _check("full_actual_city_and_capsule_ready",_scene.runtime_ok and _scene.terrain_surface.loaded and _scene.player.get_node("CollisionShape").shape is CapsuleShape3D):await _finish();return
	_initial_counts={"source_meshes":_scene.city.source_nodes.size(),"collision_objects":_scene.find_children("*","CollisionObject3D",true,false).size(),"catalog":_manager._catalog().size(),"cars":_manager.vehicles._cars.size(),"npc_and_dogs":_manager.npcs._actors.size()}
	_check("full_existing_14cars_28humans_2dogs_catalog",_initial_counts.catalog==44 and _initial_counts.cars==14 and _initial_counts.npc_and_dogs==30 and _initial_counts.source_meshes>100)
	_physics_start=Engine.get_physics_frames();_client.check_service()
	if not _check("actual_service_bootstrap",await _until(func()->bool:return _client.available and not _client.busy())):await _finish();return
	await _stage("ready")
	if _role=="a":
		_context=_choose_context()
		if not _check("actual_existing_actor_fixture_context_found",not _context.is_empty()):await _finish();return
		if not _check("single_safe_precreate_capsule_placement",_scene._commit_exploration_teleport(_point(_context.spawn))):await _finish();return
		_precreate_capsule_writes=1;await _wait(300)
		await _coord("/context",HTTPClient.METHOD_POST,_context)
		if not _check("both_full_games_ready",await _peer_stage("ready",20000)):await _finish();return
		_restore_before=_restore_state();_check("host_create_started",_client.create_room())
		if not _check("host_world_created",await _until(func()->bool:return _client.connected and _manager.world_active)):await _finish();return
		_invite_memory=_client.invite_code();await _coord("/invite",HTTPClient.METHOD_POST,{"code":_invite_memory})
	else:
		var until:=Time.get_ticks_msec()+30000
		while _invite_memory.is_empty() and Time.get_ticks_msec()<until:
			var reply: Dictionary=await _coord("/invite");_invite_memory=String(reply.get("code",""))
			if _invite_memory.is_empty():await _wait(200)
		_context=await _coord("/context");_restore_before=_restore_state()
		if not _check("memory_only_invite_and_public_context_received",not _invite_memory.is_empty() and not _context.is_empty()):await _finish();return
		_check("guest_join_started",_client.join_room(_invite_memory))
	if not _check("two_full_worlds_real_remote_and_shared_catalog",await _until(func()->bool:return _remote_ready() and _manager.world_active and _client.world.get("entities",[]).size()==44,18000)):await _finish();return
	var ids: Array=[]
	for row: Dictionary in _client.world.entities:ids.append(row.id)
	ids.sort();_catalog_digest=JSON.stringify(ids).sha256_text()
	_check("world_authority_matches_role",_manager.npcs.authority==(_role=="a") and bool(_manager.vehicles.diagnostic().host_ai)==(_role=="a"))
	await _stage("joined")
	if not _check("both_worlds_joined",await _peer_stage("joined")):await _finish();return
	if _role=="a":await _capture_pair("joined")
	if _role=="a":
		var before: Dictionary={}
		for row: Dictionary in _manager.npcs._actors:before[row.id]=row.body.global_position
		var cars_before: Dictionary={}
		for id: String in _manager.vehicles._cars:cars_before[id]=_manager.vehicles._cars[id].global_position
		var snapshots: int=_client.received_snapshots;var frames:=Engine.get_physics_frames()
		# Native focus loss may already have opened the production menu. Set the
		# requested test state instead of accidentally closing an existing pause.
		_pause_menu_baseline={"paused":paused,"menu":_scene.menu.visible,"window_focus":root.has_focus()}
		if not _scene.menu.visible:_scene.toggle_menu()
		await _wait(1600)
		var moved:=false;var cars_moved:=false
		for row: Dictionary in _manager.npcs._actors:moved=moved or row.body.global_position.distance_to(before[row.id])>.08
		for id: String in _manager.vehicles._cars:cars_moved=cars_moved or _manager.vehicles._cars[id].global_position.distance_to(cars_before[id])>.08
		_check("host_pause_menu_keeps_shared_AI_physics_and_HTTP_running",paused and moved and cars_moved and _client.received_snapshots>snapshots and Engine.get_physics_frames()>frames+5)
		if _scene.menu.visible:_scene.toggle_menu()
		_check("host_menu_close_restores_unpaused_world",not paused and not _scene.menu.visible)
		_scene.set_pedestrians_running(false);_scene.set_vehicles_running(false);_production_stationary_setters=true;await _stage("stationary")
	else:
		if not _check("host_approved_stationary_phase",await _peer_stage("stationary")):await _finish();return
		_check("guest_replicas_converge_to_approved_host_poses",await _until(_replica_matches,8000))
	await _stage("stationary_ready")
	if not _check("both_ready_for_actual_interactions",await _peer_stage("stationary_ready")):await _finish();return
	if _role=="a":
		if not _check("physical_input_walk_to_actual_npc",await _walk_to_actor(_context.npcId,_context.dogId)):await _finish();return
		_trace_input("before_greet")
		await _fresh_e()
		var greeted: bool=await _until(func()->bool:return _reaction("greet"),6000)
		_trace_input("after_greet")
		if not _check("fresh_E_greet_approved",greeted):await _finish();return
		await _capture_pair("greeting",_manager.npcs._by_id[_context.npcId].body)
		await _stage("greeted")
		if not _check("guest_observed_same_greeting",await _peer_stage("greeting_seen")):await _finish();return
		if not _check("guest_petted_dog",await _peer_stage("petted",35000)):await _finish();return
		_check("host_observes_shared_pet_reaction",await _until(func()->bool:return _reaction("pet"),3000));await _stage("pet_seen")
	else:
		if not _check("host_greeted_npc",await _peer_stage("greeted",35000)):await _finish();return
		_check("guest_observes_same_greeting_reaction",await _until(func()->bool:return _reaction("greet"),3000));await _stage("greeting_seen")
		if not _check("physical_input_walk_to_actual_dog",await _walk_to_actor(_context.dogId,_context.npcId)):await _finish();return
		await _fresh_e()
		if not _check("fresh_E_pet_approved",await _until(func()->bool:return _reaction("pet"),6000)):await _finish();return
		await _stage("petted")
		if not _check("host_observed_same_pet",await _peer_stage("pet_seen")):await _finish();return
	if not _check("physical_input_walk_to_existing_car_door",await _walk_to(_car_goal,.7,35000)):await _finish();return
	await _stage("at_car")
	if not _check("both_near_same_existing_car",await _peer_stage("at_car",40000)):await _finish();return
	if _role=="b":
		await _fresh_e()
		if not _check("guest_E_gets_approved_driver_and_actual_mount",await _until(func()->bool:return _manager.shared_riding(),8000)):await _finish();return
		await _stage("driver")
		if not _check("host_busy_E_rejected",await _peer_stage("busy_seen")):await _finish();return
		var body: CharacterBody3D=_manager.vehicles._cars[_context.carId];var start: Vector3=body.global_position
		_release_actions();await _wait(250);Input.action_press("move_forward");await _wait(1400);Input.action_release("move_forward");await _wait(1300)
		_movement={"drive_start":start,"drive_end":body.global_position,"metres":body.global_position.distance_to(start),"W_press_ms":1400}
		if not _check("actual_W_drives_retained_physical_car",_movement.metres>.2):await _finish();return
		await _stage("driven")
		if not _check("host_observed_driven_car_and_hidden_remote",await _peer_stage("drive_seen")):await _finish();return
		await _fresh_e()
		if not _check("guest_fresh_E_safe_exit_and_server_parked",await _until(func()->bool:return not _manager.shared_riding() and _entity(_context.carId).get("mode")=="parked" and not _scene.player.facility_control,10000)):await _finish();return
		await _stage("parked")
		if not _check("host_claimed_and_released_same_car",await _peer_stage("host_released",35000)):await _finish();return
	else:
		if not _check("guest_claim_visible_to_host",await _peer_stage("driver")):await _finish();return
		if not _check("host_receives_guest_driver_lease_before_busy_E",await _until(func()->bool:return not _entity(_context.carId).get("driverId","").is_empty() and _entity(_context.carId).driverId!=_client.self_id,5000)):await _finish();return
		await _fresh_e()
		var busy: bool=await _until(func()->bool:return String(_manager.vehicles._notice).contains("다른 참가자"),2000)
		_check("actual_host_E_busy_does_not_steal_driver",busy and not _manager.shared_riding() and _entity(_context.carId).driverId!=_client.self_id);await _stage("busy_seen")
		var before: Vector3=_point(_entity(_context.carId).position)
		if not _check("guest_physical_drive_completed",await _peer_stage("driven",16000)):await _finish();return
		_check("host_observes_server_accepted_car_displacement",await _until(func()->bool:return _point(_entity(_context.carId).position).distance_to(before)>.2,5000))
		_check("seated_remote_guest_is_hidden",_manager.remotes.size()==1 and not (_manager.remotes.values()[0] as Node3D).visible)
		_movement={"accepted_car_before":before,"accepted_car_after":_point(_entity(_context.carId).position)};await _stage("drive_seen")
		if not _check("guest_announced_parked",await _peer_stage("parked",15000)):await _finish();return
		if not _check("host_walks_to_parked_same_car",await _walk_to(_car_goal,.7)):await _finish();return
		await _until(func()->bool:return _manager.remotes.size()==1 and (_manager.remotes.values()[0] as Node3D).visible,3000)
		await _capture_pair("after_drive",_manager.vehicles._cars[_context.carId])
		await _fresh_e()
		if not _check("host_can_claim_same_released_car",await _until(func()->bool:return _manager.shared_riding(),8000)):await _finish();return
		await _fresh_e()
		if not _check("host_safe_E_exit_releases_car",await _until(func()->bool:return not _manager.shared_riding() and _entity(_context.carId).get("mode")=="parked",10000)):await _finish();return
		await _stage("host_released")
	if _role=="b":
		_client.leave_room()
		if not _check("guest_leave_restores_AI_collision_camera_capsule",await _until(func()->bool:return not _client.connected and not _client.busy() and not _manager.world_active and not _manager.cleanup_pending,8000)):await _finish();return
		_restore_after=_restore_state();_check("guest_local_state_equals_prejoin_baseline",_restore_after==_restore_before and not _scene.player.facility_control and _scene.player.is_physics_processing())
		await _stage("left")
		if not _check("host_acknowledged_absence",await _peer_stage("absence_seen")):await _finish();return
		_check("guest_rejoin_for_host_loss_case",_client.join_room(_invite_memory))
		if not _check("guest_second_world_joined",await _until(func()->bool:return _client.connected and _manager.world_active and _remote_ready(),10000)):await _finish();return
		await _stage("rejoined")
		if not _check("host_leave_closes_room_and_cleans_guest_world",await _until(func()->bool:return not _client.connected and not _manager.world_active and not _manager.cleanup_pending,12000)):await _finish();return
		await _stage("host_closed_seen")
	else:
		if not _check("guest_left_after_cleanup",await _peer_stage("left")):await _finish();return
		_check("host_removes_guest_actor",await _until(func()->bool:return _client.participant_count==1 and _manager.remotes.is_empty(),6000));await _stage("absence_seen")
		if not _check("guest_second_join_announced",await _peer_stage("rejoined")):await _finish();return
		_client.leave_room()
		_check("host_actual_leave_completed",await _until(func()->bool:return not _client.connected and not _client.busy() and not _manager.world_active,8000))
		_restore_after=_restore_state();_check("host_local_state_equals_prejoin_baseline",_restore_after==_restore_before)
		_check("guest_observed_closed_room",await _peer_stage("host_closed_seen"))
	await _finish()

func _finish() -> void:
	if _done or _finishing:return
	_finishing=true;_release_actions();Input.action_release("interact")
	var simulation: Dictionary={}
	if is_instance_valid(_manager) and is_instance_valid(_client):
		_trace_input("before_finish")
		for id: String in _manager.vehicles._cars:
			var body: CharacterBody3D=_manager.vehicles._cars[id];var history: Array=body.get("_recycle_history")
			simulation[id]={"cycle_count":body.get("_cycle_count"),"last_recycle":history.back() if not history.is_empty() else {}}
	if is_instance_valid(_client):
		_client.leave_room();_check("shutdown_waits_actual_http_leave",await _until(func()->bool:return not _client.busy() and not _client.connected,6000))
	_check("actual_physics_advanced",Engine.get_physics_frames()>_physics_start+10)
	var after:=_settings();_check("actual_user_settings_unchanged",after==_settings_before)
	var no_writes:=true;var prefix:=_report.get_basename()+"_absent_settings"
	for suffix: String in ["_exploration.json","_exploration.json.time.json","_quality.json","_character.json"]:no_writes=no_writes and not FileAccess.file_exists(prefix+suffix)
	_check("scoped_settings_remain_unwritten",no_writes)
	var failed:=0
	for row: Dictionary in _checks:
		if not row.passed:failed+=1
	if failed>0:await _stage("failed")
	var record: Dictionary={"task":"EXP41_FULL_SHARED_ACTORS","role":_role,"result":"PASS" if failed==0 else "FAIL","checks":_checks.size(),"failed":failed,"cases":_checks,"elapsed_ms":Time.get_ticks_msec()-_started,"engine":Engine.get_version_info().string,"world_counts":_initial_counts,"catalog_sha256":_catalog_digest,"public_context":_context,"precreate_capsule_writes":_precreate_capsule_writes,"fixture_capsule_writes_after_create":0,"fresh_E_presses":_e_presses,"walking_Input_steps":_walk_steps,"physical_walk_observations":_walk_observations,"used_production_stationary_setters":_production_stationary_setters,"movement":_movement,"simulation":simulation,"restore_before":_restore_before,"restore_after":_restore_after,"action_results":_action_observations,"input_traces":_input_traces,"fixture_normal_menu_resumes":_fixture_menu_resumes,"pause_menu_baseline":_pause_menu_baseline,"user_settings_before":_settings_before,"user_settings_after":after,"diagnostic":_manager.diagnostic() if is_instance_valid(_manager) else {},"captures":_captures,"render_mode":"native_graphical" if _capture_enabled else "headless","scope":"Two independent full production city processes. Existing 14 cars,28 humans,2 dogs. One safe host capsule placement before create; subsequent travel and E/W interactions use actual Input. Production menu setters stop AI during interaction stages. Physical controller and approved replication acceptance. Native captures, when enabled, use an explicitly labelled temporary fixture camera. No server-owned 3D physics, production authentication or measured capacity. Credentials remain in memory."}
	var file:=FileAccess.open(_report,FileAccess.WRITE)
	if file==null:quit(1);return
	file.store_string(JSON.stringify(_json(record),"  ")+"\n");file.close();file=null
	_done=true;_invite_memory=""
	if is_instance_valid(_scene):_scene.queue_free()
	_coord_http.queue_free();await process_frame;await process_frame
	_scene=null;_manager=null;_client=null;_coord_http=null
	print("SHARED_ACTORS_CHECK role=",_role," result=",record.result," checks=",record.checks," failed=",failed)
	create_timer(.1,true,false,true).timeout.connect(Callable(self,"quit").bind(0 if failed==0 else 1))
