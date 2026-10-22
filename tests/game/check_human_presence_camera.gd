extends "res://../tests/game/check_human_scale_motion.gd"
## Independent late observation of production camera, body and local joints.
## This metre fixture injects engine actions; it does not claim OS input,
## whole-city geometry accuracy, sustained frame rate or subjective comfort.
const ATTACHED_BIKE_SERVICE := preload("res://scripts/city_bike_service.gd")
const EXPECTED_HIP_MARKER_Y_M := .978
const EXPECTED_WALK_SUPPORT_HALF_AMPLITUDE_M := .016
const EXPECTED_RUN_SUPPORT_HALF_AMPLITUDE_M := .024
class AttachedBikeHost extends Node3D:
	var player: CharacterBody3D
	var exploration_avatar: Node3D
	var rig: Node3D
class AttachedBikeDriver extends Node:
	var service: Node3D
	var row: Dictionary
	var elapsed := 0.0
	func _physics_process(delta: float) -> void:
		# Only the synthetic fixture's supported forward course and cadence are
		# authored here. Actual bicycle art, attachments and IK remain production.
		elapsed+=delta;row.previous=row.current
		row.body.velocity=Vector3(0.,-.12,-1.4);row.body.move_and_slide()
		service._pedal_phase=fposmod(elapsed*5.4,TAU)
		row.crank.rotation.x=service._pedal_phase
		for pedal: Node3D in row.pedals:pedal.rotation.x=-service._pedal_phase
		row.front.rotation.y=.18*sin(elapsed*1.7);row.current=row.body.global_transform
		service._attach_player(delta);service._rider_pose()
var presence_cases: Array=[]
var presence_captures: Array=[]
var presence_phase := ""
var presence_tick_count := 0
var presence_physics: Array=[]
var presence_render: Array=[]
var presence_nodes: Array[Node3D]=[]
var presence_node_names: Array[String]=[]
var presence_previous: Array[Transform3D]=[]
var presence_current: Array[Transform3D]=[]
var presence_previous_root := Transform3D.IDENTITY
var presence_current_root := Transform3D.IDENTITY
var presence_history_ready := false
var presence_previous_gait: Dictionary={}
var presence_current_gait: Dictionary={}
var presence_analytic_pelvis_samples := 0
var presence_analytic_pelvis_nontrivial_samples := 0
var presence_analytic_pelvis_maximum_error_m := 0.
var presence_analytic_pelvis_maximum_linear_difference_m := 0.
var presence_paused_teleport_pending := false
var presence_paused_teleport_result: Dictionary={}
var presence_eye_baseline := 0.0
var presence_started_ms := 0
var presence_physics_hz := 30
var presence_render_cap := 144
var presence_camera_previous := Transform3D.IDENTITY
var presence_camera_current := Transform3D.IDENTITY
var presence_max_joint_position_error := 0.0
var presence_max_joint_basis_error := 0.0
var presence_max_root_error := 0.0
var presence_max_eye_relative_error := 0.0
var presence_max_raw_root_error := 0.0
var presence_min_torso_y := INF
var presence_max_torso_y := -INF
var presence_max_roll := 0.0
var presence_max_yaw_step := 0.0
var presence_last_yaw := 0.0
var presence_max_angle_alignment := 0.0
var presence_min_eye_offset := INF
var presence_max_eye_offset := -INF
var presence_fraction_bins: Dictionary={}
var presence_joint_changed := false
var presence_observed_intermediate := false
var presence_moving_v_pending := false
var presence_moving_v_result: Dictionary={}
var presence_timing_events: Array=[]
var presence_case_start_ms := 0
var presence_case_physics_start := 0
var presence_case_process_start := 0
var presence_physics_delta_sum_s := 0.0
var presence_render_delta_sum_s := 0.0
var presence_render_count := 0
var presence_focused_render_count := 0
var presence_case_draw_start := 0
var presence_render_first_usec := 0
var presence_render_last_usec := 0
var presence_vsync_before := -1
var presence_vsync_requested := -1
var presence_vsync_initial_readback := -1
var presence_bicycle_row: Dictionary={}
var presence_bicycle_max_sole_height_error := 0.0
var presence_bicycle_max_hand_error := 0.0
var presence_bicycle_render_samples := 0

func _initialize() -> void:
	started_at=Time.get_datetime_string_from_system();presence_started_ms=Time.get_ticks_msec()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
	if report_path.is_empty() or not report_path.is_absolute_path():push_error("check_human_presence_camera needs absolute --report");quit(2);return
	for action: String in ACTIONS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action);Input.action_release(action)
	if not InputMap.has_action("toggle_menu"):InputMap.add_action("toggle_menu")
	Engine.physics_ticks_per_second=30;Engine.max_fps=144
	if DisplayServer.get_name()!="headless":
		# A 120Hz display with V-Sync phase-locks60Hz physics into two actual
		# render fractions, even when the fixture requests a144FPS cap. Disable
		# V-Sync only in this disposable test window to exercise the requested
		# scheduling matrix. Never assign an artificial interpolation fraction.
		# Unsupported renderers/platforms can fall back; record the readback and
		# actual wall-clock observations rather than assume the request worked.
		presence_vsync_before=int(DisplayServer.window_get_vsync_mode())
		presence_vsync_requested=int(DisplayServer.VSYNC_DISABLED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		presence_vsync_initial_readback=int(DisplayServer.window_get_vsync_mode())
	create_timer(240.,true,false,true).timeout.connect(_presence_timeout)
	_presence_checkpoint("initialize")
	_run.call_deferred()

func _presence_checkpoint(label: String) -> Dictionary:
	var event:={"event":label,"phase":presence_phase,"elapsed_wall_seconds":float(Time.get_ticks_msec()-presence_started_ms)/1000.,"physics_frame":Engine.get_physics_frames(),"process_frame":Engine.get_process_frames(),"frames_drawn":Engine.get_frames_drawn(),"physics_hz":Engine.physics_ticks_per_second,"render_cap_fps":Engine.max_fps,"engine_time_scale":Engine.time_scale,"maximum_physics_steps_per_render_frame":Engine.max_physics_steps_per_frame,"tree_paused":paused,"window_focused":DisplayServer.window_is_focused() if DisplayServer.get_name()!="headless" else false,"low_processor_usage_mode":OS.low_processor_usage_mode,"low_processor_sleep_usec":OS.low_processor_usage_mode_sleep_usec}
	event["window_scheduling"]=_presence_window_scheduling()
	presence_timing_events.append(event)
	print("HUMAN_CAMERA_PROGRESS ",JSON.stringify(event))
	return event

func _presence_window_scheduling() -> Dictionary:
	var native:=DisplayServer.get_name()!="headless"
	return {"native_window":native,"vsync_original_mode":presence_vsync_before,"vsync_requested_mode":presence_vsync_requested,"vsync_initial_readback_mode":presence_vsync_initial_readback,"vsync_current_readback_mode":int(DisplayServer.window_get_vsync_mode()) if native else -1,"screen_reported_refresh_hz":DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen()) if native else -1.,"scope":"Test-window V-Sync disabled request permits independent render-cap observations. Backend/OS fallback is possible. Readback and actual process/draw wall clocks are evidence; cap labels are not achieved or sustained FPS assertions. Production settings and interpolation fractions are never written."}

