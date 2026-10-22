extends SceneTree
## Read-only placement search on the production source/TIN/native city. Does not
## modify source files, move actors or remove colliders. Candidate bodies are
## geometric queries, not rental inventory or accepted actual rides.
var scene: Node3D
var service: Node3D
var report_path := "/tmp/sim2seoul-mobility-placement.json"
var results: Array = []
var ready_error := ""
var started := 0
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path=arg.trim_prefix("--report=")
	Engine.max_fps=0;started=Time.get_ticks_msec();create_timer(180.,true,false,true).timeout.connect(func()->void:ready_error="bounded_probe_timeout";_finish());_run.call_deferred()
func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Dictionary:
		var out: Dictionary={}
		for key: Variant in value:out[str(key)]=_json(value[key])
		return out
	if value is Array:
		var out: Array=[]
		for item: Variant in value:out.append(_json(item))
		return out
	return value
func _ticks(count: int) -> void:
	for index: int in range(count):await physics_frame
func _candidate(route: Dictionary, segment: int, fraction: float, side_offset: float) -> Dictionary:
	var a: Array=route.xz[segment];var b: Array=route.xz[segment+1]
	var start: Vector3=scene.city.to_global(Vector3(a[0],0,a[1]));var end: Vector3=scene.city.to_global(Vector3(b[0],0,b[1]))
	var direction: Vector3=(end-start).normalized();var side:=Vector3(direction.z,0,-direction.x)
	var desired: Vector3=start.lerp(end,fraction)+side*side_offset
	var yaw:=atan2(-direction.x,-direction.z)
	var result: Dictionary={"route":route.id,"segment":[segment,segment+1],"fraction":fraction,"side_offset_m":side_offset,"desired":desired,"yaw":yaw,"compact_sign":true,"passed":false,"reason":""}
	var support: Dictionary=service._ground(desired)
	if support.is_empty():result.reason="native_support_missing";return result
	desired=support.point;result.point=desired
	var basis: Basis=service._pose_basis(desired,yaw)
	if not service._footprint_allowed(desired,basis):result.reason="source_body_footprint";return result
	for local: Vector3 in [Vector3.ZERO,Vector3(-.36,0,-.96),Vector3(.36,0,-.96),Vector3(-.36,0,.96),Vector3(.36,0,.96)]:
		var at: Vector3=desired+basis*local;var source: Vector3=scene.city.to_local(at)
		if not service._walk_index.contains(Vector2(source.x,source.z)) or service._road_index.contains(Vector2(source.x,source.z)):result.reason="parked_body_not_exclusive_walk";return result
	for local: Vector3 in [Vector3(-.75,0,.75),Vector3(0.,0,.75),Vector3(-.55,0,.55),Vector3(.55,0,.55)]:
		var at: Vector3=desired+basis*local;var source: Vector3=scene.city.to_local(at)
		if not service._source_allowed(at) or not service._walk_index.contains(Vector2(source.x,source.z)) or service._ground(at).is_empty():result.reason="source_station_fixture";result.failed_fixture={"local":local,"at":at,"source_allowed":service._source_allowed(at),"walk":service._walk_index.contains(Vector2(source.x,source.z)),"ground":not service._ground(at).is_empty()};return result
	var sign_query:=PhysicsShapeQueryParameters3D.new();var sign_box:=BoxShape3D.new();sign_box.size=Vector3(1.52,1.94,.14);sign_query.shape=sign_box;sign_query.collision_mask=1|32;sign_query.margin=.005;sign_query.transform=Transform3D(Basis(Vector3.UP,yaw),desired+Basis(Vector3.UP,yaw)*Vector3(0.,2.45,.75))
	if not scene.get_world_3d().direct_space_state.intersect_shape(sign_query,1).is_empty():result.reason="native_upper_sign";return result
	var excludes: Array[RID]=[scene.player.get_rid(),support.rid]
	if is_instance_valid(scene.terrain_surface.support):excludes.append(scene.terrain_surface.support.get_rid())
	if not service._clear_box(desired+Vector3.UP*.035,basis,excludes):result.reason="native_parked_body";return result
	var previous: Vector3=desired
	for index: int in range(1,21):
		var flat: Vector3=desired+direction*(float(index)*.2);var ground: Dictionary=service._ground(flat)
		if ground.is_empty():result.reason="departure_ground";return result
		var at: Vector3=ground.point;var pose: Basis=service._pose_basis(at,yaw)
		if not service._footprint_allowed(at,pose):result.reason="departure_source_footprint";return result
		for local: Vector3 in [Vector3.ZERO,Vector3(-.36,0,-.96),Vector3(.36,0,-.96),Vector3(-.36,0,.96),Vector3(.36,0,.96)]:
			var sample: Vector3=at+pose*local;var source: Vector3=scene.city.to_local(sample)
			if not service._walk_index.contains(Vector2(source.x,source.z)) or service._road_index.contains(Vector2(source.x,source.z)):result.reason="departure_not_exclusive_walk";return result
		if not service._clear_box(previous+Vector3.UP*.035,pose,excludes,at-previous):result.reason="departure_native_sweep";return result
		previous=at
	var observers: Array=[]
	for local: Vector3 in [Vector3(1.90,0,.1),Vector3(-1.90,0,.1),Vector3(1.65,0,.75),Vector3(-1.65,0,.75)]:
		var safe: Dictionary=scene.interior_visit._safe_external_point(desired+basis*local)
		if safe.is_empty():continue
		var visible:=true
		for h: float in [.65,1.20]:
			var ray:=PhysicsRayQueryParameters3D.create(safe.point+Vector3.UP*h,desired+Vector3.UP*h,1|4|8|32,[scene.player.get_rid()])
			if not scene.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():visible=false
		if visible:observers.append(safe.point)
	if observers.is_empty():result.reason="native_observer_or_LOS";return result
	result.observers=observers;result.passed=true;return result
