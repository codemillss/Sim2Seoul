extends Node
## N03 current-physics observation, human priority, FIFO and camera-time recycle.
var vehicles: Array[CharacterBody3D]=[]
var humans: Array[CharacterBody3D]=[]
var routes: Dictionary={}
var camera: Camera3D
var city: Node3D
var observations_enabled:=true
var last_observation_tick: int=-999999
var refreshed_tick: int=-1
var observations_valid:=false
var human_present:=true
var clear_s:=0.
var zone_owner: String=""
var queue: Array[String]=[]
var events: Array[Dictionary]=[]
var guards: Dictionary={}
var human_rows: Array[Dictionary]=[]
var human_polygons: Array[PackedVector2Array]=[]
# Optional latest-exploration service. Historical N03 scenes retain their
# exact human-priority/FIFO behavior while no provider is attached.
var signal_provider: Node

func attach_signal_provider(provider: Node) -> void:
	signal_provider=provider if is_instance_valid(provider) and provider.has_method("allows_vehicle") else null

func _signal_allows(route_id: String,crossing_id: String) -> bool:
	return not is_instance_valid(signal_provider) or bool(signal_provider.allows_vehicle(route_id,crossing_id))

func _signal_permission(body: CharacterBody3D,conflict: Dictionary) -> bool:
	if not is_instance_valid(signal_provider) or conflict.is_empty():return true
	# A vehicle already committed beyond the old hold point clears normally.
	# Revoking a green grant mid-crossing must not strand it in the zebra.
	if body.get_station_m()>float(conflict.stop_s_m)+.05:return true
	return _signal_allows(body.get_route_id(),String(conflict.crossing_id))

func painted_signal_limit(body: CharacterBody3D,direction: Vector3,max_distance: float) -> Dictionary:
	# New display crossings need braking even when they were absent from the
	# historical route's conflict list. Keep that list and its FIFO grants intact;
	# their existing controller remains the only authority for those crossings.
	if not is_instance_valid(signal_provider) or not signal_provider.has_method("vehicle_stop_distance"):return {}
	var route: Dictionary=routes.get(body.get_route_id(),{})
	var source: String=String(route.get("source_binding",{}).get("feature_id",""))
	if source.is_empty():return {}
	var ignored: Array=[]
	for conflict: Dictionary in route.get("conflicts",[]):ignored.append(String(conflict.crossing_id))
	return signal_provider.vehicle_stop_distance(source,body.global_position,direction,max_distance,ignored)

func _terrain_service() -> Node:
	if not is_instance_valid(city):return null
	var candidate: Variant=city.get_parent().get("terrain_surface")
	return candidate as Node if is_instance_valid(candidate) and bool(candidate.get("loaded")) else null

func _terrain_point(point: Vector3) -> Vector3:
	var terrain: Node=_terrain_service()
	if terrain==null:return point
	var sample: Dictionary=terrain.sample_ground_world(point)
	return sample.point if bool(sample.get("ok",false)) else point

func _portal_pose(point: Vector3,direction: Vector3) -> Transform3D:
	for body: CharacterBody3D in vehicles:
		if body.get("_terrain_enabled"):return body._terrain_pose(point,atan2(-direction.x,-direction.z))
	return Transform3D(Basis(Vector3.UP,atan2(-direction.x,-direction.z)),point)

func refresh_terrain() -> void:
	# Invalidate pre-height observations. The next physics tick observes humans
	# at their refreshed poses before issuing any crossing/recycling grant.
	last_observation_tick=-999999;refreshed_tick=-1;observations_valid=false
	clear_s=0.0;human_present=true;guards.clear()

func configure(data: Dictionary, people: Array, view: Camera3D, world: Node3D) -> void:
	for r in data.routes:routes[r.id]=r
	for p in people:humans.append(p)
	camera=view;city=world
	for c in data.crossings:
		if c.id=="sejong_marked":
			for ring in c.human_occupancy_geometry.coordinates:
				var packed:=PackedVector2Array()
				for p in ring:packed.append(Vector2(p[0],p[1]))
				human_polygons.append(packed)

func register_vehicle(body: CharacterBody3D) -> void:
	if not vehicles.has(body):vehicles.append(body)

func register_human(body: CharacterBody3D) -> void:
	if not humans.has(body):humans.append(body)