func _presence_timeout() -> void:
	if finished:return
	var event:=_presence_checkpoint("bounded_runtime_timeout")
	_check("bounded_runtime",false,{"timeout_seconds":240,"phase":presence_phase,"active_case_wall_seconds":float(Time.get_ticks_msec()-presence_case_start_ms)/1000.,"active_case_physics_ticks":presence_tick_count,"active_case_sum_physics_delta_s":presence_physics_delta_sum_s,"active_case_render_frames_after_warmup":presence_render_count,"active_case_focused_render_frames_after_warmup":presence_focused_render_count,"last_clock_checkpoint":event});_finish()

func _presence_wait(count: int) -> void:
	for index: int in range(count):await physics_frame;await process_frame

func _presence_bone_difference(a: Transform3D,b: Transform3D) -> Dictionary:
	return {"position_m":a.origin.distance_to(b.origin),"basis":maxf(a.basis.x.distance_to(b.basis.x),maxf(a.basis.y.distance_to(b.basis.y),a.basis.z.distance_to(b.basis.z)))}

func _observe_physics(delta: float) -> void:
	if not is_instance_valid(avatar) or presence_nodes.is_empty():return
	var next: Array[Transform3D]=[]
	for node: Node3D in presence_nodes:next.append(node.transform)
	var next_gait:={"stride_phase":float(avatar.get("stride_phase")),"walk_weight":float(avatar.get("walk_weight")),"run_weight":float(avatar.get("_run_weight")),"state":String(avatar.get("state")),"activity":String(avatar.get("_activity_kind")),"facility_control":bool(player.get("facility_control"))}
	presence_previous_gait=presence_current_gait.duplicate() if presence_history_ready else next_gait.duplicate()
	presence_current_gait=next_gait
	presence_previous=presence_current.duplicate() if presence_history_ready else next.duplicate()
	presence_current=next
	presence_previous_root=presence_current_root if presence_history_ready else avatar.global_transform
	presence_current_root=avatar.global_transform
	presence_camera_previous=presence_camera_current if presence_history_ready else rig._physics_pose
	presence_camera_current=rig._physics_pose
	presence_history_ready=true
	if presence_phase.is_empty():return
	presence_tick_count+=1
	presence_physics_delta_sum_s+=delta
	var yaw: float=player.get_node("Visual").rotation.y
	var yaw_step:=absf(angle_difference(presence_last_yaw,yaw));presence_last_yaw=yaw
	if presence_tick_count<=5:return
	var upper: Node3D=avatar._upper_body
	presence_min_torso_y=minf(presence_min_torso_y,upper.position.y);presence_max_torso_y=maxf(presence_max_torso_y,upper.position.y)
	presence_max_roll=maxf(presence_max_roll,absf(upper.rotation.z))
	presence_max_yaw_step=maxf(presence_max_yaw_step,yaw_step)
	var speed:=Vector2(player.velocity.x,player.velocity.z).length()
	var alignment:=0.0
	if speed>.30:
		alignment=absf(angle_difference(yaw,atan2(-player.velocity.x,-player.velocity.z)))
		presence_max_angle_alignment=maxf(presence_max_angle_alignment,alignment)
	var eye_offset: float=rig._physics_pose.origin.y-player.global_position.y
	presence_min_eye_offset=minf(presence_min_eye_offset,eye_offset);presence_max_eye_offset=maxf(presence_max_eye_offset,eye_offset)
	for index: int in range(presence_nodes.size()):
		var difference:=_presence_bone_difference(presence_previous[index],presence_current[index])
		if float(difference.position_m)>.0001 or float(difference.basis)>.0001:presence_joint_changed=true
	if presence_physics.size()<90:
		presence_physics.append({"physics_frame":Engine.get_physics_frames(),"elapsed_wall_seconds":float(Time.get_ticks_msec()-presence_started_ms)/1000.,"physics_delta_s":delta,"position":player.global_position,"velocity":player.velocity,"visual_yaw":yaw,"heading_velocity_difference_radians":alignment,"upper_body":upper.transform,"eye_offset_m":eye_offset,"grounded":player.is_on_floor(),"state":avatar.state,"independent_physics_gait":next_gait})

