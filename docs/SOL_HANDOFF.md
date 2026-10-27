# Sol 작업 인수 안내

## 2026-10-27 EXP40 — 현재 인수: version6·운영 로그인 폼 진입까지

현재 선택은 **exp40_shared_city02_delivery01 / version6**다. [게시](../data/reports/shared_city/20261027/site_publication.json) `succeeded`/Site 소스 `005a64485430aa82ed60b10192864a2c5c78d016`·[운영212개/전체 SHA](../data/reports/shared_city/20261027/deployed_asset_check.json) PASS/17.795초·[익명 API200/401](../data/reports/shared_city/20261027/deployed_api_check.json)을 먼저 읽는다. PCK180,883,704B·전송94,792,406B/212조각이며 같은 URL/public 범위를 유지했다.

[운영 실제 브라우저](../data/reports/shared_city/20261027/deployed_browser_check.json)는 도시 ready→Esc 함께 걷기→로그인 안내→공식 `auth.openai.com/log-in` 정상 폼까지 PASS·engine ERROR0이다. **계정 정보를 입력하지 않았다. 로그인한 방 DB 작업/서로 다른 두 계정 플레이·수용 인원은 미검증**이다.21.757초 준비는 단일 cache 실행 관찰이며 성능 보장이 아니다.

version5는 실제 압축 API에서 `StreamPeerGZIP` 오류가 났다. [원인과 수정](../data/reports/shared_city/20261027/browser_gzip_fix_diagnosis.json)은 Web Fetch가 이미 해제한 본문에 대한 중복 decoder를 Web-only `accept_gzip=false`로 막고 native 기본값을 유지한다. [최신36검사](../data/reports/shared_city/20261027/client_gzip01/summary.json)와 [실제 Web gzip 검사](../data/reports/shared_city/20261027/gzip_browser_check.json)를 통과했다. 이전03/04 전체게임 source/settings 불변은 각 실행 내부 판정이며 이 수정 전 client다. 합산/최신 runtime 동일 판정을 하지 않는다.

사용자 지시 **최적화보다 기능 개발 먼저**를 유지한다. 다음은 실제 로그인/두 계정의 방 생성·상대 이동 수용이다. NPC/차량/전투 공유·2Hz 최종 액션화·4/8명·FPS 해결은 아직 범위 밖이다. version5 receipt/자원 PASS와 gzip 실패 원문을 모두 유지한다. 아래26일 인수는 이전 시도다. [함께 걷기](SHARED_CITY_WALK.md)를 따른다.

## 2026-10-26 EXP40 — 현재 인수: 함께 걷기 version5 게시

[현재 상태](WORK_STATUS.md) → [함께 걷기 실행/증거](SHARED_CITY_WALK.md) → [두 전체 게임](../data/reports/shared_city/20261026/world_pair_attempt03/summary.json)·[교차 대조](../data/reports/shared_city/20261026/world_pair_attempt03_crosscheck.json)를 먼저 읽는다. 사용자 최신 우선순위는 **최적화보다 기능 개발**이다. NPC 계산 개선을 다음 첫 작업으로 되돌리지 않는다. 현재 브랜치 `codex/shared-city-gameplay-20261026`는 main `ce010e5`에서 시작했다.

실제 게임은 RoomPresenceClient → SharedCityWalk 메뉴/생명주기 → 충돌 없는 RemoteResident로 연결한다. 초대 생성/참가·가까운 안전 위치 배치·승인 외형/600ms 보간·퇴장/재참가를 구현했다. 실내/탈것 전환과 늦은 참가 응답은 현재 활동의 제어권을 보존하며 방을 나간다. 메뉴 포커스 상실로 패널이 닫히는 경우를 막았다. 로컬 움직임/카메라/충돌은 원래 플레이어가 소유하며 원격 actor는 AI/충돌/피격/상점/탑승 판정에 참여하지 않는다.

선택 로컬 검사는 client31, Remote84/87+3PNG, 개발서버8, 두 전체 headless 게임 A24/B22·exit0/ERROR0·51.079초다. native 일반 메뉴의 방 생성/퇴장/Esc 복귀와 설정2파일 불변도 기록했다. [native04 GPU owner+headless guest](../data/reports/shared_city/20261026/world_pair_attempt04_native_crosscheck.json)는 별도58조건·각 exit0/ERROR0·원본PNG2장 확인이며 headless03의46조건과 합산하지 않는다. fixture 카메라/표식과 실제 제품 UI를 구분한다. 초기 JSON 파싱/조기 HTTP timeout·전체게임 두 번의 cleanup ERROR는 실패 원문을 유지한다. 최종 pair03의 정리 ERROR는0이며 원래 orphan 클래스는 확정하지 않았다.

현재 Site는 public으로 조회됐고 이번 작업에서 audience를 바꾸지 않았다. 기존 project_id/URL을 보존하는 정적→Vinext/D1 소스 준비와 로컬 자산/스키마/HTTP 검증이 완료됐다. 새 Web 후보는 **exp40_shared_city01_delivery01**, PCK180,883,576B/전송94,792,341B/212조각이다. [게시 receipt](../data/reports/shared_city/20261026/site_publication.json)는 version5·2026-10-26T12:18:18Z `succeeded`/Site 소스 `0efcc19eea238e6972212ceb3ab8893d79d023a9`다. [운영 검사](../data/reports/shared_city/20261026/deployed_asset_check.json)는212/212·전체 SHA·manifest/loader PASS/34.231초, [익명 API](../data/reports/shared_city/20261026/deployed_api_check.json)는 status200/로그인 필요·create401이다. 초기 UA403 실패와 재검사 성공을 유지하며 브라우저 원인을 단정하지 않는다. [실제 checkout preview12조건/238자산](../data/reports/shared_city/20261026/site_preview_8776_check.json)과 [로컬 Web 방 생성/퇴장](../data/reports/shared_city/20261026/web_room_browser_check.json)은 운영 인증과 구분한다. **운영 브라우저 시작·로그인한 두 계정 게임 수용은 대기**다. anonymous solo와 방 로그인 경계를 유지하고 개발용 cookie/mock identity를 운영에 넣지 않는다. 캐시·PCK/WASM·Site 체크아웃·자격 증명은 main Git에 넣지 않는다.

## 2026-10-25 EXP39 — 현재 인수: delivery01 게시·운영212개 PASS

[현재 상태](WORK_STATUS.md) → [EXP39 원본/실패/측정](../data/reports/web_sites/20261025/performance01/README.md) → [최종 게시](../data/reports/web_sites/20261025/performance01/delivery01_deployment.json)·[운영 검사](../data/reports/web_sites/20261025/performance01/deployed_asset_check.json)를 읽는다. 최종 릴리스는 performance01_build04_delivery01, Site 소스 `c67bf053417cf836106e99e900858c0cef0eaff1`이며 소유자 전용을 유지했다. 실제212개 조각·manifest/loader·전체 WASM/PCK SHA가 모두 첫 시도31.938초에 PASS다.

게임 runtime은 build04와 같고 PCK180,846,148B·전송94,781,218B·212조각이다. 기존211개 전송의 PCK0만두512KiB로 나눴으며 전체 게임/다른 압축 바이트는 유지한다. native raw SHA 경로와 Web의 명시적 attestation/실제 scene15·texture49 검사를 구분한다. [최종 로컬 시작](../data/reports/web_sites/20261025/performance01/delivery01_runtime_dom.txt)은210cache/2network1,043,828B·16.505초다. 실제 드래그·W/Shift+W·메뉴·신/구 갤러리·도시 복귀를 확인했고 IAB의 마우스 잠금 거절은 드래그 대안으로 대응했다.

짧은6표본 중앙값30.25FPS와 후속18표본26.15/최저8.2FPS를 구분한다. 저하가 남고 완전 통제 비교·전구역60FPS·모든 기기 보장이 아니다. 물리30Hz를 유지한다. build01 낮은 FPS·build02 fatal overlay·build03 import 실패·두 운영 PCK0 시간 초과를 삭제하지 않는다. 인증 후 운영 지속 플레이·청취·저장 재접속·장시간 성능은 별도 수용이다.

사용자가 공동 도시 방향을 확정했지만 현재 게임은 단일 플레이다. [서버 원형](../tools/web/multiplayer/README.md)은 로컬 HTTP/SQLite14검사·yaw 경계 왕복만 완료한 게임 미연결·미호스팅이다.8명 정책/2Hz polling을 수용 인원·최종 동기화로 안내하지 않는다. 다음은 NPC 물리 계산과 지원 서버 배포 경로, 두 허용 계정의 상대 표시/이동·퇴장/재접속·지연 검증이다. 작업 브랜치 `codex/shared-city-performance-20261025`는 main `a1f6134`에서 시작했다. 아래 EXP38은 이전 이력이다.

## 2026-10-25 EXP38 recovery01 — 현재 인수: 운영94% 로딩 복구

작업 브랜치는 `codex/web-loading-recovery-20261025`, 시작 main은 `65f6f7f`다. [사건 기록](../data/reports/web_sites/20261025/recovery01/incident.json)과 [복구 결합 검사](../data/reports/web_sites/20261025/recovery01/artifact_and_browser_check.json)를 먼저 읽는다. 실제 운영 `pck-005.gz`500/40.115초 읽기 시간 초과의 근본 원인은 미확정이다. 이전42조각 성공 기록으로 현재 운영 문제를 덮지 않는다.

