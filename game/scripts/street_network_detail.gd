extends Node3D
## Source-road-bound visual paint and street furniture. Placement/dimensions and
## the coordinated signal cycle are game art, never a surveyed/live Seoul plan.
## Build AFTER EXP21 commits terrain.loaded, so every surface is elevated once.
const DESIGN_PATH := "res://assets/authored/road_furniture.json"
const WARP := preload("res://scripts/terrain_geometry_warp.gd")
var loaded := false
var load_error := ""
var host: Node3D
var terrain: Node3D
var design: Dictionary={}
var paint_meshes: Array[MeshInstance3D]=[]
var paint_projection: Array[Dictionary]=[]
var lamps: Array[Dictionary]=[]
var signals: Array[Dictionary]=[]
var skipped: Array[Dictionary]=[]
var time_id := "day"
var quality_id := "standard"
var elapsed_s := 0.0
var active_lights := 0
var _light_elapsed := 0.0
var _last_state := ""
var _materials: Dictionary={}
var _batch_transforms: Dictionary={}
var _batch_meshes: Dictionary={}
var _batch_materials: Dictionary={}
var _crossing_ids: Dictionary={}
var _paint_faces := 0
var _minimum_paint_clearance_m := INF
var _maximum_paint_clearance_m := -INF
var _setup_usec := 0
var surface_mask_audit: Array=[]

func _fail(message: String) -> bool:
	load_error=message;push_error(message);return false

func setup(root_scene: Node3D) -> bool:
	if loaded or not is_inside_tree() or not is_instance_valid(root_scene):return false
	host=root_scene;terrain=host.get("terrain_surface") as Node3D
	if not is_instance_valid(terrain) or not bool(terrain.get("loaded")):return _fail("거리 세부 표현은 지형 연결 뒤 준비해야 합니다.")
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(DESIGN_PATH))
	if not raw is Dictionary or raw.get("schema_version")!=1:return _fail("거리 시설 자료를 읽지 못했습니다.")
	design=raw
	for path: String in design.get("source_hashes",{}):
		if FileAccess.get_sha256(path)!=String(design.source_hashes[path]):return _fail("거리 시설과 도로·지형 원본이 다릅니다.")
	name="StreetNetworkDetail";process_mode=Node.PROCESS_MODE_PAUSABLE
	global_transform=host.city.global_transform
	var started: int=Time.get_ticks_usec()
	_make_materials()
	for row: Dictionary in design.crossings:_crossing_ids[String(row.id)]=true
	if not _mask_walk_render_surfaces():return false
	if not _build_paint():return false
	_build_lamps();_build_signals();_publish_batches()
	loaded=not paint_meshes.is_empty() and not signals.is_empty() and not lamps.is_empty()
	if not loaded:return _fail("거리 표시·신호·조명을 준비하지 못했습니다.")
	if is_instance_valid(host.get("traffic")):host.traffic.attach_signal_provider(self)
	var population: Node=host.get("neighborhood_population") as Node
	if is_instance_valid(population) and is_instance_valid(population.get("traffic")):
		population.traffic.manager.attach_signal_provider(self)
	_update_signals();_update_lights();_setup_usec=Time.get_ticks_usec()-started
	print("STREET_NETWORK_READY corridors=",design.counts.road_corridors," paint=",design.paint.size()," signals=",signals.size()," lamps=",lamps.size()," source_geometry_changed=false timing=game_authored")
	return true

func _material(color: Color,emission := false) -> StandardMaterial3D:
	var result:=StandardMaterial3D.new();result.albedo_color=color;result.roughness=.72
	if emission:
		result.emission_enabled=true;result.emission=color;result.emission_energy_multiplier=2.0
	return result

func _make_materials() -> void:
	_materials.steel=_material(Color(.105,.125,.14))
	_materials.flange=_material(Color(.23,.25,.25))
	_materials.glass=_material(Color(.90,.84,.63),true)
	_materials.off=_material(Color(.035,.045,.044))
	_materials.red=_material(Color(1.0,.055,.035),true)
	_materials.amber=_material(Color(1.0,.54,.025),true)
	_materials.green=_material(Color(.035,.94,.25),true)
	_materials.white=_material(Color(.98,.975,.89))
	_materials.yellow=_material(Color(.98,.70,.065))
	_materials.white.roughness=.96;_materials.yellow.roughness=.96
	# The authored paint is a thin surface with a17mm clearance over the old
	# .035m road display. No polygon offset or raised box hides terrain seams.