func _observe_render(delta: float) -> void:
	if presence_phase.is_empty() or presence_tick_count<=5 or not presence_history_ready:return
	var observed_usec:=Time.get_ticks_usec()
	if presence_render_count==0:presence_render_first_usec=observed_usec
	presence_render_last_usec=observed_usec
	presence_render_delta_sum_s+=delta;presence_render_count+=1
	if DisplayServer.get_name()!="headless" and DisplayServer.window_is_focused():presence_focused_render_count+=1
	var fraction:=clampf(Engine.get_physics_interpolation_fraction(),0.,1.)
	var fraction_bin:=int(floor(fraction*5.))
	presence_fraction_bins[fraction_bin]=int(presence_fraction_bins.get(fraction_bin,0))+1
	var fixed_activity: bool=rig.get("_facility_mode")==true or rig.get("_moving_attachment")==true
	var max_position:=0.0;var max_basis:=0.0;var intermediate:=false
	var local_rows: Array=[]
	var analytic:={}
	# Independently recorded physical fields drive the stated display contract.
	# Do not use render metadata or call production gait_support_wave here.
	if not fixed_activity and not presence_current_gait.is_empty() and String(presence_current_gait.state) in ["idle","walk","run"] and String(presence_current_gait.activity).is_empty() and not bool(presence_current_gait.facility_control):
		var before_phase: float=presence_previous_gait.stride_phase
		var interpolated_phase:=before_phase+fposmod(float(presence_current_gait.stride_phase)-before_phase,TAU)*fraction
		var interpolated_run:=lerpf(float(presence_previous_gait.run_weight),float(presence_current_gait.run_weight),fraction)
		var interpolated_walk:=lerpf(float(presence_previous_gait.walk_weight),float(presence_current_gait.walk_weight),fraction)
		var expected_y:=EXPECTED_HIP_MARKER_Y_M-lerpf(EXPECTED_WALK_SUPPORT_HALF_AMPLITUDE_M,EXPECTED_RUN_SUPPORT_HALF_AMPLITUDE_M,clampf(interpolated_run,0.,1.))*(1.+cos(2.*interpolated_phase))*clampf(interpolated_walk,0.,1.)
		analytic={"expected_y_m":expected_y,"unwrapped_phase_radians":interpolated_phase,"interpolated_run_weight":interpolated_run,"interpolated_walk_weight":interpolated_walk,"previous_independent_physics_gait":presence_previous_gait,"current_independent_physics_gait":presence_current_gait,"oracle":"Independently recorded physical phase/weights and declared .978m hip marker minus .016/.024m half-amplitude cosine support wave; no production helper/metadata read."}
	for index: int in range(presence_nodes.size()):
		var expected: Transform3D=presence_current[index] if fixed_activity else presence_previous[index].interpolate_with(presence_current[index],fraction)
		var linear_expected:=expected
		if presence_node_names[index]=="Pelvis" and not analytic.is_empty():expected.origin.y=float(analytic.expected_y_m)
		var actual: Transform3D=presence_nodes[index].transform
		if presence_node_names[index]=="Pelvis" and not analytic.is_empty():
			presence_analytic_pelvis_samples+=1
			var linear_difference:=absf(expected.origin.y-linear_expected.origin.y)
			if fraction>.15 and fraction<.85 and linear_difference>.0003:presence_analytic_pelvis_nontrivial_samples+=1
			presence_analytic_pelvis_maximum_error_m=maxf(presence_analytic_pelvis_maximum_error_m,absf(actual.origin.y-expected.origin.y))
			presence_analytic_pelvis_maximum_linear_difference_m=maxf(presence_analytic_pelvis_maximum_linear_difference_m,linear_difference)
		var difference:=_presence_bone_difference(actual,expected)
		max_position=maxf(max_position,float(difference.position_m));max_basis=maxf(max_basis,float(difference.basis))
		var endpoint_difference:=_presence_bone_difference(presence_previous[index],presence_current[index])
		if not fixed_activity and fraction>.15 and fraction<.85 and float(endpoint_difference.basis)>.015:
			var from_previous:=_presence_bone_difference(actual,presence_previous[index]);var from_current:=_presence_bone_difference(actual,presence_current[index])
			if float(from_previous.basis)>.001 and float(from_current.basis)>.001:intermediate=true
		if presence_render.size()<12 and (index<6 or presence_node_names[index]=="Pelvis"):
			local_rows.append({"name":presence_node_names[index],"actual":actual,"previous_physical":presence_previous[index],"current_physical":presence_current[index],"expected_at_fraction":expected,"linear_expected_at_fraction":linear_expected,"analytic_pelvis_contract":analytic if presence_node_names[index]=="Pelvis" else {},"independent_fraction_0":presence_previous[index].interpolate_with(presence_current[index],0.),"independent_fraction_half":presence_previous[index].interpolate_with(presence_current[index],.5),"independent_fraction_1":presence_previous[index].interpolate_with(presence_current[index],1.)})
	presence_observed_intermediate=presence_observed_intermediate or intermediate
	presence_max_joint_position_error=maxf(presence_max_joint_position_error,max_position);presence_max_joint_basis_error=maxf(presence_max_joint_basis_error,max_basis)
	var root_expected:=presence_previous_root.interpolate_with(presence_current_root,fraction)
	var root_actual: Transform3D=_anchor().global_transform
	presence_max_root_error=maxf(presence_max_root_error,root_actual.origin.distance_to(root_expected.origin))
	var camera_expected:=presence_camera_previous.interpolate_with(presence_camera_current,fraction)
	# The same independently recorded physical eye and avatar histories expose
	# render-clock mismatch without relying on the rig's _render_pose helper.
	var relative_error: float=(rig.camera.global_position-root_actual.origin).distance_to(camera_expected.origin-root_expected.origin)
	presence_max_eye_relative_error=maxf(presence_max_eye_relative_error,relative_error)
	presence_max_raw_root_error=maxf(presence_max_raw_root_error,player.get_node("Visual").global_position.distance_to(player.global_position))
	if presence_phase=="attached_bicycle_current_props" and not presence_bicycle_row.is_empty():
		presence_bicycle_render_samples+=1
		for side_index: int in range(2):
			var side_name: String="Left" if side_index==0 else "Right";var side: float=-1. if side_index==0 else 1.
			var sole: Vector3=avatar._joints[side_name+"Foot"].to_global(Vector3(0.,-.1145,-.06))
			var pedal: Vector3=presence_bicycle_row.crank.to_global(Vector3(side*.20,0.,side*.155))+presence_bicycle_row.proxy.global_basis.y*.0175
			presence_bicycle_max_sole_height_error=maxf(presence_bicycle_max_sole_height_error,absf((sole-pedal).dot(presence_bicycle_row.proxy.global_basis.y)))
			var grip: Vector3=presence_bicycle_row.front.to_global(Vector3(side*.265,1.20,.36))
			presence_bicycle_max_hand_error=maxf(presence_bicycle_max_hand_error,avatar._hands[side_index].global_position.distance_to(grip))
	if presence_render.size()<90:
		presence_render.append({"process_frame":Engine.get_process_frames(),"elapsed_wall_seconds":float(Time.get_ticks_msec()-presence_started_ms)/1000.,"process_delta_s":delta,"window_focused":DisplayServer.window_is_focused() if DisplayServer.get_name()!="headless" else false,"fraction":fraction,"actual_camera":rig.camera.global_transform,"independent_camera":camera_expected,"actual_visible_anchor":root_actual,"independent_visible_anchor":root_expected,"maximum_local_joint_position_error_m":max_position,"maximum_local_joint_basis_error":max_basis,"moving_joint_is_between_endpoints":intermediate,"fixed_activity":fixed_activity,"independent_analytic_pelvis":analytic,"joints":local_rows})
	if presence_moving_v_pending and intermediate:_presence_apply_moving_v(fraction)
	if presence_paused_teleport_pending and intermediate:_presence_apply_paused_teleport(fraction)

func _presence_apply_moving_v(fraction: float) -> void:
	# Run after the real camera and avatar renderer, at an observed intermediate
	# display fraction. Calling the same public V action must restore physical
	# joints before collapsing history, rather than promote displayed IK to it.
	presence_moving_v_pending=false;presence_phase=""
	var at: Vector3=player.global_position;var velocity_before: Vector3=player.velocity
	var displayed_before: Array[Transform3D]=[]
	for node: Node3D in presence_nodes:displayed_before.append(node.transform)
	rig.use_human_eye_view()
	var maximum_position:=0.0;var maximum_basis:=0.0;var maximum_display_physics_difference:=0.0
	for index: int in range(presence_nodes.size()):
		var difference:=_presence_bone_difference(presence_nodes[index].transform,presence_current[index])
		maximum_position=maxf(maximum_position,float(difference.position_m));maximum_basis=maxf(maximum_basis,float(difference.basis))
		var previous_difference:=_presence_bone_difference(displayed_before[index],presence_current[index])
		maximum_display_physics_difference=maxf(maximum_display_physics_difference,float(previous_difference.basis))
	presence_moving_v_result={"observed_fraction":fraction,"velocity_before":velocity_before,"velocity_after":player.velocity,"player_before":at,"player_after":player.global_position,"maximum_local_position_error_against_independent_physical_pose_m":maximum_position,"maximum_local_basis_error_against_independent_physical_pose":maximum_basis,"maximum_displayed_vs_physical_basis_difference_before_reset":maximum_display_physics_difference,"collapsed_joint_histories":rig._previous_joint_poses==rig._physics_joint_poses,"default_camera":rig.snapshot()}
	_check("view.moving_human_reset_restores_physical_joints_before_history_capture",maximum_display_physics_difference>.001 and maximum_position<.0003 and maximum_basis<.0005 and rig._previous_joint_poses==rig._physics_joint_poses,presence_moving_v_result)
	_check("view.moving_human_reset_preserves_actual_momentum_capsule_and_human_eye",Vector2(velocity_before.x,velocity_before.z).length()>1. and velocity_before==player.velocity and at==player.global_position and _capsule()==initial_capsule and absf(rig.requested_distance-3.4)<.0001 and absf(rig._physics_pose.origin.y-player.global_position.y-presence_eye_baseline)<.003,presence_moving_v_result)

func _presence_reset_observation(title: String) -> void:
	presence_phase=title;presence_tick_count=0;presence_physics=[];presence_render=[];presence_fraction_bins={}
	presence_case_start_ms=Time.get_ticks_msec();presence_case_physics_start=Engine.get_physics_frames();presence_case_process_start=Engine.get_process_frames()
	presence_case_draw_start=Engine.get_frames_drawn();presence_render_first_usec=0;presence_render_last_usec=0
	presence_physics_delta_sum_s=0.;presence_render_delta_sum_s=0.;presence_render_count=0;presence_focused_render_count=0
	presence_max_joint_position_error=0.;presence_max_joint_basis_error=0.;presence_max_root_error=0.;presence_max_eye_relative_error=0.;presence_max_raw_root_error=0.
	presence_min_torso_y=INF;presence_max_torso_y=-INF;presence_max_roll=0.;presence_max_yaw_step=0.;presence_max_angle_alignment=0.
	presence_min_eye_offset=INF;presence_max_eye_offset=-INF;presence_joint_changed=false;presence_observed_intermediate=false
	presence_last_yaw=player.get_node("Visual").rotation.y
	_presence_checkpoint("case_begin")

