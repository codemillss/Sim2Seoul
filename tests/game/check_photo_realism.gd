extends "check_seoul_detail.gd"
## The existing actual-city physics/GPU probe plus the new display layer.
func _appearance_checks() -> void:
	super._appearance_checks()
	var civic=scene.photo_civic_detail
	_check("photo.civic_geometry",civic.loaded and civic.window_count==200 and civic.lattice_segment_count==741 and civic.triangle_count==33024,{"windows":civic.window_count,"diagrid_segments":civic.lattice_segment_count,"triangles":civic.triangle_count,"meshes":civic.detail_mesh_count})
	var palace=scene.photo_palace_detail
	_check("photo.palace_geometry",palace.loaded and palace.hidden_window_count>0 and palace.ornament_count>100 and palace.label_count>0,{"landmarks":palace.landmark_count,"meshes":palace.mesh_count,"ornaments":palace.ornament_count,"hidden_gate_windows":palace.hidden_window_count,"labels":palace.label_count})
	_check("photo.wall_tile_ends",scene.photo_wall_detail.loaded and scene.photo_wall_detail.tile_end_count>500,{"tile_ends":scene.photo_wall_detail.tile_end_count})
	var stone: ShaderMaterial=scene.seoul_identity._materials.stone_wall
	var texture: Texture2D=stone.get_shader_parameter("granite_albedo")
	_check("photo.granite_texture",texture!=null and texture.get_width()>=1024 and texture.get_height()>=1024,{"path":texture.resource_path if texture!=null else "","width":texture.get_width() if texture!=null else 0,"height":texture.get_height() if texture!=null else 0})
	_check("photo.daylight_environment",scene.photo_atmosphere.loaded and scene.photo_atmosphere.environment.background_mode==Environment.BG_SKY,{"ground_surfaces":scene.photo_atmosphere.ground_count,"materials":scene.photo_atmosphere.material_count})
	_check("photo.library_portal_ready",scene.interior_visit.loaded and not scene.interior_visit.active,scene.interior_visit.snapshot())

func _quality_cases() -> void:
	await super._quality_cases()
	for id in ["low","standard"]:
		scene.apply_quality(id)
		_check("photo.quality_"+id,scene.photo_atmosphere.environment.ssao_enabled==(id=="standard") and scene.rig.camera.far==1400.0,{"ssao":scene.photo_atmosphere.environment.ssao_enabled,"far":scene.rig.camera.far})

func _capture(title: String, eye: Vector3, target: Vector3) -> void:
	await super._capture(title,eye,target)
	if title=="gate_front":
		await super._capture("gate_close",Vector3(43,3.6,14),Vector3(26,4,8))
	elif title=="city_hall_library":
		var entry: Vector3=scene.photo_civic_detail.entrance_world_position
		var outward: Vector3=scene.photo_civic_detail.entrance_outward_direction
		await super._capture("library_entrance",entry+outward*13.0+Vector3.UP*3.2,scene.photo_civic_detail.door_world_position+Vector3.UP*1.5)
