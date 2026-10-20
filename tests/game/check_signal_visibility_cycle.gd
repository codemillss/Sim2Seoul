extends SceneTree
## Observe production clocks and actual mesh materials for two complete cycles.
## Never assigns signal time or calls advance_signal_time. Headless does not
## claim rendered readability; static LOS/orientation is separately measurable.
var report_path := ""
var scene: Node3D
var network: Node3D
var checks: Array=[]
var transitions: Array=[]
var samples: Array=[]
var started_usec := 0
var requested_hz := 30
var sources: Dictionary={}
var captures: Array=[]
var placements: Array=[]
var captured_phases: Dictionary={}
var view_only := false
var observer_view := "pedestrian"
const INPUTS := ["res://scripts/street_network_detail.gd","res://assets/authored/road_furniture.json","res://scripts/traffic/traffic_manager.gd","res://scripts/traffic/vehicle.gd","res://resources/world_geometry/world.json","res://data/generated/traffic.json","res://assets/authored/neighborhood_population.json","res://../tools/prepare_road_furniture.py","res://../tests/game/check_signal_visibility_cycle.gd"]

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
		elif arg.begins_with("--physics-hz="):requested_hz=int(arg.trim_prefix("--physics-hz="))
		elif arg=="--view-only":view_only=true
	if not report_path.is_absolute_path() or FileAccess.file_exists(report_path) or requested_hz not in [30,60]:push_error("Use a new absolute --report= and --physics-hz=30|60");quit(1);return
	started_usec=Time.get_ticks_usec()
	for path: String in INPUTS:sources[path]=FileAccess.get_sha256(path)
	create_timer(360.,true,false,true).timeout.connect(func():_check("timeout",false);_finish())
	_run.call_deferred()

