# 같은 방의 자동차·주민·반려견

갱신일: 2026-10-27 · EXP41 · **version7 게시·native11 89/89 / 운영 두 계정·장시간 성능 미검증**

사용자의 “같은 방에서 같은 차량과 NPC를 보고 상호작용” 요청에 따라 기존 함께 걷기에 자동차와 주민을 연결한다. 현재 공개 Site는 **version7 / `exp41_shared_actors03_delivery01`**이다. [게시 receipt](../data/reports/shared_actors/20261027/site_publication03b.json)는 같은 URL/public 범위의 `succeeded`를 확인한다. 운영 브라우저 부팅·방 로그인 안내와 실제 로그인한 두 계정의 공동 플레이는 구분한다. EXP40 version6 이력은 아래 연결 문서에 보존한다. 작업 브랜치는 `codex/shared-city-vehicles-npcs-20261027`, 시작 main은 `328ef22491a0551c9d79e87b4ca95b48de371ce3`다.

## 이번 공유 범위

| 대상 | 범위와 조작 | 소유권 |
|---|---|---|
| 원래 도로 자동차14대 | 가까이에서 E로 운전권 요청·승차, 운전 후 E로 안전 하차. 다른 참가자가 운전하면 배타적으로 거절 | 서버가 claim/lease를 승인하고 운전자만 주행을 제안. 하차 뒤 parked 상태 |
| 성인 보행자28명 |3m 안에서 E로 인사. 승인 후 같은 고정 한국어 문구 표시 | host가 기존 route AI 실행, 게스트는 승인 pose 표시 |
| 반려견2마리 |3m 안에서 E로 쓰다듬기. 승인 후 공유 고정 문구/표현 | host의 원래 산책 AI와 보호자 연결 유지 |
| 참가자 아바타 | 기존 함께 걷기의 위치·방향·동작·외형 공유 | 본인이 조작, 상대는 충돌 없는 승인 표시 |

F/X 공유 전투·명중·경찰 출동은 이번 구현에 포함하지 않는다. 방 안에서는 고정 안내로 제한을 알리고 원래 solo 경찰 사건을 만들지 않는다. 자유 입력 대화·경제·아이템·시설 사용 결과도 공유하지 않는다. 추가 경찰·순찰차·소방관/소방차·버스3대는 공유 catalog 밖이며 방 동안 독립 동작/상호작용을 중지·숨겼다가 solo로 복원한다. 최신 소스의 실제 두 전체 도시·조작·복원 결과는 아래 native11, local Web03과 운영 검사를 구분해 따른다.

실내·시설·다른 탈것은 원래 단독 소유권을 따른다. 전환 전에 방/탑승 정리를 끝내며 원래 카메라·플레이어 조작·설정을 복구한다. 방 종료 때 복원할 NPC나 차량의 위치에 플레이어가 있으면 먼저 위치를 비켜야 한다. 복구 실패를 이유로 플레이어의 걷기를 막거나 충돌체를 겹쳐 놓지 않는다.

## 안정 ID와 같은 빌드

build ID는 `sim2seoul-shared-world-v2`다. 기존 v1 presence API는 world를 생략한 경우의 회귀 검사로 유지한다. 방 참가 시 ID/kind 집합이 완전히 같아야 하며 다른 구성을 별도 개체로 추가하지 않는다.

- 자동차: `car:<원래 route ID>`14개. 기존6대와 분산 도로 차8대다.
- 원래 보행자2명: `npc:n02:palace_court`, `npc:n02:plaza_front`.
- 거리 성인6명: `npc:street:<route>:walker`. route는 `stonewall_east`, `stonewall_dog`, `stonewall_west`, `plaza_dog`, `plaza_west`, `museum_slope`다.
- 반려견2마리: `npc:street:stonewall_dog:dog`, `npc:street:plaza_dog:dog`.
- 분산 성인20명: `npc:coverage:coverage_walk_00_0`부터 `coverage_walk_09_1`까지의10쌍이다.

## 승인과 표시의 경계

