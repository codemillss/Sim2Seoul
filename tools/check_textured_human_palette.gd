extends SceneTree
## Actual imported mesh/material readback. Native outfit pixels remain a
## separate acceptance requirement; this fixture never substitutes proxies.
class Actor extends CharacterBody3D:
	var facility_control:=false
var report:={"task":"ACTUAL_TEXTURED_HUMAN_PALETTE_READBACK","engine":Engine.get_version_info().string,"checks":[],"models":[],"native_visual_acceptance":false}
var failed:=0

func _initialize() -> void:call_deferred("_run")

func _check(title: String,ok: bool,evidence: Dictionary={}) -> void:
	report.checks.append({"name":title,"passed":ok,"evidence":evidence})
	if not ok:failed+=1

func _plain(value: Variant) -> Variant:
	if value is Color:return [value.r,value.g,value.b,value.a]
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Dictionary:
		var result:={}
		for key: Variant in value:result[str(key)]=_plain(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value:result.append(_plain(item))
		return result
	return value

func _mean_reflectance(surface: Node3D) -> Dictionary:
	var mesh: ArrayMesh=surface.visible_meshes[0].mesh
	var source: ArrayMesh=surface._weighted_mesh_cache[surface.model_id]
	var arrays: Array=mesh.surface_get_arrays(0);var original: Array=source.surface_get_arrays(0)
	var texture: Image=surface._body_material.albedo_texture.get_image()
	if texture.is_compressed():texture.decompress()
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV];var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX];var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR];var masks: PackedColorArray=original[Mesh.ARRAY_COLOR]
	var sums: Array[Color]=[Color(0,0,0,0),Color(0,0,0,0)];var areas: Array[float]=[0.,0.]
	var material_gain: Color=surface._body_material.albedo_color.srgb_to_linear()
	var min_channel:=1.;var max_channel:=0.
	for color: Color in colors:
		min_channel=minf(min_channel,minf(color.r,minf(color.g,color.b)));max_channel=maxf(max_channel,maxf(color.r,maxf(color.g,color.b)))
	for triangle: int in range(0,indices.size(),3):
		var a: int=indices[triangle];var b: int=indices[triangle+1];var c: int=indices[triangle+2]
		var area: float=(vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).length()*.5
		var midpoint: Vector2=(uv[a]+uv[b]+uv[c])/3.
		var pixel:=texture.get_pixel(clampi(int(fposmod(midpoint.x,1.)*texture.get_width()),0,texture.get_width()-1),clampi(int(fposmod(midpoint.y,1.)*texture.get_height()),0,texture.get_height()-1)).srgb_to_linear()
		var amount: Color=(colors[a]+colors[b]+colors[c])/3.;var region:=1 if masks[a].g+masks[b].g+masks[c].g>1.5 else 0
		sums[region]+=pixel*amount*material_gain*area;areas[region]+=area
	return {"jacket_linear":sums[0]/areas[0],"pants_linear":sums[1]/areas[1],"vertex_rgb_min":min_channel,"vertex_rgb_max":max_channel,"material_gain_linear":material_gain,"source_means":surface._garment_texture_means}

func _rgb_error(value: Color,goal: Color) -> float:
	return maxf(absf(value.r-goal.r),maxf(absf(value.g-goal.g),absf(value.b-goal.b)))

