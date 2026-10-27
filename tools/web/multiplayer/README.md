# 같은 도시에서 함께 걷기: 방 API와 게임 연결

갱신일: 2026-10-27 · EXP40 · **version6 게시·운영 도시/방 로그인 안내/공식 로그인 폼 확인 · 인증 두 계정 수용 대기**

현재 우선순위는 사용자 지시 **최적화보다 기능 개발**에 따른 함께 걷기다. 실제 탐험 게임의 Esc → **함께 걷기 · 친구 초대**에서 방 생성·참가·퇴장과 상대 표시를 연결했다. 야외 보행만 공유하며 NPC·차량·전투는 각 게임의 독립 상태다. [사용법·실제 게임 검증·한계](../../../docs/SHARED_CITY_WALK.md)를 따른다.

수정 전 client31조건, Remote headless84/native87·3PNG, loopback 개발 HTTP8조건, 두 독립 전체 headless 게임 A24/B22조건·각 exit0/ERROR0을 확인했다. native 일반 메뉴 방 생성/퇴장·Esc 복귀와 설정2파일 불변도 기록했다. native GPU owner+headless guest58조건과 원본PNG2장도 별도로 확인했고 headless03의46조건과 합산하지 않는다. 서로 다른 실제 두 계정의 운영 브라우저 검증은 아직 남았다.8명은 입장 정책이고2Hz HTTP presence는 최종 액션 네트워크가 아니다.

최종 Web 릴리스는 **exp40_shared_city02_delivery01**이다. version5의 [운영 gzip 실패와 원인](../../../data/reports/shared_city/20261027/browser_gzip_fix_diagnosis.json)을 Web-only `accept_gzip=false`로 고쳤으며 native 기본값은 유지한다. [최신 client36조건](../../../data/reports/shared_city/20261027/client_gzip01/summary.json) actual exit0/ERROR0·[실제 Web gzip](../../../data/reports/shared_city/20261027/gzip_browser_check.json)을 통과했다. 앞선03/04 전체게임의 source/settings 불변은 수정 전 각각의 실행 내부 판정이다.

[version6 게시](../../../data/reports/shared_city/20261027/site_publication.json)·[운영212개/전체 SHA/manifest·loader](../../../data/reports/shared_city/20261027/deployed_asset_check.json) PASS(17.795초), [익명 API200/401](../../../data/reports/shared_city/20261027/deployed_api_check.json)와 [실제 운영 도시→방 안내→공식 정상 로그인 폼](../../../data/reports/shared_city/20261027/deployed_browser_check.json)을 확인했다. 계정 정보 미입력으로 인증된 DB 작업/두 계정 플레이는 미검증이다. 아래 version5 receipt와 로컬 후보 검사는 이전 이력이다.

## 실제 구현과 검증 범위

`room-api.mjs`는 Web 표준 Request/Response와 `env.DB`의 D1 API를 사용한다. 방 생성, 초대 참가, 위치·방향·동작·아바타 외형 갱신, 참가자 목록, 퇴장, 소유자의 방 종료가 동작한다. `schema.sql`은 방 API의 기준 스키마다. EXP40의 공식 Vinext 후보에는 같은 의미의 Drizzle migration을 생성해 실제 로컬 D1에 적용하고 별도 SQLite14조건으로 동등성을 확인했다. 운영 D1 적용과 게시 결과는 별도 확인 대상이다.

`local-d1.mjs`는 Node의 실제 SQLite에 같은 SQL을 실행하는 **검증 전용** 어댑터다. 서버 원형에는 이 파일을 포함하지 않는다. 다음 명령은 Node 26.7.0에서 **14개 test case 모두 통과**했다. 테스트 중에만 임의의 loopback 포트를 열고 종료한다.

```sh
node --test tools/web/multiplayer/room-api.test.mjs
```

두 별도 HTTP 클라이언트가 한 방을 생성·참가하고, 두 번째 참가자의 이동을 첫 번째 참가자가 읽는 경로를 실제 요청으로 확인했다. 나머지는 초대·인증·Origin, 계정별 세션, 동일 빌드, 동시 입장 상한, 요청 간격, 순서가 뒤집힌 패킷, 논리 만료, 세션 교체, 위치 범위·속도, 동시에 들어온 상태 갱신, 비밀값의 해시 저장과 방 종료를 검증했다. 이는 방 API의 로컬 기능 검사이며 네트워크 지연·동시접속 성능·호스팅된 D1을 검증한 수치는 아니다. 실제 Godot 연결은 EXP40의 별도 client/Remote/전체 도시 검사로 구분한다.