고정 host 한 명이 기존 AI를 실행한다. 서버는 인증된 방 참가자·host/driver 권한, 순서·시각·거리·속도와 운전권을 검사한다. 서버에서 Godot3D 충돌·지형·AI를 실행하는 구조는 아니다. 소유자가 방을 나가거나 만료되면 방이 끝나며 host 이양은 하지 않는다. 공유 중 AI 자동차는 원래 단방향 route 끝에서 정차하고 E로 claim할 수 있다. 불연속 endpoint→start 재배치를 막은 것이며 계속 물리적으로 순환하는 도로 AI를 새로 구현한 것은 아니다. guest 퇴장/만료 때에는 운전권을 회수하고 차량을 멈춘다.

게스트의 원래 NPC 이동/회전·render anchor writer를 막고 승인 pose 구간만600ms 보간한다. 최신 승인 위치 밖으로 외삽하지 않는다. NPC guest body의 충돌 layer/mask는0이며 원래 body·route·visual identity를 재사용한다. host avoidance에는 승인된 상대 표시의 위치를 이웃으로 제공할 수 있지만 상대에게 충돌체나 독립 AI를 추가하지 않는다.

서버가 승인한 인사/쓰다듬기 반응은 entity 최상위의 `reactionKind`, `reactionUntilMs`, `reactorId`로 전달한다. 클라이언트는 고정 문구만 표시하며 원래 solo 타격·신고·구금 함수를 호출하지 않는다.

## DB 이행과 재시도

`multiplayer_worlds`는 방당 한 world JSON과 host/revision/갱신 시각을 저장한다. `multiplayer_world_actions`는 `(room_id, player_id, request_id)`를 기본키로 두고 요청 해시와 결과를 보관한다. 공개 snapshot의 최근 결과32개에서 밀려난 UUID도 같은 요청을 다시 실행하지 않는다. receipt에는 player FK를 두지 않아 퇴장 뒤에도 방이 만료/삭제될 때까지 결과를 보존한다. 예전 player는 퇴장/재참가 뒤 인증할 수 없다.

운전권 변경과 world revision 갱신은 실제 DB 원자성 경계로 검사한다. 새 hosted 스키마는 [overlay Drizzle 소스](../tools/web/site-worker/overlay/db/schema.ts)와 [0001 migration](../tools/web/site-worker/overlay/drizzle/0001_shared_world.sql)에 있다. 배포된0000 SQL/snapshot은 수정하지 않았다. 기존 데이터가 있는 DB에서0001을 적용해 방·참가자·rate-limit 보존과 room→world→receipt 삭제 연쇄를 검사했다. 공식 starter의 실제 로컬 Worker/D1에는 이행해 아래20조건을 통과했다. [version7 정상 게시](../data/reports/shared_actors/20261027/site_publication03b.json)에서 운영 DB schema overview가 기존3개→world/world_actions를 포함한5개 table로 바뀌어0001 적용을 확인했다. 운영 행·사용자·세션 값은 읽지 않았다.

## 현재 확인한 증거

