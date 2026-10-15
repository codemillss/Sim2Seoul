extends "res://test_support/check_walkable_milestone.gd"
## Independent N03 support experiment. Only the six test bodies are placed/reset.
## The N02 scene, source polygons, player, and pedestrians keep their production code.

class DropBox extends CharacterBody3D:
	signal stepped(delta: float)
	var steps := 0
	func _physics_process(delta: float) -> void:
		if not is_on_floor():velocity.y-=9.8*delta
		else:velocity.y=0.
		move_and_slide()
		steps+=1
		stepped.emit(delta)

var route_data: Dictionary
var added_supports := []

func _at_road(route: Dictionary,station: float) -> Dictionary:
	var left:=clampf(station,0.,float(route.length_m))
	for i in range(route.xz.size()-1):
		var a:=Vector3(route.xz[i][0],route.ground_y_m,route.xz[i][1])
		var b:=Vector3(route.xz[i+1][0],route.ground_y_m,route.xz[i+1][1])
		var length:=a.distance_to(b)
		if left<=length or i==route.xz.size()-2:
			return {"point":a.lerp(b,clampf(left/length,0.,1.)),"tangent":(b-a).normalized(),"segment":i}
		left-=length
	return {}

func _support_ray(point: Vector3,mask: int) -> Dictionary:
	var from:=point+Vector3.UP*.5
	var to:=point-Vector3.UP*1.
	var query:=PhysicsRayQueryParameters3D.create(from,to,mask)
	var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(query)
	var row:={"from":_v(from),"to":_v(to),"mask":mask,"hit":not hit.is_empty(),"id":"","position":[],"normal":[],"layer":0,"mask_observed":0,"collider_path":""}
	if not hit.is_empty():
		row.id=hit.collider.get_meta("geometry_id","")
		row.position=_v(hit.position);row.normal=_v(hit.normal)
		row.layer=hit.collider.collision_layer;row.mask_observed=hit.collider.collision_mask
		row.collider_path=str(hit.collider.get_path())
	return row

func _road_stations(mask: int) -> Array:
	var rows:=[]
	for route in route_data.routes:
		var stations:=[]
		var station:=0.
		while station<float(route.length_m):stations.append(station);station+=5.
		stations.append(float(route.length_m))
		for s in stations:
			var pose:=_at_road(route,s)
			var point: Vector3=pose.point
			var forward: Vector3=pose.tangent
			var side:=Vector3(-forward.z,0,forward.x)
			var offsets:=[["centre",Vector3.ZERO],["front_left",forward*2.1-side*.9],["front_right",forward*2.1+side*.9],["rear_left",-forward*2.1-side*.9],["rear_right",-forward*2.1+side*.9]]
			var rays:=[]
			for offset in offsets:
				var p: Vector3=point+offset[1]
				var ray:=_support_ray(p,mask)
				ray["name"]=offset[0];ray["footprint_point"]=_v(p);rays.append(ray)
			rows.append({"route_id":route.id,"station_m":s,"segment":pose.segment,"centre":_v(point),"tangent":_v(forward),"rays":rays})
	return rows

func _drop_row(body: DropBox) -> Dictionary:
	var contacts:=[]
	for i in range(body.get_slide_collision_count()):
		var hit:=body.get_slide_collision(i)
		contacts.append({"id":hit.get_collider().get_meta("geometry_id",""),"normal":_v(hit.get_normal()),"depth_m":hit.get_depth(),"position":_v(hit.get_position())})
	return {"tick":Engine.get_physics_frames(),"step":body.steps,"position":_v(body.global_position),"velocity":_v(body.velocity),"on_floor":body.is_on_floor(),"contacts":contacts}

