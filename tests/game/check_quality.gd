extends "res://test_support/check_urban_motion.gd"
## R02 short V0 display/UI regression. All actor restarts are after motion trials.
var settings_path := ""
var quality_profiles := []
var ui_events := {}
var layout_rows := []
var restart_rows := []

func _retain_motion() -> void:
	var count:=motion_samples.size()
	super._retain_motion()
	if motion_samples.size()>count:motion_samples[-1]["quality"]=scene.quality_snapshot()

func _instances() -> Array:
	var ids:=[]
	for body in scene.pedestrians+scene.vehicles:ids.append(body.get_instance_id())
	return ids

func _quality_state() -> Dictionary:
	return {"quality":scene.quality_snapshot(),"settings_recovered":scene.settings_recovered,
		"notice":scene.quality_notice.text,"paused":paused,"menu_visible":scene.menu.visible,
		"popup_visible":scene.sources_overlay.visible,"input_enabled":scene.input_router.gameplay_enabled,
		"camera_input_enabled":scene.rig.input_enabled,"player":_player_row(),"npcs":_npc_rows(),"vehicles":_vehicle_rows(),"instances":_instances()}

func _fresh_quality(label: String) -> bool:
	_keys([]);paused=false
	if is_instance_valid(scene):scene.queue_free();scene=null
	await process_frame
	await process_frame
	scene=load("res://scenes/world/v0_walk.tscn").instantiate()
	scene.quality_settings_path=settings_path
	root.add_child(scene)
	if not scene.runtime_ok:return false
	scene.input_router.set_script(load("res://test_support/daehanmun_probe_input.gd"))
	scene.input_router.isolate_movement_bindings()
	for route in scene.pedestrian_bundle.routes:route_map[route.id]=route
	for route in scene.traffic_bundle.routes:source_routes[route.id]=route
	await _wait(1.)
	restart_rows.append({"name":label,"phase":"settings_restart_only","state":_quality_state(),"inventory":_inventory()})
	return true

func _select_quality(id: String) -> Dictionary:
	_keys([])
	if not scene.menu.visible:await _escape()
	var before:=_quality_state()
	var index:=0 if id=="standard" else 1
	# Emit the actual OptionButton signal: its production connection applies/saves.
	scene.quality_option.select(index);scene.quality_option.item_selected.emit(index)
	await process_frame
	var selected:=_quality_state()
	var saved:=FileAccess.get_file_as_string(settings_path)
	await _escape()
	await _wait(.2)
	return {"requested":id,"signal_connected":scene.quality_option.item_selected.is_connected(scene._quality_selected),"before":before,"selected":selected,"saved_text":saved,"resumed":_quality_state()}

func _orbit_hold(seconds: float,pixels_per_second:=0.) -> void:
	_keys([])
	for tick in range(int(round(seconds*60.))):
		if pixels_per_second!=0.:
			_mouse(pixels_per_second/60.,0.);Input.flush_buffered_events()
		await scene.rig.camera_stepped
	_retain_motion()

func _profile(id: String) -> void:
	var selected: Dictionary=await _select_quality(id)
	var before:=_inventory();var instances:=_instances()
	var supports:=[]
	for body in scene.road_supports:supports.append(_body_row(body.get_meta("geometry_id"),body))
	motion_samples=[];motion_pose_calls=0;motion_last_retained=-1;exercise_phase=id
	_begin_motion()
	var legs:=[]
	var route: Array=scene.city.connection.route_xz
	if suite!="smoke":
		for sense in ["forward","reverse"]:
			var indices: Array=[1,2,3] if sense=="forward" else [2,1,0]
			for index in indices:
				legs.append(await _seek(id+"_gate_"+sense+"_"+str(index),_point(route[index])))
				if not run_error.is_empty():break
				if sense=="forward" and index in [1,2]:
					for zoom in range(12):_button(MOUSE_BUTTON_WHEEL_UP if index==1 else MOUSE_BUTTON_WHEEL_DOWN)
					Input.flush_buffered_events()
					await _orbit_hold(16.,260.)
			if not run_error.is_empty():break
	var target_ticks:=180 if suite=="smoke" else 5400
	while motion_stats.ticks<target_ticks and run_error.is_empty():await _orbit_hold(1.)
	var timeline:=_finish_motion()
	quality_profiles.append({"id":id,"selection":selected,"before_inventory":before,"after_inventory":_inventory(),
		"supports_before":supports,"supports_after":scene.road_supports.map(func(body):return _body_row(body.get_meta("geometry_id"),body)),
		"instances_before":instances,"instances_after":_instances(),"quality_after":scene.quality_snapshot(),"legs":legs,"timeline":timeline})
	print("R02_PROFILE ",id," ticks=",timeline.ticks," error=",run_error)

func _resize(size: Vector2i) -> void:
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size=Vector2i.ZERO;root.content_scale_factor=1.
	root.size=size
	for frame in range(4):await process_frame

func _controls(control: Control,rows: Array) -> void:
	if control.is_visible_in_tree():
		var rect:=control.get_global_rect()
		var row:={"path":str(scene.get_path_to(control)),"class":control.get_class(),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]}
		if control is Label:row["text"]=(control as Label).text
		elif control is Button:row["text"]=(control as Button).text
		rows.append(row)
	for child in control.get_children():
		if child is Control:_controls(child,rows)

