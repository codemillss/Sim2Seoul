"""Attest exact native GLB inputs and their imported Web resources.

Call write_web_provenance(staged_project) after Godot import, before export.
The result describes build inputs; raw source GLBs are omitted from Web packs.
It never substitutes invented hashes for missing or stale native inputs.
"""
from __future__ import annotations

import hashlib
import json
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RECORD_RELATIVE = Path("data/generated/web_asset_provenance.json")


def _digest(data: bytes, algorithm: str = "sha256") -> str:
    return hashlib.new(algorithm, data).hexdigest()


def _res_file(project: Path, resource: str) -> Path:
    if not resource.startswith("res://"):
        raise ValueError("Expected project resource path: " + resource)
    relative = Path(resource.removeprefix("res://"))
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError("Unsafe project resource path: " + resource)
    path = project / relative
    if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(project):
        raise ValueError("Missing or non-regular imported input: " + resource)
    return path


def _quoted_fields(path: Path) -> dict[str, str]:
    """Read only simple quoted import fields, without evaluating Godot syntax."""
    fields: dict[str, str] = {}
    section = ""
    for line in path.read_text().splitlines():
        if re.fullmatch(r"\[[^\]]+\]", line):
            section = line[1:-1]
        match = re.fullmatch(r'([A-Za-z_][A-Za-z0-9_]*)=(".*")', line)
        if match:
            fields[section + "." + match[1]] = json.loads(match[2])
    return fields


def _imported(project: Path, source: str, source_bytes: bytes, expected_type: str) -> dict:
    remap_path = _res_file(project, source + ".import")
    fields = _quoted_fields(remap_path)
    if fields.get("deps.source_file") != source or fields.get("remap.type") != expected_type:
        raise ValueError("Import source/type does not bind the source asset: " + source)
    imported_path = fields.get("remap.path", "")
    if not imported_path.startswith("res://.godot/imported/"):
        raise ValueError("Unexpected imported resource path: " + imported_path)
    imported_file = _res_file(project, imported_path)
    imported_bytes = imported_file.read_bytes()
    md5_file = imported_file.with_suffix(".md5")
    if not md5_file.is_file():
        raise ValueError("Missing import dependency checksum: " + str(md5_file))
    md5_fields = _quoted_fields(md5_file)
    if md5_fields.get(".source_md5") != _digest(source_bytes, "md5"):
        raise ValueError("Import is stale relative to actual source bytes: " + source)
    if md5_fields.get(".dest_md5") != _digest(imported_bytes, "md5"):
        raise ValueError("Imported binary differs from Godot's import checksum: " + source)
    return {
        "path": imported_path,
        "bytes": len(imported_bytes),
        "sha256": _digest(imported_bytes),
        "import_remap_path": source + ".import",
        # Godot strips editor metadata during export. This binds the checked
        # source import settings, not the rewritten remap bytes in the PCK.
        "import_remap_sha256": _digest(remap_path.read_bytes()),
    }


def _binding(relative: Path) -> tuple[Path, str, bool]:
    name = relative.as_posix()
    if name.startswith("assets/original/seoul_resident/seoul_resident_"):
        return relative.parent / "AUTHORED_MANIFEST.json", "game/" + name, False
    if name == "assets/original/resident_study/resident_form_m01.glb":
        return relative.parent / "FORM_STUDY_MANIFEST.json", "resident_form_m01.glb", False
    if name == "assets/original/resident_study/resident_form_m01_previous.glb":
        return relative.parent / "FORM_STUDY_PREVIOUS_MANIFEST.json", "resident_form_m01.glb", False
    if name == "assets/vendor/kenney_city_kit_commercial/building-skyscraper-a.glb":
        return relative.parent / "provenance.json", relative.name, True
    raise ValueError("GLB has no explicit source-manifest binding: " + name)


def _declared(manifest: dict, entry: str) -> dict:
    files = manifest.get("files")
    if isinstance(files, list):
        matches = [row for row in files if isinstance(row, dict) and row.get("path") == entry]
        if len(matches) != 1:
            raise ValueError("Source manifest entry missing or ambiguous: " + entry)
        return matches[0]
    if isinstance(files, dict) and isinstance(files.get(entry), dict):
        return files[entry]
    raise ValueError("Source manifest entry missing: " + entry)