| 검사 | 선택 결과 | 범위와 한계 |
|---|---|---|
| backend/API 최종 통합 | [cleanup57/57](../data/reports/shared_city/20261027/stale_owner_world_cleanup01/summary.json)·[원문](../data/reports/shared_city/20261027/stale_owner_world_cleanup01/all.log) | 실제 HTTP/SQLite·기존45조건+만료 own-world12조건. 새12는 수정 전2PASS/10FAIL→수정 후12PASS. Protocol fixture와 실제 물리는 구분 |
| migration | [7/7 원문](../data/reports/shared_city/20261027/world_migration01/raw.log) | 위57에 포함. 기존0000·occupied DB 보존·FK cascade·로컬 SQL parity. 별도 합산하지 않음 |
| 차량 최신 lease 경계 | [86/86](../data/reports/shared_city/20261027/vehicles/lease_boundary01.json)·[actual exit0/ERROR0/source 불변](../data/reports/shared_city/20261027/vehicles/lease_boundary01_run.json) | 평면/지원 함수·아바타 stub에서 native 상속 조작·lease 표시 경계·복원. 실제 도시 수용과 분리 |
| NPC final04 | [41/41](../data/reports/shared_city/20261027/npcs_component04/result.json)·[actual exit0/ERROR0/source 불변](../data/reports/shared_city/20261027/npcs_component04/run.json) | native guard·600ms 보간·ID/종류·인사/쓰다듬기 요청·복원 전 겹침 거절·dog collider 회전 복원 |
| client 최신 재시도 | [39/39](../data/reports/shared_actors/20261027/client_regression03_retry/summary.json) | 실제 HTTPRequest·gzip와 sync422 제한 재시도. actual exit0/ERROR0/source 불변·10.150초 |
| actual live NPC | [15/15](../data/reports/shared_city/20261027/live_npcs_attempt01/summary.json)·[개체별 원문](../data/reports/shared_city/20261027/live_npcs_attempt01/client_report.json) | 실제 전체 headless 도시 host120초·176승인 snapshot·3600physics samples·30명 모두 이동. actual exit0/ERROR0/source/settings 불변 |
| 최종 두 전체 게임 native11 | [89/89(A54/B35)](../data/reports/shared_city/20261027/shared_actors_attempt11_native/summary.json)·[독립 route/실패 진단](../data/reports/shared_city/20261027/shared_actors_fixture_route_diagnosis.json) |83.460초·각 actual exit0/ERROR0·19-source/settings 불변·원래 actor/충돌/카메라 exact복원·cleanup오류0. 원본 GPU PNG3장 |
| native08 실패 | [FAIL86/89](../data/reports/shared_city/20261027/shared_actors_attempt08_native/summary.json) | owner menu/focus3조건 실패·`self_list` engine ERROR2건. guest35/35여도 전체 성공 아님 |
| 이전 native09/10 | [09 FAIL39/41](../data/reports/shared_city/20261027/shared_actors_attempt09_native/summary.json)·[10 진단](../data/reports/shared_city/20261027/shared_actors_fixture_route_diagnosis.json) |09 NPC waypoint/peer,10 owner 직선 접근 정지/peer 연쇄. ERROR0.10 원인 미확정,11 우회 분기 사용0이라 해결 원인으로 단정하지 않음 |
| 최종 실제 로컬 Worker/D1 | [05 cleanup20/20](../data/reports/shared_actors/20261027/site_worker_world05_cleanup.json) | 같은 실제 로컬 D1의03/04 active_room_limit 실패 뒤 새 cleanup API로 create/hostCAS/greet/claim/drive/exit/pet/close 통과. 공식 mock signin이며 운영 계정은 아님 |
| 최신03 built 자산 | [238자산·212gzip·whole WASM/PCK PASS](../data/reports/shared_actors/20261027/site_built_assets_check03.json) | 최신03 built Worker 로컬 바이트 검사. 최초candidate01 보고서도 보존 |
| actual Web candidate02 반복 | [3회 승차/주행/하차](../data/reports/shared_actors/20261027/web_gui_attempt02_summary.json)·[proxy 원문](../data/reports/shared_actors/20261027/web_gui_attempt02_proxy.json) | 기록 시698 API·오류0, 실제 Web/WASM owner1명. NPC 이동 on/차량 AI switch off. 이후 proxy 누적700 요청도 실패0 |
| 최신 Web03 export | [4단계 exit0/ERROR0](../data/reports/web_sites/20261027/exp41_shared_actors03/build.json)·[delivery03 whole SHA 보존](../data/reports/shared_actors/20261027/web_delivery03.json) |`exp41_shared_actors03_delivery01`, PCK180,951,132B. [manual Web03 PASS](../data/reports/shared_actors/20261027/web_gui_attempt03_summary.json): 실제 E승차/W1600ms주행/E정차·하차 뒤 공유1명 badge 유지·DOM ERROR0. NPC on/초기 차량AI switch off. 운영 게시 여부는 별도 receipt 참조 |
| version7 게시/운영 DB | [publication03b](../data/reports/shared_actors/20261027/site_publication03b.json) | Site commit `c753b4f76541b9ed2f0a4c87b435b0d6e649e418`·deploy `succeeded`·public 유지·table3→5. 운영 행은 조회하지 않음 |
| 최종 export 결합 | [124개 GD drift0/API 일치](../data/reports/shared_actors/20261027/final_source_binding03b.json) | PCK03 GD 입력/current game 소스 동일, Site API `51b71717…`. export 당시 dirty feature tree의 base가 manifest `buildCommit=328ef22`이며 최종 main commit에서 만들었다고 주장하지 않음 |

