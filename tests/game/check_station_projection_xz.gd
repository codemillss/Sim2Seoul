extends SceneTree
## Small controlled math regression; no city, collision world or game is loaded.
const STREET:=preload("res://scripts/street_pedestrians.gd")
const LEGACY:=preload("res://scripts/exploration_pedestrian_avoidance.gd")
class ControlledStreet extends STREET:
	var terrain_calls:=0
	var terrain_revision:=0.
	func _terrain_point(at: Vector3) -> Vector3:
		terrain_calls+=1
		return Vector3(at.x,terrain_revision+at.x*.03125-at.z*.0625,at.z)
class ControlledActor extends CharacterBody3D:
	var _station_m:=0.
	var _segment:=0
	var route_arc: Array=[]
	func _segment_at(station: float,direction: int) -> int:
		for index in range(1,route_arc.size()):
			if station<float(route_arc[index]) or (station==float(route_arc[index]) and direction<0):return index-1
		return maxi(0,route_arc.size()-2)
var checks:=0
var failures: Array[String]=[]
var original_terrain_calls:=0
var cached_terrain_calls:=0
var decisions:=0
var endpoint_turns:=0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var street:=ControlledStreet.new()
	var legacy:=LEGACY.new();legacy.street=street
	root.add_child(street);street.set_physics_process(false);street.set_process(false)
	root.add_child(legacy);legacy.set_physics_process(false);legacy.set_process(false)
	var routes: Array[Dictionary]=[
		{"id":"negative_straight","points":[Vector3(-113.7,8.,-91.3),Vector3(-12.2,-2.,-18.6)],"offset":-.78},
		{"id":"mitered_bends","points":[Vector3(-19.,3.,-21.),Vector3(-7.,9.,-21.),Vector3(-7.,-5.,-9.),Vector3(9.,11.,2.)],"offset":1.25},
		{"id":"closed_loop","points":[Vector3(-12.,0.,-12.),Vector3(12.,6.,-12.),Vector3(12.,2.,12.),Vector3(-12.,-8.,12.),Vector3(-12.,0.,-12.)],"offset":-.93},
		{"id":"short_segments","points":[Vector3(-.2,12.,-.3),Vector3(-.199,8.,-.3),Vector3(-.198,4.,-.298),Vector3(.7,-3.,.5)],"offset":.37},
	]
	var dense: Array[Vector3]=[]
	for index in range(25):dense.append(Vector3(-317.25+index*.91,sin(float(index))*.4,-123.4+sin(float(index)*.17)*7.))
	routes.append({"id":"museum_25_points","points":dense,"offset":.42})
	for row: Dictionary in routes:
		var group:=_group(row.points,float(row.offset))
		var points_before: Array=group.points.duplicate(true);var arcs_before: Array=group.arc.duplicate(true)
		street.terrain_calls=0
		var cached: Array[Vector3]=street._station_projection_points(group)
		_check(street.terrain_calls==0,String(row.id)+": cache construction never queries terrain")
		for index in range(group.arc.size()):
			var old: Vector3=street._at(group,group.arc[index])
			_check(old.x==cached[index].x and old.z==cached[index].z,String(row.id)+": exact old endpoint XZ at arc "+str(index))
		_check(street._station_projection_points(group)==cached,String(row.id)+": repeated use retains cached points")
		# Probe negative stations, both sides of every arc boundary and beyond
		# the end; construct positions through the original authoritative _at.
		var stations: Array[float]=[-1.,0.,group.length,group.length+1.]
		for arc: float in group.arc:
			stations.append(arc-.00001);stations.append(arc);stations.append(arc+.00001)
		for index in range(21):stations.append(group.length*float(index)/20.)
		var sequence: Array[Vector3]=[]
		for station: float in stations:
			for side: float in [-.33,0.,.29]:sequence.append(street._at(group,station,side))
		var reverse:=sequence.duplicate();reverse.reverse();sequence.append_array(reverse)
		var old_state:={"station":0.,"actual_distance_m":0.,"direction":1,"turns":0}
		var new_state: Dictionary=old_state.duplicate(true)
		var actor:=ControlledActor.new();actor.route_arc=group.arc;root.add_child(actor);actor.set_physics_process(false)
		var legacy_group: Dictionary=group.duplicate(true);legacy_group.station=0.;legacy_group.actual_distance_m=0.;legacy_group.direction=1;legacy_group.members=[{"body":actor}]
		var legacy_old: Dictionary=legacy_group.duplicate(true)
		for position: Vector3 in sequence:
			street.terrain_calls=0
			var expected:=_project(street,group,position,false,false)
			original_terrain_calls+=street.terrain_calls
			street.terrain_calls=0
			var actual:=_project(street,group,position,true,false)
			cached_terrain_calls+=street.terrain_calls
			_check(expected==actual,String(row.id)+": exact street station")
			_advance(old_state,expected,group.length);_advance(new_state,actual,group.length)
			_check(old_state==new_state,String(row.id)+": distance/direction/turn state retained")
			var expected_legacy:=_project(street,legacy_old,position,false,true)
			legacy_old.actual_distance_m+=absf(expected_legacy-float(legacy_old.station));legacy_old.station=expected_legacy
			actor.position=position
			street.terrain_calls=0
			legacy._record_station(legacy_group)
			_check(street.terrain_calls==0,String(row.id)+": real legacy record has no terrain queries")
			_check(legacy_group.station==legacy_old.station and legacy_group.actual_distance_m==legacy_old.actual_distance_m,String(row.id)+": real legacy station/distance retained")
			_check(actor._station_m==expected_legacy and actor._segment==actor._segment_at(expected_legacy,int(legacy_group.direction)),String(row.id)+": real legacy actor station/segment retained")
			decisions+=1
		endpoint_turns+=int(old_state.turns)
		# Terrain remains dynamic wherever Y is actually consumed. Cached
		# projection XZ must survive a height-only refresh without resampling it.
		var before_height: Vector3=street._at(group,group.length*.37)
		street.terrain_revision+=27.
		for index in range(group.points.size()):group.points[index].y+=14.
		var after_height: Vector3=street._at(group,group.length*.37)
		_check(after_height.y!=before_height.y and after_height.x==before_height.x and after_height.z==before_height.z,String(row.id)+": authoritative terrain Y stays live")
		for index in range(group.arc.size()):
			var refreshed: Vector3=street._at(group,group.arc[index])
			_check(refreshed.x==cached[index].x and refreshed.z==cached[index].z,String(row.id)+": height refresh leaves cached XZ exact")
		_check(group.arc==arcs_before,String(row.id)+": source arcs retained")
		for index in range(group.points.size()):_check(group.points[index].x==points_before[index].x and group.points[index].z==points_before[index].z,String(row.id)+": source XZ retained")
		actor.free()
	_check(endpoint_turns>0,"controlled traversal exercised endpoint reversals")
	_check(original_terrain_calls>0 and cached_terrain_calls==0,"station reprojection removes all repeated terrain calls")
	var result:={"task":"EXACT_STATION_PROJECTION_XZ","result":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures,"route_fixtures":routes.size(),"projection_decisions":decisions,"endpoint_reversals":endpoint_turns,"baseline_projection_terrain_calls":original_terrain_calls,"cached_projection_terrain_calls":cached_terrain_calls,"terrain_calls_avoided":original_terrain_calls-cached_terrain_calls,"engine":Engine.get_version_info().string,"scope":"Controlled old/new exact XZ and station math, negative and out-of-range samples, arc boundaries, closed loop, forward/reverse sequences, real legacy _record_station, distance/direction/turn state and live terrain-Y preservation. No city, gameplay, collision or performance benchmark."}
	print("STATION_PROJECTION_XZ_CHECK ",JSON.stringify(result))
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		var file:=FileAccess.open(args[0],FileAccess.WRITE)
		if file==null:push_error("Could not save station projection result");quit(1);return
		file.store_string(JSON.stringify(result,"  ")+"\n");file.close()
	legacy.free();street.free()
	quit(0 if failures.is_empty() else 1)

