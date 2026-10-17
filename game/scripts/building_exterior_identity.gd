extends Node3D
## Photo-informed facade cues over unchanged source shells, not a reconstruction.
## All detail is shallow native MultiMesh geometry and carries no collision.
const DESIGN_PATH := "res://assets/authored/building_exteriors.json"
const WORLD_PATH := "res://resources/world_geometry/world.json"
var host: Node3D
var loaded := false
var load_error := ""
var design: Dictionary={}
var records: Array[Dictionary]=[]
var source_before: Dictionary={}
var batches: Array[MultiMeshInstance3D]=[]
var signs: Array[Label3D]=[]
var profile_counts: Dictionary={}
var piece_count := 0
var _materials: Dictionary={}
var _parts: Dictionary={}
var _by_id: Dictionary={}
var _current: Dictionary={}
var _bottom := 0.0
var _top := 0.0

func setup(root_scene: Node3D) -> bool:
	if loaded or not is_instance_valid(root_scene) or not root_scene.runtime_ok:return false
	host=root_scene;name="BuildingExteriorIdentity";process_mode=Node.PROCESS_MODE_PAUSABLE
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(DESIGN_PATH))
	var world: Variant=JSON.parse_string(FileAccess.get_file_as_string(WORLD_PATH))
	if not parsed is Dictionary or not world is Dictionary:return _fail("외관 표현 자료를 읽지 못했습니다.")
	if parsed.get("world_sha256")!=FileAccess.get_sha256(WORLD_PATH):return _fail("외관 표현과 원본 도시 버전이 다릅니다.")
	design=parsed
	var named: Dictionary={}
	for item: Dictionary in design.named_buildings:named[String(item.id)]=item
	for entry: Dictionary in world.meshes:
		if entry.get("role")!="Buildings" or entry.get("material")!="building":continue
		var source: MeshInstance3D=host.city.source_nodes.get(String(entry.id)) as MeshInstance3D
		if not is_instance_valid(source) or source.mesh==null:continue
		# L03 already replaces the SFC shell visually. Its retained source
		# envelope still anchors this explicitly named shallow facade detail;
		# do not reveal that shell or apply this exception to other landmarks.
		if not source.is_visible_in_tree() and not named.has(String(entry.id)):continue
		var faces: Array[Dictionary]=_source_faces(entry,source)
		if faces.is_empty():continue
		var bounds: AABB=source.global_transform*source.get_aabb()
		var profile: String=String(named[String(entry.id)].profile) if named.has(String(entry.id)) else _generic_profile(entry,bounds)
		if not design.profiles.has(profile):return _fail("지원하지 않는 외관 유형입니다.")
		source_before[String(entry.id)]=_source_state(source)
		_bottom=bounds.position.y;_top=bounds.end.y
		_current={"id":String(entry.id),"title":String(entry.metadata.get("name","")),"profile":profile,"named":named.has(String(entry.id)),"source_bounds":bounds,"source_height_m":_top-_bottom,"source_footprint_area_m2":float(entry.topology.get("footprint_area_m2",0.)),"face_count":faces.size(),"treated_faces":0,"pieces":0,"ingredients":design.profiles[profile].ingredients,"reference_ids":named[String(entry.id)].get("reference_ids",[]) if named.has(String(entry.id)) else [],"source_geometry_changed":false,"new_collision":false,"faces":faces}
		_materials_for(profile)
		# Named shells lose the competing generic window shader only. Their
		# original mesh, source transform, height and collision stay unchanged.
		var facades: Node=host.get_node_or_null("ExplorationOverlay/CityFacades")
		if bool(_current.named) and is_instance_valid(facades):facades.set_identity_profile(String(entry.id),profile,_color(design.profiles[profile].wall))
		var limit: int=mini(faces.size(),12 if bool(_current.named) else 4)
		for index in range(limit):
			var face: Dictionary=faces[index]
			if float(face.width)<(2.6 if bool(_current.named) else 5.0):continue
			_build_face(face,profile,bool(_current.named),index)
			_current.treated_faces+=1
		profile_counts[profile]=int(profile_counts.get(profile,0))+1
		records.append(_current);_by_id[String(entry.id)]=_current
	_flush()
	loaded=not records.is_empty()
	print("BUILDING_EXTERIOR_IDENTITY_READY buildings=",records.size()," profiles=",profile_counts.size()," native_parts=",piece_count," batches=",batches.size()," new_collision=0")
	return loaded