독립 검토에서 yaw ±π의 승인값을 소수4자리 snapshot으로 반올림한 뒤 그대로 sync하면400이 되는 경계 결함을 수정했다. ±π와 인접 방향이 create→snapshot→sync를 왕복하는 실제14번째 검사를 추가했다. [최종14/14·exit0 원문](../../../data/reports/web_sites/20261025/performance01/shared_room_tests_final.log)과 [sandbox의13PASS/1listen EPERM 원문](../../../data/reports/web_sites/20261025/performance01/shared_room_tests_final_sandbox_attempt.log)을 구분한다. 이전13검사 로그는 과거 원문으로 보존한다. 이후 게임 연결 결과는 [EXP40 안내](../../../docs/SHARED_CITY_WALK.md)를 따른다.

## 배포 환경에서 확인한 제약

현재 Sites의 지원 문서는 Worker당 128 MB, HTTP 기반 외부 연결, D1/R2 binding을 설명한다. `.openai/hosting.json`의 D1 이름은 `"d1": "DB"` 형식이다. 확인한 Sites 계약에서 Durable Object binding·class migration·WebSocket room router의 배포 방법은 제공되지 않았다. Cloudflare 플랫폼 자체의 지원과 이 Site에서 실제 제공되는 binding을 구분한다.

기존 static Site에 D1만 추가하면 packager가 거절한다. EXP40에서는 공식 Vinext starter를 바탕으로 기존 project_id/URL과 게임 자산 경로를 보존하는 같은 출처 자산+API/D1 후보를 준비했다. [안전 준비 helper/overlay](../site-worker/README.md)는 기존 tracked 정적 출력의 복구 정보를 기록하며 새 worker source와 자산을 해시 대조한 뒤 이행한다. 임의 auth proxy나 service bearer를 브라우저에 넣지 않는다.

[로컬 후보](../../../data/reports/shared_city/20261026/hosting_candidate.json)는 자산714/스키마14/개발HTTP13/빌드WorkerHTTP10조건을 통과했다. [이행 fixture23조건](../../../data/reports/shared_city/20261026/hosting_prepare_fixtures.json)은 별도 준비 도구 검사다. 실제 새 게임 export는 [같은 Site version5 게시 succeeded](../../../data/reports/shared_city/20261026/site_publication.json)·[운영212개/전체 SHA/manifest·loader PASS](../../../data/reports/shared_city/20261026/deployed_asset_check.json)·[익명 API status200/로그인 필요·create401](../../../data/reports/shared_city/20261026/deployed_api_check.json)를 확인했다. 운영 로그인/D1 CRUD와 두 실제 계정 검증은 아직 대기다. 기존 후보가 보존한 EXP39 자산과 신규 EXP40 export를 구분한다.

현재 Site는 public으로 조회됐고 이번 작업이 공개 범위를 바꾸지 않았다. 익명 단일 플레이를 유지하고 방 생성/참가만 ChatGPT 로그인을 요구한다. public status의 `signInRequired`는 dispatch 소유 사용자 헤더에서 판단한다.401 안내는 고정 같은 출처 로그인으로 이동한다. 초대 코드가 계정 인증을 대신하지 않는다. 로컬 mock sign-in·개발 cookie는 운영 인증 증거가 아니다.

