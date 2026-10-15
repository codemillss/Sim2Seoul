# R02 기본 품질 유지와 가벼운 설정의 기능 검증

기본 품질은 기존 **3D 배율1.0·Sun 그림자 켬·시야200m·보행자2명/차량2대**를 유지한다. M1 Pro 16GB의 R01 B 측정은 실제1920×1080에서20분 동안 프레임 p95 **9.6133ms**였고 제안 기준33.3ms 안이었다. 현재 측정에서 기본 표시를 낮춰야 할 근거가 없어 원래 설정을 채택했다. [R01 수치](performance_m1pro.json)·[고정 조건과 한계](../../docs/performance_notes.md).

| 설정 | 실제 3D 배율 | Sun 그림자 | 시야 | 보행자 / 차량 | 판단 |
|---|---:|---|---:|---:|---|
| 기본 `standard` | 1.0 | 켬 | 200m | 2 / 2 | 기존 표시 유지, 기본 선택 |
| 가볍게 `low` | 0.75 | 끔 | 200m | 2 / 2 | 선택 가능한 기능 대안 |

가볍게는 내부3D 해상도와 그림자만 바꾸며 지도·축척·물리·지원면·개체수는 바꾸지 않는다. **가벼운 설정의 성능 개선율은 측정하지 않았다. 새 HUD를 포함한 성능 재측정도 하지 않았다.** R01은 안내 UI를 숨기고 별도 카메라로 화면 부하를 측정했으므로 새 V0 UI나 release 앱의1080p 성능 수치로 옮겨 쓰지 않는다. 이번 R02는 최적화 전후 FPS 비교가 아니라 기본 설정의 유지 결정과 두 선택지의 기능 회귀다.

## 실제 검사 결과

Godot4.7.2, M1 Pro의 offline runtime-only 사본에서 headless **64/64**, 실제 Forward+/Metal **68/68** 검사를 통과했다. 처음 기동/API 확인용 smoke는 **60/60 진단 통과**이며 정식 회귀 판정과 구분한다. [요약](r02/summary.json)·[headless 판정](r02/contract_check.json)·[GPU 판정](r02/gpu_check.json)·[smoke 판정](r02/development/smoke02/smoke_check.json).

| GPU 관측 구간 | 물리 tick | 물리초 | 실제초 |
|---|---:|---:|---:|
| 기본 | 5,427 | 90.450000 | 90.423194 |
| 가볍게 | 5,426 | 90.433333 | 90.425150 |

두 구간은 같은 보행자2명·차량2대 인스턴스를 유지했다. 각 설정에서 원문 대한문 경로 `0→1→2→3→2→1→0`의6구간을 실제 입력으로 왕복하고, 문·벽 가까이에서 요청 거리2m/6m 카메라 회전을 관측했다. 구간 중 캐릭터 위치 주입·복귀·개체 재생성·시험 장애물은0이다. 두 NPC와 차량의 실제 이동 및 물리 tick 진행, 정적 인벤토리/차량 지원면 동일, 중간 실제 품질 설정을 확인했다.

기존 침투·지면5mm, 카메라 추적2mm, near/overlap0과 개체별 step 기준을 유지했다. 전tick 접지·높이·속도·이동량/접촉 요약과 약10Hz의 독립 원문 기하·카메라 검산을 함께 사용했다. 최대 플레이어 정적 침투는 약2.178mm, 카메라 침투는0이었다. 기존 core·생성 자료·N04 스냅샷·R01 측정 도구와 신규6개 소스의 전후 SHA가 일치했다. [원시 headless](r02/contract.json.gz)·[원시 GPU](r02/gpu.json.gz)·[소스 동결](r02/development/source_freeze_after_smoke01.json).

보행 관측 뒤 별도로 Esc 정지/재개, 보행자·차량 스위치, 실제 품질 선택 신호와 저장, 출처 팝업의 Esc/닫기 후 메뉴 정지 유지, 재개 후 실제 actor 물리 tick 증가를 검사했다. 수동 복귀 버튼 시험도 이 뒤에 분리했다. 임시 설정 경로에서 가볍게 저장→새 인스턴스 재시작 유지→깨진 JSON/알 수 없는 ID의 기본 복구를 확인했고, 잘못된 사용자 설정에서 엔진 ERROR는 없었다. 이 저장 재시작 단계에서만 장면과 개체를 다시 만들었다.

960×600의 메뉴·출처 팝업/닫기와1152×720의 팝업·HUD 필수 control 실제 사각형이 화면 안에 있었다. 주 에이전트가 아래3PNG를 직접 열어 한글·메뉴·출처 읽기와 화면 경계를 확인했다. [직접 검토 기록](r02/views.json)·[메뉴960](r02/gpu_view_menu_960.png)·[출처1152](r02/gpu_view_popup_1152.png)·[HUD1152](r02/gpu_view_hud_1152.png). 저장된 `gpu_check.json`의 시각 검토 미완료 필드는 원바이트 보존하고, 후속 직접 검토는 별도 `views.json`에 기록했다.

## 실패와 해결

첫 smoke는 기능53항목이 통과했어도, `camera_stepped` 신호 처리 중 검사기가 `scene.free()`로 장면을 즉시 해제해 **엔진 ERROR3회**가 발생했으므로 실패로 보존했다. 검사기만 `queue_free()`와 두 process frame 대기로 바꿔 재시험했다. production leaf/프리셋이나 원래 물리 기준은 고치거나 완화하지 않았다. 실행기의 증거 보호는 mode별 충돌을 거부하도록 정리해 같은 새 폴더의 contract/GPU 기록이 공존하게 했으며 같은 mode의 덮어쓰기는 계속 거부한다. [최초 실패/원시/로그/당시 소스](r02/development/smoke01/smoke_failure.json)·[실패 원시의 별도 기능 감사](r02/development/smoke01/retained_failure_audit.json).

## 재현과 남은 범위

준비된 입력과 기존 Python 환경을 사용하며 아래 출력 경로는 아직 사용하지 않은 새 폴더로 바꾼다. 실행기는 Godot 버전·N04 원본/생성 자료 바이트를 대조하고 가상환경·원본 GIS·`.godot` 캐시를 복사하지 않는다. 설정은 임시 경로로 재지정해 실제 사용자 설정을 건드리지 않는다.

```sh
.venv-data/bin/python tools/check_quality_contract.py --mode smoke --output data/cache/r02_recheck_smoke01
.venv-data/bin/python tools/check_quality_contract.py --mode contract --output data/cache/r02_recheck_full01
.venv-data/bin/python tools/check_quality_contract.py --mode gpu --output data/cache/r02_recheck_full01
```

일반 V0 진입은 `sh tools/run_v0.sh run`이며 기존 프로젝트 기본 main은 바꾸지 않았다. 전체334구간·3.33km의 검수는 원본 [N04 증거](urban_motion.md)를 유지하며 이번 짧은 시험으로 다시 완주했다고 부르지 않는다. 이번 결과는 새 UI를 포함한1080p 성능/개선율·20분 내구·release 패키지·M4·직접 사람/OS 조작감·현장 지형/출입·실내 검증이 아니다. R03의 실제 앱과 R04의 다른 Mac 결과는 별도로 판정한다.
