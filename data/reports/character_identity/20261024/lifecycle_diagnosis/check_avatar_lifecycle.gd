extends SceneTree
## Focused actual production avatar lifetime evidence. No source or input changes.
const AVATAR := preload("res://scripts/player/exploration_avatar.gd")
var report_path:="/private/tmp/sim2seoul-avatar-lifecycle.json"
var engine_log:=""
var checks: Array[Dictionary]=[]
var hashes: Dictionary={}
var finished:=false
var world: Node3D

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
		if argument.begins_with("--engine-log="):engine_log=argument.trim_prefix("--engine-log=")
	create_timer(90.,true,false,true).timeout.connect(func()->void:
		if not finished:_check("bounded_lifecycle_timeout",false);_finish()
	)
	_run.call_deferred()

func _check(title: String,passed: bool,evidence: Dictionary={}) -> void:
	checks.append({"name":title,"passed":passed,"evidence":evidence})
	print("LIFECYCLE_CHECK ",title," ",passed," ",JSON.stringify(evidence))

func _source_hashes() -> Dictionary:
	var result: Dictionary={}
	for path: String in ["res://scenes/player/player.tscn","res://scripts/player/idle_support.gd","res://scripts/player/exploration_avatar.gd","res://scripts/player/textured_human_surface.gd","res://scripts/player/textured_human_rig.gd","res://scripts/player/human_skin_materials.gd",get_script().resource_path]:result[path]=FileAccess.get_sha256(path)
	return result

func _nodes_under(node: Node) -> Array[int]:
	var result: Array[int]=[node.get_instance_id()]
	for child: Node in node.find_children("*","Node",true,false):result.append(child.get_instance_id())
	return result

func _all_gone(ids: Array[int]) -> bool:
	return ids.all(func(id: int)->bool:return not is_instance_id_valid(id))

func _idle() -> void:
	# Two process boundaries include a completed deferred-message idle flush.
	await process_frame;await process_frame

