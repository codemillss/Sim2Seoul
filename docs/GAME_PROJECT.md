# 정식 Godot 프로젝트와 데이터 경계

2026-10-13 · E03/E04/P01/P02/P03/P04 · [충돌](../data/reports/collision.md) · [카메라](../data/reports/camera.md) · [이동/복귀](../data/reports/movement.md) · [서울 표시](../data/reports/world_import.md) · [거리·축척](../data/reports/scale_view/README.md) · [사람 크기·시험장](../data/reports/player_scale.md) · [E02 준비 당시 증거](../data/reports/project_setup.md)

## 실행과 보기

고정 환경은 Godot **4.7.2 Standard·Forward+/Metal**이다. 새 Mac은 [CROSS_MAC](CROSS_MAC.md)의 작은 공유 지도 준비와 [엔진 설치](environment.md)를 먼저 수행한다. 기존 G01–G04 환경에서 E03 자료를 처음 만들거나 관련 입력을 변경했을 때만 실행한다.

```sh
.venv-data/bin/python tools/prepare_world.py
python3 tools/prepare_game_data.py
```

이후 실행 도구가 소스 최신성·manifest를 확인해 게임을 연다.

```sh
sh tools/run_game.sh run
sh tools/run_game.sh editor
sh tools/run_game.sh observe
```

아래 버튼으로 **전체 배치 / 위에서 보기 / 덕수궁 가까이**를 선택한다. Esc는 메뉴를 열고 Esc나 **돌아가기**로 닫으며 **종료**로 끝낸다. 실제 사람 이동·마우스 회전은 아직 없다. `observe`는 약 12초의 장면 처리 후 PNG/JSON/로그를 Git 제외 `data/cache/game/`에 남기고 종료한다. 12초는 기동 시간·도시 성능 측정이 아니다.

실행 준비의 삼각분할은 `.venv-data` Shapely 환경이 필요하다. 준비된 `game/` 사본을 Godot으로 실행할 때는 Python·원본·인터넷·내보내기 템플릿이 필요 없다. `run_game.sh`의 자료 확인은 엔진 밖의 표준 Python이다. 새/오래된 자산을 좌표 기본값으로 조용히 대체하지 않고 재생성 안내를 낸다. 엔진/Python 위치가 다르면 `GODOT_BIN`·`SIM2SEOUL_PYTHON`을 지정한다.

### E04 고정 검증 화면

```sh
python3 tools/prepare_scale_view.py
sh tools/run_scale_view.sh run
sh tools/run_scale_view.sh editor
sh tools/run_scale_view.sh observe
```

[scale_view.tscn](../game/scenes/tests/scale_view.tscn)은 같은 base_world를 표시하고 G01 외곽점·4쌍 직선거리·5방향 10m 기준물·시험 큐브를 추가한다. 좌표/도시 메시 변환은 identity이고 플레이어·충돌은 없다. `config/scale_view.json`에 세 시점을 저장했으며 화면 아래 버튼과 Esc 메뉴로 확인한다. `observe`는 세 시점/메뉴와 실제 메시·기준물·카메라 측정값을 Git 제외 `data/cache/scale/`에 남기고 종료한다. 직접 키보드·마우스 사용성 검사는 별도다.

`prepare_scale_view.py`는 현재 E03 계약/입력과 G01 로컬 기준점=공유 보고서, region 해시를 먼저 확인한다. Git 제외 `game/data/generated/scale_view.json`·`scale_manifest.json`을 생성하며 E03 world 해시와 정확 실행 경로를 연결한다. `scale_config.gd`는 해시/크기·자료 정의/숫자·축·시점 형식을 확인해 잘못된 자료를 거부한다. 대표점은 출입구/중심/스폰이 아니며 가려지지 않는 선·큐브는 합성 검사용 표시다.

독립 검사기는 원본 경위도를 재투영해 실제 engine global 정점/선/변환과 대조한다. `.venv-data/bin/python tools/check_scale_contract.py`로 네트워크 차단 game 사본에서 정상/10종 실제 변형·11종 자료 거부·재생성을 다시 검사한다. [E04 결과/정확한 방법·한계](../data/reports/scale_view/README.md)를 따른다.

## 장면과 입력 역할

