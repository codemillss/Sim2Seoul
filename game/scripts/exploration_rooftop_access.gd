extends Node3D
## Shared source-positioned roofs for free outdoor jumps and elevator visits.
## This cache never changes source bodies/heights or teleports a passing player.
const REPRESENTATIVE_POOL_ID := "osm:way:233593619:building"
const PERSISTENT_HOTEL_IDS := [REPRESENTATIVE_POOL_ID,"osm:way:233593644:building"]
const PREPARE_DISTANCE_M := 45.0
const PREPARE_BELOW_ROOF_M := 15.0
const RETAIN_DISTANCE_M := 140.0
const SCAN_INTERVAL_SECONDS := .25
var host: Node3D
var visit: Node3D
var roofs: Dictionary = {}
var _specs: Dictionary = {}
var _borrowed: Dictionary = {}
var _scan_elapsed := 0.0
var _outdoor_water_id := ""
var _loaded := false
var creations := 0
var removals := 0
var active_outdoor_roof: Node3D

func setup(root_scene: Node3D, visit_controller: Node3D) -> bool:
	if _loaded or not is_inside_tree() or not is_instance_valid(root_scene) or not is_instance_valid(visit_controller):return false
	host=root_scene;visit=visit_controller
	for building: Dictionary in visit.catalog:_specs[String(building.id)]=building
	# The initial prepared library roof already exists before this helper.
	# Retain its identity and make the cache its owner, without a second deck.
	var initial: Node3D=visit.rooftop
	if is_instance_valid(initial):
		var id:=String(initial.spec.get("id",""))
		initial.reparent(self,true);roofs[id]=initial;_borrowed[id]=true
	process_mode=Node.PROCESS_MODE_PAUSABLE
	process_physics_priority=2
	for id: String in PERSISTENT_HOTEL_IDS:ensure_rooftop(id)
	_loaded=true
	return true

func owns_rooftop(roof: Node3D) -> bool:
	return is_instance_valid(roof) and roof.get_parent()==self and roofs.get(String(roof.spec.get("id","")))==roof

func ensure_rooftop(id: String) -> Node3D:
	var existing:=roofs.get(id) as Node3D
	if is_instance_valid(existing):return existing
	if not _specs.has(id) or not is_instance_valid(host):return null
	var roof: Node3D=preload("res://scripts/rooftop_space.gd").new()
	roof.name="ExplorationRoof_"+id.replace(":","_");add_child(roof)
	if not roof.setup(host,_specs[id]):roof.queue_free();return null
	roofs[id]=roof;roof.visible=true;roof.set_process(false);creations+=1
	return roof

func borrow_rooftop(id: String) -> Node3D:
	var roof:=ensure_rooftop(id)
	if not is_instance_valid(roof):return null
	_borrowed[id]=true
	return roof

func release_rooftop(roof: Node3D) -> void:
	if not owns_rooftop(roof):return
	_borrowed.erase(String(roof.spec.get("id","")))
	roof.visible=true;roof.set_process(false)

func representative_pool_destination() -> Dictionary:
	var roof:=ensure_rooftop(REPRESENTATIVE_POOL_ID)
	if not is_instance_valid(roof):return {}
	return {"building_id":REPRESENTATIVE_POOL_ID,"building_title":roof.spec.title,"title":"야외 수영장 · 24 × 10m", "roof":roof,
		"point":roof.spawn_point(),"pool_entry":roof.pool_entry_point(),"pool_float":roof.pool_float_point(),"camera_point":roof.pool_camera_point(),"pool_dimensions":roof.pool_dimensions()}

func _footprint_distance(point: Vector3, building: Dictionary) -> float:
	var centre: Vector2=building.rectangle_center
	var axis: Vector3=building.rectangle_along
	var offset:=Vector3(point.x-centre.x,0,point.z-centre.y)
	var lateral:=axis.cross(Vector3.UP)
	var dx:=maxf(0.0,absf(offset.dot(axis))-minf(float(building.width)-1.6,32.0)*.5)
	var dz:=maxf(0.0,absf(offset.dot(lateral))-minf(float(building.depth)-1.6,36.0)*.5)
	return Vector2(dx,dz).length()

