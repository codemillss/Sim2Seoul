extends Node3D
## A synthetic GPU startup check, with no map, collision, or gameplay claims.

var elapsed := 0.0
var frame_count := 0
var observation_seconds := 12.0
var capture_path := ""
var report_path := ""
var stay_open := false
var recorded := false
var cube: MeshInstance3D
var status: Label

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")
		elif argument.begins_with("--seconds="):
			observation_seconds = argument.trim_prefix("--seconds=").to_float()
		elif argument == "--stay-open":
			stay_open = true
	var camera := Camera3D.new()
	camera.position = Vector3(6, 4, 7)
	add_child(camera)
	camera.look_at(Vector3(0, 0.8, 0))
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.shadow_enabled = true
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.06, 0.09, 0.13)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.7, 0.85)
	environment.environment.ambient_light_energy = 0.5
	add_child(environment)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(10, 10)
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.material_override = _material(Color(0.21, 0.28, 0.32))
	add_child(floor_node)
	cube = MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	cube.position.y = 1.0
	cube.scale = Vector3(1.5, 2, 1.5)
	cube.material_override = _material(Color(0.13, 0.7, 0.65))
	add_child(cube)
	var hud := CanvasLayer.new()
	add_child(hud)
	status = Label.new()
	status.position = Vector2(24, 22)
	status.add_theme_font_size_override("font_size", 20)
	hud.add_child(status)
	var close_button := Button.new()
	close_button.text = "Close (Esc)"
	close_button.position = Vector2(790, 22)
	close_button.pressed.connect(func(): get_tree().quit())
	hud.add_child(close_button)
	print("E01_READY renderer=%s driver=%s device=%s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name()])

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material

func _process(delta: float) -> void:
	elapsed += delta
	frame_count += 1
	cube.rotation.y += delta * 0.4
	status.text = "Sim2Seoul / E01 engine startup\nSynthetic 3D scene - Seoul world is not loaded\n%s / %s\n%.1f s | frame %d" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(), elapsed, frame_count]
	if elapsed >= observation_seconds and not recorded:
		recorded = true
		_record.call_deferred()

func _record() -> void:
	await RenderingServer.frame_post_draw
	var capture_error := OK
	if not capture_path.is_empty():
		capture_error = get_viewport().get_texture().get_image().save_png(capture_path)
	var evidence := {
		"engine": Engine.get_version_info(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"display_server": DisplayServer.get_name(),
		"elapsed_seconds": elapsed,
		"processed_frames": frame_count,
		"viewport_pixels": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"capture_error": capture_error,
		"scope": "synthetic startup only; no city, scale, walking or performance acceptance"
	}
	if not report_path.is_empty():
		var report := FileAccess.open(report_path, FileAccess.WRITE)
		if report == null:
			push_error("Cannot write E01 report: %s" % report_path)
			get_tree().quit(1)
			return
		report.store_string(JSON.stringify(evidence, "\t") + "\n")
	print("E01_OBSERVED %s" % JSON.stringify(evidence))
	if not stay_open:
		get_tree().quit(0 if capture_error == OK else 1)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