func _source_state(source: MeshInstance3D) -> Dictionary:
	return {"node":source.get_instance_id(),"mesh":source.mesh.get_instance_id(),"transform":source.global_transform,"bounds":source.get_aabb(),"faces_hash":hash(source.mesh.get_faces()),"visible":source.visible}

func _source_faces(entry: Dictionary,source: MeshInstance3D) -> Array[Dictionary]:
	var result: Array[Dictionary]=[];var found: Dictionary={}
	var vertices: Array=entry.vertices;var normals: Array=entry.normals
	for offset in range(0,vertices.size(),9):
		var normal:=Vector3(float(normals[offset]),float(normals[offset+1]),float(normals[offset+2]))
		if absf(normal.y)>.05:continue
		var points: Array[Vector3]=[]
		for corner in range(3):
			var point:=Vector3(float(vertices[offset+corner*3]),float(entry.bottom_y_m),float(vertices[offset+corner*3+2]))
			if not points.has(point):points.append(point)
		if points.size()!=2:continue
		var a: Vector3=points[0];var b: Vector3=points[1]
		var first: String="%.4f,%.4f"%[a.x,a.z];var second: String="%.4f,%.4f"%[b.x,b.z]
		var key: String=first+"|"+second if first<second else second+"|"+first
		if found.has(key):continue
		found[key]=true
		var outward:=Vector3(normal.x,0.,normal.z).normalized()
		var frame: Transform3D=source.global_transform*Transform3D(Basis(Vector3(outward.z,0.,-outward.x),Vector3.UP,outward),(a+b)*.5)
		result.append({"frame":frame,"width":a.distance_to(b),"height":float(entry.top_y_m)-float(entry.bottom_y_m),"source_edge_start":source.to_global(a),"source_edge_end":source.to_global(b)})
	result.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return float(a.width)>float(b.width))
	return result

func _generic_profile(entry: Dictionary,bounds: AABB) -> String:
	var tags: Dictionary=design.source_kind_tags.get(String(entry.id),{})
	var kind: String=String(tags.get("building","yes"));var height: float=bounds.size.y
	var area: float=float(entry.topology.get("footprint_area_m2",0.))
	var aspect: float=maxf(bounds.size.x,bounds.size.z)/maxf(.1,minf(bounds.size.x,bounds.size.z))
	if tags.get("tourism")=="hotel" or kind=="hotel":return "hotel_ribbon"
	if kind=="apartments" or (height<24. and aspect>2.6 and area>180.):return "plaster_balcony"
	if kind in ["roof","parking","warehouse","industrial"] or (height<10. and area>420.):return "service_hall"
	if tags.has("shop") or kind=="commercial" or height<15. or area<150.:return "brick_shopfront"
	if height>=65. and area>=350.:return "glass_office"
	return "stone_office"

func _color(values: Array) -> Color:return Color(float(values[0]),float(values[1]),float(values[2]))

func _materials_for(profile: String) -> void:
	for kind: String in ["wall","trim","glass","accent"]:
		var key: String=profile+":"+kind
		if _materials.has(key):continue
		var material:=StandardMaterial3D.new();material.albedo_color=_color(design.profiles[profile][kind]);material.roughness=.35 if kind=="glass" else .82
		material.metallic=.17 if kind=="glass" else (.25 if profile=="lotte_vertical" and kind=="trim" else 0.)
		_materials[key]=material

func _piece(frame: Transform3D,size: Vector3,at: Vector3,key: String,angle := 0.) -> void:
	if size.x<=.001 or size.y<=.001 or size.z<=.001:return
	var transform: Transform3D=frame*Transform3D(Basis(Vector3.BACK,angle).scaled_local(size),at)
	var bounds: AABB=transform*AABB(Vector3(-.5,-.5,-.5),Vector3.ONE)
	if bounds.position.y<_bottom+.045 or bounds.end.y>_top-.045:return
	if not _parts.has(key):_parts[key]=[]
	_parts[key].append(global_transform.affine_inverse()*transform)
	piece_count+=1;_current.pieces+=1

