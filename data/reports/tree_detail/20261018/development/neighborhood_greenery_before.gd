extends Node3D
## OSM tree points plus labelled source-footway edge fill. Source geometry stays
## untouched; all visible trees use native spatial MultiMesh batches.
const DESIGN_PATH := "res://assets/authored/neighborhood_greenery.json"
const WORLD_PATH := "res://resources/world_geometry/world.json"
var loaded: bool=false
var load_error: String=""
var host: Node3D
var trees: Array[Dictionary]=[]
var skipped: Array[Dictionary]=[]
var batches: Array[MultiMeshInstance3D]=[]
var bodies: Array[StaticBody3D]=[]
var _design: Dictionary={}
var _activation_elapsed: float=0.0
var _active_collision_count: int=0
var _candidate_collision_count: int=0
var _materials: Dictionary={}
var _batch_rows: Dictionary={}
var _doors: Array[Vector3]=[]
var _maximum_slope_degrees: float=0.0

func setup(root_scene: Node3D) -> bool:
	if loaded or not is_inside_tree() or not is_instance_valid(root_scene):return false
	host=root_scene;process_mode=Node.PROCESS_MODE_PAUSABLE;name="NeighborhoodGreenery"
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(DESIGN_PATH))
	if not raw is Dictionary or raw.get("schema_version")!=1 or raw.get("world_sha256")!=FileAccess.get_sha256(WORLD_PATH):return _fail("가로수 자료와 원본 지도가 다릅니다.")
	_design=raw
	for building: Dictionary in host.interior_visit.catalog:
		for entry: Dictionary in building.entry_candidates:_doors.append(entry.entrance)
	for key: String in ["bark","leaf","grate"]:
		var material: StandardMaterial3D=StandardMaterial3D.new();material.vertex_color_use_as_albedo=true;material.roughness=.95
		_materials[key]=material
	for record: Dictionary in _design.trees:_prepare_tree(record)
	_publish_batches();_update_collisions()
	loaded=trees.size()>=40
	if not loaded:return _fail("안전한 가로수 지면을 충분히 확인하지 못했습니다.")
	print("NEIGHBORHOOD_GREENERY_READY visible=",trees.size()," native_batches=",batches.size()," source_tree_nodes=",_design.source_tree_node_count)
	return true

func _fail(message: String) -> bool:load_error=message;return false

func _terrain_point(point: Vector3) -> Vector3:
	var terrain: Variant=host.get("terrain_surface")
	if is_instance_valid(terrain) and bool(terrain.get("loaded")):
		var result: Dictionary=terrain.sample_ground_world(point)
		if bool(result.get("ok",false)):return result.point
	return point

func refresh_terrain() -> void:
	# Rebuild each instance from its tree's source XZ. A rigid batch translation
	# would leave the trees at the ends of a sloped 100m cell floating/buried.
	if not loaded:return
	for batch: MultiMeshInstance3D in batches:remove_child(batch);batch.queue_free()
	batches.clear();_batch_rows.clear();_maximum_slope_degrees=0.0
	for row: Dictionary in trees:
		var point: Vector3=_terrain_point(host.city.to_global(Vector3(row.record.xz[0],0.,row.record.xz[1])))
		var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*.4,point-Vector3.UP*.4,1|32,[row.body.get_rid(),host.player.get_rid()])
		var native: Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
		if not native.is_empty():
			point.y=native.position.y;row.floor_collider=String(native.collider.get_path())
		row.point=point+Vector3.UP*.02;row.floor_y=point.y;row.body.global_position=row.point
		var terrain: Variant=host.get("terrain_surface")
		if is_instance_valid(terrain) and bool(terrain.get("loaded")):
			var result: Dictionary=terrain.sample_ground_world(point)
			row.normal=result.get("normal",Vector3.UP);row.slope_degrees=rad_to_deg(acos(clampf(row.normal.y,-1.,1.)))
			_maximum_slope_degrees=maxf(_maximum_slope_degrees,row.slope_degrees)
		var cell: String=str(floori(point.x/100.))+"_"+str(floori(point.z/100.))
		if not _batch_rows.has(cell):_batch_rows[cell]=[]
		_batch_rows[cell].append(row)
	_publish_batches();_update_collisions()

func _ground(point: Vector3) -> Dictionary:
	point=_terrain_point(point)
	var query: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(point+Vector3.UP*8.0,point-Vector3.UP*3.0,1|32,[host.player.get_rid()])
	var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y<.80:return {}
	return hit