기존 게임 WASM/PCK 바이트는 유지하고1MiB332조각/새 내용 해시 파일명으로 바꿨다. `tools/rechunk_web_site.py`는 이미 검증한 export를 재분할하며 native 재생성은 필요 없다. loader의30초 무진행·최대3시도 복구와 검증 조각 유지, 실제 JS13검사·로컬500주입→실제 도시 준비를 구분한다. [재게시 성공](../data/reports/web_sites/20261025/recovery01/deployment.json) 및 [운영332개 HTTP200·크기·개별/전체 SHA 일치](../data/reports/web_sites/20261025/recovery01/deployed_asset_check.json)를 기록했으며 중복 Site 생성이나 공유 범위 변경을 하지 않는다. 단일 플레이와 최대 동시접속 미검증을 유지한다. 아래 인수는 최초 배포 이력이다.

## 2026-10-25 EXP38 — 현재 인수: Web/Sites 실제 게임 배포

게시 완료: [실제 URL](https://sim2seoul-play-20261025-e7d4.rocky-lily-7307.chatgpt.site) · [native Sites 성공 응답](../data/reports/web_sites/20261025/deployment.json). 현재 소유자 전용이다. 배포 브라우저는 ChatGPT 로그인 게이트까지 확인했으며 인증 후 게임 시작·지속 조작이 다음 수용이다.

[현재 상태](WORK_STATUS.md) → [선택 attempt04 빌드](../data/reports/web_sites/20261025/attempt04/build.json) → [Site 식별/실제 게시 상태](../data/reports/web_sites/20261025/site_identity.json)를 먼저 읽는다. 프로젝트는 `appgprj_6adda788b5208191a1d18a536bbcff80`이며 소유자 전용으로 한 번 생성했다. 새 Site를 중복 생성하거나 예상 URL만으로 게시 완료를 판단하지 않는다. 배포/원격 전송의 최종 결과는 위 게시 응답과 보고서에 기록했다.

작업 브랜치는 `codex/web-sites-20261025`, 시작 native 커밋은 `6825154`다. `tools/build_web_site.py`와 `tools/web/`가 Web 제작 소스다. `data/cache/sites/sim2seoul-web-20261025`는 별도 관리되는 Site 체크아웃이며 `.openai/hosting.json`의 동일 project_id를 유지한다. `data/cache/web-export/`·공식 export template·PCK/WASM/chunks·자격 증명은 main Git에 넣지 않는다. 원본 `game/project.godot`와 실행 중이던 Mac 게임은 유지했다.

실제 로컬 브라우저에서 대한문 도시/한국어/메뉴/갤러리/Q 호출을 확인했고42조각 및 전체 해시·PCK 원본213파일 검사가 통과했다. 지속 이동 입력은 자동화 도중 메뉴가 열리는 문제로 확정하지 못했다. 이름에 walk/movement가 들어간 저장 화면을 보행 성공 증거로 해석하지 않는다. 청취 음향·저장 재접속·모바일·장시간 성능도 미검증이다. Web 시작은 사용자 클릭 이후 마우스 잠금, 캔버스는 상단 도구막대54px 아래 policy0 크기를 유지한다. 기존 native/EXP37 수치를 현재 변경의 전체 회귀 합격으로 합산하지 않는다.

## 2026-10-25 EXP37 — 현재 인수: 얼굴·관절과 확대 비교

**현재 기술 검증:** final01 headless **85/85**, native **141/141**, 원본 **44 PNG(전체32·확대12)**이며 두 실행 모두 actual exit0·ERROR0·capture 오류0·source 변경0이다. [headless 원문](../data/reports/resident_face_joints/20261025/face_joints_headless_final01.json)·[native 원문](../data/reports/resident_face_joints/20261025/face_joints_native_final01.json)·[44장 직접 열람 peer 검토](../data/reports/resident_face_joints/20261025/visual_review_peer.json)를 구분한다. [root의 일반 OS 기록](../data/reports/resident_face_joints/20261025/normal_launch.json)은 실제 JPEG11장·ERROR0 로그2개·설정4파일 동일을 보존했다. 메뉴/확대/신구/자세·거리 복귀/재진입을 확인했으며, peer는 이 저장 기록을 읽기 검토했다. 복귀 도구는16.698초에 시간초과였지만 다음 실제 화면에서 거리 복귀를 확인했다. 로딩 성능 수용은 포함하지 않는다. 실사 미술·연속 동작 수용은 false다.

[WORK_STATUS](WORK_STATUS.md)·[제작 설명](CHARACTER_IDENTITIES.md)·[이번 증거 폴더](../data/reports/resident_face_joints/20261025/)를 먼저 읽는다. 현재 기술 검증과 원본 검토를 완료했으며 이전 EXP36 실행을 현재 변경 소스의 합격 결과로 재사용하지 않는다. 비교 자산 `resident_form_m01_previous.glb`와 `FORM_STUDY_PREVIOUS_MANIFEST.json`은 동결 EXP36 v03이다. 기존 EXP35 v04 비교는 아래 과거 인수 기록이다.

갤러리 첫 줄에서 **새 원형/이전 원형(EXP36)**, 둘째 줄에서 방향과 **전체·얼굴·어깨·골반**, 셋째 줄에서 네 자세를 선택한다. 모델 교체 시 포즈·방향·확대를 유지한다. 확대는 관심 부위만 포함하며 나머지 몸의 잘림은 의도된 것이다. **전체**로 전신 복귀, **거리로 돌아가기/Esc**로 도시 복귀한다. 실제 일반 OS 입력과 복귀는 최종 normal_launch 기록으로 따로 확인해야 한다.

일반 실행은 준비된 GLB를 import하고 Blender 재생성을 요구하지 않는다. 새 인체는 독립 회색 검토 원형이며 생산 플레이어/NPC·도시·캡슐을 교체하지 않는다. 실사/매력·연속 보행 수용도 별도 후속이다. 저장 증거 검사는 `tools/check_resident_face_joints_handoff.py`를 사용하며, 현재 원본과 root 일반 OS 기록의 정확 SHA를 peer에 결합했다. 기록 시 PID48203은 새 얼굴45도로 열려 있다.

## 2026-10-25 EXP36 — 현재 인수: 원형 큰 면 다듬기

[WORK_STATUS](WORK_STATUS.md)와 [EXP36 집계](../data/reports/resident_form_refinement/20261025/summary.json)를 먼저 읽는다. 새 원형과 이전 EXP35 v04를 같은 화면에서 각각 네 자세로 비교한다. canonical `resident_form_m01_previous.glb`와 `FORM_STUDY_PREVIOUS_MANIFEST.json`은 v04 바이트 원본이다. 다른 Mac에서는 준비된 GLB만 import하면 되며 일반 실행에 Blender가 필요 없다. 제작 원본은 `art/characters/resident_form_m01.blend`, 생성 소스는 `tools/sculpted_character/`다. 기존 EXP35 수치는 현재 변경 소스에 대한 회귀 실행으로 해석하지 않는다. 기존 플레이어 적용·여성/체형 확장·연속 보행은 원형 수용 후 작업이다.


## 2026-10-25 EXP35 — 현재 인수: 단일 인체 원형

[WORK_STATUS](WORK_STATUS.md)·[제작 설명](CHARACTER_IDENTITIES.md)·[EXP35 집계](../data/reports/resident_form_study/20261025/summary.json)를 먼저 읽는다. 새 `.blend`는 `art/characters/`에 있고 게임에는 준비된 GLB만 포함한다. 다른 Mac의 일반 실행에 Blender 재설치는 필요 없다. 선택 재생성은 체크섬을 확인한 공식 Blender4.5.15LTS와 `tools/sculpted_character/build_resident_study.py`를 사용한다.

게임 Esc → 인체 원형 비교 · 무채색으로 들어간다. 새 원형 네 자세/네 방향, 이전 모델은 원본 rest 네 방향만 지원한다. 원형 비교의 이전 모델 특수 pose adapter는 왜곡 때문에 제거했고, 이전 native dev02 수치PASS14PNG는 현재 시각 수용으로 세지 않는다. 현재 selected 실행과 실제 OS 입력/복귀는 집계의 정확 소스·로그/PNG 해시를 따른다. 기존 플레이어/NPC를 새 원형으로 갈아끼우지 않는다. 다음 행동은 한 명의 큰 면 조형이며 미술 수용 이전에 파생 인물/기능을 늘리지 않는다. 아래 EXP34 이하는 이전 인수 이력이다.


## 2026-10-24 EXP34 — 현재 인수

[WORK_STATUS](WORK_STATUS.md)·[첫 남녀 모델](CHARACTER_IDENTITIES.md)·[현재 집계](../data/reports/character_identity/20261024/summary.json)를 먼저 읽는다. 제작 모듈/원본 페인트와 프롬프트는 함께 보존한다. 일반 실행은 준비된12GLB를 import하며 재생성이 필요 없다. 선택 재생성은 NumPy/Pillow 환경과 저장된 두 자체 PNG를 사용한다.

현재 선택은 **11실행·4185개 assertion·220PNG**다. native release06의 12GLB/변형·접촉3730, 남녀 상체 headless각62, 재질/꾸미기/통합 headless15/56/33, 얼굴 native74/64PNG·전신 native각38/144PNG·꾸미기 native68/12PNG, lifecycle headless03의9조건을 합한다. 같은3730 headless 보조 실행은 다시 더하지 않는다. [선택 목록](../data/reports/character_identity/20261024/selected_runs.json)과 [엄격 감사](../data/reports/character_identity/20261024/final/audit_current_release06.json)는 실제 엔진/실행기 종료0·스크립트/엔진 ERROR0·현재 소스 일치를 확인한다.

이전 headless materialnull16건과 native renderer04의32건은 실패 이력이다. Dummy 전용 추론과 Body 복원 지연만으로 해결됐다는 설명을 사용하지 않는다. 부모 Surface가 복제 override 재질8개 모두의 참조를 보유하도록 고쳤다. 같은9조건 lifecycle01→02에서 material12→0을 확인했으나 sandbox CA 오류1건씩으로8/9였고, 보안 설정 변경 없는 신뢰된 설치 엔진 환경의 root03은9/9·ERROR0이다. 현재 release06은 수정 소스로 다시 수행한 무오류 결과다.

Esc → 캐릭터 꾸미기의 앞/뒤/옆/얼굴과 팝업 없는7개 선택기를 유지한다. 얼굴은1.95m/18° 렌즈로1인칭 숨김을 피하고 취소/닫기 때 FoV·카메라/HUD를 복원한다. 현재 일반 창은 설치본과 바이트가 같은 캐시 엔진의 실제 NFD 경로에 연결해 마우스로 남녀 얼굴·여성 옆/뒤·취소를 확인했다. [새 OS 화면6장과 실행 기록](../data/reports/character_identity/20261024/normal_launch.json), 설정4파일 불변을 보존했고 남성 얼굴 확대 패널이 열려 있다. 연속 OS 주행/편안함 수용은 포함하지 않는다.

현재 production12는v06표준4SHA와 같고 원래52rest/몸·손발·옷과12개LOD=false를 보존한다. capture fixture의 Skeleton NOTIFICATION_UPDATE_SKELETON 발행은 검사 프레임 정합용이며 생산 보행을 바꾸지 않는다. 4위상 GIF/전신8샘플의 일부 중복을 연속영상으로 표현하지 않는다. 얼굴·모발·표정과 자연스러운 동작의 미술 한계는 [현재 peer 검토](../data/reports/character_identity/20261024/final/visual_review_peer.json)에 남겼으며 실사 완성으로 인수하지 않는다. 아래 EXP33 이하는 이전 인수 이력이다.

## 현재 인수: 2026-10-24 EXP33 자체 인물·출동·선택 수영/외형

[WORK_STATUS](WORK_STATUS.md)·[EXP33 안내](AUTHORED_CHARACTER_COMBAT.md)·[집계](../data/reports/authored_character_combat/20261024/summary.json)를 먼저 읽는다. 자체 generator/12GLB는 `tools/authored_character/`와 `game/assets/original/seoul_resident/`에 있다. 외부 모델은 역사 재현용이며 현재 표시 모델로 사용하지 않는다. 일반 실행은 준비된 GLB/PNG를 import하므로 generator 재생성이 필요 없다. 선택 재생성에는 NumPy/Pillow가 필요하다.

실제 손 접촉과 피격 임시 소유/원래 controller 복귀, 초기14경찰/가까운2명 출동·연결 경로/막힘 대응·60초 시계를 유지한다. 원래 개체/도시/1.70m 캡슐은 바꾸지 않는다. 모델/수영복은 같은52본 자체 몸을 사용한다. 자동 LOD는 끄며 `game/assets/original/seoul_resident/*.import` 설정도 Git과 현재 해시에 포함한다. `.godot` 캐시는 공유하지 않는다. 작은 겨드랑이 틈과 얼굴/옷의 프로토타입 한계는 후속 과제다.

수영은 미준비도 허용하며 샤워/수영복은 각각 실제 속도 보너스다. 외형 설정은 별도 저장, 적용/취소와 상점/수영복 복귀를 구분한다. 새 검사는 `authored_resident`, `authored_combat`, `police_dispatch`, `driver_reaction`, `customization`, `human_materials`, `swim_arm_skin`, 갱신된 `pool`이다. 정확한 인수/분모/결과는 집계의 `.run.json`을 따른다. 저장 무결성 기본 집계는 EXP33이고 새 엔진 실행·픽셀 검토·일반 OS 입력·주관적 조작감은 서로 다른 판정이다.

현재 선택은 UI 수정 뒤4실행179개(54/64/33/28)다. 앞선36실행5560개는 실제 OS popup 종료를 놓친 UI 수정 전 이력이며, 정확한 옛 두 UI 소스와 SHA를 별도 보존했다. 두 UI 파일 이외의 결합 소스/자산은 동일하다. 현재7개 선택기는 같은 패널 좌우 버튼과 방향키를 사용하고 PopupMenu를 만들지 않는다. 편집 전용 fill은 닫을 때 숨긴다. 일반 OS 마우스/방향키 선택·뒤 보기·취소·복귀는 별도 normal_launch 기록을 따른다. 실제 사용자 설정 Save와 지속 주행 수용으로 확대하지 않는다.

기존 새 창은 코드 변경을 자동 반영하지 않는다. 최신 일반 실행기로 다시 열고 Esc의 외형/보행/야외 풀 메뉴와 F/X/G를 체험한다. 기존 속도/해질녘 저장은 보존한다. 아래 인수 안내는 각각 당시 이력이다.

최신 외형 목표는 몸 크기 구분뿐 아니라 매력적인 얼굴과 평범/성숙/투박한 인상을 모두 설득력 있게 만드는 것이다. [미술 방향 제안](REFERENCE_DIRECTION.md#2026-10-24-캐릭터-미술-방향--매력과-개성)의 제작 방식/고정 조명 비교부터 시작한다. 현재 얼굴의 단면 반경을 반복 조절하거나 프리셋 숫자만 늘리는 방식으로 완료 처리하지 않는다. 새 얼굴/헤어스타일은 아직 미구현이다.

## 이전 인수: 2026-10-23 EXP32 도시 액션

[WORK_STATUS](WORK_STATUS.md)·[EXP32 summary](../data/reports/city_action_freedom/20261023/summary.json)·[조작/구현 범위](CITY_ACTION_FREEDOM.md)를 먼저 읽는다. F 세 연속 동작/X 밀기/G 방어 자세와 원래 도로 차14대의 staged E 진입/H 경적이 추가됐다. `city_public_safety.gd`가 접촉 시 실제 성인/벽을 검사하고, avatar의 matching cancel은 지난 동작이 새 탑승/구금 제어를 덮지 않게 한다. `traffic_car_takeover.gd`는 본래 차의 AI/FIFO→player 제어를 성공 시 인계하고 player_enter 취소와 체포 소유권을 구분한다.

새 자산/의존성 다운로드는 없으며 MIT 인체/기존 지도/네 생성 입력 준비를 유지한다. 일반 실행은 기존 실행기다. 새 `action_freedom` suite와 승하차/취소 fixture의 정확한 명령은 선별된 `.run.json`에 있다. 저장 인수 기본 summary는 EXP32이고 저장 무결성 검사를 새 엔진 실행·픽셀/OS·주관적 조작감으로 확대하지 않는다. 기존 열린 창은 새 코드를 자동으로 받지 않으므로 재실행이 필요하다.

## 이전 인수: 2026-10-22 EXP31 상체·팔 보행

[WORK_STATUS](WORK_STATUS.md)·[EXP31 summary](../data/reports/upper_body_gait/20261022/summary.json)·[구현/조작](HUMAN_GAIT_AND_LIFE.md)을 먼저 읽는다. 새로운 의존성/자산은 없다. 작은 가슴/어깨 회전과 팔꿈치 굽힘을 표시 위상에 맞추고, 첫 척추와 thigh socket은 골반을 따른다. 원래 목/머리 local 연결과 본 길이를 유지한다. 고정 접촉과 authored 타격/움찔이 보행 팔보다 우선한다.

새 fixture는 `tests/game/check_human_upper_gait.gd`와 `tests/game/check_human_authored_actions.gd`다. 정확한 실행 인수는 집계가 선별한 `.run.json`을 따른다. `human_gait native`는 실제 남녀144PNG를 만든다. 현재 저장 무결성 기본 manifest는 EXP31이며 `--prepared`는 네 생성 입력까지 대조한다. 새 엔진 실행·픽셀 검토·일반 OS 조작·사용자 편안함은 서로 다른 증거다. 보행 체험은 세션1.4/3.5m/s이고 저장 초고속/해질녘은 보존한다. 아래 인수의 당시 기본 경로/수치는 역사 기록이다.

## 이전 인수: 2026-10-22 EXP30 보행 지지·도서관 공부·야외 풀

[WORK_STATUS](WORK_STATUS.md), [EXP30 summary](../data/reports/human_gait/20261022/summary.json), [조작·설계·검증](HUMAN_GAIT_AND_LIFE.md)을 먼저 읽는다. 실제 표시 시점의 골반/발 접촉을 검사하며 고정120Hz PASS로 기본30Hz의 중간 프레임까지 수용하지 않는다. `human_gait_support.gd`는 실제 rest skin의 sole patch로 heel/toe pivot을 구하고, `exploration_camera.gd`는 이전/현재 물리 gait를 보간한 표시 위상과 발 목표를 렌더 전용 metadata로 전달한다. 다음 물리 tick에서는 metadata/표시 pose를 복원해 피드백하지 않는다. 공통 골반 profile 캐시는 공통 marker parent 프레임을 쓰며 현재 물리 actor 원점과 섞지 않는다.

공부는 기존 facility fresh-E owner의 study 활동이다. 풀 바는 기존 pool-preparation dispatcher를 공유하고 준비 gate를 열지 않는다. Esc의 서울도서관 공부 정문, 야외 풀 해질녘 바로가기를 사용한다. 새 다운로드·의존성·원본 지도 변경은 없고 일반 실행기는 기존 준비/import를 사용한다. 저장 초고속/시간과 현재 체험 세션은 구분한다. 아래 인수와 EXP29 manifest는 과거 소스의 기록이다.

## 이전 인수: 2026-10-22 EXP29 사람 시선·텍스처 인체·골반/보행

[WORK_STATUS](WORK_STATUS.md)·[EXP29 최종 집계](../data/reports/human_presence/20261022/summary.json)를 먼저 읽는다. source Avatar/Rig/Surface는 실제81본 스킨과163본 수영 몸체를 연결하며 기존59개 외형은 숨긴 접촉 호환 기준이다. 실제 사람의 geometry를 숨긴 proxy AABB로 검증하지 않는다. 원본 본 길이·골반 연결·실제 CPU 스킨 인덱스와 앞뒤양옆 위상을 본다. 중립 목만 맞는 것으로 보행 접합까지 수용하지 않으며 표시 단계 머리 체인 동기화를 유지한다.

새 Mac은 기존 준비 후 일반 실행기의 FBX/GLB import를 마친다. `.godot`/TGA 캐시는 Git 대상이 아니며 실제 파생 자산·MIT/CC0 고지는 Git으로 공유한다. 선택형 재생성/접촉시트 도구에는 NumPy/Pillow가 필요하지만 일반 게임은 미리 준비된 자산을 사용하므로 새 Python 의존성을 요구하지 않는다. 현재 저장 인수 검사기의 기본 summary는 EXP29이며 `--prepared`는 네 생성 입력까지 대조한다. 이 검사는 새 엔진 실행이나 주관적 자연스러움을 증명하지 않는다.

조작은 V 눈높이, Esc 걷기 체험, WASD/Shift/Space다. 체험은 세션1.4/3.5m/s이며 저장 초고속은 보존한다. 실제 남녀144위상과 별도 대표 native 원본 중 확인한 사진·일반 OS 입력의 정확한 범위는 집계를 따른다. 수영복 재단·피부톤/헤어 카드·몸의 상하 움직임과 두 원본 반복은 남아 있다. 다음은 열린 일반 게임에서 직접 체험하는 것이다. 아래 인수는 이전 소스의 이력이다.


## 이전 인수: 2026-10-22 EXP28 실제 치수·외곽 대형 공공시설

[WORK_STATUS](WORK_STATUS.md)와 [EXP28 집계](../data/reports/real_scale/20261022/summary.json)를 먼저 읽는다. EXP27 도로 자동차 인계·Q·F/경찰·소방/기상에 더해 대형 병원/공공청사·새 자동문/보행·원본 파출소/263m순찰·23차체 위치 음향·사람 비례/동작·건물 폭/간격 비교가 결합된 소스다. 사용자가 개편 전 버전의 별도 브랜치 보관과 ‘현재 지도 외곽에 실제 크기 기준의 게임 대형 시설’을 직접 선택했다. `codex/archive-before-real-scale-20261022`의 `69db9ca`는 진행 중 보관점이고 전체 최종 수용 배포본이 아니다.

병원48×34m·12층 주 외피44m, 소방서36×30×12m·3차고/8m펌프차2대, 경찰청사30×22×15.6m는 가상 설계다. 기존151.65㎡ 세종로파출소를 확대하지 않는다. 새 병원과 경찰청사 공용1층은 같은 세계의 바닥/벽/native 자동문이며 외부 전환 owner를 만들지 않는다. 기존 파출소52㎡ 분리 게임 로비는 opening/inside→구금→8/12초 석방까지 실제 owner 정리를 검사했다. 소방차는 후진 차고 복귀까지 실제 경로를 따르고 대기차는 엔진이 꺼져 있다. 원래28성인/2개/14AI차/1233source IDs와 추가 인원·차량은 분리한다.

`tools/audit_real_scale.py`는 원본635동의 재투영/너비·깊이·최소 간격과 height basis를 기록하고 치수 비교/병원 제작 자료를 생성한다. 원본 기하/간격과 런타임 경계 일치를 독립 실측 정확성으로 해석하지 않는다. 479동 기본 높이·53동 층수 추정·4랜드마크 가정·1구성부외피와 높이태그98건을 구분한다. 미측정 높이를 일괄 확대/승격하지 않는다. 인체 원캡슐1.70/0.30을 유지하고 실제mesh 키/머리비례·관절·접지·가감속·회전을 개선했지만 GTA 자산/모션캡처·21m/s 현실 보행은 아니다.

새 시설 이름/입구 안내는 `civic_facility_guidance.gd`의 늦은 visual pass로 원본 안내를 잠시 가린다. `building_names.current_*`나 실제 catalog/E 소유권을 변경하지 않는다. 비교 mode는 좌하단 읽기창/1m격자·2m눈금으로 치수를 표시하고 원래 입구 배지만 숨긴다. 차량소리는 Master/기타음악을 바꾸지 않는 별도 조절이며 실제PCM 좌우/무음/음량/메뉴 검사와 헤더 검사·주관 음질/전체Master 합성을 구분한다.

저장 인수 도구의 기본 summary는 EXP28이다. `--prepared`는 네 생성 입력의 SHA도 대조하며 새 엔진 실행·OS 조작·장시간 성능을 증명하지 않는다. 최종 exact 분모·현재SHA·raw 실패/수정·실제 화면·일반 기동 범위는 집계를 따른다. 새 Mac은 기존 준비/지형 생성 후 일반 실행기를 사용한다. 이전 EXP27/26/25 결과를 이번 소스의 새 수용으로 재사용하지 않는다.

## EXP27 개발 이력: 2026-10-22 도시 샌드박스

[WORK_STATUS](WORK_STATUS.md)·[EXP27 집계](../data/reports/real_scale/20261022/summary.json)부터 읽는다. 도로의 원래 14대 E 탈취·운전, Q 개인 킥보드, F 성인 NPC 타격/경찰 60초 추격·조사/유치, 게임 119 출동과 간헐적 비/화재가 현재 범위다. 실제 사건·법률·시설 위치·기상 정보를 재현한 기능이 아니다. 사용자의 이번 명시적 요청이 이전 EXP24의 AI 자동차 분리 설계를 변경했다. 원본 차를 삭제/복제하지 않고 같은 body/model/shape의 AI 소유권만 인수한다.

새 모듈은 `traffic_car_takeover.gd`, `city_public_safety.gd`, `city_weather_emergency.gd`다. 개인 킥보드는 기존 서비스의 안전한 native/source 검사를 공유한다. 지연 하차의 충돌쌍 해제는 유지하되 구금 중 제어를 복원하지 않는다. 구금의 외부 이동/체크박스/메뉴 우회는 host가 막으며 검증된 지면 전환만 내부 소유권으로 수행한다. 경찰은 원본 public/playable TIN 틈을 걷되 사유지·정문·native 충돌을 계속 검사한다. 고정 대기/귀가 위치는 기존16대의 전방8m·시설·승하차 공간을 비운다. 생산 30Hz의 이전/현재 위치를 보이는 모델에 보간하고, 경로 탐색은 짧은 물리 틱 작업으로 나눈다.

Esc에서 도로 자동차·경찰 안내소·119안전센터·비/화재 체험으로 이동할 수 있다. Q 호출은 지원되는 실외 지면에서 개인 차체 하나를 재사용한다. 비는 실내를 제외하고 시간대 광원을 기준으로 적용/복원한다. 소방차/소방관은 지정 출동 경로를 실제 이동하며 막힌 경로를 순간이동하지 않는다. 원본 28명/개2/14대와 새 경찰4/소방관2/소방차1은 분리해 센다.

저장 무결성 검사기의 기본 summary는 현재 결합 EXP28이다. `--prepared`는 재생성한 네 입력의 SHA도 비교하며 새 엔진 실행·OS 조작·성능 검사가 아니다. 원문 실패/수정 기록은 삭제하지 않고 최종 source와 일치하는 결과만 current 목록에 넣는다. 새 기능 및 킥보드/자전거/E/카메라 회귀의 정확한 분모, 실제 검토 이미지와 일반 실행 판정은 EXP27 집계를 따른다. 다른 Mac/export·장시간 성능·사용자 주관적 조작감은 별도다.

## 이전 인수: 2026-10-22 EXP26 분산 대여

[WORK_STATUS](WORK_STATUS.md)와 [EXP26 집계](../data/reports/mobility_distribution/20261022/summary.json)부터 읽는다. 두 authored service JSON은 각각8개 지점이며 기존 첫2개 record/policy는 그대로다. 추가 지점은 도서관 북측·세종대로 북측·을지로입구·북창동 남측·서소문·덕수궁 북측이다. 실제 업체/대여소 위치가 아닌 게임 배치다.

`city_bike_service.gd`는 원본 walk 삼각형을 기존 movement 색인에 더하고 public_walk에 없는 경로 ID를 이미 로드한 neighborhood 원본 경로에서 찾는다. JSON의 neighborhood 입력 SHA를 유지한다. 모든 표지/판/거치대 바닥 투영은 실제 수직 시설과 같은 yaw-only 좌표, 차체는 기존 경사 basis를 사용한다. source/사유지/정문·native 지원/점유와 주행 sweep을 약화하지 않는다. 좁은 보도에서 모델 크기나 source를 바꿔 해결하지 않았다.

현재 전수 실행은 headless88/88·native92/92이며 원본 mesh ID1,233개와 사람28·개2·AI차14·capsule/TIN을 보존한다. native 새 구역 대표4장을 직접 검수했다. E 회귀204/204, 자전거23/23·킥보드30/30·시야14/14·고속29/29·자동차30/30·탑승 카메라73/73도 현재 입력과 일치한다. 중복 시나리오이며 고유 요구사항으로 합산하지 않는다.

실행 도구의 `distribution`을 사용하고 `--output-dir data/reports/mobility_distribution/20261022/acceptance`를 지정한다. 기본 출력 경로는 옛 실행 재현을 위해 EXP25 그대로다. 저장 무결성 검사기의 기본 summary는 EXP26으로 갱신했다. `--prepared`는 재생성 입력의 SHA까지 확인하며 새 엔진 실행/성능/실제 서울 정확도는 판정하지 않는다. 실패/과거 보고서를 current 목록에 추가하지 않는다.

일반 실행 창·초고속/자유탐험/해질녘 및 OS Esc 메뉴는 확인했으나 CUA 스크롤/재연결이 응답 시간 초과로 끝나 이번 개정의 일반 OS E/W/Space/E는 미검증이다. 재연결 후 버스 탑승 화면이 관측됐으나 해당 입력은 이 에이전트가 수행하지 않아 출처를 확정하지 않고 추가 자동 조작을 중단했다. 창을 유지했다. [일반 실행 기록](../data/reports/mobility_distribution/20261022/normal_launch.json), 조작은 [RUN_GUIDE](RUN_GUIDE.md)를 따른다. 아래 EXP25의 기능 설명은 이어받되 당시 검사 수를 이번 source 판정으로 재사용하지 않는다.

## 이전 인수: 2026-10-21 EXP25 빠른 이동·도로·순환 교통·지하 연결

[WORK_STATUS](WORK_STATUS.md)와 [EXP25 집계](../data/reports/urban_transit/20261021/summary.json)부터 확인한다. 최종 실행 범위와 남은 확인은 그 두 파일을 기준으로 하며 아래 EXP24/23 판정을 변경된 소스의 수용 결과로 재사용하지 않는다. 일반 실행은 `sh tools/run_exploration.sh run`이고 새 외부 모델·의존성 다운로드는 없다.

- 최종 탑승 표시 검사는 native73/73이다. camera가 고정 활동과 이동 탑승을 구분하며 vehicle/avatar/eye와 로프 하네스·양 끝에 같은 표시 시점을 쓴다. 물리 body를 render에서 움직이거나 기존 native 충돌을 해제하지 않는다. 회귀는 `camera` suite로 실제 이동 중 여러 표시 분율과 정상 주행 snap0·메뉴/복원을 확인한다.
- `transport_motion_policy.gd`는 현재 달리기 속도를 기준으로 전진 최고 속도·가속·제동을 계산한다. 초고속 달리기 21m/s에서 bike/scooter/car/helicopter의 최고 속도는 33.6/42/52.5/84m/s다. 역방향과 정차·앞차/신호·장애물 대기는 별도이며, 최고 속도를 평균 여행 속도라고 설명하지 않는다. 빠른 이동의 중간 지지면 표본·native 연속 충돌·원래 캡슐/소스 경계 검사를 유지한다.
- `prepare_road_furniture.py`·`street_network_detail.gd`는 원본 차도와 겹치는 보도 **표시 메시**만 잘라 차선이 보이게 한다. 원본 노드·XZ·충돌·공공 보행 권한을 함께 삭제하지 않는다. 비대칭 세종대로는 마주 보는 원본 차도 표시 경계 사이에 공유 중앙선을 만들며 횡단부·교차부·게임 버스 회전부를 비운다. 도로 자산은 `bus_service.json`의 해시도 확인하므로 버스 정류장/회전 입력을 수정한 뒤 도로 자산을 다시 생성한다.
- `city_bus_service.gd`와 제작 자산은 3대·4정류장·약 812m 실제 이동 순환을 맡는다. 원래 14개 이동 자동차의 끝점/카메라 재배치 규칙을 바꾸지 않고 그 전에 게임 회전부를 배치한다. 정류장·대기 위치·물리 쉘터는 원본 횡단 동선을 비워야 한다. 탑승/하차 뒤 카메라 yaw·pitch·distance와 제어·충돌 관계를 모두 복원한다.
- `city_subway_service.gd`는 원본 시청역 5번/을지로입구역 1-1번 출구 정체성과 지역 선형을 보존한다. 지하 대합실·개찰·계단·승강장·열차는 게임 공간이다. 약 338m는 확보한 지역 선형 길이이며 실제 역간 전체 거리·현장 평면·배차로 주장하지 않는다. 역 방문 `active`와 열차 `riding`을 구분하고 같은 E 디스패처와 검증 후 장소 전환을 쓴다.
- `game_underground_connections.gd`는 시청역 게임 대합실과 서울도서관/서울특별시청 B1의 연결문을 맡는다. 실제 복도 보행 뒤 E로 분리된 게임 실내를 연결하며 도착 공간을 먼저 검사한 뒤 소유권을 교환한다. 원본 건물 층수·평면 크기를 유지하고 B1 인덱스 -1을 별도로 추가한다. 실패/메뉴/장소 이동에서 pending만 정리하며 기존 방문·외부 복귀 상태를 먼저 버리지 않는다. B1 계단과 승강기를 통해 기존 지상층·옥상으로 이어진다.
- `interior_escalator.gd`는 원래 SFC 크기 안에서 1↔2↔3↔4층의 상·하행 3쌍을 만든다. 실제 슬래브 개구부·층별 연결 보행·가구/사람 예약 영역을 함께 유지한다. 움직이는 표시 발판과 부드러운 운반 지지면을 분리해 캡슐이 계단 단차마다 진동하지 않게 한다.
- `city_helicopter_rope.gd`는 새 R 입력·제동/호버·캡슐 연속 하강/회수를 맡는다. 지면/지원되는 게임 옥상과 기체 전체 착륙 검사를 유지한다. 성공 하강 뒤 보행용 basis를 복원하고, 메뉴에서 시작한 R이나 이동 후 남은 하강 예약을 재실행하지 않는다. 로프 완료/착륙장 메뉴의 기체 회수는 게임 위치 복귀이며 실제 복귀 비행이 아니다. 옥상 관찰 바로가기는 플레이어만 옮기고 지형 높이로 다시 내리지 않는다.

입력·소유권의 조립은 `explore_walk.gd`와 `interior_visit.gd`의 단일 fresh E 경로를 따른다. 새 기능 때문에 쇼핑·의상·샤워/수영 준비·기존 출입 상태를 우회하거나 동시에 여러 탈것이 플레이어를 소유하게 하지 않는다. 사용자 조작 안내는 [RUN_GUIDE](RUN_GUIDE.md), 재현할 검사는 [VALIDATION_PLAN](VALIDATION_PLAN.md)를 따른다. 저장 무결성 검사는 `python3 tools/check_street_detail_handoff.py [--prepared]`이며 실제 엔진·OS 조작·다른 Mac의 성능 수용을 대신하지 않는다. 진행 중/실패 보고서의 숫자 PASS만 보지 말고 예상 판정 수·원시 엔진 오류·현재 소스 SHA를 대조한다.

검사기의 기본 집계는 `data/reports/urban_transit/20261021/summary.json`이다. 실제 재실행은 `python3 tools/run_urban_transit_acceptance.py <suite> <headless|native> <새_태그>`를 쓴다. `--help`로 선택 가능한 suite를 확인하고, 기본 외 위치의 Godot는 `SIM2SEOUL_GODOT`에 지정한다. 도구는 기존 태그를 거절하며 판정 JSON·원시 엔진/콘솔 로그·실행 조건을 별도로 보존하고 스크립트 오류를 실패로 기록한다. `native`는 실제 그래픽 창을 여므로 직접 플레이와 겹치지 않게 한다. 보고서 생성과 이미지 검토·일반 OS 키 입력은 별도다.

## 이전 인수: 2026-10-21 EXP24 상점·옷·운전·비행·수영 준비

[WORK_STATUS](WORK_STATUS.md)와 [EXP24 집계](../data/reports/city_life/20261021/summary.json)를 먼저 읽는다. `shop_visit_service.gd`는 기존 문에 연결한 편의점/식당과 가상 의류점, 거래 토큰·보유품·구매 의상/수영복을 맡는다. `drivable_car_service.gd`는 자전거 기반의 전체 차체/차도 판정을 별도로 대체하고, `city_helicopter_service.gd`는 로터·꼬리 포함 native 기체와 실제 비행/착륙·안전 회수를 맡는다.

`pool_preparation_service.gd`는 별도 E 입력 없이 공통 디스패처로 탈의·수영복·샤워 완료·입수 허가를 처리한다. `rooftop_space.gd`가 현재 두 게임 호텔 풀의 준비실/게이트를 생성하고 같은 outdoor_pool 클래스의 새 지붕에도 적용한다. `free_roam_player.gd`의 물 이동 전/후 guard로 사복·미완료 상태의 점프/낙하 우회를 막는다. 사복 즉시 입수였던 과거 기대값을 되살리지 않는다.

`explore_walk.gd`의 소유권·가까운 대상/힌트·검증 후 장소 이동/복원과 `interior_visit.gd`의 단일 physical E를 함께 유지한다. 실패 목적지는 현재 방문/탑승/샤워를 먼저 취소하지 않는다. 검증한 roof는 terrain y로 다시 내리지 않는다. 메뉴 복귀 시 상품/소지품의 커서·포커스를 보존한다. 테스트의 observer 배치/합성 유지 입력과 실제 OS 조작을 구분하며, 현재 source hashes가 맞는 보고서만 최신 판정에 사용한다.

새 의존성이나 외부 모델 다운로드는 없다. 새 Mac은 기존 준비 순서 후 일반 실행기를 사용하고, `python3 tools/check_street_detail_handoff.py --prepared`는 저장 입력·증거 일치만 검사한다. 실제 실행은 [RUN_GUIDE](RUN_GUIDE.md), 재검증은 [VALIDATION_PLAN](VALIDATION_PLAN.md)를 따른다. 첫 native 옷 관찰 가림·풀 준비실 시야/부호 문제와 수정 전 결과를 지우지 않는다. 아래 EXP23은 이전 소스/날짜의 인수 이력이다.


## 이전 인수: 2026-10-20 E 탑승 안정화·킥보드와 거리 신호 회귀

[WORK_STATUS](WORK_STATUS.md)와 [최신 집계](../data/reports/street_detail/20261020/summary.json)부터 읽는다. 같은 날짜에 두 요청 흐름이 이어졌다. 첫째는 자전거 시야와 원본 횡단 후보의 신호 배치/자동 주기이고, 둘째는 실제 E 탑승의 간헐적 실패와 직접 타는 전동 킥보드다. 아래 선행 완료 기록을 추가 요청 뒤 소스의 통과로 재사용하지 않는다. 추가 요청까지 동결 소스로 완료했고 이 Mac의 일반 창에서 OS E 탑승·W 이동·Space 제동·E 하차를 확인했다. 최신 실행·화면·실패와 수정은 집계와 WORK_STATUS에 연결한다.

입력·탑승 쪽은 `city_bike_service.gd`의 공유 기반, 이를 상속한 `city_scooter_service.gd`와 2대/2대여소 자료, `interior_visit.gd`의 물리 E 처리, `explore_walk.gd`/버스의 공통 대상 선택·동시 탑승 금지·복원을 함께 본다. 장치 변형 입력, 짧은 탭과 메뉴에서 누른 채 복귀한 입력, 현재 발밑 지지, 보행자가 잠깐 지나가는 시선과 실제 점유 거절을 각각 검사한다. 일반 창의 OS E 조작 여부는 엔진 이벤트와 구분해 최신 기록에서 확인한다.

도로·회귀 쪽은 앞선 신호 위치/방향·자연 두 주기·기존 차량 제동/버스와 건물 출입을 유지하는지 확인한다. 킥보드 주차 때문에 자전거 경로가 물리적으로 막히는 실패와 native 창의 입력 유지 실패도 별도 개발 증거로 남긴다. 실행을 통과시키려고 원래 경로·충돌·키보드 판정 조건을 약화하지 않는다. 현재 해결/미해결·다음 첫 행동은 WORK_STATUS가 기준이며 이 문서에 완료 수를 중복 확정하지 않는다.

최종 검증 전에는 생산 입력·공유 기반 제어·모델·대여소 배치를 동결하고, 보고서의 소스 해시가 그 동결본과 맞는지 먼저 확인한다. 변경 중 나온 PASS는 개발 이력으로 보존하며, 영향을 받은 기능을 같은 소스에서 다시 검사한다. 일반 실행/조작은 [RUN_GUIDE](RUN_GUIDE.md), 필요한 실제 검사는 [VALIDATION_PLAN](VALIDATION_PLAN.md)을 따른다. 공유 무결성 검사 자체를 새 Mac의 실행·직접 조작 수용으로 바꾸지 않는다.

## 선행 인수 이력: 2026-10-20 자전거 시야와 횡단 신호 보완

WORK_STATUS와 [새 집계](../data/reports/street_detail/20261020/summary.json)를 먼저 읽는다. 일반 실행은 `sh tools/run_exploration.sh run`, 공유 검사는 `python3 tools/check_street_detail_handoff.py [--prepared]`다. 검사기의 기본 manifest는 20261020이며 `--summary`로 과거 동결본을 지정할 수 있다(변경된 현재 소스로 과거 SHA 검사 성공을 기대하지 않는다). 기존 열린 창은 갱신 뒤 재실행한다. 새 의존성/외부 다운로드는 없다.

자전거 2대의 실제 바로가기·탑승 시점/표지, 7횡단/29신호와 46초 자동 주기·보행 점멸/카운터·새 신호 앞 기존 차량 제동을 반영했다. source 후보 79개에는 수용/제외 근거가 있다. 북측 교량의 가린 두 횡단부를 임의로 건물 위에 얹어 완료하지 않았다. 일반 바로가기는 대한문 앞 보도에서 건너편 신호를 보며, 별도 native 차량 검수는 차선 정지선 뒤에 명시적으로 배치한 시험이다. 아래 EXP22/21 인수와 20261019 수치는 과거 소스의 이력이다.

## 이전 인수: EXP22 가로수 성목 비례와 세부 외형

최신 상태는 WORK_STATUS와 [EXP22 요약](../data/reports/tree_detail/20261018/summary.json)이다.369개 원래 식재/전체 지면과 줄기 충돌은 유지하고 표시 모델/셰이더만 개선했다. 현재 공유 무결성은 `python3 tools/check_tree_detail_handoff.py [--prepared]`로 확인한다. 실제 재검사는 VALIDATION_PLAN의 EXP22 절을 따른다. 아래 EXP21의 고정 수관3개 검사·과거 소스 해시는 당시 이력이며 현재 모델 수용에 재사용하지 않는다. 새 모델/셰이더는 Git으로 공유되고 별도 다운로드나 유료 asset/Python 의존성을 추가하지 않는다.

## 이전 인수: EXP21 지형 연결의 구현과 검증 기록

최신 단일 상태는 [WORK_STATUS](WORK_STATUS.md), 최종 인수 파일·실행 결과는 [EXP21 summary](../data/reports/terrain_integration/20261018/summary.json), 구현 이유와 한계는 [TERRAIN_INTEGRATION](TERRAIN_INTEGRATION.md)이다. 이 문서에 최종 검사 수나 완료·커밋을 중복 확정하지 않는다. 요약이 없으면 최종 인수 기록이 아직 없는 것이며, 과거 EXP20의 평면판 결과로 새 지형을 완료 처리하지 않는다.

로그인 없이 확보한 서울시 공식 등고선41개·표고점96개와 공유 높이장을 재사용한다. source EPSG5174/기존32652 좌표와 원래 HEIGHT를 보존하고, 고정 원점의 보간 높이를 뺀 상대Y와 추정한525개 기초를 탐험 장면에 연결한다. 원본635개 건물의 XZ·자체 높이·층수와 source/world bytes는 그대로다. 도로·마당·지원체는 동일 지형 삼각형에 맞춰 나누고 원래 면의 높이·두께를 더한다. 분리 실내 셀은 자체 좌표를 유지하며 문·옥상·풀·승강기·밖 복귀는 새 기초/지면 기준을 쓴다. 수직 datum 미상, 표고점 보류 검사 RMSE2.315m/최대8.739m, 실측이 아닌 기초 평탄화는 계속 명시한다.

현재 파일·증거 무결성은 `python3 tools/check_terrain_handoff.py`로 확인한다. 실행 자료 준비 뒤 `--prepared`를 추가한다. 이 도구는 엔진을 재실행하거나 새 Mac을 수용하는 검사가 아니다. 실제 재시험은 `tools/run_terrain_validation.py`와 [검증 계획의 EXP21 절](VALIDATION_PLAN.md#exp21-지형-연결-검증과-인수-기준)을 따르며, 이전 실패·원시 결과를 덮어쓰지 않는 새 출력 경로를 쓴다. EXP20 [요약](../data/reports/realism_rework/20261017/summary.json)/`check_realism_handoff.py`는 당시 소스의 이력으로 보존한다.

다른 Mac에서는 [CROSS_MAC](CROSS_MAC.md)의 Python 환경과 기존11개 V0 생성기 준비를 먼저 마친다. 이후 `Sim2Seoul.command`/`sh tools/run_exploration.sh run`이 `prepare_local_terrain.py`로 공유 준비 증거를 보존하면서 Git 제외 물리 TIN/색인을 준비하고 Godot import 후 실행한다. 첫 장면 투영의 기하 캐시도 그 Mac에서 생성한다. 캐시는 엔진 버전·원본 기하/변환·전체 지형 SHA·투영·높이 조회 코드 SHA가 맞을 때만 재사용하며 없거나 손상되면 실제 투영으로 돌아간다. 준비 도구가 Python 의존성 설치까지 대신하지 않는다. 서울 전체 ZIP이나 NGII 로그인은 기본 인수의 선행 조건이 아니다.

최신 탐험 leaf의 기본 물리는30Hz(`exploration_physics_hz=30`)이고 화면 주기는 독립적이다. 전체 배우의 개선 후 물리 step 약19ms 관측이60Hz 예산16.7ms를 넘겨 기본값을 바꿨으며, 기존 milestone60Hz는 유지한다. m/s·1m·초 기준 중력/타이머·source XZ/충돌·속도 판정 기준을 바꾸지 않는다. 실제 충돌/현재 step 검사와 동적 상대 검사는 매 물리 step 수행하고, 미래0.9m의 정적 미리보기만0.15초 간격으로 재사용한다. 실패·방향 전환·우회 계획 종료 시에는 즉시 갱신한다. 원래 다각형/문 거리의 공간 색인과 단일 choose 안의 동일 바닥 조회 재사용은 최종 원본 판정을 유지한다. 재현 runner는 `--physics-hz=30|60`을 받으며 GPU 기본30/headless 기본60이다.30Hz 실제 여정과60Hz 스트레스, 짧은 부하 관측을 구분해 이어받고 과거60Hz 보고서를 지우지 않는다.

기존 옥상/야외 풀·관리자 객실 문·장소별 인물·외관/가로수·분산 인구 기능을 유지하며, 원래 사용자 속도/시간/자유탐험 설정도 유지한다. `Sim2Seoul.command`는 개발 장면이고 이전 V0/R03 앱 ZIP은 이번 변경을 포함하지 않는다. 사람 직접 체감·모든 실측 문턱/옹벽·지하/교량 구조·장시간 성능·새 export·M4 검증은 별도다. 대중교통 T01의 착수 여부와 다음 첫 행동도 WORK_STATUS에서 읽는다.

아래 단계별 설명은 각 작업 당시의 인수 이력이다. 과거 문장의 ‘현재’나 ‘다음 작업’을 최신 상태보다 우선하지 않는다.

이 문서는 사용자가 비용을 고려해 Sol로 이어서 개발할 때 필요한 짧은 진입점이다. 현재 채팅 모델을 자동으로 변경하거나 더 비싼 모델을 호출하는 지시가 아니다.

## 먼저 읽을 것

루트 [AGENTS.md](../AGENTS.md)가 새 세션의 시작 지침이다. 새 Mac에서는 [CROSS_MAC.md](CROSS_MAC.md)에 따라 공유 지역 지도와 Python 환경을 준비한다. 국가 원본은 전체 D02 재검사가 필요할 때만 받는다.

1. [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md): 목표·선택 이유·확정/미정. 최초 진입과 범위 변경 때 확인하고 변경이 없다면 반복하지 않는다.
2. [WORK_STATUS.md](WORK_STATUS.md): 실제 완료 증거와 다음 작업. 새 작업마다 확인한다.
3. [MASTER_PLAN.md](MASTER_PLAN.md): 최초 진입에는 전체 단계와 W0/V0 완료 의미를 파악한다.
4. [IMPLEMENTATION_TASKS.md](IMPLEMENTATION_TASKS.md): 수행할 ID의 항목만.
5. [TECHNICAL_CONTRACTS.md](TECHNICAL_CONTRACTS.md), [VALIDATION_PLAN.md](VALIDATION_PLAN.md): 그 ID와 관련된 절만. 이전 변경 이유가 필요하면 [EXECUTION_LOG.md](EXECUTION_LOG.md)의 해당 기록을 읽는다.

매번 전체 대화·모든 문서·전국 지도 데이터를 읽지 않는다. 대화가 다른 기기에 자동으로 이어진다고 가정하지 않고, 저장소의 결정·상태·증거를 사용한다.

## 바꾸면 안 되는 핵심

- 실제 도로/건물 배치와 1m 축척을 바탕으로 한 3인칭 공간이다.
- 대한문을 지나 **덕수궁 경내를 걷는 기능은 필수**다. 건물 실내와 혼동하지 않는다.
- 첫 중간 결과 W0는 보행 검증이다. 사용자 합의 첫 버전 V0는 랜드마크·간단한 보행자·차량을 포함한다.
- M1 Pro 16GB 기준으로 개발하고 M4 Pro에서도 확인한다. M4의 1TB는 저장공간이며 RAM은 아직 모른다.
- 데이터에 없는 높이·도로폭·지형은 출처와 추정을 구분한다. 핵심 동선을 임의의 길로 연결하지 않는다.
- 개발 기준은 Godot 4.7.2 Standard·Forward+/Metal이다. E02 정식 `game/`은 [실행 도구와 구조](GAME_PROJECT.md)로 로컬 기동된다. 원천 region→G01 해시 대조→Git 제외 실행 사본을 준비하며 입력은 의도만 전달한다. E03 서울 배치·E04 외곽점 거리/10m 기준물/화면 비례 검증을 완료했다. [E04 화면/재현](../data/reports/scale_view/README.md)을 유지하고 P01 사람 크기 캐릭터/독립 시험장·60초 안정 정지 검증도 완료했다. P02에서 [시험장 이동/복귀·증거](../data/reports/movement.md)도 완료했다. P03의 [카메라 조작/가림·문 회전·잠금 검증](../data/reports/camera.md)도 완료했다. P04의 [충돌 계층·도시 배치 검증](../data/reports/collision.md)도 완료했다. W01의 [대한문 밖↔경내 입구 연결](../data/reports/daehanmun_walk.md)도 완료했고 W02의 [경내 순환·앞마당](../data/reports/palace_walk.md)도 완료했다. W03의 [도심·돌담길 연결/장면 경계](../data/reports/public_walk.md)도 완료했다. W04의 [자동 연속 여정·중간 버전 보존](../data/reports/walkable_milestone.md)도 완료했다. `W0-engineering-walk-v1` 스냅샷/인수는 기존 W03 게임·원천/경계를 유지한 자동 엔진 판정이며 직접 사람/OS·현실 접근/지형·M4는 미검증이다. L01의 참조·제작 명세도 완료했으며 해당 단계 당시의 재개는 N03 차량 이동이었으며 현재 재개는 WORK_STATUS를 따른다. 기존 W01/W02/W03 원문·실패·검증을 재사용한다. 시험장 이동은 실제 서울 보행과 구분하며 직접 키 조작감은 미검증이다. E02 화면 잠금 이력과 GPU/엔진 자동 검증을 직접 사용성 검사와 구분한다.

## 작업을 작게 수행하는 규칙

1. 선행 입력이 있는 작업 하나를 고른다. 현재 원본을 재다운로드하거나 성공한 준비를 처음부터 반복하지 않는다.
2. 시작 시 변경할 파일과 검증 방법을 짧게 정한다.
3. 기존 산출물을 보존하며 필요한 변경만 한다. 대형 파일을 답변/문맥에 출력하지 않는다.
4. 변경 목적을 실제로 확인하는 시험만 한다. 같은 조건으로 의미 없이 반복하지 않는다.
5. 결과를 기록하고 다음 작업의 입력이 준비됐는지 판단한다. 사용자가 연속 구현을 요청했다면 한 작업의 검증 후 다음 작업을 이어갈 수 있다.

기본은 단일 Sol이다. 독립적인 자료 조사/검토를 병렬로 맡길 때만 이득을 따져 사용하며, 짧은 목적·필요한 입력만 전달한다. 전체 대화 복제와 여러 에이전트의 같은 조사 반복을 피한다. 모델 성능·비용에 대한 근거 없는 수치를 만들지 않는다.

같은 원인으로 두 번 실패하면 오류·시도 차이·재개 조건을 기록하고 대안을 고른다. 자동으로 Astra 사용을 전제하지 않는다. 기술적 실패가 아니라 사용자만 정할 수 있는 실내 범위 등의 결정이 필요한 경우에는 결정 직전의 구체적인 선택지만 묻는다.

사용자는 직접 확인·점검·인사이트가 유용할 때 알려주기를 원한다(2026-10-13). 모든 작업에 확인을 요청하지 말고, E03/E04 배치·축척 화면, P/W 조작·카메라·동선, L 장소 인상 등에서 이유·확인 항목·화면/실행 방법을 함께 제시한다. 검토 가능한 결과를 준비하기 전에 막연한 승인을 요청하지 않는다.

## 다음 작업 요청 예시

> AGENTS.md의 시작 순서에 따라 프로젝트 맥락과 현재 상태를 확인하고, 기존 지도와 감사 결과를 재사용해서 상태 문서에 지정된 다음 작업부터 진행해 주세요. 관련 계약과 검증 절만 읽고, 한 작업씩 구현·검증한 뒤 실행 이력과 현재 상태를 함께 기록하세요. 선행 조건이 준비된 작업을 이어가고, 실제 확인한 결과와 추정을 구분하며 대한문을 지나 경내를 걷는 범위를 유지하세요.

한 작업만 검토하고 싶다면 위 문장의 마지막에 “이번에는 `<작업 ID>`까지만 진행해 주세요”를 추가한다.

## 종료 시 남길 짧은 기록

현재 결과와 다음 행동은 WORK_STATUS에 갱신한다. 시도·실패·변경 이유·검증·한계는 EXECUTION_LOG의 양식에 따라 누적한다. 완료 체크는 증거가 있는 작업만 바꾸고, 범위 변경이 있으면 PROJECT_CONTEXT와 관련 계약도 맞춘다. 각 파일의 역할을 유지해 현재 상태를 여러 곳에 중복 복사하지 않는다.

```text
완료 작업 ID와 근거:
변경 파일:
검증 명령/조작과 결과:
미해결 결함 또는 미실행 검증:
다음 작업 ID, 입력 위치, 첫 행동:
실행 이력·변경된 결정/계약 링크:
```

작업 파일과 기록을 같은 커밋으로 공유해야 다른 Mac에서 이어받을 수 있다. 예정 파일을 모두 미리 생성하지 않는다. 실행 가능한 다음 작업부터 만들고, 원본·자동 생성물·수동 보정을 구분한다. 무관한 취업 자료나 상위 저장소는 수정하지 않는다.

W01 자동 GPU 판정은 12카메라 시점과 중립 정지의 준비 후 결과다. 측정 과정의 실제 이동/Shift 키 바인딩은 시험 프로세스에서만 제거하며 일반 `run`에는 그대로다. 기존 정지/관통/시간 허용치는 유지했고 초기 기동·첫 렌더링 끊김과 사람/OS 조작은 별도 검증이다. 준비 시간·pipeline count·입력 격리·최초 실패는 [W01 결과](../data/reports/daehanmun_walk.md)와 raw 기록에서 확인한다.

최근 사용자 지시(2026-10-13): “알아서 계속 만들어 당분간은너가해”. 선행 조건이 준비된 다음 작업을 구현·검증·기록하고 기존 전용 저장소에 함께 공유하는 흐름을 이어간다. 매 단계의 사람 조작 확인을 대기 조건으로 삼지 않으며, 자동 검사와 미확인 사람 조작감을 구분한다. 큰 범위 변경 직전에만 질문한다.

L01 참조·명세는 [landmark_reference](landmark_reference.md)로 완료했다. L01 종료 당시 다음은 **L02 궁궐 외형**이었다. `landmark_plan.json`/`landmark_references.json`은 수동 원천, `prepare_landmark_spec.py`로 만든 `data/processed/landmark_spec.json`은 Git 제외 로컬 연결물이다. L02는 대한문의 단일 지붕 층을 미확인 홑처마 형식으로 읽지 않고, 현재 문 개구부/기존 충돌·중화문 닫힘과 석조전 부모-부분·정관헌 선택 윤곽을 보존한다. L01에서 새 모델·실내·GPU 회귀·사람/M4·장소 인지 검증은 하지 않았다. 위 단계별 이력의 ‘다음 L01’은 당시 기록이며 현재 재개는 최신 WORK_STATUS를 따른다.


L02 궁궐6곳 외형과 보행 회귀는 [실제 결과](../data/reports/palace_landmarks.md)로 완료했다. L02 종료 당시 다음 작업은 **L03**이었으며 위 L01 종료 당시 ‘다음L02’ 문장은 이력이다. `recipes.json`과 `prepare_palace_landmarks.py`로 표시용 JSON/manifest를 재생성하고 `run_palace_landmarks.sh`로 최신 장면을 연다. 기존 충돌/경계·문/경로는 유지한다. 첫GPU 시간3항목 실패와 동일 소스/입력/허용치의 짧은/전체 재시험 통과를 함께 보존했고 초기 지연 원인은 미확정이다.

사용자의 기존 결과물 수정 질문은 [재사용 대안](ASSET_REUSE_OPTIONS.md), 메타버스/심즈 구분은 [맥락](PROJECT_CONTEXT.md)에 남겼다. 기존 자산 후보 한 개의 비교를 권고하며 아직 실제 비교/파일 이용권 확보로 주장하지 않는다. 현재 목표는 서울 탐험 기반에 생활/시뮬레이션을 확장하는 것이고 메타버스/멀티플레이를 확정하지 않았다. 핵심 반복 활동/개별 실내는 미정이다.

L03은 [실제 비교·도시 외형·회귀](../data/reports/city_landmarks.md)로 완료했다. L03 종료 당시 다음은 **L04**였다. 기존 CC0 모델을 실제 가져와 배경 빌딩1곳에 수정 사용했고 시청/도서관은 독립 단순화했다. `prepare_city_landmarks.py`/`run_city_landmarks.sh`를 사용한다. 원본 GLB·상대 PNG·CC0·취득 해시와 변환 규칙을 공유하고 정확한 SFC 복제/새 높이/새 동선으로 주장하지 않는다. L01/L02 종료 당시 다음 문장은 이력이다.


L04 [결합 화면·보행 검수](../data/reports/landmark_review.md)를 완료했고 L04 종료 당시 다음은 **N01**이었다. 일반 게임은 L03와 같고16시점 전후/눈높이와 새 국소 보행·회전만 추가 검증했다. L03 전체3.3km는 정확한 소스/원관측 해시 일치 때만 재사용했다. 돈덕전·정관헌 가림과 중화문의 약한 문 인지를 남겼으며 실제 장소 식별·사람/M4·실내 완성으로 확대하지 않는다. 회사 보안/접근과 건물 정보·엘리베이터 질문은 PROJECT_CONTEXT의 제안/미정이며 기존 N 계획을 대체하지 않는다.


N01 [경로·교차 규칙](route_rules.md)과 [정적 검증/재현](../data/reports/route_review.md)을 완료했고 N01 종료 당시 다음은 N02였다. `urban_routes.json`→`prepare_routes.py`로 로컬2모드경로를 만든다. 원문 방향/차로수와 추정 오프셋/차폭·정지 여유를 구분하며 N01 당시 초기2NPC/2차량은 미생성 제안이었다. 기존 game/지원면·플레이어경계를 바꾸지 않았다. NPC 경로2곳부터 실제 움직임을 관측하고 차량 지지/제동/점유·시야밖 반복은 N03에서 검증한다. 정적108검사와 별도폴더 재생성을 실제 controller/새Mac/M4 통과로 쓰지 않는다.


N02의 [왕복·회전·정지/재개·접촉 결과](../data/reports/pedestrians.md)를 완료했다. N02 당시 실행은 `prepare_pedestrians.py`→`run_pedestrians.sh run`이다. L03 상속 장면에 두 고정선/각1명만 추가하며 물리/표시/원천은 분리한다. 접지 중 중력 중복 적용으로 생긴 이음부 보정을 수정하고 원래 속도·step/5mm/2% 기준으로 전체 headless/GPU를 통과했다. 실패/원시자료·화면·prepared 재생성도 공유한다. N02 종료 당시 다음은 N03이었으며 차도 실제 지지/접촉부터 확인하기로 했다. NPC간 실제 조우·차량/교차·10분 이상 N04·사람/OS/M4·실내/V0는 아직 아니다. 다른 Mac에서 채팅을 추정하지 말고 최종 인수와 실행 이력의 실패/선택 이유까지 읽는다.


N03의 최신 실행은 `prepare_traffic.py`→`run_traffic.sh run`이다. N02 상속 장면에 세종대로 차량2대와 기존 W03 지원면 밖의 차량용 지지체2개만 추가한다. 차도 지지는 실제 ray/차체 낙하로 먼저 확인했으며 layer16/mask8·차량mask31 확장을 C07에 기록했다. 원본692/687과 사람/카메라 mask·보행 경계는 유지한다. 실제 이동/교차·재배치와 실패·재현은 [N03 결과](../data/reports/vehicles.md), 현재 완료와 다음 작업의 단일 기준은 WORK_STATUS를 따른다. N02 종료 당시 ‘최신/다음N03’은 이력이다.

N03에서는 횡단부2m/s·빈상태1초/FIFO·관측불명 정지와 차량OFF 중 계속 관측을 적용했다. 재배치는 실제 끝점 정지/접지와 현재 카메라6평면의 전체 차체·사람 표면30m·빈진입을 함께 만족해야 한다. 전체19case는 독립 장면 재시작/사람 시험 배치·정지 역할 물체를 명시한다. 이를 새3.3km 연속 완주나 자연스러운 NPC/차량 조우·N04로 설명하지 않는다. 현재 인수는 `python3 tools/check_vehicles_handoff.py`, 준비 실행 자료까지 대조하려면 `--prepared`다. N04는 현재 N03 장면에서 W04 필수 여정과10분 이상/각2주기/교차정지·재개3회를 실제 관측하는 것이 첫 행동이다. 새 자료 다운로드나 완료된 준비를 반복하지 않는다.

N04는 [동적 연속 검수](../data/reports/urban_motion.md)로 완료했다. 일반 게임은 기존 `sh tools/run_traffic.sh run`이며 지도/충돌/속도/2NPC2차량의 production 변경은 없다. 별도 자동입력 검수로 원문334구간/11단계와4회 양보, 지정횡단3회·실제NPC막힘/회복3회를같은26분세션에서통과했다. 최종headless396/GPU398독립·도시58/궁궐76검사,실제teleport결함/저장변조5종거부와최초실패를보존한다. 현재 인수는 `python3 tools/check_urban_motion_handoff.py --prepared`이며 새생성기를요구하지않는다. 위N03당시 ‘다음N04’는 이력이고 현재다음은 **R01**이다.

사용자는2026-10-16 최초32작업계획이끝날때까지사람승인없이자체검증하며진행하도록위임했다. 자동검수/실제화면을기록하고R01→R02→R03→R04를이어간다. R01은현재2NPC/2차량과A0/0을실제1920×1080·고정카메라로비교하며V06의12/4제안부하를실행한것처럼쓰지않는다. M4접근/센서/API가없으면미실행/null과재개조건을남기고M1결과로대신하지않는다. 직접사람조작감·현실접근/지형·실내/생활AI는현재범위를넘는다.

R01은[조건/실제수치/재현](performance_notes.md)로완료했다. A10분/B20분의p95는9.952950/9.613300ms이며현재2/2부하에서초기33.3ms제안을충족했다. GPU시간/온도는미관측이며A/B차이를actor성능인과로설명하지않는다. 다음R02는기본값유지와가벼운설정·메뉴/복원/UI의기능회귀후채택을기록한다. 기존N04 snapshot과R01원시자료는바꾸지않는다. 최신현재상태는WORK_STATUS를따르며앞선단계의‘다음’은당시이력이다.

R02의[채택/검증](../data/reports/performance_comparison.md)을완료했다. 최신개발실행은`sh tools/run_v0.sh run`이며기존traffic의상속장면에서기본/가벼운품질·저장복원·출처/메뉴를제공한다. 계약64/GPU68검사와직접3PNG검토를통과했고기하/충돌/속도/개체수는유지한다. 성능개선율은미측정이다. 다음R03은같은V0를실제release앱으로내보내고개발폴더밖ZIP복원·원본접근/네트워크차단·일반기동/설정/전체여정을검증한다.

## 최신 인수: R03 완료·R04 기기별 판정 완료

원래 계획의 첫 탐험 V0는 M1 Pro 로컬 release 앱으로 인수했다. 최신 [실행 안내](RUN_GUIDE.md)·[패키지 증거](../data/reports/package_check.md)·[첫 버전 판정](../data/reports/first_version_acceptance.md)을 읽는다. 새 자료 취득·이미 끝난 준비·3.33km 시험을 이유 없이 반복하지 않는다. 이전 절의 ‘다음R01/R02/R03’은 당시 기록이다.

최종 ZIP은64,884,999bytes/SHA `feb939b72ecd9d077b563e77aeacf0b2b8d4892dc0a00800eadc68cd65d8facb`이며 Git 제외다. 코드·작은 지도·도구·계획/실패/검수 증거는 Git으로 공유하고 앱은 별도로 옮긴다. `.tres` 변환/템플릿 `--script` 제약/최초 HUD 가림의 실패와 수정된 full04 PASS를 구분해 보존했다. 앱을 재검수하려면 원 export manifest를 바꾸지 않고 [두 Mac 안내의 마지막 절](CROSS_MAC.md)을 따른다.

M4는 접근 불가 대안의 UNRUN·실제 사양/성능null이다. 실제 final 앱/ZIP 경로 바인딩 검수는 M1에서만 수행했다. Mac 잠금으로 OS 입력/초점도 미실행이며 합성 입력 PASS와 사람 조작감을 혼동하지 않는다. 현재 원래 계획 내에서 승인을 기다리는 다음 구현은 없다. M4 접근이 생기면 같은 앱으로 미실행 항목을 재개하고, 별도 실내/생활AI·외형 개선은 새 우선순위가 정해질 때 진행한다.

새 Mac의 일반 실행은 `prepare_local_terrain.py`가 실제 지면 생성기를 호출한다. 재생성으로 달라진 준비 보고서는 Git 제외 `terrain_local_preparation.json`에 보존하고 공유된 수용 보고서는 복원한다. 실제 출력 SHA가 공유 기준과 다르면 자동 기동을 멈춰 그 Mac의 검증 없이 수용 기록을 덮어쓰지 않는다. 개발 중 원천/생성기 변경의 새 판정은 별도 작업·증거로 갱신한다.
