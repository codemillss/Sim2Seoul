#!/usr/bin/env python3
"""Prepare a recoverable static Site -> Vinext/D1 source migration, locally only.

Does not install, build, apply a database migration, commit, push, or deploy.
The caller supplies an existing clean Site checkout and the official starter.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
OVERLAY_ROOT = ROOT / "tools/web/site-worker"
RUNTIME_PARTS = {".git", "node_modules", ".sites-runtime", ".wrangler", ".vinext", ".next", "dist", "outputs", "__pycache__"}
APP_ROOTS = {"app", "lib", "db", "drizzle", "worker", "scripts", "components", "hooks", "examples", "public"}
SECRET_NAMES = {".npmrc", ".yarnrc", ".yarnrc.yml", "credentials", "credentials.json"}


class PreparationError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise PreparationError(message)


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def git(site: Path, *arguments: str) -> str:
    result = subprocess.run(["git", *arguments], cwd=site, capture_output=True, text=True)
    require(result.returncode == 0, "Git verification failed: " + " ".join(arguments))
    return result.stdout


def relative_path(value: str) -> PurePosixPath:
    require(isinstance(value, str) and value and not any(char in value for char in ("\\", "\x00", "?", "#", ":")), "Unsafe relative path")
    path = PurePosixPath(value)
    require(not path.is_absolute() and all(part not in {".", ".."} for part in path.parts), "Unsafe relative path: " + value)
    require(str(path) == value, "Noncanonical relative path: " + value)
    return path


def secret(path: Path) -> bool:
    return any(part in SECRET_NAMES or part.startswith((".env", ".dev.vars")) for part in path.parts)


def destination_parents(site: Path, target: Path) -> None:
    require(target.is_relative_to(site), "Destination escapes Site checkout")
    for parent in [target, *target.parents]:
        if parent == site:
            break
        require(not parent.is_symlink(), "Destination symlink is protected: " + str(parent.relative_to(site)))
        if parent != target:
            require(not parent.exists() or parent.is_dir(), "Destination parent is a file: " + str(parent.relative_to(site)))


def inventory(directory: Path, *, starter: bool = False) -> dict[str, dict]:
    """Inventory regular source files; never follow or carry source symlinks."""
    rows = {}
    for parent, directories, files in os.walk(directory, followlinks=False):
        parent = Path(parent)
        for name in [*directories, *files]:
            child = parent / name
            require(not child.is_symlink(), "Source symlinks are unsupported: " + str(child.relative_to(directory)))
        if starter:
            directories[:] = [name for name in directories if name not in RUNTIME_PARTS | {".openai", "public"}]
        for name in files:
            file = parent / name
            relative = file.relative_to(directory)
            if starter and secret(relative):
                continue
            require(not secret(relative), "Secret/config file is not a public game asset: " + str(relative))
            require(not any(part in RUNTIME_PARTS | {".openai"} for part in relative.parts), "Runtime/identity file is not a public game asset: " + str(relative))
            require(file.is_file(), "Expected regular file: " + str(relative))
            rows[relative.as_posix()] = {"path": file, "sha256": digest(file), "bytes": file.stat().st_size}
    return rows


def validate_game(directory: Path) -> dict[str, dict]:
    rows = inventory(directory)
    for name in ["index.html", "play.html", "site.css", "game-loader.js", "game/manifest.json", "game/engine-config.json", "game/index.js"]:
        require(name in rows, "Game export is incomplete: " + name)
    manifest = json.loads((directory / "game/manifest.json").read_text())
    seen = set()
    for kind in ("wasm", "pck"):
        record = manifest.get("files", {}).get(kind, {})
        require(record.get("path") == "game/index." + kind, "Unexpected game file path")
        require(type(record.get("bytes")) is int and record["bytes"] > 0, "Invalid whole game byte count")
        require(re.fullmatch(r"[0-9a-f]{64}", record.get("sha256", "")) is not None, "Invalid whole game SHA")
        chunks = record.get("chunks")
        require(isinstance(chunks, list) and bool(chunks), "Missing game chunks")
        total = 0
        for chunk in chunks:
            name = str(relative_path(chunk.get("path")))
            require(re.fullmatch(r"chunks/[A-Za-z0-9][A-Za-z0-9._-]*\.gz", name) is not None and name not in seen, "Invalid/duplicate chunk path")
            seen.add(name)
            require(name in rows and chunk.get("encoding") == "gzip", "Missing/unsupported chunk")
            require(type(chunk.get("bytes")) is int and chunk["bytes"] > 0, "Invalid raw chunk byte count")
            require(type(chunk.get("transferBytes")) is int and rows[name]["bytes"] == chunk["transferBytes"], "Compressed chunk byte count differs")
            require(re.fullmatch(r"[0-9a-f]{64}", chunk.get("sha256", "")) is not None, "Invalid chunk SHA")
            total += chunk["bytes"]
        require(total == record["bytes"], "Chunk sum differs from whole game byte count")
    return rows


def prepare(site: Path, game_export: Path, starter: Path, report: Path) -> dict:
    require(not report.exists() and not report.is_symlink(), "Choose a fresh report path; earlier evidence is preserved")
    site = site.resolve(strict=True)
    game_export = game_export.resolve(strict=True)
    starter = starter.resolve(strict=True)
    report = report.resolve()
    require(site.is_dir() and game_export.is_dir() and starter.is_dir(), "Inputs must be directories")
    require(not any(report.is_relative_to(path) for path in (site, starter, game_export)), "Report must be outside all input trees")
    require(not starter.is_relative_to(site) and not site.is_relative_to(starter), "Starter and Site trees must not overlap")
    require(not game_export.is_relative_to(site) and not site.is_relative_to(game_export), "Game export and Site trees must not overlap")
    require(Path(git(site, "rev-parse", "--show-toplevel").strip()).resolve() == site, "Site must be the root of its own Git checkout")
    base_commit = git(site, "rev-parse", "--verify", "HEAD").strip()
    require(not git(site, "status", "--porcelain=v1", "--untracked-files=all").strip(), "Site checkout must be clean; preserve existing work first")
    tracked = set(git(site, "ls-files", "-z").split("\x00")) - {""}
    require(".openai/hosting.json" in tracked, "Site hosting manifest must be recoverable from Git HEAD")
    hosting_path = site / ".openai/hosting.json"
    destination_parents(site, hosting_path)
    require(hosting_path.is_file() and not hosting_path.is_symlink(), "Site hosting manifest is required")
    hosting = json.loads(hosting_path.read_text())
    hosting_before_sha256 = digest(hosting_path)
    require(isinstance(hosting, dict) and isinstance(hosting.get("project_id"), str) and bool(hosting["project_id"]), "Existing Site project_id is required")
    static = hosting.get("static")
    require(isinstance(static, dict) and isinstance(static.get("directory"), str), "Only an existing static Site is supported; existing Worker app data is never overwritten")
    old_relative = relative_path(static["directory"])
    require(old_relative.parts[0] in {"dist", "out", "build", ".output"}, "Only generated static output directories can be removed")
    old_output = site / str(old_relative)
    destination_parents(site, old_output)
    require(old_output.is_dir() and old_output.resolve().is_relative_to(site), "Static output must be inside the Site checkout")
    require(hosting.get("d1") in {None, "DB"}, "An existing different D1 binding must be migrated explicitly")
    for name in APP_ROOTS:
        require(not (site / name).exists() and not (site / name).is_symlink(), "Existing app/data directory is protected: " + name)
    # All old output must be in HEAD and clean, so removal is Git-recoverable.
    old_files = {}
    for parent, directories, files in os.walk(old_output, followlinks=False):
        for name in [*directories, *files]:
            require(not (Path(parent) / name).is_symlink(), "Static output symlinks are unsupported")
        for name in files:
            path = Path(parent) / name
            relative = path.relative_to(site).as_posix()
            require(relative in tracked, "Untracked/ignored old static file is protected: " + relative)
            old_files[relative] = {"sha256": digest(path), "git_blob": git(site, "rev-parse", base_commit + ":" + relative).strip()}
    require(bool(old_files), "Existing static output is empty")
    game_files = validate_game(game_export)
    template_files = inventory(starter, starter=True)
    require("package.json" in template_files and "worker/index.ts" in template_files and "scripts/vite/sites-vite-plugin.ts" in template_files, "Official Vinext starter shape is required")
    overlay_manifest = json.loads((OVERLAY_ROOT / "overlay.json").read_text())
    omitted = set(overlay_manifest["omit_official_files"])
    for name in omitted:
        require(name in template_files and template_files[name]["sha256"] == overlay_manifest["omitted_official_sha256"][name], "Official omitted source changed; review overlay: " + name)
    planned = {name: {**row, "source_kind": "official_starter"} for name, row in template_files.items() if name not in omitted}
    for entry in overlay_manifest["files"]:
        name = str(relative_path(entry["path"]))
        if entry["kind"] == "modified":
            require(name in template_files and template_files[name]["sha256"] == entry["official_sha256"], "Official source changed; review overlay: " + name)
        else:
            require(name not in template_files, "Official starter now owns added overlay path: " + name)
        path = OVERLAY_ROOT / "overlay" / name
        require(path.is_file() and not path.is_symlink() and digest(path) == entry["sha256"], "Overlay differs from its frozen manifest: " + name)
        planned[name] = {"path": path, "sha256": digest(path), "bytes": path.stat().st_size, "source_kind": "custom_overlay"}
    api = ROOT / overlay_manifest["authoritative_api"]["source"]
    destination = str(relative_path(overlay_manifest["authoritative_api"]["destination"]))
    planned[destination] = {"path": api, "sha256": digest(api), "bytes": api.stat().st_size, "source_kind": "authoritative_room_api"}
    for name, row in game_files.items():
        planned["public/" + name] = {**row, "source_kind": "game_export"}
    # A custom old README is unrelated documentation. Keep it instead of the
    # generic starter README. Other overlapping source files fail before writes.
    preserved = {}
    for name in list(planned):
        target = site / name
        destination_parents(site, target)
        require(not secret(Path(name)) and not any(part in RUNTIME_PARTS | {".openai"} for part in Path(name).parts), "Unsafe planned source path: " + name)
        if target.exists() and name == "README.md":
            require(target.is_file(), "Existing README must be a regular file")
            preserved[name] = digest(target)
            del planned[name]
        elif target.exists() and name == ".gitignore":
            require(target.is_file(), "Existing .gitignore must be a regular file")
        elif target.exists():
            require(target.is_file() and digest(target) == planned[name]["sha256"], "Existing unrelated source is protected: " + name)
    temporary = hosting_path.with_name("hosting.json.prepare-tmp")
    require(not temporary.exists() and not temporary.is_symlink(), "Temporary hosting manifest path is occupied")
    for name in tracked:
        require(not (site / name).is_symlink(), "Existing tracked symlink is protected: " + name)
    before = {name: digest(site / name) for name in tracked if not name.startswith(str(old_relative) + "/") and name != ".openai/hosting.json" and (site / name).is_file()}
    updated = copy.deepcopy(hosting)
    del updated["static"]
    updated["d1"] = "DB"
    updated.setdefault("r2", None)
    copied = []
    for name, row in sorted(planned.items()):
        target = site / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if name == ".gitignore" and target.exists():
            require(target.is_file(), "Existing .gitignore must be a regular file")
            previous = target.read_text()
            missing = [line for line in row["path"].read_text().splitlines() if line and line not in previous.splitlines()]
            target.write_text(previous.rstrip("\n") + "\n" + "\n".join(missing) + "\n")
            copied.append({"path": name, "source_kind": "merged_gitignore", "sha256": digest(target), "bytes": target.stat().st_size})
            continue
        shutil.copyfile(row["path"], target)
        require(digest(target) == row["sha256"], "Copy hash differs: " + name)
        copied.append({"path": name, "source_kind": row["source_kind"], "sha256": row["sha256"], "bytes": row["bytes"]})
    # Prove all new source/assets before switching the manifest or removing
    # tracked generated files. No user app/database/runtime files are removed.
    require(all(digest(site / row["path"]) == row["sha256"] for row in copied), "Prepared source hash differs")
    for name, sha in before.items():
        if name == ".gitignore" or name in planned:
            continue
        require(digest(site / name) == sha, "Unrelated source changed: " + name)
    destination_parents(site, hosting_path)
    destination_parents(site, old_output)
    require(digest(hosting_path) == hosting_before_sha256, "Hosting manifest changed during preparation; preserve the newer version")
    latest_old = {path.relative_to(site).as_posix() for path in old_output.rglob("*") if path.is_file()}
    require(latest_old == set(old_files), "Old static output changed during preparation; preserve the newer files")
    for name, row in old_files.items():
        destination_parents(site, site / name)
        require(digest(site / name) == row["sha256"], "Old static file changed during preparation: " + name)
    require(all(digest(row["path"]) == row["sha256"] for row in planned.values()), "Input source/export changed during preparation")
    new_manifest = json.dumps(updated, ensure_ascii=False, indent=2) + "\n"
    with temporary.open("x") as stream:
        stream.write(new_manifest)
    os.replace(temporary, hosting_path)
    for relative in old_files:
        (site / relative).unlink()
    for parent, directories, _files in os.walk(old_output, topdown=False):
        for name in directories:
            (Path(parent) / name).rmdir()
    old_output.rmdir()
    result = {"result": "PASS", "at_utc": datetime.now(timezone.utc).isoformat(), "site": str(site), "game_export": str(game_export), "official_starter": str(starter), "base_commit": base_commit, "project_id_preserved": updated["project_id"] == hosting["project_id"], "hosting_before": hosting, "hosting_after": updated, "hosting_sha256": digest(hosting_path), "copied_files": copied, "source_file_count": len(copied), "game_asset_count": len(game_files), "game_asset_bytes": sum(row["bytes"] for row in game_files.values()), "room_api_exact_sha256": digest(site / destination), "overlay_manifest_sha256": digest(OVERLAY_ROOT / "overlay.json"), "removed_generated_files": old_files, "unrelated_files_preserved": before, "git_status": git(site, "status", "--short"), "scope": "Source preparation only. No installation/build, migration application, account/identity/audience change, commit, push or publication.", "recovery": {"source_commit": base_commit, "old_static_directory": str(old_relative), "note": "Old generated static files remain recoverable from the recorded Git commit. Review changes before any Git restore or cleanup; this helper never resets the checkout."}}
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site", type=Path, required=True)
    parser.add_argument("--game-export", type=Path, required=True, help="Exported dist directory, not its parent Site")
    parser.add_argument("--starter", type=Path, required=True, help="Official vinext-starter template directory")
    parser.add_argument("--report", type=Path, required=True, help="Fresh report outside the Site checkout")
    args = parser.parse_args()
    try:
        result = prepare(args.site, args.game_export, args.starter, args.report)
    except (PreparationError, OSError, ValueError, KeyError, TypeError) as error:
        print(json.dumps({"result": "FAIL", "error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1
    print(json.dumps({"result": result["result"], "site": result["site"], "game_assets": result["game_asset_count"], "game_bytes": result["game_asset_bytes"], "source_files": result["source_file_count"], "report": str(args.report.resolve())}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
