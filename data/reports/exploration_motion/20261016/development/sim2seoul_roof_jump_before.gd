extends "res://../tests/game/check_rooftops.gd"
var flights: Array=[]
func _run() -> void:
	source_hashes={"player":FileAccess.get_sha256("res://scripts/player/free_roam_player.gd"),"roof":FileAccess.get_sha256("res://scripts/rooftop_space.gd")}
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path=report_path+".settings.json";scene.quality_settings_path=report_path+".quality.json";root.add_child(scene)
	visit=scene.interior_visit;await _ticks(25)
	if not visit.select_building(IDS[0]):quit(1);return
	await _pose(visit.entrance_world_position);_e(true);_e(false);await _ticks(12)
	if not visit.active or not await _ride_to(int(visit.current_spec.floor_count),"real_roof_ride"):quit(1);return
	var roof: Node3D=visit.rooftop
	var start: Vector3=scene.player.global_position
	var recoveries: int=scene.player.recoveries
	for index in range(6):
		_keys();await _ticks(2)
		var before: Vector3=scene.player.global_position;var vy: float=scene.player.velocity.y
		Input.action_press("jump");await _ticks(1)
		flights.append({"edge":index+1,"before":before,"before_vy":vy,"after":scene.player.global_position,"after_vy":scene.player.velocity.y,"air_remaining":scene.player.air_jumps_remaining(),"grounded":scene.player.is_on_floor(),"latched":scene.player.input_latched,"recoveries":scene.player.recoveries-recoveries})
		await _ticks(20)
	_keys();await _ticks(180)
	var fault_start: Vector3=scene.player.global_position
	for index in range(7):
		_keys();await _ticks(2)
		# Explicit diagnostic injection only: emulate uncapped fresh edges to
		# isolate the existing 9m roof-region ceiling from the two-jump policy.
		scene.player.set("_air_jumps_used",0)
		Input.action_press("jump");await _ticks(1)
		flights.append({"diagnostic_policy_override":true,"edge":index+1,"position":scene.player.global_position,"above_deck":scene.player.global_position.y-roof.deck_height_y,"vy":scene.player.velocity.y,"recoveries":scene.player.recoveries-recoveries,"reason":scene.player.last_recovery_reason})
		await _ticks(20)
	_keys()
	var report:={"task":"roof_jump_before_reproduction","source_sha256":source_hashes,"display":DisplayServer.get_name(),"real_lift_arrival":start,"roof_world_bounds":roof.world_bounds,"flights":flights,"diagnostic_policy_override_start":fault_start,"scope":"First6freshSpaceedgesuseunchangedproductionpolicy. Secondsequenceexplicitlyresetsprivatejumpbudgetonlytoreproduceindependentexisting9mroofceiling; itisdiagnosticfaultinjectionnotuseracceptance."}
	var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(_json(report),"\t"));file.close();print(JSON.stringify(_json(report)));quit(0)
