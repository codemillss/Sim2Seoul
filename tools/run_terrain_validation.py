#!/usr/bin/env python3
"""Run EXP21 production-scene checks sequentially; never trust exit code alone."""
from pathlib import Path
import argparse, json, os, re, subprocess, sys, time
ROOT=Path(__file__).resolve().parents[1]
SUITES={'main':'check_terrain_integration.gd','entries':'check_terrain_entries.gd','actors':'check_terrain_actors.gd'}
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--mode',choices=['headless','gpu'],required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--only',choices=['all',*SUITES],default='all');ap.add_argument('--full-journey',action='store_true');ap.add_argument('--physics-hz',type=int,choices=[30,60]);args=ap.parse_args()
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=True)
    engine=os.environ.get('GODOT_BIN','/Applications/Godot.app/Contents/MacOS/Godot')
    version=subprocess.check_output([engine,'--version'],text=True).strip()
    if version!='4.7.2.stable.official.ed1daf0bf':raise SystemExit('Use the pinned Godot version in docs/environment.md')
    subprocess.run([sys.executable,str(ROOT/'tools/prepare_terrain_surface.py'),'--check'],cwd=ROOT,check=True)
    for name,script in SUITES.items():
        if args.only not in ('all',name):continue
        report=output/f'{name}_{args.mode}.json';log=report.with_suffix('.log')
        if report.exists() or log.exists():raise SystemExit(f'Refusing to replace retained evidence: {report}')
        command=[engine]
        if args.mode=='headless':command+=['--headless']
        else:command+=['--resolution','960x640']
        physics_hz=args.physics_hz or (30 if args.mode=='gpu' else 60)
        command+=['--path',str(ROOT/'game'),'--script',f'res://../tests/game/{script}','--','--automatic-probe',f'--report={report}',f'--physics-hz={physics_hz}']
        if name=='main' and args.full_journey:command+=['--full-journey']
        start=time.monotonic()
        with log.open('w') as stream:
            completed=subprocess.run(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
        for suffix in ['.settings.json','.settings.json.quality.json','.settings.json.time.json']:
            candidate=Path(str(report)+suffix)
            if candidate.exists():candidate.unlink()
        valid=False;summary={};result='MISSING_REPORT'
        if report.exists():
            data=json.loads(report.read_text());result=data.get('result');summary=data.get('summary',{});valid=result=='PASS' and summary.get('failed')==0
        log_text=log.read_text()
        runtime_errors=any(needle in log_text for needle in ['SCRIPT ERROR:','Parse Error:']) or any(line.startswith('ERROR:') and not re.match(r'ERROR: \d+ resources still in use at exit',line) for line in log_text.splitlines())
        print(json.dumps({'suite':name,'mode':args.mode,'physics_hz':physics_hz,'returncode':completed.returncode,'result':result,'summary':summary,'runtime_script_errors':runtime_errors,'wall_s':round(time.monotonic()-start,3),'report':str(report.relative_to(ROOT)) if report.is_relative_to(ROOT) else str(report)},ensure_ascii=False),flush=True)
        if completed.returncode or not valid or runtime_errors:raise SystemExit(1)
if __name__=='__main__':main()