func _check(title: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":evidence});print("SIGNAL_CYCLE_CHECK ",title," ",passed)
	if not passed:push_warning("SIGNAL_CYCLE_FAIL "+title)

func _v(point: Vector3) -> Array:return [point.x,point.y,point.z]

func _run() -> void:
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_physics_hz=requested_hz;scene.exploration_settings_path="/private/tmp/sim2seoul-signals-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality"
	root.add_child(scene);scene.set_vehicles_running(false);scene.set_pedestrians_running(false)
	for tick: int in range(4):await physics_frame
	network=scene.street_network_detail
	_check("production_scene_network_ready",scene.runtime_ok and network.loaded,{"runtime_error":scene.exploration_error,"network_error":network.load_error})
	if not network.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	_check("signal_timing_is_game_authored",network.design.provenance.schedules.contains("never a live Seoul"))
	var geometry_rows: Array=[];var errors: Array=[];var by_crossing: Dictionary={}
	for row: Dictionary in network.signals:
		var eye: Vector3=(row.opposite_bank_approach if row.kind=="pedestrian" else row.controller_stop_point)+Vector3.UP*1.4
		var target: Vector3=row.head.global_position+row.head.global_basis.z*.145;var delta: Vector3=eye-target;delta.y=0;var front: Vector3=row.head.global_basis.z;front.y=0
		var dot: float=front.normalized().dot(delta.normalized())
		var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye,target,1|32,[scene.player.get_rid()]))
		var ground: float=scene.terrain_surface.ground_y_world(row.point)
		var ok: bool=dot>.94 and hit.is_empty() and is_finite(ground) and absf(row.point.y-ground-.015)<.025
		if not ok:errors.append(row.id)
		geometry_rows.append({"id":row.id,"kind":row.kind,"crossing_id":row.crossing_id,"point":_v(row.point),"head":_v(target),"viewpoint":_v(eye),"front_dot":dot,"static_LOS_clear":hit.is_empty(),"static_obstacle":String(hit.collider.name) if not hit.is_empty() else "","supported":is_finite(ground),"passed":ok})
		if not by_crossing.has(row.crossing_id):by_crossing[row.crossing_id]={"vehicle":0,"pedestrian":0}
		by_crossing[row.crossing_id][row.kind]+=1
	var missing: Array=[]
	for crossing: Dictionary in network.design.crossings:
		var counts: Dictionary=by_crossing.get(crossing.id,{})
		if counts.get("pedestrian",0)!=2 or counts.get("vehicle",0)<1:missing.append(crossing.id)
	_check("accepted_crossings_have_both_banks_and_vehicle_heads",missing.is_empty(),{"crossings":by_crossing,"missing":missing,"runtime_skips":network.skipped})
	_check("actual_heads_supported_face_approach_and_static_LOS",errors.is_empty(),{"errors":errors,"heads":geometry_rows})
	var coverage: Array=network.design.source_signal_coverage
	_check("all_source_crossing_candidates_explicitly_accounted",coverage.size()==79 and coverage.all(func(row: Dictionary)->bool:return row.status in ["accepted","excluded"] and (row.has("crossing_id") or row.has("reason"))),{"rows":coverage})
	_check("no_perpendicular_nearby_green_approaches",int(network.design.preflight.nearby_perpendicular_green_approach_pairs)==0,{"authoring_max_crossing_separation_m":45,"absolute_axis_dot_exclusion_threshold":.65})
	if DisplayServer.get_name()!="headless":
		await _native_observer("pedestrian")
		if view_only:
			await _capture("pedestrian_preview")
			await _native_observer("vehicle")
			await _capture("vehicle_preview");_finish();return
	var previous:="";var flash_on:=0;var flash_off:=0;var material_errors: Array=[];var overlap_errors: Array=[];var wraps:=0;var prior_time: float=network.elapsed_s;var observed_seconds:=0.0
	# Rendering/capture yields may observe fewer physics notifications than a
	# nominal loop budget. Finish by the actual production clock, with an extra
	# third-cycle guard, rather than equating observations with elapsed time.
	for tick: int in range(ceili(float(network.design.cycle.duration_s)*3.0*requested_hz)):
		await physics_frame
		var t: float=network.elapsed_s;var dt: float=fposmod(t-prior_time,float(network.design.cycle.duration_s));observed_seconds+=dt
		if t<prior_time:wraps+=1
		prior_time=t
		if DisplayServer.get_name()!="headless" and wraps==1 and observer_view=="pedestrian":await _native_observer("vehicle")
		var phase: Dictionary=network.signal_phase_snapshot("sejong_marked");var key: String=phase.vehicle+"/"+phase.pedestrian
		if key!=previous:transitions.append({"simulation_seconds":observed_seconds,"cycle_t":t,"vehicle":phase.vehicle,"pedestrian":phase.pedestrian,"wall_seconds":(Time.get_ticks_usec()-started_usec)/1000000.});previous=key
		if phase.pedestrian_flashing:
			if phase.pedestrian_lit:flash_on+=1
			else:flash_off+=1
		if phase.vehicle=="green" and phase.pedestrian=="green":overlap_errors.append(t)
		if DisplayServer.get_name()!="headless" and wraps<2:
			var capture_key: String=observer_view+"_view_vehicle_"+phase.vehicle+"_pedestrian_"+phase.pedestrian
			if phase.pedestrian_flashing:capture_key=observer_view+"_view_pedestrian_flash_"+("lit" if phase.pedestrian_lit else "dark")
			if not captured_phases.has(capture_key):
				captured_phases[capture_key]=true;await _capture(capture_key)
		if tick%maxi(1,requested_hz/4)!=0:continue
		for row: Dictionary in network.signals:
			var actual: Dictionary=network.signal_phase_snapshot(row.crossing_id)
			if row.kind=="vehicle":
				var lit: Array=[]
				for index: int in range(3):
					if row.lenses[index].material_override!=network._materials.off:lit.append(["red","amber","green"][index])
				if lit!=[actual.vehicle] or row.countdown.text!=str(actual.remaining_s):material_errors.append({"t":t,"id":row.id,"lit":lit,"phase":actual,"counter":row.countdown.text})
			else:
				var green_lit: bool=row.green_icon[0].material_override==network._materials.green
				var red_lit: bool=row.red_icon[0].material_override==network._materials.red
				if green_lit!=bool(actual.pedestrian_lit) or red_lit!=(actual.pedestrian=="red") or row.countdown.text!=str(actual.pedestrian_remaining_s):material_errors.append({"t":t,"id":row.id,"green_lit":green_lit,"red_lit":red_lit,"phase":actual})
		samples.append({"t":t,"vehicle":phase.vehicle,"pedestrian":phase.pedestrian,"flashing":phase.pedestrian_flashing,"green_lit":phase.pedestrian_lit})
		if observed_seconds>=float(network.design.cycle.duration_s)*2.0+.2 and wraps>=2:break
	_check("production_clock_naturally_completes_two_cycles",wraps>=2 and observed_seconds>=92.0,{"wraps":wraps,"simulation_seconds":observed_seconds,"wall_seconds":(Time.get_ticks_usec()-started_usec)/1000000.,"transitions":transitions,"no_clock_assignment_or_advance_method":true})
	_check("pedestrian_final_five_seconds_actually_flashes",flash_on>requested_hz and flash_off>requested_hz,{"lit_physics_samples":flash_on,"dark_physics_samples":flash_off})
	_check("real_lenses_and_physical_counters_follow_clock",material_errors.is_empty(),{"errors":material_errors.slice(0,20),"samples":samples.size()})
	_check("vehicle_green_never_overlaps_pedestrian_green",overlap_errors.is_empty(),{"errors":overlap_errors})
	var frozen: float=network.elapsed_s;scene.toggle_menu()
	for tick: int in range(5):await physics_frame
	_check("menu_pauses_signal_clock",network.elapsed_s==frozen)
	scene.toggle_menu()
	for tick: int in range(5):await physics_frame
	_check("resume_restarts_signal_clock",network.elapsed_s!=frozen)
	_finish()

