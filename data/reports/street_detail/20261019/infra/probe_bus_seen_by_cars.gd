extends SceneTree
var scene: Node3D
var rows: Array=[]
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/private/tmp/bus-review-settings.json";scene.quality_settings_path="/private/tmp/bus-review-quality.json";root.add_child(scene)
	for i in range(3):await physics_frame
	if not scene.runtime_ok:push_error(scene.exploration_error);quit(1);return
	if scene.menu.visible:scene.toggle_menu()
	scene.set_vehicles_running(false);scene.set_pedestrians_running(false)
	var service: Node3D=scene.city_bus_service;var bus: CharacterBody3D=service.bus
	service.set_physics_process(false);bus.set_physics_process(false)
	var all: Array=[];all.append_array(scene.vehicles);all.append_array(scene.neighborhood_population.traffic.vehicles)
	for car: CharacterBody3D in all:car.collision_layer=0
	var passed:=0
	for car: CharacterBody3D in all:
		# Explicit collision fixture: move only the stationary bus ahead of each
		# unchanged original controller. Other cars' layers are isolated to prove
		# the returned collider is the real large bus, not another stopped actor.
		var direction: Vector3=car._segment_direction(car._segment)
		var target: Vector3=car.global_position+direction*9.0
		bus.global_transform=bus._terrain_pose(target,atan2(-direction.x,-direction.z));bus.velocity=Vector3.ZERO
		await physics_frame
		car._find_support()
		var hit: Dictionary=car._corridor_obstacle(12.0)
		var ok: bool=String(hit.get("reason","")).contains("BluePilotBus_T01")
		if ok:passed+=1
		rows.append({"id":car.get_route_id(),"passed":ok,"original_mask":car.collision_mask,"bus_layer":bus.collision_layer,"bus_box_m":[bus.body_shape.shape.size.x,bus.body_shape.shape.size.y,bus.body_shape.shape.size.z],"distance_m":hit.get("distance_m",-1),"reason":hit.get("reason","")})
	var f:=FileAccess.open("/private/tmp/bus-original14-review.json",FileAccess.WRITE);f.store_string(JSON.stringify({"passed":passed,"total":all.size(),"fixture":"Bus alone was moved9m ahead of each original unchanged car; other original car layers isolated. Native original full corridor queries, not a registry/mock; this proves detection and is not an observed braking journey.","rows":rows},"\t"));f.close()
	print("BUS_ORIGINAL14_REVIEW ",passed,"/",all.size());quit(0 if passed==all.size() else 1)