func _run() -> void:
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/mobility-placement-settings-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(8)
	service=scene.city_bike_service
	if not scene.runtime_ok or not service.loaded:ready_error=scene.exploration_error+" / "+service.load_error;_finish();return
	if scene.menu.visible:scene.toggle_menu()
	scene.set_free_roam(true);scene.player.set_physics_process(false)
	var routes: Array=scene.city.public_data.routes.duplicate();routes.append_array(scene.neighborhood_population.design.routes)
	var specs: Array=[{"id":"city_plaza","segments":[17,29,31,97]}, {"id":"coverage_walk_09_0","segments":[0]}, {"id":"coverage_walk_05_0","segments":[0,1,2]}, {"id":"coverage_walk_07_0","segments":[0,1]}, {"id":"coverage_walk_00_0","segments":[0,1,2,3]}, {"id":"coverage_walk_08_0","segments":[1]}]
	for spec: Dictionary in specs:
		var route: Dictionary={}
		for row: Dictionary in routes:
			if row.id==spec.id:route=row;break
		if route.is_empty():results.append({"route":spec.id,"passed":false,"reason":"missing_route"});continue
		for segment: int in spec.segments:
			for fraction: float in [.1,.2,.3,.4,.5,.6,.7,.8,.9]:
				for offset: float in [0.,-.4,.4,-.8,.8,-1.2,1.2,-1.6,1.6]:results.append(_candidate(route,segment,fraction,offset))
		print("PLACEMENT_ROUTE ",route.id," pass=",results.filter(func(row: Dictionary)->bool:return row.get("route")==route.id and row.passed).size())
	_finish()
func _finish() -> void:
	var inputs: Dictionary={}
	for path: String in ["res://resources/world_geometry/world.json","res://data/generated/public_walk.json","res://assets/authored/neighborhood_population.json","res://assets/authored/bike_service.json","res://assets/authored/scooter_service.json","res://scripts/city_bike_service.gd","res://scripts/city_scooter_service.gd","res://assets/authored/bus_service.json","res://assets/authored/road_furniture.json","res://data/generated/terrain_surface.json","res://../tests/game/probe_mobility_distribution_placement.gd"]:inputs[path]=FileAccess.get_sha256(path)
	var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(_json({"task":"mobility_distribution_candidate_search","ready_error":ready_error,"results":results,"source_hashes":inputs,"elapsed_ms":Time.get_ticks_msec()-started,"scope":"Geometric candidate queries with retained source geometry and original native actors. No actual ride/E/graphics acceptance; per-site ride suite is separate."}),"  "));file.close();print("PLACEMENT_REPORT ",results.size()," accepted=",results.filter(func(row: Dictionary)->bool:return row.passed).size());quit(0 if ready_error.is_empty() else 1)
