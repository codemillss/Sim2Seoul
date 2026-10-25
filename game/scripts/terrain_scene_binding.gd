extends RefCounted
## One synchronous, exploration-only rebase. Historical milestone inputs remain flat.
var host: Node3D
var terrain: Node3D
var warp: RefCounted
var records: Array=[]
var rigid_nodes := 0
var seen: Dictionary={}
var skipped: Dictionary={}

func _record(node: Node,result: Dictionary) -> void:
	result["node"]=String(node.get_path());records.append(result)
	if records.size()%100==0:print("EXP21_PROJECTING operations=",records.size()," node=",node.name)

func _disable(node: Node) -> void:
	if node is CollisionObject3D:node.collision_layer=0;node.collision_mask=0
	if node is Node3D:node.visible=false
	for child in node.get_children():_disable(child)

func _rigid(node: Node3D,height: float) -> void:
	if is_finite(height):node.global_position.y+=height;rigid_nodes+=1

func _visit(node: Node) -> void:
	if seen.has(node) or skipped.has(node):return
	seen[node]=true
	if node is CharacterBody3D or node is Camera3D or node is Control:return
	if node is Node3D:
		var id:=String(node.get_meta("geometry_id",node.get_meta("feature_id",node.get_meta("source_feature_id",""))))
		var base: float=terrain.building_base_y_world(id)
		if is_finite(base):
			_rigid(node,base)
			if node is MeshInstance3D:
				if OS.has_feature("web") and node.get_meta("web_facade_uniforms",false) and node.material_override is ShaderMaterial:
					var material:=node.material_override as ShaderMaterial
					var limits:Variant=material.get_shader_parameter("height_limits_m")
					if limits is Vector2:material.set_shader_parameter("height_limits_m",limits+Vector2(base,base))
				else:
					var limits: Variant=node.get_instance_shader_parameter("height_limits_m")
					if limits is Vector2:node.set_instance_shader_parameter("height_limits_m",limits+Vector2(base,base))
			return
		if node.get_meta("authored_game_placement",false):
			_rigid(node,terrain.ground_y_world(node.global_position));return
	if node is MeshInstance3D:
		if node.mesh is PrimitiveMesh:
			var point: Vector3=node.to_global(node.mesh.get_aabb().get_center())
			_rigid(node,terrain.ground_y_world(point))
		else:_record(node,warp.warp_mesh(node))
	elif node is MultiMeshInstance3D:_record(node,warp.warp_multimesh(node))
	elif node is CollisionShape3D:_record(node,warp.warp_shape(node))
	elif node is Label3D or node is AudioStreamPlayer3D or node is OmniLight3D:
		_rigid(node,terrain.ground_y_world(node.global_position))
	for child in node.get_children():_visit(child)

func apply(root_scene: Node3D,surface: Node3D) -> bool:
	host=root_scene;terrain=surface
	if not terrain.data_ready or terrain.loaded:return false
	warp=preload("res://scripts/terrain_geometry_warp.gd").new();warp.configure(terrain,host.city)
	# Flat temporary supports and the former invented3m hill are replaced.
	var temporary: MeshInstance3D=host.city.source_nodes.get("temporary_support")
	if is_instance_valid(temporary):_disable(temporary);skipped[temporary]=true
	if is_instance_valid(host.exploration_overlay.support):_disable(host.exploration_overlay.support);skipped[host.exploration_overlay.support]=true
	# The same support handle remains valid for free-roam toggles and NPC masks.
	host.exploration_overlay.support=terrain.support
	host.museum_approach.adopt_terrain(terrain)
	for node: Variant in [terrain,host.player,host.rig,host.interior_visit,host.exploration_rooftop_access,host.neighborhood_greenery,host.neighborhood_population,host.street_pedestrians,host.exploration_pedestrians,host.exploration_traffic,host.museum_approach]:
		if is_instance_valid(node):skipped[node]=true
	# Bird animation owns local head/wing transforms. Move only its root/anchor,
	# otherwise visiting primitive children would add the terrain twice.
	for bird: Dictionary in host.street_life.birds:
		skipped[bird.actor]=true
		bird["flat_source_anchor"]=bird.anchor
	# Source gate fragments and the visible replacement share one level foundation.
	var gate_base: float=terrain.building_base_y_world("osm:way:377289797:building")
	for id: String in host.city.fragments:
		if id.begins_with("W01_gate_"):
			var node: Node3D=host.city.fragments[id].get_parent();_rigid(node,gate_base);skipped[node]=true
	# Actor-owned trees/lanes refresh themselves. Existing lane supports still
	# belong to the original Traffic subtree, so traverse that subtree normally.
	for child in host.get_children():
		print("EXP21_BINDING branch=",child.name)
		_visit(child)
	# Extra coverage supports live under an excluded manager; they are geometry,
	# not actors, and need the same exact terrain-triangle cuts.
	for support: StaticBody3D in host.neighborhood_population.traffic.supports:
		for child in support.get_children():_visit(child)
	for row: Dictionary in host.building_names.markers:
		row.point=row.node.global_position
	for id: String in host.building_names.records:
		var base: float=terrain.building_base_y_world(id)
		if is_finite(base):host.building_names.records[id].top+=base
	for bird: Dictionary in host.street_life.birds:
		var delta: float=terrain.ground_y_world(bird.anchor)
		if is_finite(delta):bird.anchor+=Vector3.UP*delta;bird.actor.global_position=bird.anchor
	# Loaded becomes visible to dynamic queries only after every static shape is
	# projected. No physics frame advances through the mixed-height state.
	terrain.loaded=true
	if not host.interior_visit.apply_terrain_elevation():return false
	if not host.player.bind_terrain_surface(terrain):return false
	var rise: float=terrain.ground_y_world(host.player.global_position)
	if not is_finite(rise):return false
	host.player.global_position.y+=rise;host.player.velocity=Vector3.ZERO;host.player.spawn_valid=false
	host.exploration_traffic.refresh_terrain()
	host.street_pedestrians.refresh_terrain()
	host.exploration_pedestrians.refresh_terrain()
	host.neighborhood_population.refresh_terrain()
	host.neighborhood_greenery.refresh_terrain()
	host.player.reset_physics_interpolation();host.rig.snap_to_target_pose()
	print("EXP21_TERRAIN_READY triangles=",terrain.faces.size()/3," foundations=",terrain.field.foundations.size()," rigid_nodes=",rigid_nodes," source_geometry_files_changed=false")
	return true

func snapshot() -> Dictionary:
	return {"rigid_nodes":rigid_nodes,"geometry_operations":records,"skipped_subtrees":skipped.size(),"scope":"One synchronous runtime rebase; source data bytes and XZ scale remain unchanged. Detached interior cells retain their own frame; roofs and entries are rebuilt against level foundations."}