func _run() -> void:
	for id: String in ["Male_Adult_04","Female_Adult_07"]:
		var actor:=Actor.new();root.add_child(actor);actor.set_meta("human_model_id",id)
		var visual:=Node3D.new();visual.name="Visual";actor.add_child(visual)
		var old:=MeshInstance3D.new();old.name="Body";visual.add_child(old)
		var avatar: Node3D=load("res://scripts/player/exploration_avatar.gd").new();visual.add_child(avatar);avatar.setup(actor);avatar.set_physics_process(false)
		await process_frame;await process_frame
		var wrapper: Node3D=avatar._textured_surface;var actual: MeshInstance3D=wrapper.visible_meshes[0]
		var initial_mesh: Mesh=actual.mesh;var initial_skin: Skin=actual.skin
		var original_head: Material=actual.get_surface_override_material(1);var original_hair: Material=actual.get_surface_override_material(2);var original_hands: StandardMaterial3D=actual.get_surface_override_material(3)
		var original_head_color: Color=original_head.albedo_color;var original_hand_color: Color=original_hands.albedo_color
		var body_texture: Texture2D=wrapper._body_material.albedo_texture;var body_normal: Texture2D=wrapper._body_material.normal_texture
		var initial_arrays: Array=actual.mesh.surface_get_arrays(0)
		var torso: MeshInstance3D=avatar.find_child("Torso",true,false);var jacket: Color=torso.material_override.albedo_color;var pants: Color=avatar._materials.trousers.albedo_color
		var before:=_mean_reflectance(wrapper)
		_check(id+".default_original_texture",wrapper._body_material.albedo_color.is_equal_approx(Color.WHITE) and before.vertex_rgb_min==1. and before.vertex_rgb_max==1.,before)
		var trials: Array=[]
		for target: Color in [Color(.92,.95,.98),Color(.70,.045,.035)]:
			var pants_target:=Color(.045,.11,.52)
			torso.material_override.albedo_color=target;avatar._materials.trousers.albedo_color=pants_target;wrapper.sync_clothing()
			var measured:=_mean_reflectance(wrapper);var goal:=target.srgb_to_linear();var pants_goal:=pants_target.srgb_to_linear()
			var error:=_rgb_error(measured.jacket_linear,goal);var pants_error:=_rgb_error(measured.pants_linear,pants_goal)
			_check(id+".selected_fabric_mean",error<.04 and pants_error<.04,{"target":target,"actual_readback":measured,"maximum_jacket_error_linear":error,"maximum_pants_error_linear":pants_error})
			_check(id+".packed_vertex_range",measured.vertex_rgb_min>=0. and measured.vertex_rgb_max<=1.,measured)
			var arrays: Array=actual.mesh.surface_get_arrays(0)
			_check(id+".native_geometry_skin_texture_unchanged",arrays[Mesh.ARRAY_VERTEX]==initial_arrays[Mesh.ARRAY_VERTEX] and arrays[Mesh.ARRAY_BONES]==initial_arrays[Mesh.ARRAY_BONES] and arrays[Mesh.ARRAY_WEIGHTS]==initial_arrays[Mesh.ARRAY_WEIGHTS] and arrays[Mesh.ARRAY_TEX_UV]==initial_arrays[Mesh.ARRAY_TEX_UV] and actual.skin==initial_skin and wrapper._body_material.albedo_texture==body_texture and wrapper._body_material.normal_texture==body_normal)
			_check(id+".original_skin_head_hair_unchanged",actual.get_surface_override_material(1)==original_head and actual.get_surface_override_material(2)==original_hair and actual.get_surface_override_material(3)==original_hands and original_head.albedo_color==original_head_color and original_hands.albedo_color==original_hand_color)
			trials.append({"target":target,"readback":measured})
		torso.material_override.albedo_color=jacket;avatar._materials.trousers.albedo_color=pants;wrapper.sync_clothing()
		_check(id+".restore_exact_cached_default",actual.mesh==initial_mesh and wrapper._body_material.albedo_color==Color.WHITE and actual.skin==initial_skin and original_head.albedo_color==original_head_color and original_hands.albedo_color==original_hand_color)
		report.models.append({"id":id,"default":before,"selected_outfits":trials});actor.free()
	report["passed"]=report.checks.size()-failed;report["total"]=report.checks.size();report["failed"]=failed
	var output:="data/reports/human_presence/20261022/appearance/textured_palette_headless_dev01.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
	var path:=ProjectSettings.globalize_path("res://../"+output);var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(_plain(report),"  ")+"\n");file.close()
	print("TEXTURED_PALETTE ",report.passed,"/",report.total," failed=",failed);quit(0 if failed==0 else 1)
