# EXP39 Web 성능·전송 수정·공동 도시 준비 · 2026-10-25

최종 릴리스는 **performance01_build04_delivery01**, 게임 runtime은 **performance01_build04**다. [최종 게시](delivery01_deployment.json)는 succeeded, [실제 운영 검사](deployed_asset_check.json)는 **212/212조각·manifest/loader·전체 WASM/PCK SHA PASS**다. 이전 두 전송 실패와 후속 FPS 저하를 보존한다. 게임은 단일 플레이이며 서버 원형은 미연결·미호스팅이다. [현재 상태](../../../../../docs/WORK_STATUS.md)를 따른다.

## 저장량과 실제 PCK

Web에서 raw GLB15개126,659,912B 중복을 제외하고 실제 engine용 scene15개·texture49개·참조를 보존했다. Web 원본 출처는 명시적 **빌드 attestation**이며 제외한 raw를 실행 중 직접 SHA로 읽었다고 하지 않는다. native 원본/직접 SHA 경로는 유지한다.

| 버전 | PCK bytes | 압축 전송 bytes, WASM 포함 | 조각 |
|---|---:|---:|---:|
| 기존 recovery01 | 307,439,668 | 141,196,835 | 332 |
| 중간 build01 | 180,837,780 | 94,778,532 | 211 |
| runtime build04 최초 전송 | 180,846,148 | 94,781,204 | 211 |
| 최종 delivery01 | 180,846,148 | 94,781,218 | 212 |

최종 전송은 recovery01 대비 **32.8730% 감소**다. WASM39,514,754B는 같다. [build04 실제 빌드](../performance01_build04/build.json)는 import/export/repack/PCK 읽기 각 exit0·ERROR0, [PCK 판정](../performance01_build04/pack_integrity.json)은 raw202파일·scene15/texture49·한글 폰트 PASS다. [기존 imported64항목 동등성](imported_export_equivalence.json), [최초 저장량 감사](payload_audit.json), [provenance 부정 입력 검사](provenance_generator_negative_check.json)는 각 실행 범위로 구분한다.

## 실제 로컬 시작과 cache

| 버전/관찰 | 조각 cache/network | EXPLORATION_READY | 원문 |
|---|---|---:|---|
| build01 cold | cache0/211, network94,778,532B | 실제 도시 준비 확인 | [cold](cold_runtime_dom.txt) |
| build01 warm | cache211/211, 조각 network0B | 16.880초 | [warm01](warm_build01_runtime_dom.txt) |
| build02 update | cache177/211, network34조각20,979,605B | 16.581초 | [update02](build02_update_runtime_dom.txt) |
| build02 warm | cache211/211, 조각 network0B | 16.680초 | [warm02](build02_warm_runtime_dom.txt) |
| build04 update | cache68/211, network143조각53,458,812B | 17.028초 | [update04](build04_runtime_dom.txt) |
| build04 warm | cache211/211, 조각 network0B | 16.599초 | [warm04](build04_warm_runtime_dom.txt) |
| 최종 delivery01 | cache210/212, network2조각1,043,828B | 16.505초 | [최종 실행](delivery01_runtime_dom.txt) |

[최종 실제 도시·한국어 HUD](delivery01_city.jpg)를 보존했다.0B는 게임 조각의 네트워크 전송이며 HTML/JS 등 모든 요청0B나 즉시 부팅을 뜻하지 않는다. loopback 관찰이고 모든 기기/운영 지역의 속도로 일반화하지 않는다. cache 저장 차단·용량 제한·정리 시 일반 전송을 시도한다. [실제 loader22검사](loader_cache_tests_final.log)는 Cache API 실패15하위조건과 pointer-lock 선택 기능 실패/다른 runtime 오류 구분을 포함한다. [이전20검사 결합](loader_cache_tests.json)은 당시 소스 SHA의 이력이다.

## 프레임 향상과 남은 저하

fast profile은 far350m/detail180m·3D scale0.75·MSAA0·그림자 off·**physics30Hz**·외벽80m cell이다. 초기 build01은 비정지 약5~18FPS라 미수용했다. [일시정지 진단](build01_pause_diagnostic.txt)·[화면](build01_pause_diagnostic.jpg)은 정지 중 약90FPS 전후와 재개 저하를 기록했다. 전환5초 창을 플레이 성능으로 쓰지 않았고 GPU 병목 부재/단일 원인을 단정하지 않았다.

이후 인물 visual LOD·같은 XZ/route endpoint 재사용·선택 내부 이웃/반경 재사용을 구현했다. [LOD25조건](web_human_visual_lod_check.json), [외벽45조건](web_profile_geometry_check.json), [이웃 재사용128조건](choose_neighbor_reuse_check.json)은 제한된 fixture 판정으로 실제 GPU/인체 미술/도시 FPS를 대신하지 않는다.

| runtime04 비정지 표본 | 범위 FPS | 중앙값 | 범위의 의미 |
|---|---:|---:|---|
| 실제 조작 표본2~7, 6개 | 16.1~32.0 | 30.25 | 드래그 중16.1 저점 포함 |
| 후속 warm 표본2~19, 18개 | 8.2~33.9 | 26.15 | 후반 저하 포함 |

[실측 집계와 원문 SHA](measurements.json)를 따른다. 최초 부팅/일시정지 표본은 위 플레이 집계에 넣지 않는다. 구도·입력이 완전히 통제된 비교가 아니며 **전구역60FPS·모든 기기·장시간 부드러운 플레이를 보장하지 않는다**. delivery01은 같은 game PCK이므로 전송 변경을 새 FPS 개선처럼 다시 합산하지 않는다.