def _images(project: Path, relative: Path, raw: bytes, manifest: dict) -> list[dict]:
    if raw[:4] != b"glTF" or struct.unpack_from("<I", raw, 4)[0] != 2 or struct.unpack_from("<I", raw, 8)[0] != len(raw):
        raise ValueError("Invalid source GLB: " + relative.as_posix())
    json_size, kind = struct.unpack_from("<II", raw, 12)
    if kind != 0x4E4F534A:
        raise ValueError("GLB JSON chunk missing: " + relative.as_posix())
    document = json.loads(raw[20:20 + json_size])
    binary_start = 28 + json_size
    dependencies = []
    for image in document.get("images", []):
        if "bufferView" in image:
            view = document["bufferViews"][image["bufferView"]]
            if view.get("buffer", 0) != 0 or image.get("mimeType") != "image/png":
                raise ValueError("Unsupported embedded GLB image: " + relative.as_posix())
            start = binary_start + view.get("byteOffset", 0)
            image_bytes = raw[start:start + view["byteLength"]]
            if len(image_bytes) != view["byteLength"]:
                raise ValueError("Truncated embedded GLB image: " + relative.as_posix())
            image_relative = relative.parent / (relative.stem + "_" + image["name"] + ".png")
        elif "uri" in image:
            image_relative = relative.parent / image["uri"]
            image_file = _res_file(project, "res://" + image_relative.as_posix())
            image_bytes = image_file.read_bytes()
            declaration = _declared(manifest, image["uri"])
            if declaration.get("sha256") != _digest(image_bytes) or declaration.get("bytes") != len(image_bytes):
                raise ValueError("External GLB image differs from supplier manifest: " + str(image_file))
        else:
            raise ValueError("GLB image has no source binding: " + relative.as_posix())
        resource = "res://" + image_relative.as_posix()
        dependency = _imported(project, resource, image_bytes, "CompressedTexture2D")
        dependency["source_image_sha256"] = _digest(image_bytes)
        dependencies.append(dependency)
    return dependencies


def write_web_provenance(project_path: Path) -> dict:
    project = Path(project_path).resolve()
    native = (ROOT / "game").resolve()
    if project == native or not (project / "project.godot").is_file():
        raise ValueError("A separate, already imported staging project is required")
    record = {
        "schema_version": 1,
        "kind": "web_imported_asset_provenance",
        "raw_glb_included": False,
        "scope": "Native GLB source, source-manifest and Godot imported dependency bytes verified before Web export. Web includes imported resources; raw GLB bytes are omitted.",
        "assets": {},
    }
    for source in sorted((project / "assets").rglob("*.glb")):
        relative = source.relative_to(project)
        resource = "res://" + relative.as_posix()
        raw = _res_file(project, resource).read_bytes()
        native_bytes = _res_file(native, resource).read_bytes()
        if raw != native_bytes:
            raise ValueError("Staged GLB differs from current native input: " + resource)
        manifest_relative, entry, unused = _binding(relative)
        manifest_resource = "res://" + manifest_relative.as_posix()
        manifest_bytes = _res_file(project, manifest_resource).read_bytes()
        if manifest_bytes != _res_file(native, manifest_resource).read_bytes():
            raise ValueError("Staged source manifest differs from native: " + manifest_resource)
        manifest = json.loads(manifest_bytes)
        declared = _declared(manifest, entry)
        source_sha = _digest(raw)
        if declared.get("sha256") != source_sha or ("bytes" in declared and declared["bytes"] != len(raw)):
            raise ValueError("Actual source GLB differs from its declared source manifest: " + resource)
        imported = _imported(project, resource, raw, "PackedScene")
        row = {
            "source_sha256": source_sha,
            "source_bytes": len(raw),
            "source_manifest_path": manifest_resource,
            "source_manifest_sha256": _digest(manifest_bytes),
            "source_manifest_entry": entry,
            "imported_resource_path": imported["path"],
            "imported_resource_sha256": imported["sha256"],
            "imported_resource_bytes": imported["bytes"],
            "import_remap_sha256": imported["import_remap_sha256"],
            "imported_dependencies": _images(project, relative, raw, manifest),
            "native_staged_source_bytes_equal": True,
            "source_and_import_dependency_checksums_match": True,
        }
        if unused:
            row["no_runtime_consumer"] = True
        record["assets"][resource] = row
    if len(record["assets"]) != 15:
        raise ValueError("Expected exactly the current 15 source GLBs, got " + str(len(record["assets"])))
    output = project / RECORD_RELATIVE
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
    return record