func _mask_walk_render_surfaces() -> bool:
	var warp: RefCounted=WARP.new();warp.configure(terrain,host.city)
	for row: Dictionary in design.get("surface_masks",[]):
		var visual: MeshInstance3D=host.city.source_nodes.get(row.node_id)
		if not is_instance_valid(visual):return _fail("차도와 겹친 원본 보도 표시 노드가 없습니다: "+String(row.node_id))
		var identity: int=visual.get_instance_id();var children: Array=visual.get_children()
		var points:=PackedVector3Array()
		for i: int in range(0,row.retained_triangles_xz.size(),3):
			var triangle:=PackedVector3Array()
			for j: int in range(3):
				var xz: Array=row.retained_triangles_xz[i+j];triangle.append(Vector3(xz[0],row.source_y_m,xz[1]))
			if (triangle[2]-triangle[0]).cross(triangle[1]-triangle[0]).y<0:points.append_array(PackedVector3Array([triangle[0],triangle[2],triangle[1]]))
			else:points.append_array(triangle)
		var audit: Dictionary={"node_id":row.node_id,"source_feature_id":row.source_feature_id,"masked_drive_overlap_m2":row.masked_drive_overlap_m2,"retained_area_m2":row.retained_area_m2,"source_y_m":row.source_y_m}
		if points.is_empty():visual.visible=false;audit["entire_display_masked"]=true
		else:
			var normals:=PackedVector3Array();normals.resize(points.size());normals.fill(Vector3.UP)
			var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=normals
			var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);visual.mesh=mesh
			audit["projection"]=warp.warp_mesh(visual)
			if not audit.projection.ok:return _fail("보도 표시 경계의 지형 투영에 실패했습니다.")
		audit["same_source_node"]=visual.get_instance_id()==identity;audit["same_children"]=visual.get_children()==children
		surface_mask_audit.append(audit)
	return true

func _build_paint() -> bool:
	var points: Dictionary={"white":PackedVector3Array(),"yellow":PackedVector3Array()}
	for row: Dictionary in design.paint:
		var polygon:=PackedVector2Array()
		for p: Array in row.xz:polygon.append(Vector2(p[0],p[1]))
		var indices: PackedInt32Array=Geometry2D.triangulate_polygon(polygon)
		if indices.is_empty():return _fail("도로 표시 면을 나눌 수 없습니다: "+String(row.id))
		var values: PackedVector3Array=points[String(row.color)]
		for i: int in range(0,indices.size(),3):
			var a:=Vector3(polygon[indices[i]].x,.052,polygon[indices[i]].y)
			var b:=Vector3(polygon[indices[i+1]].x,.052,polygon[indices[i+1]].y)
			var c:=Vector3(polygon[indices[i+2]].x,.052,polygon[indices[i+2]].y)
			if (c-a).cross(b-a).y<0.0:values.append_array(PackedVector3Array([a,c,b]))
			else:values.append_array(PackedVector3Array([a,b,c]))
		points[String(row.color)]=values
	var warp: RefCounted=WARP.new();warp.configure(terrain,host.city)
	for color: String in points:
		var vertices: PackedVector3Array=points[color]
		if vertices.is_empty():continue
		var normals:=PackedVector3Array();normals.resize(vertices.size());normals.fill(Vector3.UP)
		var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var visual:=MeshInstance3D.new();visual.name="RoadPaint_"+color;visual.mesh=mesh;visual.material_override=_materials[color]
		visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;visual.layers=1;add_child(visual)
		var audit: Dictionary=warp.warp_mesh(visual);audit["color"]=color;paint_projection.append(audit)
		if not bool(audit.get("ok",false)) or int(audit.get("output_faces",0))==0:return _fail("도로 표시 지형 투영에 유효한 면이 없습니다.")
		# Roads crossing the selected world edge can extend beyond the prepared
		# TIN. The exact projection helper clips those nonrequired outer portions;
		# keep its omission counts explicit rather than aborting the whole city.
		if int(audit.get("uncovered_source_faces",0))>0:skipped.append({"id":"uncovered_road_paint_"+color,"kind":"paint","reason":"uncovered_source_slivers_omitted_by_exact_terrain_clip","source_faces":audit.uncovered_source_faces,"omitted_xz_area_m2":float(audit.source_xz_area_m2)-float(audit.covered_xz_area_m2)})
		paint_meshes.append(visual)
		var actual: PackedVector3Array=visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		_paint_faces+=actual.size()/3
		for index: int in range(0,actual.size(),3):
			# Measure the actual post-projection face centre, not just an anchor.
			var point: Vector3=visual.to_global((actual[index]+actual[index+1]+actual[index+2])/3.0)
			var floor_y: float=terrain.ground_y_world(point)
			if not is_finite(floor_y):return _fail("도로 표시의 실제 면이 지형 밖입니다.")
			_minimum_paint_clearance_m=minf(_minimum_paint_clearance_m,point.y-floor_y)
			_maximum_paint_clearance_m=maxf(_maximum_paint_clearance_m,point.y-floor_y)
	return true