func _presence_end_case(title: String,start: Vector3,recovery_before: int,expect_motion:=true,expect_level_eye:=true,expect_local_intermediate:=true) -> void:
	presence_phase=""
	var row:={"name":title,"physics_hz":presence_physics_hz,"render_cap_fps":presence_render_cap,"physical_ticks":presence_tick_count,"physics_samples_saved":presence_physics.size(),"render_samples_saved":presence_render.size(),"actual_travel_m":player.global_position.distance_to(start),"local_joint_count":presence_nodes.size(),"maximum_local_joint_position_error_m":presence_max_joint_position_error,"maximum_local_joint_basis_error":presence_max_joint_basis_error,"maximum_visible_root_error_m":presence_max_root_error,"maximum_eye_avatar_clock_error_m":presence_max_eye_relative_error,"maximum_unmodified_Visual_root_error_m":presence_max_raw_root_error,"torso_local_y_range_m":[presence_min_torso_y,presence_max_torso_y],"maximum_torso_roll_radians":presence_max_roll,"maximum_yaw_step_radians":presence_max_yaw_step,"maximum_heading_velocity_difference_radians":presence_max_angle_alignment,"eye_height_over_physical_feet_range_m":[presence_min_eye_offset,presence_max_eye_offset],"render_fraction_bins":presence_fraction_bins.keys(),"joint_changed_in_physics":presence_joint_changed,"actual_moving_joint_between_endpoints":presence_observed_intermediate,"physics_rows":presence_physics,"render_rows":presence_render}
	presence_cases.append(row)
	row["timing"]={"wall_seconds":float(Time.get_ticks_msec()-presence_case_start_ms)/1000.,"physics_frame_delta":Engine.get_physics_frames()-presence_case_physics_start,"process_frame_delta":Engine.get_process_frames()-presence_case_process_start,"sum_observed_physics_delta_seconds":presence_physics_delta_sum_s,"sum_observed_render_delta_seconds_after_warmup":presence_render_delta_sum_s,"observed_render_frames_after_warmup":presence_render_count,"focused_render_frames_after_warmup":presence_focused_render_count,"scope":"Short actual fixture scheduling observation including warmup and any capture wait. These are diagnostic clocks and frame counts, not sustained game FPS or a performance pass criterion."}
	row["timing"]["frames_drawn_delta"]=Engine.get_frames_drawn()-presence_case_draw_start
	row["timing"]["observed_process_first_to_last_wall_seconds"]=float(presence_render_last_usec-presence_render_first_usec)/1000000. if presence_render_count>1 else 0.
	row["timing"]["observed_process_intervals_per_wall_second"]=float(presence_render_count-1)*1000000./float(presence_render_last_usec-presence_render_first_usec) if presence_render_count>1 and presence_render_last_usec>presence_render_first_usec else 0.
	row["render_fraction_bin_counts"]=presence_fraction_bins.duplicate()
	row["window_scheduling"]=_presence_window_scheduling()
	_presence_checkpoint("case_end."+title)
	_check(title+".independent_local_joint_render_interpolation_matches_actual_nodes",presence_tick_count>15 and presence_render.size()>=8 and presence_max_joint_position_error<.0003 and presence_max_joint_basis_error<.0005 and (presence_joint_changed or not expect_motion),row)
	_check(title+".eye_body_same_clock_and_original_physical_roots_unchanged",presence_max_root_error<.002 and presence_max_eye_relative_error<.002 and presence_max_raw_root_error<.0001 and player.recoveries==recovery_before and _capsule()==initial_capsule,{"root_error_m":presence_max_root_error,"eye_avatar_clock_error_m":presence_max_eye_relative_error,"raw_Visual_error_m":presence_max_raw_root_error,"recovery_delta":player.recoveries-recovery_before})
	var eye_stable:=not expect_level_eye or (absf(presence_max_eye_offset-presence_min_eye_offset)<.003 and absf(presence_min_eye_offset-presence_eye_baseline)<.015)
	_check(title+".no_added_torso_roll_bob_or_camera_stride_bounce",absf(presence_min_torso_y-.85)<.0001 and absf(presence_max_torso_y-.85)<.0001 and presence_max_roll<.0001 and eye_stable,{"torso_y_range_m":[presence_min_torso_y,presence_max_torso_y],"torso_roll":presence_max_roll,"eye_offset_range_m":[presence_min_eye_offset,presence_max_eye_offset],"expected_eye_height_m":presence_eye_baseline})
	if presence_render_cap==144 and expect_motion and expect_local_intermediate:
		_check(title+".actual_render_frames_exercise_intermediate_joint_poses",presence_fraction_bins.size()>=3 and presence_observed_intermediate,{"fraction_bins":presence_fraction_bins.keys(),"actual_moving_joint_between_endpoints":presence_observed_intermediate})

func _presence_place(at: Vector3) -> void:
	presence_phase="";_keys([]);player.set_facility_control(false);avatar.set_activity("",0.)
	_presence_checkpoint("placement_begin")
	player.global_transform=Transform3D(Basis.IDENTITY,at);player.velocity=Vector3.ZERO;player.get_node("Visual").rotation=Vector3.ZERO
	player.require_neutral_input();player.reset_physics_interpolation();rig.use_human_eye_view()
	await _presence_wait(15)
	_presence_checkpoint("placement_end")
	_check("placement."+str(checks.size())+".actual_native_floor_and_neutral_input",player.is_on_floor() and not player.input_latched,{"point":player.global_position})

func _presence_motion(title: String,actions: Array,seconds: float,photo:=false) -> void:
	await _presence_place(Vector3(-25,.08,-25));var before: int=player.recoveries;var start: Vector3=player.global_position
	_presence_reset_observation(title);_keys(actions);await _presence_wait(int(ceil(seconds*presence_physics_hz)))
	if photo:await _presence_capture(title)
	_presence_end_case(title,start,before)
	_keys([]);await _presence_wait(int(ceil(.45*presence_physics_hz)))

func _presence_turn(title: String,second: String,photo:=false) -> void:
	await _presence_place(Vector3(-25,.08,-25));_keys(["move_forward"]);await _presence_wait(int(ceil(.7*presence_physics_hz)))
	var before: int=player.recoveries;var start: Vector3=player.global_position
	_presence_reset_observation(title);_keys([second]);await _presence_wait(int(ceil(1.3*presence_physics_hz)))
	if photo:await _presence_capture(title)
	_presence_end_case(title,start,before)
	_check(title+".body_turn_has_bounded_physical_tick_angle",presence_max_yaw_step<=float(player.turn_speed_radians)/float(presence_physics_hz)+.003,{"maximum_yaw_step_radians":presence_max_yaw_step,"retained_maximum_radians_s":player.turn_speed_radians,"physics_hz":presence_physics_hz})
	_keys([]);await _presence_wait(int(ceil(.45*presence_physics_hz)))

func _presence_capture(title: String) -> void:
	if DisplayServer.get_name()=="headless":return
	# macOS can stop ordinary draws when a window is occluded while process and
	# physics still run. Request a real GPU draw rather than await an event that
	# cannot arrive; this changes no production transform or render fraction.
	await process_frame;RenderingServer.force_draw()
	var path:=report_path.get_basename()+"_"+title+".png";var pixels:=root.get_texture().get_image();var code:=pixels.save_png(path)
	_check("native.actual_camera_"+title+"_image",code==OK and not pixels.is_empty(),{"file":path,"camera":rig.camera.global_transform,"player":player.global_position,"capture_method":"RenderingServer.force_draw after actual process_frame; no production camera, joint transform or render-fraction write","scope":"Controlled native GPU draw of unmodified production exploration Camera3D; no independent review camera or artificial render fraction used."})
	if code==OK:presence_captures.append({"file":path,"sha256":FileAccess.get_sha256(path),"camera":rig.camera.global_transform,"player":player.global_position,"capture_method":"RenderingServer.force_draw after actual process_frame"})

