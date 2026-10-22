extends SceneTree
var scene: Node3D
func _initialize() -> void:run.call_deferred()
func encode(v: Variant) -> Variant:
	if v is Vector3:return [v.x,v.y,v.z]
	if v is Dictionary:
		var out: Dictionary={}
		for key: Variant in v:out[str(key)]=encode(v[key])
		return out
	if v is Array:
		var out: Array=[]
		for row: Variant in v:out.append(encode(row))
		return out
	return v
func run() -> void:
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/police-campus-probe-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";root.add_child(scene)
	for index: int in range(8):await physics_frame;await process_frame
	var rows: Array=[]
	for center: Vector3 in [Vector3(-400,0,390),Vector3(-410,0,380),Vector3(-120,0,-420),Vector3(-110,0,-420)]:
		var minimum:=INF;var maximum:=-INF;var all_support:=true;var private_points:=0;var native_hits: Array=[];var points: Array=[]
		for x: float in range(-20,21,2):
			for z: float in range(-15,16,2):
				var point:=center+Vector3(x,0,z);var floor: Dictionary=scene.drivable_car_service._ground(point)
				if floor.is_empty():all_support=false;continue
				minimum=minf(minimum,floor.point.y);maximum=maxf(maximum,floor.point.y);var local: Vector3=scene.city.to_local(point);var inside: bool=scene.city_bike_service._private_index.contains(Vector2(local.x,local.z));if inside:private_points+=1
				points.append({"xz":[point.x,point.z],"height":floor.point.y,"private":inside,"source_walk":scene.city_bike_service._walk_index.contains(Vector2(local.x,local.z)),"source_road":scene.city_bike_service._road_index.contains(Vector2(local.x,local.z))})
		var query:=PhysicsShapeQueryParameters3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(34,15,26);query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,Vector3(center.x,maximum+7.55,center.z));query.collision_mask=1|4|8|32;query.exclude=[scene.player.get_rid(),scene.terrain_surface.support.get_rid()]
		for hit: Dictionary in scene.get_world_3d().direct_space_state.intersect_shape(query,64):native_hits.append({"path":String(hit.collider.get_path()),"geometry_id":hit.collider.get_meta("geometry_id","")})
		rows.append({"center":center,"reserve_size":[40,30],"sample_count":points.size(),"all_native_support":all_support,"private_samples":private_points,"ground_min_y":minimum,"ground_max_y":maximum,"ground_range_m":maximum-minimum,"full34x15x26_native_hits":native_hits,"samples":points})
	var file:=FileAccess.open("res://../data/reports/city_sandbox/20261022/police_facility/campus_native_probe01.json",FileAccess.WRITE);file.store_string(JSON.stringify(encode({"runtime_ok":scene.runtime_ok,"candidates":rows}),"  "));file.close();print("POLICE_CAMPUS_PROBE ",JSON.stringify(encode(rows.map(func(row: Dictionary)->Dictionary:return {"center":row.center,"support":row.all_native_support,"private":row.private_samples,"ground_range_m":row.ground_range_m,"hits":row.full34x15x26_native_hits}))))
	if is_instance_valid(scene.neighborhood_life.audio):scene.neighborhood_life.audio.stop();scene.neighborhood_life.audio.stream=null
	scene.queue_free();await process_frame;await process_frame;quit()
