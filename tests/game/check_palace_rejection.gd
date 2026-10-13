extends SceneTree
var output_path := ""
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--result="):output_path=arg.trim_prefix("--result=")
	_run.call_deferred()
func _run() -> void:
	var config: Resource=load("res://resources/world_config.tres")
	var base: Dictionary=config.read_runtime()
	if not base.ok:push_error("Base world invalid");quit(1);return
	var city=load("res://scenes/world/palace_world.tscn").instantiate()
	root.add_child(city)
	var accepted: bool=city.load_connection(base.world)
	var record:={"task":"W02","accepted":accepted,"source_bodies_created":city.bodies.size(),"fragment_bodies_created":city.fragments.size(),"error":city.walk_error}
	var file:=FileAccess.open(output_path,FileAccess.WRITE)
	if file==null:quit(1);return
	file.store_string(JSON.stringify(record)+"\n")
	city.queue_free()
	quit(0)
