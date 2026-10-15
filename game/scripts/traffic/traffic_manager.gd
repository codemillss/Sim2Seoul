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
		var inside:=_human_inside(Vector2(p.x,p.z))
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
	if zone_owner.is_empty() and not queue.is_empty() and observations_valid and not human_present and clear_s>=1.:
		zone_owner=queue.pop_front()
		events.append({"type":"grant","tick":tick,"route_id":zone_owner,"clear_s":clear_s,"human_present":human_present})

func permission(body: CharacterBody3D) -> Dictionary:
	_refresh()
	var fresh:=observations_valid and float(Engine.get_physics_frames()-last_observation_tick)/Engine.physics_ticks_per_second<=.1
	var id: String=body.get_route_id()
	var allowed: bool=fresh and not human_present and zone_owner==id
	var reason:="reserved" if allowed else "human_present" if human_present else "fifo_or_clear_hold"
	if not fresh:reason="stale_or_unknown_observation"
	return {"fresh":fresh,"allow_crossing":allowed,"human_present":human_present,"occupied_by":zone_owner,"reason":reason,
		"tick":Engine.get_physics_frames(),"observation_tick":last_observation_tick,"observation_age_s":float(Engine.get_physics_frames()-last_observation_tick)/Engine.physics_ticks_per_second,
		"clear_s":clear_s,"queue":queue.duplicate()}

func _corners(route: Dictionary,ending: bool) -> Array[Vector3]:
	var points: Array=route.xz
	var a: Array=points[-2] if ending else points[0]
	var b: Array=points[-1] if ending else points[1]
	var d:=Vector3(b[0]-a[0],0,b[1]-a[1]).normalized()
	var centre: Array=points[-1] if ending else points[0]
	var origin: Vector3=city.to_global(Vector3(centre[0],0,centre[1]))
	var basis:=Basis(Vector3.UP,atan2(-d.x,-d.z))
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
	query.transform=Transform3D(Basis(Vector3.UP,atan2(-direction.x,-direction.z)),city.to_global(Vector3(a[0],.75,a[1])))
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
		"observations_enabled":observations_enabled,"valid":observations_valid,"human_present":human_present,"clear_s":clear_s,"owner":zone_owner,"queue":queue.duplicate(),"humans":human_rows.duplicate(true),"guards":guards.duplicate(true)}
