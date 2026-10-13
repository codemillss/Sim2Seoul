# 정식 Godot 프로젝트와 데이터 경계

2026-10-13 · E03/E04/P01 · [서울 표시](../data/reports/world_import.md) · [거리·축척](../data/reports/scale_view/README.md) · [사람 크기·시험장](../data/reports/player_scale.md) · [E02 준비 당시 증거](../data/reports/project_setup.md)

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

메뉴는 SceneTree를 멈추고 이동/빠른 이동 의도를 0/false로 차단한다. World/Actors/Presentation은 명시 PAUSABLE로 두며 재개 시 초점을 해제한다. [InputMap](../game/project.godot)은 물리 키 W/↑, S/↓, A/←, D/→·Shift·Esc를 등록한다. [InputRouter](../game/scripts/input_router.gd)는 대각선 길이 ≤1인 의도만 전달한다. 걷기/달리기 속도·카메라 기준 이동·마우스 잠금은 P01/P02에서 구현한다. 점프/실내/새 게임 규칙을 자동 추가하지 않는다.

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

작은 공유 파일에서 G01–G04→E03 재생성 검사는 `tools/check_world_portability.py`다. 현재 M1의 기존 인터프리터를 사용한 사본 검사이며 새 가상환경/M4 실측을 대신하지 않는다. `.godot`·UID·생성 JSON·빌드·설치 앱·사용자 설정은 복사/공유하지 않는다. E04 고정 대표 거리·10m 기준물 검증은 완료했으며 P01 사람 크기/독립 정적 충돌은 아래 절과 같이 구현했으며 다음 P02부터 수평 조작/복귀를 연결한다. 대한문 통과와 전체 경로는 W 단계에서 검증한다.

## P01 캐릭터와 독립 충돌 시험장

```sh
sh tools/run_player_fixture.sh run
sh tools/run_player_fixture.sh editor
sh tools/run_player_fixture.sh observe
```

[Player](../game/scenes/player/player.tscn)는 발 위치를 루트로 하고 `CollisionShape`·`Visual/Body`를 분리한 1.70m/반경 0.30m 캡슐이다. [idle_support](../game/scripts/player/idle_support.gd)는 P01 수직 중력/정지 지지만 구현하고 수평 입력은 받지 않는다. [player_fixture](../game/scenes/tests/player_fixture.tscn)는 Actors/Fixtures/Guides/Presentation을 PAUSABLE, 안내/시점/메뉴를 ALWAYS로 두며 메뉴 중 물리를 멈춘다. 전체/사람/문 보기·다시 놓기는 시험장 기능이다. 실제 서울의 main·PlayerSlot·표시 geometry는 그대로다.

시험장의 7개 정적 충돌 구조·1.20×2.20m 개구부·0.15/0.30m 단차·미터 기준물은 합성 자료다. 생성 manifest나 원본/가공 지도·Python을 런타임에서 읽지 않는다. `observe`는 기본 정착 1초+60초 실제 관측·세 시점/메뉴 캡처를 `data/cache/player/`에 저장한다. `observe 2` 같은 짧은 관측은 화면/실행 확인용이며 60초 완료 근거와 구분한다.

`python3 tools/check_player_contract.py`는 지도/초기 캐시 없는 5개 authored 파일 사본에서 실제 엔진 오류 9종·가속 60초 물리·반복 측정을 검사한다. 정상 검사기는 `tools/check_player_fixture.py`이고 `--require-real-time`은 실제 벽시계 관측을 요구한다. [P01 결과/한계/정확한 실행](../data/reports/player_scale.md). 다음 P02에서 입력/이동·낙하 복귀, P03에서 3인칭, P04에서 도시 충돌을 연결하며 시험장 query를 실제 보행 완료로 해석하지 않는다.