```text
Main                          # 계약/표시 연결·안내·메뉴, ALWAYS
├── World (base_world)        # 지면/건물/길/담장 표시, PAUSABLE
│   ├── Ground
│   ├── Buildings
│   ├── Routes
│   └── Barriers
├── Actors                    # PAUSABLE
│   └── PlayerSlot            # P01의 빈 자리, 기본 위치는 스폰이 아님
├── Presentation              # 고정 카메라·낮 조명·표시 원점/북쪽, PAUSABLE
├── InputRouter               # 정규화한 입력 의도·Esc, ALWAYS
└── Interface                 # 안내/보기 버튼/메뉴·원천 표시, ALWAYS
```

[main](../game/scenes/main.tscn)·[base_world](../game/scenes/world/base_world.tscn)·[loader](../game/scripts/base_world.gd)가 실행 장면이다. E02의 [빈 역할 장면](../game/scenes/world/world_root.tscn)은 보존하지만 현재 main은 base_world를 쓴다. 월드/역할/메시 변환은 identity·scale 1이며 이미 변환된 XZ 미터 좌표를 다시 투영/이동/축 반전하지 않는다.

메뉴는 SceneTree를 멈추고 이동/빠른 이동 의도를 0/false로 차단한다. World/Actors/Presentation은 명시 PAUSABLE로 두며 재개 시 초점을 해제한다. [InputMap](../game/project.godot)은 물리 키 W/↑, S/↓, A/←, D/→·Shift·Esc를 등록한다. [InputRouter](../game/scripts/input_router.gd)는 대각선 길이 ≤1인 의도만 전달한다. P02 별도 시험장에서 걷기/달리기·카메라 기준 이동을 연결했다. P03 별도 카메라 시험장에 마우스 잠금·3인칭 회전을 연결했다. 점프/실내/새 게임 규칙을 자동 추가하지 않는다.

## 원본 → 가공 → 실행 경계

| 경로 | 역할 / 공유 |
|---|---|
| `config/region.json` | 좌표 값의 단일 원천, 공유 |
| `config/world_display.json` | 색·시점·표시용 오프셋/담장 두께 가정, 공유 |
| `data/raw/`, `data/manual/` | 원본·검토 입력. Godot이 읽지 않음 |
| `data/processed/` | G01–G04 미터 도형/높이/지면/후보, 기기별·Git 제외 |
| `tools/prepare_world.py` | 검증된 가공물의 표시 삼각형 생성, 공유 |
| `game/resources/world_geometry/world.json` | 약 5.04MB 생성 결과·출처/보류 ID, Git 제외 |
| `game/resources/world_config.tres` | manifest 경로만 보유. 좌표 숫자를 중복 작성하지 않음 |
| `game/data/generated/region.json` | region 원본 바이트 사본, Git 제외 |
| `game/data/generated/manifest.json` | v2/E03_display_only·region과 world 해시/크기, Git 제외 |
| `game/assets/authored/` | 이후 수동 모델 소스, 현재 모델 없음 |
| `game/assets/generated/` | 이후 별도 생성 모델 경계, 현재 없음 |

[prepare_game_data.py](../tools/prepare_game_data.py)는 G01 region 해시와 E03의 28개 필수 원천·정책·검토/근거/생성기 입력을 확인한다. 필수 해시 누락/중복·현재 파일 변경·오래된 사본은 거부한다. `--check`는 현재 사본의 바이트 일치도 검사한다. 원본 갱신 때 새 스냅샷과 재검증을 먼저 수행한다. 자동 생성과 수동 제작/보정 입력을 함께 덮어쓰지 않는다.

[world_config.gd](../game/scripts/world_config.gd)는 허용된 정확 `res://` 경로, 체크섬/크기, schema·축/단위/원점, 표시 범위·배열/숫자를 검사한다. `base_world.gd`는 이 자료의 삼각형과 명시 법선을 실제 ArrayMesh에 전달하며 뒤쪽 면을 제거한다. 외부 원본 경로는 provenance 문자열이며 런타임에서 해당 경로를 열지 않는다. E02 빈 manifest는 새 계약으로 대체했으므로 새 소스로 실행할 때 자료를 다시 준비한다.

635개 본체, 참조 부분/지붕, 132개 미정 지면을 구분한다. 구멍·분리 면을 보존한다. 190/180개 보행/차량 후보를 보여도 `runtime_permission=null`, `runtime_surface_ready=false`, 충돌 없음이다. 토지 색과 임시 y=0 평면은 보행 권한·현실 표고·플레이 경계가 아니다. 도로/장애물의 210개 표시 교차는 절단/승인하지 않았다. 자세한 겹침/추정은 [E03 결과](../data/reports/world_import.md)에 있다.

