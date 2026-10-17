extends "res://../tests/game/check_street_scene.gd"
## Production actors remain continuous. Only the player and explicit temporary
## obstacle fixtures are placed at scenario starts; every NPC step is physical.
var _began_ms:=0
var _contact_failures: Array=[]

func _check(title: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":_json(evidence)})
	if not passed:push_warning("PEDESTRIAN_AVOIDANCE_CHECK_FAIL "+title)

func _group(id: String) -> Dictionary:
	for group: Dictionary in scene.street_pedestrians.groups:
		if group.id==id:return group
	return {}

func _all_actors() -> Array:
	var result: Array=scene.pedestrians.duplicate()
	for row: Dictionary in scene.street_pedestrians.actors:result.append(row.body)
	return result

func _contacts(body: CharacterBody3D) -> Array:
	var shape: CollisionShape3D=body.get_node("CollisionShape")
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape.shape;query.transform=shape.global_transform
	query.collision_mask=2|4|8;query.exclude=[body.get_rid()];query.margin=-.002
	var result:=[]
	for contact: Dictionary in scene.get_world_3d().direct_space_state.intersect_shape(query,8):result.append(String(contact.collider.name))
	return result

func _passing(title: String,group: Dictionary,dog: bool,legacy: bool=false) -> void:
	scene.set_pedestrians_running(false)
	var module: Node3D=scene.street_pedestrians;var before_s: float=group.station;var direction: int=group.direction
	var obstacle_s: float=before_s+direction*1.8
	var obstacle: Vector3=module._at(group,obstacle_s)+Vector3.UP*.065
	if not await _pose(title+"_stationary_player_start",obstacle):scene.set_pedestrians_running(true);return
	var actor: CharacterBody3D=group.members[0].body
	var start:=actor.global_position;var previous:=start;var maximum_offset:=0.;var maximum_step:=0.;var min_player:=INF
	var floor_failures:=0;var overlap_failures:=[];var saw_pass:=false;var rejoined:=false;var saw_lane:=false;var leash_max:=0.;var leashes_hidden:=0;var path:=[];var maximum_separation:=0.
	scene.set_pedestrians_running(true)
	for tick in range(900):
		await _ticks(1)
		var at:=actor.global_position;var offset: float=absf(group.get("avoidance_offset_m",0.))
		maximum_offset=maxf(maximum_offset,offset);maximum_step=maxf(maximum_step,Vector2(at.x-previous.x,at.z-previous.z).length());previous=at
		min_player=minf(min_player,Vector2(at.x-obstacle.x,at.z-obstacle.z).length())
		saw_lane=saw_lane or group.get("avoidance_count",0)>0
		if (group.station-obstacle_s)*direction>1.0:saw_pass=true
		if saw_pass and offset<.10 and group.get("avoidance_plan",[]).is_empty():rejoined=true
		if not actor.is_on_floor():floor_failures+=1
		if dog:
			var companion: CharacterBody3D=group.members[1].body
			maximum_separation=maxf(maximum_separation,actor.global_position.distance_to(companion.global_position))
			leash_max=maxf(leash_max,group.leash.global_basis.y.length())
			if not group.leash.visible:leashes_hidden+=1
		if tick%6==0:
			path.append({"tick":tick,"position":at,"station_m":group.station,"offset_m":offset,"state":group.state})
			for row: Dictionary in group.members:
				var contacts:=_contacts(row.body)
				if not contacts.is_empty() and overlap_failures.size()<8:overlap_failures.append({"tick":tick,"body":String(row.body.name),"contacts":contacts})
		if rejoined:break
	var evidence:={"legacy_adapter":legacy,"start":start,"end":actor.global_position,"station_start_m":before_s,"player_station_m":obstacle_s,"station_end_m":group.station,"direction":direction,"maximum_offset_m":maximum_offset,"maximum_step_m":maximum_step,"minimum_player_distance_m":min_player,"groundless_ticks":floor_failures,"contacts":overlap_failures,"physical_path":path,"pass":saw_pass,"rejoined":rejoined}
	_check(title+".physically_sidesteps_passes_stationary_player_and_rejoins_original_route",saw_lane and maximum_offset>.5 and maximum_offset<=1.30 and saw_pass and rejoined,evidence)
	_check(title+".bounded_physical_steps_ground_and_no_actor_overlap",maximum_step<(1.2/60.+.003 if legacy else 1.05/60.+.003) and min_player>.54 and floor_failures<=2 and overlap_failures.is_empty(),evidence)
	if dog:_check(title+".keeper_dog_stay_together_with_visible_short_leash",maximum_separation<1.15 and leash_max<1.4 and leashes_hidden==0,{"maximum_pair_separation_m":maximum_separation,"maximum_leash_m":leash_max,"hidden_ticks":leashes_hidden})
	observations[title]=evidence
	await _pose(title+"_player_clears_route",scene.city.to_global(Vector3(-5,.08,100)))

func _wall(title: String,frame: Transform3D,size: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new();body.name=title;body.collision_layer=1;body.collision_mask=0
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box;body.add_child(shape);scene.add_child(body);body.global_transform=frame
	return body

func _narrow_blocked() -> void:
	var group:=_group("plaza_west");var module: Node3D=scene.street_pedestrians
	scene.set_pedestrians_running(false)
	var start_s: float=group.station;var sign: int=group.direction
	var centre: Vector3=module._at(group,start_s+sign*1.2)
	var tangent: Vector3=module._tangent(group,start_s);var side:=Vector3(tangent.z,0,-tangent.x)
	var basis:=Basis(side,Vector3.UP,tangent)
	var walls:=[]
	for multiplier in [-1.,1.]:walls.append(_wall("ExplicitNarrowPassingWall",Transform3D(basis,centre+side*.67*multiplier+Vector3.UP),Vector3(.30,2.,6.0)))
	await _ticks(2)
	await _pose("narrow_stationary_player",module._at(group,start_s+sign*1.7)+Vector3.UP*.07)
	var actor: CharacterBody3D=group.members[0].body;var stopped:=0;var min_distance:=INF;var max_offset:=0.;var wall_contacts:=[];var previous:=actor.global_position
	scene.set_pedestrians_running(true)
	for tick in range(230):
		await _ticks(1)
		var at:=actor.global_position
		if at.distance_to(previous)<.0005:stopped+=1
		previous=at;min_distance=minf(min_distance,Vector2(at.x-scene.player.global_position.x,at.z-scene.player.global_position.z).length());max_offset=maxf(max_offset,absf(group.get("avoidance_offset_m",0.)))
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=group.members[0].collider.shape;query.transform=group.members[0].collider.global_transform;query.collision_mask=1;query.margin=-.002;query.exclude=[actor.get_rid()]
		for contact: Dictionary in scene.get_world_3d().direct_space_state.intersect_shape(query,8):
			if walls.has(contact.collider) and wall_contacts.size()<4:wall_contacts.append({"tick":tick,"wall":String(contact.collider.name)})
	_check("narrow.actual_closed_sides_wait_or_reverse_without_wall_player_penetration",stopped>20 and max_offset<.26 and min_distance>.54 and wall_contacts.is_empty(),{"waiting_ticks":stopped,"maximum_offset_m":max_offset,"minimum_player_m":min_distance,"wall_penetrations":wall_contacts,"original_direction":sign,"final_direction":group.direction,"state":group.state})
	for wall in walls:wall.queue_free()
	await _pose("narrow_player_clears",scene.city.to_global(Vector3(-5,.08,100)))
	var before:=actor.global_position;var resume_path:=[];var resume_distance:=0.;var resume_excursion:=0.;var resume_previous:=before
	var resume_moving_ticks:=0;var resume_groundless:=0;var resume_contacts:=[];var resume_max_offset:=0.;var resume_max_step:=0.;var resume_blocked_ticks:=0
	for tick in range(180):
		await _ticks(1)
		var at:=actor.global_position;var step:=Vector2(at.x-resume_previous.x,at.z-resume_previous.z).length()
		resume_distance+=step;resume_max_step=maxf(resume_max_step,step);resume_previous=at;resume_excursion=maxf(resume_excursion,at.distance_to(before))
		if step>.001:resume_moving_ticks+=1
		if not actor.is_on_floor():resume_groundless+=1
		if not String(group.blocked_reason).is_empty() or group.state=="waiting":resume_blocked_ticks+=1
		resume_max_offset=maxf(resume_max_offset,absf(group.get("avoidance_offset_m",0.)))
		if tick%3==0:
			var contacts:=_contacts(actor)
			if not contacts.is_empty():resume_contacts.append({"tick":tick,"contacts":contacts})
			var nearby:=[]
			for other: CharacterBody3D in _all_actors():
				if other!=actor and other.global_position.distance_to(at)<3.:nearby.append({"body":String(other.name),"position":other.global_position,"distance_m":other.global_position.distance_to(at)})
			resume_path.append({"tick":tick,"position":at,"station_m":group.station,"direction":group.direction,"state":group.state,"blocked_reason":group.blocked_reason,"offset_m":group.get("avoidance_offset_m",0.),"plan_waypoints":group.get("avoidance_plan",[]).size(),"nearby":nearby})
	# A patrol may reach an endpoint, turn, and finish near its start. Net
	# displacement alone incorrectly rejected a real 2.47m physical walk.
	# Count actual bounded steps and retain the entire route/turn observation.
	_check("narrow.resumes_when_actual_corridor_is_clear",resume_distance>2.0 and resume_moving_ticks>100 and resume_excursion>.5 and resume_groundless==0 and resume_blocked_ticks==0 and resume_contacts.is_empty() and resume_max_offset<.03 and resume_max_step<1.05/60.+.003,{"start":before,"end":actor.global_position,"actual_distance_m":resume_distance,"maximum_excursion_m":resume_excursion,"moving_ticks":resume_moving_ticks,"groundless_ticks":resume_groundless,"blocked_ticks":resume_blocked_ticks,"actor_contacts":resume_contacts,"maximum_offset_m":resume_max_offset,"maximum_step_m":resume_max_step,"route_length_m":group.length,"resume_path":resume_path,"measurement_basis":"Per-tick actual horizontal travel; a normal endpoint turn can cancel net displacement. Diagnostic preserved the original failed net-only acceptance and its 2.47m real walk."})

func _menus() -> void:
	var starts:=[]
	for actor: CharacterBody3D in _all_actors():starts.append(actor.global_transform)
	scene.movement_switch.set_pressed(false);await _ticks(90)
	var maximum:=0.
	for index in range(starts.size()):maximum=maxf(maximum,_all_actors()[index].global_position.distance_to(starts[index].origin))
	_check("checkbox.all_ten_original_and_added_people_dogs_stop",not scene.street_pedestrians.running and not scene.exploration_pedestrians.running and maximum<.002,{"maximum_drift_m":maximum})
	scene.movement_switch.set_pressed(true);await _ticks(60)
	await _menu_edge();var frozen:=[]
	for actor: CharacterBody3D in _all_actors():frozen.append(actor.global_transform)
	var module_time: float=scene.street_pedestrians.elapsed;var clock:=Time.get_ticks_msec()
	for index in range(12):await process_frame
	var same:=true
	for index in range(frozen.size()):same=same and frozen[index]==_all_actors()[index].global_transform
	_check("menu.actual_scene_tree_pause_freezes_every_physical_pedestrian",paused and same and scene.street_pedestrians.elapsed==module_time,{"real_elapsed_ms":Time.get_ticks_msec()-clock,"paused":paused})
	await _menu_edge()

func _run() -> void:
	_began_ms=Time.get_ticks_msec()
	for path in ["res://scripts/street_pedestrians.gd","res://scripts/pedestrian_corridor_avoidance.gd","res://scripts/exploration_pedestrian_avoidance.gd","res://scripts/explore_walk.gd","res://scripts/npc/pedestrian.gd","res://assets/authored/street_pedestrians.json","res://../tests/game/check_pedestrian_avoidance.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	scene=load("res://scenes/world/explore_walk.tscn").instantiate()
	_settings_path="/private/tmp/sim2seoul-pedestrian-avoidance-"+str(OS.get_process_id())+".json"
	var settings:=FileAccess.open(_settings_path,FileAccess.WRITE);settings.store_string(JSON.stringify({"schema_version":1,"speed_id":"brisk","free_roam":true}));settings.close()
	scene.exploration_settings_path=_settings_path;scene.quality_settings_path=_settings_path+".quality.json"
	root.add_child(scene);await _ticks(12)
	_check("startup.production_six_walkers_two_dogs_and_two_adapted_legacy_npcs",scene.runtime_ok and scene.street_pedestrians.loaded and is_instance_valid(scene.get("exploration_pedestrians")) and scene.exploration_pedestrians.loaded,{"error":scene.exploration_error})
	if not scene.runtime_ok or not is_instance_valid(scene.get("exploration_pedestrians")):_finish();return
	if scene.menu.visible:await _menu_edge()
	visit=scene.interior_visit;original_inventory=_inventory()
	await _passing("clear_wide_walk",_group("plaza_west"),false)
	await _passing("dog_pair",_group("plaza_dog"),true)
	var legacy: Dictionary=scene.exploration_pedestrians.groups[1]
	await _passing("legacy_person",legacy,false,true)
	await _narrow_blocked();await _menus()
	var appearances:=[]
	for row: Dictionary in scene.street_pedestrians.actors:
		if row.kind=="walker":appearances.append(str(row.avatar._materials.skin.albedo_color))
	var unique:=[]
	for colour in appearances:
		if not unique.has(colour):unique.append(colour)
	_check("appearance.six_distinct_authored_skin_colours_without_identity_labels",unique.size()==6,{"actual_skin_colours":appearances})
	_check("regression.source_collision_inventory_unchanged",original_inventory==_inventory(),{"source_bodies":original_inventory.size()})
	var changed:=[]
	for path: String in source_hashes:
		if source_hashes[path]!=FileAccess.get_sha256(path):changed.append(path)
	_check("sources.frozen_during_run",changed.is_empty(),{"changed":changed})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;paused=false;_movement();_e(false)
	var failed:=0
	for check: Dictionary in checks:
		if not check.passed:failed+=1
	var report:={"task":"pedestrian_avoidance","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"source_sha256":source_hashes,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"observations":observations,"scenario_starts":placements,"wall_elapsed_seconds":(Time.get_ticks_msec()-_began_ms)/1000.,"scope":"Actual production controllers, stationary-player passing and original-route rejoin, keeper/dog cohesion, explicit narrow-wall failure fixture, dynamic actor overlap and real menu/checkbox signals. No NPC placement or per-step teleport. Only scenario-start player placements and removable test walls. Local passing is game authored, not a validated global crowd model, measured walking behaviour, native human control, performance or other-Mac acceptance."}
	var output:=FileAccess.open(report_path,FileAccess.WRITE)
	if output!=null:output.store_string(JSON.stringify(_json(report),"\t")+"\n");output.close()
	else:failed+=1
	print("PEDESTRIAN_AVOIDANCE_TEST ","PASS" if failed==0 else "FAIL"," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)
