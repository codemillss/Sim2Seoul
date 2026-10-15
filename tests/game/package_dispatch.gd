extends Node
## Private package QA entry: normal launches keep this Autoload inert.
const PROBES: Dictionary={"quality":"res://test_support/check_quality.gd","urban":"res://test_support/check_packaged_walk.gd"}
func _ready() -> void:
	set_process(false);set_physics_process(false);set_process_input(false);set_process_unhandled_input(false)
	var arguments: PackedStringArray=OS.get_cmdline_user_args()
	var mode: String=""
	for argument in arguments:
		if argument.begins_with("--sim2seoul-test="):mode=argument.trim_prefix("--sim2seoul-test=")
	if mode.is_empty():return
	if not arguments.has("--automatic-probe") or not PROBES.has(mode):
		push_error("Unsupported private package QA request");get_tree().quit(2);return
	_dispatch.call_deferred(mode)
func _dispatch(mode: String) -> void:
	var tree: SceneTree=get_tree()
	var current: Node=tree.current_scene
	if is_instance_valid(current):current.queue_free()
	await tree.process_frame
	await tree.process_frame
	if is_instance_valid(current) or tree.current_scene!=null or tree.get_script()!=null:
		push_error("Package QA requires the old main freed and an unmodified SceneTree");tree.quit(2);return
	var probe: Script=load(PROBES[mode])
	if probe==null or not probe.can_instantiate():
		push_error("Embedded package QA script is unavailable");tree.quit(2);return
	tree.set_script(probe)
	if tree.get_script()!=probe:
		push_error("Package QA could not attach to the active SceneTree");tree.quit(2);return
	print("R03_QA_DISPATCH mode=",mode," script=",PROBES[mode])
	tree.call("_initialize")
	# Autoload lifetime belongs to SceneTree: retain this disabled Node.