## 검증과 인수

```sh
.venv-data/bin/python tools/prepare_world.py --check
python3 tools/prepare_game_data.py --check
.venv-data/bin/python tools/check_world_geometry.py
.venv-data/bin/python tools/check_world_overlaps.py
python3 tools/check_game_project.py
```

검사 기본 출력은 Git 제외 캐시다. 현재 입력의 독립 원본↔삼각형 대조·손상 6건 거부, 엔진 구조/물리 키 이벤트 27개·잘못된 자료 27건 거부·전달 12개를 수행한다. 자동 키/시점 선택은 실제 사람 조작과 구분한다. 저장 실패는 성공 종료로 덮지 않으며 종료 코드 1을 검사했다.

`tests/game/check_world.gd`는 actual ArrayMesh의 모든 정점을 읽고 변환/법선·삼각형 수를 검사한다. 현재 M1 GPU에서 12개+세 시점/메뉴 캡처 4개를 통과했다. `tests/game/offline.sb`는 시험 프로세스에만 네트워크 차단을 적용하며 시스템 설정을 바꾸지 않는다. 별도 game 사본의 관측 결과·정상 종료와 환경 범위는 [E03 보고서](../data/reports/world_import.md)에 있다.

작은 공유 파일에서 G01–G04→E03 재생성 검사는 `tools/check_world_portability.py`다. 현재 M1의 기존 인터프리터를 사용한 사본 검사이며 새 가상환경/M4 실측을 대신하지 않는다. `.godot`·UID·생성 JSON·빌드·설치 앱·사용자 설정은 복사/공유하지 않는다. E04 고정 대표 거리·10m 기준물 검증은 완료했으며 P01 사람 크기/독립 정적 충돌은 아래 절과 같이 구현했으며 P02 별도 시험장에서 수평 조작/복귀를 연결했다. 대한문 통과와 전체 경로는 W 단계에서 검증한다.

## P01 캐릭터와 독립 충돌 시험장

```sh
sh tools/run_player_fixture.sh run
sh tools/run_player_fixture.sh editor
sh tools/run_player_fixture.sh observe
```

[Player](../game/scenes/player/player.tscn)는 발 위치를 루트로 하고 `CollisionShape`·`Visual/Body`를 분리한 1.70m/반경 0.30m 캡슐이다. [idle_support](../game/scripts/player/idle_support.gd)는 P01 수직 중력/정지 지지만 구현하고 수평 입력은 받지 않는다. [player_fixture](../game/scenes/tests/player_fixture.tscn)는 Actors/Fixtures/Guides/Presentation을 PAUSABLE, 안내/시점/메뉴를 ALWAYS로 두며 메뉴 중 물리를 멈춘다. 전체/사람/문 보기·다시 놓기는 시험장 기능이다. 실제 서울의 main·PlayerSlot·표시 geometry는 그대로다.

시험장의 7개 정적 충돌 구조·1.20×2.20m 개구부·0.15/0.30m 단차·미터 기준물은 합성 자료다. 생성 manifest나 원본/가공 지도·Python을 런타임에서 읽지 않는다. `observe`는 기본 정착 1초+60초 실제 관측·세 시점/메뉴 캡처를 `data/cache/player/`에 저장한다. `observe 2` 같은 짧은 관측은 화면/실행 확인용이며 60초 완료 근거와 구분한다.

`python3 tools/check_player_contract.py`는 지도/초기 캐시 없는 5개 authored 파일 사본에서 실제 엔진 오류 9종·가속 60초 물리·반복 측정을 검사한다. 정상 검사기는 `tools/check_player_fixture.py`이고 `--require-real-time`은 실제 벽시계 관측을 요구한다. [P01 결과/한계/정확한 실행](../data/reports/player_scale.md). P02 별도 시험장에서 입력/이동·낙하 복귀를 구현했다. P03 별도 시험장에 3인칭도 구현했고 P04 별도 장면에 도시 충돌을 연결했으며 시험장 결과를 서울 보행 완료로 해석하지 않는다.

## P02 이동·중력·복귀 시험장

```sh
sh tools/run_movement_test.sh run
sh tools/run_movement_test.sh editor
sh tools/run_movement_test.sh observe
```