func _human_inside(point: Vector2) -> bool:
	if human_polygons.is_empty():return true
	if not Geometry2D.is_point_in_polygon(point,human_polygons[0]):return false
	for i in range(1,human_polygons.size()):
		if Geometry2D.is_point_in_polygon(point,human_polygons[i]):return false
	return true

func _refresh() -> void:
	var tick:=Engine.get_physics_frames()
	if refreshed_tick==tick:return
	refreshed_tick=tick
	if not observations_enabled:
		clear_s=0.
		return
	if tick-last_observation_tick>1:clear_s=0.
	human_rows.clear();observations_valid=not humans.is_empty();human_present=false
	for h in humans:
		if not is_instance_valid(h) or not h.global_position.is_finite():
			observations_valid=false;human_present=true;continue
		var p: Vector3=h.global_position
		var local: Vector3=city.to_local(p)
		var inside:=_human_inside(Vector2(local.x,local.z))
		if _terrain_service()!=null:inside=inside and absf(p.y-_terrain_point(p).y)<2.8
		human_present=human_present or inside
		human_rows.append({"id":str(h.get_path()),"position":[p.x,p.y,p.z],"layer":h.collision_layer,"inside_crossing":inside})
	last_observation_tick=tick
	if not observations_valid or human_present:clear_s=0.
	else:clear_s+=1./Engine.physics_ticks_per_second
	if not zone_owner.is_empty():
		for v in vehicles:
			if v.get_route_id()==zone_owner and v.get_station_m()>float(routes[zone_owner].conflicts[0].exit_s_m)+.005:
				events.append({"type":"release","tick":tick,"route_id":zone_owner,"station_m":v.get_station_m()})
				zone_owner=""
	for v in vehicles:
		var id: String=v.get_route_id()
		var station: float=v.get_station_m()
		var conflict: Dictionary=routes[id].conflicts[0]
		if station>=float(conflict.stop_s_m)-.25 and station<=float(conflict.exit_s_m)+.005 and zone_owner!=id and not queue.has(id):
			queue.append(id)
			events.append({"type":"queued","tick":tick,"route_id":id,"station_m":station})
	if zone_owner.is_empty() and not queue.is_empty() and observations_valid and not human_present and clear_s>=1. and _signal_allows(queue.front(),String(routes[queue.front()].conflicts[0].crossing_id)):
		zone_owner=queue.pop_front()
		events.append({"type":"grant","tick":tick,"route_id":zone_owner,"clear_s":clear_s,"human_present":human_present})

func permission(body: CharacterBody3D) -> Dictionary:
	_refresh()
	var fresh:=observations_valid and float(Engine.get_physics_frames()-last_observation_tick)/Engine.physics_ticks_per_second<=.1
	var id: String=body.get_route_id()
	var signal_clear: bool=_signal_permission(body,routes[id].conflicts[0])
	var allowed: bool=fresh and not human_present and zone_owner==id and signal_clear
	var reason:="reserved" if allowed else "human_present" if human_present else "fifo_or_clear_hold"
	if not signal_clear:reason="signal_red_or_amber"
	if not fresh:reason="stale_or_unknown_observation"
	return {"fresh":fresh,"allow_crossing":allowed,"human_present":human_present,"occupied_by":zone_owner,"reason":reason,
		"tick":Engine.get_physics_frames(),"observation_tick":last_observation_tick,"observation_age_s":float(Engine.get_physics_frames()-last_observation_tick)/Engine.physics_ticks_per_second,
		"clear_s":clear_s,"queue":queue.duplicate(),"signal_attached":is_instance_valid(signal_provider),"signal_clear":signal_clear}

func _corners(route: Dictionary,ending: bool) -> Array[Vector3]:
	var points: Array=route.xz
	var a: Array=points[-2] if ending else points[0]
	var b: Array=points[-1] if ending else points[1]
	var d:=Vector3(b[0]-a[0],0,b[1]-a[1]).normalized()
	var centre: Array=points[-1] if ending else points[0]
	var origin: Vector3=_terrain_point(city.to_global(Vector3(centre[0],0,centre[1])))
	var pose: Transform3D=_portal_pose(origin,d)
	origin=pose.origin
	var basis: Basis=pose.basis
	var points3: Array[Vector3]=[]
	for x in [-.9,.9]:
		for y in [0.,1.5]:
			for z in [-2.1,2.1]:points3.append(origin+basis*Vector3(x,y,z))
	return points3

