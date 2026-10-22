extends SceneTree
var scene: Node3D
func _initialize() -> void:run.call_deferred()
func ticks(count: int) -> void:
	for i: int in range(count):await physics_frame;await process_frame
func encode(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2:return [value.x,value.y]
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:result[str(key)]=encode(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value:result.append(encode(item))
		return result
	if value is float:return value if is_finite(value) else null
	return value
func pose(point: Vector3,yaw: float) -> Dictionary:
	var guards: Node3D=scene.city_public_safety;var floor: Dictionary=guards._ground(point)
	if floor.is_empty():return {"ok":false,"reason":"floor"}
	var basis:=Basis(Vector3.UP,yaw);var private_hits:=0;var outside:=0;var walk_samples:=0;var drive_samples:=0;var max_gap:=0.;var missing:=0
	for x: float in [-1.18,-.59,0.,.59,1.18]:
		for z: float in [-2.33,-1.55,-.77,0.,.77,1.55,2.33]:
			var sample: Vector3=floor.point+basis*Vector3(x,0,z);var local: Vector3=scene.city.to_local(sample);var flat:=Vector2(local.x,local.z)
			if scene.city_bike_service._private_index.contains(flat):private_hits+=1
			if not scene.player.free_roam_bounds.has_point(Vector2(sample.x,sample.z)):outside+=1
			if scene.city_bike_service._walk_index.contains(flat):walk_samples+=1
			if scene.city_bike_service._road_index.contains(flat):drive_samples+=1
			var foot: Dictionary=guards._ground(sample)
			if foot.is_empty():missing+=1
			else:max_gap=maxf(max_gap,absf(foot.point.y-floor.point.y))
	var shape:=BoxShape3D.new();shape.size=Vector3(2.2,1.65,4.5);var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform=Transform3D(basis,floor.point+Vector3.UP*.86);query.collision_mask=1|2|4|8|32;query.exclude=[floor.rid];query.margin=.005;var collisions: Array=[]
	for hit: Dictionary in scene.get_world_3d().direct_space_state.intersect_shape(query,8):collisions.append(String(hit.collider.get_path()))
	return {"ok":private_hits==0 and outside==0 and missing==0 and collisions.is_empty() and max_gap<.7,"point":floor.point,"yaw":yaw,"private_samples":private_hits,"walk_samples":walk_samples,"drive_samples":drive_samples,"missing_support":missing,"max_foot_height_difference_m":max_gap,"collisions":collisions}
func run() -> void:
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/policefacility-probe-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";root.add_child(scene);await ticks(8)
	var rows: Array=[]
	for x: float in [34.,38.,42.,46.,50.,54.,58.,62.]:
		for z: float in [-440.,-436.,-432.,-428.,-424.,-420.,-416.,-412.]:rows.append(pose(Vector3(x,0,z),0.))
	var building: Node3D=scene.city.source_nodes["osm:way:1215689854:building"]
	var result: Dictionary={"task":"READ_ONLY_POLICE_FORECOURT_NATIVE_PREFLIGHT","candidates":rows,"building_origin":building.global_position,"scope":"Read-only full native box/support/private guard queries; no car/officer/source/player pose writes beyond ordinary startup."};var file:=FileAccess.open("res://../data/reports/city_sandbox/20261022/police_facility/site_probe.json",FileAccess.WRITE);file.store_string(JSON.stringify(encode(result),"  "));file.close()
	if is_instance_valid(scene.neighborhood_life.audio):scene.neighborhood_life.audio.stop();scene.neighborhood_life.audio.stream=null
	scene.queue_free();await process_frame;await process_frame;quit()
