extends Node
const HUMAN_VISUAL_LOD := preload("res://scripts/player/web_human_visual_lod.gd")
## Web-only display budget. Simulation, source meshes and collisions stay intact.
## Engine.start arguments after `--`: --web-quality=fast|balanced|clear.
const PROFILES := {
	"fast": {"label":"빠르게", "far_m":350.0, "scale_3d":0.75, "detail_m":180.0},
	"balanced": {"label":"균형", "far_m":650.0, "scale_3d":0.90, "detail_m":220.0},
	"clear": {"label":"먼 거리", "far_m":1400.0, "scale_3d":1.0, "detail_m":400.0},
}
const FACADE_CELL_M := 80.0
const SAMPLE_INTERVAL_USEC := 5_000_000
var profile_id := "fast"
var _host: Node3D
var _viewport: Viewport
var _environment: Environment
var _lights: Array[Light3D] = []
var _start_usec := 0
var _last_sample_usec := 0
var _last_enforce_usec := 0
var _last_drawn_frames := 0
var _last_physics_frames := 0
var _sample_count := 0
var _last_human_sync_usec := 0
var _last_human_sync_count := 0
var _last_human_skipped_count := 0

func setup(root_scene: Node3D) -> void:
	if not OS.has_feature("web"):
		set_process(false)
		return
	_host=root_scene
	_viewport=get_viewport()
	process_mode=Node.PROCESS_MODE_ALWAYS
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--web-quality="):continue
		var requested:=argument.trim_prefix("--web-quality=")
		if PROFILES.has(requested):profile_id=requested
	var world_environment:=_host.get_node_or_null("Presentation/WorldEnvironment") as WorldEnvironment
	if world_environment!=null:_environment=world_environment.environment
	for node: Node in _host.find_children("*","Light3D",true,false):
		_lights.append(node as Light3D)
	var quality_option:=_host.get("quality_option") as OptionButton
	if quality_option!=null:
		# Existing menu choices still control their original gameplay-safe lights.
		# Restore the browser rendering budget before that frame is submitted.
		quality_option.item_selected.connect(_on_legacy_quality_selected)
	_apply_visual_budget()
	var detail:=_host.get("building_exterior_identity") as Node
	var facade_instances:=0
	var facade_batches:=0
	if detail!=null:
		for batch: MultiMeshInstance3D in detail.get("batches"):
			batch.visibility_range_end=float(PROFILES[profile_id].detail_m)
			batch.visibility_range_end_margin=15.0
			batch.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			facade_instances+=batch.multimesh.instance_count
			facade_batches+=1
	_start_usec=Time.get_ticks_usec()
	_last_sample_usec=_start_usec
	_last_enforce_usec=_start_usec
	_last_drawn_frames=Engine.get_frames_drawn()
	_last_physics_frames=Engine.get_physics_frames()
	var human_totals: Dictionary=HUMAN_VISUAL_LOD.totals()
	_last_human_sync_usec=int(human_totals.sync_usec)
	_last_human_sync_count=int(human_totals.syncs)
	_last_human_skipped_count=int(human_totals.skips)
	print("WEB_PROFILE ",JSON.stringify({"id":profile_id,"far_m":PROFILES[profile_id].far_m,"scale_3d":PROFILES[profile_id].scale_3d,"detail_m":PROFILES[profile_id].detail_m,"msaa":0,"shadows":false,"facade_batches":facade_batches,"facade_instances":facade_instances,"physics_hz":Engine.physics_ticks_per_second,"perf_interval_s":5,"perf_logging":"continuous_browser_log_ring"}))
	set_process(true)

func _on_legacy_quality_selected(_index: int) -> void:
	_apply_visual_budget.call_deferred()

func _apply_visual_budget() -> void:
	if not is_instance_valid(_host) or not is_instance_valid(_viewport):return
	var profile: Dictionary=PROFILES[profile_id]
	_viewport.scaling_3d_scale=float(profile.scale_3d)
	_viewport.msaa_3d=Viewport.MSAA_DISABLED
	_viewport.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_taa=false
	if _environment!=null:
		_environment.ssao_enabled=false
		_environment.ssil_enabled=false
		_environment.sdfgi_enabled=false
		_environment.ssr_enabled=false
		_environment.volumetric_fog_enabled=false
		_environment.glow_enabled=false
	for light: Light3D in _lights:
		if is_instance_valid(light):light.shadow_enabled=false
	var rig:=_host.get("rig") as Node3D
	if rig!=null:
		rig.set("exploration_far_m",float(profile.far_m))
		var camera:=rig.get("camera") as Camera3D
		if camera!=null:camera.far=float(profile.far_m)
	var active_camera:=_viewport.get_camera_3d()
	if active_camera!=null:active_camera.far=minf(active_camera.far,float(profile.far_m))
	var description:=_host.get("quality_description") as Label
	if description!=null:
		description.text="웹 · %s · 먼 거리 %dm · 그림자 끄기\n화면의 웹 품질을 바꾼 뒤 다시 시작해 다른 거리를 볼 수 있습니다."%[profile.label,int(profile.far_m)]