func _world_ground(xz: Array) -> Vector3:
	var flat: Vector3=host.city.to_global(Vector3(xz[0],0.0,xz[1]));var y: float=terrain.ground_y_world(flat)
	return Vector3(flat.x,y+.015,flat.z) if is_finite(y) else Vector3.INF

func _volume_clear(point: Vector3,height: float,radius := .3) -> bool:
	if not point.is_finite():return false
	var shape:=BoxShape3D.new();shape.size=Vector3(radius*2.0,height,radius*2.0)
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.collision_mask=1;query.margin=.01
	query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*(height*.5+.15))
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _furniture_head_clear(frame: Transform3D,size: Vector3) -> bool:
	var shape:=BoxShape3D.new();shape.size=size
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.collision_mask=1;query.margin=.01;query.transform=frame
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _batch(kind: String,mesh: Mesh,material: Material,frame: Transform3D) -> void:
	if not _batch_transforms.has(kind):
		_batch_transforms[kind]=[];_batch_meshes[kind]=mesh;_batch_materials[kind]=material
	_batch_transforms[kind].append(global_transform.affine_inverse()*frame)

func _box_batch(kind: String,size: Vector3,frame: Transform3D,material: Material) -> void:
	var mesh:=BoxMesh.new();mesh.size=size;_batch(kind,mesh,material,frame)

func _cylinder_batch(kind: String,bottom: float,top: float,height: float,frame: Transform3D,material: Material) -> void:
	var mesh:=CylinderMesh.new();mesh.bottom_radius=bottom;mesh.top_radius=top;mesh.height=height;mesh.radial_segments=12
	_batch(kind,mesh,material,frame)

func _build_lamps() -> void:
	for row: Dictionary in design.lamps:
		var point: Vector3=_world_ground(row.xz);var height: float=row.height_m;var arm: float=row.arm_m
		if not _volume_clear(point,height,.28):skipped.append({"id":row.id,"kind":"lamp","reason":"native_static_volume"});continue
		var toward: Vector3=_world_ground(row.toward_xz);var direction: Vector3=(toward-point);direction.y=0;direction=direction.normalized()
		var frame:=Transform3D(Basis(Vector3.UP,atan2(-direction.x,-direction.z)),point)
		if not _furniture_head_clear(frame*Transform3D(Basis.IDENTITY,Vector3(0,height-.17,-arm*.5)),Vector3(.58,.42,arm+.88)):
			skipped.append({"id":row.id,"kind":"lamp","reason":"native_static_head_or_arm_volume"});continue
		var suffix: String="tall" if height>6 else "short"
		_cylinder_batch("LampPole_"+suffix,.105,.06,height,frame*Transform3D(Basis.IDENTITY,Vector3(0,height*.5,0)),_materials.steel)
		_box_batch("LampBase",Vector3(.37,.16,.37),frame*Transform3D(Basis.IDENTITY,Vector3(0,.08,0)),_materials.flange)
		_box_batch("LampServiceDoor",Vector3(.15,.58,.025),frame*Transform3D(Basis.IDENTITY,Vector3(0,.9,.085)),_materials.flange)
		_box_batch("LampArm_"+suffix,Vector3(.085,.085,arm),frame*Transform3D(Basis.IDENTITY,Vector3(0,height-.17,-arm*.5)),_materials.steel)
		_box_batch("LampLEDHousing",Vector3(.39,.14,.83),frame*Transform3D(Basis.IDENTITY,Vector3(0,height-.17,-arm)),_materials.steel)
		_box_batch("LampLEDPanel",Vector3(.31,.018,.66),frame*Transform3D(Basis.IDENTITY,Vector3(0,height-.246,-arm)),_materials.glass)
		var light:=SpotLight3D.new();light.name="WarmPavement_"+String(row.id);add_child(light)
		light.global_position=frame*Vector3(0,height-.28,-arm);light.rotation_degrees.x=-90.0
		light.light_color=Color(1.0,.79,.49);light.light_energy=1.8;light.spot_range=16.0;light.spot_angle=54.0;light.spot_attenuation=1.15
		light.shadow_enabled=false;light.distance_fade_enabled=true;light.distance_fade_begin=55;light.distance_fade_length=15;light.visible=false
		lamps.append({"id":row.id,"source_feature_id":row.source_feature_id,"point":point,"head":light.global_position,"light":light,"height_m":height,"active":false})

