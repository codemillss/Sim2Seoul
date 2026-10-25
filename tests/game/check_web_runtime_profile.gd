extends SceneTree
## Bounded geometry-only check; never loads the city or establishes Web FPS.
const PROFILE := preload("res://scripts/web_runtime_profile.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	var mesh:=BoxMesh.new()
	var material:=StandardMaterial3D.new()
	var points: Array[Vector3]=[
		Vector3(-160.1,4.,-.1),Vector3(-80.,12.,0.),
		Vector3(-.01,0.,79.99),Vector3(0.,1.,0.),
		Vector3(79.99,9.,79.99),Vector3(80.,3.,80.),
		Vector3(160.25,-4.,-80.01),
	]
	var original: Array[Transform3D]=[]
	var expected: Dictionary={}
	for index in range(points.size()):
		var basis:=Basis.from_euler(Vector3(.03*index,.17*index,.02*index)).scaled(Vector3(1.+index,.1+index*.2,.5+index*.3))
		var transform:=Transform3D(basis,points[index])
		original.append(transform)
		var cell:=Vector2i(floori(points[index].x/80.),floori(points[index].z/80.))
		if not expected.has(cell):expected[cell]=[]
		expected[cell].append(transform)
	var before:=original.duplicate()
	var physics_hz:=Engine.physics_ticks_per_second
	var parent_transform:=Transform3D(Basis.from_euler(Vector3(.1,.7,-.2)).scaled(Vector3(1.2,.8,1.1)),Vector3(42.,8.,-71.))
	var plan: Array[Dictionary]=PROFILE.partition_facade_transforms(original)
	var batches: Array[MultiMeshInstance3D]=PROFILE.create_facade_batches("test:glass",original,mesh,material)
	_check(batches.size()==5,"negative coordinates and exact boundaries create five expected cells")
	_check(plan.size()==batches.size(),"each planned cell creates one display batch")
	var retained:=0
	for batch_index in range(batches.size()):
		var batch: MultiMeshInstance3D=batches[batch_index]
		var cell: Vector2i=batch.get_meta("web_facade_cell")
		var partition: Dictionary=plan[batch_index]
		_check(expected.has(cell),"cell is derived from original local coordinates")
		_check(partition.cell==cell and partition.origin==batch.position,"batch uses its planned cell transform")
		_check(batch.multimesh.mesh==mesh and batch.material_override==material,"mesh and material resources are retained")
		_check(batch.get_child_count()==0,"partition adds no collision or gameplay child")
		_check(batch.multimesh.instance_count==expected[cell].size(),"per-cell instance count matches input")
		for index in range(batch.multimesh.instance_count):
			# Dummy rendering servers need not retain instance readback. Check the
			# exact pure transforms that create_facade_batches writes to MultiMesh.
			var local_transform: Transform3D=partition.transforms[index]
			var original_transform: Transform3D=expected[cell][index]
			var reconstructed: Transform3D=parent_transform*batch.transform*local_transform
			var source: Transform3D=parent_transform*original_transform
			_check(reconstructed.is_equal_approx(source),"world transform including scale and rotation is retained")
		retained+=batch.multimesh.instance_count
		batch.free()
	_check(retained==original.size(),"total instance count is conserved")
	for index in range(original.size()):
		_check(original[index].is_equal_approx(before[index]),"input transform remains unchanged")
	_check(PROFILE.create_facade_batches("empty",[],mesh,material).is_empty(),"empty input adds no display batch")
	var profile:=PROFILE.new()
	var host:=Node3D.new()
	profile.setup(host)
	_check(not profile.is_processing(),"native setup does not enable Web profiling")
	_check(Engine.physics_ticks_per_second==physics_hz,"physics frequency stays unchanged")
	profile.free();host.free()
	var result:={"task":"WEB_FACADE_GEOMETRY_CONSERVATION","result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"source_instances":original.size(),"retained_instances":retained,"spatial_cells":batches.size(),"renderer_readback":false,"failures":failures,"engine":Engine.get_version_info().string,"scope":"Synthetic transforms across negative and exact grid boundaries. Verifies pure partition transforms, shared resources, actual instance counts and effective world transforms under a non-identity parent. Does not establish GPU transform readback, browser performance or gameplay."}
	print("WEB_PROFILE_GEOMETRY_CHECK ",JSON.stringify(result))
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		var file:=FileAccess.open(args[0],FileAccess.WRITE)
		if file==null:
			push_error("Could not save Web profile geometry result")
			quit(1);return
		file.store_string(JSON.stringify(result,"  ")+"\n");file.close()
	quit(0 if failures.is_empty() else 1)

func _check(passed: bool,message: String) -> void:
	checks+=1
	if not passed:failures.append(message)