[movement_test](../game/scenes/tests/movement_test.tscn)은 P01을 상속하고 [이동 컨트롤러](../game/scripts/player/movement_controller.gd)·InputRouter를 연결한다. 기존 P01 소스/scene·main/PlayerSlot·도시 geometry는 변경하지 않았다. 고정 시점에서 WASD/방향키·Shift 이동과 Visual 방향 회전, Esc 일시 정지·복귀 버튼을 사용할 수 있다. 기본 시험장에서 녹색 진입 램프/별도 경사를 왕복하고, 거리 시험 보기에서는 시작점과80×40m 구간을 함께 본다. 큰 격자5m, P01 작은 격자1m다.

Actors 물리는 PAUSABLE이고 InputRouter/UI는 ALWAYS다. 메뉴에서 이동 의도를 차단하고 복귀/메뉴 재개 후 키 중립을 기다린다. 복귀에는 지면 ray와 캡슐 겹침 검증이 필요하며 시험 영역/시작점은 서울 bbox/스폰이 아니다. 카메라가 따라가지 않는 고정 시점 상태와 P03 별도 시험장에서 구현한 조작/가림 범위를 구분한다. [P02 측정·재현·남은 한계](../data/reports/movement.md).

`python3 tools/check_movement_contract.py --mode contract`는9개 authored 파일 사본만으로302개 정상 검사·반복·실제 오류6종을 검사한다. `--mode gpu`는 실제30/60fps 거리와60초 정지를 별도로 측정한다. 기본 결과는 Git 제외 `data/cache/movement_contract/`, 공유 스냅샷은 `data/reports/movement/`다. 엔진 측정과 독립 Python 채점을 구분한다.

## P03 3인칭 카메라 시험장

```sh
sh tools/run_camera_test.sh run
sh tools/run_camera_test.sh editor
sh tools/run_camera_test.sh observe
```

[camera_test](../game/scenes/tests/camera_test.tscn)은 P02를 상속한다. Presentation 아래 [camera_rig](../game/scenes/player/camera_rig.tscn)와 그 자식 SpringArm/Camera를 두고 Player의 카메라 경로를 이 카메라로 연결했다. 기존 고정 Camera는 현재 시점에서 제외하며 P02 파일은 보존한다. P03만 L자 모서리 보조벽을 추가한 합성13개 정적 구조이며 도시 main/PlayerSlot·데이터는 그대로다.

카메라가 따라오고 마우스로 회전·휠로 거리를 바꾼다. Esc 메뉴에서는 마우스를 풀고 Actor/리그를 정지하며 돌아온 후 마우스 첫 움직임/키 중립을 처리한다. 창 포커스 이탈도 메뉴를 열어 수동 재개하도록 한다. 가까운 벽/문에서 거리를 줄이고 화면을 가리는 몸체를 잠시 숨긴다. 코너 최종 겹침 보완과 근접면 검사를 별도로 둔다. [실행·검증·화면·한계](../data/reports/camera.md).

`check_camera_contract.py`는 지도 없는13개 authored 파일 사본과 실제 오류5종, `check_camera_guard_regression.py`는 코너 보완을 실제로 제거한 사본1종을 검사한다. `--mode gpu`는 실제30/60fps 전체 카메라 시험·문20회 왕복을 측정하고 표준 Python 검사기가 관측을 채점한다. 기본 출력은 캐시이며 공유 스냅샷은 `data/reports/camera/`다. P04 실제 도시 충돌은 아래 절의 별도 검증이며 W 대한문/경로·M4·직접 조작감 완료로 확대 해석하지 않는다.

## P04 역할별 충돌과 도시 배치 확인

```sh
.venv-data/bin/python tools/prepare_collision.py
python3 tools/check_collision_bundle.py
sh tools/run_collision_test.sh run
sh tools/run_collision_test.sh editor
sh tools/run_collision_test.sh observe
```

P03 상속 [collision_test](../game/scenes/tests/collision_test.tscn)에 합성 건물1개를 추가해14개 정적 시험 구조를 만들었다. 기존 이동/카메라/메뉴는 보존한다. E03 상속 [collision_world](../game/scenes/world/collision_world.tscn)는 기존 actual ArrayMesh를 읽어 selected685개에만 StaticBody3D/ConcavePolygonShape3D를 붙인다. [rules](../game/resources/collision/rules.json)는 이름별 matrix, 기기별 generated.json은 source hash/ID/삼각형·검사 위치·W01 gate pending을 연결한다. 표준 Python bundle checker와 runtime loader가 잘못된 계획을 거부한다.

