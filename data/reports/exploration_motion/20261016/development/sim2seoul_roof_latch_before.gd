extends "res://../tests/game/check_rooftops.gd"
func _run() -> void:
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=report_path+".settings.json";scene.quality_settings_path=report_path+".quality.json";root.add_child(scene)
	visit=scene.interior_visit;await _ticks(25);visit.select_building(IDS[0])
	await _pose(visit.entrance_world_position);_e(true);_e(false);await _ticks(12)
	await _pose(visit.room.elevator_point(0));_e(true);_e(false);await _ticks(4)
	var accepted: bool=visit.request_floor(int(visit.current_spec.floor_count))
	Input.action_press("move_forward");await _wait_ride();await _ticks(4)
	var before := {"latched":scene.player.input_latched,"grounded":scene.player.is_on_floor(),"position":scene.player.global_position,"vy":scene.player.velocity.y}
	Input.action_release("jump");await _ticks(2);Input.action_press("jump");await _ticks(1)
	var after := {"latched":scene.player.input_latched,"grounded":scene.player.is_on_floor(),"position":scene.player.global_position,"vy":scene.player.velocity.y}
	var report:={"task":"roof_jump_latch_reproduction","accepted_real_ride":accepted,"on_roof":visit.on_roof,"held_W_through_ride":true,"fresh_Space_after_arrival":true,"before":before,"after":after,"player_sha256":FileAccess.get_sha256("res://scripts/player/free_roam_player.gd"),"scope":"ActualproductionEentry/rooflift. Wheldthroughrideandarrival; Spacefreshlypressedafterarrivalwithoutmovementrelease. Noassignedpositionafterrideorvelocity."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(_json(report),"\t"));file.close();print(JSON.stringify(_json(report)));quit(0)