func _segment(frame: Transform3D,a: Vector2,b: Vector2,z: float,width: float,key: String) -> void:
	var delta: Vector2=b-a
	_piece(frame,Vector3(delta.length()+.025,width,.13),Vector3((a.x+b.x)*.5,(a.y+b.y)*.5,z),key,atan2(delta.y,delta.x))

func _build_face(face: Dictionary,profile: String,named: bool,index: int) -> void:
	var style: Dictionary=design.profiles[profile];var frame: Transform3D=face.frame
	var width: float=float(face.width)-.10;var height: float=face.height
	var podium: float=minf(float(style.podium_m),height*.24)
	var crown: float=minf(5.8 if named else .7,height*.09)
	var upper: float=height-crown
	var bays: int=clampi(int(floor(width/float(style.bay_m))),1,48 if named else 18)
	var bay: float=width/float(bays)
	var rows: int=clampi(int(floor((upper-podium)/float(style.floor_m))),1,42)
	var floor_height: float=(upper-podium)/float(rows)
	var trim: String=profile+":trim";var wall: String=profile+":wall";var glass: String=profile+":glass";var accent: String=profile+":accent"
	if named:
		_piece(frame,Vector3(width,upper-podium,.035),Vector3(0.,(upper+podium)*.5,.025),glass)
		_piece(frame,Vector3(width,podium-.14,.08),Vector3(0.,podium*.5+.02,.05),wall)
		_piece(frame,Vector3(width,crown-.10,.12),Vector3(0.,upper+crown*.5,.08),wall)
	_piece(frame,Vector3(width,.22,.16),Vector3(0.,.22,.09),accent)
	_piece(frame,Vector3(width,.38,.22),Vector3(0.,height-.28,.12),trim)
	for side: float in [-1.,1.]:
		_piece(frame,Vector3(minf(.68,width*.08),height-.2,.22),Vector3(side*(width*.5-.34),height*.5,.12),trim)
	if profile=="plaza_faceted":
		for row in range(rows):
			for column in range(bays):
				var centre:=Vector2(-width*.5+bay*(float(column)+.5),podium+floor_height*(float(row)+.5))
				var half_w: float=bay*.48;var half_h: float=floor_height*.46
				var ring: Array[Vector2]=[Vector2(-half_w*.68,-half_h),Vector2(half_w*.68,-half_h),Vector2(half_w,0.),Vector2(half_w*.68,half_h),Vector2(-half_w*.68,half_h),Vector2(-half_w,0.)]
				for segment in range(ring.size()):_segment(frame,centre+ring[segment],centre+ring[(segment+1)%ring.size()],.17,.18,trim)
	else:
		for column in range(bays+1):
			var x: float=-width*.5+float(column)*bay
			var pier: float=float(style.pier_m)
			if profile=="sfc_grouped_piers":pier=.95 if column%4==0 else (.38 if column%4==1 else .10)
			elif profile=="koreana_glass":pier=.08 if column not in [0,bays] else .65
			elif profile=="plaster_balcony" and column%2==1:pier*=2.0
			_piece(frame,Vector3(pier,upper-podium,.20),Vector3(clampf(x,-width*.5+pier*.5,width*.5-pier*.5),(upper+podium)*.5,.13),trim)
	for row in range(rows+1):
		var y: float=podium+float(row)*floor_height
		var band: float=float(style.band_m)
		if profile=="plaza_faceted" and row%3!=0:continue
		if profile=="service_hall" and row not in [0,rows]:continue
		_piece(frame,Vector3(width,band,.22 if profile in ["plaster_balcony","stone_office"] else .12),Vector3(0.,y,.13),trim)
	if profile=="plaza_faceted":
		for y: float in [podium*.30,podium*.68,podium-.42]:_piece(frame,Vector3(width,.68,.22),Vector3(0.,y,.13),accent)
	elif profile=="lotte_vertical":
		for column in range(bays):
			var x: float=-width*.5+bay*(float(column)+.5)
			_piece(frame,Vector3(bay*.65,crown*.56,.12),Vector3(x,upper+crown*.45,.15),glass)
	elif profile=="sfc_grouped_piers":
		for fraction: float in [.22,.50,.78]:_piece(frame,Vector3(width*.18,crown*.60,.12),Vector3(width*(fraction-.5),upper+crown*.45,.15),glass)
	elif profile=="service_hall":_piece(frame,Vector3(width*.86,.75,.10),Vector3(0.,minf(height-1.1,podium+1.5),.08),glass)
	# Ground-scale structure differs from the tower window system. These
	# shallow visual portals do not open or extend a retained source building.
	if index<2:
		var portal_width: float=minf(width*.52,12. if named else 5.2)
		var portal_height: float=minf(podium-.5,3.5)
		_piece(frame,Vector3(portal_width,portal_height,.10),Vector3(0.,portal_height*.5+.12,.11),glass)
		for side: float in [-1.,1.]:_piece(frame,Vector3(.32,portal_height+.3,.22),Vector3(side*(portal_width*.5+.20),portal_height*.5+.15,.14),trim)
		var canopy_y: float=portal_height+.45
		_piece(frame,Vector3(portal_width+.9,.24,.26),Vector3(0.,canopy_y,.14),accent)
		if profile in ["koreana_glass","brick_shopfront"]:
			for column in range(mini(bays,10)):
				var x: float=-width*.5+bay*(float(column)+.5)
				_piece(frame,Vector3(bay*.78,.30,.26),Vector3(x,minf(podium-.15,3.0),.14),accent)
		if named:_name_sign(frame,String(_current.title),width,upper+crown*.46,String(_current.id))