func _presence_eye_samples() -> Dictionary:
	var bad:=0;var invalid:=0;var minimum_y:=INF;var rows: Array=[]
	for fraction: float in [0.,.25,.5,.75,1.]:
		var pose: Transform3D=rig._previous_pose.interpolate_with(rig._physics_pose,fraction)
		var overlap:=_overlaps(pose.origin)
		if overlap:bad+=1
		if not pose.origin.is_finite() or not pose.basis.is_finite() or pose.basis.y.dot(Vector3.UP)<=0.:invalid+=1
		minimum_y=minf(minimum_y,pose.origin.y)
		rows.append({"fraction":fraction,"pose":pose,"overlap":overlap})
	return {"overlaps":bad,"invalid_or_inverted":invalid,"minimum_eye_world_y_m":minimum_y,"samples":rows}

func _presence_basics() -> void:
	await _presence_place(Vector3(0,.08,0))
	presence_eye_baseline=1.2+3.4*sin(deg_to_rad(7.))
	var actual_height: float=rig.camera.global_position.y-player.global_position.y
	_check("view.actual_eye_is_approximately_adult_1_614m_with_visible_third_person_body",absf(actual_height-presence_eye_baseline)<.003 and absf(rig.pivot_height_m-1.2)<.0001 and absf(rig.requested_distance-3.4)<.0001 and absf(rig.pitch-deg_to_rad(-7.))<.0001 and player.get_node("Visual").visible,{"actual_eye_over_feet_m":actual_height,"expected_eye_m":presence_eye_baseline,"pivot_m":rig.pivot_height_m,"distance_m":rig.current_distance,"pitch_degrees":rad_to_deg(rig.pitch),"fov":rig.camera.fov})
	_check("view.one_transform_owner_and_unchanged_clipping_safety",rig.camera.top_level and not rig.arm.is_physics_processing_internal() and absf(rig.camera.fov-62.)<.001 and rig.camera.near>=.079 and rig.camera.far>=1400.,rig.snapshot())
	var size:=root.get_visible_rect().size;var half_height: float=rig.camera.near*tan(deg_to_rad(rig.camera.fov)*.5)
	var near_corner:=Vector3(half_height*size.x/size.y,half_height,rig.camera.near).length()
	_check("view.probe_sphere_contains_whole_near_plane_for_current_fov",near_corner<float(rig.arm.shape.radius),{"near_frustum_corner_distance_m":near_corner,"collision_probe_radius_m":rig.arm.shape.radius,"aspect":size.x/size.y})
	_check("view.local_joint_history_ready_without_added_physics_objects",rig.get("_joint_nodes") is Array and rig._joint_nodes.size()==presence_nodes.size() and rig._previous_joint_poses.size()==presence_nodes.size() and rig._physics_joint_poses.size()==presence_nodes.size() and avatar.find_children("*","CollisionObject3D",true,false).is_empty(),{"independent_node_count":presence_nodes.size(),"camera_state":rig.snapshot()})
	rig.automatic_probe=true;rig.set_capture(true)
	var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true;wheel.device=42
	Input.parse_input_event(wheel);await _presence_wait(3)
	_check("view.actual_wheel_event_retains_user_third_person_zoom",rig.requested_distance>3.4 and rig.requested_distance<=rig.distance_max_m,{"requested_distance_after_wheel_m":rig.requested_distance})
	rig.use_human_eye_view();await _presence_wait(3)
	_check("view.human_view_action_restores_collision_solved_default_without_new_owner",absf(rig.requested_distance-3.4)<.0001 and absf(rig.camera.global_position.y-player.global_position.y-presence_eye_baseline)<.003 and _capsule()==initial_capsule,rig.snapshot())
	await _presence_capture("default_eye_height_third_person")

func _presence_moving_reset() -> void:
	Engine.physics_ticks_per_second=30;Engine.max_fps=144;presence_physics_hz=30;presence_render_cap=144
	await _presence_place(Vector3(-20,.08,-20));_keys(["move_forward","move_fast"]);await _presence_wait(20)
	rig.requested_distance=4.8;await _presence_wait(12)
	presence_moving_v_result={};_presence_reset_observation("moving_public_human_view_reset");presence_moving_v_pending=true
	for index: int in range(240):
		if not presence_moving_v_pending:break
		await process_frame
	if presence_moving_v_pending:
		presence_moving_v_pending=false;presence_phase=""
		_check("view.moving_human_reset_restores_physical_joints_before_history_capture",false,{"reason":"No actual moving intermediate render fraction observed in bounded 240 process frames"})
		_check("view.moving_human_reset_preserves_actual_momentum_capsule_and_human_eye",false,{"reason":"Prerequisite intermediate render observation absent"})
	_keys([]);await _presence_wait(15)

func _presence_physical_joint_world(node: Node3D) -> Transform3D:
	# Compose authored locals in physical avatar space. The presentation proxy
	# is intentionally omitted, independently of camera history/metadata.
	var chain: Array[Transform3D]=[];var cursor: Node=node
	var proxy:=avatar.get_node_or_null("RenderProxy")
	while cursor!=null and cursor!=avatar:
		if cursor is Node3D and cursor!=proxy:chain.append((cursor as Node3D).transform)
		cursor=cursor.get_parent()
	var value:=avatar.global_transform
	for index: int in range(chain.size()-1,-1,-1):value=value*chain[index]
	return value

