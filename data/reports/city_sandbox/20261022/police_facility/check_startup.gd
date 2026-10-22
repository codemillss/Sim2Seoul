extends SceneTree
var scene: Node3D
func _initialize() -> void:run.call_deferred()
func encode(v: Variant) -> Variant:
	if v is Vector3:return [v.x,v.y,v.z]
	if v is Vector2:return [v.x,v.y]
	if v is Dictionary:
		var out: Dictionary={}
		for k: Variant in v:out[str(k)]=encode(v[k])
		return out
	if v is Array:
		var out: Array=[]
		for i: Variant in v:out.append(encode(i))
		return out
	if v is float:return v if is_finite(v) else null
	return v
func run() -> void:
	scene=load("res://scenes/world/explore_walk.tscn").instantiate();scene.exploration_settings_path="/tmp/police-facility-startup-"+str(OS.get_process_id())+".json";scene.quality_settings_path=scene.exploration_settings_path+".quality.json";root.add_child(scene)
	for i: int in range(8):await physics_frame;await process_frame
	var file:=FileAccess.open("res://../data/reports/city_sandbox/20261022/police_facility/startup04.json",FileAccess.WRITE);file.store_string(JSON.stringify(encode({"runtime_ok":scene.runtime_ok,"error":scene.exploration_error,"safety":scene.city_public_safety.snapshot()}),"  "));file.close()
	if is_instance_valid(scene.neighborhood_life.audio):scene.neighborhood_life.audio.stop();scene.neighborhood_life.audio.stream=null
	scene.queue_free();await process_frame;await process_frame;quit()
