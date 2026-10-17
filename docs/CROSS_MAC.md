# 두 Mac에서 이어서 개발하기

## 2026-10-18 지형 지역 원천 인수

`data/raw/supplemental/seoul_terrain/20261018/`의7파일은 약1.4MB의 서울시 공식 source 지역본이다. Git에서 함께 받아 쓰며 원본 서울 전체 ZIP은 받지 않아도 된다. EPSG5174 원본/변환·source 높이·datum 미상·공공누리1유형은 manifest와source_license를 읽는다. 로컬 좌표 JSON은 WGS84 GeoJSON과 구분한다. 이 자료는 아직 게임 높이에 연결하지 않았다.

정확한 원본 재현이 필요한 경우만 `.venv-data/bin/python tools/prepare_seoul_terrain_sources.py --download` 후 `--check`를 사용한다. 공식 익명 다운로드이며 서울 ZIP은 `/private/tmp`에만 둔다. 약45.85MB ZIP/국가 지도·캐시를 Git에 넣지 않는다. FABDEM/Mapzen은 비교 참고이며 기본 실행 의존성이 아니다.


## 2026-10-17 최신 개발 장면 인수

현재 후속 기능은 `explore_walk`이며 `Sim2Seoul.command` / `sh tools/run_exploration.sh run`으로 연다. 아래 V0/R03의 앱/성능/검수는 당시 고정 버전이다. EXP16–19는 큰 호텔 야외 풀·직접 옥상 접근/이탈·보행 우회·SFC 에스컬레이터/새 운동기구·거리 생활/안내/음악을 포함한다. 출처·선택 이유·미구현 교통 계획까지 `PROJECT_CONTEXT`와 `WORK_STATUS`에 함께 공유한다.

Git으로 새로 받은 WAV/PNG/GLB의 import 캐시는 각 Mac에서 필요하다. 실행기가 정식 Godot의 headless import를 먼저 마친 뒤 게임을 연다. 캐시는 저장소에 넣지 않는다. 기존 준비대로 지역 데이터/가상환경을 준비하면 국가 전체 자료를 다시 받을 필요가 없다. 현재 기능 검증은 M1 Pro16GB/macOS27.0이며 M4 Pro/추가 Mac 검증이나 새 앱 export를 대체하지 않는다.

