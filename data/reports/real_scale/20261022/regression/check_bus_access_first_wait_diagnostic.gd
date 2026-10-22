extends "res://../tests/game/check_city_bus_loop.gd"
## Observation-only copy of the original first source-wait KEY_E fixture.
var timeline: Array=[]
var observations: Array=[]
var original_pose:=false
func _state(label: String) -> Dictionary:
	var visit: Node3D=scene.interior_visit if is_instance_valid(scene) else null
	return {"label":label,"physics_tick":Engine.get_physics_frames(),"process_frame":Engine.get_process_frames(),"waiting_for_bus":service.waiting_for_bus if is_instance_valid(service) else null,"waiting_stop_index":service._waiting_stop_index if is_instance_valid(service) else null,"events":service.events.duplicate(true) if is_instance_valid(service) else [],"interact_held":Input.is_action_pressed("interact"),"e_press_pending":visit._e_press_pending if is_instance_valid(visit) else null,"e_was_pressed":visit._e_was_pressed if is_instance_valid(visit) else null,"e_requires_release":visit.e_requires_release if is_instance_valid(visit) else null,"player":str(scene.player.global_position) if is_instance_valid(scene) else "","menu_open":scene.menu.visible if is_instance_valid(scene) else null}
func _ticks(count: int) -> void:
	for tick: int in range(count):
		await physics_frame
		if is_instance_valid(service):timeline.append(_state("original_physics_only_tick"))
func _target_name() -> String:
	var target: Node3D=scene._street_interact_target()
	return String(target.name) if is_instance_valid(target) else "none"
func _tap_key() -> void:
	observations.append(_state("before_pressed_parse_input_event"))
	var event:=InputEventKey.new();event.physical_keycode=KEY_E;event.pressed=true;event.device=42;Input.parse_input_event(event)
	observations.append(_state("immediately_after_pressed_parse_input_event"));await _ticks(2)
	event=InputEventKey.new();event.physical_keycode=KEY_E;event.pressed=false;event.device=42;Input.parse_input_event(event)
	observations.append(_state("immediately_after_released_parse_input_event"));await _ticks(3)
func _run() -> void:
	var settings: String="/tmp/sim2seoul-bus-first-wait-diagnostic-"+str(OS.get_process_id())+".json"
	var file:=FileAccess.open(settings,FileAccess.WRITE);file.store_string(JSON.stringify({"schema_version":1,"speed_id":"realistic","free_roam":true}));file.close()
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=settings;scene.quality_settings_path=settings+".quality.json";scene.exploration_physics_hz=30;root.add_child(scene);await _ticks(6);service=scene.city_bus_service
	_check("whole_city_ready",scene.runtime_ok and service.loaded)
	if not scene.runtime_ok or not service.loaded:_finish();return
	if scene.menu.visible:scene.toggle_menu()
	var stop: Dictionary=service.design.stops[0];original_pose=await _pose(stop.wait_world)
	var before: Dictionary=_state("before_original_first_E");before["posed"]=original_pose;before["requested_wait_world"]=str(stop.wait_world);before["street_target"]=_target_name();before["bus_can_interact"]=service.can_interact();before["nearest_wait"]=service._nearest_wait();before["boarding_candidate"]=str(service._boarding_candidate());observations.append(before)
	service.set_running(true);await _tap_key()
	var after: Dictionary=_state("same_original_assertion_phase");after["posed"]=original_pose;after["street_target"]=_target_name();after["bus_can_interact"]=service.can_interact();after["nearest_wait"]=service._nearest_wait();observations.append(after)
	_check("original_source_wait_first_E_condition",original_pose and service.waiting_for_bus and service._waiting_stop_index==0,after)
	# Observation only: allow one ordinary process frame and subsequent original
	# physics processing; no extra E, clock assignment, or direct service call.
	await process_frame;observations.append(_state("after_next_process_frame"));await _ticks(3);observations.append(_state("settled_after_process_and_physics"))
	_finish()
func _finish() -> void:
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"task":"BUS_FIRST_WAIT_INPUT_PHASE_OBSERVATION","display":DisplayServer.get_name(),"checks":checks,"timeline":timeline,"observations":observations,"production_source_hashes":{"res://scripts/city_bus_service.gd":FileAccess.get_sha256("res://scripts/city_bus_service.gd"),"res://scripts/interior_visit.gd":FileAccess.get_sha256("res://scripts/interior_visit.gd"),"res://scripts/explore_walk.gd":FileAccess.get_sha256("res://scripts/explore_walk.gd")},"scope":"Short first-stop portion using the exact original pose and physical KEY_E timing; observations only. No production, actor, service state, test assertion or input flushing mutation. Headless input phase observation cannot reproduce or prove a native first-frame scheduling failure."},"  ")+"\n");file.close();print("BUS_FIRST_WAIT_DIAGNOSTIC_DONE");quit(0)
