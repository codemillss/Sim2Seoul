extends "res://test_support/check_urban_motion.gd"
## R03 runs the frozen N04 journey against V0 resources inside the exported app.
## Normal app launch still uses v0_walk.tscn; this script is explicit CLI-only QA.
const QUALITY_PROBE_PATH := "res://test_support/check_quality.gd"

func _fresh_scene() -> bool:
	if is_instance_valid(scene):
		sessions.append({"index":scene_index,"events":scene.traffic.events.duplicate(true),"inventory_after":_inventory()})
		scene.queue_free();scene=null
	await process_frame
	await process_frame
	scene_index+=1
	scene=load("res://scenes/world/v0_walk.tscn").instantiate()
	# A fresh output location isolates testing from the person's saved preference.
	scene.quality_settings_path=output_path+".quality.json"
	if FileAccess.file_exists(scene.quality_settings_path):
		push_error("Package probe requires a fresh settings/output location");return false
	root.add_child(scene)
	if not scene.runtime_ok:return false
	if OS.has_feature("editor") or OS.is_debug_build():
		push_error("R03 package probe requires the actual exported release executable");return false
	scene.input_router.set_script(load("res://test_support/daehanmun_probe_input.gd"))
	scene.input_router.isolate_movement_bindings()
	for route in scene.pedestrian_bundle.routes:route_map[route.id]=route
	for route in scene.traffic_bundle.routes:source_routes[route.id]=route
	fixtures.clear()
	await _wait(.5)
	var configured_main: String=str(ProjectSettings.get_setting("application/run/main_scene",""))
	var resolved_main:=configured_main
	if configured_main.begins_with("uid://"):
		resolved_main=ResourceUID.get_id_path(ResourceUID.text_to_id(configured_main))
	var files:={}
	for path in ["res://icudt_godot.dat","res://resources/quality_presets/standard.json","res://resources/quality_presets/low.json","res://resources/legal/ATTRIBUTION.md","res://resources/legal/GODOT_LICENSE.txt","res://resources/legal/GODOT_THIRD_PARTY.txt","res://resources/legal/KENNEY_CC0.txt","res://resources/legal/NOTICES.txt"]:
		files[path]={"exists":FileAccess.file_exists(path),"sha256":FileAccess.get_sha256(path),"bytes":FileAccess.get_file_as_bytes(path).size()}
	var context:={"task":"R03","scene_path":scene.scene_file_path,"configured_main_scene":configured_main,"resolved_main_scene":resolved_main,
		"executable_path":OS.get_executable_path(),"executable_sha256":FileAccess.get_sha256(OS.get_executable_path()),
		"editor_feature":OS.has_feature("editor"),"debug_build":OS.is_debug_build(),"engine_version":Engine.get_version_info().string,
		"quality":scene.quality_snapshot(),"packed_files":files,
		"scope":"Actual exported release executable and PCK resources; N04 continuous-input observations follow in the primary raw file. Automatic input is not human handling or another-Mac acceptance."}
	var saved:=FileAccess.open(output_path+".package_context.json",FileAccess.WRITE)
	if saved==null:push_error("Package context could not be saved");return false
	saved.store_string(JSON.stringify(context)+"\n")
	print("R03_PACKAGE_CONTEXT main=",resolved_main," scene=",scene.scene_file_path)
	return true
