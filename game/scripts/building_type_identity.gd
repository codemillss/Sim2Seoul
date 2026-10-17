extends Node3D
## Source-bound, non-colliding facade ornaments. Dimensions/style are authored;
## the shared building meshes, footprint, source height and bodies stay intact.
const CATALOG_PATH:="res://assets/authored/interiors/source_catalog.json"
const CHURCH_ID:="osm:way:223418691:building"
var loaded:=false
var host: Node3D
var records: Array[Dictionary]=[]
var meshes: Array[MeshInstance3D]=[]
var signs: Array[Label3D]=[]
var _church_spec: Dictionary={}
var _materials: Dictionary={}

func setup(root_scene: Node3D) -> bool:
	if loaded or not is_instance_valid(root_scene) or not root_scene.runtime_ok:return false
	host=root_scene;name="BuildingTypeIdentity";process_mode=Node.PROCESS_MODE_PAUSABLE
	var catalog: Variant=JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not catalog is Dictionary or catalog.get("world_sha256")!=FileAccess.get_sha256("res://resources/world_geometry/world.json"):return false
	var colors: Dictionary={"stone":Color(.76,.66,.48),"red_stone":Color(.49,.28,.18),"wood":Color(.20,.12,.075),"gold":Color(.86,.69,.34),"dark":Color(.055,.095,.12),"glass_blue":Color(.17,.40,.64),"glass_rose":Color(.61,.26,.29),"glass_green":Color(.24,.50,.40),"hotel":Color(.17,.21,.25),"office":Color(.18,.30,.32)}
	for key: String in colors:
		var material:=StandardMaterial3D.new();material.albedo_color=colors[key];material.roughness=.85
		if String(key).begins_with("glass_"):material.emission_enabled=true;material.emission=colors[key]*.3
		_materials[key]=material
	var office_count:=0
	for spec: Dictionary in catalog.records:
		if not host.city.source_nodes.has(spec.id) or spec.entry_candidates.is_empty():continue
		var title:=String(spec.title);var kind:=""
		if spec.id==CHURCH_ID or spec.get("source_building_tag","")=="church":kind="church"
		elif "호텔" in title or "hotel" in title.to_lower() or "프레이저" in title:kind="hotel"
		elif office_count<10 and "빌딩" in title and not "성공회" in title:kind="office";office_count+=1
		if kind.is_empty():continue
		if kind=="church":
			_church_spec=spec
			for index in range(mini(3,spec.entry_candidates.size())):_church_face(spec,spec.entry_candidates[index],index)
		else:_type_sign(spec,kind)
		records.append({"id":spec.id,"title":title,"kind":kind,"source_height_m":spec.source_height,"source_footprint_unchanged":true,"source_height_unchanged":true,"new_collision":false})
	loaded=not _church_spec.is_empty()
	print("BUILDING_TYPE_IDENTITY_READY church=",not _church_spec.is_empty()," facade_records=",records.size()," source_geometry_changed=false")
	return loaded

func _frame(entry: Dictionary) -> Transform3D:
	var outward:=Vector3(entry.outward[0],0,entry.outward[1]).normalized()
	var basis:=Basis(Vector3(outward.z,0,-outward.x),Vector3.UP,outward)
	return host.city.global_transform*Transform3D(basis,Vector3(entry.door[0],0,entry.door[1]))

func _mesh(frame: Transform3D,title: String,mesh: Mesh,at: Vector3,material: String) -> MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=title;node.mesh=mesh;node.material_override=_materials[material];node.visibility_range_end=150.;node.visibility_range_end_margin=15.
	add_child(node);node.global_transform=frame*Transform3D(Basis.IDENTITY,at);meshes.append(node)
	return node

func _box(frame: Transform3D,title: String,size: Vector3,at: Vector3,material: String) -> MeshInstance3D:
	var mesh:=BoxMesh.new();mesh.size=size;return _mesh(frame,title,mesh,at,material)

func _label(frame: Transform3D,title: String,text: String,at: Vector3,width: float) -> Label3D:
	var label:=Label3D.new();label.name=title;label.text=text;label.font_size=64;label.pixel_size=.011;label.outline_size=8
	label.modulate=Color(.97,.93,.77);label.outline_modulate=Color(.045,.065,.075);label.no_depth_test=false;label.shaded=false
	add_child(label);label.global_transform=frame*Transform3D(Basis.IDENTITY,at)
	var estimated:=text.length()*.58*64.*label.pixel_size
	if estimated>width:label.pixel_size*=width/estimated
	label.visibility_range_end=90.;label.visibility_range_end_margin=8.;signs.append(label)
	return label

func _bar(frame: Transform3D,title: String,a: Vector3,b: Vector3,width: float,material: String) -> void:
	var delta:=b-a;var node:=_box(frame,title,Vector3(width,delta.length(),.07),(a+b)*.5,material)
	node.global_basis=frame.basis*Basis(Quaternion(Vector3.UP,delta.normalized()))