func _native_observer(kind: String) -> void:
	var destination: Dictionary=network.destination("crossing_vehicle" if kind=="vehicle" else "crossing")
	var safe: Dictionary=scene._exploration_destination(destination.point)
	_check("native_"+kind+"_observer_supported",not safe.is_empty())
	if safe.is_empty():return
	observer_view=kind
	var direction: Vector3=destination.toward-safe.point;direction.y=0
	if kind=="pedestrian":
		placements.append({"kind":"actual_production_crossing_shortcut","view":kind,"point":_v(safe.point),"crossing_id":"source_node_921242887"})
		scene._visit_street_detail("crossing")
	else:
		placements.append({"kind":"explicit_native_vehicle_observer_scene_start","view":kind,"point":_v(safe.point),"crossing_id":"source_node_921242887"})
		scene.player.global_transform=Transform3D(Basis.IDENTITY,safe.point);scene.player.require_neutral_input();scene.player.reset_physics_interpolation();scene.player.get_node("Visual").rotation.y=atan2(-direction.x,-direction.z)
		scene.rig.reset_orientation();scene.rig.yaw=float(destination.get("camera_yaw",atan2(-direction.x,-direction.z)));scene.rig.pitch=deg_to_rad(float(destination.get("camera_pitch_degrees",-8.)));scene.rig.requested_distance=float(destination.get("camera_distance_m",4.2));scene.rig.current_distance=scene.rig.requested_distance;scene.rig.snap_to_target_pose()
	for tick: int in range(6):await physics_frame
	var head: Node3D=destination.get("target_head")
	var eye: Vector3=scene.rig.camera.global_position;var target: Vector3=destination.toward;var rendered_blockers: Array=[]
	for row: Dictionary in network.signals:
		if row.head==head:continue
		var box: MeshInstance3D=row.head.get_node("PedestrianSignalCase" if row.kind=="pedestrian" else "HorizontalSignalCase")
		if box.mesh.get_aabb().intersects_segment(box.to_local(eye),box.to_local(target))!=null:rendered_blockers.append(row.id)
	var static_hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye,target,1|32,[scene.player.get_rid()]))
	var pixel: Vector2=scene.rig.camera.unproject_position(target)
	var front_dot: float=head.global_basis.z.dot((eye-target).normalized()) if head!=null else -1.
	var viewport: Vector2=scene.get_viewport().get_visible_rect().size
	_check("native_"+kind+"_camera_sees_signal_front_without_near_case",static_hit.is_empty() and rendered_blockers.is_empty() and scene.rig.current_distance>2.0 and head!=null and not scene.rig.camera.is_position_behind(target) and front_dot>.9 and pixel.x>80 and pixel.x<viewport.x-80 and pixel.y>145 and pixel.y<viewport.y-180,{"rendered_blockers":rendered_blockers,"static_clear":static_hit.is_empty(),"front_dot":front_dot,"head_pixel":[pixel.x,pixel.y],"camera_distance_m":scene.rig.current_distance})

func _capture(title: String) -> void:
	await process_frame;RenderingServer.force_draw(false,0);await RenderingServer.frame_post_draw
	var picture: Image=scene.get_viewport().get_texture().get_image();var path: String=report_path.trim_suffix(".json")+"_daehanmun_"+title+".png"
	var saved: bool=not picture.is_empty() and picture.save_png(path)==OK
	captures.append({"title":title,"path":path,"saved":saved,"cycle_t":network.elapsed_s,"player":_v(scene.player.global_position),"camera":_v(scene.rig.camera.global_position),"camera_distance_m":scene.rig.current_distance,"actual_normal_camera":true})
	_check("native_capture_"+title,saved)

func _finish() -> void:
	var failed: int=checks.filter(func(row: Dictionary)->bool:return not row.passed).size()
	var report: Dictionary={"task":"EXP23_SIGNAL_VISIBILITY_CYCLE","mode":"native_view_preview_only" if view_only else "two_natural_cycles","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"physics_hz":Engine.physics_ticks_per_second,"wall_elapsed_s":(Time.get_ticks_usec()-started_usec)/1000000.,"source_sha256":sources,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"samples":samples,"transitions":transitions,"captures":captures,"placements":placements,"scope":"Production scene and real physics clock for two full cycles without assigning signal time, unless explicitly labelled native_view_preview_only. Actual lens/icon materials, physical counters, bank coverage, source-candidate exclusions, supported placements and static LOS. Native captures use labelled observer scene starts for pedestrian then vehicle views at the new Daehanmun crossing and ordinary third-person camera. Headless is geometry/state evidence only; official siting/timing, all NPC signal compliance and sustained performance are separate."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n");file.close();print("SIGNAL_CYCLE_RESULT ",report.result," checks=",checks.size()," failed=",failed)
	quit(0 if failed==0 else 1)
