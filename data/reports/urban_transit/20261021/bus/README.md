# EXP25 버스 인수 증거

생산 고정본은 `source_freeze.json`에 기록했다. `city_bus_service.gd` SHA256은 `0845d2046f40ace57146b439574b6d149884d3036b416d86fb7c25ed40bf0472`, `bus_service.json`은 `a5b7c4cbc36553f022e2b0796f89acc15fdf21efa1c349ba94a557cd7077d2ea`다. 최신 정류장 수정 검증은 아래 `stopfix_final03` 및 `stop_clearance_native_query_final01`이며, 기존 final02는 수정 전 정류장의 기록으로 보존했다.

## 구현 범위

- 원본 공공 차도 면 안의 812.29164m 닫힌 게임 경로와 청색 버스 3대, 원본 보행면 대기·하차 지점 4곳을 추가했다. 모두 승하차 가능하다. 정류장은 숭례문 북측, 북창동, 서소문, 시청 남측의 북행 정차 방향이며 남행은 복귀 구간이다.
- 원본 일방통행 그래프로 이용 가능한 남측 회랑을 찾았다. 정확한 원본 남측 접합점을 쓰면 기존 차량의 가시성 보호 종점과 차체가 겹쳤다. 기존 차량·종점·카메라 보호를 유지하기 위해, 기존 공공 차도 union 안에서 앞당긴 게임 U턴으로 정했다. 실제 U턴 허가, 실측 교차로, 공식 버스 노선 재현을 주장하지 않는다.
- 최종 곡선의 최소 중심선 반경은 9.805m다. 9×2.45m 차체에 사방5cm를 더한 전체 직사각형을 0.2m 간격으로 다시 검사해 원본 공공 차도 밖 면적0을 확인했다. 기존 종점 및 그 뒤15m의 모든 승용차 상자와 최소3.559m를 띄웠다.
- 매 프레임 실제 `move_and_slide`, 전체 차체 장애물 검사, TIN 높이·기울기, 신호와 완전한 앞/뒤 차체 통과 처리를 사용한다. 닫힌 경로의 같은 물리 접점에서 arc만 다시 세며, 버스 위치를 끝에서 시작으로 옮기지 않는다.
- 정차·열린 문·같은 쪽·현재 지지면·LOS를 충족한 실제 두 문에서 fresh E로 승차한다. 하차는 fresh E 예약 후 실제 정차·현재 전체 capsule 검사에서 안전한 보행점이 확인될 때만 한다. 원래 capsule과 masks를 보존하고, 하차한 capsule의 native publication이 확인된 후 충돌 예외를 해제한다.
- 원본14대는 그대로다. 기존 차량 전용 평면 지지체4개의 명시적 `authored_flat_support`만 새버스의 충돌쌍/장애물 query에서 제외한다. 원본 차량 차체와 건물·사람·player·실제 TIN 물리는 유지한다.
- 각 버스의 실제 station/state에 기반한 도착 추정과 다음 버스를 표시하며 현재 신호 대기를 반영한다. 정차에서 앞 버스와 균등 분산 간격의 절반 이상을 확보한 뒤 출발해 뭉침을 줄인다. 교통·보행·대기 요청에 따라 실제 간격은 달라진다. 공식 배차/실시간 서울 도착 정보가 아니다.
- 보행면 대기 위치와 실제 문앞 위치를 구분한다. 원본 남행 보도 자료 공백을 채운 가상 정류장을 만들지 않았으며, 북행 보도 대기점에서 실제 문으로 접근해 E로 탄다. 대기 E는 자동 승차나 즉시 버스 생성이 아니다.

## 이전 final02 실행 결과 — 정류장 위치 수정 전

`endpoint_camera_final02.json` / `.log`: **8/8 PASS**, 실제 headless60Hz production scene.