func _church_face(spec: Dictionary,entry: Dictionary,index: int) -> void:
	var frame:=_frame(entry);var width:=minf(3.35,float(entry.source_edge_length)-.55);var half:=width*.5
	var cap:=minf(11.6,float(spec.source_height)-.15);var rose_y:=minf(6.4,cap-3.1)
	# A shallow Romanesque-inspired portal reads as a church without cutting
	# a new opening into the existing source building collision.
	_box(frame,"ChurchPortalDark",Vector3(width-.28,2.45,.04),Vector3(0,1.23,.045),"wood")
	for side in [-1.,1.]:
		_box(frame,"ChurchPortalStone",Vector3(.22,2.5,.10),Vector3(side*half,1.25,.075),"stone")
		_box(frame,"ChurchDoorPanel",Vector3((width-.45)*.47,1.7,.025),Vector3(side*(width-.45)*.25,1.1,.08),"red_stone")
		_box(frame,"ChurchDoorHandle",Vector3(.055,.28,.035),Vector3(side*.12,1.12,.105),"gold")
	for segment in range(14):
		var a:=float(segment)/14.*PI;var b:=float(segment+1)/14.*PI
		_bar(frame,"ChurchPortalArch",Vector3(cos(a)*half,2.5+sin(a)*half,.075),Vector3(cos(b)*half,2.5+sin(b)*half,.075),.22,"stone")
	_box(frame,"ChurchNameBackplate",Vector3(width+.12,.68,.06),Vector3(0,4.57,.065),"dark")
	_label(frame,"ChurchSourceName",String(spec.title),Vector3(0,4.57,.105),width-.12)
	_label(frame,"ChurchWorshipEntrance","예배 공간 · 입구",Vector3(0,.45,.11),width-.25)
	# Stained glass and stone spokes are shallow facade ornaments, kept below
	# the pre-existing source top; no new floor, body or height is introduced.
	var disc:=CylinderMesh.new();disc.top_radius=.8;disc.bottom_radius=.8;disc.height=.055;disc.radial_segments=32
	var rose:=_mesh(frame,"ChurchRoseWindow",disc,Vector3(0,rose_y,.065),"dark");rose.global_basis=frame.basis*Basis(Vector3.RIGHT,PI*.5)
	for segment in range(12):
		var angle:=float(segment)/12.*TAU;var next:=float(segment+1)/12.*TAU
		var outer:=Vector3(cos(angle)*.82,rose_y+sin(angle)*.82,.10);var outer_next:=Vector3(cos(next)*.82,rose_y+sin(next)*.82,.10)
		_bar(frame,"ChurchRoseStoneRim",outer,outer_next,.10,"stone")
		_bar(frame,"ChurchRoseSpoke",Vector3(0,rose_y,.10),outer*.72+Vector3(0,rose_y*.28,0.028),.055,"stone")
		var glass: String=["glass_blue","glass_rose","glass_green"][segment%3]
		var pane:=_box(frame,"ChurchStainedPane",Vector3(.19,.29,.025),Vector3(cos(angle+.26)*.45,rose_y+sin(angle+.26)*.45,.11),glass)
		pane.global_basis=frame.basis*Basis(Vector3.FORWARD,-angle-.26)
	_box(frame,"ChurchCrossVertical",Vector3(.20,2.05,.11),Vector3(0,cap-1.18,.075),"gold")
	_box(frame,"ChurchCrossHorizontal",Vector3(1.30,.20,.11),Vector3(0,cap-.79,.075),"gold")
	# Two red stone lines suggest a gable while staying within the existing
	# height envelope. They are an authored cue, not a surveyed roof model.
	_bar(frame,"ChurchGableLeft",Vector3(-half,cap-2.9,.075),Vector3(0,cap-.05,.075),.15,"red_stone")
	_bar(frame,"ChurchGableRight",Vector3(0,cap-.05,.075),Vector3(half,cap-2.9,.075),.15,"red_stone")
	set_meta("church_face_"+str(index),{"source_id":spec.id,"entry_index":index,"source_edge_length_m":entry.source_edge_length,"width_m":width,"top_y_m":cap,"source_top_y_m":spec.source_height})

func _type_sign(spec: Dictionary,kind: String) -> void:
	var entry: Dictionary=spec.entry_candidates[0];var frame:=_frame(entry)
	var width:=minf(4.0,float(entry.source_edge_length)-.35);var height:=minf(4.25,float(spec.source_height)-.65)
	_box(frame,"BuildingTypeBackplate",Vector3(width,.9,.06),Vector3(0,height,.06),kind)
	_label(frame,"BuildingTypeSourceTitle",String(spec.title),Vector3(0,height+.16,.105),width-.25)
	_label(frame,"BuildingTypePurpose","호텔 · LOBBY" if kind=="hotel" else "업무 공간 · OFFICE",Vector3(0,height-.24,.105),width-.35)

func destination() -> Dictionary:
	if not loaded:return {}
	var entry: Dictionary=_church_spec.entry_candidates[0];var frame:=_frame(entry);var outward:=frame.basis.z
	var toward:=frame.origin+Vector3.UP*4.5
	var capsule:=CapsuleShape3D.new();capsule.radius=.31;capsule.height=1.7
	for distance in [7.,5.,3.,2.]:
		var point: Vector3=frame.origin+outward*distance
		var hit: Dictionary=host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP,point-Vector3.UP,1|32))
		if hit.is_empty() or hit.normal.y<.8:continue
		point.y=hit.position.y+.08
		var local: Vector3=host.city.to_local(point)
		if host.city._contains(Vector2(local.x,local.z),host.city.private_cache):continue
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.collision_mask=1|2|4|8|32;query.exclude=[host.player.get_rid()]
		query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.85)
		if not host.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():continue
		return {"id":CHURCH_ID,"point":point,"toward":toward}
	return {}

func snapshot() -> Dictionary:
	return {"loaded":loaded,"records":records,"mesh_count":meshes.size(),"sign_count":signs.size(),"new_collision_bodies":0,"source_geometry_changed":false,"surveyed_facade":false,"style_basis":"Authored shallow Romanesque-inspired portal, rose window, cross and gable cues, anchored to source church edges below unchanged source height. Hotel/office labels use source titles; present tenancy/service is unverified."}
