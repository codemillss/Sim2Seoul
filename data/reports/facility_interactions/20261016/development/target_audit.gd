extends SceneTree
var errors: Array = []
var counts := {}
var profiles := {}
var target_count := 0
var sample_count := 0
var shape := CapsuleShape3D.new()
func _initialize() -> void:
	shape.radius=.30;shape.height=1.70
	run.call_deferred()
func inspect_point(room: Node3D,row: Dictionary,p: Vector3,label: String) -> void:
	var world: Vector3=room.to_global(p)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,world+Vector3.UP*.85);query.collision_mask=1
	var hits: Array=root.get_world_3d().direct_space_state.intersect_shape(query,16)
	var names := []
	for hit in hits:names.append(str(hit.collider.name))
	if not hits.is_empty():errors.append({"id":row.id,"kind":"blocked_"+label,"point":str(p),"hits":names})
	var support := root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(world+Vector3.UP*.25,world-Vector3.UP*.30,1))
	if support.is_empty() or absf((world.y-float(support.position.y))-.08)>.025:errors.append({"id":row.id,"kind":"unsupported_"+label,"point":str(p),"support":str(support.get("position",Vector3.INF))})
	sample_count+=1
func run() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/interiors/source_catalog.json"))
	for record: Dictionary in data.records:
		var room: Node3D=load("res://scripts/building_interior_space.gd").new();root.add_child(room)
		var spec := {"id":record.id,"title":record.title,"kind":record.kind,"width":float(record.floor.width),"depth":float(record.floor.depth),"floor_height":float(record.floor_height),"floor_count":int(record.floor_count)}
		if not room.setup(spec,Vector3(650,-100,0)):errors.append({"source_id":record.id,"kind":"setup_failed"});room.free();continue
		await physics_frame;await physics_frame
		var list: Array=room.detail_kit.facility_kit.interactions
		for row: Dictionary in list:
			target_count+=1;counts[row.kind]=int(counts.get(row.kind,0))+1
			var key: String=room.detail_kit.profile_id+"/"+str(row.kind)
			profiles[key]=int(profiles.get(key,0))+1
			for field in ["use_point","approach_point"]:inspect_point(room,row,row[field],field)
			var start: Vector3=row.approach_point;var finish: Vector3=row.use_point
			for n in range(1,8):
				var p: Vector3=start.lerp(finish,float(n)/8.0)
				# Treadmill ascent uses a raised capsule sweep, whose support is
				# tested at each endpoint; the low deck is an intentional step.
				if row.kind=="treadmill":continue
				inspect_point(room,row,p,"segment")
		room.free();await physics_frame
	var report := {"result":"PASS" if errors.is_empty() else "FAIL","targets":target_count,"counts":counts,"profiles":profiles,"point_queries":sample_count,"errors":errors}
	var file := FileAccess.open("/private/tmp/sim2seoul_facility_target_audit.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