func _drop_road(route: Dictionary,station: float,label: String) -> Dictionary:
	var pose:=_at_road(route,station)
	var point: Vector3=pose.point
	var tangent: Vector3=pose.tangent
	var body:=DropBox.new()
	body.name="N03SupportDrop"
	body.collision_layer=8;body.collision_mask=31
	body.safe_margin=.001;body.floor_snap_length=.1
	body.position=point+Vector3.UP*.08
	body.rotation.y=atan2(-tangent.x,-tangent.z)
	var shape:=BoxShape3D.new();shape.size=Vector3(1.8,1.5,4.2)
	var collision:=CollisionShape3D.new();collision.name="CollisionShape";collision.shape=shape;collision.position.y=.75
	body.add_child(collision);scene.add_child(body)
	var initial:=_drop_row(body)
	var samples:=[]
	for i in range(60):
		await body.stepped
		samples.append(_drop_row(body))
	var record:={"route_id":route.id,"label":label,"station_m":station,"ground_y_m":route.ground_y_m,"centre_xz":[point.x,point.z],"tangent":_v(tangent),"descriptor":{"size":_v(shape.size),"shape_offset":_v(collision.position),"layer":body.collision_layer,"mask":body.collision_mask,"safe_margin":body.safe_margin,"floor_snap":body.floor_snap_length,"yaw":body.rotation.y,"gravity_mps2":9.8},"initial":initial,"samples":samples,"end":_drop_row(body),"duration_s":1.,"ticks":body.steps,"placement_scope":"isolated support drop setup only; no vehicle motion or recurrence evidence"}
	body.set_physics_process(false);body.queue_free()
	await process_frame
	print("N03_SUPPORT_DROP ",route.id," ",label," floor=",record.end.on_floor," foot_y=",record.end.position[1])
	return record

func _add_test_supports() -> bool:
	var traffic=JSON.parse_string(FileAccess.get_file_as_string("res://test_support/traffic.json"))
	if not traffic is Dictionary or not traffic.get("supports") is Array:return false
	var holder:=Node3D.new();holder.name="IndependentN03TestSupports";scene.add_child(holder)
	for spec in traffic.supports:
		if not spec is Dictionary or not spec.get("vertices") is Array or spec.vertices.size()%9!=0 or spec.vertices.is_empty():return false
		var points:=PackedVector3Array()
		for i in range(0,spec.vertices.size(),3):points.append(Vector3(spec.vertices[i],spec.vertices[i+1],spec.vertices[i+2]))
		var body:=StaticBody3D.new();body.name=String(spec.id);body.collision_layer=16;body.collision_mask=8;body.set_meta("geometry_id",spec.id)
		var shape:=ConcavePolygonShape3D.new();shape.set_faces(points)
		var collision:=CollisionShape3D.new();collision.name="CollisionShape";collision.shape=shape;body.add_child(collision);holder.add_child(body)
		added_supports.append(_body_row(spec.id,body))
	return true

func _run() -> void:
	if variant not in ["baseline","final"]:push_error("N03 support requires baseline/final case");quit(1);return
	route_data=JSON.parse_string(FileAccess.get_file_as_string("res://test_support/vehicle_routes.json"))
	scene=load("res://scenes/world/pedestrian_walk.tscn").instantiate();root.add_child(scene)
	if not scene.runtime_ok:push_error("N02 scene required for support test");quit(1);return
	scene.input_router.set_script(load("res://test_support/daehanmun_probe_input.gd"));scene.input_router.isolate_movement_bindings()
	await _wait(1.)
	var before:=_inventory()
	if variant=="final" and not _add_test_supports():push_error("N03 support data malformed");quit(1);return
	await _wait(.1)
	var mask:=17 if variant=="final" else 1
	var stations:=_road_stations(mask)
	var drops:=[]
	for route in route_data.routes:
		for spec in [["start",0.],["middle",float(route.length_m)*.5],["end",float(route.length_m)]]:
			drops.append(await _drop_road(route,spec[1],spec[0]))
	var record:={"schema_version":1,"task":"N03","experiment":"road_support","mode":variant,"scene":"res://scenes/world/pedestrian_walk.tscn","engine":{"version":Engine.get_version_info().string,"display":DisplayServer.get_name(),"physics_hz":Engine.physics_ticks_per_second,"render_fps":fps},"route_sha256":FileAccess.get_sha256("res://test_support/vehicle_routes.json"),"traffic_sha256":FileAccess.get_sha256("res://test_support/traffic.json") if variant=="final" else "","inventory_before":before,"inventory_after":_inventory(),"added_supports":added_supports,"ray_mask":mask,"station_spacing_m":5.,"station_observations":stations,"drops":drops,"scope":"Independent static support/drop experiment in same Mac runtime-only offline N02 copy. Final adds traffic support faces as test-only StaticBody3D; production loader integration, driving, recurrence, human handling, field elevation, M4 and performance are unverified here."}
	var file:=FileAccess.open(output_path,FileAccess.WRITE)
	if file==null:push_error("N03 support fresh output required");quit(1);return
	file.store_string(JSON.stringify(record)+"\n")
	print("N03_SUPPORT_DONE mode=",variant," stations=",stations.size()," drops=",drops.size())
	scene.queue_free();quit(0)