fixture에서는 City layer/mask0·시험장1/14·Player2/13·camera query mask1이다. 메뉴의 서울/덕수궁 보기에서는 시험장0/0·City1/14, Player/리그의 일반 물리 갱신·입력을 중단하고 고정 CityCamera를 쓴다. 시험장 복귀 버튼은 확인한 합성 지면으로 돌아오고 카메라/키 중립을 복원한다. 도시 보기에는 스폰·플레이 경계·실제 보행을 추가하지 않았다. 토지/도로 표시548개는 충돌0이며 y=0 지원평면은 현실 지형이 아니다.

`check_collision_contract.py`는 authored22+runtime4의 초기캐시 없는 사본과 실제 도형/설정 고장10종을 검사하고 GPU mode는30/60fps를 실제 측정한다. `check_collision_rejections.py`는 runtime 계획 손상10종의 실제 거부를 검증한다. `check_collision_evidence.py`는 표준 Python으로 엔진 관측을 독립 채점한다. [결과/실패/측정 범위](../data/reports/collision.md). generation/test_support는 Git 제외며 기존 E03 manifest의 표시 provenance를 P04 권한으로 바꾸지 않는다. W01의 별도 장면에서 대한문 개구부·앞뒤 지면·도시 시작점/복귀를 연결했다. 다음 W02는 경내 길·마당·전각 앞 경로를 확장한다.

## W01 대한문 실제 배치 보행

```sh
.venv-data/bin/python tools/prepare_daehanmun.py
sh tools/run_daehanmun_walk.sh run
sh tools/run_daehanmun_walk.sh observe
```

[daehanmun_walk](../game/scenes/tests/daehanmun_walk.tscn)은 기존 3인칭/이동을 상속하고 합성 Fixtures를 제거한다. World의 [daehanmun_connection](../game/scenes/world/daehanmun_connection.tscn)은 P04 원천 충돌을 생성한 뒤 gate/담장/광역 지원 평면 3개를 0/0·숨김으로 처리하고 지역 교체 5개를 붙인다. 제한 원문 연결/지역 spawn·복귀만 열며 기존 E03/P04 파일은 유지한다. `daehanmun_player.gd`는 지역 polygon과 추가 source-volume spawn guard를 적용하고, root는 복귀 yaw와 안내/메뉴를 연결한다.

자료는 수동 결정→Git 제외 daehanmun.json/decision/manifest 3개다. 실행 전 stdlib bundle checker와 runtime hash/형식/scope를 대조한다. 독립 game 사본은 authored 27/runtime 7·측정 helper 2개이며 평소 run에는 helper를 붙이지 않는다. `check_daehanmun_contract.py`는 고정 checker bytes로 정상/반복/실제 고장 6종과 GPU30/60을 검사, `check_daehanmun_rejections.py`는 실제 잘못된 자료 12종을 거부한다. [정확한 실행/결과/한계](../data/reports/daehanmun_walk.md). 다음은 W02 경내 전체 연결이다.

## W02 경내 순환과 앞마당

```sh
.venv-data/bin/python tools/prepare_palace_walk.py
sh tools/run_palace_walk.sh run
sh tools/run_palace_walk.sh editor
```

[palace_walk](../game/scenes/world/palace_walk.tscn)은 별도 장면이고 기존 W01/P04 authored 파일은 유지한다. [palace_world](../game/scenes/world/palace_world.tscn)는 기존 685+5body를 생성하되 W01지원면만0/0·숨김으로 바꾸고 W02지원면1개를 붙인다. 실제691생성/687활성, 원본 문/담장 조각4개 유지다. 원천 순환선과 별도 계산 보정선을 분리하고 보행로/원본 열린 마당의 holes·제외 체적을 보존한다. 임시 지원면과 바깥에서0.4m 안쪽 이동 중심 영역은 지역 게임 가정이다. `palace_player.gd`는 경계에서 멈춤/축방향 미끄러짐을 추가하고 기존 중력/카메라/스폰/복귀/메뉴를 재사용한다.

