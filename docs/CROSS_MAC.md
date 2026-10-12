# 두 Mac에서 이어서 개발하기

전용 저장소: [codemillss/Sim2Seoul](https://github.com/codemillss/Sim2Seoul). 비공개 저장소이므로 GitHub 계정에 접근 권한이 필요하다. 이 프로젝트 폴더에는 독립 `.git`을 사용한다.

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

준비 도구는 공유 지도와 D03 참고 파일의 해시를 확인하고, 고정 의존성을 설치하며, 현재 지역 지도로 미리보기·G01 좌표 기준·G02 미터 도형과 검사, G03 높이·지면 분류와 검사, G04 이동/경계 후보와 검사를 재생성한다. 전국 원본과 게임 엔진은 설치하지 않는다. E01에서 현재 M1에 Godot **4.7.2 Standard·Forward+/Metal**을 설치하고 실제 편집기·GPU 창을 확인했다. 다른 Mac에는 [엔진 환경](environment.md)의 공식 동일 버전 설치·체크섬·기동 절차를 따른다. 템플릿은 장면 실행에 필요하지 않으며 R03 전에 4.7.2.stable로 준비한다.

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

현재 기기에서 국가 원본이 없는 새 복제본과 새 Python 3.14 환경으로 지역 지도 검사·미리보기 재생성을 확인했다. 준비 후 추적 파일 변경도 없었다. [준비 검증 기록](../data/reports/git_portability_check.json)을 참고한다. 실제 M4 Pro의 실행/성능 검증은 R04에서 별도로 기록한다. E02 정식 빈 프로젝트·입력/메뉴·로컬 자료 구성은 완료됐지만 서울 메시·보행은 미구현이다.

## 엔진 기동 확인

Godot 설치 뒤 저장소 루트에서 다음을 실행한다. 지도/Python 준비와 독립적이다. 버전·실제 renderer/driver·화면·종료를 확인하며 새 결과는 Git 제외 캐시에 기록된다. 자세한 설치/후보 비교는 [환경](environment.md), 현재 M1 증거는 [기동 결과](../data/reports/engine_startup.md)를 따른다.

```sh
sh tools/run_engine_smoke.sh editor
sh tools/run_engine_smoke.sh run
sh tools/run_engine_smoke.sh observe
```

M4 Pro의 RAM/OS와 실제 기동은 아직 미확인이다. M1의 보고서를 다른 기기의 결과로 복사해 완료 처리하지 않는다.

## 정식 프로젝트 실행

E02 이후 정식 프로젝트는 [GAME_PROJECT](GAME_PROJECT.md)를 따른다. 지역 지도 가공과 독립적으로 작은 계약을 준비하며 표준 Python 3·고정 Godot만 필요하다. 다른 작업 폴더에서도 실행 도구의 절대 경로를 사용하면 같은 자료를 준비한다.

```sh
sh tools/run_game.sh run
sh tools/run_game.sh editor
sh tools/run_game.sh observe
python3 tools/check_game_project.py --report /tmp/sim2seoul-e02-check.json
```

`config/region.json`과 공유 G01 해시를 대조해 `game/data/generated/`를 재생성한다. 생성된 파일·UID·캐시를 다른 Mac에서 복사하지 않는다. E03 도시 자산 준비는 아직 없다. 현재 M1의 GPU/자동 입력 시험은 [E02 기록](../data/reports/project_setup.md), 직접 키 조작과 M4 실제 기동은 미검증이다.
