extends SceneTree
## Compare to the saved, byte-identical pre-change production script. Only
## counters are injected into the reference; native sweep code stays intact.
const AVOIDANCE := preload("res://scripts/pedestrian_corridor_avoidance.gd")
const REFERENCE := "res://../data/reports/web_sites/20261025/performance01/corridor_neighbor_reuse_reference.gd"
class MeasuredAvoidance extends "res://scripts/pedestrian_corridor_avoidance.gd":
	var sweep_trace: Array=[]
	func _sweep(row: Dictionary,start: Vector3,end: Vector3,floor_a: RID,floor_b: RID,excluded: Array[RID],direction: Vector3) -> bool:
		sweep_trace.append([row.kind,start,end,floor_a,floor_b,excluded.duplicate(),direction])
		return super._sweep(row,start,end,floor_a,floor_b,excluded,direction)
var checks := 0
var failures: Array[String]=[]
var observations: Array=[]
var floor_body: StaticBody3D

func _initialize() -> void:
	_run.call_deferred()

func _check(passed: bool,message: String) -> void:
	checks+=1
	if not passed:failures.append(message)

func _body(parent: Node3D,at: Vector3,dog:=false,with_shape:=true) -> Dictionary:
	var body:=CharacterBody3D.new();parent.add_child(body);body.position=at;body.collision_layer=4;body.collision_mask=1|4
	var visual:=Node3D.new();body.add_child(visual)
	var collider:=CollisionShape3D.new();collider.name="CollisionShape"
	if dog:
		var shape:=BoxShape3D.new();shape.size=Vector3(.42,.52,.84);collider.shape=shape;collider.position.y=.28;body.set_meta("street_actor_kind","dog")
	else:
		var shape:=CapsuleShape3D.new();shape.radius=.27;shape.height=1.70;collider.shape=shape;collider.position.y=.86
	if with_shape:body.add_child(collider)
	else:collider.free();collider=null
	return {"body":body,"collider":collider,"visual":visual,"side":0.,"kind":"dog" if dog else "walker"}

func _reference_script() -> GDScript:
	_check(FileAccess.get_sha256(REFERENCE)=="69085e7ffd2640712f5bae45b202fe989bb5fc5ae3984f5e951d2555453dbfa4","reference is the exact frozen pre-change script")
	var source:=FileAccess.get_file_as_string(REFERENCE)
	source=source.replace("extends RefCounted\n","extends RefCounted\nvar reference_sweeps: Array=[]\nvar reference_radius_reads:=0\n")
	source=source.replace("func _other_radius(body: CharacterBody3D) -> float:\n","func _other_radius(body: CharacterBody3D) -> float:\n\treference_radius_reads+=1\n")
	var sweep_header:="func _sweep(row: Dictionary, start: Vector3, end: Vector3, floor_a: RID, floor_b: RID, excluded: Array[RID], direction: Vector3) -> bool:\n"
	source=source.replace(sweep_header,sweep_header+"\treference_sweeps.append([row.kind,start,end,floor_a,floor_b,excluded.duplicate(),direction])\n")
	var script:=GDScript.new();script.source_code=source
	_check(script.reload()==OK,"instrumented original script compiles")
	return script