전용 저장소: [codemillss/Sim2Seoul](https://github.com/codemillss/Sim2Seoul). 비공개 저장소이므로 GitHub 계정에 접근 권한이 필요하다. 이 프로젝트 폴더에는 독립 `.git`을 사용한다.

각 준비 절의 결과·다음 단계는 해당 작업 당시의 범위다. 최신 개발 실행은 아래 R02의 `v0_walk`이며, N04에서2NPC/2차량을켠W04필수동선을26분연속검수했다. 현재 M1의고정1920×1080성능은R01로측정했고품질/메뉴회귀는R02로확인했다. R03은 같은 V0의 M1 로컬 앱 검수를 완료했고 R04는 M4 UNRUN 대안으로 판정했다. 진행 상태는 [WORK_STATUS](WORK_STATUS.md)를 따른다. M4·사람조작감·현실지형/접근은별도다.

## 공유되는 것

- 코드·데이터 준비 도구·설정·32개 작업 계획·결정 이유·실행 이력·검증 증거.
- 루트 `AGENTS.md`와 프로젝트 맥락·현재 상태: 다른 기기의 새 에이전트가 읽을 시작 지침.
- 현재 지역 지도 `data/raw/deoksugung_cityhall-v2.osm.pbf` — 188,346 bytes.
- 비교용 이전 지역 지도 `data/raw/deoksugung_cityhall.osm.pbf` — 187,286 bytes.
- 지도 출처·ODbL 표시·스냅샷 SHA-256과 고정 Python 의존성.
- D03 Overture 지역 건물 GeoJSON 497,524 bytes와 DSM 지표 참고 사본 5,356 bytes, 취득·검증·접근 제한 기록.

국가 전체 PBF·전체 DSM 타일·컬럼 정의서/공식 안내 HTML, `.venv-data`, `data/processed`, Godot 캐시와 빌드 파일은 각 기기의 로컬 자료다. 지역 지도가 포함돼 있으므로 평소 개발을 재개할 때 대형 원본을 다시 받을 필요가 없다. 참고 HTML이 없어도 공유 조사 요약과 URL·해시 기록으로 이어갈 수 있다.

## 다른 Mac의 최초 준비

Git과 Python 3.14를 준비한다. Python 환경은 기기별로 만들며 `.venv-data`를 복사하지 않는다. 다음은 아직 `Sim2Seoul` 폴더가 없는 위치에서 실행한다.

```sh
git clone https://github.com/codemillss/Sim2Seoul.git
cd Sim2Seoul
bash tools/setup_mac.sh
```

GitHub HTTPS 인증이 준비되지 않았고 해당 Mac의 SSH 인증이 이미 설정돼 있다면 복제 명령은 다음을 사용한다. 인증 정보나 SSH 개인키를 저장소에 넣지 않는다.

```sh
git clone git@github.com:codemillss/Sim2Seoul.git
```

Python 명령 이름이 다르면 Python 3.14를 가리키는 실행 파일을 지정한다.

```sh
SIM2SEOUL_PYTHON=python3 bash tools/setup_mac.sh
```

준비 도구는 공유 지도와 D03 참고 파일의 해시를 확인하고, 고정 의존성을 설치하며, 현재 지역 지도로 미리보기·G01 좌표 기준·G02 미터 도형과 검사, G03 높이·지면 분류와 검사, G04 이동/경계 후보와 검사, E03 표시 삼각형·실행 자료와 E04 고정 거리/기준물 실행 자료를 재생성한다. 전국 원본과 게임 엔진은 설치하지 않는다. E01에서 현재 M1에 Godot **4.7.2 Standard·Forward+/Metal**을 설치하고 실제 편집기·GPU 창을 확인했다. 다른 Mac에는 [엔진 환경](environment.md)의 공식 동일 버전 설치·체크섬·기동 절차를 따른다. 템플릿은 장면 실행에 필요하지 않으며 R03 전에 4.7.2.stable로 준비한다.

환경 설치 전 지도 파일만 확인하려면 다음을 실행한다.

```sh
python3 tools/check_checkout.py
```

## 작업을 이어가는 순서

1. 작업 시작 전 `git status --short --branch`로 남은 변경과 브랜치를 확인한다. 깨끗한 상태에서 `git pull --ff-only`로 최신 내용을 받는다. 미완료 변경이 있으면 먼저 보존하고, 원격 변경과 비교한 뒤 통합한다. 양쪽에 서로 다른 커밋이 있어 fast-forward가 불가능하면 중단 이유를 확인하고 안전하게 합친다. 강제 덮어쓰기는 하지 않는다.
2. 루트 `AGENTS.md`의 순서대로 `PROJECT_CONTEXT` → `WORK_STATUS` → `SOL_HANDOFF`를 확인한다. 처음에는 전체 계획도 파악하고, 이후에는 수행할 작업 ID와 관련 계약·검증만 읽는다. 과거 수정 이유는 `EXECUTION_LOG`에서 찾는다.
3. 해당 작업을 수행·검증하고 WORK_STATUS의 결과·다음 행동을 갱신한다. EXECUTION_LOG에는 입력·실제 시도·수정·검증·한계를 추가한다. 결정이나 계약이 달라졌으면 그 문서도 함께 갱신한다.
4. 의도한 파일을 선택해 커밋한다. `git diff --cached --check`와 파일 목록을 확인하고, 사용자가 요청한 공유 범위에서 `git push`한 뒤 원격 커밋을 대조한다.
5. 다른 Mac에서는 최신 커밋을 받은 뒤 같은 진행 기록을 이어간다. 같은 파일을 두 기기에서 동시에 수정했다면 변경을 비교해 합친다. 강제 push를 사용하지 않는다.

기능 작업용 새 브랜치 이름은 `codex/<작업명>`을 기본으로 한다. 최초 공유 상태와 정리된 작업은 `main`에 둔다. 두 Mac에서 동시에 개발할 때는 독립 작업을 서로 다른 브랜치로 맡고 같은 미완료 작업을 중복 실행하지 않는다. 기록을 로컬에만 남기면 다른 Mac이 볼 수 없으므로 작업 산출물과 기록을 같은 커밋으로 공유한다.

새 에이전트에게 전달할 짧은 요청은 [SOL_HANDOFF](SOL_HANDOFF.md)의 예시를 사용할 수 있다. **현재 다음 작업은 WORK_STATUS가 기준**이며 과거 실행 보고서의 `next_task`로 되돌아가지 않는다.

## 국가 원본이 필요한 경우

일반 지역 감사는 공유된 작은 지도만 사용한다.

```sh
.venv-data/bin/python tools/prepare_osm.py audit data/raw/deoksugung_cityhall-v2.osm.pbf
```

`tools/review_osm_extract.py`는 국가 원본과 지역 전체를 다시 대조하는 선택 작업이다. 이 전체 D02 검사를 재실행하거나 조사 범위를 넓힐 때만 [날짜 고정 국가 원본](https://download.geofabrik.de/asia/south-korea-261009.osm.pbf)을 `data/raw/geofabrik/south-korea-261009.osm.pbf`에 받아 manifest의 SHA-256과 대조한다.

기대 SHA-256:

```text
70007aa979f8e362ca609fdc2d6302164c2f1379f11c8fc5fd39a7a2e79d3c17
```

국가 원본이 없는 복제본에서도 기존 D02 증거를 읽고 D03 이후를 진행할 수 있다. 국가 원본을 받기 전 전체 검토 도구를 실행하면 필요한 파일과 선택 작업이라는 안내가 표시된다.

## 검증 범위

D03 상세 원천 비교와 DSM 검사를 다시 실행할 때만 추가 도구를 설치한다. 기본 작업 재개에는 이 설치나 원본 재취득이 필수가 아니다. 지표 고도는 보행 지면으로 사용하지 않으며 [D03 보고서](evidence/D03_SUPPLEMENTAL_REVIEW.md)의 한계를 유지한다.

```sh
.venv-data/bin/python -m pip install -r requirements-supplemental.txt
.venv-data/bin/python tools/review_supplemental.py --report /tmp/sim2seoul-d03-review.json --no-map
```

전체 DSM 타일이 없는 Mac에서는 지역 사본을 검사하고 전체 타일 비교 2개는 미실행으로 남긴다. 상세 검토 보고서는 `/tmp`에 만들고 공유된 과거 결과를 덮어쓰지 않는다.

D04 원천 사용 규칙·수동 검토 큐는 Git에 포함된다. 원문 높이/층수와 결손 집계만 다시 확인할 때는 기본 준비 후 `python3 tools/audit_data_gaps.py --report /tmp/sim2seoul-d04-audit.json`을 사용한다. 이 검사는 추정값이나 게임 자산을 만들지 않는다.

G01을 재확인할 때는 데이터 환경에서 다음을 실행한다. 가공 좌표 기준은 각 기기에 생성되고 동일 기준점·원점·검사 증거는 공유된 [coordinate_check.json](../data/reports/coordinate_check.json) 안에도 있다. 이는 수평 수학 검사이며 Godot·지면·M4 실제 실행 검증을 대신하지 않는다.

```sh
.venv-data/bin/python tools/check_coordinates.py --report /tmp/sim2seoul-g01-check.json --reference /tmp/sim2seoul-g01-reference.json
```

G02 가공 도형은 Git에 넣지 않으며 기본 준비에서 재생성된다. 기존 준비 환경에서는 다음을 실행한다. 본체 후보·부분/지붕 참조·겹침 보류 역할과 원본 위경도를 함께 보존한 JSON이며 지면/높이/충돌은 아직 없다.

```sh
.venv-data/bin/python tools/prepare_features.py
.venv-data/bin/python tools/check_geometry.py --report /tmp/sim2seoul-g02-check.json
.venv-data/bin/python tools/test_geometry_contract.py --report /tmp/sim2seoul-g02-regression.json
```

G03 가공물 `heights.json`·`terrain.json`도 Git 제외이며 기본 준비에서 재생성한다. 정책/큐를 변경했다면 먼저 G02를 다시 생성·검사한 뒤 진행한다. G03 생성기는 현재 `data/reports/geometry_check.json`을 필수 입력으로 읽으므로 아래 순서를 따른다.

```sh
.venv-data/bin/python tools/prepare_features.py
.venv-data/bin/python tools/check_geometry.py
.venv-data/bin/python tools/prepare_heights.py
.venv-data/bin/python tools/check_heights.py --report /tmp/sim2seoul-g03-check.json
.venv-data/bin/python tools/test_height_contract.py --report /tmp/sim2seoul-g03-regression.json
```

[G03 검토](../data/reports/height_review.md)에는 임시 계수/지면·132개 예외·잠정 본체 선택과 상세 외형의 미확인 부분을 남겼다. [별도 사본 검사](../data/reports/g03_verification.json)는 현재 M1의 기존 인터프리터로 두 번 생성해 높이/지면 결과와 수동 입력 보존을 확인한 증거다. 새로운 환경 설치나 M4 기기 검증으로 확대하지 않는다.

G04의 `walkable_areas.json`·`driveable_areas.json`·`boundary_candidate.json`도 Git 제외 재생성 입력이다. 파일 이름이 통행 가능성을 확정하지 않는다. 기존 준비 환경에서는 G02/G03의 현재 검사 후 다음을 실행한다.

```sh
.venv-data/bin/python tools/prepare_movement.py
.venv-data/bin/python tools/check_movement.py --report /tmp/sim2seoul-g04-check.json
.venv-data/bin/python tools/test_movement_contract.py --report /tmp/sim2seoul-g04-regression.json
```

[G04 인수 검사](../data/reports/g04_verification.json)는 국가 원본·전체 DSM 없는 파일 사본과 기존 M1 인터프리터의 재현 증거다. 새 설치·M4·게임 시험과 구분한다. SVG 지도는 공유되며 재생성은 `tools/map_movement.py`, 선택 PNG 렌더는 별도 도구이며 기본 준비의 의존성은 아니다. 최종 경계·스폰·gate·실제 통행 검증은 남아 있다.

현재 기기에서 국가 원본이 없는 새 복제본과 새 Python 3.14 환경으로 지역 지도 검사·미리보기 재생성을 확인했다. 준비 후 추적 파일 변경도 없었다. [준비 검증 기록](../data/reports/git_portability_check.json)을 참고한다. 실제 M4 Pro의 실행/성능 검증은 R04에서 별도로 기록한다. E02 정식 구조·입력/메뉴에 이어 E03 서울 표시와 별도 게임 사본 GPU 기동을 확인했다. W01의 제한된 대한문 밖↔경내 입구 보행은 구현했고 전체 경로는 후속이다.

## 엔진 기동 확인

Godot 설치 뒤 저장소 루트에서 다음을 실행한다. 지도/Python 준비와 독립적이다. 버전·실제 renderer/driver·화면·종료를 확인하며 새 결과는 Git 제외 캐시에 기록된다. 자세한 설치/후보 비교는 [환경](environment.md), 현재 M1 증거는 [기동 결과](../data/reports/engine_startup.md)를 따른다.

```sh
sh tools/run_engine_smoke.sh editor
sh tools/run_engine_smoke.sh run
sh tools/run_engine_smoke.sh observe
```

M4 Pro의 RAM/OS와 실제 기동은 아직 미확인이다. M1의 보고서를 다른 기기의 결과로 복사해 완료 처리하지 않는다.

## 정식 프로젝트 실행

E03/E04 정식 프로젝트는 [GAME_PROJECT](GAME_PROJECT.md)를 따른다. 최초 `setup_mac.sh`가 지역 지도에서 현재 G01–G04 가공물·E03 삼각형/실행 manifest·E04 기준점/시점 manifest를 만든다. 준비된 기존 환경에서 표시 입력만 갱신하면 아래 생성기를 사용한다. 엔진은 [고정 환경](environment.md)대로 별도 설치한다.

```sh
.venv-data/bin/python tools/prepare_world.py
python3 tools/prepare_game_data.py
sh tools/run_game.sh run
sh tools/run_game.sh editor
sh tools/run_game.sh observe
```

아래 세 보기 버튼과 Esc 메뉴를 사용할 수 있다. 생성기에는 `.venv-data`가 필요하고 준비된 game 사본의 실제 Godot 실행에는 원본/Python/네트워크가 필요 없다. 입력 변화·누락은 확인하고 묵은 geometry로 실행하지 않는다. 생성 JSON/UID/캐시를 다른 Mac에서 복사하지 않는다.

```sh
.venv-data/bin/python tools/check_world_geometry.py
.venv-data/bin/python tools/check_world_overlaps.py
python3 tools/check_game_project.py --report /tmp/sim2seoul-e03-project-check.json
```

[E03 화면/기하·독립 검토](../data/reports/world_import.md)와 [사본 재생성](../data/reports/e03/portability_check.json)은 현재 M1·기존 인터프리터에서 얻은 증거다. 두 번 생성한 기하와 수동 결정이 같음을 확인했고 전국 원본·전체 DSM은 사용하지 않았다. E04도 [기준점·10m·고정 화면 검증](../data/reports/scale_view/README.md)을 완료했다. 새 Mac의 준비/실행은 그 기기에서 별도로 기록한다. M4 RAM·OS·GPU/성능, 직접 키 조작, 전체 경로 보행은 미검증이다. 현재 M1의 제한된 대한문 연결 보행은 W01 증거로 구분한다. P01 독립 시험장·P02 이동/지면 복귀·P03 3인칭 카메라를 완료했으며 P04 도시 정적 충돌과 W01 대한문 연결도 완료했고 다음 W02 경내 경로를 이어간다.

```sh
python3 tools/prepare_scale_view.py
sh tools/run_scale_view.sh run
sh tools/run_scale_view.sh observe
.venv-data/bin/python tools/check_scale_contract.py
```

생성 `scale_view.json`·`scale_manifest.json`도 기기별이며 Git에 넣지 않는다. 공유 설정/장면/기준점 보고서에서 재생성해 같은 위치·축·단위와 세 시점을 확인한다. 검사 도구는 현재 Mac의 Godot을 사용하므로 실제 M4 실행 결과를 별도로 남긴다.

## P01 독립 시험장만 먼저 확인하기

동일한 Godot 4.7.2와 저장소만 있으면 지도/Python 준비 전에 아래 P01 합성 시험장을 열 수 있다. 생성 자산·지도 서버·국가 원본을 요구하지 않는다.

```sh
sh tools/run_player_fixture.sh run
sh tools/run_player_fixture.sh observe
python3 tools/check_player_contract.py
```

기본 관측은 정착 후 60초이며 `observe 2`는 짧은 실행 확인용이다. 검사기는 표준 Python, 계약 검사는 macOS의 설치된 Godot/네트워크 차단 프로파일을 사용한다. 현재 M1의 60초/3,600회 안정 정지와 지도 없는 사본 검증은 [P01 보고서](../data/reports/player_scale.md)에 있다. 실제 M4·새 환경·직접 조작·서울 보행 결과는 이 증거로 대신하지 않는다. P02는 아래 별도 이동 시험장에서 같은 캐릭터/충돌을 재사용한다.

## P02 이동 시험장과 재현

지도/가공 자산 없이 동일 Godot과 저장소로 실행한다.

```sh
sh tools/run_movement_test.sh run
sh tools/run_movement_test.sh editor
sh tools/run_movement_test.sh observe
python3 tools/check_movement_contract.py --mode contract
python3 tools/check_movement_contract.py --mode gpu
```

WASD/방향키·Shift 달리기·Esc 메뉴·시작점 복귀 버튼. 녹색 램프는 단차 진입용, 거리 구간 큰 격자는5m이며 카메라는 고정이다. `observe`는 실제60fps 제한의10초 걷기/달리기·화면을 Git 제외 캐시에 저장한다. `contract`는9개 authored 파일 사본과 실제 오류6종을 가속 물리로 검사하고, `gpu`는30/60fps 조건과 실제60초 정지를 각각 실행한다. 표준 Python만 필요하며 macOS offline.sb는 시험 프로세스 네트워크만 차단한다. 다른 OS의 실행/프로파일은 별도 준비한다.

[현재 M1 증거](../data/reports/movement.md)는 새 Mac 결과가 아니다. 기기명/칩/RAM/OS·실제 렌더러와 직접 조작감을 해당 기기에서 기록하고 `.godot`/캐시·생성물/앱은 공유하지 않는다. P03의 마우스 회전/가림은 아래 별도 시험장에서 완료했다. 전체 도시 보행은 미검증이다. P04 충돌과 제한된 W01 대한문 연결 이후 다음 작업은 W02다.

## P03 카메라 시험장과 다른 Mac 인수

```sh
sh tools/run_camera_test.sh run
sh tools/run_camera_test.sh editor
sh tools/run_camera_test.sh observe
python3 tools/check_camera_contract.py --mode contract
python3 tools/check_camera_contract.py --mode gpu
python3 tools/check_camera_guard_regression.py
```

동일한 고정 Godot과 저장소만으로 지도 가공 없이 실행한다. WASD/방향키·Shift, 마우스 회전·휠 거리, Esc/돌아가기 메뉴를 사용한다. 다른 창으로 이동하면 일시 정지/마우스 해제, 돌아온 뒤 직접 재개한다. 복귀 버튼은 메뉴 안에 있고 이동키를 놓은 후 다시 시작한다. 가까운 곳에서 몸체가 잠시 숨겨지는 것은 카메라 가림 처리다.

`observe`는 실제60fps 제한에서 전체 카메라 시험/문 왕복/캡처를 캐시에 남긴다. `contract`는13개 authored 파일 사본/가속 물리/실제 오류5종, `gpu`는 실제30/60fps 입력/충돌/문 회전 시험, guard regression은 실제 코너 보완 제거1종을 별도 사본에서 검사한다. native mouse capture가 없는 headless의 모의 의도 시험은 실제 Mac 화면 결과와 구분한다. 기존 P01/P02 원본은 보존했으므로 각 독립 시험을 그대로 실행할 수 있다.

[현재 M1 카메라 증거](../data/reports/camera.md)는1152×720/기존 환경이다. 새 Mac은 칩/RAM/OS와 실제 렌더러·마우스/트랙패드 감도·창 포커스·시야를 해당 기기에서 기록한다. M4/임의 화면비·사람 조작감·도시 성능은 이 결과로 대신하지 않는다. P04 충돌 장면은 아래 절, 현재 다음 작업은 W02 경내 길·마당·전각 사이 보행이다.

## P04 충돌 시험과 W01 별도 보행 장면

기존 위 G/E03 준비를 재사용하고 정적 충돌 계획만 기기별로 생성한다.

```sh
.venv-data/bin/python tools/prepare_collision.py
python3 tools/check_collision_bundle.py
sh tools/run_collision_test.sh run
sh tools/run_collision_test.sh observe
python3 tools/check_collision_contract.py --mode contract
python3 tools/check_collision_contract.py --mode gpu
python3 tools/check_collision_rejections.py
```

생성에는 기존 Shapely 환경, 실행 도구의 사전 검사에는 표준 Python을 사용한다. 준비된 game 런타임은 지도/패키지/인터넷을 읽지 않는다. generated.json·test_support·캐시·.godot는 공유하지 않는다. 22개 authored/4개 런타임 사본의 실행과 이미 준비된32입력의 P04 동일 재생성은 [현재 M1 증거](../data/reports/collision.md)이며 전체 G 재준비·새 가상환경·M4 검증은 아니다.

WASD/Shift/마우스/휠/Esc는 시험장 조작이고 메뉴의 서울/덕수궁 보기는 고정 시점이다. 이 P04 장면의 대한문/중화문 원본 본체는 막혀 있다. 별도 W01 장면에서는 대한문 개구부·앞뒤 지면·도시 시작점/복귀를 연결했다. 다음 W02는 G04 R1과 공식 근거를 대조해 경내 상세 경로를 확장하며 중화문·금천교·계단 예외를 검토한다. 도시 보행·권한/지형·NPC 제어·사람 조작감·기기 성능을 기존 검사 통과로 대신하지 않는다.

## W01 대한문 보행과 W02 인수

위 G/E03/P04 준비를 재사용하고 새 W01 자료만 생성한다.

```sh
.venv-data/bin/python tools/prepare_daehanmun.py
python3 tools/check_daehanmun_bundle.py
sh tools/run_daehanmun_walk.sh run
python3 tools/check_daehanmun_contract.py --mode contract
python3 tools/check_daehanmun_contract.py --mode gpu
```

현재는 문 밖↔경내 입구 65.6m 연결이다. WASD/Shift·마우스/휠·Esc/밖으로 복귀 메뉴를 쓰며 지역 영역 밖은 자동 복귀한다. 자동 생성 3파일/.godot/test_support/앱/캐시는 공유하지 않는다. [현재 M1 증거](../data/reports/daehanmun_walk.md)의75개 준비 입력/도구 사본 재생성은 기존 인터프리터 검증이고 새 기기/전체 G/M4 결과가 아니다. 새 Mac의 RAM/OS/실제 render/input은 해당 기기에서 확인한다. 다음 W02는 안쪽 n/921242931부터 기존 R1 원문/수직 예외/중화문·금천교·계단을 대조해 전각 앞 경로를 확장한다.

W01 자동 GPU 판정은 12카메라 시점과 중립 정지의 준비 후 결과다. 측정 과정의 실제 이동/Shift 키 바인딩은 시험 프로세스에서만 제거하며 일반 `run`에는 그대로다. 기존 정지/관통/시간 허용치는 유지했고 초기 기동·첫 렌더링 끊김과 사람/OS 조작은 별도 검증이다. 준비 시간·pipeline count·입력 격리·최초 실패는 [W01 결과](../data/reports/daehanmun_walk.md)와 raw 기록에서 확인한다.

## W02 경내 보행 재개

위 G/E03/P04/W01 준비를 재사용한 후 다음을 실행한다. 전국 지도와 전체 DSM은 필요 없다.

```sh
.venv-data/bin/python tools/prepare_palace_walk.py
python3 tools/check_palace_bundle.py
sh tools/run_palace_walk.sh run
python3 tools/check_palace_contract.py --mode contract
python3 tools/check_palace_contract.py --mode gpu30
python3 tools/check_palace_contract.py --mode gpu60
```

원본 경내 순환 약564m와 중화전 앞마당 접근을 사용한다. 중화문/전각·기단·계단·잔디를 보존/제외하고 실제 지면 대신 명시한 지역 y=0지원면을 쓴다. 생성3파일/캐시는 공유하지 않는다. [경로 선택·실패·검증범위](../data/reports/palace_walk.md). 준비된 작은 입력의 W02-only 사본 재생성은 기존 M1 환경 검사이며 새 Mac/M4 실행을 대신하지 않는다. 새 Mac의 RAM/OS/GPU/조작은 해당 기기에서 기록한다. 사용자는 당분간 기존 계획의 구현·검증·기록·공유를 위임했으며 사람 조작 확인을 재개 조건으로 삼지 않는다.

## W03 도심·돌담길 보행 재개

위 G/E03/P04/W01/W02 준비가 끝나면 전국 지도 없이 실행한다.

```sh
.venv-data/bin/python tools/prepare_public_walk.py
python3 tools/check_public_bundle.py
sh tools/run_public_walk.sh run
```

북측 원문 횡단을 통해 시청 전면/광장 외곽, 남측 돌담길을 왕복한다. [경계·국소 보정·공사 근거·검증범위](../data/reports/public_walk.md). `play_boundary.tres`는 장면 계약이며 현실 통행 경계가 아니다. generated3파일/자동 가공/캐시/앱/가상환경을 공유하지 않는다. 작은 prepared98입력의 W03-only 사본2회 생성은 기존 M1 환경 검사다. 새 Mac의 RAM/OS/Metal/물리/실제 조작은 별도로 확인한다. W04 전체 보행의 자동 통합 결과는 아래 검증판 절을 따른다. 사용자 위임에 따라 사람 피드백 대기를 진행 조건으로 삼지 않는다.

## W04 보행 검증판 재개

위 W03 준비 뒤, 표준 Python만으로 기존5경로를 잇는 itinerary를 만든다.

```sh
python3 tools/prepare_walkable_itinerary.py
sh tools/run_walkable_milestone.sh run
```

이 명령은 일반 장면을 열며 캐릭터를 자동으로 움직이지 않는다. [직접 확인 체크리스트](WALKABLE_CHECKLIST.md)와 [W04 기록](../data/reports/walkable_milestone.md)을 따른다. 생성 itinerary/manifest·.godot·가상환경·앱은 공유하지 않는다. 작은 prepared65입력의 W04-only 사본2회 표준 라이브러리 재생성은 기존 M1 검사이며 새 설치/전체G재구축/M4 결과가 아니다. 실제 새 Mac의 RAM/OS/renderer/조작·물리는 해당 기기에서 기록한다.

W04의 현재 자동 검수판은 `W0-engineering-walk-v1`이다. 증거/문서/소스의 고정 스냅샷은 `data/reports/walkable_milestone/snapshot.json`, 준비 후 인수 재대조는 `python3 data/reports/walkable_milestone/handoff_check.py`다. 재검사는 이 스냅샷의 동일 입력·상태에서 사용하며, 의도한 변경 뒤에는 해당 새 작업의 기준을 사용한다. 과거 W03 input 해시의 저장 당시 절대 경로는 현재 체크아웃으로 재배치하며 원래 컴퓨터 폴더로 fallback하지 않는다. 아래 절은 단계별 인수 이력이며 현재 다음 작업은 WORK_STATUS를 따른다.

## L01 외형 명세 재생성

W04까지 준비한 Mac에서 다음을 실행한다. 표준 Python만 필요하며 네트워크/엔진을 호출하지 않는다.

```sh
python3 tools/prepare_landmark_spec.py
python3 tools/prepare_landmark_spec.py --check
python3 tools/check_landmark_spec.py --output /tmp/sim2seoul-l01-check.json
```

공유 대상은 수동 `data/manual/landmark_plan.json`·`landmark_references.json`과 도구·[제작 기준](landmark_reference.md)·검사 기록이다. `data/processed/landmark_spec.json`은 기기별 재생성하며 자동 가공물 Git 제외 규칙을 유지한다. prepared98입력 사본의 두 번 생성은 기존 M1에서 확인한 L01-only 검사이며 전체 GIS/새 설치/게임 실행/M4 검증이 아니다. L01 종료 당시 외형 제작 시작점은 L02였다. W04 스냅샷의 문서 해시는 당시 문서이므로 L01의 의도한 상태 변경에는 새 L01 검사/기록을 사용한다.

## L02 궁궐 외형 재생성과 실행

W04와 위 L01 자료를 준비한 뒤 실행한다. 새 의존성은 추가하지 않았으며 기존 `requirements-data.txt`의 Shapely 환경을 사용한다.

```sh
.venv-data/bin/python tools/prepare_palace_landmarks.py
.venv-data/bin/python tools/prepare_palace_landmarks.py --check
sh tools/run_palace_landmarks.sh run
```

공유하는 것은 [외형 원천](../game/assets/authored/landmarks/palace/README.md)의 recipes/생성기·새 scene/script·관측/검사와 기록이다. 실행용 `game/data/generated/palace_landmarks.json`/`palace_landmarks_manifest.json`은 기기별 생성한다. 원본 footprint·G03 높이 분류·W04 물리/경계를 유지하므로 L01과 기존 지원 자료의 준비가 먼저 필요하다. 사진/외부 모델·앱·캐시·가상환경은 포함하지 않는다.

검사를 다시 실행하려면 아래 명령을 사용한다. 결과는 Git 제외 캐시에 둔다. `gpu`는 현재 약16분 길이의 실제 전체 왕복이므로 다른 엔진이나 무거운 검사를 동시에 돌리지 않는다.

```sh
.venv-data/bin/python tools/check_palace_landmarks_portability.py
.venv-data/bin/python tools/check_palace_landmarks_contract.py --mode views
.venv-data/bin/python tools/check_palace_landmarks_contract.py --mode contract
.venv-data/bin/python tools/check_palace_landmarks_contract.py --mode gpu
```

여섯 준비 입력을 별도 폴더에서 두 번 재생성하는 검사는 현재 M1의 기존 인터프리터를 사용한다. 새 기기 설치/전체GIS 재구축·M4 실행을 완료했다는 뜻이 아니다. [현재 M1의 화면과 검사 범위](../data/reports/palace_landmarks.md)를 참고하고 새 Mac의 RAM/OS/렌더러·직접 조작은 해당 기기에서 기록한다. 현재 재개 작업은 WORK_STATUS가 기준이며 과거 절의 다음 단계 문장은 당시 이력이다.

## L03 도시 외형과 공개 모델 재생성

위 W04/L01/L02를 준비한 다음 실행한다. 기존 Shapely 환경과 고정 Godot 4.7.2를 사용하며 새 패키지/국가 지도/전체 모델 ZIP 다운로드는 필요 없다. 원본 GLB·상대 PNG·CC0 문구·취득 해시는 저장소에 포함한다. 원본 모델은 실제 SFC 복제가 아니고 수정 범위/가정은 [L03 결과](../data/reports/city_landmarks.md)에 남긴다.

```sh
.venv-data/bin/python tools/prepare_city_landmarks.py
.venv-data/bin/python tools/prepare_city_landmarks.py --check
sh tools/run_city_landmarks.sh run
```

준비할 때 GLTFDocument로 원본을 실제 읽고 실행용 `city_landmarks.json`/manifest를 만든다. 일반 실행은 만들어진 표시 배열을 읽으며 자동 probe가 없다. `GODOT_BIN`으로 고정 버전의 다른 위치를 지정할 수 있다. 원본 GLB의 `Textures/colormap.png` 상대 경로를 유지하고 `.godot`/실행 JSON/캐시는 공유하지 않는다.

편집기는 `sh tools/run_city_landmarks.sh editor`로 해당 장면을 열고 ‘현재 장면 실행’(F6)을 사용한다. 프로젝트의 기존 기본 장면은 이전 검증을 위해 유지했으므로 최신 도시 보행은 위 launcher/현재 장면으로 연다.

```sh
.venv-data/bin/python tools/check_city_landmarks_portability.py
.venv-data/bin/python tools/check_city_landmarks_contract.py --mode views
.venv-data/bin/python tools/check_city_landmarks_contract.py --mode contract
.venv-data/bin/python tools/check_city_landmarks_contract.py --mode gpu_trial
.venv-data/bin/python tools/check_city_landmarks_contract.py --mode gpu
```

`gpu`는 약16분의 실제 전체 여정이다. 측정 중 다른 엔진/무거운 검사를 동시에 돌리지 않는다. prepared14입력의 다른 폴더 재생성은 현재 M1의 기존 설치를 사용했으며 새 환경/M4 검사로 읽지 않는다. 시청13층/기존12층 추정, SFC130m/기존124m, 광장2025년 내부 변경 차이는 해결되지 않아 현재 높이·분류·지면/보행을 유지했다. 새 Mac은 RAM/OS/실제 실행과 직접 조작을 해당 기기에서 확인한다.

CC0 동봉 라이선스는 원래 CRLF/공백까지 해시에 포함된다. 저장소의 파일별 보존 규칙을 유지하며 원문을 자동 정리하지 않는다. 실제 Git 인덱스의 GLB/PNG/라이선스 바이트도 [원본과 대조](../data/reports/landmarks/l03/git_source_bytes.json)했다.


## L04 검수 재현과 다음 작업 인수

위 L03 실행 자산까지 재생성한 뒤 기존 Python/NumPy/Shapely와 동일 Godot4.7.2로 실행한다. 새 설치·국가 지도·새 모델 다운로드는 필요 없다. 실제 M4 실행을 검증한 절차로 해석하지 않는다.

```sh
.venv-data/bin/python tools/check_landmark_review.py --output data/cache/l04_headless
.venv-data/bin/python tools/check_landmark_review.py --gpu --output data/cache/l04_gpu
```

16시점80PNG와 국소 회전/문·광장 보행을 새로 기록한다. 소스/실행자산/입력/검사 또는 원관측 해시가 L03 합격본과 다르면 전체 회귀 재사용을 거부한다. 자료를 변경한 경우 해당 회귀와 인수 기록을 새 스냅샷으로 만든다. GPU 측정 중 다른 엔진/무거운 검사를 동시에 실행하지 않는다. 검수 도구는 `--engine`으로 동일 버전의 다른 설치 위치를 받으며 일반 게임은 기존 `run_city_landmarks.sh run`이다.

[L04 화면·한계·실패·재현](../data/reports/landmark_review.md)와 [인수](../data/reports/l04_verification.json)를 읽고 다음 N01을 시작한다. 돈덕전·정관헌 가림/중화문 인지와 사람 조작·M4는 미검증이다. 정보 UI·실내·엘리베이터는 질의/제안 상태이므로 자동 착수하지 않는다.


## N01 경로 계획 재생성과 N02 인수

기존 G04/W03 및 L 준비가 끝난 현재 입력을 재사용한다. 새 국가 원본/모델/패키지나 Godot 실행은 N01 생성에 필요 없다. 기존 Python3.14/NumPy/Shapely 환경에서 다음을 실행한다.

```sh
.venv-data/bin/python tools/prepare_routes.py
.venv-data/bin/python tools/prepare_routes.py --check
.venv-data/bin/python tools/check_routes.py
.venv-data/bin/python tools/check_route_rejections.py
.venv-data/bin/python tools/check_route_portability.py
```

`data/processed/npc_routes.json`·`vehicle_routes.json`은 기기에서 다시 생성한다. Git에는 수동 원천·생성/독립 검사·정상2 gzip 스냅샷과 근거/인수를 공유한다. 별도폴더 prepared23입력2회 재생성은 현재 M1 설치를 사용한 N01-only 결과이며 새Mac설치/전체GIS/M4/실제controller 결과가 아니다. SVG 경로도는 `tools/map_routes.py`로 생성하고 공유 PNG는 실제 렌더로 확인했다.

N01 종료 당시 다음N02는 [규칙](route_rules.md)·[정적 검증과 한계](../data/reports/route_review.md)·[인수](../data/reports/n01_verification.json)를 읽고 NPC 실제 왕복/정지/접촉부터 구현한다. 당시 일반게임은 기존 run_city_landmarks.sh이며 NPC/차량이 없었다. 원문/가정·모드영역·반복 guard와 미검증 차량 지지면을 유지한다.


## N02 보행자 장면 재생성·실행·인수

위 L03와 N01 준비 뒤 실행한다. 현재 일반 게임에 두 보행자가 추가된 장면이며 이전 `run_city_landmarks.sh`는 NPC 없는 기준판으로 유지한다.

```sh
.venv-data/bin/python tools/prepare_routes.py --check
.venv-data/bin/python tools/prepare_pedestrians.py
.venv-data/bin/python tools/prepare_pedestrians.py --check
sh tools/run_pedestrians.sh run
```

편집기는 `sh tools/run_pedestrians.sh editor` 뒤 현재 장면 실행(F6)이다. 앞마당/광장 전면의 청록색 capsule 각1명이 왕복한다. WASD·Shift·마우스·휠과 대한문 시작 위치는 기존과 같다. Esc 메뉴는 모두 멈추며 `보행자 이동` 스위치로 두 보행자만 정지/재개할 수 있다. 런처는 Python으로 자료를 사전 대조하고 실제 게임은 준비된 작은 자료로 오프라인 실행한다.

`pedestrians.json`/manifest·N01 두 가공 JSON과 `.godot`/환경/캐시는 Git 제외다. 공유 source/수동 계획과 도구로 재생성하며 [검증용 snapshot/실제 결과](../data/reports/pedestrians.md)를 대조한다. 준비된27입력16,327,528bytes를 다른 폴더에 복사해 두 번 생성/폴더 이동 후 같은 bytes/SHA와 입력불변을19검사로 확인했다. 기존 M1 설치에서의 N02-only 증거이며 새Mac 설치/전체GIS/M4 검증은 아니다.

N02 당시 코드·문서·검증 기록의 인수는 `python3 tools/check_pedestrians_handoff.py`, 실행 자산까지 준비한 뒤에는 `--prepared`를 덧붙인다. 이후 단계에서 갱신한 문서 SHA와 과거 snapshot의 차이는 정상이며 현재 인수는 아래 N03을 따른다. 재시험은 cache 출력 경로를 사용해 합격/실패 원기록을 덮어쓰지 않는다. N02 종료 당시 다음은 N03이었다.

## N03 차량 장면 재생성·실행·인수

위 L03/N01/N02 준비를 재사용한다. 원래 지도 추출·준비나 설치를 이유 없이 반복하지 않는다.

```sh
.venv-data/bin/python tools/prepare_routes.py --check
.venv-data/bin/python tools/prepare_pedestrians.py --check
.venv-data/bin/python tools/prepare_traffic.py
sh tools/run_traffic.sh run
```

`traffic_walk.tscn`은 N02를 상속하며 두 차량과 차량용 지원체2개를 더한다. WASD·Shift·마우스·휠은 그대로이며 `Esc`는 전체 정지, `차량 이동`/`보행자 이동`은 각 이동 스위치다. 차량은 북측 지정 횡단에서 사람을 기다리고 화면/사람/진입 조건이 맞아야 끝에서 반복한다. 바닥은 기존 y0 가정이며 W03 사람 경계·축척·원본/추정 출처를 유지한다.

`traffic.json`/manifest는 Git 제외 로컬 생성물이다. N01/N02 준비 자료와 수동 원천·공유 도구를 사용해 생성하고 [N03 결과/실패/재현](../data/reports/vehicles.md)의 snapshot과 대조한다. 준비31파일16,336,566bytes만 복사한 다른 폴더에서 두 번 생성, 폴더 이동/출력 삭제 후 같은 bytes/SHA와 입력 불변을27검사로 확인했다. 기존 Python3.14.7/Shapely2.2.0에서의 N03-only 증거이며 새Mac 설치·전체GIS·M4 검증은 아니다.

현재 인수는 `python3 tools/check_vehicles_handoff.py`, 실행 자료 준비 뒤에는 `--prepared`를 덧붙인다. 고정된 원시/판정·화면과 개발 실패를 덮어쓰지 않도록 재시험은 위 결과 문서의 cache 경로를 쓴다. 다음 N04는 두 보행자/두 차량을 켠 채 필수 보행 여정·10분 이상·각2주기·교차 정지/재개3회를 통합 관측한다. 이번 독립19case는 그 연속 보행 증거를 대신하지 않는다. 성능/패키지·사람 조작/OS·M4·실내/V0는 후속이다.

## V0 개발 자료를 처음 만드는 Mac의 추가 준비

`setup_mac.sh`의 E03/E04 준비가 끝난 새 사본에서만 다음 순서로 생성한다. 현재 사본에 같은 자료가 이미 있으면 반복하지 않는다. 각 명령의 성공을 확인한 뒤 다음으로 진행한다. `prepare_city_landmarks.py`는 Godot의 네이티브 import를 사용하므로 공식 4.7.2가 필요하며, 다른 설치 위치는 `GODOT_BIN`으로 지정한다. 이 순서의 의존성을 코드와 대조했지만, 이를 새 M4 실행 결과로 기록하지 않는다.

```sh
.venv-data/bin/python tools/prepare_collision.py
.venv-data/bin/python tools/prepare_daehanmun.py
.venv-data/bin/python tools/prepare_palace_walk.py
.venv-data/bin/python tools/prepare_public_walk.py
.venv-data/bin/python tools/prepare_walkable_itinerary.py
.venv-data/bin/python tools/prepare_landmark_spec.py
.venv-data/bin/python tools/prepare_palace_landmarks.py
.venv-data/bin/python tools/prepare_city_landmarks.py
.venv-data/bin/python tools/prepare_routes.py
.venv-data/bin/python tools/prepare_pedestrians.py
.venv-data/bin/python tools/prepare_traffic.py
```

이 자료를 기존 패키지와 대조할 때는 원 export manifest의 source/runtime SHA와 일치해야 한다. 차이가 나면 원인과 생성 조건을 확인하며 과거 manifest·raw·snapshot을 새 값으로 덮어쓰지 않는다. Python/편집기가 필요한 개발 자료 준비와, 해당 도구가 필요 없는 완성 앱 사용을 구분한다.

## R02 이후 최신 개발 장면

위 준비와 도구 검사가 끝난 뒤 최신 품질/메뉴가 있는 장면은 다음으로 연다.

```sh
sh tools/run_v0.sh run
```

기존 `traffic_walk`의 지도·충돌·두 NPC/두 차량을 상속하고 화면 품질, 설정 복원, 출처 팝업을 제공한다. 프로젝트 기본 main은 준비용 E02를 보존하므로 Godot 프로젝트를 열기만 한 화면과 위 V0 장면을 구분한다. [R02 실제 검사](../data/reports/performance_comparison.md), [M1 성능 조건](performance_notes.md)을 따른다. 새 Mac을 M1과 같은 성능으로 간주하지 않는다.

앱만 사용하려면 개발 환경을 설치하지 않고 R03에서 검증한 동일 ZIP을 별도로 옮긴다. `builds/`, 내보내기 템플릿과 캐시는 Git에 넣지 않으므로 Git pull만으로 앱 ZIP이 생기지 않는다. 코드·지도·재현 도구·보고서/해시는 Git으로 공유한다. 앱 경로·해시·실제 검증 범위와 조작법은 [실행 안내](RUN_GUIDE.md)에 기록한다. 이 경로의 로컬 파일 유무와 다른 Mac에서의 실제 실행 여부는 구분한다.

## R03 앱 사용과 R04 같은 패키지 재검수

M1의 최종 앱은 [R03 결과](../data/reports/package_check.md)와 [실행 안내](RUN_GUIDE.md)로 인수했다. M4 실행은 [UNRUN](../data/reports/performance_m4pro.json)이며, 아래는 실제 기기 접근이 생겼을 때의 재개 절차다. 기기 이름으로 M4/RAM/OS를 추정하지 않는다.

앱만 쓰려면 동일 ZIP을 별도로 옮기고 SHA-256 `feb939b72ecd9d077b563e77aeacf0b2b8d4892dc0a00800eadc68cd65d8facb`를 대조해 푼다. Godot/Python/개발 저장소가 없어도 앱 실행 자료는 포함돼 있다. 앱은 ad-hoc 로컬 서명이고 Developer ID/공증·전송 Gatekeeper는 미검증이다. macOS의 해당 앱 경고 사유를 기록하며 시스템 전체 보안 설정을 끄지 않는다.

개발 검수에는 현재 소스와 앞 절의 생성 자료, 고정 Python 환경·Shapely가 필요하다. **원본 [export manifest](../data/reports/r03/exports/final/manifest.json)를 수정하지 않는다.** 원 manifest SHA는 `65e4fd2c9858120a1fe27fb01ece028df78de291685f4b3ad01f403ebf1da3bb`다. 실제 앱/ZIP/catalog bytes를 검사한 뒤 `relocate_package_manifest.py`가 catalog/app/ZIP 경로3개와 preservation의 catalog key2개만 바꾼 파생 manifest를 만든다. 나머지 JSON 값과 역적용 복원을 검증하며 역사적인 engine/template/log 경로는 현재 기기 경로로 꾸미지 않는다.

다음 `/delivery`는 옮긴 파일을 둔 실제 폴더로 바꾼다. 앱 이름과 실행 권한·심볼릭 링크를 보존해 추출한다. 출력은 매번 새 폴더를 사용한다.

```sh
ditto -x -k /delivery/Sim2Seoul.zip /delivery/unpacked
.venv-data/bin/python -B tools/relocate_package_manifest.py data/reports/r03/exports/final/manifest.json --zip /delivery/Sim2Seoul.zip --app /delivery/unpacked/Sim2Seoul.app --catalog "$PWD/data/reports/n04/gpu_check.json" --output data/cache/r04_run01/binding
.venv-data/bin/python -B tools/check_package_contract.py data/cache/r04_run01/binding/derived_manifest.json --output data/cache/r04_run01/package_check
```

기존 package checker가 같은 source/runtime SHA, 실제 기기/release/설정·오프라인 기동·전체 여정·서명을 검사한다. 새 clone의 원천/생성 SHA가 다르면 원인을 확인하며 원 manifest/PASS 증거를 덮어쓰지 않는다. 과거 N04 인수 snapshot의 문서 SHA는 이후 기록 갱신과 다를 수 있으므로 현재 문서를 과거 값으로 되돌리지 않는다. 최신 앱 인수는 위 R03 manifest와 checker로 수행한다.

[작은 입력29검사](../data/reports/r04/manifest_relocation_checks.json)는 과거 시점의 fixture 기록이다. [최종 실제 앱/ZIP·113source 경로 검수](../data/reports/r04/final_path_binding/source_check.json)는 현재 M1에서 수행했다. 다른 clone/M4/앱 재실행 결과가 아니며 M4 기록은 계속 UNRUN이다. 실제 M4에서는 칩/RAM/OS·전원/품질/출력 크기를 기록하고 같은 검수의 raw/check/log/PNG를 별도 보존한다. OS 입력/초점과 사람 조작감, R01과 같은 성능 측정은 서로 구분한다.
