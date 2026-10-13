extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var output:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--result="):output=arg.trim_prefix("--result=")
	var config: Resource=load("res://resources/world_config.tres")
	var runtime: Dictionary=config.read_runtime()
	var city=load("res://scenes/world/collision_world.tscn").instantiate()
	root.add_child(city)
	var accepted:=false
	var error: String=runtime.get("error","")
	if runtime.ok:
		accepted=city.load_collision(runtime.world)
		error=city.collision_error
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:push_error("P04 rejection output missing");quit(2);return
	file.store_string(JSON.stringify({"task":"P04","accepted":accepted,"error":error,"colliders_created":city.bodies.size(),"scope":"Actual malformed collision-plan rejection; no source originals changed"})+"\n")
	city.queue_free()
	quit(0 if not accepted else 1)
