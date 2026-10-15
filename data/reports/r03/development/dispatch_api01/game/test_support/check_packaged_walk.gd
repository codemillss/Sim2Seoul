extends SceneTree
var initialize_calls: int=0
func _initialize() -> void:
	initialize_calls+=1
	_run.call_deferred()
func _run() -> void:
	await process_frame
	var dispatcher: Node=root.get_node_or_null("Sim2SeoulPackageQA")
	var record: Dictionary={"initialize_calls":initialize_calls,"old_main_gone":current_scene==null and root.get_node_or_null("NormalMain")==null,"autoload_retained":is_instance_valid(dispatcher),"autoload_inert":is_instance_valid(dispatcher) and not dispatcher.is_processing() and not dispatcher.is_physics_processing() and not dispatcher.is_processing_input() and not dispatcher.is_processing_unhandled_input(),"script_path":get_script().resource_path,"main_setting":ProjectSettings.get_setting("application/run/main_scene"),"engine":Engine.get_version_info().string}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--result="):
			var stream: FileAccess=FileAccess.open(argument.trim_prefix("--result="),FileAccess.WRITE)
			stream.store_string(JSON.stringify(record)+"\n");stream.close()
	print("R03_TINY_DISPATCH ",JSON.stringify(record))
	quit(0 if initialize_calls==1 and record.old_main_gone and record.autoload_retained and record.autoload_inert else 1)
