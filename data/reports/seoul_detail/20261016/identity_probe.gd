extends SceneTree
func _initialize() -> void:
 run.call_deferred()
func run() -> void:
 var scene = load("res://scenes/world/city_landmarks.tscn").instantiate()
 root.add_child(scene)
 var bodies_before := _body_snapshot(scene)
 var original_wall_mesh: Mesh = scene.city.fragments.W01_palace_wall.get_parent().mesh
 var helper = load("res://scripts/seoul_identity.gd").new()
 scene.add_child(helper)
 var before := Time.get_ticks_msec()
 var ok: bool = helper.setup(scene.city, scene)
 print("IDENTITY_PROBE ",JSON.stringify({"ok":ok,"error":helper.load_error,"elapsed_ms":Time.get_ticks_msec()-before,"wall_count":helper.wall_count,"landmark_count":helper.landmark_count,"detail_mesh_count":helper.detail_mesh_count,"ornament_count":helper.ornament_count,"material_count":helper.material_count,"overlap":helper.overlap_report,"collision_unchanged":bodies_before==_body_snapshot(scene),"original_wall_resource_kept":original_wall_mesh.get_surface_count()==1}))
 await process_frame
 scene.queue_free()
 quit(0 if ok and bodies_before==_body_snapshot(scene) else 1)
func _body_snapshot(node: Node) -> Dictionary:
 var snapshot := {}
 for child in node.find_children("*", "CollisionObject3D", true, false):
  snapshot[str(child.get_instance_id())] = [child.collision_layer,child.collision_mask]
 for child in node.find_children("*", "CollisionShape3D", true, false):
  snapshot[str(child.get_instance_id())] = [child.shape.get_instance_id(),child.disabled]
 return snapshot