func _portal_outside(points: Array[Vector3],planes: Array[Plane],reference: Vector3) -> bool:
	# Separating plane test on the whole box; uncertain intersections wait.
	for plane in planes:
		var sign_inside:=signf(plane.distance_to(reference))
		var all_out:=sign_inside!=0.
		for p in points:
			if plane.distance_to(p)*sign_inside>=-.001:all_out=false;break
		if all_out:return true
	return false

func recycle_guard(body: CharacterBody3D) -> Dictionary:
	_refresh()
	var id: String=body.get_route_id()
	var route: Dictionary=routes[id]
	var planes: Array[Plane]=camera.get_frustum()
	var reference: Vector3=camera.global_position-camera.global_basis.z*((camera.near+camera.far)*.5)
	var start:=_corners(route,false)
	var finish:=_corners(route,true)
	var start_out:=_portal_outside(start,planes,reference)
	var end_out:=_portal_outside(finish,planes,reference)
	var separation:=INF
	for h in humans:
		if not is_instance_valid(h):continue
		var hp:=Vector2(h.global_position.x,h.global_position.z)
		for point in [route.xz[0],route.xz[-1]]:separation=minf(separation,hp.distance_to(Vector2(point[0],point[1]))-2.9)
	var a: Array=route.xz[0];var b: Array=route.xz[1]
	var direction:=Vector3(b[0]-a[0],0,b[1]-a[1]).normalized()
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=body.get_node("CollisionShape").shape
	var feet: Vector3=_terrain_point(city.to_global(Vector3(a[0],0.,a[1])))
	var pose: Transform3D=_portal_pose(feet,direction)
	query.transform=Transform3D(pose.basis,pose.origin+pose.basis*Vector3.UP*.75)
	query.collision_mask=14;query.exclude=[body.get_rid()];query.margin=.05
	var contacts: Array[Dictionary]=body.get_world_3d().direct_space_state.intersect_shape(query,16)
	var entry_clear:=contacts.is_empty()
	var fresh:=observations_valid and float(Engine.get_physics_frames()-last_observation_tick)/Engine.physics_ticks_per_second<=.1
	var allowed: bool=fresh and start_out and end_out and separation>=30. and entry_clear and body.can_recycle()
	var plane_rows:=[]
	for p in planes:plane_rows.append({"normal":[p.normal.x,p.normal.y,p.normal.z],"d":p.d})
	var guard:={"allowed":allowed,"tick":Engine.get_physics_frames(),"route_id":id,"fresh":fresh,"start_outside":start_out,"end_outside":end_out,
		"before":{"position":[body.global_position.x,body.global_position.y,body.global_position.z],"velocity":[body.velocity.x,body.velocity.y,body.velocity.z],"station_m":body.get_station_m(),"speed_mps":body.snapshot().speed_mps,"on_floor":body.is_on_floor(),"state":body.snapshot().state},
		"minimum_human_surface_distance_m":separation if is_finite(separation) else -1.,"entry_clear":entry_clear,"entry_contacts":contacts.size(),
		"start_corners":start.map(func(p):return [p.x,p.y,p.z]),"end_corners":finish.map(func(p):return [p.x,p.y,p.z]),
		"planes":plane_rows,"inside_reference":[reference.x,reference.y,reference.z],"humans":human_rows.duplicate(true)}
	guards[id]=guard
	return guard

func after_camera_step(_delta: float) -> void:
	# Human observation continues while both vehicle movement switches are off.
	_refresh()
	for v in vehicles:
		if v.can_recycle():
			var guard:=recycle_guard(v)
			if guard.allowed and v.try_recycle(guard):events.append({"type":"recycle","route_id":v.get_route_id(),"tick":Engine.get_physics_frames(),"guard":guard})

func snapshot() -> Dictionary:
	return {"tick":Engine.get_physics_frames(),"last_observation_tick":last_observation_tick,"observation_age_s":float(Engine.get_physics_frames()-last_observation_tick)/Engine.physics_ticks_per_second,
		"observations_enabled":observations_enabled,"valid":observations_valid,"human_present":human_present,"clear_s":clear_s,"owner":zone_owner,"queue":queue.duplicate(),"humans":human_rows.duplicate(true),"guards":guards.duplicate(true),"signal_attached":is_instance_valid(signal_provider)}