func _process(_delta: float) -> void:
	if not is_instance_valid(_host):return
	var now:=Time.get_ticks_usec()
	# Menu selections are restored immediately above; this also covers other
	# existing quality callbacks without adding work to simulation/physics ticks.
	if now-_last_enforce_usec>=1_000_000:
		_apply_visual_budget()
		_last_enforce_usec=now
	if now-_last_sample_usec<SAMPLE_INTERVAL_USEC:return
	var window_s:=float(now-_last_sample_usec)/1_000_000.0
	var drawn_frames:=Engine.get_frames_drawn()
	var physics_frames:=Engine.get_physics_frames()
	_sample_count+=1
	print("WEB_PERF ",JSON.stringify({
		"sample":_sample_count,"profile":profile_id,
		"elapsed_s":snappedf(float(now-_start_usec)/1_000_000.0,0.01),
		"window_s":snappedf(window_s,0.01),
		"render_fps":snappedf(float(drawn_frames-_last_drawn_frames)/window_s,0.1),
		"engine_fps":Engine.get_frames_per_second(),
		"process_ms":snappedf(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,0.01),
		"physics_ms":snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,0.01),
		"physics_steps":physics_frames-_last_physics_frames,
		"physics_hz":Engine.physics_ticks_per_second,
		"draw_calls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"visible_draw_calls":_viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"shadow_draw_calls":_viewport.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"primitives":int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"viewport_px":[int(_viewport.get_visible_rect().size.x),int(_viewport.get_visible_rect().size.y)],
		"scale_3d":_viewport.scaling_3d_scale,"paused":get_tree().paused,
		"human_visual":_human_visual_window(),
	}))
	_last_sample_usec=now
	_last_drawn_frames=drawn_frames
	_last_physics_frames=physics_frames

func _human_visual_window() -> Dictionary:
	var totals: Dictionary=HUMAN_VISUAL_LOD.totals()
	var result:={"rigs":0,"processing_rigs":0,"tiers":{},"syncs":int(totals.syncs)-_last_human_sync_count,"skips":int(totals.skips)-_last_human_skipped_count,"sync_ms":snappedf(float(int(totals.sync_usec)-_last_human_sync_usec)/1000.0,.01)}
	for rig: Node in get_tree().get_nodes_in_group("web_human_visual_rigs"):
		result.rigs+=1
		if rig.is_processing():result.processing_rigs+=1
		var state: Dictionary=rig.web_visual_lod_snapshot()
		var tier:=String(state.get("tier","unclassified"))
		result.tiers[tier]=int(result.tiers.get(tier,0))+1
	_last_human_sync_usec=int(totals.sync_usec)
	_last_human_sync_count=int(totals.syncs)
	_last_human_skipped_count=int(totals.skips)
	return result

static func partition_facade_transforms(transforms: Array) -> Array[Dictionary]:
	# Pure geometry plan: preserve each full transform under a cell translation.
	var cells: Dictionary={}
	for transform: Transform3D in transforms:
		var cell:=Vector2i(floori(transform.origin.x/FACADE_CELL_M),floori(transform.origin.z/FACADE_CELL_M))
		if not cells.has(cell):cells[cell]=[]
		cells[cell].append(transform)
	var result: Array[Dictionary]=[]
	for cell: Vector2i in cells:
		var centre:=Vector3((float(cell.x)+0.5)*FACADE_CELL_M,0.0,(float(cell.y)+0.5)*FACADE_CELL_M)
		var rows: Array[Transform3D]=[]
		for source: Transform3D in cells[cell]:
			var local_transform:=source
			local_transform.origin-=centre
			rows.append(local_transform)
		result.append({"cell":cell,"origin":centre,"transforms":rows})
	return result

static func create_facade_batches(title: String,transforms: Array,mesh: Mesh,material: Material) -> Array[MultiMeshInstance3D]:
	# Native facade batches cover the whole city. Repartition only the Web
	# display instances so distance/frustum culling can omit remote decoration.
	var result: Array[MultiMeshInstance3D]=[]
	for partition: Dictionary in partition_facade_transforms(transforms):
		var cell: Vector2i=partition.cell
		var rows: Array=partition.transforms
		var multimesh:=MultiMesh.new()
		multimesh.transform_format=MultiMesh.TRANSFORM_3D
		multimesh.mesh=mesh
		multimesh.instance_count=rows.size()
		for index in range(rows.size()):
			multimesh.set_instance_transform(index,rows[index])
		var node:=MultiMeshInstance3D.new()
		node.name="Exterior_"+title.replace(":","_")+"_Cell_%d_%d"%[cell.x,cell.y]
		node.position=partition.origin
		node.multimesh=multimesh
		node.material_override=material
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end=float(PROFILES.fast.detail_m)
		node.visibility_range_end_margin=15.0
		node.set_meta("web_facade_cell",cell)
		result.append(node)
	return result