실제 왼쪽 드래그 시야·W 보행·Shift+W 이동·Esc 메뉴·신/구 원형 표시·Esc 도시 복귀를 확인했다. [드래그/보행](build04_drag_walk.jpg)·[메뉴](build04_menu.jpg)·[새 원형](build04_gallery_new.jpg)·[이전 원형](build04_gallery_previous.jpg)을 보존한다. IAB는 자유 마우스 잠금을 거절했으므로 캡처 성공은 수용하지 않고 왼쪽 버튼을 누른 채 드래그하는 대안을 확인했다.

## 입력·빌드 실패와 수정

[build02 실패 원문](build02_pointerlock_failure_dom.txt)·[화면](build02_pointerlock_failure.jpg)은 Chromium requestPointerLock Promise 거절이 전체 fatal overlay로 번진 실제 이력이다. canvas API 경계에서 이 선택 기능 거절만 경고로 처리하고 관계없는 runtime rejection은 계속 중단하도록 고쳤다. 드래그 대안 build03은 타입 추론 Parse Error가 [실제 import](../performance01_build03/import.log)에 나와 엄격 검사가 거절했다. 명시적 bool 수정 뒤 build04의4단계 검사와 실제 조작을 통과했다. 숫자 PASS를 모든 브라우저 입력 성공으로 확대하지 않는다.

## 운영 전송 실패·단일 조각 수정·최종 게시

211조각의 [이전 게시 응답](deployment.json)은2026-10-25T11:07:07Z succeeded/Site 소스 `cd424763e8dc27ee9e20844bc0a707deedcb5046`다. 그러나 [운영 검사1](deployed_asset_check_attempt01.json)·[검사2](deployed_asset_check_attempt02.json)는 manifest/loader 일치·WASM38개 뒤 같은 PCK0에서 읽기 시간 초과로 실패했다(64.699/65.346초). [probe](production_probe.json)는 CSS/WASM/PCK1/마지막 PCK200, PCK0만15.026초 시간 초과였다. 빈 worker 오류 이벤트로 실패를 부정하지 않고 파일 크기·storage/edge 근본 원인이나 서버 수용량을 단정하지 않았다.

[실제 단일 조각 재분할](delivery_rechunk.json)은 PCK0만524,288B 두 raw 조각으로 바꾸고 전체 WASM/PCK SHA·나머지 압축 파일 바이트를 보존했다. **211→212조각·전송14B 증가·총94,781,218B**, `webRelease=performance01_build04_delivery01`이다. [utility](../../../../../tools/rechunk_web_asset.py)의 [최종 synthetic6검사](rechunk_asset_tests.log)는 단일 치환·바이트/전체 SHA 보존·잘못된 입력 거부·실패 처리를 검사한다.

[최종 Sites 게시](delivery01_deployment.json)는2026-10-25T11:21:30Z succeeded/Site 소스 `c67bf053417cf836106e99e900858c0cef0eaff1`다. [실제 운영212개 검사](deployed_asset_check.json)는 **모든 조각 첫 시도·크기/개별 SHA·전체 WASM/PCK SHA·manifest/loader 일치 PASS**,31.938초다. 소유자 전용 범위는 유지했다. 이는 한 차례 전체 HTTP 수신 판정이며 인증 후 운영 지속 플레이·음향 청취·저장 재접속·서버 용량/수용 인원은 별도다.

재현은 **분할 전211조각 Site 소스 `cd424763e8dc27ee9e20844bc0a707deedcb5046`를 별도 작업 복사본 `data/cache/sites/delivery-reproduction`에 준비**하고 새 보고서 경로로 실행한다. 이미212개인 현재 Site에는 원래 PCK0가 없으므로 같은 명령을 반복하지 않는다.

```sh
python3 tools/rechunk_web_asset.py \
  --site data/cache/sites/delivery-reproduction \
  --chunk chunks/pck-1m-000-da2a16e8df832836.gz \
  --part-bytes 524288 \
  --release performance01_build04_delivery01 \
  --report data/reports/web_sites/20261025/performance01/delivery_rechunk_reproduction.json
python3 -m unittest discover -s tests/web -p test_rechunk_web_asset.py
```

## 공동 도시: 로컬 서버 원형만 완료

사용자는 여러 사람이 같은 도시에서 만나 플레이하는 방향을 확정했다. [서버 원형 설명](../../../../../tools/web/multiplayer/README.md)과 [최종14검사](shared_room_tests_final.log)는 로컬 HTTP 두 클라이언트+SQLite의 방 생성/참가·승인 위치 공유를 확인한다. yaw ±π의4자리 snapshot 반올림이 재동기화400이 되는 결함을 수정하고 경계/인접 방향 왕복 검사를 추가했다. [초기13검사](shared_room_tests.log)는 당시 원문이며 [최종 suite sandbox 시도](shared_room_tests_final_sandbox_attempt.log)의13PASS/1listen EPERM와 최종14/14·exit0를 구분한다.

**현재 Godot 상대 표시·실제 서버 호스팅·운영 인증은 미구현/미검증**이다.8명은 입장 정책이고2Hz polling은 최종 부드러운 동기화가 아니다. 정적 Sites manifest+D1만으로 호스팅되지 않는다. 지원 배포 경로와 서로 다른 허용 계정 두 개의 실제 상대 표시/동시 이동·퇴장/재접속·RTT/snapshot 나이/10분 플레이가 필요하다. NPC/차량/전투/경제 공유는 별도 서버 소유권 과제다.

다음은 **NPC 물리 계산 부담과 지속 프레임 측정**, **지원되는 실시간 서버 배포·두 계정 Godot 연결**이다. 전송/국소 향상 검증을 FPS 저하 완전 해결이나 멀티플레이 활성화로 보고하지 않는다.
