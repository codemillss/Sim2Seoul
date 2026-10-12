# 정식 Godot 프로젝트와 데이터 경계

2026-10-13 · E02 · [실행/검증 결과](../data/reports/project_setup.md)

## 로컬에서 실행하기

Godot은 [고정 환경](environment.md)의 **4.7.2 Standard·Forward+/Metal**을 사용한다. 저장소 루트에서 실행한다.

```sh
sh tools/run_game.sh run
sh tools/run_game.sh editor
sh tools/run_game.sh observe
```

`run`은 정식 프로젝트를 연다. Esc로 메뉴를 열고 **돌아가기** 또는 Esc로 닫으며 **종료**로 끝낸다. `editor`는 정식 main 장면을 편집기로 연다. `observe`는 약 12초의 장면 처리 후 PNG/JSON/로그를 `data/cache/game/`에 남기고 종료한다. 이 진단 시간은 기동 시간이나 도시 성능 측정값이 아니다.

실행 도구는 엔진 버전을 확인한 뒤 표준 Python 3으로 작은 로컬 계약을 준비하고 Godot을 실행한다. 가상환경·전국 지도·네트워크·내보내기 템플릿은 E02 실행 준비에 필요하지 않다. 경로가 다르면 `GODOT_BIN`·`SIM2SEOUL_PYTHON`을 지정한다. 지도 가공 환경은 별도 [CROSS_MAC](CROSS_MAC.md)을 따른다.

```sh
GODOT_BIN=/Applications/Godot-4.7.2.app/Contents/MacOS/Godot sh tools/run_game.sh run
python3 tools/prepare_game_data.py
python3 tools/prepare_game_data.py --check
```

자료 준비 후 `game/project.godot`을 Godot에서 직접 열어도 된다. 준비되지 않은 새 복제본을 직접 실행하면 자료 준비가 필요하다는 안내를 표시하며 좌표 기본값으로 조용히 대체하지 않는다.

## 장면의 역할

```text
Main                              # 상태·메뉴와 실행 계약 확인
├── World                         # 메뉴 중 처리 중단
│   ├── Ground                    # 지면 표시 자리
│   ├── Buildings                 # 건물 표시 자리
│   ├── Routes                    # 보행/차량 표현 자리
│   └── Barriers                  # 담장 등 표시 자리
├── Actors                        # 메뉴 중 처리 중단
│   └── PlayerSlot                # P01 캐릭터의 빈 자리
├── Presentation                  # 초기 확인용 카메라·환경, 메뉴 중 처리 중단
├── InputRouter                   # 입력 의도·Esc 전달, 메뉴 중 계속 처리
└── Interface                     # 안내·메뉴, 메뉴 중 계속 처리
```

[main](../game/scenes/main.tscn)·[world_root](../game/scenes/world/world_root.tscn)·[player_slot](../game/scenes/actors/player_slot.tscn)는 독립 장면이다. World/Actors/Presentation은 명시 `PAUSABLE`, Main/InputRouter/Interface는 `ALWAYS`다. 메뉴를 열면 SceneTree를 멈추고 입력 의도를 0/false로 차단한다. 메뉴를 닫으면 처리·입력이 복구되고 버튼 초점을 해제한다.

현재 역할 노드는 모두 비어 있고 스케일은 1이다. PlayerSlot의 `(0,0,0)`은 빈 노드의 기본 변환이며 **실제 스폰이 아니다**. 카메라도 구조 확인용이며 최종 3인칭 카메라가 아니다. 지면·건물·경로 메시, 충돌, 캐릭터 이동은 없다.

## 입력 계약

| 입력 동작 | 물리 키 | 현재 의미 |
|---|---|---|
| `move_forward` / `move_backward` | W/↑, S/↓ | 이동 의도의 앞/뒤 성분 |
| `move_left` / `move_right` | A/←, D/→ | 이동 의도의 좌/우 성분 |
| `move_fast` | Shift | 빠른 이동 요청 여부 |
| `toggle_menu` | Esc | 메뉴 열기/닫기, 키 반복은 무시 |

