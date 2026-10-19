extends SceneTree
class FlatSupport extends Node3D:
	func _ground(at: Vector3,_height: float) -> Dictionary:return {"point":Vector3(at.x,.025,at.z)}
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	var host:=FlatSupport.new();root.add_child(host);var visual:=Node3D.new();host.add_child(visual);visual.position.y=.025
	var model=load("res://scripts/street_dog_model.gd").new();model.build(host,visual,{"dog_color":[.72,.49,.27]})
	var maximum_planted_step:=0.;var previous:={};var turns:=0;var previous_yaw:=0.;var distance:=0.;var side:=1.
	for tick: int in range(6000):
		var delta:=1./60.;var moving:=tick%600<500
		if tick%600==0 and tick>0:side=-side;turns+=1
		var step:=1.05*delta if moving else 0.;visual.position.z-=side*step;distance+=step
		visual.rotation.y=rotate_toward(visual.rotation.y,0. if side>0. else PI,2.8*delta)
		model.pose(step,delta,"walking" if moving else "sniffing",tick*delta,Vector3(1.,0.,-1.))
		for index: int in range(4):
			var leg: Dictionary=model.legs[index];var current: Vector3=leg.ankle.global_position
			if previous.has(index) and leg.planted and previous[index].planted:maximum_planted_step=maxf(maximum_planted_step,current.distance_to(previous[index].at))
			previous[index]={"at":current,"planted":leg.planted}
	var state: Dictionary=model.snapshot();var passed: bool=state.maximum_planted_target_error_m<.045 and state.paw_center_ground_gap_range_m[0]>=-.012 and state.paw_center_ground_gap_range_m[1]<.12 and maximum_planted_step<.025
	print(JSON.stringify({"result":"PASS" if passed else "FAIL","source_sha256":FileAccess.get_sha256("res://scripts/street_dog_model.gd"),"frames":6000,"visual_anchor_distance_m":distance,"simulated_yaw_turns":turns,"maximum_planted_frame_step_m":maximum_planted_step,"model":state,"scope":"Synthetic flat visual rig only. Stresses fast turns and pauses; does not replace real production physical patrol/terrain acceptance."},"  "))
	quit(0 if passed else 1)
