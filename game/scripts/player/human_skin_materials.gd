extends RefCounted
## Small shared, project-authored PBR maps. No source images or game textures.
## The caller duplicates its material; only read-only microtextures are shared.
const MAP_SIZE := 128
const VERSION := 1
static var _maps: Dictionary={}

static func role_from_name(material_name: String) -> String:
	var title:=material_name.to_lower()
	# Earlier prototypes shared dark eye pieces with hair. Only the new,
	# explicitly separated eye material receives the wet-eye settings.
	if "original_eye" in title:return "eye"
	if "jacket" in title or "swimwear" in title:return "jacket"
	if "trousers" in title:return "pants"
	if "hands" in title:return "hands"
	if "skin" in title:return "skin"
	if "hair" in title:return "hair"
	if "sneakers" in title:return "shoes"
	return "detail"

static func apply_to(material: StandardMaterial3D,role: String,tangent_ready: bool) -> void:
	if material==null:return
	var kind:="";var normal_strength:=0.
	# Preserve albedo, vertex colors, UVs, transparency, depth and cull policy.
	# Roughness is multiplied by its map, so its bounded product is intentional.
	material.metallic=0.;material.clearcoat_enabled=false
	material.subsurf_scatter_enabled=false;material.subsurf_scatter_strength=0.
	material.subsurf_scatter_skin_mode=false;material.subsurf_scatter_transmittance_enabled=false
	match role:
		"skin","hands":
			kind="skin";normal_strength=.18
			material.roughness=.82;material.metallic_specular=.30
			if RenderingServer.get_current_rendering_method()=="forward_plus":
				material.subsurf_scatter_enabled=true;material.subsurf_scatter_skin_mode=true;material.subsurf_scatter_strength=.035
		"hair":
			# Existing head UVs are not a strand-flow groom. Keep this relief
			# below obvious directional bands; matte response does most work.
			kind="hair";normal_strength=.025
			material.roughness=.96;material.metallic_specular=.18
		"jacket","pants":
			kind="fabric";normal_strength=.20
			material.roughness=.97;material.metallic_specular=.12
		"shoes":
			kind="fabric";normal_strength=.14
			material.roughness=.82;material.metallic_specular=.20
		"eye":
			material.roughness=.22;material.metallic_specular=.42
		_:
			material.roughness=.85;material.metallic_specular=.18
	material.normal_enabled=not kind.is_empty() and tangent_ready
	material.normal_scale=normal_strength
	material.normal_texture=null;material.roughness_texture=null
	if not kind.is_empty():
		var maps: Dictionary=_get_maps(kind)
		material.roughness_texture=maps.roughness;material.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
		if tangent_ready:material.normal_texture=maps.normal
	material.set_meta("human_material_version",VERSION);material.set_meta("human_material_role",role)
	material.set_meta("human_normal_tangent_ready",tangent_ready)

static func _height(kind: String,x: float,y: float) -> float:
	var u:=x/float(MAP_SIZE);var v:=y/float(MAP_SIZE)
	match kind:
		"skin":
			# Periodic fine relief, not painted facial pores or dark color noise.
			return .26*sin(TAU*(29.*u+17.*v))*sin(TAU*(19.*u-31.*v))+.10*sin(TAU*(47.*u+13.*v))
		"hair":return .28*sin(TAU*(43.*u+2.*v))+.06*sin(TAU*(7.*u+29.*v))
		_:return .22*sin(TAU*32.*u)*cos(TAU*32.*v)+.05*sin(TAU*(13.*u+17.*v))

static func _get_maps(kind: String) -> Dictionary:
	if _maps.has(kind):return _maps[kind]
	var normal:=Image.create(MAP_SIZE,MAP_SIZE,false,Image.FORMAT_RGB8)
	var roughness:=Image.create(MAP_SIZE,MAP_SIZE,false,Image.FORMAT_R8)
	var minimum:=INF;var maximum:=-INF
	for y: int in range(MAP_SIZE):
		for x: int in range(MAP_SIZE):
			var dx:=(_height(kind,x+1.,y)-_height(kind,x-1.,y))*.30
			var dy:=(_height(kind,x,y+1.)-_height(kind,x,y-1.))*.30
			var direction:=Vector3(-dx,-dy,1.).normalized()
			normal.set_pixel(x,y,Color(direction.x*.5+.5,direction.y*.5+.5,direction.z*.5+.5))
			var grain:=.5+.5*sin(TAU*(17.*float(x)/MAP_SIZE+23.*float(y)/MAP_SIZE))
			var low:=.86 if kind=="skin" else (.90 if kind=="hair" else .88)
			var value:=lerpf(low,1.,grain);minimum=minf(minimum,value);maximum=maxf(maximum,value)
			roughness.set_pixel(x,y,Color(value,value,value))
	normal.generate_mipmaps();roughness.generate_mipmaps()
	var result: Dictionary={"normal":ImageTexture.create_from_image(normal),"roughness":ImageTexture.create_from_image(roughness),"minimum_roughness_map":minimum,"maximum_roughness_map":maximum,"image_bytes_with_mips":normal.get_data().size()+roughness.get_data().size()}
	_maps[kind]=result;return result

static func cache_snapshot() -> Dictionary:
	var rows: Dictionary={};var total_bytes:=0
	for kind: String in _maps:
		var maps: Dictionary=_maps[kind];total_bytes+=int(maps.image_bytes_with_mips)
		rows[kind]={"normal_id":maps.normal.get_instance_id(),"roughness_id":maps.roughness.get_instance_id(),"width":MAP_SIZE,"height":MAP_SIZE,"roughness_map_min":maps.minimum_roughness_map,"roughness_map_max":maps.maximum_roughness_map,"image_bytes_with_mips":maps.image_bytes_with_mips}
	return {"version":VERSION,"shared_map_pairs":_maps.size(),"shared_texture_count":_maps.size()*2,"image_bytes_with_mips":total_bytes,"maps":rows,"albedo_changed_by_helper":false,"external_source_images":false,"runtime_generation":"Once per skin/hair/fabric kind; no Node, timer, physics or render process."}
