# 같은 도시에서 함께 걷기

갱신일: 2026-10-27 · EXP40 · 현재 상태: **version6 게시·운영 도시/로그인 폼 진입 확인 · 인증 두 계정 수용 대기**

사용자는 여러 사람이 같은 도시에 들어와 만나고 함께 플레이하는 방향을 확정했고, 이후 **최적화보다 기능 개발을 먼저** 요청했다. 첫 연결은 야외에서 서로의 캐릭터를 보고 걷는 기능이다. 기존 도시와 이동·실내·생활 기능 위에 선택적으로 참가하는 방을 붙였다.

## 현재 사용할 수 있는 범위

Esc 메뉴의 **함께 걷기 · 친구 초대**에서 새 방을 만들거나 전달받은 초대 코드로 참가한다. 같은 방은 생성자의 시작 위치 근처에서 만나도록 현재 도시의 안전한 야외 지점을 확인한다. 시작 위치가 막히면 참가를 취소하고 다른 야외 장소에서 만들도록 안내한다.

상대의 위치·방향·걷기/달리기/점프 상태와 자체 남성형/여성형×기본/통통/근육 체형·사복/수영복을 표시한다. 임의 파일 경로·색상·구매 아이템은 전송하지 않는다. 다른 참가자는 승인 snapshot 사이만600ms 지연 보간하고, 다음 승인값을 예측해 앞으로 움직이지 않는다. 첫 위치는 즉시 표시하며 승인 순서/시각이 뒤집히면 거절한다.

현재는 **야외 보행만 공유**한다. 실내·상점·자전거·킥보드·자동차·버스·헬리콥터·지하철·구금 등 다른 활동으로 전환하면 방을 나가고 기존 활동을 계속한다. 늦게 도착한 참가 응답도 현재 활동 제어를 회수하지 않는다. **NPC·차량·날씨·도시 시간·전투·경찰·경제는 각 게임에서 독립적으로 실행**된다. 상대에게 충돌하거나 피해를 주고 같은 차량에 타는 기능은 아직 연결하지 않았다.

## 웹에서의 접근