### 422와 실패 기록

candidate02 첫 직접 Web 수동 승차→W1600ms(약43km/h)→하차에서 sync422 뒤 방을 나간 사례는 **정확 오류 JSON이 없어 원인 미확정**이다. 이후 safe proxy 반복3회 성공은 이 실패를 지우거나 lease 보간 수정이 원인을 해결했다는 뜻이 아니다. 같은 폴더의 최초 기록과 후속 반복을 함께 보존한다.

client는 sync422 때 기존 서버80/24m/s 경계를 유지한 채1초 뒤 새 sample로 최대2번 재시도하고 세 번째 거절에서 방을 나간다. 안정성을 높이는 제한된 복구이며 최초 원인 해결을 증명하지 않는다. 최종 소스는 API `51b71717…`, 차량 `ab6c2eb9…`, client `b2ca3cdb…`이고 각 구성 요소 보고서의 실행 내부 소스 해시를 따른다.

120초 live NPC 검사에서는 최대 raw 속도1.20000005m/s·physics 한 번 최대 이동0.04243m·최대 TIF 차이0.04455m·outlier0·API4220을 관찰했다. **직접 운전과 NPC/차량 접촉은 없었으므로(contact ticks0) 충돌로 밀리는 경우나 owner drive/exit 오류를 배제하지 않는다.** backend45의 owner-drive 경로는 실제 NPC 물리를 실행하지 않는 별도 검사다.

native11은 처음에는 AI/menu pause 지속을 확인한 뒤 production setter로 NPC/차량을 멈추고 guest가 운전한다. 따라서 live owner AI+owner drive/exit의 동시 경로 수용으로 세지 않는다. 최종 native11 PNG3장은 실제 M5/Metal4/Forward+ viewport이지만 **임시 fixture 카메라와 명시적 test label**을 썼다. 첫 joined 화면의 초기 겹침과 greeting/after_drive에서 보이는 실제2인·NPC/차량을 구분하며 제품 카메라는 복원했다. 일반 화면의 조작감·장시간 성능 수용은 별도다.

attempt01의 client parameter shadow parse 실패와 앞선 relative script 경로 parse 실패, native02–06의 parse/fixture token 오탐/focus-menu 조건·일회422를 삭제하지 않는다. 특히05의 일회 world-distance422 원인은 확정하지 않는다. source에서 확인한 AI endpoint portal은 shared-only no-recycle guard로 예방했으며 그 사실만으로05/첫 Web422의 원인을 단정하지 않는다. native08도 FAIL·원문 그대로 유지한다. native09는 ERROR0이지만 물리 NPC 접근 waypoint와 peer 연쇄 실패가 있어 FAIL39/41로 보존한다.10에서는 NPC 접근1.739m는 통과했으나 owner의 직선 car 접근이13.96m 이동 뒤 멈췄고 guest44.65m 접근은 통과했다. 새 독립 world의 capsule query로10의 당시 blocker를 확정할 수 없었다.11은 실제 Input으로45.074/44.485m 접근을 통과했지만 detour 분기0회이므로 우회 코드가10을 고쳤다고 주장하지 않는다. 좁은 인공 waypoint와 실제 E 범위를 구분하며 [진단 원문](../data/reports/shared_city/20261027/shared_actors_fixture_route_diagnosis.json)을 보존한다. NPC initial fixture의 누락 meta/anchor 오류·CA 오류, final03의38조건은 각각 실패·이전 소스 결과로 보존한다.

### 만료 host 방의 생성 한도

