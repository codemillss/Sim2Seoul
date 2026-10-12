# E02 정식 프로젝트·입력·데이터 경계 구성

2026-10-13 · **완료** · [구조/실행 방법](../../docs/GAME_PROJECT.md)

## 시작과 실제 결과

공유 커밋 `45c450dcde7a9ee9ef8aa3a15b76b77bbc7a105a`의 깨끗한 main에서 최신 원격을 확인했다. E01에 설치한 Godot 4.7.2 Standard·Forward+/Metal과 G01 좌표 계약을 그대로 사용했다. 엔진·원본 지도는 다시 받지 않았다.

정식 `game/project.godot`, main/world/player-slot 장면, authored `world_config.tres`, 입력 전달·메뉴·로컬 계약 읽기 스크립트를 만들었다. 지면·건물·경로·담장·플레이어 역할은 분리된 빈 Node3D다. 스케일 1을 유지하고 실제 지면/경계/스폰·캐릭터 이동은 구현하지 않았다.

좌표 설정은 단일 원천 `config/region.json`을 G01 해시와 대조해 작은 런타임 사본으로 준비한다. authored Resource에 좌표를 중복 기입하지 않았고, 준비된 JSON은 Git 제외 재생성물이다. Godot은 프로젝트 내부 계약만 읽으며 전국 PBF·가공 데이터·Python·외부 API를 실행 입력으로 사용하지 않는다.

## 실제 검증

| 검증 | 결과 / 증거 |
|---|---|
| 프로젝트 가져오기 | 장면·Resource·스크립트 파싱, 오류 없음. [로그](e02/import.log) |
| 구조·입력 자동 검사 | **27개 통과**. 빈 역할/단위 스케일, 물리 키 매핑, W·방향키·Shift·대각선 의도, Esc 열기/닫기/재열기·echo 무시·메뉴 입력/역할 처리 차단·재개. [결과](e02/project_check.json) |
| 잘못된/오래된 입력 | **17건 거부**. 누락/JSON/해시·단위·축·원점/경계·외부/상위/원격 경로·manifest/원천 형식, G01 이후 원천 변경·오래된 사본. [같은 결과](e02/project_check.json) |
| 자동 준비 | 2회 바이트/해시 동일, `--check` 통과. 현재 region 사본 949 bytes, manifest 516 bytes. 좌표 원천 SHA 유지 |
| 네트워크 차단 확인 | 시험 프로세스의 네트워크를 거부하는 프로파일에서 소켓이 `PermissionError/errno 1`로 차단됨. 시스템/다른 앱 설정 변경 없음. [차단 근거](e02/offline_check.json) |
| 실행 자료만 가진 사본 | 캐시·저장소 config/raw/processed·Python 환경 없는 준비된 game 사본을 네트워크 차단 상태에서 **실제 macOS GPU 기동**, 약 12초 계약 읽기/화면 저장·자동 종료 exit 0. [JSON](e02/offline_gpu.json)·[로그](e02/offline_gpu.log)·[화면](e02/offline_gpu.png) |
| GPU에서 입력·메뉴 자동 검사 | 같은 네트워크 차단 사본에서 엔진 내부 물리 키 이벤트를 주입해 **27개 동작+2개 PNG 저장=29개 통과**, exit 0. [결과](e02/gpu_input_check.json)·[로그](e02/gpu_input.log)·[준비 화면](e02/gpu_ready.png)·[메뉴 화면](e02/gpu_menu.png) |
| 실행 도구 | 저장소 밖 작업 폴더에서 `run_game.sh observe`로 자료 준비→GPU 기동→기록→정상 종료. [최종 인수](e02_verification.json) |

실제 GPU 로그는 `Metal 4.0 / Forward+ / Apple M1 Pro (Apple7)`이며 runtime 보고서의 display server는 macOS다. 화면은 1152×720으로 저장됐다. headless 보고서의 renderer/driver 문자열만으로 GPU 성공을 판정하지 않았다. 서로 겹치는 검사 수를 합산해 고유 검증 수로 표현하지 않는다.

## 발견과 수정

독립 Sol 검토에서 Main의 `ALWAYS` 모드를 World/Actors가 상속해 이후 도시·캐릭터 처리가 메뉴 중에도 계속될 수 있음을 찾았다. 현재는 빈 노드여서 이동 증상은 없었다. World·Actors·Presentation을 명시 `PAUSABLE`로 바꾸고 메뉴 중 `can_process=false`, 재개 후 true를 검사했다. 최초 25개 결과는 [보존](e02/project_check-before-review.json), 최종 27개는 현재 결과다. [독립 검토](e02/independent_review.json).

GPU 메뉴 캡처에서 배경 안내 문구가 메뉴 아래 비쳐 겹쳐 보이는 것을 확인해, 메뉴 중 안내를 숨기고 화면을 다시 검증했다. 진단 입력 이력은 최대 1,024개로 제한했다.

Mac 화면이 잠겨 있어 CUA의 직접 창/키 제어는 진행하지 못했고 사용자에게 잠금 해제를 요청했다. 잠금 화면 우회는 하지 않았다. **직접 키 조작은 미실행**이며 실제 GPU 캡처와 엔진 내부 이벤트 자동 검사를 대체 증거로 사용했다. 이 결과를 사람의 조작감 검수로 표현하지 않는다. 수정 전 장시간 대기 시험은 소유한 프로세스만 의도적으로 SIGTERM 종료해 교체했으며, 마지막 시험은 자동 정상 종료였다. 수정 전 GPU 기록도 [보존](e02/gpu-before-review.json)했다.

## 범위·한계와 다음

완료한 것은 네트워크 없는 정식 빈 프로젝트 기동과 입력·데이터 역할 구성이다. 서울 메시·표시 위치/축척·지형/문/충돌·보행·3인칭 조작감·도시 성능·패키지·M4 기동은 미검증이다. W0/V0 미완료.

다음 **E03**의 첫 행동은 현재 G02 features·G03 heights/terrain·G04 이동/경계 후보와 보류 규칙을 읽고 지면/길/건물의 실제 엔진 표시를 생성하는 것이다. 원문/추정/수직 예외와 도형 구멍을 보존하고 최종 통행/경계로 승격하지 않는다. 첫 서울 배치 화면을 준비하면 사용자가 익숙한 장소로 읽히는지 확인할 구체적인 지점을 알린다.