func _run() -> void:
	hashes=_source_hashes()
	world=Node3D.new();world.name="AvatarLifecycleEvidence";root.add_child(world)
	var player: CharacterBody3D=load("res://scenes/player/player.tscn").instantiate()
	player.set_meta("human_model_id","SeoulResident_M01");world.add_child(player);player.set_physics_process(false)
	var collision: CollisionShape3D=player.get_node("CollisionShape")
	var body: MeshInstance3D=player.get_node("Visual/Body")
	var visual: Node3D=player.get_node("Visual")
	var capsule: CapsuleShape3D=collision.shape
	var shape_id:=capsule.get_instance_id();var collision_id:=collision.get_instance_id()
	var body_id:=body.get_instance_id();var original_mesh: Mesh=body.mesh
	var original_material: Material=body.mesh.surface_get_material(0);var original_visible:=body.visible
	_check("retained_production_player_scene_and_capsule_are_loaded",body.is_inside_tree() and original_visible and original_material!=null and is_equal_approx(capsule.radius,.30) and is_equal_approx(capsule.height,1.70),{"body_id":body_id,"capsule_id":shape_id,"radius_m":capsule.radius,"height_m":capsule.height,"player_scene":"res://scenes/player/player.tscn"})
	var avatar: Node3D=AVATAR.new();var accepted: bool=avatar.setup(player)
	avatar.set_physics_process(false)
	_check("actual_production_avatar_hides_body_and_loads_native_skeleton",accepted and avatar._textured_surface.loaded and avatar._textured_surface.skeleton.get_bone_count()==52 and not body.visible and collision.shape.get_instance_id()==shape_id,{"accepted":accepted,"native_bones":avatar._textured_surface.skeleton.get_bone_count() if accepted else 0,"body_visible":body.visible})
	if not accepted:_finish();return
	var holder:=Node3D.new();holder.name="SamePlayerPresentationParent";player.add_child(holder)
	avatar.reparent(holder,false)
	await _idle()
	_check("live_avatar_reparent_keeps_original_fallback_hidden_after_idle",is_instance_valid(avatar) and avatar.is_inside_tree() and avatar.get_parent()==holder and not body.visible and avatar._textured_surface.loaded and collision.shape.get_instance_id()==shape_id,{"avatar_parent":String(avatar.get_parent().get_path()),"fallback_visible":body.visible,"native_surface_loaded":avatar._textured_surface.loaded})
	avatar.reparent(visual,false);await _idle()
	var avatar_ids: Array[int]=_nodes_under(avatar)
	avatar.free()
	_check("avatar_only_free_keeps_surviving_body_hidden_during_teardown",_all_gone(avatar_ids) and is_instance_valid(body) and body.is_inside_tree() and not body.visible and is_instance_valid(player),{"deleted_owned_nodes":avatar_ids.size(),"fallback_visible_before_idle":body.visible,"body_still_inside_tree":body.is_inside_tree()})
	await _idle()
	_check("next_idle_restores_original_body_mesh_material_and_capsule",body.visible==original_visible and body.get_instance_id()==body_id and body.mesh==original_mesh and body.mesh.surface_get_material(0)==original_material and collision.get_instance_id()==collision_id and collision.shape.get_instance_id()==shape_id and is_equal_approx(capsule.radius,.30) and is_equal_approx(capsule.height,1.70),{"fallback_visible_after_idle":body.visible,"body_id":body.get_instance_id(),"capsule_id":collision.shape.get_instance_id()})
	var replacement: Node3D=AVATAR.new();var reattached: bool=replacement.setup(player)
	replacement.set_physics_process(false)
	_check("reattached_production_avatar_uses_same_player_and_capsule",reattached and replacement.player==player and replacement._textured_surface.loaded and not body.visible and collision.shape.get_instance_id()==shape_id,{"reattached":reattached,"same_capsule":collision.shape.get_instance_id()==shape_id,"fallback_hidden":not body.visible})
	var whole_ids: Array[int]=_nodes_under(player)
	player.free();await _idle()
	_check("whole_production_player_free_removes_all_owned_nodes",_all_gone(whole_ids) and world.get_child_count()==0,{"deleted_owned_nodes":whole_ids.size(),"remaining_world_children":world.get_child_count()})
	# Preserve the original renderer04 reproducer as well: its host used a
	# CapsuleMesh with no material, unlike the authored production player scene.
	var bare:=CharacterBody3D.new();bare.name="BareCapsuleRendererReproducer";bare.set_meta("human_model_id","SeoulResident_F01")
	var bare_collision:=CollisionShape3D.new();bare_collision.name="CollisionShape";var bare_shape:=CapsuleShape3D.new();bare_shape.radius=.30;bare_shape.height=1.70;bare_collision.shape=bare_shape;bare.add_child(bare_collision)
	var bare_visual:=Node3D.new();bare_visual.name="Visual";bare.add_child(bare_visual)
	var bare_body:=MeshInstance3D.new();bare_body.name="Body";bare_body.mesh=CapsuleMesh.new();bare_visual.add_child(bare_body);world.add_child(bare)
	var bare_avatar: Node3D=AVATAR.new();var bare_ok: bool=bare_avatar.setup(bare);bare_avatar.set_physics_process(false)
	var bare_hidden:=not bare_body.visible;var material_was_null:=bare_body.mesh.surface_get_material(0)==null
	var bare_bones: int=bare_avatar._textured_surface.skeleton.get_bone_count() if bare_ok else 0
	var bare_ids: Array[int]=_nodes_under(bare)
	bare.free();await _idle()
	_check("unmaterialized_capsule_reproducer_whole_free_is_safe",bare_ok and bare_bones==52 and bare_hidden and material_was_null and _all_gone(bare_ids) and world.get_child_count()==0,{"production_avatar_loaded":bare_ok,"native_bones":bare_bones,"original_capsule_material_was_null":material_was_null,"deleted_owned_nodes":bare_ids.size(),"remaining_world_children":world.get_child_count()})
	world.free();world=null;await _idle()
	var pattern:=RegEx.new();pattern.compile("(?m)^(?:ERROR:|SCRIPT ERROR:|USER ERROR:)")
	var log_exists:=not engine_log.is_empty() and FileAccess.file_exists(engine_log)
	var error_count: int=pattern.search_all(FileAccess.get_file_as_string(engine_log)).size() if log_exists else -1
	_check("all_lifecycle_cases_have_no_engine_errors_and_sources_stay_frozen",log_exists and error_count==0 and _source_hashes()==hashes and not hashes.values().has(""),{"engine_log":engine_log,"engine_error_count_at_completed_teardown":error_count,"source_hashes_unchanged":_source_hashes()==hashes})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true
	var passed: int=checks.filter(func(row: Dictionary)->bool:return row.passed).size()
	var result: Dictionary={"task":"EXP34_AVATAR_LIFECYCLE","result":"PASS" if passed==9 and checks.size()==9 else "FAIL","passed":passed,"total":checks.size(),"expected_checks":9,"checks":checks,"engine":Engine.get_version_info().string,"display":DisplayServer.get_name(),"source_before":hashes,"source_after":_source_hashes(),"engine_log":engine_log,"scope":"Actual production avatar/resources on retained production player scene plus original bare-CapsuleMesh renderer reproducer. Lifecycle/ownership evidence only;headless run is not native gameplay acceptance. No source/input/renderer state is modified by the fixture."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify(result,"  ")+"\n");file.close()
	print("LIFECYCLE_RESULT ",passed,"/",checks.size()," ",result.result)
	quit(0 if result.result=="PASS" else 1)