개발만 하려면 `node tools/web/multiplayer/dev-server.mjs --api-only --port 8766`을 사용한다. 메모리 SQLite와 port별 개발 cookie를 쓰며 loopback 밖에 노출하지 않는다. 일반 native 게임은 기본으로 이 주소에 연결한다. 상세 실행은 [함께 걷기 안내](../../../docs/SHARED_CITY_WALK.md#mac-로컬-개발-실행)를 따른다.

## 첫 방의 정책

| 항목 | 구현 값과 의미 |
|---|---|
| 첫 실제 검증 대상 | 2~4명, 같은 버전, 같은 시작 위치의 짧은 보행 |
| 참가자 상한 | 방당 8명. **입장 정책이며 검증된 수용 인원 아님** |
| 방 수 | 계정당 활성 방 2개, 방 생성 간격 5초 이상 |
| 입장 | 로그인한 Site 사용자 + 128비트 무작위 초대 코드, 계정별 입장 간격 1초 이상 |
| 상태 갱신 | 갱신과 snapshot 합쳐 참가자당 최대 2 Hz. 500 ms보다 빠르면 429 |
| 세션 | 참가자별 192비트 무작위 token, 동일 계정 재참가 시 교체 |
| 참가 표시 | 마지막 승인 요청 뒤 15초가 지나면 목록·입장 인원에서 제외 |
| 방 만료 | 생성 뒤 30분. 소유자가 먼저 종료 가능 |
| 보간 | RemoteResident가 승인 snapshot 사이600ms 보간을 구현·검사. 운영 체감 수용은 대기 |
| 요청 크기 | JSON 최대 2,048 bytes, 정의하지 않은 필드 거절 |
| 이동 | 수평 최대 24 m/s, 수직 최대 50 m/s, 최대 2초 이동 여유 + 0.25 m 오차 |
| 대략적 좌표 범위 | x/z ±1,000 m, y -100~500 m. 실제 도시 충돌 경계 검증을 대체하지 않음 |

2 Hz는 부드러운 액션 게임의 최종 전송률이 아니다. 보내는 쪽과 읽는 쪽의 500 ms 주기, 실제 RTT, 표시 보간이 합쳐져 다른 사람이 늦게 보일 수 있다. 위치 외삽으로 이를 가려도 승인되지 않은 충돌·전투 결과를 만들어서는 안 된다.

이 원형은 서버가 snapshot 요청 간격과 생존 시각도 D1에서 검증하므로, 가만히 서 있는 활성 참가자도 snapshot마다 행을 갱신한다. 상한 8명이 계속 최대 주기로 요청하면 **최대 16회 참가자 행 갱신/초, 57,600회/시간**이며 인증·방 조회·snapshot 조회·색인·입퇴장 작업은 별도다. 이 계산은 D1의 과금 대상 rows-written 수나 비용 견적이 아니다. 현재 계정의 허용량·비용·지역별 RTT는 확인하지 않았다. 5초 간격의 대기 heartbeat로 늦추면 쓰기는 줄지만 다른 사람을 보는 갱신도 느려진다. 현재 `idleHeartbeatMs`는 후속 클라이언트의 대기/백그라운드 정책 제안이며 자동 실행되는 기능이 아니다.

초기 검증이 끝나면 위치를 매번 D1에 저장하는 구조를 장기 운영안으로 확장하지 않는다. D1은 방 권한·영속 상태·낮은 빈도의 checkpoint에 적합한 후보로 남긴다. 이 API에는 Site 전체의 요청량·요금 한도를 집행하는 기능이 없다.

## API 계약

모든 경로는 `/api/multiplayer/` 아래다. 공개 `GET /status`는 가용성과 로그인 필요 여부만 반환한다. 방/참가자 작업에는 Sites dispatch가 제공하는 `oai-authenticated-user-id`가 필요하다. 이메일·실명은 읽지 않는다. POST는 서버와 같은 `Origin` 및 `Content-Type: application/json`을 요구한다. 플레이어 동작에는 본인의 세션을 `Authorization: Bearer …`로 보낸다. CORS를 열지 않고 모든 응답은 `Cache-Control: no-store`다.

| 요청 | 본문 | 반환 |
|---|---|---|
| `GET /status` | 없음 | `available`, `apiVersion`, `mode`, `signInRequired` (운영 route) |
| `POST /rooms` | `buildId`, `avatar`, `position: [x,y,z]`, `yaw` | 방·참가자 snapshot + `selfId`, `sessionToken`, `invite` |
| `POST /rooms/:roomId/join` | `invite`, `buildId`, `avatar` | snapshot + 본인의 `selfId`, `sessionToken` |
| `POST /rooms/:roomId/players/:playerId/sync` | 증가하는 `sequence`, `position`, `yaw`, `motion`, 선택적 `avatar` | 승인된 방 snapshot |
| `GET /rooms/:roomId/players/:playerId/snapshot` | 없음 | 방 snapshot, 생존 시각 갱신 |
| `POST /rooms/:roomId/players/:playerId/leave` | `{}` | `left: true` |
| `POST /rooms/:roomId/close` | `{}` | 방 소유자에게만 `closed: true` |

`avatar`는 `modelId` (`SeoulResident_M01`/`SeoulResident_F01`), `bodyProfile` (`standard`/`soft`/`athletic`), boolean `swimwear`만 받는다. 해당 이름은 현재 프로젝트 자산 계약을 읽어 정했다. 임의 파일 경로·이름·색상·아이템 구매 상태는 전송하지 않는다. `motion`은 `idle/walk/run/jump/swim`, `yaw`는 -π~π다. timestamp와 참가자 ID는 서버가 발급한다. build가 다른 참가자는 거절한다.

snapshot에는 무작위 참가자 ID, 승인 sequence·좌표·방향·동작·세 가지 외형 값·승인 시각만 들어간다. 다른 사람의 token·계정 ID·이메일·실명·초대 코드는 포함되지 않는다. token과 초대 코드는 DB에 SHA-256 해시로 저장한다. 계정 권한 확인용 해시도 내부에 저장하며 snapshot으로 보내지 않는다. 세션 token은 현재 client 메모리에 두고 장기 저장·오류 로그·analytics에 기록하지 않는다. API 단독 실행 시 브라우저가 인증 헤더를 사칭할 수 있으므로 **반드시 신뢰할 수 있는 Sites dispatch 뒤에서만 운영**해야 한다.

15초/30분은 **접근·노출의 논리적 만료**다. 삭제 스케줄은 구현하지 않았다. 만료 참가자는 다음 입장 때, 만료 방과 오래된 rate-limit 행은 다음 방 생성 때 각각 제한된 양을 정리한다. 물리적 삭제 시각을 15초/30분 이내로 보장하지 않는다. 장기 운영 전에 별도 보존·삭제 정책이 필요하다.

## 상태 소유권과 실제 Godot 연결

| 상태 | 이 원형의 소유자/한계 |
|---|---|
| 방 입장·퇴장·유효 세션·순서·시각 | 서버가 판정 |
| 위치·방향·외형·동작 | 클라이언트 제안 → 서버의 크기/속도/순서 검사 → 승인 목록. 서버 물리 시뮬레이션 아님 |
| 카메라·HUD·지역 렌더링 | 각 클라이언트 |
| NPC·차량·날씨·도시 시간 | 현재 게임은 각 클라이언트의 로컬 상태. 이 API로 동기화되지 않음 |
| 탑승 소유권·전투 명중·경찰·경제·아이템 | 미구현. 다른 클라이언트의 결과를 믿고 공유하면 안 됨 |

현재 Godot 연결은 별도 `RoomPresenceClient`와 충돌 없는 `RemoteResident`를 실제 `explore_walk` 장면에 붙인다. 로컬 입력·카메라·충돌은 원래 플레이어가 소유한다. 원격 actor는 승인 snapshot 사이만600ms 보간하고 충돌 layer/mask0·AI 미등록으로 피격/상점/탑승 판정에 참여하지 않는다. 야외 보행에서 실내/탈것으로 바뀌면 방을 나가며 현재 조작을 보존한다. 목록에서 빠진 참가자는 원격 actor를 제거한다. 활성 정지 참가자의 위치 시각이 오래됐다는 이유만으로 지우지 않는다.

실제 `HTTPRequest` 두 client와 두 독립 전체 게임을 로컬에서 확인했다. GUI/픽셀·운영 로그인·두 실제 계정은 별도 수용이다. 단일 계정은 방당 한 actor만 가지므로 같은 계정의 두 탭으로 두 사람을 검증하지 않는다. 개발 host는 서버가 발급한 가상 계정 cookie를 쓰는 loopback 검증용이며 운영 인증을 증명하지 않는다. 숨긴 탭은 브라우저가 멈출 수 있으므로 긴 단절 뒤 상태 확인/재참가가 필요할 수 있다.

## 지연을 낮추는 실제 서비스 방향

서버의 가벼운 참가자 위치 공유에는 **방 하나를 단일 Durable Object가 소유하고 WebSocket으로 상태를 전달하는 구조**가 적합한 후보이다. 브라우저는 입력/최신 제안 상태를 보내고 방 owner가 순서·속도·참가 권한을 검사해 broadcast한다. 후속 전송 주기·보간값은 실제 수용 인원·지역 RTT·지터·요금 측정 후 정한다. 현재 구현은 최대2Hz HTTP presence/600ms 보간이며 native 물리30Hz를 바꾸지 않는다. DB에는 매 tick 위치 대신 필요한 checkpoint만 저장한다. 평범한 Worker의 전역 Map에 방을 저장하면 요청들이 서로 다른 isolate로 갈 때 방이 갈라지므로 사용하지 않는다.

Cloudflare는 WebSocket upgrade와 Durable Object의 hibernation을 지원하지만, 이 Site에서 DO namespace·binding·class 배포를 지원하는지 먼저 확인해야 한다. 이 원형은 새 Cloudflare 계정·유료 서비스·외부 실시간 백엔드를 만들지 않았다. JS 서버에는 Godot의 `WebSocketPeer`와 명시적인 JSON 프로토콜을 사용한다. Godot의 RPC 내부 프로토콜을 JS 서버가 자동으로 이해한다고 가정하지 않는다. 브라우저 WebSocket에서는 임의 handshake header가 제한되므로 기존 session을 같은 출처의 승인된 join 절차와 연결해야 한다.

NPC·차량·탑승·명중·경찰까지 **한 도시의 결과**로 만들려면 단일 서버가 해당 상태와 입력 판정을 소유해야 한다. 현실적인 후속 후보는 Godot headless 전용 서버와 WebSocket transport이며, 서버가 같은 충돌·게임 규칙을 실행하고 클라이언트는 예측/보정을 담당한다. Worker 128 MB 안에서 지금의 전체 Godot 도시를 그대로 시뮬레이션하는 것은 검증된 경로가 아니다. 가벼운 DO 방은 전체 Godot 물리 서버와 같은 기능을 자동 제공하지 않는다.

## 다음 수용 기준

1. version6의 운영 도시·로그인 안내/공식 폼 확인을 유지하고, 실제 로그인 후 방 DB 작업을 수용한다.
2. 같은 빌드의 서로 다른 두 실제 계정으로 같은 방에 입장하고 상대 위치/방향/외형/동작과 퇴장·재참가를 눈으로 확인한다.
3. 실제 RTT·snapshot 나이·프레임·연결 단절·10분 지속 보행을 기록한다.
4. 4명, 이후 정책8명 순서로 검증한다. 통과 전 동시 수용 인원을 확정하지 않는다.
5. NPC·차량·전투 공유는 서버 소유권·입력/충돌 판정을 별도로 개발한 뒤 수용한다.

## 확인한 출처

- 로컬 Sites 문서: `skills/sites/SKILL.md`, `references/storage.md`, `references/identity-and-secrets.md`, `templates/worker-esm-starter/README.md`. 설치 경로: `/Users/jmjeon/.codex/plugins/cache/openai-curated-remote/sites/1.1.2/`.
- 로컬 Sites packager: 같은 설치의 `skills/sites/scripts/prepare-site-build.cjs`, `scripts/package-site.mjs`와 `templates/vinext-starter/vite.config.ts`. 정적/Worker 분리와 D1/R2 이름을 직접 읽었다.
- [Cloudflare Worker memory limits](https://developers.cloudflare.com/workers/platform/limits/): isolate 메모리는 JS/WASM을 포함해 128 MB.
- [Cloudflare Durable Object 설정](https://developers.cloudflare.com/durable-objects/get-started/): namespace binding과 class 배포 설정이 필요.
- [Cloudflare WebSocket + Durable Object](https://developers.cloudflare.com/durable-objects/best-practices/websockets/): 방을 단일 actor가 소유하는 연결과 hibernation.
- [Cloudflare D1 batch API](https://developers.cloudflare.com/d1/worker-api/d1-database/): prepared statements와 트랜잭션 batch 계약.
- [Cloudflare D1 consistency](https://developers.cloudflare.com/d1/best-practices/read-replication/): 비제약 replica 읽기는 늦을 수 있음. 이 원형은 일반 D1 binding으로 primary를 읽는다.
- [Godot Web networking](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html#networking): 브라우저의 HTTP/WebSocket client/WebRTC 범위와 숨긴 탭 정지 제약.
- [Godot WebSocketPeer](https://docs.godotengine.org/en/stable/classes/class_websocketpeer.html): JSON text frame, `poll()`, 브라우저 handshake-header 제약.
- [Godot high-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html): 사용자 정의 서버와 저수준 프로토콜 연결의 구분.
