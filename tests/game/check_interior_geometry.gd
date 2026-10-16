extends SceneTree
var checked := 0
var floors := 0
var failures: Array[String] = []
var max_bodies := 0
var max_shapes := 0
var total_bodies := 0
var shape := CapsuleShape3D.new()
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	shape.radius=.3;shape.height=1.7
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/interiors/source_catalog.json"))
	for record: Dictionary in data.records:
		var spec := {"id":record.id,"title":record.title,"kind":record.kind,"width":record.floor.width,"depth":record.floor.depth,"floor_height":record.floor_height,"floor_count":record.floor_count}
		var room: Node3D=load("res://scripts/building_interior_space.gd").new();root.add_child(room)
		if not room.setup(spec,Vector3(650,-100,0)):failures.append(record.title+" setup");room.free();continue
		await physics_frame;await physics_frame
		checked+=1;floors+=room.floor_count;max_bodies=maxi(max_bodies,room.bodies.size())
		var shapes := 0
		for body: StaticBody3D in room.bodies:
			shapes+=body.get_child_count()
			if body.collision_layer!=1 or body.collision_mask!=0:failures.append(record.title+" body layer")
		max_shapes=maxi(max_shapes,shapes);total_bodies+=room.bodies.size()
		for level in range(room.floor_count):
			for point: Vector3 in [room.floor_spawn(level),room.elevator_point(level)]:
				if not room.interior_bounds.has_point(point):failures.append(record.title+" bound "+str(level))
				var space := root.get_world_3d().direct_space_state
				var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP,point-Vector3.UP,1))
				if ground.is_empty() or absf(ground.position.y-point.y+.08)>.02:failures.append(record.title+" floor "+str(level))
				var query := PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.85);query.collision_mask=1
				if not space.intersect_shape(query,1).is_empty():failures.append(record.title+" capsule "+str(level))
		room.free()
	print("SPACE_CATALOG_RESULT ",JSON.stringify({"buildings":checked,"floors":floors,"max_bodies":max_bodies,"max_shapes":max_shapes,"total_bodies_checked":total_bodies,"standing_targets_checked":floors*2,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