주소는 기존 [Sim2Seoul](https://sim2seoul-play-20261025-e7d4.rocky-lily-7307.chatgpt.site)을 유지한다. 이번 조회에서 Site는 public으로 확인됐으며 이번 작업에서 공개 범위를 바꾸지 않았다. 익명 단일 플레이는 유지하고 방 생성/참가에만 ChatGPT 로그인을 사용한다. 로그인 안내는 같은 출처의 고정 `/signin-with-chatgpt?return_to=%2Fplay.html`로 이동한다. 초대 코드는 계정 로그인을 대체하지 않는다.

**현재 릴리스는 `exp40_shared_city02_delivery01` / Site version6이다.** [게시 receipt](../data/reports/shared_city/20261027/site_publication.json)는2026-10-27T01:47:37Z `succeeded`/Site 소스 `005a64485430aa82ed60b10192864a2c5c78d016`, [운영 자료](../data/reports/shared_city/20261027/deployed_asset_check.json)는212/212·전체 WASM/PCK SHA·manifest/loader PASS(17.795초)다. [운영 익명 API](../data/reports/shared_city/20261027/deployed_api_check.json)는 status200/로그인 필요·방 생성401이다.

[실제 운영 HTTPS 브라우저](../data/reports/shared_city/20261027/deployed_browser_check.json)에서3D 도시 ready→Esc 방 패널→로그인 안내→버튼으로 공식 `auth.openai.com/log-in` 정상 계정 입력 폼까지 확인했다. [원본 화면](../data/reports/shared_city/20261027/deployed_browser_login.png)·로그에서 engine ERROR0/게임 ready를 보존한다. 준비21.757초는 cache를 사용한 단일 실행 관찰이며 일반 로딩/프레임 보장이 아니다. **계정 정보를 입력하지 않았고 인증된 방 DB 작업·서로 다른 두 계정 플레이는 미검증**이다. 한 계정은 방에 한 actor만 가지므로 같은 계정의 두 탭은 두 사람 검증이 아니다.

version5는 게시/자료 검사를 통과했지만 실제 압축된 방 API 응답을 읽을 때 Fetch와 Godot의 중복 해제로 `StreamPeerGZIP` 오류가 났다. [원인/수정](../data/reports/shared_city/20261027/browser_gzip_fix_diagnosis.json)에 따라 Web-only `accept_gzip=false`로 고쳤고 native 기본값은 유지한다. [최신 client36조건](../data/reports/shared_city/20261027/client_gzip01/summary.json) actual exit0/ERROR0과 [실제 로컬 Web gzip](../data/reports/shared_city/20261027/gzip_browser_check.json)을 통과한 뒤 version6을 재게시했다. 이전 성공 receipt/실패 원문은 모두 보존한다.

함께 걷기 조작 순서는 다음과 같다. 운영의 서로 다른 두 계정 검증은 아직 남아 있다.

1. 두 사람 모두 새 게임을 열고 각자의 ChatGPT 계정으로 로그인한다.
2. 야외에서 Esc → **함께 걷기 · 친구 초대** → **새 방 만들기**를 누른다.
3. **초대 코드 복사**로 코드를 복사해 친구에게 직접 전달한다.
4. 친구는 같은 메뉴에 코드를 붙여넣고 **초대 코드로 참가**한다.
5. **게임 메뉴로 돌아가기 · Esc** 후 기존 메뉴에서 다시 Esc로 거리에 복귀한다.
6. 마칠 때 같은 패널의 **방 나가기**를 누른다. 실내/탈것으로 전환해도 방에서 나간다.

입장/연결 실패는 방 상태 안내로 표시하고 기존 단일 플레이를 계속할 수 있다. 현재 client는6초 요청 제한, 550ms를 기준으로 한 갱신을 사용한다. 서버 상한은 참가자당2Hz이며 방당8명은 **입장 정책**이다. 검증된 동시 수용 인원·최종 액션 게임 통신·저지연 보장을 뜻하지 않는다. 숨긴 탭은 브라우저가 정지시킬 수 있으며 긴 단절 뒤 재참가가 필요할 수 있다.

## Mac 로컬 개발 실행

기존 지역 자료와 Godot4.7.2 환경은 [일반 실행 안내](RUN_GUIDE.md)를 따른다. 개발 방 서버는 이 Mac의 loopback에만 열며 실제 운영 인증을 제공하지 않는다. Node26.7.0에서 아래 실행/검사를 확인했다.

터미널 하나에서 저장소 루트 기준으로 실행한다.

```sh
node tools/web/multiplayer/dev-server.mjs --api-only --port 8766
```

다른 터미널에서 일반 탐험 게임을 실행한다. 기본 native 방 주소는 `http://127.0.0.1:8766`이다.

```sh
sh tools/run_exploration.sh
```

검증한 Web 출력 폴더를 함께 서비스하려면 API-only 대신 다음 형태를 사용한다. 폴더가 실제로 완성된 export인지 먼저 확인한다.

```sh
node tools/web/multiplayer/dev-server.mjs --dist /absolute/verified-web-export/dist --port 8766
```

개발용 서버는 메모리 SQLite와 서버 발급 개발 cookie를 쓴다. 재시작하면 방과 참가 정보가 사라진다. 임의 사용자 헤더를 운영 인증처럼 받지 않는다. 이 서버를 외부에 공개하거나 운영 Site의 인증을 대신하게 사용하지 않는다.

## 구현과 소유권

| 구성 | 역할 |
|---|---|
| [RoomPresenceClient](../game/scripts/multiplayer/room_presence_client.gd) | 실제 HTTPRequest·서비스/로그인 상태·메모리 세션·방 입퇴장·승인 snapshot 검증 |
| [SharedCityWalk](../game/scripts/multiplayer/shared_city_walk.gd) | 기존 Esc 메뉴·방 패널·야외 상태/안전 참가 위치·원격 생성/정리 |
| [RemoteResident](../game/scripts/multiplayer/remote_resident.gd) | 승인 외형·600ms 보간·표현 전용 이동. 충돌 layer/mask0, AI/전투 불참 |
| [방 API](../tools/web/multiplayer/room-api.mjs) | 같은 빌드/계정·순서/속도·참가 목록·만료·방 권한 검사. 서버 물리 시뮬레이션 아님 |
| [개발 host](../tools/web/multiplayer/dev-server.mjs) | loopback 개발 cookie·실제 SQLite·선택한 정적 게임 파일. 운영 인증 아님 |
| [같은 Site 이행 소스](../tools/web/site-worker/README.md) | 공식 Vinext starter 위에 기존 자산+같은 출처 API/D1을 준비. 게시와 DB 적용은 별도 |

원래 로컬 플레이어가 입력·카메라·충돌을 계속 소유한다. 원격 actor는 도시 AI 목록이나 실제 피격/탑승/상점 판정에 등록하지 않는다. 상대 목록 만료는 서버의 마지막 요청 시각으로 판단한다. 활성 정지 참가자의 위치 승인 시각은15초 이상 오래될 수 있으므로 그 값만으로 표시를 지우지 않는다. 비밀 token·cookie·초대 코드 원문은 메모리에만 두고 보고서/오류 로그/설정 파일에 저장하지 않는다.

## 실제 검증과 남은 수용

| 검사 | 실제 결과와 범위 |
|---|---|
| 수정 전 production HTTP client | [attempt03](../data/reports/shared_city/20261026/client_attempt03_report.json)31조건·[실제 exit0/ERROR0](../data/reports/shared_city/20261026/client_attempt03_run.json). 한 headless 엔진의 두 HTTPRequest client·실제 입퇴장/이동/재참가 및 명시적 오류 fixture |
| 원격 캐릭터 | [선택 final02](../data/reports/shared_city/20261026/remote_summary.json): headless84/native87조건·각 exit0/ERROR0. 실제52본 남녀 모델·외형 교체·보간/거절/충돌0·정면/옆/뒤3PNG. 인체 미술/연속 동작 수용 아님 |
| 수정 전 실제 도시 두 프로세스 | [pair03](../data/reports/shared_city/20261026/world_pair_attempt03/summary.json): A24/B22조건·각 exit0/ERROR0·51.079초. 실제 지면/AI/플레이어 물리/입력과 상대 이동·퇴장/재참가. [교차 대조](../data/reports/shared_city/20261026/world_pair_attempt03_crosscheck.json)는 상대 위치 오차0.00046m 이내·52본 표시·설정/소스 불변. 둘 다 headless |
| 수정 전 native 전체게임 표시 | [native04](../data/reports/shared_city/20261026/world_pair_attempt04_native_crosscheck.json): GPU owner+headless guest58조건·각 exit0/ERROR0·설정/소스 불변. [참가](../data/reports/shared_city/20261026/world_pair_attempt04_native/a_report_joined.png)·[이동](../data/reports/shared_city/20261026/world_pair_attempt04_native/a_report_moved.png) 원본 확인. 임시 fixture 카메라/검증 표식이며 제품 UI와 구분. headless03의46조건과 합산하지 않음 |
| native 일반 메뉴 | [manual03](../data/reports/shared_city/20261026/manual_preview03.json)·[패널](../data/reports/shared_city/20261026/room_menu_ready.png)·[복귀](../data/reports/shared_city/20261026/room_menu_back.png): 실제 버튼 방 생성/퇴장·Esc 복귀와 설정2파일 불변 |
| 개발 HTTP | [8조건](../data/reports/shared_city/20261026/dev_server_check.json): loopback 실제 두 cookie client·SQLite·Origin/Host/경로·session/파일 제한. 운영 인증 아님 |
| 같은 Site 후보 | [이행 fixture23](../data/reports/shared_city/20261026/hosting_prepare_fixtures.json), [후보](../data/reports/shared_city/20261026/hosting_candidate.json) 자산714/스키마14/개발HTTP13/빌드HTTP10조건. 실제 운영 D1/identity/게시 아님 |
| 새 Web 게임 | [build4단계](../data/reports/web_sites/20261027/exp40_shared_city02/build.json) 각 exit0/ERROR0, [실제 PCK](../data/reports/web_sites/20261027/exp40_shared_city02/pack_integrity.json) raw205/scene15/texture49/폰트. [재분할](../data/reports/shared_city/20261027/web_delivery.json): PCK180,883,704B·WASM39,514,754B·전체 SHA 유지·212조각/전송94,792,406B |

추가 [실제 Site checkout 로컬 preview](../data/reports/shared_city/20261026/site_preview_8776_check.json)는12조건+238자산과 로컬 D1, [실제 CUA Web 조작](../data/reports/shared_city/20261026/web_room_browser_check.json)은 로컬 도시 부팅·방 생성1명 표시·퇴장 PASS다. 개발 cookie/로컬 D1 검사를 운영 SSO로 세지 않는다.

위 검사들은 서로 다른 경계를 다루며 합산한 전체 품질 점수가 아니다. 운영 도시와 공식 로그인 폼 진입은 확인했다. 계정 정보 미입력으로 실제 로그인/방 DB 작업과 서로 다른 두 계정의 상대 이동은 후속 판정이다. 앞선 전체게임03/04는 Web-only 수정 전 client이며 source/settings 불변은 각각 실행 내부 판정이다. 최신 client36조건과 합산해 최신 전체게임 회귀라고 하지 않는다. 운영 RTT·snapshot 나이·10분 이동/단절·4명/8명 수용량·공유 NPC/차량/전투는 아직 완료하지 않았다. EXP39의 남은 FPS 저하는 이 기능 작업으로 해결됐다고 주장하지 않는다.

운영 자원 검사의 초기 Python 기본 UA 요청403은 attempt01 원문으로 보존했다. 명시 UA 재검사로212개 자료가 통과했으며 이것을 브라우저 문제 원인이나 모든 접속의 영구 안정성으로 단정하지 않는다.

[version5 게시 성공](../data/reports/shared_city/20261026/site_publication.json)·[212개 자원 PASS](../data/reports/shared_city/20261026/deployed_asset_check.json)와 [운영 gzip 실패 원문](../data/reports/shared_city/20261026/deployed_browser_attempt02.txt)을 함께 보존한다. version5를 최종 수용본으로 표시하지 않는다.

실패도 보존한다. [manual01](../data/reports/shared_city/20261026/manual_preview_attempt01.log)의 초기 JSON 오류와 [manual02](../data/reports/shared_city/20261026/manual_preview02.json)의 조기 HTTP TIMEOUT 뒤 process frame 대기를 적용했다. [pair01](../data/reports/shared_city/20261026/world_pair_attempt01/summary.json)/[pair02](../data/reports/shared_city/20261026/world_pair_attempt02/summary.json)는 cleanup ERROR가 남아 거절했다. fixture FileAccess 참조 해제와 새 idle100ms 뒤 종료한 pair03에서는 ERROR0이지만 원래 orphan 클래스는 확정하지 않았다. [Remote의 초기 실패/미선택 성공 이력](../data/reports/shared_city/20261026/remote_summary.json)도 유지한다.

선택 fixture를 다시 실행할 때는 기존 증거를 덮어쓰지 않는 새 report 폴더를 사용한다.

```sh
node --test tools/web/multiplayer/room-api.test.mjs tools/web/multiplayer/dev-server.test.mjs
node tools/web/multiplayer/check-game-pair.mjs --report-dir /absolute/fresh-pair-report
```

전체 게임 두 프로세스 검사는 실제 엔진·도시 데이터를 사용한다. 출력의 실제 exit/ERROR와 설정/소스 불변을 확인한다. 실행 명령의 성공만으로 일반 GUI·운영 로그인·체감 성능을 합격 처리하지 않는다. 게시 이행은 [전용 준비 절차](../tools/web/site-worker/README.md)를 따른다.
