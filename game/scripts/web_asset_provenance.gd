extends RefCounted
## Web keeps the imported scene, not a second copy of its source GLB.
## The build validates source/manifests/import dependencies before export; the
## loader validates the complete exported pack. This record attests that build
## input. It does not claim that raw GLB bytes exist or were hashed at runtime.
const RECORD_PATH := "res://data/generated/web_asset_provenance.json"
const RECORD_KIND := "web_imported_asset_provenance"
static var _record_loaded := false
static var _assets: Dictionary = {}
static var _manifests: Dictionary = {}
static var _validated: Dictionary = {}

static func source_exists(path: String) -> bool:
	if not OS.has_feature("web"): return FileAccess.file_exists(path)
	return not _web_entry(path).is_empty()

static func source_sha256(path: String) -> String:
	if not OS.has_feature("web"): return FileAccess.get_sha256(path)
	return String(_web_entry(path).get("source_sha256", ""))

static func evidence(path: String) -> Dictionary:
	if not OS.has_feature("web"):
		return {"basis":"runtime_raw_file_sha256", "raw_glb_included":true}
	var row := _web_entry(path)
	return {"basis":"build_verified_source_manifest_and_imported_resource", "raw_glb_included":false,
		"attestation_path":RECORD_PATH, "attestation_valid":not row.is_empty(),
		"imported_resource_path":row.get("imported_resource_path", ""),
		"scope":"Source hash verified during Web build. Raw GLB is omitted; imported scene is included. Complete Web pack integrity is checked by the browser loader."}

static func _sha(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for character: String in value:
		if character not in "0123456789abcdef": return false
	return true

static func _read_record() -> void:
	if _record_loaded: return
	_record_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECORD_PATH))
	if not parsed is Dictionary or parsed.get("schema_version") != 1 or parsed.get("kind") != RECORD_KIND or parsed.get("raw_glb_included") != false: return
	if parsed.get("assets") is Dictionary: _assets = parsed.assets

static func _manifest(path: String) -> Dictionary:
	if _manifests.has(path): return _manifests[path]
	var result: Dictionary = {}
	if path.begins_with("res://assets/") and path.ends_with(".json") and FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary: result = {"value":parsed, "sha256":FileAccess.get_sha256(path)}
	_manifests[path] = result
	return result

static func _declared_source(manifest: Dictionary, entry: String) -> Dictionary:
	var files: Variant = manifest.get("files")
	if files is Dictionary:
		var row: Variant = files.get(entry)
		return row if row is Dictionary else {}
	if files is Array:
		for row: Variant in files:
			if row is Dictionary and row.get("path") == entry: return row
	return {}

static func _source_binding(path: String) -> Dictionary:
	if path.begins_with("res://assets/original/seoul_resident/seoul_resident_") and path.ends_with(".glb"):
		return {"path":"res://assets/original/seoul_resident/AUTHORED_MANIFEST.json", "entry":"game/" + path.trim_prefix("res://")}
	if path == "res://assets/original/resident_study/resident_form_m01.glb":
		return {"path":"res://assets/original/resident_study/FORM_STUDY_MANIFEST.json", "entry":"resident_form_m01.glb"}
	if path == "res://assets/original/resident_study/resident_form_m01_previous.glb":
		return {"path":"res://assets/original/resident_study/FORM_STUDY_PREVIOUS_MANIFEST.json", "entry":"resident_form_m01.glb"}
	return {}

static func _web_entry(path: String) -> Dictionary:
	if _validated.has(path): return _validated[path]
	_read_record()
	var row: Variant = _assets.get(path)
	var result: Dictionary = {}
	if row is Dictionary and _valid_entry(path, row): result = row
	_validated[path] = result
	return result

static func _valid_entry(path: String, row: Dictionary) -> bool:
	if not path.begins_with("res://assets/original/") or not path.ends_with(".glb"): return false
	for field: String in ["source_sha256", "source_manifest_sha256", "imported_resource_sha256", "import_remap_sha256"]:
		if not _sha(row.get(field)): return false
	var source_bytes: Variant = row.get("source_bytes")
	if not (source_bytes is int or source_bytes is float) or not is_finite(float(source_bytes)) or source_bytes <= 0 or float(source_bytes) != floor(float(source_bytes)): return false
	for field: String in ["source_manifest_path", "source_manifest_entry", "imported_resource_path"]:
		if not row.get(field) is String or row[field].is_empty(): return false
	var binding := _source_binding(path)
	if binding.is_empty() or row.source_manifest_path != binding.path or row.source_manifest_entry != binding.entry: return false
	var imported: String = row.imported_resource_path
	if not imported.begins_with("res://.godot/imported/") or not imported.ends_with(".scn"): return false
	var manifest := _manifest(String(row.source_manifest_path))
	if manifest.is_empty() or manifest.sha256 != row.source_manifest_sha256: return false
	var declared := _declared_source(manifest.value, String(row.source_manifest_entry))
	if declared.get("sha256") != row.source_sha256: return false
	if declared.has("bytes") and declared.bytes != source_bytes: return false
	# These are existence/remap checks, not per-NPC hashing of large scenes.
	# Exact imported bytes are bound by the build report and whole-pack SHA.
	var remap := ConfigFile.new()
	if remap.load(path + ".import") != OK or remap.get_value("remap", "path", "") != imported: return false
	return ResourceLoader.exists(path, "PackedScene") and ResourceLoader.exists(imported, "PackedScene")
