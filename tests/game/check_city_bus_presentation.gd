extends "res://../tests/game/check_city_bus_loop.gd"
class RenderObserver extends Node:
	var body: CharacterBody3D
	var service: Node3D
	var render_samples:=0
	var moving_samples:=0
	var physics_samples:=0
	var fractions: Dictionary={}
	var maximum_render_error_m:=0.
	var maximum_seated_anchor_error_m:=0.
	var maximum_native_collider_error_m:=0.
	var maximum_physics_visual_error_m:=0.
	var last_native_pose:=Transform3D.IDENTITY
	func _physics_process(_delta: float) -> void:
		if get_tree().paused or not service.running or not body._visual_ready:return
		last_native_pose=body.global_transform
		maximum_physics_visual_error_m=maxf(maximum_physics_visual_error_m,body.get_node("Visual").global_position.distance_to(body.global_position));physics_samples+=1
	func _process(_delta: float) -> void:
		if get_tree().paused or not service.running or not body._visual_ready:return
		var alpha:=clampf(Engine.get_physics_interpolation_fraction(),0.,1.);var expected: Transform3D=body._visual_previous.interpolate_with(body._visual_current,alpha);var visual: Node3D=body.get_node("Visual");var seated: Node3D=visual.get_node("SeatedPassenger");var collider: CollisionShape3D=body.get_node("CollisionShape")
		maximum_render_error_m=maxf(maximum_render_error_m,visual.global_position.distance_to(expected.origin));maximum_seated_anchor_error_m=maxf(maximum_seated_anchor_error_m,seated.global_position.distance_to(expected*seated.position));maximum_native_collider_error_m=maxf(maximum_native_collider_error_m,collider.global_position.distance_to(body.global_transform*collider.position));render_samples+=1
		if body._visual_previous.origin.distance_to(body._visual_current.origin)>.001:
			moving_samples+=1;fractions[str(roundi(alpha*1000.))]=true
func _run() -> void:
	if FileAccess.file_exists(report_path):push_error("Refusing to overwrite presentation evidence");quit(2);return
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/sim2seoul-bus-presentation-settings.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(6);service=scene.city_bus_service
	_check("production_three_bus_30Hz_ready",scene.runtime_ok and service.loaded and Engine.physics_ticks_per_second==30)
	if not scene.runtime_ok or not service.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	var body: CharacterBody3D=service.buses[2];var observer:=RenderObserver.new();observer.body=body;observer.service=service;observer.process_mode=Node.PROCESS_MODE_ALWAYS;observer.process_priority=1000;observer.process_physics_priority=4;root.add_child(observer)
	for tick: int in range(30*30):
		await _ticks(1);service._switch_bus(body)
		if service.bus_state=="doors_open":break
	_check("natural_dock_without_bus_pose_fixture",service.bus_state=="doors_open")
	if service.bus_state!="doors_open":_finish();return
	service.set_running(false);var door: Vector3=body.to_global(Vector3(1.6,0,.55));door.y=scene.terrain_surface.ground_y_world(door)+.08;var posed: bool=await _pose(door);await _tap();_check("fresh_E_actual_visible_seated_passenger",posed and service.riding and service.active_bus()==body and body.get_node("Visual/SeatedPassenger").visible)
	if not service.riding:_finish();return
	service.set_running(true)
	for tick: int in range(30*60):
		await _ticks(1)
		if body._speed_mps>.5 and observer.moving_samples>100:break
	_check("actual_render_frames_interpolate_moving_bus_and_visible_passenger_same_fraction",observer.moving_samples>100 and observer.fractions.size()>=3 and observer.maximum_render_error_m<.0005 and observer.maximum_seated_anchor_error_m<.0005,{"render_samples":observer.render_samples,"moving_samples":observer.moving_samples,"distinct_fractions":observer.fractions.keys(),"maximum_bus_render_error_m":observer.maximum_render_error_m,"maximum_seated_anchor_error_m":observer.maximum_seated_anchor_error_m})
	_check("render_offset_never_enters_actual_native_collider_or_physics_visual_queries",observer.physics_samples>10 and observer.maximum_native_collider_error_m<.0005 and observer.maximum_physics_visual_error_m<.0005,{"physics_samples":observer.physics_samples,"maximum_native_collider_error_m":observer.maximum_native_collider_error_m,"maximum_physics_visual_error_m":observer.maximum_physics_visual_error_m})
	service.set_running(false);var frozen_visual: Transform3D=body.get_node("Visual").global_transform;var frozen_body: Transform3D=body.global_transform;await _ticks(12)
	_check("vehicle_checkbox_freezes_native_and_presented_bus",body.global_transform==frozen_body and body.get_node("Visual").global_transform==frozen_visual)
	service.set_running(true);await _ticks(3);frozen_visual=body.get_node("Visual").global_transform;frozen_body=body.global_transform;scene.toggle_menu();await _ticks(12)
	_check("menu_freezes_native_and_presented_bus",body.global_transform==frozen_body and body.get_node("Visual").global_transform==frozen_visual);scene.toggle_menu()
	_check("source_geometry_original14_and_bus_json_preserved",service.snapshot().original_vehicle_ids_unchanged and FileAccess.get_sha256("res://assets/authored/bus_service.json")=="a5b7c4cbc36553f022e2b0796f89acc15fdf21efa1c349ba94a557cd7077d2ea")
	_finish()