func _run() -> void:
	var reference:=_reference_script()
	if not failures.is_empty():_finish();return
	var world:=Node3D.new();root.add_child(world)
	floor_body=StaticBody3D.new();floor_body.collision_layer=1;floor_body.collision_mask=0
	var floor_shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(1000.,.1,100.);floor_shape.shape=box;floor_body.add_child(floor_shape);world.add_child(floor_body);floor_body.position.y=-.05
	var cases: Array=[
		{"name":"open"},{"name":"paced_preview","wait":.12},
		{"name":"new_passing_plan","distance":1.6},
		{"name":"all_lanes_protected","distance":1.6,"width":.46},
		{"name":"keeper_dog_pair","pair":true,"distance":1.6},
		{"name":"waypoint_pop","plan":[Vector2(2.,0.),Vector2(3.,.95)]},
		{"name":"plan_completion","plan":[Vector2(2.,0.)]},
		{"name":"missing_floor","missing_floor":true},
		{"name":"missing_capped_step","plan":[Vector2(3.,0.)],"step_hole":true},
		{"name":"native_wall_stuck_replan","wall":true,"plan":[Vector2(3.,0.)],"stuck":.46},
		{"name":"initial_overlap_escape","distance":-.2},
		{"name":"other_height_ignored","distance":1.4,"height":3.},
		{"name":"dog_radius","distance":1.6,"other_dog":true},
		{"name":"missing_capsule_fallback","distance":1.6,"other_shape":false},
	]
	var fixtures: Array=[]
	for index in range(cases.size()):
		var config: Dictionary=cases[index];var origin:=Vector3(float(index)*30.-200.,.025,0.)
		var members: Array=[_body(world,origin+Vector3(0.,0.,-2.))]
		if config.get("pair",false):
			members[0].side=-.34;members[0].body.position.x-=.34
			var dog:=_body(world,origin+Vector3(.34,0.,-2.),true);dog.side=.34;members.append(dog)
		var other:=_body(world,origin+Vector3(0.,float(config.get("height",0.)),-2.-float(config.get("distance",10.))),bool(config.get("other_dog",false)),bool(config.get("other_shape",true)))
		var others: Array=[other.body]
		var group:={"id":config.name,"record":{"dog":config.get("pair",false)},"members":members,"station":2.,"length":12.,"direction":1,"origin":origin}
		if config.has("plan"):
			var plan: Array=[]
			for point: Vector2 in config.plan:plan.append({"station":point.x,"offset":point.y})
			group.merge({"avoidance_plan":plan,"avoidance_retry_s":0.,"avoidance_lane_m":.95,"avoidance_count":1,"avoidance_preview_wait_s":0.,"avoidance_stuck_s":config.get("stuck",0.)})
		if config.has("wait"):group.avoidance_plan=[];group.avoidance_retry_s=0.;group.avoidance_lane_m=0.;group.avoidance_count=0;group.avoidance_preview_wait_s=config.wait
		if config.get("wall",false):
			var wall:=StaticBody3D.new();wall.collision_layer=1;wall.collision_mask=0;var shape:=CollisionShape3D.new();var wall_box:=BoxShape3D.new();wall_box.size=Vector3(10.,2.,.1);shape.shape=wall_box;wall.add_child(shape);world.add_child(wall);wall.position=origin+Vector3(0.,1.,-2.02)
		fixtures.append({"config":config,"group":group,"others":others,"other":other})
	await physics_frame;await physics_frame
	for fixture: Dictionary in fixtures:
		var config: Dictionary=fixture.config;var original_group: Dictionary=fixture.group
		var baseline: RefCounted=reference.new();var optimized:=MeasuredAvoidance.new();optimized.reuse_neighbors_within_choose=true
		var baseline_counts:={"neighbors":0,"ground":0,"allowed":0};var optimized_counts:={"neighbors":0,"ground":0,"allowed":0}
		_bind(baseline,world,fixture,baseline_counts);_bind(optimized,world,fixture,optimized_counts)
		var first: Dictionary=original_group.duplicate(true);var second: Dictionary=original_group.duplicate(true)
		var before: Dictionary=baseline.choose(first,1./30.,1.2);var after: Dictionary=optimized.choose(second,1./30.,1.2)
		_check(before==after,String(config.name)+": exact decision and targets")
		_check(first==second,String(config.name)+": exact plan, preview, retry, offset and stuck state")
		_check(baseline.reference_sweeps==optimized.sweep_trace,String(config.name)+": unchanged ordered native sweep inputs")
		_check(baseline_counts.ground==optimized_counts.ground and baseline_counts.allowed==optimized_counts.allowed,String(config.name)+": unchanged floor/protected-boundary callback counts")
		_check(optimized_counts.neighbors==1,String(config.name)+": one neighbor snapshot per choose")
		_check(not optimized._choose_queries_active and optimized._choose_neighbors_cache.is_empty() and optimized._choose_radius_cache.is_empty(),String(config.name)+": choose scope is fully released")
		observations.append({"name":config.name,"clear":after.clear,"reason":after.reason,"neighbors_before":baseline_counts.neighbors,"neighbors_after":optimized_counts.neighbors,"radius_reads_before":baseline.reference_radius_reads,"radius_reads_after":optimized.choose_radius_reads,"radius_cache_hits":optimized.choose_radius_cache_hits,"native_sweeps":optimized.sweep_trace.size()})
		# Move/resize/add membership BETWEEN calls. can_reverse and the next
		# choose must read those current values, including a caller-owned Array.
		fixture.other.body.position.x+=2.
		if fixture.other.collider!=null and fixture.other.collider.shape is CapsuleShape3D:fixture.other.collider.shape.radius=.6
		fixture.others.append(fixture.group.members[0].body)
		baseline.reference_sweeps.clear();optimized.sweep_trace.clear()
		var reverse_before: bool=baseline.can_reverse(first,.8);var reverse_after: bool=optimized.can_reverse(second,.8)
		_check(reverse_before==reverse_after and baseline.reference_sweeps==optimized.sweep_trace,String(config.name)+": reverse is fresh outside choose")
		baseline.reference_sweeps.clear();optimized.sweep_trace.clear()
		before=baseline.choose(first,1./30.,1.2);after=optimized.choose(second,1./30.,1.2)
		_check(before==after and first==second and baseline.reference_sweeps==optimized.sweep_trace,String(config.name)+": later choice observes moved/resized/new membership")
		_check(fixture.others.size()==2,String(config.name)+": cached Array cleanup never clears provider-owned membership")
	world.free();_finish()

