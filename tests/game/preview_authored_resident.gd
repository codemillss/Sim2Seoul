extends SceneTree
const HUMAN_MATERIALS := preload("res://scripts/player/human_skin_materials.gd")
## Native static geometry views of the actual own GLBs. Dynamic animation,
## gameplay and subjective quality require the independent production tests.
var scene: Node3D
var camera: Camera3D
var source_sha256: Dictionary={}
var captures: Array[Dictionary]=[]
var report_path:="/private/tmp/authored_resident_preview.json"
var quick_body_preview:=false
var single_face_preview:=false
var candidate_root:=""

func _initialize() -> void:call_deferred("_run")

func _json(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2i:return [value.x,value.y]
	if value is Dictionary:
		var result:={}
		for key: Variant in value:result[key]=_json(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value:result.append(_json(item))
		return result
	return value

func _run() -> void:
	var args:=OS.get_cmdline_user_args()
	for argument: String in args:
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
		if argument=="--body-preview-quick":quick_body_preview=true
		if argument=="--single-face-preview":single_face_preview=true;quick_body_preview=true
		if argument.begins_with("--candidate-root="):candidate_root=argument.trim_prefix("--candidate-root=")
	for index: int in range(args.size()-1):
		if args[index]=="--report-path":report_path=args[index+1]
	var directory:=report_path.get_basename()+"_views"
	DirAccess.make_dir_recursive_absolute(directory)
	for path: String in ["res://../tests/game/preview_authored_resident.gd","res://../tools/authored_character/build_seoul_resident.py","res://../tools/authored_character/anatomical_surface_fields.py","res://scripts/player/human_skin_materials.gd","res://scripts/player/textured_human_surface.gd","res://assets/original/seoul_resident/AUTHORED_MANIFEST.json"]:source_sha256[path]=FileAccess.get_sha256(path)
	# Match the production 16:10 viewport aspect. The actual native texture
	# remains 16:10 even when a taller OS window is requested.
	root.size=Vector2i(960,600)
	scene=Node3D.new();root.add_child(scene)
	var env:=WorldEnvironment.new();var e:=Environment.new()
	e.background_mode=Environment.BG_COLOR;e.background_color=Color(.15,.17,.19)
	e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color(.78,.80,.84);e.ambient_light_energy=.55;e.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	env.environment=e;scene.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-28,-30,0);light.light_energy=1.2;scene.add_child(light)
	# Inspection-only rear fill keeps scapula/gluteal contours readable in
	# the back views. It does not change the game's environment lighting.
	var rear_fill:=DirectionalLight3D.new();rear_fill.rotation_degrees=Vector3(-22,145,0);rear_fill.light_energy=.50;rear_fill.light_color=Color(.86,.91,1.0);scene.add_child(rear_fill)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;scene.add_child(camera);camera.current=true
	var valid:=DisplayServer.get_name()!="headless"
	var expected_captures:=0
	var profiles: Array[String]=["standard","soft","athletic"]
	var dresses: Array=["swim"] if quick_body_preview else ["street","swim"]
	var angles: Array=["front","front_oblique","side","back","back_oblique","face","hands","pelvis"]
	if not candidate_root.is_empty():
		profiles=["standard"];dresses=["street"]
		angles=["front","face","face_side","face_left","face45","face_back"]
	var targeted: Dictionary={"m01_standard":["front","face","face_side","hands","hands_oblique","hands_back"],"f01_standard":["front","side","face","face_side"],"m01_soft":["side"],"m01_athletic":["front"]}
	if single_face_preview:targeted={"m01_standard":["face","face_side"]}
	for sex: String in ["m01","f01"]:
		for profile: String in profiles:
			for dress: String in dresses:
				var selected_angles: Array=targeted.get(sex+"_"+profile,[]) if quick_body_preview else angles
				if selected_angles.is_empty():continue
				expected_captures+=selected_angles.size()
				var asset:="res://assets/original/seoul_resident/seoul_resident_"+sex+("" if profile=="standard" else "_"+profile)+"_"+dress+".glb"
				if not candidate_root.is_empty():asset=candidate_root.path_join("seoul_resident_"+sex+"_street.glb")
				source_sha256[asset]=FileAccess.get_sha256(asset)
				var person: Node3D
				if candidate_root.is_empty():
					var packed: PackedScene=load(asset)
					if packed!=null:person=packed.instantiate()
				else:
					var document:=GLTFDocument.new();var state:=GLTFState.new()
					if document.append_from_file(asset,state)==OK:person=document.generate_scene(state)
				if person==null:valid=false;continue
				scene.add_child(person)
				var bone_names: Array[String]=[];var material_names: Array[String]=[];var mesh_names: Array[String]=[];var lod_counts: Array[int]=[];var cull_modes: Array[int]=[]
				for node: Node in person.find_children("*","Skeleton3D",true,false):
					for bone: int in range(node.get_bone_count()):bone_names.append(node.get_bone_name(bone))
				for node: Node in person.find_children("*","MeshInstance3D",true,false):
					mesh_names.append(node.mesh.resource_name)
					for surface: int in range(node.mesh.get_surface_count()):
						material_names.append(node.mesh.surface_get_material(surface).resource_name)
						cull_modes.append(node.mesh.surface_get_material(surface).cull_mode)
						var material: StandardMaterial3D=node.mesh.surface_get_material(surface).duplicate() as StandardMaterial3D
						var arrays: Array=node.mesh.surface_get_arrays(surface);var count_vertices: int=arrays[Mesh.ARRAY_VERTEX].size()
						var tangent_ready: bool=arrays[Mesh.ARRAY_NORMAL]!=null and arrays[Mesh.ARRAY_TEX_UV]!=null and arrays[Mesh.ARRAY_TANGENT]!=null and arrays[Mesh.ARRAY_NORMAL].size()==count_vertices and arrays[Mesh.ARRAY_TEX_UV].size()==count_vertices and arrays[Mesh.ARRAY_TANGENT].size()==count_vertices*4
						HUMAN_MATERIALS.apply_to(material,HUMAN_MATERIALS.role_from_name(material.resource_name),tangent_ready)
						node.set_surface_override_material(surface,material)
						var runtime_surface: Dictionary=RenderingServer.mesh_get_surface(node.mesh.get_rid(),surface)
						var count: int=runtime_surface.get("lods",[]).size()
						lod_counts.append(count);valid=valid and count==0
				for angle: String in selected_angles:
					var target:=Vector3(0,.85,0);camera.size=1.90;camera.position=Vector3(0,.85,3)
					match angle:
						"front_oblique":camera.position=Vector3(2.2,1.0,2.2)
						"side":camera.position=Vector3(3,.85,.3)
						"back":camera.position=Vector3(0,.85,-3)
						"back_oblique":camera.position=Vector3(-2.2,1.0,-2.2)
						"face":camera.size=.36;camera.position=Vector3(.13,1.57,3);target=Vector3(0,1.57,0)
						"face_side":camera.size=.36;camera.position=Vector3(3,1.57,.2);target=Vector3(0,1.57,0)
						"face_left":camera.size=.36;camera.position=Vector3(-3,1.57,.2);target=Vector3(0,1.57,0)
						"face45":camera.size=.36;camera.position=Vector3(2.1,1.57,2.1);target=Vector3(0,1.57,0)
						"face_back":camera.size=.36;camera.position=Vector3(0,1.57,-3);target=Vector3(0,1.57,0)
						"hands":camera.size=.30;camera.position=Vector3(.25,.80,3);target=Vector3(.25,.80,0)
						"hands_oblique":camera.size=.30;camera.position=Vector3(2,.80,2);target=Vector3(.25,.80,0)
						"hands_back":camera.size=.30;camera.position=Vector3(.25,.80,-3);target=Vector3(.25,.80,0)
						"pelvis":camera.size=.55;camera.position=Vector3(.7,.91,-3);target=Vector3(0,.91,0)
						"ankles":camera.size=.42;camera.position=Vector3(.8,.17,3);target=Vector3(0,.17,0)
					camera.look_at(target)
					for frame: int in range(8):await process_frame
					await RenderingServer.frame_post_draw
					var path:=directory.path_join(sex+"_"+profile+"_"+dress+"_"+angle+".png")
					var image:=root.get_texture().get_image();var error:=image.save_png(path)
					valid=valid and error==OK and image.get_size()==Vector2i(960,600) and bone_names.size()==52
					captures.append({"path":path,"sha256":FileAccess.get_sha256(path),"size_px":image.get_size(),"sex_variant":sex,"wardrobe":dress,"body_profile":profile,"view":angle,"actual_glb":asset,"actual_glb_sha256":source_sha256[asset],"selected_model_id":"SeoulResident_F01" if sex=="f01" else "SeoulResident_M01","actual_mesh_resource_names":mesh_names,"actual_bone_names":bone_names,"actual_material_names":material_names,"actual_surface_lod_counts":lod_counts,"actual_surface_cull_modes":cull_modes,"lod_observation_api":"RenderingServer.mesh_get_surface(...).lods","scope":"Static actual authored GLB, native renderer. No animation quality claim."})
				person.queue_free();await process_frame
	for path: String in source_sha256:valid=valid and FileAccess.get_sha256(path)==source_sha256[path]
	valid=valid and captures.size()==expected_captures
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(_json({"task":"EXP33_AUTHORED_RESIDENT_NATIVE_STATIC_VIEWS","result":"PASS" if valid else "FAIL","engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"source_sha256":source_sha256,"captures":captures,"inspection_lighting":{"key_energy":1.2,"key_rotation_degrees":[-28,-30,0],"rear_fill_energy":.50,"rear_fill_rotation_degrees":[-22,145,0],"ambient_energy":.55,"scope":"Static geometry inspection studio only; not gameplay lighting."},"summary":{"captures":captures.size(),"expected_captures":expected_captures},"scope":"Capture completeness, source integrity and actual own GLB skeleton/material identity only. A person must inspect pixels; animation, game input, comfort and performance are separate."}),"  ")+"\n")
	file.close();print("AUTHORED_RESIDENT_PREVIEW ",captures.size(),"/",expected_captures," ","PASS" if valid else "FAIL");quit(0 if valid else 1)