func _visual_box(parent: Node3D,title: String,size: Vector3,at: Vector3,material: Material) -> MeshInstance3D:
	var mesh:=BoxMesh.new();mesh.size=size
	var node:=MeshInstance3D.new();node.name=title;node.mesh=mesh;node.material_override=material;node.position=at;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node);return node

func _lens(parent: Node3D,at: Vector3) -> MeshInstance3D:
	var mesh:=CylinderMesh.new();mesh.top_radius=.18;mesh.bottom_radius=.18;mesh.height=.045;mesh.radial_segments=20
	var node:=MeshInstance3D.new();node.name="SignalLens";node.mesh=mesh;node.material_override=_materials.off;node.position=at;node.rotation_degrees.x=90
	parent.add_child(node);return node

func _build_signals() -> void:
	for row: Dictionary in design.signals:
		var point: Vector3=_world_ground(row.xz);var height: float=row.height_m
		if not _volume_clear(point,height,.22):skipped.append({"id":row.id,"kind":"signal","reason":"native_static_volume"});continue
		var direction:=Vector3(row.direction_xz[0],0,row.direction_xz[1]);direction=host.city.global_basis*direction
		var frame:=Transform3D(Basis(Vector3.UP,atan2(-direction.x,-direction.z)),point)
		var arm: float=float(row.arm_m)*float(row.arm_sign)
		if not _furniture_head_clear(frame*Transform3D(Basis.IDENTITY,Vector3(arm*.5,height-.24,.08)),Vector3(absf(arm)+1.9,1.0,.80)):
			skipped.append({"id":row.id,"kind":"signal","reason":"native_static_head_or_arm_volume"});continue
		_cylinder_batch("SignalPole",.09,.07,height,frame*Transform3D(Basis.IDENTITY,Vector3(0,height*.5,0)),_materials.steel)
		_box_batch("SignalPoleServiceBox",Vector3(.22,.42,.14),frame*Transform3D(Basis.IDENTITY,Vector3(0,1.05,-.04)),_materials.steel)
		_box_batch("SignalPoleBase",Vector3(.34,.15,.34),frame*Transform3D(Basis.IDENTITY,Vector3(0,.075,0)),_materials.flange)
		_box_batch("SignalArm_"+String(row.id),Vector3(absf(arm),.09,.09),frame*Transform3D(Basis.IDENTITY,Vector3(arm*.5,height-.1,0)),_materials.steel)
		var head:=Node3D.new();head.name="VehicleSignal_"+String(row.id);add_child(head);head.global_transform=frame*Transform3D(Basis.IDENTITY,Vector3(arm,height-.24,0))
		_visual_box(head,"SignalBackplate",Vector3(1.90,.88,.035),Vector3(0,-.12,-.125),_materials.steel)
		_visual_box(head,"HorizontalSignalCase",Vector3(1.74,.74,.24),Vector3(0,-.12,0),_materials.steel)
		var lenses: Array[MeshInstance3D]=[]
		for x: float in [-.55,0,.55]:
			var rim:=_lens(head,Vector3(x,0,.125));(rim.mesh as CylinderMesh).top_radius=.215;(rim.mesh as CylinderMesh).bottom_radius=.215;rim.material_override=_materials.flange;rim.name="LensBezel"
			lenses.append(_lens(head,Vector3(x,0,.145)))
			_visual_box(head,"LensSunHood",Vector3(.40,.055,.28),Vector3(x,.23,.22),_materials.steel)
		var remaining:=Label3D.new();remaining.name="VehiclePhaseSeconds";remaining.font_size=48;remaining.pixel_size=.0038;remaining.position=Vector3(0,-.33,.135);remaining.double_sided=false;remaining.billboard=BaseMaterial3D.BILLBOARD_DISABLED;remaining.outline_modulate=Color(.015,.02,.02);head.add_child(remaining)
		signals.append({"id":row.id,"crossing_id":row.crossing_id,"kind":"vehicle","point":point,"head":head,"lenses":lenses,"countdown":remaining,"controller_stop_point":_world_ground(row.controller_stop_xz),"stop_line_id":row.stop_line_id})
	# Each road bank has a physical far-end head facing INWARD across the road.
	# Its opposite-bank approach is explicit, so reverse-direction readability
	# is independently testable rather than a double-sided material shortcut.
	for row: Dictionary in design.pedestrian_signals:
		var point: Vector3=_world_ground(row.xz)
		var front: Vector3=host.city.global_basis*Vector3(row.front_direction_xz[0],0,row.front_direction_xz[1])
		var frame:=Transform3D(Basis(Vector3.UP,atan2(front.x,front.z)),point)
		# Terrain at the northern bridge banks has a substantial source-derived
		# height difference. Keep the pole rooted, and raise the lower head only
		# as far as a real native ray needs to see its front from the far bank.
		var eye: Vector3=_world_ground(row.opposite_bank_approach_xz)+Vector3.UP*1.4
		var head_height:=2.25
		while head_height<5.26:
			var target: Vector3=frame*Vector3(0,head_height,.145)
			var ray: Dictionary=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye,target,1|32,[host.player.get_rid()]))
			if ray.is_empty():break
			head_height+=.5
		if head_height>5.25 or not _volume_clear(point,head_height+.55,.18):skipped.append({"id":row.id,"kind":"pedestrian_signal","reason":"native_static_volume_or_far_bank_LOS"});continue
		var pole_height: float=head_height+.55
		_cylinder_batch("PedestrianSignalPole_"+String(row.id),.06,.05,pole_height,frame*Transform3D(Basis.IDENTITY,Vector3(0,pole_height*.5,0)),_materials.steel)
		var head:=Node3D.new();head.name="PedestrianSignal_"+String(row.id);add_child(head);head.global_transform=frame*Transform3D(Basis.IDENTITY,Vector3(0,head_height,0))
		_visual_box(head,"PedestrianSignalCase",Vector3(.78,1.02,.19),Vector3.ZERO,_materials.steel)
		_visual_box(head,"PedestrianInsetFace",Vector3(.70,.94,.015),Vector3(0,0,.105),_materials.off)
		_visual_box(head,"PedestrianVisor",Vector3(.85,.045,.32),Vector3(0,.52,.16),_materials.steel)
		var red_icon:=_person_icon(head,Vector3(-.14,.23,.128),false)
		var green_icon:=_person_icon(head,Vector3(-.14,-.16,.128),true)
		var countdown:=Label3D.new();countdown.name="GameCrossingCountdown";countdown.font_size=32;countdown.pixel_size=.004;countdown.position=Vector3(.18,-.16,.128);countdown.double_sided=false;countdown.billboard=BaseMaterial3D.BILLBOARD_DISABLED;countdown.modulate=Color(.08,1,.28);countdown.outline_modulate=Color(.02,.04,.03);head.add_child(countdown)
		signals.append({"id":head.name,"crossing_id":row.crossing_id,"kind":"pedestrian","bank":row.bank,"point":point,"head":head,"front_direction":front,"approach_point":_world_ground(row.approach_xz)+Vector3.UP*.065,"opposite_bank_approach":_world_ground(row.opposite_bank_approach_xz)+Vector3.UP*.065,"red_icon":red_icon,"green_icon":green_icon,"countdown":countdown})