func _presence_apply_paused_teleport(fraction: float) -> void:
	presence_paused_teleport_pending=false;presence_phase=""
	var displayed_difference:=0.
	for index: int in range(presence_nodes.size()):displayed_difference=maxf(displayed_difference,float(_presence_bone_difference(presence_nodes[index].transform,presence_current[index]).basis))
	var root_before:=_anchor().global_transform;var metadata_before:=avatar.has_meta("render_gait_foot_goals_world") or avatar.has_meta("render_gait_state")
	var old_position:=player.global_position
	paused=true
	player.global_position+=Vector3(17.,0.,-13.);player.velocity=Vector3.ZERO
	player.require_neutral_input();player.reset_physics_interpolation()
	# A portal/activity service may author the destination pose before snapping.
	# Restoring an older camera joint array here would discard that new pose.
	avatar._rest_pose()
	var authored: Array[Transform3D]=[]
	for node: Node3D in presence_nodes:authored.append(node.transform)
	var expected_feet:={}
	for side: String in ["Left","Right"]:expected_feet[side]=_presence_physical_joint_world(avatar._joints[side+"Foot"]).origin
	rig.snap_to_target_pose()
	var maximum_position:=0.;var maximum_basis:=0.;var maximum_foot_error:=0.;var maximum_actual_foot_error:=0.;var foot_rows:={}
	for index: int in range(presence_nodes.size()):
		var difference:=_presence_bone_difference(presence_nodes[index].transform,authored[index])
		maximum_position=maxf(maximum_position,float(difference.position_m));maximum_basis=maxf(maximum_basis,float(difference.basis))
	for side: String in ["Left","Right"]:
		var published: Vector3=rig._physics_foot_goals.get(side,Vector3.INF)
		var error:=published.distance_to(Vector3(expected_feet[side]));maximum_foot_error=maxf(maximum_foot_error,error)
		var actual: Vector3=avatar._joints[side+"Foot"].global_position
		maximum_actual_foot_error=maxf(maximum_actual_foot_error,actual.distance_to(Vector3(expected_feet[side])))
		foot_rows[side]={"independent_destination_physical_foot_world":expected_feet[side],"published_physics_foot_world":published,"actual_displayed_foot_world":actual,"published_error_m":error}
	var cleared:=not avatar.has_meta("render_gait_foot_goals_world") and not avatar.has_meta("render_gait_state")
	presence_paused_teleport_result={"observed_intermediate_fraction":fraction,"displayed_vs_physical_basis_difference_before_pause":displayed_difference,"render_metadata_existed_before_pause":metadata_before,"old_player_position":old_position,"destination_player_position":player.global_position,"old_displayed_root":root_before,"destination_displayed_root":_anchor().global_transform,"destination_physical_avatar":avatar.global_transform,"maximum_authored_local_position_error_m":maximum_position,"maximum_authored_local_basis_error":maximum_basis,"maximum_published_foot_error_m":maximum_foot_error,"maximum_displayed_foot_error_m":maximum_actual_foot_error,"old_render_metadata_cleared":cleared,"joint_histories_collapsed":rig._previous_joint_poses==rig._physics_joint_poses,"world_foot_histories_collapsed":rig._previous_foot_goals==rig._physics_foot_goals,"foot_rows":foot_rows,"physics_frame":Engine.get_physics_frames(),"tree_paused":paused}
	_check("menu.paused_midstride_teleport_preserves_new_authored_pose_and_collapses_history",displayed_difference>.001 and paused and maximum_position<.0003 and maximum_basis<.0005 and rig._previous_joint_poses==rig._physics_joint_poses and _anchor().global_position.distance_to(avatar.global_position)<.0003 and rig._previous_pose.origin.distance_to(rig._physics_pose.origin)<.0003,presence_paused_teleport_result)
	_check("menu.paused_midstride_teleport_reseeds_world_foot_goals_and_clears_old_render_metadata",metadata_before and cleared and maximum_foot_error<.0003 and maximum_actual_foot_error<.0003 and rig._previous_foot_goals==rig._physics_foot_goals,presence_paused_teleport_result)

func _presence_paused_midstride_teleport() -> void:
	Engine.physics_ticks_per_second=30;Engine.max_fps=144;presence_physics_hz=30;presence_render_cap=144
	await _presence_place(Vector3(-60,.08,-60));_keys(["move_forward","move_fast"]);await _presence_wait(24)
	presence_paused_teleport_result={};_presence_reset_observation("paused_midstride_teleport");presence_paused_teleport_pending=true
	for index: int in range(240):
		if not presence_paused_teleport_pending:break
		await process_frame
	if presence_paused_teleport_pending:
		presence_paused_teleport_pending=false;presence_phase=""
		_check("menu.paused_midstride_teleport_preserves_new_authored_pose_and_collapses_history",false,{"reason":"No moving intermediate render observation within240processframes"})
		_check("menu.paused_midstride_teleport_reseeds_world_foot_goals_and_clears_old_render_metadata",false,{"reason":"Prerequisite intermediate render observation absent"})
	_keys([])
	for index: int in range(3):await process_frame
	paused=false;await _presence_wait(15)

func _presence_door() -> void:
	await _presence_place(Vector3(0,.08,-1.));var before: int=player.recoveries;var overlaps:=0;var invalid:=0;var rows: Array=[]
	_keys(["move_forward"])
	for index: int in range(110):
		await _presence_wait(1);var row:=_presence_eye_samples();overlaps+=int(row.overlaps);invalid+=int(row.invalid_or_inverted)
		if index%10==0:rows.append({"player":player.global_position,"camera":rig.camera.global_transform,"fractional_sphere_samples":row})
	_keys([]);await _presence_wait(12)
	_check("safety.actual_adult_capsule_walks_under_2_20m_lintel_and_through_1_20m_door",player.global_position.z<-5. and player.is_on_floor() and player.recoveries==before and _capsule()==initial_capsule,{"end":player.global_position,"clear_door_width_height_m":[1.2,2.2],"native_door_transform":door.global_transform})
	_check("safety.human_eye_and_every_fraction_remain_clear_across_real_doorway",overlaps==0 and invalid==0,{"fractional_eye_sphere_samples":550,"overlaps":overlaps,"invalid":invalid,"selected_rows":rows})
	await _presence_capture("actual_eye_through_adult_doorway")

func _presence_safety() -> void:
	Engine.physics_ticks_per_second=30;Engine.max_fps=144;presence_physics_hz=30;presence_render_cap=144
	var wall:=_solid("PresenceCameraWall",Vector3(10,4,.4),Vector3(0,2,2.4))
	var corner:=_solid("PresenceCameraCorner",Vector3(.4,4,5),Vector3(-4.8,2,4.7))
	await _presence_place(Vector3(0,.08,0))
	var blocked_distance: float=rig.current_distance;var overlaps:=0;var invalid:=0;var samples:=0
	for index: int in range(72):
		rig.yaw=wrapf(rig.yaw+TAU/72.,-PI,PI);await _presence_wait(1)
		var row:=_presence_eye_samples();overlaps+=int(row.overlaps);invalid+=int(row.invalid_or_inverted);samples+=5
	_check("safety.real_wall_orbit_keeps_all_fractional_eye_spheres_clear",blocked_distance<2.3 and overlaps==0 and invalid==0,{"initial_retracted_distance_m":blocked_distance,"eye_sphere_samples":samples,"overlaps":overlaps,"invalid":invalid})
	await _presence_capture("wall_obstruction_orbit")
	await _presence_place(Vector3(-4.1,.08,1.55));overlaps=0;invalid=0
	for index: int in range(48):
		rig.yaw=wrapf(rig.yaw+TAU/48.,-PI,PI);await _presence_wait(1)
		var row:=_presence_eye_samples();overlaps+=int(row.overlaps);invalid+=int(row.invalid_or_inverted)
	_check("safety.real_corner_orbit_never_interpolates_through_native_wall",overlaps==0 and invalid==0,{"samples":240,"overlaps":overlaps,"invalid":invalid})
	wall.free();corner.free();await _presence_wait(3)
	await _presence_place(Vector3(0,.08,0))
	var old_eye: Vector3=rig._physics_pose.origin
	var snaps_before: int=rig.transition_snaps
	var new_obstacle:=_solid("PresenceNewObstacleAtFormerEye",Vector3(.7,.7,.7),old_eye)
	await _presence_wait(2);var corrected:=_presence_eye_samples()
	_check("safety.starting_eye_overlap_collapses_history_to_new_clear_pose",_overlaps(old_eye) and int(corrected.overlaps)==0 and rig.transition_snaps>snaps_before and rig.current_distance<3.1,{"old_eye":old_eye,"transition_snap_delta":rig.transition_snaps-snaps_before,"corrected_fraction_samples":corrected,"snapshot":rig.snapshot()})
	new_obstacle.free();await _presence_wait(3)
	await _presence_place(Vector3(0,.08,0));rig.pitch=deg_to_rad(rig.pitch_max_degrees);await _presence_wait(4)
	var low:=_presence_eye_samples()
	_check("safety.lowest_user_pitch_keeps_native_ground_outside_eye_probe",int(low.overlaps)==0 and int(low.invalid_or_inverted)==0 and float(low.minimum_eye_world_y_m)>=.19,low)
	var parapet:=_solid("PresenceExplicitRoofParapet",Vector3(5,1.55,.35),Vector3(0,.775,1.12))
	await _presence_place(Vector3(0,.08,0))
	var before_hint: float=rig.current_distance
	for index: int in range(10):
		rig.set_roof_camera_hint({"minimum_pivot_y_world":player.global_position.y+2.10,"maximum_raise_m":1.2,"building_id":"explicit_roof_fixture","basis":"Native floor and explicit 1.55m parapet, camera-only test fixture"});await _presence_wait(1)
	var raised:=_presence_eye_samples()
	_check("safety.bounded_fresh_roof_hint_only_raises_through_clear_native_corridor",before_hint<1.8 and rig._roof_camera_fallback and rig._roof_pivot_offset_m>.8 and rig._roof_pivot_offset_m<=1.2 and rig.current_distance>=1.8 and int(raised.overlaps)==0,{"distance_before_hint_m":before_hint,"samples":raised,"snapshot":rig.snapshot()})
	await _presence_capture("bounded_roof_hint_clearance")
	await _presence_wait(6)
	_check("safety.stale_roof_hint_is_rejected_and_not_kept_as_street_eye_height",not rig._roof_camera_fallback and rig._roof_pivot_offset_m==0. and rig.current_distance<1.8,rig.snapshot())
	parapet.free();await _presence_wait(3);await _presence_place(Vector3(0,.08,0))
	var regions: Array[Rect2]=[Rect2(-250,-250,500,500)]
	player.configure_recovery(Vector3(80,.08,0),regions);var recovered: bool=player.recover("human_presence_explicit_recovery_fixture")
	await rig.camera_stepped
	_check("safety.actual_recovery_collapses_camera_and_joint_histories",recovered and rig._previous_pose.origin.distance_to(rig._physics_pose.origin)<.001 and _anchor().global_position.distance_to(avatar.global_position)<.001 and rig._previous_joint_poses==rig._physics_joint_poses,{"recovery_accepted":recovered,"camera_history_separation_m":rig._previous_pose.origin.distance_to(rig._physics_pose.origin),"joint_history_equal":rig._previous_joint_poses==rig._physics_joint_poses})
	await _presence_wait(4)

