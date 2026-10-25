extends SceneTree
## Preserve the exporter's imported resources and add raw originals used by
## FileAccess integrity/audio code. Imported remaps stay intact.
## Raw authoring GLBs are omitted; build-verified provenance and compiled models remain.
var entries:Array[String]=[]
func walk(path:String) -> void:
	var dir:=DirAccess.open(path)
	if dir==null:return
	dir.include_hidden=true
	for name:String in dir.get_files():entries.append(path.path_join(name))
	for name:String in dir.get_directories():
		if name not in [".",".."]:walk(path.path_join(name))
func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	var source_root:=args[0]
	for path:String in [".godot","assets","data","resources","scenes","scripts","shaders","web_source"]:walk("res://"+path)
	entries.append("res://project.binary");entries.sort()
	var pack:=PCKPacker.new();var failures:Array=[]
	var error:=pack.pck_start(args[1]);assert(error==OK)
	for path:String in entries:
		if path.ends_with(".glb"):continue
		error=pack.add_file(path,path)
		if error!=OK:failures.append({"path":path,"error":error})
	var raw:Array=[]
	var expected:=JSON.parse_string(FileAccess.get_file_as_string(args[2])) as Dictionary
	for path:String in expected:
		if FileAccess.file_exists(path):continue
		var original:=source_root.path_join(path.trim_prefix("res://"))
		assert(FileAccess.get_sha256(original)==expected[path])
		error=pack.add_file(path,original)
		if error!=OK:failures.append({"path":path,"error":error})
		raw.append({"path":path,"sha256":expected[path]})
	error=pack.flush()
	if error!=OK:failures.append({"flush_error":error})
	var record:=FileAccess.open(args[3],FileAccess.WRITE)
	record.store_string(JSON.stringify({"task":"WEB_PACK_RAW_PRESERVATION","result":"PASS" if failures.is_empty() else "FAIL","exported_entries_preserved":entries.size(),"raw_originals_added":raw,"failures":failures},"  ")+"\n");record.close()
	quit(0 if failures.is_empty() else 1)