[project.godot](../game/project.godot)의 InputMap이 키 매핑의 기준이다. [InputRouter](../game/scripts/input_router.gd)는 정규화된 2D 의도를 반환한다. 대각선 길이는 1을 넘지 않는다. 현재 의도는 안내 화면/시험에만 사용하며 플레이어를 움직이지 않는다. 카메라 기준 월드 방향·실제 속도·달리기는 P01/P02에서 구현하고 점프·복귀를 임의로 추가하지 않는다. 마우스는 현재 항상 보이며 잠금·회전·복구는 P02에서 검증한다.

## 원본 → 가공 → 실행 자료

| 경로 | 역할 / 공유 |
|---|---|
| `config/region.json` | 좌표 값의 단일 원천, Git 공유 |
| `data/raw/`, `data/manual/` | 원본·검토 입력. Godot이 읽지 않음 |
| `data/processed/` | G01–G04 지역 가공물, Git 제외. E03 생성기의 입력 |
| `game/resources/world_config.tres` | 사람이 관리하는 Resource. 런타임 manifest 경로만 지정, 별도 좌표 값 없음 |
| `game/data/generated/region.json` | region 원본 바이트 사본, 기기별 재생성·Git 제외 |
| `game/data/generated/manifest.json` | 계약 원천 SHA-256·G01 증거 해시·자산 목록, 기기별 재생성·Git 제외 |
| `game/assets/generated/` | 자동 생성 자산의 예정 경계, 현재 자산 없음·Git 제외 |
| `game/assets/authored/` | 수동 제작 모델의 예정 경계, 현재 모델 없음·소스 공유 |

[prepare_game_data.py](../tools/prepare_game_data.py)는 G01 공유 검사의 region 해시와 현재 원천을 대조한다. 원점/축척을 변경하고 G01을 다시 검증하지 않았다면 준비를 중단한다. 생성 시각/기기 절대경로를 넣지 않아 두 번 생성한 결과가 동일하다. `--check`는 원천 대비 현재 실행 사본이 오래되거나 없는 경우를 거부한다. 자동 생성기가 수동 자산·보정 입력을 수정하지 않는다.

[world_config.gd](../game/scripts/world_config.gd)는 허용된 `res://data/generated/`의 정확 경로에서만 계약을 읽고 SHA-256·JSON·버전·축/단위·원점 역할을 확인한다. 원본 파일 경로는 provenance 문자열이며 런타임에서 그 경로를 열지 않는다. E02 manifest의 자산 목록은 빈 배열이고 도시 로더는 아직 없다. 위경도를 엔진에서 재투영하거나 조사 bbox/기술 원점을 경계/스폰으로 사용하는 코드도 없다.

`playable_boundary=null`, `vertical_datum=not_yet_resolved`, 조사 bbox와 기술 원점의 역할을 사본에서 그대로 보존한다. 실행 사본의 수치 읽기는 좌표 전달·실제 거리/축척 검증(E04)을 대신하지 않는다. 저장·설정은 이후 `user://`에서 다루며 E02는 사용자 위치/설정을 저장하지 않는다. [Godot 경로 규칙](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html)·[Resource](https://docs.godotengine.org/en/stable/classes/class_resource.html).

## 검증 재현

```sh
python3 tools/check_game_project.py --report /tmp/sim2seoul-e02-check.json
```

실제 엔진의 headless 구조/물리 키 이벤트·메뉴·자료 검사를 수행한다. 자동 입력은 직접 키 조작과 구분한다. macOS의 앱별 네트워크 차단 GPU 시험은 [실행 기록](../data/reports/project_setup.md)에 있다. `tests/game/offline.sb`는 해당 시험 프로세스에만 적용하며 시스템/다른 앱 네트워크 설정을 바꾸지 않는다.

새 Mac에서는 공유 소스에서 자료를 준비한 뒤 빈 기동부터 확인한다. `.godot`, UID sidecar, 준비된 자동 자료·설치 앱·빌드·사용자 설정은 기기별로 유지한다. E03에서는 기존 G02–G04 가공물의 도형/높이/면과 보류 정책을 읽고 실제 지도 표시를 만든다.