- 기존 실제 Camera3D/frustum을 두 원본 종점 차량에 고정하고 원래 `camera_stepped`/manager guard를 호출했다.
- 기존 두 차량은 각각 (XZ) `[-44.85,414.68] waiting_obstacle`, `[-46.51,419.63] endpoint_wait`였고, 둘 다 `end_outside=false`, `allowed=false`를 유지했다.
- 그 상태에서 승객을 태운3호차가 전체812m를 완주하고 다음 정류장 하차 예약/안전 하차까지 마쳤다. 승객 부착 오차0, 최대 실제 이동step0.16811m였다.
- 실행 종료 시3대 모두 실제 이동거리가 한 바퀴를 넘었다: 1052.17m, 1009.73m, 911.02m. 각 cycle_count≥1이며 원본 경로로부터 최대 오차2.406mm 미만이었다.

`safety_final02.json` / `.log`: **18/18 PASS**, 같은 생산/JSON 해시.

- 실제 TIN-fit 3D 차체의 위/아래8corner XZ를1,626poses에서 확인해 밖으로 나온 corner0.
- 실제 움직이는 버스, 반대편, 벽, 공중의 승차 거절.
- 실제 문 주변4위치 fresh E/최근접 버스 선택/단일 승객, capsule·masks 원상 유지, 승차 전 orbit yaw 복원, 충돌쌍 해제 후 버스 밀림2mm 미만.
- 12초를 지난 문앞 대기 유지와 W를 누르는 중 fresh E 승차.
- 전체 capsule 하차 공간 차단 시 승객과 예약 유지→차단 제거 뒤 실제 안전 하차.
- 실패한 외부 목적지에서는 승객 소유 유지, 검증된 외부 이동 뒤 control과 지연 충돌쌍 해제 복원.
- 차량 checkbox/menu에서3대 동결, 원본14대 유지.

두 Godot 종료 로그의 ObjectDB/resource 경고는 SceneTree 시험 종료 시 남은 참조 경고다. 실행 중 Script ERROR는 없다. headless 검사는 native 외관, OS 키 입력 또는 GPU 성능 통과를 뜻하지 않는다.

## API와 재실행

기존 `setup`, `set_running`, `riding`, `can_interact`, `interaction_distance_m`, `handle_interact`, `prompt_text`, `viewpoint`, `cancel_ride_for_teleport`, `snapshot`을 유지했다. `buses`는 실제3대 배열이다. `active_bus()`는 승객 또는 현재 상호작용 맥락의 버스다. 기존 `.bus`도 그 맥락에 따라 바뀌므로 한 대를 고정한 검사는 `bus_singlehead()`를 사용한다. `viewpoint.id`는 기존 shortcut 호환 bookmark이며 실제 게임 정류장 ID는 `design.stops`의 `GAME-L01..04`다.

- 장기 camera/승객: `--headless --fixed-fps 60 --path game --script res://../tests/game/check_city_bus_ride_loop.gd -- --report=<새 절대경로.json>`
- 안전 회귀: `--headless --fixed-fps 60 --path game --script res://../tests/game/check_city_bus_loop_safety.gd -- --report=<새 절대경로.json>`
- 최초3대 반복 순환/문: `check_city_bus_loop.gd`. 초기1대/2정류장 검사는 역사 기록으로 유지하며 현 범위는 새검사를 사용한다.
- 원본 기하 재생성: `.venv-data/bin/python tools/prepare_city_bus_loop.py`. JSON이 바뀌면 연결된 `road_furniture`를 root가 다시 생성해야 한다.
- native 짧은 인수: root만 `--path game --script res://../tests/game/check_city_bus_loop_native.gd -- --report=<새 절대경로.json> --physics-hz=30`.120초 watchdog이며 생산 메뉴 shortcut→대기→자연 도착→명시적 safe player-door 접근 fixture→승차/실제 이동/예약 하차/카메라 복원과 native PNG3장, 별도로 표시한 실제3대 배치 aerial-camera fixture PNG1장을 만든다. 버스 위치를 fixture로 바꾸지 않는다. 이 하니스는 구문 검사만 수행했고 native 실행은 root에 넘겼다.

