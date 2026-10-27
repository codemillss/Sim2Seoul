#!/usr/bin/env python3
"""Bounded Git-backed migration fixtures. Never edits an actual Site checkout."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("shared_site_prepare", ROOT / "tools/prepare_shared_city_site.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def sha(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()


def command(site, *args):
    result = subprocess.run(["git", *args], cwd=site, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr)
    return result.stdout


def commit(site):
    command(site, "add", "-f", "--", ".")
    command(site, "-c", "user.name=Local Fixture", "-c", "user.email=fixture@example.invalid", "-c", "core.hooksPath=/dev/null", "commit", "-m", "Recoverable static fixture")


def fixture(parent, name, assets=None):
    site = parent / name
    site.mkdir()
    command(site, "init", "--initial-branch=fixture")
    (site / ".openai").mkdir()
    (site / ".openai/hosting.json").write_text(json.dumps({"project_id": "appgprj_fixture_preserve", "static": {"directory": "dist"}, "r2": "KEEP_BUCKET", "unrelated": {"nested": [1, {"preserve": True}]}}, indent=2) + "\n")
    if assets:
        shutil.copytree(assets, site / "dist")
    else:
        (site / "dist").mkdir()
        (site / "dist/index.html").write_text("old static fixture")
    (site / "README.md").write_text("Existing user documentation must survive.\n")
    (site / ".gitignore").write_text("/keep-cache/\n")
    commit(site)
    return site


def tree(site):
    result = {}
    for path in site.rglob("*"):
        name = path.relative_to(site).as_posix()
        if name == ".git" or name.startswith(".git/"):
            continue
        if path.is_symlink():
            result[name] = {"symlink": str(path.readlink())}
        elif path.is_file():
            result[name] = sha(path)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-export", type=Path, required=True)
    parser.add_argument("--starter", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.report.exists():
        raise RuntimeError("Choose a fresh fixture report")
    work = Path(tempfile.mkdtemp(prefix="shared-city-prepare-fixtures-", dir=ROOT / "data/cache"))
    checks = []

    def check(name, passed, **evidence):
        checks.append({"name": name, "passed": bool(passed), **evidence})

    positive = fixture(work, "positive", args.game_export)
    original = json.loads((positive / ".openai/hosting.json").read_text())
    result_path = work / "positive-preparation.json"
    result = MODULE.prepare(positive, args.game_export, args.starter, result_path)
    actual = json.loads((positive / ".openai/hosting.json").read_text())
    expected_assets = MODULE.inventory(args.game_export)
    check("full_export_copied_exact", all(sha(positive / "public" / name) == row["sha256"] for name, row in expected_assets.items()), assets=len(expected_assets))
    check("project_id_and_unrelated_fields_preserved", actual["project_id"] == original["project_id"] and actual["unrelated"] == original["unrelated"] and actual["r2"] == "KEEP_BUCKET")
    check("only_static_removed_D1_added", "static" not in actual and actual["d1"] == "DB")
    check("old_static_removed_but_git_recoverable", not (positive / "dist").exists() and bool(command(positive, "show", result["base_commit"] + ":dist/play.html")))
    check("authoritative_API_exact", sha(positive / "lib/room-api.mjs") == sha(ROOT / "tools/web/multiplayer/room-api.mjs"))
    check("latest_dispatch_status_preserved", 'signInRequired: !request.headers.get("oai-authenticated-user-id")' in (positive / "app/api/multiplayer/status/route.ts").read_text())
    check("user_README_and_ignore_rules_preserved", (positive / "README.md").read_text() == "Existing user documentation must survive.\n" and "/keep-cache/" in (positive / ".gitignore").read_text())
    check("official_page_omitted_for_route", not (positive / "app/page.tsx").exists() and (positive / "app/route.ts").is_file())
    check("no_runtime_or_secrets_copied", not any((positive / name).exists() for name in ["node_modules", ".sites-runtime", ".wrangler", ".vinext", ".env", ".npmrc"]))

    def rejection(name, change, *, game=None, starter=None, report=None):
        site = fixture(work, name)
        change(site)
        before = tree(site)
        message = None
        try:
            MODULE.prepare(site, game or args.game_export, starter or args.starter, report or work / (name + "-report.json"))
        except (MODULE.PreparationError, OSError, ValueError, KeyError, TypeError) as error:
            message = str(error)
        check(name + "_rejected_without_mutation", message is not None and tree(site) == before and not (site / "package.json").exists(), reason=message)

    rejection("dirty_tracked", lambda site: (site / "README.md").write_text("ongoing work"))
    rejection("untracked_user_file", lambda site: (site / "notes.txt").write_text("ongoing work"))

    def ignored_output(site):
        with (site / ".gitignore").open("a") as stream:
            stream.write("/dist/ignored.txt\n")
        commit(site)
        (site / "dist/ignored.txt").write_text("ignored data is protected")

    rejection("ignored_old_static_file", ignored_output)
    for folder in ["app", "db", "drizzle", "public"]:
        def existing_app(site, folder=folder):
            (site / folder).mkdir()
            (site / folder / "user-data.json").write_text('{"preserve":true}')
            commit(site)
        rejection("existing_" + folder + "_data", existing_app)

    def manifest_change(site, key, value):
        path = site / ".openai/hosting.json"
        manifest = json.loads(path.read_text())
        manifest[key] = value
        path.write_text(json.dumps(manifest))
        commit(site)

    rejection("different_D1_binding", lambda site: manifest_change(site, "d1", "KEEP_OTHER_DB"))
    rejection("unsafe_static_directory", lambda site: manifest_change(site, "static", {"directory": ".git"}))

    def symlink_hosting(site):
        outside = work / "outside-hosting"
        outside.mkdir()
        shutil.copyfile(site / ".openai/hosting.json", outside / "hosting.json")
        shutil.rmtree(site / ".openai")
        (site / ".openai").symlink_to(outside, target_is_directory=True)
        commit(site)

    rejection("hosting_parent_symlink", symlink_hosting)

    def parent_file(site):
        (site / "scripts").write_text("not a directory")
        commit(site)

    rejection("planned_parent_is_file", parent_file)
    rejection("report_inside_game_input", lambda site: None, report=args.game_export / "forbidden-preparation-report.json")
    occupied_report = work / "occupied.json"
    occupied_report.write_text("prior evidence")
    rejection("existing_report", lambda site: None, report=occupied_report)
    altered = work / "altered-starter"
    shutil.copytree(args.starter, altered)
    with (altered / "vite.config.ts").open("a") as stream:
        stream.write("\n// changed upstream official version\n")
    rejection("changed_upstream_overlay_base", lambda site: None, starter=altered)
    result = {"result": "PASS" if all(row["passed"] for row in checks) else "FAIL", "passed": sum(row["passed"] for row in checks), "total": len(checks), "fixture_root": str(work), "positive_site": str(positive), "positive_preparation_report": str(result_path), "checks": checks, "scope": "Real clean Git-backed old-static fixtures only. No actual Site checkout, runtime, database, native tool, network or publication action."}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ["result", "passed", "total", "fixture_root"]}))
    return 0 if result["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