func _group(points: Array,offset: float) -> Dictionary:
	var group:={"points":points.duplicate(true),"arc":[0.],"length":0.,"sides":[],"record":{"side_offset_m":offset},"station":0.}
	for index in range(1,points.size()):
		var a: Vector3=points[index-1];var b: Vector3=points[index]
		group.length+=Vector2(b.x-a.x,b.z-a.z).length();group.arc.append(group.length)
	for index in range(points.size()):
		var before: Vector3=points[index]-points[maxi(index-1,0)];var after: Vector3=points[mini(index+1,points.size()-1)]-points[index]
		before.y=0.;after.y=0.
		if before.is_zero_approx():before=after
		if after.is_zero_approx():after=before
		before=before.normalized();after=after.normalized()
		var normal_before:=Vector3(before.z,0,-before.x);var normal_after:=Vector3(after.z,0,-after.x)
		var side: Vector3=(normal_before+normal_after).normalized()
		group.sides.append(side/maxf(.8,side.dot(normal_after)))
	return group

func _project(street: Node3D,group: Dictionary,position: Vector3,cached: bool,legacy: bool) -> float:
	var best:=INF;var station: float=group.station;var p:=Vector2(position.x,position.z)
	var points: Array[Vector3]=[]
	if cached:points=street._station_projection_points(group)
	for index in range(1,group.points.size()):
		var a: Vector3=points[index-1] if cached else street._at(group,group.arc[index-1])
		var b: Vector3=points[index] if cached else street._at(group,group.arc[index])
		var q:=Geometry2D.get_closest_point_to_segment(p,Vector2(a.x,a.z),Vector2(b.x,b.z));var distance:=q.distance_to(p)
		if distance>=best:continue
		best=distance
		var fraction:=q.distance_to(Vector2(a.x,a.z))/maxf(.0001,Vector2(b.x-a.x,b.z-a.z).length())
		station=lerpf(group.arc[index-1],group.arc[index],fraction if legacy else clampf(fraction,0.,1.))
	return station

func _advance(state: Dictionary,station: float,length: float) -> void:
	state.actual_distance_m+=absf(station-float(state.station));state.station=station
	if (state.direction>0 and station>length-.04) or (state.direction<0 and station<.04):state.direction=-state.direction;state.turns+=1

func _check(passed: bool,message: String) -> void:
	checks+=1
	if not passed:failures.append(message)