수동 결정과 생성3파일은 W01과 분리한다. 실행 전 stdlib checker와 runtime manifest/hash/형식/scope 검사를 수행하며 잘못된W02자료는 기존body 생성 전에 거부한다. 시험사본은 authored32/runtime10/helper3이며 실행 중 지도/Python/네트워크가 필요 없다. 독립 검사기는 source노드/지원면 적합성·실제bodycensus/float32hash/약10Hz캡슐·카메라 표본을 확인하며 엔진 매tick 극값과 구분한다. GPU30은 짧은 조작·경계/속도시험, GPU60은 전체 경내 왕복이다. [실제 결과·실패·한계](../data/reports/palace_walk.md).

## W03 도심·돌담길과 장면 경계

```sh
.venv-data/bin/python tools/prepare_public_walk.py
sh tools/run_public_walk.sh run
```

[public_walk](../game/scenes/world/public_walk.tscn)은 W02/P03를 상속한 별도 장면이다. 기존 authored/source는 바이트 보존하며 W02 지원면만 비활성화하고 W03 지원면으로 확장한다. actual692생성/687활성·3,028삼각형/구멍4개, 기존 담장/대한문 조각4개를 유지한다. 북측 원문 marked 횡단·보행 지정 분리길과 원문 보행면을 따라 시청/광장 및 남측 돌담길을 잇는다. 도서관 실내·잔디·물·분수·계단/사유지는 제외한다.

[play_boundary](../game/resources/play_boundary.tres)는 W03 장면 범위만 고정한다. 지원면0.4m 안쪽 이동/추가0.08m 경로 여유·원문 도로 접속3곳·차도 중심선 제외·정지/복귀를 연결한다. 금색 경계선은 시각 메시다. runtime manifest/Resource hash·형식/scope·수치/원문 스폰을 실제body 생성 전에 검사한다. 사본은 authored39/runtime13/helper5개, 일반 실행에는 helper가 없다. [출처·보정·실패·검증/한계](../data/reports/public_walk.md). 실제 지형/통행/사람 조작/M4는 별도다. 통합 자동 엔진 검수는 아래 W04 결과를 따른다.

## W04 연속 통합 관측과 스냅샷

기존 W03 장면/플레이어/자료는 변경하지 않는다. [수동 여정](../data/manual/walkable_milestone.json)→[표준 생성기](../tools/prepare_walkable_itinerary.py)→Git 제외 itinerary/manifest2파일로 정확한 원문 구간을 복사한다. 일반 실행은 [run_walkable_milestone](../tools/run_walkable_milestone.sh)로 기존 public_walk를 열고, 자동 시험만 새 probe/동일39authored+15runtime/6helper 사본을 쓴다.

관측 도구는 W03 helper를 상속하되 여정 중 구간별 pose를 호출하지 않는다. 전역 camera_stepped 관측은 PNG 대기 중에도 이어지고 물리 tick·프레임/시간·체크포인트·연결부를 대조한다. 여정 종료 후에만 기존 복귀/메뉴5이벤트를 호출한다. [검증·실행·범위](../data/reports/walkable_milestone.md). 직접 사용자 조작·현장 접근·M4·성능·V0 판정은 포함하지 않는다.

## L02 궁궐 외형과 보행

```sh
python3 tools/prepare_landmark_spec.py
.venv-data/bin/python tools/prepare_palace_landmarks.py
sh tools/run_palace_landmarks.sh run
```

위 W04까지의 준비를 재사용한다. [새 장면](../game/scenes/world/palace_landmarks.tscn)은 public_walk의 기존 이동/카메라/메뉴/경계를 재사용하고 [외형 loader](../game/scripts/landmark_visuals.gd)만 붙인다. 대한문·중화전·닫힌 중화문·석조전·돈덕전·정관헌을 구별하는 간결한 지붕/기둥/기단/창·열주를 만든다. 표시용401부재와 기존 물리는 분리돼 나중에 적합한 모델로 외형만 교체할 수 있다. 기존 public_walk와 이전 시험장 진입점은 보존한다.

일반 실행은 WASD/방향키·Shift·마우스/휠·Esc이며 자동 보행 도구는 붙이지 않는다. 생성 단계만 기존 GIS 가상환경/Shapely를 쓰고 실행 중 Python/원본/네트워크는 필요 없다. [전후 화면·기하/보행 검증·한계](../data/reports/palace_landmarks.md). 외형 확인용 고정 카메라 위치는 새 스폰/보행 권한이 아니다. 실제 장소 인상/사람 조작·M4 확인과 L03 도시 외형은 별도로 남긴다.
