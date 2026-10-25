extends SceneTree
## Actual exported-pack reader. Raw sources and imported Web models are distinct.
func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	var reference:=JSON.parse_string(FileAccess.get_file_as_string(args[0])) as Dictionary
	var failures:Array=[]
	var checked:=0
	for path:String in reference:
		checked+=1
		if not FileAccess.file_exists(path):failures.append({"file":path,"reason":"missing_raw_file"})
		elif FileAccess.get_sha256(path)!=reference[path]:failures.append({"file":path,"reason":"raw_bytes_differ"})
	var fonts:=ResourceLoader.exists("res://assets/fonts/NotoSansKR.ttf")
	if not fonts:failures.append({"file":"NotoSansKR.ttf","reason":"font_resource_missing"})
	var provenance:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/generated/web_asset_provenance.json"))
	var imported_count:=0
	var dependency_count:=0
	var remaps:Array=[]
	var helper=load("res://scripts/web_asset_provenance.gd")
	if not provenance is Dictionary or provenance.get("kind")!="web_imported_asset_provenance" or provenance.get("raw_glb_included")!=false:
		failures.append({"reason":"missing_or_invalid_web_provenance"})
	else:
		for path:String in provenance.assets:
			var row:Dictionary=provenance.assets[path]
			imported_count+=1
			if FileAccess.file_exists(path):failures.append({"file":path,"reason":"redundant_raw_glb_included"})
			if not ResourceLoader.exists(path,"PackedScene"):failures.append({"file":path,"reason":"missing_imported_scene_remap"})
			var compiled:String=row.imported_resource_path
			if FileAccess.get_sha256(compiled)!=row.imported_resource_sha256:failures.append({"file":compiled,"reason":"compiled_scene_bytes_differ"})
			var config:=ConfigFile.new()
			var remap_path:=path+".import"
			if config.load(remap_path)!=OK or config.get_value("remap","path","")!=compiled:failures.append({"file":remap_path,"reason":"exported_scene_remap_differs"})
			remaps.append({"path":remap_path,"exported_sha256":FileAccess.get_sha256(remap_path),"source_import_metadata_sha256":row.import_remap_sha256,"scope":"Export rewrites import metadata; semantic path checked, hashes intentionally distinct."})
			if not row.get("no_runtime_consumer",false) and helper._web_entry(path).is_empty():failures.append({"file":path,"reason":"web_runtime_provenance_binding_rejected"})
			for dependency:Dictionary in row.get("imported_dependencies",[]):
				dependency_count+=1
				if FileAccess.get_sha256(dependency.path)!=dependency.sha256:failures.append({"file":dependency.path,"reason":"compiled_texture_bytes_differ"})
	var file:=FileAccess.open(args[1],FileAccess.WRITE)
	file.store_string(JSON.stringify({"task":"WEB_PACK_IMPORTED_MODELS_AND_RAW_INTEGRITY","result":"PASS" if failures.is_empty() else "FAIL","raw_files_checked":checked,"font_resource_exists":fonts,"raw_glbs_omitted":imported_count,"compiled_models_checked":imported_count,"compiled_texture_dependencies_checked":dependency_count,"exported_scene_remaps":remaps,"failures":failures,"engine":Engine.get_version_info().string,"scope":"Native actual-PCK reader validates raw files, imported models/textures and Web provenance bindings. Does not establish browser graphics, controls, audio, persistence, performance or deployment."},"  ")+"\n");file.close()
	quit(0 if failures.is_empty() else 1)