func _presence_facility_and_pause() -> void:
	await _presence_place(Vector3(-10,.08,-10));player.set_facility_control(true);avatar.set_activity("weights",.8);await _presence_wait(6)
	var at: Vector3=player.global_position;var before: int=player.recoveries
	_presence_reset_observation("fixed_facility_current_joint_contacts");await _presence_wait(30)
	_presence_end_case("fixed_facility_current_joint_contacts",at,before,false)
	_check("facility.physics_hand_contacts_are_current_without_render_lag",rig._facility_mode and rig._avatar_root==avatar and avatar._activity_kind=="weights" and not avatar._hands[0].visible,{"camera":rig.snapshot(),"activity":avatar.snapshot()})
	var camera_before: Transform3D=rig.camera.global_transform;var anchor_before: Transform3D=_anchor().global_transform;var joint_before: Array[Transform3D]=[]
	for node: Node3D in presence_nodes:joint_before.append(node.transform)
	var clock_before: float=avatar.clock;paused=true
	for index: int in range(15):await process_frame
	var frozen: bool=camera_before==rig.camera.global_transform and anchor_before==_anchor().global_transform and avatar.clock==clock_before and player.global_position==at
	for index: int in range(presence_nodes.size()):frozen=frozen and joint_before[index]==presence_nodes[index].transform
	_check("menu.actual_camera_root_and_every_local_joint_stay_frozen",frozen,{"joint_count":presence_nodes.size(),"paused_process_frames":15})
	paused=false;avatar.set_activity("",0.);player.set_facility_control(false);_keys([]);await _presence_wait(6)
	_check("facility.release_preserves_native_capsule_and_restores_human_camera",not rig._facility_mode and not player.facility_control and _capsule()==initial_capsule and absf(rig.pivot_height_m-1.2)<.0001,rig.snapshot())

func _presence_attached_bicycle() -> void:
	Engine.physics_ticks_per_second=30;Engine.max_fps=144;presence_physics_hz=30;presence_render_cap=144
	await _presence_place(Vector3(-30,.08,-30))
	var saved_left_hip: Vector3=avatar._joints.LeftThigh.position;var saved_right_hip: Vector3=avatar._joints.RightThigh.position
	var adapter:=AttachedBikeHost.new();adapter.name="ExplicitMetreBicycleComponentHost";adapter.player=player;adapter.exploration_avatar=avatar;adapter.rig=rig;fixture.add_child(adapter)
	var bike: Node3D=ATTACHED_BIKE_SERVICE.new();adapter.add_child(bike)
	bike.host=adapter;bike.set_physics_process(false);bike.set_process_input(false);bike.set_process_unhandled_input(false)
	var body:=CharacterBody3D.new();body.name="ExplicitMetreBicycleBody";body.collision_layer=4;body.collision_mask=1;body.floor_snap_length=.35;body.safe_margin=.001;adapter.add_child(body);body.global_position=Vector3(-30,.02,-30)
	var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(.70,1.90,1.90);collision.shape=box;collision.position.y=.95;body.add_child(collision)
	var visual:=Node3D.new();body.add_child(visual)
	var proxy: Node3D=ATTACHED_BIKE_SERVICE.PhysicsReset.new();proxy.process_physics_priority=-100;visual.add_child(proxy)
	var row:={"body":body,"visual":visual,"proxy":proxy,"front":null,"wheels":[],"crank":null,"pedals":[],"kickstand":null,"previous":body.global_transform,"current":body.global_transform}
	bike._build_bike(row,proxy);row.kickstand.visible=false;bike.bikes.append(row);bike.loaded=true;bike.riding=true;bike.rental_index=0
	player.set_facility_control(true);player.set_physics_process(false)
	var driver:=AttachedBikeDriver.new();driver.service=bike;driver.row=row;driver.process_physics_priority=2;adapter.add_child(driver)
	await _presence_wait(12)
	presence_bicycle_row=row;presence_bicycle_max_sole_height_error=0.;presence_bicycle_max_hand_error=0.;presence_bicycle_render_samples=0
	var start: Vector3=player.global_position;var before: int=player.recoveries
	_presence_reset_observation("attached_bicycle_current_props");await _presence_wait(75)
	_presence_end_case("attached_bicycle_current_props",start,before,true,true,false)
	_check("attachment.bicycle_current_local_joints_share_actual_current_pedal_and_handle_clock",presence_bicycle_render_samples>=45 and presence_bicycle_max_sole_height_error<.010 and presence_bicycle_max_hand_error<.025,{"observed_render_samples":presence_bicycle_render_samples,"maximum_visible_sole_to_current_pedal_height_error_m":presence_bicycle_max_sole_height_error,"maximum_visible_hand_to_current_handle_error_m":presence_bicycle_max_hand_error,"scope":"Actual production bicycle geometry, rider IK, attachment and render callback on explicit flat supported component course/cadence. Does not replace whole-city E rental, source permission, steer/braking or OS acceptance."})
	_check("attachment.bicycle_root_and_eye_still_interpolate_while_equipment_joints_remain_current",rig._moving_attachment and not rig._facility_mode and String(rig.snapshot().joint_presentation_policy)=="current_equipment_contacts" and presence_fraction_bins.size()>=3 and presence_max_root_error<.002 and presence_max_eye_relative_error<.002,{"camera":rig.snapshot(),"fraction_bins":presence_fraction_bins.keys(),"root_error_m":presence_max_root_error,"eye_error_m":presence_max_eye_relative_error})
	presence_bicycle_row={};driver.set_physics_process(false);bike.loaded=false;bike.riding=false;adapter.queue_free()
	player.set_physics_process(true);player.set_facility_control(false);avatar._joints.LeftThigh.position=saved_left_hip;avatar._joints.RightThigh.position=saved_right_hip;avatar._rest_pose()
	# Generic snap deliberately captures the restored physical riding exit pose;
	# the public V action first restores old history and is unsuitable here.
	rig.snap_to_target_pose();await _presence_wait(3)

