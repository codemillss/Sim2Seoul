#!/usr/bin/env python3
"""Capture paused N02 review views in an offline runtime-only copy."""
import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
from check_pedestrians_contract import ROOT, FILES, ASSETS, HELPERS, sha, write


def main(output, engine):
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='sim2seoul-n02-views-') as temporary:
        game = Path(temporary) / 'game'
        for name in FILES + ASSETS:
            target = game / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / 'game' / name, target)
        for name in [*HELPERS, 'tests/game/check_pedestrians.gd']:
            target = game / 'test_support' / Path(name).name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        result = Path(temporary) / 'views.json'
        ran = subprocess.run(['/usr/bin/sandbox-exec', '-f', str(ROOT / 'tests/game/offline.sb'), str(engine),
            '--path', str(game), '--script', str(ROOT / 'tests/game/inspect_pedestrians.gd'),
            '--log-file', str(output / 'views.log'), '--', '--automatic-probe', '--result=' + str(result),
            '--capture-prefix=' + str(output / 'review')], capture_output=True, text=True, timeout=90)
        if ran.returncode or 'ERROR:' in ran.stdout + ran.stderr or not result.exists():
            raise RuntimeError((ran.stdout + ran.stderr)[-4000:])
        record = json.loads(result.read_text())
        record['probe_sha256'] = sha(ROOT / 'tests/game/inspect_pedestrians.gd')
        record['driver_sha256'] = sha(Path(__file__))
        record['images'] = {p.name: sha(p) for p in sorted(output.glob('review_*.png'))}
        assert len(record['images']) == len(record['captures']) == len(record['npcs']) == 2
        assert record['bundle_sha256'] == sha(ROOT / 'game/data/generated/pedestrians.json')
        write(output / 'views.json', record)
        print('N02 paused review views', len(record['images']))
    return 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'data/reports/n02')
    parser.add_argument('--engine', type=Path, default=Path('/Applications/Godot.app/Contents/MacOS/Godot'))
    args = parser.parse_args()
    raise SystemExit(main(args.output, args.engine))