초기 실패와 대체된869m 경로는 `failures/index.json`에 남겼다. 이전 시도를 현재 고정본의 완료 증거로 합산하지 않았다. 출처·공식 청색 버스/쉼터 참고는 `bus_service.json.sources`에 유지하며, 사진/로고를 가져오지 않았다.

## 카메라 yaw 복원 후 final02

독립 검토에서 승차 전 rig_yaw를 저장하지만 `_restore_ride`에서 쓰지 않는 누락을 확인했다. 생산 변경은 `host.rig.yaw=float(_ride_saved.rig_yaw)` 한 줄이며, 그 줄을 제거한 해시가 이전 고정본과 정확히 일치함을 `yaw_fix_delta.json`에 기록했다. JSON과812m 경로는 바뀌지 않았다.

`safety_final02`의4개 문 위치 모두 버스 yaw -0.307621rad와 다른 승차 전 orbit yaw0.422379rad를 사용했고, 각 E 하차 뒤0.422379rad로 정확히 돌아왔다.18/18과장기 endpoint-camera8/8을 동일 수정본에서 다시 통과했다. native 하니스도 승차 전 yaw 저장/하차 복원 assertion을 추가해 parse를 확인했다. final01 원시 보고서와 `source_freeze_before_yaw_fix.json`은 보존했으며 현재 소스의 증거로 대신 쓰지 않는다.

## 횡단 통로·보행 통로 방해 수정 후 stopfix_final03

root의 실제 native 7횡단 보행에서 북창동 GAME-L02 쉼터가 원본 횡단 경로 `coverage_11414286323`/`osm:way:1230789307:highway_line`를 막았다. player가(15.1431,302.7074) 부근에서 멈췄고 camera가0.676m로 짧아졌다. root의 `acceptance/roads_native_final01` 원시 JSON·로그·PNG와, 기존 자산 `failures/bus_service_before_crossing_fix.json` 및 전체4곳의 기존 간격 계산 `failures/stop_clearance_before_fix.json`을 보존했다. 이전18+8은 이 통로 통과를 검증하지 않았으므로 그 통과만으로 실제 보행 완료를 주장하지 않는다.

`tools/city_bus_stop_placement.py`가 모든19원본 횡단선과7게임 횡단대, 전체190원본 보행 mesh, 건물·전각·장벽 mesh, 명시적 사유/출입금지 polygon을 읽는다. 횡단으로 태그된 면은 정류장 대기점 후보에서 제외한다. 전체9×2.45m 버스+5cm, 반경0.35m 대기점, roof·표지판까지 포함한 비대칭 전체 쉼터 경계가 각 횡단대에서3m 이상 떨어지도록 네 정류장 모두 다시 선정했다. 쉼터는 대기점에서3.85m 후퇴하며 전체 원본 보행 면으로부터0.5m, 원본 고형물로부터0.4m 이상 떨어지고 drive/private와 겹치지 않는다. 대기점은 원본 비횡단 보행·자전거 면 안에 남겼다. 이는 인접 게임 쉼터 배치이며 공식 정류장 실측·토지 권리·실제 버스 노선 재현을 뜻하지 않는다.

