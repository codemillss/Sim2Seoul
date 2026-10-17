#!/usr/bin/env python3
"""Verify the committed EXP21 handoff; this does not rerun Godot or accept a Mac."""
from pathlib import Path
import argparse,hashlib,json
ROOT=Path(__file__).resolve().parents[1]
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--prepared',action='store_true');args=ap.parse_args()
    summary=ROOT/'data/reports/terrain_integration/20261018/summary.json'
    if not summary.exists():raise SystemExit('EXP21 final handoff has not yet been recorded')
    data=json.loads(summary.read_text());failures=[];deferred=[];checked=0
    generated_inputs={row['path'] for row in data['files'] if row.get('kind')=='generated_runtime_input'}
    for row in data['files']:
        path=ROOT/row['path']
        if row.get('kind')=='generated_runtime_input' and not args.prepared:deferred.append(row['path']);continue
        if not path.is_file():failures.append({'path':row['path'],'reason':'missing'});continue
        if path.stat().st_size!=row['bytes'] or hashlib.sha256(path.read_bytes()).hexdigest()!=row['sha256']:failures.append({'path':row['path'],'reason':'changed'})
        checked+=1
    for item in data['acceptance_reports']:
        report=json.loads((ROOT/item['path']).read_text())
        if report.get('result')!='PASS' or report.get('summary',{}).get('failed')!=0:failures.append({'path':item['path'],'reason':'nonpass'})
        for resource,expected in report.get('source_sha256',{}).items():
            path=(ROOT/'game'/resource.removeprefix('res://')).resolve()
            if not path.is_relative_to(ROOT):failures.append({'path':resource,'reason':'source_outside_project'});continue
            relative=path.relative_to(ROOT).as_posix()
            if relative in generated_inputs and not args.prepared:
                deferred.append(relative);continue
            if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=expected:failures.append({'path':relative,'reason':'acceptance_source_changed','report':item['path']})
    print(json.dumps({'result':'PASS' if not failures else 'FAIL','files_checked':checked,'acceptance_reports':len(data['acceptance_reports']),'prepared_inputs_deferred':sorted(set(deferred)),'failures':failures,'scope':'Stored shared input/code/evidence and actual acceptance-source integrity. Does not rerun engine tests, certify surveyed terrain, or accept M4/export/performance.'},ensure_ascii=False))
    raise SystemExit(1 if failures else 0)
if __name__=='__main__':main()