func _prepare_nearby_roofs(point: Vector3) -> void:
	var candidates: Array[Dictionary]=[]
	for id: String in _specs:
		if roofs.has(id):continue
		var building: Dictionary=_specs[id]
		var distance:=_footprint_distance(point,building)
		if distance<=PREPARE_DISTANCE_M and point.y>=float(building.source_height)-PREPARE_BELOW_ROOF_M:
			candidates.append({"id":id,"distance":distance})
	candidates.sort_custom(func(first: Dictionary,last: Dictionary)->bool:return float(first.distance)<float(last.distance))
	# Construction is amortized while approaching in the air. The nearest
	# footprint is first, so the landing target exists before descent reaches it.
	for index in range(mini(3,candidates.size())):ensure_rooftop(String(candidates[index].id))
	for id: String in roofs.keys():
		if _borrowed.has(id) or id in PERSISTENT_HOTEL_IDS:continue
		if _footprint_distance(point,_specs[id])<=RETAIN_DISTANCE_M:continue
		var roof: Node3D=roofs[id]
		for body: StaticBody3D in roof.bodies:body.collision_layer=0
		roofs.erase(id);roof.queue_free();removals+=1

func _update_outdoor_water(point: Vector3) -> void:
	# Interior/lift state owns its validated water registration. Outdoor use
	# leaves interior_active false, allowing real jumps off and between roofs.
	if host.player.interior_active or (visit.active and not visit.on_roof):
		if visit.active and visit.on_roof and is_instance_valid(visit.rooftop):
			_publish_camera_hint(visit.rooftop.pool_camera_pivot_hint(point))
		else:_publish_camera_hint({})
		_outdoor_water_id="";active_outdoor_roof=null
		return
	var selected: Node3D
	for id: String in roofs:
		if _borrowed.has(id) and visit.active and visit.rooftop!=roofs[id]:continue
		var roof: Node3D=roofs[id]
		roof.visible=true
		var local: Vector3=roof.frame.affine_inverse()*point
		var lower: float=float(roof.pool_water_region().get("floor_y",-.2))-.20 if roof.profile_id=="outdoor_pool" else -.4
		var near: bool=roof.walkable_rect.grow(.5).has_point(Vector2(local.x,local.z)) and local.y>=lower and local.y<=8.0
		roof.set_process(near)
		if near and roof.profile_id=="outdoor_pool":selected=roof
	active_outdoor_roof=selected
	_publish_camera_hint(selected.pool_camera_pivot_hint(point) if is_instance_valid(selected) else {})
	var next_id:=String(selected.spec.id) if is_instance_valid(selected) else ""
	if next_id==_outdoor_water_id:return
	if not _outdoor_water_id.is_empty():host.player.clear_water_region()
	_outdoor_water_id=""
	if is_instance_valid(selected) and host.player.has_method("set_outdoor_water_region"):
		if host.player.set_outdoor_water_region(selected.pool_water_region(),selected.world_bounds,selected.walkable_rect):_outdoor_water_id=next_id

func _publish_camera_hint(hint: Dictionary) -> void:
	if is_instance_valid(host.rig) and host.rig.has_method("set_roof_camera_hint"):host.rig.set_roof_camera_hint(hint)

func clear_outdoor_water() -> void:
	if not _outdoor_water_id.is_empty() and is_instance_valid(host):host.player.clear_water_region()
	_outdoor_water_id="";active_outdoor_roof=null
	_publish_camera_hint({})

func _physics_process(delta: float) -> void:
	if not _loaded or not is_instance_valid(host.player):return
	var point: Vector3=host.player.global_position
	if not point.is_finite():return
	_scan_elapsed+=delta
	if _scan_elapsed>=SCAN_INTERVAL_SECONDS:
		_scan_elapsed=0.0
		if not visit.active:_prepare_nearby_roofs(point)
	_update_outdoor_water(point)

func snapshot() -> Dictionary:
	var prepared:=[]
	for id: String in roofs:
		var roof: Node3D=roofs[id]
		prepared.append({"id":id,"profile":roof.profile_id,"visible":roof.visible,"borrowed":_borrowed.has(id),"origin":roof.frame.origin,"pool_dimensions":roof.pool_dimensions()})
	return {"loaded":_loaded,"cached_roofs":prepared,"created":creations,"removed":removals,"outdoor_water_building_id":_outdoor_water_id,
		"persistent_hotels":PERSISTENT_HOTEL_IDS,"prepare_distance_m":PREPARE_DISTANCE_M,"prepare_below_roof_m":PREPARE_BELOW_ROOF_M,"retain_distance_m":RETAIN_DISTANCE_M,
		"source_geometry_preserved":true,"outdoor_visit_state_required":false,"basis":"Source-positioned authored amenities. Outdoor jumping/swimming retains the exterior player region; elevator visits borrow the same roof."}