func _prepare_tree(record: Dictionary) -> void:
	var point: Vector3=host.city.to_global(Vector3(float(record.xz[0]),0.,float(record.xz[1])))
	if not host.player.free_roam_bounds.grow(-.5).has_point(Vector2(point.x,point.z)):
		skipped.append({"id":record.id,"reason":"outside_game_bounds"});return
	var local: Vector3=host.city.to_local(point)
	if host.city._contains(Vector2(local.x,local.z),host.city.private_cache):skipped.append({"id":record.id,"reason":"private_ground"});return
	for door: Vector3 in _doors:
		if Vector2(point.x-door.x,point.z-door.z).length()<1.85:skipped.append({"id":record.id,"reason":"door_approach"});return
	var support: Dictionary=_ground(point)
	if support.is_empty():skipped.append({"id":record.id,"reason":"missing_or_steep_floor"});return
	point.y=support.position.y+.02
	for direction: Vector3 in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
		var edge: Dictionary=_ground(point+direction*.48)
		if edge.is_empty() or absf(edge.position.y-support.position.y)>.20:skipped.append({"id":record.id,"reason":"unsupported_trunk_footprint"});return
	var clearance: CylinderShape3D=CylinderShape3D.new();clearance.radius=.25;clearance.height=3.0
	var query: PhysicsShapeQueryParameters3D=PhysicsShapeQueryParameters3D.new();query.shape=clearance;query.collision_mask=1|32;query.exclude=[support.rid,host.player.get_rid()];query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*1.52);query.margin=.01
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():skipped.append({"id":record.id,"reason":"source_solid_or_authored_fixture"});return
	var slope: float=rad_to_deg(acos(clampf(support.normal.y,-1.,1.)));_maximum_slope_degrees=maxf(_maximum_slope_degrees,slope)
	var body: StaticBody3D=StaticBody3D.new();body.name="TreeTrunk_"+String(record.id).replace(":","_");body.position=point;body.collision_layer=0;body.collision_mask=0;body.set_meta("geometry_id",String(record.id));body.set_meta("neighborhood_tree",true)
	var collision: CollisionShape3D=CollisionShape3D.new();var cylinder: CylinderShape3D=CylinderShape3D.new();cylinder.radius=.17;cylinder.height=3.1;collision.shape=cylinder;collision.position.y=1.55;collision.disabled=true;body.add_child(collision);add_child(body);bodies.append(body)
	var row: Dictionary={"record":record,"point":point,"body":body,"shape":collision,"active":false,"normal":support.normal,"floor_y":support.position.y,"floor_collider":String(support.collider.get_path()),"slope_degrees":slope};trees.append(row)
	var cell: String=str(floori(point.x/100.))+"_"+str(floori(point.z/100.))
	if not _batch_rows.has(cell):_batch_rows[cell]=[]
	_batch_rows[cell].append(row)

func _mesh(kind: String) -> Mesh:
	if kind=="bark":
		var cylinder: CylinderMesh=CylinderMesh.new();cylinder.top_radius=.14;cylinder.bottom_radius=.21;cylinder.height=3.2;cylinder.radial_segments=8;return cylinder
	if kind=="leaf":
		var sphere: SphereMesh=SphereMesh.new();sphere.radius=1.;sphere.height=2.;sphere.radial_segments=10;sphere.rings=5;return sphere
	var plate: BoxMesh=BoxMesh.new();plate.size=Vector3(1.,.028,.17);return plate

func _publish_batches() -> void:
	for cell: String in _batch_rows:
		var rows: Array=_batch_rows[cell]
		var centre: Vector3=Vector3.ZERO
		for row: Dictionary in rows:centre+=row.point
		centre/=float(rows.size())
		for kind: String in ["bark","leaf","grate"]:
			var instances: Array[Transform3D]=[];var colors: Array[Color]=[]
			for index: int in range(rows.size()):
				var row: Dictionary=rows[index];var at: Vector3=row.point-centre;var height: float=float(row.record.height_m)
				if kind=="bark":
					instances.append(Transform3D(Basis.IDENTITY,at+Vector3.UP*1.6));colors.append(Color(.31,.24,.17))
				elif kind=="leaf":
					for crown: int in range(3):
						var spread: Vector3=Vector3(1.55,1.40,1.50) if crown==0 else Vector3(1.15,1.30,1.1)
						var offset: Vector3=Vector3(0.,height-1.40,0.) if crown==0 else Vector3(-.75 if crown==1 else .80,height-2.0,.18 if crown==1 else -.20)
						offset.y=maxf(offset.y,2.65+spread.y)
						instances.append(Transform3D(Basis.IDENTITY.scaled(spread),at+offset));colors.append(Color(.23+.025*float(index%3),.42+.03*float(index%4),.20+.015*float(index%2)))
				else:
					for side: float in [-1.,1.]:
						instances.append(Transform3D(Basis.IDENTITY,at+Vector3(0,.012,side*.42)));colors.append(Color(.27,.29,.26))
						instances.append(Transform3D(Basis(Vector3.UP,PI*.5),at+Vector3(side*.42,.012,0)));colors.append(Color(.27,.29,.26))
			var batch: MultiMeshInstance3D=MultiMeshInstance3D.new();batch.name="StreetTrees_"+cell+"_"+kind;batch.position=centre;batch.visibility_range_end=230.;batch.visibility_range_end_margin=18.;batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind=="grate" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			var multimesh: MultiMesh=MultiMesh.new();multimesh.transform_format=MultiMesh.TRANSFORM_3D;multimesh.use_colors=true;multimesh.mesh=_mesh(kind);multimesh.instance_count=instances.size()
			for index: int in range(instances.size()):multimesh.set_instance_transform(index,instances[index]);multimesh.set_instance_color(index,colors[index])
			batch.multimesh=multimesh;batch.material_override=_materials[kind];add_child(batch);batches.append(batch)
	_batch_rows.clear()