func _name_sign(frame: Transform3D,text: String,width: float,y: float,id: String) -> void:
	if text.is_empty():return
	var label:=Label3D.new();label.name="SourceBuildingName";label.text=text;label.font_size=64;label.pixel_size=.020
	label.modulate=Color(.95,.92,.80);label.outline_modulate=Color(.10,.12,.12);label.outline_size=4;label.shaded=false;label.no_depth_test=false
	var estimated: float=maxf(1.,text.length()*.64*64.*label.pixel_size)
	label.pixel_size*=minf(1.,minf(width*.72,21.)/estimated)
	add_child(label);label.global_transform=frame*Transform3D(Basis.IDENTITY,Vector3(0.,y,.25));label.visibility_range_end=190.;label.visibility_range_end_margin=15.
	label.set_meta("source_feature_id",id);signs.append(label)

func _flush() -> void:
	var box:=BoxMesh.new();box.size=Vector3.ONE
	for key: String in _parts:
		var transforms: Array=_parts[key]
		if transforms.is_empty():continue
		var mesh:=MultiMesh.new();mesh.transform_format=MultiMesh.TRANSFORM_3D;mesh.mesh=box;mesh.instance_count=transforms.size()
		for index in range(transforms.size()):mesh.set_instance_transform(index,transforms[index])
		var node:=MultiMeshInstance3D.new();node.name="Exterior_"+key.replace(":","_");node.multimesh=mesh;node.material_override=_materials[key]
		# One native batch per material; no scene node or collision per window.
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node);batches.append(node)
	_parts.clear()

func destination(id: String) -> Dictionary:
	if not loaded or not _by_id.has(id) or not is_instance_valid(host.interior_visit):return {}
	var record: Dictionary=_by_id[id];var bounds: AABB=record.source_bounds
	var toward: Vector3=bounds.get_center();toward.y=bounds.position.y+minf(42.,bounds.size.y*.40)
	for face: Dictionary in record.faces:
		if float(face.width)<8.:continue
		var frame: Transform3D=face.frame
		for distance: float in [28.,42.,18.,60.]:
			var requested: Vector3=frame.origin+frame.basis.z*distance+Vector3.UP*.08
			var safe: Dictionary=host.interior_visit._safe_external_point(requested)
			if safe.is_empty():continue
			return {"id":id,"title":record.title,"point":safe.point,"toward":toward,"kind":"validated_exterior_viewpoint","source_height_m":record.source_height_m,"teleport_required":false}
	return {}

func snapshot() -> Dictionary:
	return {"loaded":loaded,"error":load_error,"buildings":records.size(),"profile_counts":profile_counts,"native_parts":piece_count,"native_batches":batches.size(),"signs":signs.size(),"new_collision_bodies":0,"source_geometry_changed":false,"surveyed_reconstruction":false,"references":design.get("references",[]),"extent_analysis":design.get("source_extent_analysis",[]),"design_path":DESIGN_PATH}

func _fail(message: String) -> bool:
	load_error=message
	return false
