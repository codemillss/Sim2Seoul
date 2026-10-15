#!/usr/bin/env python3
"""Verify saved N04 source, documentation and full continuous-motion evidence bytes."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SNAPSHOT='data/reports/n04/snapshot.json'
OUTPUT='data/reports/n04_verification.json'
BASE_COMMIT='8420ad43f496e6170dc5e6dbb3933e7b0ae72b5a'
PRESERVATION='data/reports/n04/source_preservation.json'
N03_ORIGINALS={
    'game/scripts/traffic/vehicle.gd','game/scripts/traffic/traffic_manager.gd',
    'game/scripts/traffic_walk.gd','game/scenes/npc/vehicle.tscn',
    'game/scenes/world/traffic_walk.tscn','game/resources/collision/traffic_rules.json',
    'tests/game/check_vehicles.gd','tools/prepare_traffic.py','tools/check_vehicles_contract.py',
    'tools/check_vehicles_evidence.py','tools/check_vehicles_handoff.py','tools/run_traffic.sh',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(prepared=False):
    checks=[]

    def ck(name,passed,**details):
        checks.append({'name':name,'passed':bool(passed),**details})

    def read(name):
        try:
            path=ROOT/name
            opener=gzip.open if str(path).endswith('.gz') else open
            with opener(path,'rt') as stream:value=json.load(stream)
            if not isinstance(value,dict):raise ValueError('JSON object required')
            return value
        except (OSError,ValueError,EOFError) as exc:
            ck('read:'+name,False,error=str(exc));return {}

    def table(name,values,base=ROOT):
        ck(name+'.nonempty',isinstance(values,dict) and bool(values))
        if not isinstance(values,dict):return
        for relative,expected in values.items():
            path=base/relative
            ck(name+':'+relative,path.is_file() and sha(path)==expected)

    def passed_report(name,value,task='N04'):
        rows=value.get('checks')
        ck(name,value.get('task')==task and value.get('passed') is True
           and isinstance(rows,list) and bool(rows)
           and all(isinstance(row,dict) and row.get('passed') is True for row in rows))

    snapshot=read(SNAPSHOT)
    ck('snapshot.identity',snapshot.get('schema_version')==1 and snapshot.get('task')=='N04'
       and snapshot.get('completed') is True and snapshot.get('next_task')=='R01')
    ck('snapshot.base_commit',snapshot.get('base_commit')==BASE_COMMIT)
    for section in ('source_sha256','evidence_sha256','documentation_sha256'):
        table(section,snapshot.get(section))
    sources=snapshot.get('source_sha256',{})
    evidence=snapshot.get('evidence_sha256',{})
    ck('snapshot.includes_handoff_checker',isinstance(sources,dict)
       and 'tools/check_urban_motion_handoff.py' in sources)
    if prepared:table('prepared',snapshot.get('generated_sha256'))

    required_evidence={PRESERVATION}
    for mode in ('contract','gpu'):
        prefix=f'data/reports/n04/{mode}'
        report_path=prefix+'_check.json';motion_path=prefix+'_motion_check.json'
        raw_path=prefix+'.json.gz';log_path=prefix+'.log'
        city_path=prefix+'_city_check.json';palace_path=prefix+'_palace_check.json'
        required_evidence.update((report_path,motion_path,raw_path,log_path,city_path,palace_path))
        report=read(report_path)
        passed_report(mode+'.passed',report)
        ck(mode+'.identity',report.get('mode')==mode)
        table(mode+'.engine_source',report.get('source_sha256'),ROOT/'game')
        table(mode+'.engine_proof',report.get('proof_sha256'))
        runtime=report.get('runtime_sha256')
        ck(mode+'.runtime_hashes_recorded',isinstance(runtime,dict) and bool(runtime))
        if prepared:table(mode+'.engine_runtime',runtime,ROOT/'game')
        motion=read(motion_path)
        passed_report(mode+'.independent_passed',motion)
        ck(mode+'.full_suite',any(row.get('name')=='acceptance.full_suite' and row.get('passed') is True
           for row in motion.get('checks',[]) if isinstance(row,dict)))
        passed_report(mode+'.city_retained',read(city_path),'L03')
        passed_report(mode+'.palace_retained',read(palace_path),'L02')
        raw=read(raw_path)
        ck(mode+'.retained_normal_full_record',raw.get('schema_version')==1 and raw.get('task')=='N04'
           and raw.get('suite')=='full' and raw.get('fault')=='normal' and raw.get('error')=='')
        ck(mode+'.retained_runtime_binding',isinstance(runtime,dict)
           and raw.get('bundle_sha256')==runtime.get('data/generated/traffic.json')
           and raw.get('plan_sha256')==runtime.get('data/generated/walkable_itinerary.json'))
        log=ROOT/log_path
        logged=log.read_text(errors='replace') if log.is_file() else ''
        ck(mode+'.retained_complete_log',bool(logged) and 'N04_DONE' in logged and 'ERROR:' not in logged)

    preservation=read(PRESERVATION)
    passed_report('source_preservation.passed',preservation)
    ck('source_preservation.base_commit',preservation.get('base_commit')==BASE_COMMIT)
    originals=preservation.get('sha256')
    table('source_preservation.original_source',originals)
    ck('source_preservation.original_sources_preserved',isinstance(originals,dict)
       and N03_ORIGINALS.issubset(originals),
       missing=sorted(N03_ORIGINALS-set(originals)) if isinstance(originals,dict) else sorted(N03_ORIGINALS))

    # N04 uses the existing generators; no invented N04 preparation/portability
    # gate is required. Optional review summaries are byte-bound when present.
    for name in ('summary.json','views.json'):
        relative='data/reports/n04/'+name
        if not (ROOT/relative).is_file():continue
        required_evidence.add(relative)
        value=read(relative)
        if name=='views.json' and isinstance(value.get('images'),dict):
            table('review.images',value['images'],ROOT/'data/reports/n04')
            required_evidence.update('data/reports/n04/'+p for p in value['images'])
    ck('snapshot.includes_required_evidence',isinstance(evidence,dict) and required_evidence.issubset(evidence),
       missing=sorted(required_evidence-set(evidence)) if isinstance(evidence,dict) else sorted(required_evidence))
    result={'task':'N04','passed':all(row['passed'] for row in checks),'checks':checks,
        'snapshot':SNAPSHOT,'prepared_runtime_checked':prepared,
        'scope':('Byte verification of saved N04 source, documentation, full headless/GPU continuous-motion '
                 'evidence, retained normal raw/logs, actual city/palace checks, and original N03 source/proof '
                 'preservation. Generated runtime hashes are optional. No engine rerun, new generator or '
                 'portability gate; does not accept performance, human controls, another Mac/M4 or R01.')}
    (ROOT/OUTPUT).write_text(json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False)+'\n')
    failed=[row['name'] for row in checks if not row['passed']]
    print('N04 handoff',result['passed'],len(checks),'checks',failed)
    return 0 if result['passed'] else 1


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepared',action='store_true',help='Also verify regenerated local runtime bytes')
    raise SystemExit(main(parser.parse_args().prepared))
