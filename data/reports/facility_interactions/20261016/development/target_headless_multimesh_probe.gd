extends SceneTree
## Reproduces why headless target validation uses real StaticBody parents,
## while native tests separately inspect MultiMesh renderer instance data.
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/authored/interiors/source_catalog.json"))
	var record: Dictionary=data.records[0]
	var room: Node3D=load("res://scripts/building_interior_space.gd").new();root.add_child(room)
	room.setup({"id":record.id,"title":record.title,"kind":record.kind,"width":float(record.floor.width),"depth":float(record.floor.depth),"floor_height":float(record.floor_height),"floor_count":int(record.floor_count)},Vector3(650,-100,0))
	await physics_frame
	var identities := 0;var nonidentities := 0;var first: Transform3D=Transform3D.IDENTITY
	for child in room.get_children():
		if not child is MultiMeshInstance3D:continue
		for index in range(child.multimesh.instance_count):
			var value: Transform3D=child.multimesh.get_instance_transform(index)
			if value==Transform3D.IDENTITY:identities+=1
			else:nonidentities+=1;first=value
	for placement: Dictionary in room.detail_kit.placements:
		if placement.title=="Detail_FacilityTreadmill":print("NON_IDENTITY_PRODUCTION_PLACEMENT ",placement);break
	print("HEADLESS_MULTIMESH_OBSERVATION display=",DisplayServer.get_name()," identity_instances=",identities," non_identity_instances=",nonidentities," first_non_identity=",first)
	room.free();quit(0)
