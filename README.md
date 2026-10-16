# 덕수궁과 시청 서울 시뮬레이션

덕수궁과 서울시청 주변의 실제 도로·건물 배치와 축척을 바탕으로, 캐릭터를 직접 움직여 탐험하는 개인용 3D 공간을 만든다. 궁궐과 빌딩이 공존하는 서울의 풍경을 첫 경험으로 삼고, 이후 생활 게임이나 다른 시뮬레이션으로 확장한다.

기획 기준일: 2026-10-12

## Git으로 두 Mac에서 이어가기

전용 비공개 저장소: [codemillss/Sim2Seoul](https://github.com/codemillss/Sim2Seoul).

현재 지역 지도와 비교용 이전 지도, 도구·설정·진행 기록을 공유한다. 다른 Mac에서는 복제 후 다음 준비 도구로 Python 환경과 지도 미리보기를 만든다.

```sh
git clone https://github.com/codemillss/Sim2Seoul.git
cd Sim2Seoul
bash tools/setup_mac.sh
```

Python 3.14와 저장소 접근 권한이 필요하다. [두 Mac 준비·작업 안내](docs/CROSS_MAC.md)와 [지도 출처](docs/ATTRIBUTION.md)를 참고한다.

## 다른 컴퓨터에서 같은 방향으로 시작하기

루트 [AGENTS.md](AGENTS.md)가 새 에이전트의 시작 지침이다. [프로젝트 맥락과 결정](docs/PROJECT_CONTEXT.md)에서 목표·장소 선택 이유·확정/미정을, [현재 상태](docs/WORK_STATUS.md)에서 완료 증거와 다음 행동을 확인한다. [단계별 실행 이력](docs/EXECUTION_LOG.md)에는 시도·실패·수정·검증·한계를 남긴다. 작업 산출물과 이 기록을 같은 커밋으로 공유한다.

대화 전체가 Git에 자동으로 전달되는 것은 아니다. 개발을 이어가는 데 필요한 결정과 결과는 위 문서에 저장한다. 최초 진입에는 전체 단계도 파악하고, 이후에는 수행할 작업과 관련 계약·검증만 읽는다.

## 현재 상태

최신 개발 탐험판 **EXP11·EXP12·EXP13**는 가까운 설비에서 **E로 음식 먹기·샤워·러닝머신/덤벨 운동**을 사용한다. 식사·샤워·운동 소품과 움직임, 포만감·청결도·운동 기록을 표시하며 사용 중 E로 그만둘 수 있다. 현재 완료·검증과 한계는 [WORK_STATUS](docs/WORK_STATUS.md)를 따른다.

앞선 **EXP10**은 호텔의 한식 뷔페·운동실·샤워/탕·연회 공간과, 도서관·업무·공공·주거·전시 등 용도에 맞는 시설을 제공한다. 엘리베이터 버튼에 층별 용도를 표시해 시설을 찾을 수 있다. 시설/층 구성은 게임용이며, EXP11은 이 설비에 사용 동작을 연결한다.

걷기·달리기·점프 때 몸통이 위아래로 튀고 좌우로 흔들리던 동작을 제거하고 발의 전환을 부드럽게 했다. Space를 새로 누를 때마다 공중에서도 연속 점프할 수 있고, 승강기 도착 뒤 이동키를 누른 채 새 점프가 막히던 문제와 옥상 높이 제한 복귀를 고쳤다. 팔·다리·신발이 있는 캐릭터가 실제 이동에 따라 걷고 달리며, 멈추거나 벽에 막히면 발걸음도 멈춘다.

앞선 자동문 객실·다양한 옥상과 풀 입수/부력·Space 탈출, 125개 입구 안내와 초고속(걷기8.4/달리기21m/s)도 유지한다. **`Sim2Seoul.command` 또는 `sh tools/run_exploration.sh run`**으로 연다. 시설과 실내 배치는 원본 크기에 맞춘 게임 창작이며 실제 모든 방이나 각 주소의 시설 현황을 복원한 것은 아니다. [실행 안내](docs/RUN_GUIDE.md)·[현재 검증과 한계](docs/WORK_STATUS.md). 아래 V0/R03은 원래 버전 기록이다.

2026-10-16: **M1 Pro에서 첫 탐험 V0의 로컬 앱 검수를 완료했다.** [앱 실행 안내](docs/RUN_GUIDE.md)·[실제 패키지 검증](data/reports/package_check.md)·[기기별 인수 판정](data/reports/first_version_acceptance.md). M4는 접근 불가 대안으로 UNRUN이며 OS 입력/사람 조작감·전송 Gatekeeper도 미실행이다. 다음 행동은 [WORK_STATUS](docs/WORK_STATUS.md)를 기준으로 한다. 과거 단계의 ‘다음 작업’은 해당 시점의 기록이다.

현재 개발 장면은 다음으로 연다. 처음 준비하는 Mac은 [V0 자료 생성 순서](docs/CROSS_MAC.md#v0-개발-자료를-처음-만드는-mac의-추가-준비)를 먼저 따른다. 기본 Godot 프로젝트 main은 초기 E02 장면을 보존하므로 현재 V0와 구분한다.

```sh
sh tools/run_v0.sh run
```

실제 배치·미터 축척의 대한문 밖↔경내, 중화전 앞마당·석조전 계단 아래, 시청·서울광장·돌담길을 3인칭으로 탐험한다. 걷기·달리기·마우스/휠 카메라·충돌·안전 복귀·Esc 메뉴, 두 보행자·두 차량과 사람 우선 횡단, 품질/출처 표시를 구현했다. [N03 차량 지지·교차/실패](data/reports/vehicles.md), [N04 같은 개체의 약3.33km/26분 연속 검수](data/reports/urban_motion.md), [R02 품질·메뉴](data/reports/performance_comparison.md)를 참고한다.

M1 Pro16GB의 R01은 실제1920×1080·현재2명2대·20분에서 p95 9.6133ms를 관측했다. 편집기 밖 Standard 실행의 측정이며 실제 release 앱·가벼운 품질의 성능 개선율·M4 결과로 확대하지 않는다. [측정 조건/한계](docs/performance_notes.md).

현재 지면은 임시 y=0 지원면이며 높이·문 폭·세부 외형에는 추정/수동 보정이 있다. 현장 정확도/실제 통행·사람 조작감·M4 실행은 별도다. 돈덕전·정관헌의 가림과 중화문의 약한 문 인지는 [L04 검토](data/reports/landmark_review.md)에 남겼다. 개별 건물 실내·생활AI·꾸미기는 이후 구체화할 확장 방향이다.

축척과 독립 시험장을 다시 볼 때는 [E04](data/reports/scale_view/README.md)·[사람 크기](data/reports/player_scale.md)·[이동](data/reports/movement.md)·[카메라](data/reports/camera.md)·[충돌](data/reports/collision.md)의 각 장면과 실행 방법을 따른다. 일반 사용자용 앱은 [실행 안내](docs/RUN_GUIDE.md)에 별도로 기록하며, Git pull만으로 Git 제외 앱/ZIP이 생기지는 않는다.

## 계획과 다음 작업

- [전체 계획 — 목표·8단계·완료 기준](docs/MASTER_PLAN.md)
- [세부 실행 계획 — 선행 조건·입력·산출물·검증·대안이 있는 32개 작업](docs/IMPLEMENTATION_TASKS.md)
- [Sol 인수 안내 — 필요한 문서만 읽고 이어서 실행](docs/SOL_HANDOFF.md)
- [현재 증거와 다음 작업](docs/WORK_STATUS.md)
- [선택 이유·확정 사항·미정 사항](docs/PROJECT_CONTEXT.md)
- [단계별 실행과 변경 이력](docs/EXECUTION_LOG.md)
- [좌표·자료·게임 구성 계약](docs/TECHNICAL_CONTRACTS.md)
- [보행·축척·충돌·성능·두 기기 검증 계획](docs/VALIDATION_PLAN.md)

3인칭 시험장은 `sh tools/run_camera_test.sh run`으로 연다. WASD/방향키·Shift, 마우스 회전·휠 거리, Esc 메뉴/마우스 해제를 사용한다. 창을 벗어나면 일시 정지되고 Esc/돌아가기로 재개한다. 최신 충돌 시험장은 `.venv-data/bin/python tools/prepare_collision.py` 후 `sh tools/run_collision_test.sh run`으로 연다. Esc 메뉴에서 서울/덕수궁 충돌 배치를 볼 수 있다. P04 서울 보기는 고정 시점이다. 실제 대한문 보행은 `.venv-data/bin/python tools/prepare_daehanmun.py` 후 `sh tools/run_daehanmun_walk.sh run`으로 연다. 문 밖↔경내 입구를 걸을 수 있다. 경내 순환은 `.venv-data/bin/python tools/prepare_palace_walk.py` 후 `sh tools/run_palace_walk.sh run`으로 열며 중화전 앞마당·석조전 계단 아래까지 걷는다. 도심/돌담길 연결은 W02 준비 뒤 `.venv-data/bin/python tools/prepare_public_walk.py`로 준비한다. 최신 통합 보행 검증판은 이어 `python3 tools/prepare_walkable_itinerary.py` 후 `sh tools/run_walkable_milestone.sh run`으로 연다. [직접 확인 안내](docs/WALKABLE_CHECKLIST.md). 일반 실행에서는 자동으로 움직이지 않는다.

## 사용자가 정한 방향

| 항목 | 결정 |
|---|---|
| 장소 | 덕수궁 경내, 대한문, 돌담길, 서울광장, 시청 주변 |
| 공간의 인상 | 한국의 전통 건축과 현대 서울의 빌딩이 함께 보이는 곳 |
| 지리 | 실제 도로·건물 배치와 축척 유지 |
| 시각 표현 | 실제 비례와 주요 특징을 살리고 세부 외형은 단순화 |
| 시점 | 캐릭터가 보이는 3인칭 |
| 캐릭터 | 실제 사람 정도 크기의 임시 캐릭터, 최종 외형은 추후 결정 |
| 접근 범위 | 대한문을 지나 덕수궁 안의 길·마당·전각 사이까지 탐험 |
| 보행자와 차량 | 정해진 경로를 움직이는 간단한 보행자·차량 |
| 사용 환경 | 개인 컴퓨터에서 혼자 실행 |
| 예산 | 무료 도구와 공개 데이터로 시작 |
| 확장 방향 | 생활·꾸미기·주민 또는 다른 시뮬레이션 |

덕수궁 경내를 걷는 범위는 포함한다. 전각과 일반 건물의 실내 진입 범위는 아직 정하지 않았다. 현재 게임 보행 경계는 W03의 원문 지원면/사유지 제외/차도 접속 규칙으로 구성했다. 현실 통행 경계·실측 지형과 구분한다.

## 개발 환경

| 기기 | 확인 내용 | 근거 |
|---|---|---|
| 현재 MacBook Pro | M1 Pro, CPU 8코어, GPU 14코어, 통합 메모리 16GB, macOS 27.0 | 기기에서 직접 확인 |
| 추가 MacBook Pro | M4 Pro, 저장공간 1TB, 메모리 용량 미확인 | 사용자 제공 |

M1 Pro에서도 실행되는 수준을 기준으로 삼고, 두 기기에서 같은 프로젝트를 개발한다. 2026-10-13 E01 시작 때 작업 볼륨의 여유 공간은 약 12.02GiB였다. 디스크 여유는 설치·다운로드 전에 다시 확인한다. 다른 Mac 엔진 준비는 [환경](docs/environment.md)을 따른다.

## 무료 도구 기본안

- **Godot 4.7.2 Standard 네이티브 앱:** 현재 M1에 설치하고 3D 편집기·세 렌더러의 실제 기동을 확인했다. 개발 기준은 Forward+/Metal이다. MIT 라이선스의 무료 엔진이며, E03 서울 표시·P03 시험장3인칭·P04 도시 정적 충돌을 완료했고 W01 대한문 연결 보행은 완료했고 W02 경내 순환·W03 도심/돌담길 연결과 W04 자동 통합 검수도 완료했다. 직접 사람 조작·M4는 미검증이다. [시험 장면 실행 방법](docs/environment.md).
- **Python:** 원본 자료 검사와 좌표·도형 변환에 사용한다. 현재 기기에서 사용할 수 있다.
- **OpenStreetMap:** 도로, 건물 윤곽, 보행로, 일부 담장·출입구·높이 속성을 초기 배치 자료로 확보했다. 독립 자료 대비 누락률과 실제 높이·접근 가능성 검증은 남아 있다.
- **국내 공개 공간정보:** OSM의 누락을 보완할 후보로 검토한다. 다운로드 가능 여부, 좌표계, 갱신일, 이용 조건을 자료별로 확인한다.

Godot 공식 요구사항은 간단한 3D 프로젝트의 시작 가능성을 판단하는 근거다. 도시 장면의 성능을 보장하지 않는다. 현재 macOS 27의 독립 장면 기동은 E01에서 실제 확인했고 M4·도시 성능은 별도 검증한다.

## 데이터와 공간의 원칙

1. 원본 위경도를 보존하고 미터 단위 좌표로 변환한 뒤, 지역 원점을 기준으로 **게임 공간 1단위 = 1m**를 적용하는 안으로 설계한다.
2. 원본 도형·높이, 층수에서 추정한 높이, 임시 도형을 구분한다. 추정값을 실제 측정값으로 표현하지 않는다.
3. 도로 중심선만으로 보도 폭이나 차로 폭을 확정하지 않는다. 담장, 문, 계단, 지면 높이와 보행 연결을 별도로 확인한다.
4. 지역 조사 경계와 실제로 걸을 수 있는 범위를 구분한다. 경계를 가로지르는 도형과 복합 건물의 중복도 처리한다.
5. 지형, 건물 외형, 보행·주행 경로, 캐릭터와 생활 규칙을 분리해 향후 교체와 확장을 가능하게 한다.
6. 보행자·차량의 경로 이동은 도시 분위기 표현이다. 실제 교통량이나 군중 행동을 예측하는 모형으로 간주하지 않는다.
7. 실행 중 공개 지도 서버에 계속 의존하지 않고, 준비한 자료를 로컬에서 읽는 구성을 기본안으로 삼는다.

## 첫 제작 순서와 확인 기준

| 단계 | 작업 | 통과 기준 |
|---|---|---|
| 1. 자료 확보 | 조사 구역 원본 수신, 출처·이용 조건·갱신 시점 기록 | 부분 응답이나 오류가 없는 파일과 출처 기록을 확보 |
| 2. 배치와 축척 | 도로·건물·경내 길을 지도와 대조, 좌표 변환 | 대표 지점 간 거리와 방향이 원천 데이터와 맞고 추정 항목이 구분됨 |
| 3. 첫 보행 공간 | 대한문 밖과 안을 잇는 동선, 광장, 담장과 건물 충돌 | 3인칭 캐릭터가 동선을 끝까지 이동하고 문은 통과하며 벽·지면을 뚫지 않음 |
| 4. 장소의 특징 | 대한문, 궁궐 전각, 시청과 주요 빌딩의 간결한 외형 | 실제 위치와 비례를 유지하면서 각 장소를 구별할 수 있음 |
| 5. 도시의 움직임 | 보행로와 도로를 구분한 NPC·차량 경로 | 보행자가 담장·건물을 관통하지 않고 차량이 궁궐 보행로로 진입하지 않음 |
| 6. 기기 확인 | M1 Pro에서 해상도·부하·메모리 측정, M4 Pro에서도 실행 | 동일 자료를 사용한 측정 결과를 남기고 적절한 표시 거리·그림자 설정을 정함 |

카메라가 담장이나 건물 안으로 파고들지 않는지도 첫 보행 검증에 포함한다. 현재2NPC/2차량의 p95≤33.3ms를 R02에서 채택했다. 개발 일정·낮밤/날씨·전각 실내의 확장 범위는 정하지 않았다.

## 관련 파일

- [자료 출처와 확보 상태](docs/DATA_SOURCES.md)
- [소구역 조회 준비 파일](data/queries/deoksugung_cityhall.overpassql)
- [조회 결과 기록](data/availability_check.json)

## 공식 참고 자료

- [Godot 라이선스](https://godotengine.org/license/)
- [Godot 시스템 요구사항](https://docs.godotengine.org/en/stable/about/system_requirements.html)
- [OpenStreetMap 저작권과 라이선스](https://www.openstreetmap.org/copyright)

## 이전 단계별 실행 안내

아래의 구현/다음 단계는 각 작업 종료 당시의 기록이다. 현재 V0 실행과 인수는 위 현재 상태 및 WORK_STATUS를 따른다.

L03 도시 보행 기준판은 `sh tools/run_city_landmarks.sh run`으로 연다. [L03 기존 모델 비교·도시 외형·검사/실패](data/reports/city_landmarks.md), [다른 Mac 재생성](docs/CROSS_MAC.md), [다음 행동](docs/WORK_STATUS.md)을 따른다. CC0 원본과 수정 규칙은 공유하고 생성 자산은 기기에서 다시 만든다.


L04의 [16시점 전후/눈높이·국소 보행·검사기 수정·한계](data/reports/landmark_review.md)를 공유한다. 일반 게임은 L03와 동일하며 돈덕전·정관헌 가림과 중화문의 약한 문 인지를 후속 보완으로 남겼다. 전체3.3km는 합격 당시 파일/관측 해시 일치로 재사용했고 이번 새 국소 시험과 구분했다. 사람의 장소 인상·조작/M4·현실 정확도·실내/V0 완료를 뜻하지 않는다.


N01의 [보행자·차량 경로도/정적 검증](data/reports/route_review.md)와 [교차·정지·반복 규칙](docs/route_rules.md)을 공유한다. 기존 보행선2곳·세종대로 편도2곳의 작은 계획이며 N01 당시 초기2NPC/2차량은 아직 생성하지 않았다. 원문 방향과 가정 차로 위치를 분리하고 실제 동작/차도 지지·제동/시야밖 반복은 N02/N03에서 검증한다. 자동 경로JSON은 다른Mac에서 `prepare_routes.py`로 재생성한다.


N02 당시 게임은 [보행자 실행·화면·검증](data/reports/pedestrians.md)을 따른다. L03/N01 준비 뒤 `.venv-data/bin/python tools/prepare_pedestrians.py`와 `sh tools/run_pedestrians.sh run`으로 연다. 앞마당·광장 전면에 각각1명이 왕복하고 `Esc` 메뉴의 `보행자 이동`으로 멈추거나 재개할 수 있다. 기존 지도/문·플레이어/카메라와 정적 충돌은 그대로다. 실행 자료는 기기에서 재생성하며 차량·통합 내구성·사람 조작/M4·V0는 후속이다. [단계별 현재 상태](docs/WORK_STATUS.md)·[다른 Mac 인수](docs/CROSS_MAC.md).


N03 종료 당시 게임은 [차량 지지·이동·교차·화면/검증](data/reports/vehicles.md)을 따른다. L03/N01/N02 준비 뒤 `.venv-data/bin/python tools/prepare_traffic.py`와 `sh tools/run_traffic.sh run`으로 연다. 보행자2명·차량2대가 움직이고 북측 지정 횡단에서 사람을 기다린다. `Esc` 메뉴에서 차량/보행자 이동을 각각 끌 수 있다. 차량용 평면2개를 추가하되 기존 사람 경계·문/축척/출처는 유지한다. 이후 [N04](data/reports/urban_motion.md)에서 이를 켠 채26분 필수 동선을 통합 검수했다. 다른 Mac은 [재생성/인수](docs/CROSS_MAC.md)를 따른다.
