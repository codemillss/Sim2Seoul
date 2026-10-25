extends SceneTree
## Reads the actual exported pack; does not substitute for a browser run.
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
	var file:=FileAccess.open(args[1],FileAccess.WRITE)
	file.store_string(JSON.stringify({"task":"WEB_PACK_RAW_INTEGRITY","result":"PASS" if failures.is_empty() else "FAIL","raw_files_checked":checked,"font_resource_exists":fonts,"failures":failures,"engine":Engine.get_version_info().string,"scope":"Native reader of actual exported pack. Does not establish browser graphics, controls, audio, persistence, performance or deployment."},"  ")+"\n");file.close()
	quit(0 if failures.is_empty() else 1)