func _bind(service: RefCounted,world: Node3D,fixture: Dictionary,counts: Dictionary) -> void:
	var origin: Vector3=fixture.group.origin;var config: Dictionary=fixture.config
	service.setup(world,
		func(_group: Dictionary,station: float,lateral: float)->Vector3:return origin+Vector3(lateral,0.,-station),
		func(point: Vector3)->Dictionary:
			counts.ground+=1
			if config.get("missing_floor",false) or (config.get("step_hole",false) and -point.z>2.00001 and -point.z<2.06):return {}
			return {"point":Vector3(point.x,.025,point.z),"rid":floor_body.get_rid(),"normal":Vector3.UP},
		func(point: Vector3,radius: float)->bool:counts.allowed+=1;return absf(point.x-origin.x)+radius<=float(config.get("width",4.)),
		func(_group: Dictionary)->Array:counts.neighbors+=1;return fixture.others)

func _finish() -> void:
	var result:={"task":"CHOOSE_NEIGHBOR_REUSE_EQUALITY","result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures,"cases":observations,"reference_sha256":FileAccess.get_sha256(REFERENCE),"optimized_sha256":FileAccess.get_sha256("res://scripts/pedestrian_corridor_avoidance.gd"),"engine":Engine.get_version_info().string,"scope":"Saved pre-change production script vs production reuse. Tiny real native physics world; controlled route/support/permission callbacks. Exact decisions, full group state and ordered native sweep inputs, call counts and fresh reverse/next-call membership/radii. No city launch, real terrain, sustained walk or browser performance acceptance."}
	print("CHOOSE_NEIGHBOR_REUSE_CHECK ",JSON.stringify(result))
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		var file:=FileAccess.open(args[0],FileAccess.WRITE)
		if file==null:push_error("Could not save corridor reuse result");quit(1);return
		file.store_string(JSON.stringify(result,"  ")+"\n");file.close()
	quit(0 if failures.is_empty() else 1)
