extends SceneTree
## Exercises the same standalone review scene used by a person. A numerical
## PASS means scene/pose/capture integrity; form quality requires pixel review.
const SCENE := preload("res://scenes/study/resident_form_study.tscn")
var study: Node3D
var checks: Array = []
var captures: Array = []
var pose_observations: Array = []
var source_before: Dictionary = {}
var report_path := "/private/tmp/resident_form_refinement.json"
var native := false

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
	_run.call_deferred()

func _check(title: String, passed: bool, evidence: Dictionary = {}) -> void:
	checks.append({"name":title, "passed":passed, "evidence":evidence})
	print("FORM_REFINEMENT ", title, " ", passed)

func _json(value: Variant) -> Variant:
	if value is Vector3: return [value.x, value.y, value.z]
	if value is Vector2i: return [value.x, value.y]
	if value is Vector2: return [value.x, value.y]
	if value is Color: return [value.r, value.g, value.b, value.a]
	if value is Basis: return [_json(value.x), _json(value.y), _json(value.z)]
	if value is Transform3D: return {"origin":_json(value.origin), "basis":_json(value.basis)}
	if value is AABB: return {"position":_json(value.position), "size":_json(value.size)}
	if value is Rect2: return {"position":_json(value.position), "size":_json(value.size)}
	if value is Dictionary:
		var result := {}
		for key: Variant in value: result[str(key)] = _json(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry: Variant in value: result.append(_json(entry))
		return result
	if value is PackedStringArray: return Array(value)
	return value

func _hashes() -> Dictionary:
	var result := {}
	for path: String in ["res://scripts/study/resident_form_study.gd", "res://scenes/study/resident_form_study.tscn", "res://../tests/game/check_resident_form_study.gd", "res://scripts/player/exploration_avatar.gd", "res://scripts/player/textured_human_surface.gd", "res://scripts/player/textured_human_rig.gd", "res://assets/original/resident_study/resident_form_m01.glb", "res://assets/original/resident_study/resident_form_m01_previous.glb", "res://assets/original/resident_study/FORM_STUDY_MANIFEST.json", "res://assets/original/resident_study/FORM_STUDY_PREVIOUS_MANIFEST.json"]:
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	for name_: String in DirAccess.get_files_at("res://assets/original/resident_study"):
		if name_.get_extension() in ["json", "blend"]:
			var path := "res://assets/original/resident_study/"+name_
			result[path] = FileAccess.get_sha256(path)
	# Authoring data lives outside game/ to avoid Godot's automatic .blend
	# conversion. Bind the actual editable source when available; the exported
	# GLB and its accompanying manifest remain the gallery's runtime inputs.
	var authoring_path := "res://../art/characters/resident_form_m01.blend"
	if FileAccess.file_exists(authoring_path): result[authoring_path] = FileAccess.get_sha256(authoring_path)
	return result

func _settle() -> void:
	for tick: int in range(3): await process_frame
	study.publish_skin_state()
	if native:
		RenderingServer.force_draw(false)
		await RenderingServer.frame_post_draw

func _pose_criterion(row: Dictionary) -> bool:
	var joints: Dictionary = row.joints
	for key: String in ["head", "pelvis", "upper_arm.L", "upper_arm.R", "hand.L", "hand.R", "foot.L", "foot.R", "shin.L", "shin.R"]:
		if not joints.has(key): return false
	match String(row.pose):
		"a_pose":
			return joints.head.y > joints.pelvis.y+.40 and joints["hand.L"].y < joints["upper_arm.L"].y-.15 and joints["hand.R"].y < joints["upper_arm.R"].y-.15
		"arm_raise":
			return joints["hand.L"].y > joints["upper_arm.L"].y+.20 and joints["hand.R"].y > joints["upper_arm.R"].y+.20
		"deep_squat":
			var rest_pelvis: Vector3 = Vector3.ZERO
			for bone: Dictionary in row.bones:
				if bone.name == "pelvis":
					var index: int = study.skeleton.find_bone(bone.name)
					rest_pelvis = study._rest_world[index].origin
			return joints.pelvis.y < rest_pelvis.y-.22 and joints["shin.L"].z > joints["foot.L"].z+.05 and joints["shin.R"].z > joints["foot.R"].z+.05
		"single_support":
			# The authored v03 hold lifts the swing sole/ankle by ~14 cm.
			# Require a distinct lifted foot, not an unrelated 15 cm pose target.
			return absf(joints["foot.L"].y-joints["foot.R"].y) > .10
	return false

func _corrective_criterion(row: Dictionary) -> bool:
	var observed := {}
	for shape: Dictionary in row.blend_shapes: observed[String(shape.name)] = float(shape.value)
	var expected: Array = study.CORRECTIVES[row.pose]
	for index: int in range(study.CORRECTIVE_NAMES.size()):
		var title: String = study.CORRECTIVE_NAMES[index]
		if not observed.has(title) or absf(float(observed[title])-float(expected[index])) > .0001: return false
	return true

func _manifest_criterion(row: Dictionary) -> bool:
	var declared: Dictionary = row.manifest_contract
	if row.manifest_sha256.is_empty() or source_before.get(row.manifest_path, "") != row.manifest_sha256: return false
	if declared.declared_asset_sha256 != row.asset_sha256: return false
	if int(declared.bone_count) != study.NEW_BONES.size() or declared.bone_names.size() != study.NEW_BONES.size(): return false
	for title: String in study.NEW_BONES:
		if title not in declared.bone_names: return false
	if declared.nla_track_names.size() != study.POSES.size(): return false
	var native_clips: Array = []
	for title: String in row.imported_animation_names: native_clips.append(title.get_file())
	for title: String in study.POSES:
		if title not in declared.nla_track_names or title not in native_clips: return false
	if declared.corrective_names.size() != study.CORRECTIVE_NAMES.size(): return false
	for title: String in study.CORRECTIVE_NAMES:
		if title not in declared.corrective_names: return false
	return int(declared.declared_export_vertices) > 0 and int(declared.declared_export_faces) > 0

func _rest_anchor_observations() -> Dictionary:
	var rig: Dictionary = study._manifest.get("rig", {})
	var anchors: Array = []
	var maximum := 0.
	var valid: bool = rig.get("bones", []).size() == study.NEW_BONES.size()
	for bone: Dictionary in rig.get("bones", []):
		var index: int = study.skeleton.find_bone(String(bone.get("name", "")))
		var source: Array = bone.get("head_m", [])
		if index < 0 or source.size() != 3:
			valid = false
			continue
		var expected := Vector3(float(source[0]), float(source[2]), -float(source[1]))
		var actual: Vector3 = study._rest_world[index].origin
		var error := actual.distance_to(expected)
		maximum = maxf(maximum, error)
		anchors.append({"bone":bone.name, "declared_blender_head_m":source, "expected_godot_m":expected, "actual_imported_rest_m":actual, "error_m":error})
	return {"valid":valid, "maximum_error_m":maximum, "anchors":anchors, "scope":"Actual imported rest heads versus each source manifest in metres, Blender(x,y,z)→Godot(x,z,-y). This is not anatomy accuracy."}

func _capture(model: String, pose: String, view: String) -> void:
	study.set_view(view); await _settle()
	var palette: Dictionary = study.publish_skin_state()
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	var path := report_path.get_basename()+"_"+model+"_"+pose+"_"+view+".png"
	var code := image.save_png(path)
	var row: Dictionary = study.snapshot()
	captures.append({"file":path, "sha256":FileAccess.get_sha256(path) if code == OK else "", "image_size":image.get_size(), "save_error":code, "model":model, "pose":pose, "view":view, "actual_glb_path":row.asset_path, "actual_glb_sha256":row.asset_sha256, "actual_manifest_path":row.manifest_path, "actual_manifest_sha256":row.manifest_sha256, "actual_animation":row.actual_animation, "sample_time_s":row.sample_time_s, "camera":row.camera_transform, "camera_fov":row.camera_fov, "shared_pose_framing":row.shared_pose_framing, "projected_frame":row.projected_frame, "lighting":row.fixed_key_transform, "palette":palette, "actual_visible_meshes":row.visible_mesh_count, "readback":"same production study scene controls, actual GPU viewport; fixed world lighting/lens and common per-pose framing, no image retouch", "scope":"Capture and skeleton publication integrity only; no form/realism/art acceptance."})
	_check(model+"."+pose+"."+view+".actual_native_capture_visible_uncropped_and_palette_published", code == OK and not image.is_empty() and row.visible_mesh_count > 0 and palette.valid and row.projected_frame.inside_unobscured_frame)

func _click(key: String) -> void:
	var rectangles: Dictionary = study.control_rects()
	var rect: Rect2 = rectangles[key]
	var motion := InputEventMouseMotion.new(); motion.position = rect.get_center(); motion.global_position = motion.position; motion.window_id = root.get_window_id(); Input.parse_input_event(motion)
	var down := InputEventMouseButton.new(); down.position = rect.get_center(); down.global_position = down.position; down.button_index = MOUSE_BUTTON_LEFT; down.pressed = true; down.window_id = root.get_window_id(); Input.parse_input_event(down)
	var up := InputEventMouseButton.new(); up.position = down.position; up.global_position = up.position; up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false; up.window_id = root.get_window_id(); Input.parse_input_event(up)
	await _settle()

func _run() -> void:
	native = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	source_before = _hashes()
	root.size = Vector2i(1152, 720)
	paused = true # Same entry state as the real exploration menu.
	study = SCENE.instantiate(); root.add_child(study); study.set_review_mode(true)
	await _settle()
	_check("default_is_new_original_in_separate_scene", study.selected_model == "new" and study.get_parent() == root and study.review_mode and not study.automatic and not paused, {"entered_from_paused_menu":true,"tree_paused_after_ready":paused})
	_check("all_exact_inputs_exist_and_are_hashed", not source_before.values().has(""), {"source_sha256":source_before})
	for model: String in ["new", "previous"]:
		var loaded: bool = study.select_model(model); await _settle()
		if loaded:
			study.apply_pose("a_pose")
			await _settle()
		var row: Dictionary = study.snapshot()
		_check(model+".actual_requested_native_asset_loaded", loaded and row.loaded and row.asset_path == study.SOURCES[model] and row.asset_sha256 == source_before[row.asset_path], {"snapshot":row})
		if not loaded: continue
		_check(model+".source_manifest_binds_actual_asset_native_clips_bones_and_morphs", _manifest_criterion(row), {"manifest_path":row.manifest_path, "manifest_sha256":row.manifest_sha256, "declared_contract":row.manifest_contract, "actual_glb_sha256":row.asset_sha256})
		var names: Array = row.bones.map(func(bone: Dictionary) -> String: return bone.name)
		var bone_contract: bool = names.size() == study.NEW_BONES.size()
		for name_: String in study.NEW_BONES: bone_contract = bone_contract and name_ in names
		_check(model+".actual_imported_bone_contract", bone_contract, {"names":names})
		var bounds: AABB = row.rest_mesh_aabb_world
		var anchors := _rest_anchor_observations()
		_check(model+".source_metres_preserved_without_rescaling", row.model_anchor_transform == Transform3D.IDENTITY and bounds.size.y > 1.75 and bounds.size.y < 1.81 and absf(bounds.position.y) < .015 and anchors.valid and anchors.maximum_error_m < .002, {"rest_mesh_aabb":bounds, "source_rest_anchor_observations":anchors})
		_check(model+".real_visible_mesh_uses_same_untextured_clay", row.visible_mesh_count == row.actual_mesh_count and row.visible_mesh_count > 0 and row.same_clay_material and not study.clay.vertex_color_use_as_albedo and study.clay.albedo_texture == null and study.clay.normal_texture == null and is_equal_approx(study.clay.roughness, .72), {"actual_clay":row.clay_properties, "visible_meshes":row.visible_mesh_count, "all_meshes":row.actual_mesh_count, "same_instance_material":row.same_clay_material})
		_check(model+".all_four_native_pose_controls_enabled", row.enabled_pose_controls.size() == study.POSES.size())
		for pose: String in study.POSES:
			var applied: bool = study.apply_pose(pose); await _settle(); row = study.snapshot()
			pose_observations.append(row)
			_check(model+"."+pose+".actual_pose_loaded_with_disclosed_strategy", applied and row.pose_application_ok and (not row.actual_animation.is_empty() and row.pose_strategy == "actual_imported_NLA_animation_and_corrective_morph"), {"actual_animation":row.actual_animation, "strategy":row.pose_strategy, "blend_shapes":row.blend_shapes})
			_check(model+"."+pose+".actual_native_bone_transforms_finite", row.finite_bones)
			_check(model+"."+pose+".long_bone_lengths_preserved", row.long_bone_links.size() == 8 and row.long_bone_links.all(func(link: Dictionary) -> bool: return link.error_m < .0002), {"actual_links":row.long_bone_links})
			_check(model+"."+pose+".measured_pose_has_requested_joint_motion", _pose_criterion(row), {"joints":row.joints})
			_check(model+"."+pose+".source_materials_shared_pose_camera_light_and_reference_unchanged", row.source_materials_unchanged and is_equal_approx(row.camera_fov, 32.) and absf(row.camera_distance_m-float(study.FRAMING[pose].distance)) < .0001 and row.fixed_key_shadow and row.ruler_size_m == Vector3(.012, 1., .012))
			_check(model+"."+pose+".corrective_morph_values_match_authored_hold_contract", _corrective_criterion(row), {"actual_shapes":row.blend_shapes})
			_check(model+"."+pose+".actual_morphed_skinned_body_fits_unobscured_frame", row.projected_frame.inside_unobscured_frame, {"actual_projection":row.projected_frame})
			if native:
				for view: String in ["front", "right", "back", "oblique"]: await _capture(model, pose, view)
		if native and model == "previous":
			await _click("pose_arm_raise")
			_check("previous.native_injected_mouse_replays_actual_frozen_native_pose", study.selected_model == "previous" and study.selected_pose == "arm_raise" and _pose_criterion(study.snapshot()) and _corrective_criterion(study.snapshot()))
		study.apply_pose("a_pose"); await _settle()
		_check(model+".pose_can_return_to_base", study.selected_pose == "a_pose" and _pose_criterion(study.snapshot()))
	if native and study.loaded:
		await _click("model_new"); _check("native_injected_mouse_selects_new_model", study.selected_model == "new" and study.loaded)
		await _click("view_right"); _check("native_injected_mouse_changes_view", study.selected_view == "right")
		await _click("pose_arm_raise"); _check("native_injected_mouse_changes_actual_bone_pose", study.selected_pose == "arm_raise" and _pose_criterion(study.snapshot()))
	_check("all_input_and_production_source_bytes_unchanged", _hashes() == source_before)
	var failed: int = checks.filter(func(row: Dictionary) -> bool: return not row.passed).size()
	var report := {"task":"EXP36_RESIDENT_FORM_REFINEMENT", "result":"PASS" if failed == 0 else "FAIL", "engine":Engine.get_version_info().string, "display":DisplayServer.get_name(), "physics_hz":Engine.physics_ticks_per_second, "summary":{"checks":checks.size(), "failed":failed, "captures":captures.size()}, "checks":checks, "pose_observations":pose_observations, "captures":captures, "source_sha256":source_before, "source_after":_hashes(), "visual_acceptance":"PENDING actual clay form and deformation pixel review", "scope":"Same separate study scene as interactive gallery. Actual imported bones/animation/morph weights and visible clay/camera/light inputs are inspected. The previous model is frozen v04 and both models use their own actual native NLA/morphs under identical per-pose framing, light and gray material. No old52 retargeting is used. Headless cannot establish rendered shape quality. Native images and sparse pose holds are not continuous animation, surveyed anatomy, realistic skin, new production avatar or user art acceptance."}
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null: push_error("Cannot save form study report"); quit(2); return
	file.store_string(JSON.stringify(_json(report), "  ")+"\n"); file.close()
	print("RESIDENT_FORM_REFINEMENT_RESULT ", checks.size()-failed, "/", checks.size(), " captures=", captures.size())
	study.queue_free(); await process_frame; await process_frame
	quit(0 if failed == 0 else 1)