func _person_icon(parent: Node3D,origin: Vector3,walking: bool) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D]=[]
	result.append(_visual_box(parent,"PersonHead",Vector3(.06,.06,.02),origin+Vector3(0,.115,0),_materials.off))
	result.append(_visual_box(parent,"PersonTorso",Vector3(.055,.11,.02),origin+Vector3(0,.025,0),_materials.off))
	for side: float in [-1.0,1.0]:
		var leg:=_visual_box(parent,"PersonLeg",Vector3(.035,.12,.02),origin+Vector3(side*(.038 if walking else .022),-.078,0),_materials.off)
		leg.rotation.z=side*(.35 if walking else .03);result.append(leg)
		var arm:=_visual_box(parent,"PersonArm",Vector3(.028,.1,.02),origin+Vector3(side*.054,.024,0),_materials.off)
		arm.rotation.z=side*(.6 if walking else .1);result.append(arm)
	return result

func _publish_batches() -> void:
	for kind: String in _batch_transforms:
		var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=_batch_meshes[kind];multi.instance_count=_batch_transforms[kind].size()
		for index: int in range(multi.instance_count):multi.set_instance_transform(index,_batch_transforms[kind][index])
		var visual:=MultiMeshInstance3D.new();visual.name=kind;visual.multimesh=multi;visual.material_override=_batch_materials[kind];visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(visual)
	_batch_meshes.clear();_batch_materials.clear()

