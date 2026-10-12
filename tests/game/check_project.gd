extends SceneTree
var checks: Array[Dictionary] = []
var capture_prefix := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="):
			capture_prefix = argument.trim_prefix("--capture-prefix=")
	_run.call_deferred()

func _capture(suffix: String) -> void:
	if capture_prefix.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_check("gpu_capture_"+suffix,root.get_texture().get_image().save_png(capture_prefix+suffix+".png")==OK)

func _check(name: String, passed: bool) -> void:
	checks.append({"name":name,"passed":passed})

func _key(code: int, pressed: bool, echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	_check("local_contract_loaded",scene.runtime_state.get("ok",false))
	await _capture("ready")
	_check("empty_asset_manifest",scene.runtime_state.manifest.assets.is_empty())
	_check("technical_origin_not_spawn",scene.runtime_state.region.origin_role == "fixed_technical_origin_not_spawn_point" and scene.runtime_state.region.playable_boundary == null)
	for path in ["World/Ground","World/Buildings","World/Routes","World/Barriers","Actors/PlayerSlot"]:
		var node = scene.get_node(path)
		_check("empty_unit_scale_role_"+path,node is Node3D and node.get_child_count()==0 and node.scale==Vector3.ONE and node.position==Vector3.ZERO)
	var keys := {"move_forward":[KEY_W,KEY_UP],"move_backward":[KEY_S,KEY_DOWN],"move_left":[KEY_A,KEY_LEFT],"move_right":[KEY_D,KEY_RIGHT],"move_fast":[KEY_SHIFT],"toggle_menu":[KEY_ESCAPE]}
	for action in keys:
		var mapped := InputMap.has_action(action)
		for code in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = code
			mapped = mapped and InputMap.event_is_action(event,action)
		_check("physical_keys_"+action,mapped)
	_key(KEY_W,true)
	await process_frame
	_check("forward_key_produces_intent",scene.input_router.movement_intent().is_equal_approx(Vector2(0,-1)))
	_key(KEY_D,true)
	_key(KEY_SHIFT,true)
	await process_frame
	_check("diagonal_intent_bounded",is_equal_approx(scene.input_router.movement_intent().length(),1))
	_check("shift_produces_fast_intent",scene.input_router.fast_intent())
	_key(KEY_ESCAPE,true)
	await process_frame
	_check("esc_opens_paused_menu",scene.menu_open and paused and scene.menu_panel.visible)
	_check("menu_blocks_held_movement_and_fast",scene.input_router.movement_intent()==Vector2.ZERO and not scene.input_router.fast_intent())
	_check("menu_pauses_world_actors_presentation",not scene.get_node("World").can_process() and not scene.get_node("Actors/PlayerSlot").can_process() and not scene.get_node("Presentation").can_process())
	await _capture("menu")
	_key(KEY_ESCAPE,true,true)
	await process_frame
	_check("key_repeat_does_not_toggle_menu",scene.menu_open)
	_key(KEY_ESCAPE,false)
	_key(KEY_ESCAPE,true)
	await process_frame
	_check("esc_closes_menu_and_releases_focus",not scene.menu_open and not paused and root.gui_get_focus_owner()==null)
	_key(KEY_ESCAPE,false)
	_key(KEY_W,false)
	_key(KEY_D,false)
	_key(KEY_SHIFT,false)
	_key(KEY_UP,true)
	await process_frame
	_check("arrow_key_produces_intent",scene.input_router.movement_intent().is_equal_approx(Vector2(0,-1)))
	_key(KEY_UP,false)
	_key(KEY_ESCAPE,true)
	await process_frame
	_check("esc_reopens_menu",scene.menu_open)
	scene.resume_button.pressed.emit()
	await process_frame
	_check("resume_button_unpauses_and_enables_intent",not paused and not scene.menu_open and scene.input_router.gameplay_enabled)
	_check("resume_enables_world_and_actors",scene.get_node("World").can_process() and scene.get_node("Actors/PlayerSlot").can_process())
	_check("input_does_not_move_placeholder",scene.get_node("Actors/PlayerSlot").position==Vector3.ZERO)
	var failed := checks.filter(func(item):return not item.passed)
	print("E02_TEST_RESULT "+JSON.stringify({"checks":checks,"passed":checks.size()-failed.size(),"failed":failed.size()}))
	scene.queue_free()
	quit(0 if failed.is_empty() else 1)
