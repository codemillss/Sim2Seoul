#!/usr/bin/env python3
"""Fifteen actual W02 runtime refusals before any source/replacement bodies."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from check_palace_contract import FILES, ASSETS

ROOT = Path(__file__).resolve().parents[1]
CASES = ['checksum', 'worldhash', 'w01hash', 'manifestfiletype', 'wrongtask',
         'terrainclaim', 'wrongrole', 'fragmentnumber', 'movementnumber',
         'volumenumber', 'routenumber', 'missingroutes', 'spawnchange',
         'directionchange', 'checkpointnumber']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':'), allow_nan=False) + '\n')


def main(output, engine):
    from check_palace_bundle import check
    check(ROOT)
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    original = {p: sha(ROOT / 'game' / p) for p in FILES + ASSETS}
    proof = {p: sha(ROOT / p) for p in ['tests/game/check_palace_rejection.gd', 'tools/check_palace_rejections.py']}
    results = []
    for name in CASES:
        with tempfile.TemporaryDirectory(prefix='sim2seoul-w02-reject-') as temporary:
            game = Path(temporary) / 'game'
            for path in FILES + ASSETS:
                target = game / path
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / 'game' / path, target)
            generated = game / 'data/generated'
            plan_path = generated / 'palace_walk.json'
            decision_path = generated / 'palace_decision.json'
            manifest_path = generated / 'palace_manifest.json'
            plan = json.loads(plan_path.read_text())
            decision = json.loads(decision_path.read_text())
            manifest = json.loads(manifest_path.read_text())
            if name == 'checksum': plan_path.write_bytes(plan_path.read_bytes() + b' ')
            elif name == 'worldhash': manifest['world_sha256'] = '0' * 64
            elif name == 'w01hash': manifest['w01_sha256'] = '0' * 64
            elif name == 'manifestfiletype': manifest['files']['connection'] = []
            elif name == 'wrongtask': plan['task'] = 'W03'
            elif name == 'terrainclaim':
                plan['scope']['physical_terrain_verified'] = True
                decision['scope']['physical_terrain_verified'] = True
            elif name == 'wrongrole': plan['support']['role'] = 'Buildings'
            elif name == 'fragmentnumber': plan['support']['vertices'][0] = 'bad'
            elif name == 'movementnumber': plan['movement_rings'][0][0][0][0] = 'bad'
            elif name == 'volumenumber': plan['volume_obstacles'][0]['bottom'] = 'bad'
            elif name == 'routenumber': plan['routes'][0]['xz'][0][0] = 'bad'
            elif name == 'missingroutes': del plan['routes']
            elif name == 'spawnchange': plan['spawn'][0] += 1
            elif name == 'directionchange': plan['direction_xz'][0] *= -1
            elif name == 'checkpointnumber': plan['checkpoints'][0]['xz'][0] = 'bad'
            if name != 'checksum':
                write(plan_path, plan)
                write(decision_path, decision)
                if name != 'manifestfiletype':
                    manifest['files']['connection']['sha256'] = sha(plan_path)
                    manifest['files']['decision']['sha256'] = sha(decision_path)
            write(manifest_path, manifest)
            # Preserve the exact invalid inputs rather than only describing them.
            for source in [plan_path, decision_path, manifest_path]:
                target = output / 'inputs' / name / source.name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
            result = output / (name + '.json')
            log = output / (name + '.log')
            result.unlink(missing_ok=True)
            log.unlink(missing_ok=True)
            command = ['/usr/bin/sandbox-exec', '-f', str(ROOT / 'tests/game/offline.sb'), str(engine),
                       '--headless', '--path', str(game), '--script', str(ROOT / 'tests/game/check_palace_rejection.gd'),
                       '--log-file', str(log), '--', '--result=' + str(result)]
            try:
                ran = subprocess.run(command, capture_output=True, text=True, timeout=45)
                messages = re.sub(r'\x1b\[[0-9;]*m', '', ran.stdout + ran.stderr)
                engine_ok = ran.returncode == 0 and 'ERROR:' not in messages and 'SCRIPT ERROR' not in messages and result.exists()
                evidence = json.loads(result.read_text()) if result.exists() else {}
                passed = engine_ok and evidence.get('accepted') is False and evidence.get('source_bodies_created') == 0 and evidence.get('fragment_bodies_created') == 0 and bool(evidence.get('error'))
                results.append({'case': name, 'passed': passed, 'engine_evidence': result.name,
                                'input_directory': 'inputs/' + name, 'returncode': ran.returncode,
                                'runtime_error': evidence.get('error'), 'engine_message_tail': messages[-1500:] if not passed else ''})
            except subprocess.TimeoutExpired:
                results.append({'case': name, 'passed': False, 'error': '45-second engine timeout', 'input_directory': 'inputs/' + name})
            print('W02 rejection', name, results[-1]['passed'], flush=True)
    unchanged = original == {p: sha(ROOT / 'game' / p) for p in FILES + ASSETS} and proof == {p: sha(ROOT / p) for p in proof}
    report = {'task': 'W02', 'passed': len(results) == 15 and all(r['passed'] for r in results) and unchanged,
              'cases': results, 'original_inputs_unchanged': unchanged, 'original_runtime_sha256': original,
              'proof_sha256': proof, 'network': 'deny network*',
              'scope': '15 actual headless runtime rejection variants, with refreshed checksums for semantic mutations; zero body creation required. No GPU/human/M4 claims.'}
    write(output / 'rejection_check.json', report)
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'data/cache/palace_rejections')
    parser.add_argument('--engine', type=Path, default=Path('/Applications/Godot.app/Contents/MacOS/Godot'))
    args = parser.parse_args()
    raise SystemExit(main(args.output, args.engine))