func vehicle_signal_state(crossing_id: String) -> String:
	if not _crossing_ids.has(crossing_id):return "uncontrolled"
	var t: float=fposmod(elapsed_s,float(design.cycle.duration_s))
	if t<float(design.cycle.vehicle_green_end_s):return "green"
	return "amber" if t<float(design.cycle.vehicle_amber_end_s) else "red"

func pedestrian_signal_state(crossing_id: String) -> String:
	if not _crossing_ids.has(crossing_id):return "uncontrolled"
	var t: float=fposmod(elapsed_s,float(design.cycle.duration_s))
	return "green" if t>=float(design.cycle.pedestrian_green_start_s) and t<float(design.cycle.pedestrian_green_end_s) else "red"

func signal_phase_snapshot(crossing_id: String) -> Dictionary:
	if not _crossing_ids.has(crossing_id):return {"vehicle":"uncontrolled","pedestrian":"uncontrolled","remaining_s":0,"pedestrian_remaining_s":0,"pedestrian_flashing":false,"pedestrian_lit":false}
	var t: float=fposmod(elapsed_s,float(design.cycle.duration_s))
	var vehicle: String=vehicle_signal_state(crossing_id);var ped: String=pedestrian_signal_state(crossing_id)
	var end: float=float(design.cycle.vehicle_green_end_s) if vehicle=="green" else float(design.cycle.vehicle_amber_end_s) if vehicle=="amber" else float(design.cycle.duration_s)
	var ped_end: float=float(design.cycle.pedestrian_green_end_s) if ped=="green" else float(design.cycle.pedestrian_green_start_s) if t<float(design.cycle.pedestrian_green_start_s) else float(design.cycle.duration_s)+float(design.cycle.pedestrian_green_start_s)
	var flashing: bool=ped=="green" and t>=float(design.cycle.get("pedestrian_flash_start_s",38.0))
	var flash_on: bool=not flashing or fposmod(t,float(design.cycle.get("flash_period_s",.5)))<float(design.cycle.get("flash_period_s",.5))*.5
	return {"vehicle":vehicle,"pedestrian":ped,"remaining_s":ceili(end-t),"pedestrian_remaining_s":ceili(ped_end-t),"pedestrian_flashing":flashing,"pedestrian_lit":ped=="green" and flash_on}

func allows_vehicle(_route_id: String,crossing_id: String) -> bool:
	return vehicle_signal_state(crossing_id) in ["green","uncontrolled"]

func vehicle_stop_distance(source: String,point: Vector3,direction: Vector3,max_distance: float,ignored_crossings: Array=[]) -> Dictionary:
	var flat_direction:=Vector3(direction.x,0,direction.z).normalized()
	var best: Dictionary={"required":false,"distance_m":max_distance,"reason":"no_red_signal_ahead","crossing_id":"","state":"uncontrolled"}
	for row: Dictionary in design.get("stop_lines",[]):
		if String(row.source_feature_id)!=source:continue
		if String(row.crossing_id) in ignored_crossings:continue
		var expected: Vector3=host.city.global_basis*Vector3(row.direction_xz[0],0,row.direction_xz[1])
		if flat_direction.dot(expected)<.75:continue
		var stop: Vector3=host.city.to_global(Vector3(row.paint_stop_xz[0],0,row.paint_stop_xz[1]))
		var delta: Vector3=stop-point;delta.y=0
		var distance: float=delta.dot(expected)
		var lateral: float=absf(delta.dot(Vector3(expected.z,0,-expected.x)))
		if distance<-.15 or distance>float(best.distance_m) or lateral>16.0:continue
		var state: String=vehicle_signal_state(String(row.crossing_id))
		best={"required":state in ["red","amber"],"distance_m":maxf(0,distance),"reason":"signal_"+state,"crossing_id":row.crossing_id,"state":state,"clearance_from_stop_m":float(row.get("clearance_from_stop_m",10.0)),"stop_line_id":row.id}
	return best

