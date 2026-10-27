extends SceneTree
## Manual GUI preview of the actual complete exploration scene. Records only
## redacted room diagnostics and this game's settings hashes, never invite/auth.
var world: Node3D
var output := ""
var before: Dictionary={}

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--preview-report="):output=argument.trim_prefix("--preview-report=")
	_run.call_deferred()

func _settings() -> Dictionary:
	var result: Dictionary={}
	var directory:=DirAccess.open("user://")
	if directory==null:return result
	for name: String in directory.get_files():
		if name.ends_with(".json"):result[name]=FileAccess.get_sha256("user://"+name)
	return result

func _run() -> void:
	before=_settings()
	world=load("res://scenes/world/explore_walk.tscn").instantiate()
	root.add_child(world)
	for frame in range(3):await process_frame
	for frame in range(3):await physics_frame
	DisplayServer.window_set_title("Sim2Seoul · 함께 걷기 개발")
	if not world.runtime_ok or not is_instance_valid(world.shared_city_walk):quit(1);return
	world.shared_city_walk.client.changed.connect(_record)
	world.shared_city_walk.open_panel();_record()
	print("SHARED_CITY_MANUAL_PREVIEW_READY")

func _record() -> void:
	if output.is_empty() or not is_instance_valid(world):return
	var helper: Node=world.shared_city_walk
	var rect: Rect2=helper._overlay.get_global_rect()
	var value:={"scope":"Actual full-city manual native preview; room diagnostics exclude secrets. Screenshots/OS inputs are separately recorded.","diagnostic":helper.diagnostic(),"ui":{"layer_visible":helper._layer.visible,"overlay_visible":helper._overlay.visible,"overlay_rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"menu_visible":world.menu.visible,"paused":paused},"settings_before":before,"settings_current":_settings(),"settings_unchanged":before==_settings()}
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(value,"\t")+"\n")