func _layout(name: String) -> void:
	var rows:=[]
	_controls(scene.hud_panel,rows);_controls(scene.menu,rows);_controls(scene.sources_overlay,rows)
	_controls(scene.attribution_label,rows)
	var size:=root.get_visible_rect().size
	layout_rows.append({"name":name,"viewport":[size.x,size.y],"window":[root.size.x,root.size.y],"controls":rows,
		"attribution":scene.attribution_label.text,"source_display_text":scene.sources_text.text})

func _ui() -> void:
	_keys([])
	await _resize(Vector2i(960,600))
	await _escape()
	ui_events["menu_open"]=_quality_state()
	var p: Vector3=scene.player.global_position
	var before:=_motion_state()
	await create_timer(.25).timeout
	ui_events["menu_still"]=_quality_state()
	ui_events["menu_drift_m"]=scene.player.global_position.distance_to(p)
	ui_events["paused_actor_counters_before"]=before
	_layout("menu_960");await _capture("menu_960")
	scene.movement_switch.button_pressed=false;scene.traffic_switch.button_pressed=false
	ui_events["switches_off"]=_quality_state()
	await _escape();await _wait(.5)
	ui_events["switches_off_resumed"]=_quality_state()
	await _escape()
	scene.movement_switch.button_pressed=true;scene.traffic_switch.button_pressed=true
	ui_events["switches_on"]=_quality_state()
	scene.quality_option.select(1);scene.quality_option.item_selected.emit(1)
	ui_events["quality_low_signal"]=_quality_state()
	ui_events["saved_low_text"]=FileAccess.get_file_as_string(settings_path)
	var source_button: Button=scene.menu.find_child("SourcesButton",true,false)
	ui_events["source_signal_connected"]=source_button.pressed.is_connected(scene._show_sources)
	source_button.pressed.emit();await process_frame
	_layout("popup_960")
	scene.sources_close.pressed.emit();ui_events["popup_button_960"]=_quality_state()
	await _resize(Vector2i(1152,720))
	source_button.pressed.emit();await process_frame
	ui_events["popup_open"]=_quality_state()
	_layout("popup_1152");await _capture("popup_1152")
	await _escape();ui_events["popup_escape"]=_quality_state()
	source_button.pressed.emit();await process_frame
	scene.sources_close.pressed.emit();ui_events["popup_button"]=_quality_state()
	await _escape();await _wait(.5)
	ui_events["resumed"]=_quality_state()
	_layout("hud_1152");await _capture("hud_1152")
	# Explicit manual-recovery button case is outside both zero-recovery timelines.
	await _escape()
	var recoveries: int=scene.player.recoveries
	scene.reset_button.pressed.emit()
	ui_events["manual_recovery"]={"delta":scene.player.recoveries-recoveries,"reason":scene.player.last_recovery_reason,"state":_quality_state()}
	await _escape();await _wait(.5)
	ui_events["manual_recovery_settled"]=_quality_state()

func _settings_cases() -> void:
	if not await _fresh_quality("saved_low_restart"):run_error="saved low restart rejected";return
	for pair in [["broken_json","{broken JSON"],["unknown_id","{\"schema_version\":1,\"preset_id\":\"unknown\"}"]]:
		var file:=FileAccess.open(settings_path,FileAccess.WRITE);file.store_string(pair[1]);file.close()
		if not await _fresh_quality(pair[0]):run_error="invalid-settings recovery rejected";return
		restart_rows[-1]["injected_text"]=pair[1]
		restart_rows[-1]["recovered_saved_text"]=FileAccess.get_file_as_string(settings_path)

func _run() -> void:
	settings_path=output_path+".quality_settings.json"
	if FileAccess.file_exists(settings_path):push_error("R02 requires a fresh temporary settings file");quit(1);return
	if not await _fresh_quality("fresh_standard"):push_error("R02 V0 scene rejected");quit(1);return
	await _resize(Vector2i(1152,720))
	guidance=load("res://test_support/urban_motion_guidance.gd").new()
	itinerary=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/walkable_itinerary.json"))
	await _wait(.5)
	var initial_inventory:=_inventory()
	await _profile("standard")
	if run_error.is_empty():await _profile("low")
	var after_inventory:=_inventory()
	if run_error.is_empty():await _ui();await _settings_cases()
	var record:={"schema_version":1,"task":"R02","suite":suite,"error":run_error,
		"engine":{"version":Engine.get_version_info().string,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"physics_hz":Engine.physics_ticks_per_second},
		"initial_inventory":initial_inventory,"final_motion_inventory":after_inventory,"profiles":quality_profiles,"ui":ui_events,
		"layouts":layout_rows,"settings_restarts":restart_rows,"captures":capture_names,
		"scope":"Two short V0 display-profile regression timelines, about 90 seconds each. Original entrance route in both directions, near/far camera orbits and dynamic actors; no player placement, actor reset or fixtures within either timeline. Menu/manual recovery and actor recreation for saved-settings restart cases are separate. No N04 full journey, performance improvement, twenty-minute endurance, human handling or another Mac acceptance."}
	FileAccess.open(output_path,FileAccess.WRITE).store_string(JSON.stringify(record)+"\n")
	_keys([]);paused=false;scene.queue_free();print("R02_DONE error=",run_error);quit(0)