func advance_signal_time(seconds: float) -> void:
	if seconds<0 or not is_finite(seconds):return
	elapsed_s=fposmod(elapsed_s+seconds,float(design.get("cycle",{}).get("duration_s",46.0)));_update_signals()

func set_time_profile(id: String) -> void:
	if id not in ["day","evening","night"]:return
	time_id=id;_update_lights()

func apply_quality(id: String) -> void:
	quality_id=id;_update_lights()

func _update_lights() -> void:
	if not is_instance_valid(host):return
	var ordered: Array=lamps.duplicate()
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:return (a.point as Vector3).distance_squared_to(host.player.global_position)<(b.point as Vector3).distance_squared_to(host.player.global_position))
	var budget: int=6 if quality_id in ["low","light"] else 12;active_lights=0
	for row: Dictionary in ordered:
		var on: bool=time_id!="day" and active_lights<budget and (row.point as Vector3).distance_to(host.player.global_position)<=70.0
		row.light.visible=on;row.light.light_energy=1.8 if time_id=="night" else .9;row.active=on
		if on:active_lights+=1
	_materials.glass.emission_energy_multiplier=1.6 if time_id!="day" else 0.0

func _update_signals() -> void:
	for row: Dictionary in signals:
		var id: String=String(row.crossing_id)
		var phase: Dictionary=signal_phase_snapshot(id)
		if row.kind=="vehicle":
			var state: String=phase.vehicle
			for index: int in range(3):row.lenses[index].material_override=_materials[state] if state==["red","amber","green"][index] else _materials.off
			row.countdown.text=str(phase.remaining_s);row.countdown.modulate=_materials[state].albedo_color
		else:
			var green: bool=phase.pedestrian=="green"
			for icon: MeshInstance3D in row.red_icon:icon.material_override=_materials.off if green else _materials.red
			for icon: MeshInstance3D in row.green_icon:icon.material_override=_materials.green if bool(phase.pedestrian_lit) else _materials.off
			row.countdown.text=str(phase.pedestrian_remaining_s);row.countdown.modulate=_materials.green.albedo_color if green else _materials.red.albedo_color

func _physics_process(delta: float) -> void:
	if not loaded:return
	elapsed_s=fposmod(elapsed_s+delta,float(design.cycle.duration_s))
	var state: String=vehicle_signal_state("sejong_marked")+pedestrian_signal_state("sejong_marked")+str(floori(elapsed_s*4.0))
	if state!=_last_state:_last_state=state;_update_signals()
	_light_elapsed+=delta
	if _light_elapsed>=.35:_light_elapsed=0;_update_lights()

func destination(id := "crossing") -> Dictionary:
	var flat:=Vector3(60,0,-204);var target:=Vector3(83,0,-195)
	if id=="crossing":
		for row: Dictionary in signals:
			if row.kind=="pedestrian" and row.crossing_id=="source_node_921242887" and int(row.bank)==0:
				var side:=Vector3(-row.front_direction.z,0,row.front_direction.x)
				for lateral: float in [-5.5,5.5,-7.0,7.0]:
					var safe: Dictionary=host._exploration_destination(row.opposite_bank_approach+side*lateral)
					if safe.is_empty():continue
					var view: Dictionary=_checked_signal_view(safe.point,row,4.2,-8.)
					if not view.is_empty():return view
	if id=="crossing_vehicle":
		for row: Dictionary in signals:
			if row.kind=="vehicle" and row.crossing_id=="source_node_921242887":
				var forward: Vector3=-row.head.global_basis.z;forward.y=0;forward=forward.normalized()
				var safe: Dictionary=host._exploration_destination(row.controller_stop_point-forward*8.0+Vector3.UP*.065)
				if safe.is_empty():continue
				var view: Dictionary=_checked_signal_view(safe.point,row,4.2,-8.)
				if not view.is_empty():return view
	if id=="lamps" and not lamps.is_empty():
		var row: Dictionary=lamps[0];flat=host.city.to_local(row.point)+Vector3(-5,0,5);target=host.city.to_local(row.point)+Vector3.UP*2.0
	var point: Vector3=host.city.to_global(flat);var y: float=terrain.ground_y_world(point)
	point.y=y+.08
	var toward: Vector3=host.city.to_global(target);toward.y=terrain.ground_y_world(toward)+1.1
	return {"id":id,"point":point,"toward":toward,"basis":"authored_native_review_destination_not_real_access"}

