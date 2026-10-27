#!/usr/bin/env python3
"""Exercise the actual local Vinext/D1 routes using its official mock sign-in.

Never accepts a production origin, account header, bearer argument or cookie file.
One seeded development identity is not proof of two production accounts.
"""
import argparse
import http.cookiejar
import json
from pathlib import Path
import re
import time
import urllib.error
import urllib.request
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--origin', required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'http://127\.0\.0\.1:[0-9]{1,5}', args.origin):
        parser.error('Only an explicit loopback development origin is allowed')
    if args.report.exists():
        parser.error('Choose a fresh report path')
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
    checks = []
    token = ''
    room = ''
    self_id = ''

    def request(path, data=None, authenticated=False):
        headers = {'User-Agent': 'Sim2Seoul local Worker integration check/1.0', 'Origin': args.origin}
        if data is not None:
            headers['Content-Type'] = 'application/json'
        if authenticated:
            headers['Authorization'] = 'Bearer ' + token
        req = urllib.request.Request(args.origin + path, data=None if data is None else json.dumps(data).encode(), headers=headers)
        try:
            response = opener.open(req, timeout=10)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            return response.status, json.loads(response.read())

    def check(name, passed, status=None):
        checks.append({'name': name, 'passed': bool(passed), **({} if status is None else {'status': status})})
        if not passed:
            raise RuntimeError(name)

    def entity(id_, kind, position):
        return {'id': id_, 'kind': kind, 'position': position, 'rotation': [0, 0, 0], 'velocity': [0, 0, 0], 'motion': 'ai' if kind == 'vehicle' else 'idle'}

    record = {'task': 'EXP41_LOCAL_WORKER_D1_WORLD', 'origin': args.origin,
              'scope': 'Actual local Vinext Worker and D1, one official starter mock identity. Synthetic bounded three-entity catalog. No injected identity headers or production requests; not two-account gameplay or capacity acceptance.'}
    try:
        status, value = request('/api/multiplayer/status')
        check('anonymous_status_requires_sign_in', status == 200 and value.get('signInRequired') is True, status)
        status, value = request('/signin-with-chatgpt?return_to=%2Fapi%2Fmultiplayer%2Fstatus')
        check('official_local_mock_sign_in', status == 200 and value.get('signInRequired') is False, status)
        poses = [entity('car:sejong_south', 'vehicle', [0, 0, 0]), entity('npc:fixture', 'npc', [1, 0, 1]), entity('npc:fixture:dog', 'dog', [2, 0, 0])]
        status, value = request('/api/multiplayer/rooms', {'buildId': 'sim2seoul-shared-world-v2', 'avatar': {'modelId': 'SeoulResident_M01', 'bodyProfile': 'standard', 'swimwear': False}, 'position': [0, 0, 0], 'yaw': 0, 'world': {'entities': poses}})
        check('create_world_on_actual_D1', status == 201 and value.get('world', {}).get('version') == 1, status)
        token, room, self_id = value['sessionToken'], value['room']['id'], value['selfId']
        check('host_and_fixed_catalog', value['world']['hostId'] == self_id and len(value['world']['entities']) == 3)
        sequence = 0
        position = [0, 0, 0]

        def sync(action_type=None, target=None, drive=None):
            nonlocal sequence, value, position
            time.sleep(.6)
            sequence += 1
            data = {'sequence': sequence, 'position': position, 'yaw': 0, 'motion': 'idle', 'world': {'sequence': sequence, 'entities': poses}}
            request_id = str(uuid.uuid4()) if action_type else None
            if action_type:
                data['actions'] = [{'requestId': request_id, 'type': action_type, 'entityId': target}]
            if drive:
                data['drive'] = drive
            code, value = request(f'/api/multiplayer/rooms/{room}/players/{self_id}/sync', data, True)
            check(f'sync_{sequence}_actual_worker_CAS', code == 200, code)
            position = next(row['position'] for row in value['players'] if row['id'] == self_id)
            if request_id:
                receipt = next(row for row in value['world']['actionResults'] if row['requestId'] == request_id)
                check(action_type + '_approved', receipt['ok'])
            return value['world']['entities']

        rows = sync('npc_greet', 'npc:fixture')
        check('greeting_visible_in_world', next(row for row in rows if row['id'] == 'npc:fixture')['reactionKind'] == 'greet')
        rows = sync('vehicle_enter', 'car:sejong_south')
        car = next(row for row in rows if row['kind'] == 'vehicle')
        check('exclusive_driver_lease', car['driverId'] == self_id and car['mode'] == 'driven')
        rows = sync(drive={'entityId': car['id'], 'leaseEpoch': car['leaseEpoch'], 'sequence': 1, 'position': [3, 0, 0], 'rotation': [0, 0, 0], 'velocity': [6, 0, 0]})
        check('driver_pose_and_activity', next(row for row in rows if row['kind'] == 'vehicle')['position'] == [3, 0, 0] and next(row for row in value['players'] if row['id'] == self_id)['activity']['kind'] == 'vehicle')
        rows = sync('vehicle_exit', car['id'])
        check('released_car_remains_parked', next(row for row in rows if row['kind'] == 'vehicle')['mode'] == 'parked')
        rows = sync('npc_pet', 'npc:fixture:dog')
        check('dog_reaction_visible_in_world', next(row for row in rows if row['kind'] == 'dog')['reactionKind'] == 'pet')
        code, value = request(f'/api/multiplayer/rooms/{room}/players/{self_id}/leave', {}, True)
        check('host_leave_closes_world', code == 200 and value.get('left') is True, code)
        code, _ = request(f'/api/multiplayer/rooms/{room}/players/{self_id}/snapshot', authenticated=True)
        check('closed_world_no_longer_readable', code == 404, code)
        record['result'] = 'PASS'
    except Exception as error:
        record['result'] = 'FAIL'
        record['failed_case'] = str(error) if isinstance(error, RuntimeError) else type(error).__name__
    finally:
        # Best effort cleanup uses memory-only session material; never serialize it.
        if room and token:
            try:
                request(f'/api/multiplayer/rooms/{room}/players/{self_id}/leave', {}, True)
            except Exception:
                pass
        token = room = self_id = ''
    record['checks'] = checks
    record['passed'] = sum(row['passed'] for row in checks)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open('x') as file:
        file.write(json.dumps(record, indent=2) + '\n')
    print(json.dumps({'result': record['result'], 'passed': record['passed'], 'checks': len(checks), 'report': str(args.report)}))
    raise SystemExit(0 if record['result'] == 'PASS' else 1)


if __name__ == '__main__':
    main()