실제 Worker03/04는 status·인증 경계2조건 뒤 create429 `active_room_limit`으로 실패했다. 같은 mock identity의 world2개에서 host15초 TTL은 지났지만 create가30분 room 만료만 세어 대체 방을 막았다. 같은 create DB transaction에서 **같은 소유자의 공유 world 중 host row가 없거나 TTL 만료된 것만 LIMIT32 정리**하도록 고쳤다. live host·legacy room·다른 소유자·입장 상한·create cooldown은 유지했다. committed heartbeat가 먼저 들어오면 보존하고 뒤 SQL 실패 시 정리도 rollback하는 경계를 포함한다.

새12조건 수정 전2PASS/10FAIL→수정 후12PASS, 전체57/57과 실제 동일 로컬 Worker05 20/20을 확인했다. 최종 API `51b71717…`를03b로 빌드/패키지/게시했고 PCK03은 바꾸지 않았다. saved version7 및 `succeeded` deployment와 production schema3→5를 [receipt](../data/reports/shared_actors/20261027/site_publication03b.json)로 구분해 확인했다.

## 운영 브라우저와 원시 자산 검사

[게시된 실제 public IAB/Web/WASM](../data/reports/shared_actors/20261027/production_browser_v7.json)에서 도시 READY·64.202초·212/212 조각·cache68/network144·53,484,236B·DOM engine오류0을 관찰했다. [실제 도시 화면](../data/reports/shared_actors/20261027/production_ready_v7.png)과 [방 로그인 안내](../data/reports/shared_actors/20261027/production_room_signin_v7.png)를 보존했다. 방 메뉴는 ChatGPT 로그인을 요구한다. 이 부팅은 manifest/whole PCK·WASM 검증을 통과했지만 한 번의 혼합 cache/network 관찰이며 일반 로딩 성능 보장이 아니다. **실제 로그인한 한 계정의 방 CRUD·서로 다른 두 운영 계정 공동 플레이는 검증하지 않았다.**

별도 원시 HTTP 자산 probe는 **INCOMPLETE**다. `play.html`에 Cloudflare JSD script938B가 삽입되어 최초 strict hash 비교에 실패했고, 확인한 해당 script만 제거한 재시도 뒤403이 발생했다(실패한 정확 자산은 미확보). 기존 공식 서비스 header 재검사는307을 NoRedirect 정책으로 차단했다. 새 visitor identity/token을 만들거나 cross-origin으로 자격 증명을 전송하지 않았고 추가 probe를 하지 않는다. 로컬 built03의238/238·212gzip/whole PASS와 실제 운영 브라우저212/212/whole/runtime 성공을 **운영 raw238/238 PASS로 표현하지 않는다**. [최종 판정](../data/reports/shared_actors/20261027/production_browser_v7.json)을 따른다.

## 재실행과 남은 수용

[실행기](../tools/web/multiplayer/check-shared-actors.mjs)는200초 watchdog, 독립 API/coordinator port0,64개 stage ring과 최대4096B 공개 context allowlist를 사용한다. invite·cookie·bearer는 메모리에만 두며 root8766 서버를 건드리지 않는다. 실제 child 종료·ERROR·source/settings·finally cleanup을 함께 확인한다. 다음 회귀에는 이미 선택한11 폴더를 덮어쓰지 않고 새 경로를 사용한다.

```sh
node tools/web/multiplayer/check-shared-actors.mjs \
  --report-dir data/reports/shared_city/20261027/shared_actors_new_regression \
  --owner-graphics
```

현재 남은 수용은 실제 로그인한 서로 다른 두 운영 계정의 같은44개 개체·배타 승차·공유 인사/쓰다듬기·퇴장/host loss, 장시간 단절/재접속·4/8명·성능과 일반 조작감이다. 버스/경찰·소방/기타 시설은 solo 소유권과 복원을 유지한다. 최초 Web/05의422와10의 일시 정지는 원인 미확정 기록을 보존한다.

2Hz HTTP·600ms 보간·8명 입장 정책은 최종 액션 네트워크나 검증된 동시 수용량이 아니다. 서버3D 물리·공유 충돌·전투/경찰/구금/경제·일반 시설 결과·장시간 단절·운영 두 계정·FPS는 별도 범위다. EXP40 게시·압축 수정·로그인 폼 진입 이력은 [함께 걷기](SHARED_CITY_WALK.md)에 보존한다.