func _checked_signal_view(point: Vector3,row: Dictionary,distance: float,pitch_degrees: float) -> Dictionary:
	var target: Vector3=row.head.global_position+row.head.global_basis.z*.145
	var forward: Vector3=target-point;forward.y=0;forward=forward.normalized()
	var eye: Vector3=point-forward*distance*cos(deg_to_rad(pitch_degrees))+Vector3.UP*(host.rig.pivot_height_m-distance*sin(deg_to_rad(pitch_degrees)))
	var ray: Dictionary=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye,target,1|32,[host.player.get_rid()]))
	if not ray.is_empty():return {}
	for other: Dictionary in signals:
		if other.head==row.head:continue
		var box: MeshInstance3D=other.head.get_node("PedestrianSignalCase" if other.kind=="pedestrian" else "HorizontalSignalCase")
		if box.mesh.get_aabb().intersects_segment(box.to_local(eye),box.to_local(target))!=null:return {}
	return {"id":"crossing","point":point,"toward":target,"target_head":row.head,"camera_yaw":atan2(-forward.x,-forward.z),"camera_pitch_degrees":pitch_degrees,"camera_distance_m":distance,"basis":"authored_supported_signal_observer_with_static_and_rendered_case_LOS_not_real_access"}

func snapshot() -> Dictionary:
	var lamp_rows: Array=[];var signal_rows: Array=[]
	for row: Dictionary in lamps:lamp_rows.append({"id":row.id,"source_feature_id":row.source_feature_id,"point":row.point,"head":row.head,"height_m":row.height_m,"active":row.active,"actual_light_class":row.light.get_class(),"range_m":row.light.spot_range,"energy":row.light.light_energy,"visible":row.light.visible})
	for row: Dictionary in signals:signal_rows.append({"id":row.id,"crossing_id":row.crossing_id,"kind":row.kind,"bank":row.get("bank",-1),"point":row.point,"head_point":row.head.global_position,"front_direction":row.head.global_basis.z,"approach_point":row.get("approach_point",row.point),"opposite_bank_approach":row.get("opposite_bank_approach",row.point),"state":vehicle_signal_state(String(row.crossing_id)) if row.kind=="vehicle" else pedestrian_signal_state(String(row.crossing_id))})
	return {"loaded":loaded,"error":load_error,"terrain_bound_after_loaded":true,"source_geometry_changed":false,"old_route_arrays_changed":false,"new_collision_count":0,"paint_mesh_count":paint_meshes.size(),"paint_faces":_paint_faces,"paint_polygons":design.get("paint",[]).size(),"paint_clearance_TIN_min_m":_minimum_paint_clearance_m,"paint_clearance_TIN_max_m":_maximum_paint_clearance_m,"paint_projection":paint_projection.duplicate(true),"surface_masks":surface_mask_audit.duplicate(true),"counts":design.get("counts",{}).duplicate(true),"preflight":design.get("preflight",{}).duplicate(true),"lamps":lamp_rows,"signals":signal_rows,"active_lights":active_lights,"light_budget":6 if quality_id in ["low","light"] else 12,"time_id":time_id,"quality_id":quality_id,"elapsed_s":elapsed_s,"vehicle_state":vehicle_signal_state("sejong_marked"),"pedestrian_state":pedestrian_signal_state("sejong_marked"),"cycle":design.get("cycle",{}).duplicate(true),"stop_lines":design.get("stop_lines",[]).duplicate(true),"skipped":skipped.duplicate(true),"setup_usec":_setup_usec,"timing_basis":"game_authored_coordinated_not_real_signal_timing","provenance":design.get("provenance",{}).duplicate(true),"design_sha256":FileAccess.get_sha256(DESIGN_PATH)}