func _actor_positions() -> Array[Vector3]:
	var result: Array[Vector3]=[]
	var people: Node3D=host.get("street_pedestrians") as Node3D
	if is_instance_valid(people):
		for row: Dictionary in people.actors:result.append(row.body.global_position)
	var population: Node3D=host.get_node_or_null("NeighborhoodPopulation") as Node3D
	if is_instance_valid(population) and population.has_method("actor_positions"):result.append_array(population.actor_positions())
	for body: CharacterBody3D in host.pedestrians:result.append(body.global_position)
	return result

func _update_collisions() -> void:
	var nearby: Array[Dictionary]=[];var actors: Array[Vector3]=_actor_positions()
	for row: Dictionary in trees:
		var player_distance: float=Vector2(row.point.x-host.player.global_position.x,row.point.z-host.player.global_position.z).length()
		var actor_distance: float=INF
		for point: Vector3 in actors:actor_distance=minf(actor_distance,Vector2(row.point.x-point.x,row.point.z-point.z).length())
		if player_distance<75. or actor_distance<12.:nearby.append({"row":row,"distance":minf(player_distance,actor_distance)})
	nearby.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return float(a.distance)<float(b.distance))
	_candidate_collision_count=nearby.size();var selected: Dictionary={}
	for index: int in range(mini(128,nearby.size())):selected[nearby[index].row.body.get_instance_id()]=true
	_active_collision_count=selected.size()
	for row: Dictionary in trees:
		var enabled: bool=selected.has(row.body.get_instance_id())
		if enabled==row.active:continue
		row.body.collision_layer=1 if enabled else 0;row.shape.set_deferred("disabled",not enabled);row.active=enabled

func _physics_process(delta: float) -> void:
	if not loaded:return
	_activation_elapsed+=delta
	if _activation_elapsed>=.5:_activation_elapsed=0.;_update_collisions()

func set_running(_enabled: bool) -> void:pass

func snapshot() -> Dictionary:
	var rows: Array=[]
	var source_count: int=0
	for row: Dictionary in trees:
		if row.record.basis=="source_natural_tree_node":source_count+=1
		rows.append({"id":row.record.id,"basis":row.record.basis,"position":row.point,"source_xz":row.record.xz,"floor_y":row.floor_y,"floor_collider":row.floor_collider,"slope_degrees":row.slope_degrees,"collision_active":row.active,"collision_layer":row.body.collision_layer,"trunk_radius_m":.17,"canopy_minimum_height_m":2.65})
	return {"loaded":loaded,"error":load_error,"source_osm_tree_node_count":_design.get("source_tree_node_count",0),"visible_tree_count":trees.size(),"source_tree_count":source_count,"authored_fill_count":trees.size()-source_count,"trees":rows,"skipped":skipped,"source_rejections":_design.get("source_rejections",[]),"native_batches":batches.size(),"visual_distance_m":230.,"collision_budget":128,"active_collisions":_active_collision_count,"nearby_collision_candidates":_candidate_collision_count,"maximum_floor_slope_degrees":_maximum_slope_degrees,"source_geometry_changed":false,"scope":"Retained OSM tree points and labelled authored source-footway-edge fill; ray-supported game ground, no current survey or legal-access claim. Native spatial batches render all accepted trees, while at most128 nearby trunks collide; canopies are non-solid and begin above pedestrian heads."}
