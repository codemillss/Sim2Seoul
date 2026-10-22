extends SceneTree
var scene: Node3D
func _initialize() -> void:run.call_deferred()
func ticks(count: int) -> void:
	for i: int in range(count):await physics_frame;await process_frame
func encode(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
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
func run() -> void:
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/euljiro-police-query-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";root.add_child(scene);await ticks(8)
	var service: Node3D=scene.city_public_safety;var bike: Node3D=scene.city_bike_service;var rows: Array=[];var before: Dictionary={};var officer: CharacterBody3D=service.officers[2].body
	for i: int in range(41):
		var point:=Vector3(353.8,0,-79.0-float(i)*.25);var local: Vector3=scene.city.to_local(point);var flat:=Vector2(local.x,local.z);var ground: Dictionary=service._ground(point);var supported: Dictionary=service._supported(point);var row: Dictionary={"xz":[point.x,point.z],"private":bike._private_index.contains(flat),"walk":bike._walk_index.contains(flat),"road":bike._road_index.contains(flat),"source_allowed":service._source_allowed(point),"supported":not supported.is_empty(),"ground":ground.get("point",Vector3.INF)}
		if not ground.is_empty():
			var ray:=PhysicsRayQueryParameters3D.create(ground.point+Vector3.UP*.5,ground.point-Vector3.UP*.5,1|32);var floor: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(ray);row["floor_node"]=String(floor.collider.get_path()) if not floor.is_empty() else "none"
			var shape:=CapsuleShape3D.new();shape.radius=.27;shape.height=1.70;var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,ground.point+Vector3.UP*.86);query.exclude=[ground.rid];query.collision_mask=1|32;query.margin=.003;var hits: Array=[]
			for hit: Dictionary in scene.get_world_3d().direct_space_state.intersect_shape(query,4):hits.append(String(hit.collider.get_path()))
			row["static_capsule_hits"]=hits
			if not before.is_empty():row["native_and_source_segment_from_previous"]=service._segment_allowed(before.point,ground.point,officer)
			before=ground
		rows.append(row)
	var result: Dictionary={"task":"READ_ONLY_EULJIRO_GAP_DIAGNOSIS","rows":rows,"source_hash":FileAccess.get_sha256("res://scripts/city_public_safety.gd"),"scope":"Queries only; no player/officer/car transform or source/native geometry changes."};var file:=FileAccess.open("res://../data/reports/city_sandbox/20261022/police/euljiro_probe.json",FileAccess.WRITE);file.store_string(JSON.stringify(encode(result),"  "));file.close()
	if is_instance_valid(scene.neighborhood_life.audio):scene.neighborhood_life.audio.stop();scene.neighborhood_life.audio.stream=null
	scene.queue_free();await process_frame;await process_frame;quit()