func _run() -> void:
	for path: String in ["res://scripts/player/free_roam_player.gd","res://scripts/player/public_player.gd","res://scripts/player/palace_player.gd","res://scripts/player/movement_controller.gd","res://scripts/player/idle_support.gd","res://scripts/player/exploration_avatar.gd","res://scripts/player/human_gait_support.gd","res://scripts/player/textured_human_rig.gd","res://scripts/player/textured_human_surface.gd","res://scripts/player/human_activity_dimensions.gd","res://assets/vendor/microsoft_rocketbox/PROVENANCE.json","res://assets/vendor/microsoft_rocketbox/Male_Adult_04/Export/Male_Adult_04.fbx","res://assets/vendor/microsoft_rocketbox/Female_Adult_07/Export/Female_Adult_07.fbx","res://assets/vendor/makehuman_swim/provenance.json","res://assets/vendor/makehuman_swim/swim_male.glb","res://assets/vendor/makehuman_swim/swim_female.glb","res://scripts/player/human_surface_meshes.gd","res://scripts/player/exploration_camera.gd","res://scripts/player/camera_rig.gd","res://scripts/input_router.gd","res://scenes/player/camera_rig.tscn","res://scripts/drivable_car_service.gd","res://scripts/city_bike_service.gd","res://../tests/game/check_jump.gd","res://../tests/game/check_stable_motion.gd","res://../tests/game/check_human_scale_motion.gd","res://../tests/game/check_human_presence_camera.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	_presence_checkpoint("fixture_build_begin")
	_setup_stable();fixture.name="IndependentHumanPresenceCameraFixture";_metric_scene()
	_presence_checkpoint("fixture_build_end")
	player.walk_speed_mps=1.4;player.run_speed_mps=3.5
	for key: String in avatar._joints:
		presence_nodes.append(avatar._joints[key]);presence_node_names.append(key)
	presence_nodes.append(avatar._pelvis);presence_node_names.append("Pelvis")
	await _presence_wait(12)
	_check("startup.required_human_camera_action_and_independent_joint_nodes_exist",rig.has_method("use_human_eye_view") and presence_nodes.size()>=12,{"joint_names":presence_node_names})
	if not rig.has_method("use_human_eye_view"):_finish();return
	await _presence_basics()
	_presence_checkpoint("basic_view_and_initial_capture_complete")
	# Nominal render caps are scheduling conditions, never FPS benchmarks.
	for hz: int in [30,60]:
		Engine.physics_ticks_per_second=hz;presence_physics_hz=hz
		for cap: int in [30,60,144]:
			Engine.max_fps=cap;presence_render_cap=cap
			var prefix:=str(hz)+"hz_"+str(cap)+"cap_";var photo:=hz==30 and cap==144
			await _presence_motion(prefix+"walk",["move_forward"],1.2,photo)
			await _presence_motion(prefix+"run",["move_forward","move_fast"],1.4,photo)
			await _presence_turn(prefix+"turn_90","move_right",photo)
			await _presence_turn(prefix+"turn_180","move_backward",photo)
			await _presence_motion(prefix+"jump",["move_forward","jump"],1.9,photo)
	await _presence_moving_reset();await _presence_paused_midstride_teleport();await _presence_door();await _presence_attached_bicycle();await _presence_safety();await _presence_facility_and_pause()
	_check("render.analytic_pelvis_support_curve_has_independent_nontrivial_subphysics_coverage",presence_analytic_pelvis_samples>=30 and presence_analytic_pelvis_nontrivial_samples>=8 and presence_analytic_pelvis_maximum_error_m<.0003,{"independently_checked_pelvis_samples":presence_analytic_pelvis_samples,"intermediate_samples_differing_from_linear_by_over_0_3mm":presence_analytic_pelvis_nontrivial_samples,"maximum_analytic_y_error_m":presence_analytic_pelvis_maximum_error_m,"maximum_analytic_vs_linear_y_difference_m":presence_analytic_pelvis_maximum_linear_difference_m,"position_tolerance_unchanged_m":.0003,"oracle":"Hardcoded display contract and independent previous/current physical phase and weights, without calling production helpers or reading render metadata."})
	_check("physics.original_capsule_and_collision_layers_preserved_through_every_case",_capsule()==initial_capsule,{"original_capsule":initial_capsule,"final_capsule":_capsule()})
	_finish()

func _finish() -> void:
	if finished:return
	finished=true;presence_phase="";_keys([]);paused=false
	var failed:=checks.filter(func(row: Dictionary)->bool:return not row.passed).size()
	var scheduling:=_presence_window_scheduling()
	if presence_vsync_before>=0 and DisplayServer.get_name()!="headless":
		DisplayServer.window_set_vsync_mode(presence_vsync_before as DisplayServer.VSyncMode)
		scheduling["restored_original_mode_readback"]=int(DisplayServer.window_get_vsync_mode())
	var result:={"schema_version":1,"task":"EXP29_HUMAN_PRESENCE_CAMERA","result":"PASS" if failed==0 else "FAIL","display":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"started_at_local":started_at,"finished_at_local":Time.get_datetime_string_from_system(),"elapsed_wall_seconds":float(Time.get_ticks_msec()-presence_started_ms)/1000.,"summary":{"checks":checks.size(),"failed":failed},"checks":checks,"source_sha256":source_hashes,"cases":presence_cases,"moving_human_view_reset":presence_moving_v_result,"paused_midstride_teleport":presence_paused_teleport_result,"analytic_pelvis_oracle":{"samples":presence_analytic_pelvis_samples,"nontrivial_samples":presence_analytic_pelvis_nontrivial_samples,"maximum_error_m":presence_analytic_pelvis_maximum_error_m,"maximum_linear_difference_m":presence_analytic_pelvis_maximum_linear_difference_m},"timing_events":presence_timing_events,"captures":presence_captures,"scope":"Isolated metre floor/grid, actual latest production CharacterBody3D/avatar/exploration camera and engine Input actions. Independent late physics/process recorder captures local joint transforms, physical gait phase/weights and visible-root/eye histories at 30/60Hz physics and 30/60/144 render caps. All local transforms retain strict linear position/basis expectation except pelvis Y, independently checked against the declared analytic support-wave contract with the same0.3mm tolerance. A paused midstride teleport checks freshly authored destination joints and independently composed physical foot globals. Explicit placements, native walls/parapet/new-obstacle/recovery faults and fixed facility pose are test-only. Actual observed render fractions are used without assigning production render fraction. Images use the ordinary production exploration Camera3D. No city actors, persistent settings, source geometry, OS keyboard, sustained FPS, real anthropometry/photorealism or subjective comfort claim."}
	result["window_scheduling"]=scheduling
	var output:=FileAccess.open(report_path,FileAccess.WRITE)
	if output==null:push_error("Cannot write human presence camera report");quit(2);return
	output.store_string(JSON.stringify(_json(result),"  ")+"\n");output.close()
	print("HUMAN_PRESENCE_CAMERA_RESULT ",checks.size()-failed,"/",checks.size());quit(0 if failed==0 else 1)