- 실제 최소 횡단대 간격3.14419m, 전체 쉼터/보행면 간격0.54465m, 쉼터/원본 건물·장벽 간격0.59628m, 대기점/전체 쉼터 간격3.075m.
- 네 정류장 station은398.0 /490.25 /567.5 /642.75m다. route812.2916388m XZ, fleet, policy와 생산 GDScript는 이전 고정본과 정확히 같다. `stop_clearance_reproduction_final01.json`에서 현재 도로 횡단대 기준 후보/증명 재현 및 road의 bus hash 일치도 확인했다. 도로 전체 파일 hash를 다시 bus에 넣지 않아 순환 의존을 만들지 않았다.
- `stop_clearance_native_query_final01.json`: **8/8 PASS**. 실제 새 쉼터의 모든 StaticBody RID를 수집해26횡단대68segment의3D box(+3m)와 충돌0, 쉼터4곳×9TIN native ray, 대기4곳의 전체 capsule, 각2문 총8개의 실제 capsule 접근·LOS를 확인했다. 각 대기점8방향 orbit은 당시 공유 camera에서 최소4.5m였다. 이는 headless 물리 query 결과이며 최종 새 camera의 native 시각·OS입력 완료 증거는 root의 별도 native 실행으로 확인해야 한다. 전체 sourcewalk 비중첩은 위 planar full-envelope certificate가 담당한다.
- `safety_stopfix_final03.json`: **18/18 PASS**. 수정된 정류장 JSON에서 앞선 승하차/소유권/차체·capsule·yaw/차단 거절/메뉴 회귀를 한 번 다시 실행했다.
- `endpoint_camera_stopfix_final03.json`: **8/8 PASS**. 원본 두 종점 차량을 실제 camera guard로 유지한 채 승객의 실제812.3317m 순환, 최대step0.168078m·부착오차0, fresh E 다음 실제 정차 하차를 확인했다. 원본14대 유지.

새 하니스는 headless/normal 양쪽에서 실행 가능하다: `--path game --script res://../tests/game/check_city_bus_stop_clearance.gd -- --report=<새 절대경로.json>`. 기존 보고서를 덮어쓰지 않는다. 수정 전 native 실패를 해결한 최종7횡단 실제 native 보행과 새 공유 camera의 외관 검사는 root가 수행한다. 이번 보고서의8+18+8은 그 실제 native 보행 완료를 대신하지 않는다.

## 버스 차체·승객 화면 보간 수정

공유 camera가 승객 좌석을 부드럽게 따라가도 차체와 `Visual/SeatedPassenger`가30Hz 물리 위치로만 보이면 서로 어긋나며 흔들려 보일 수 있었다. PilotBus의 Visual만 이전/현재 native 차체 transform을 기록하고 같은 `Engine.get_physics_interpolation_fraction()`으로 매 render frame 보간한다. priority1 물리 이동 전에 Visual local transform을 identity로 되돌리고, priority2 문·좌석 처리 후 새 위치를 기록한다. 원본14차량의 renderer나 물리/충돌·속도·신호·경로 알고리즘은 건드리지 않았다. 같은 물리 접점의 loop joint에서도 연속 보간하며 초기 setup pose에서만 history를 초기화한다.

현재 생산 hash는0845d204이며 busJSONa5b7c4c는 그대로다. `presentation_only_delta.json`은 새 Visual 표시 코드만 제거하면 이전 생산0a2da627 소스가 byte 단위로 정확히 재현됨을 기록한다. 기존 `endpoint_camera_stopfix_final03`의 물리812m 증거를 새 공유 camera 외관 통과로 확대하지 않는다.

`presentation_headless_dev01.json`: **8/8 PASS**. 30Hz 실제 버스 자연정차에서 fresh E로 승객을 태운 뒤120render에서2328표본/이동676표본과 실제 alpha0/.25/.5/.75를 관찰했다. 버스 Visual과 눈에 보이는 seated passenger의 같은 fraction 위치 오차는 최대0.0000315m, native collider 위치 변화0, priority4 물리 Visual 복원오차0(582표본)였다. 메뉴·차량 checkbox는 native와표시 pose를 모두 멈췄고 원본14·JSON도 유지했다. `safety_presentation_final04.json`: 같은0845d204/a5b7c4c에서 **18/18 PASS**.

이는 실제 render callback과 native 물리 상태를 관찰한 headless 검사다. 최종 GPU 화면·공유 camera·OS입력 인수는 root의 native 결과로 따로 확인한다. 새 focused 하니스: `--headless --fixed-fps 120 --path game --script res://../tests/game/check_city_bus_presentation.gd -- --report=<새 절대경로.json>`.
