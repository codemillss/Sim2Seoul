# R03 개인용 macOS 앱 검수

2026-10-16 · **M1 Pro 로컬 release 앱 PASS**. [기계 판정 요약](r03/summary.json)·[실행 안내](../../docs/RUN_GUIDE.md). 실제 OS 입력/사람 조작감·M4·전송 후 Gatekeeper는 UNRUN이다.

## 동일 앱과 입력

- 빌드: `builds/macos/v0.1.0-fc348ad45c71-20261015T182258776232Z`. `.app` 192,828,113 bytes, ZIP 64,884,999 bytes. 앱/ZIP/템플릿은 Git 제외이며 별도로 옮긴다.
- ZIP SHA-256: `feb939b72ecd9d077b563e77aeacf0b2b8d4892dc0a00800eadc68cd65d8facb`.
- 앱 파일/권한/심볼릭 링크 tree SHA-256: `326fedaf76a80b1889dc2e950e73109979f1464b4e659493ac7ccda95b11ceb7`.
- PCK 21,659,956 bytes, SHA-256 `774b812789a16f1d4da6f97b417cba8bc377540a34e1fd86ec8ddf49611fd57a`.
- source base `fc348ad45c71177203c733bc36f42d56061c3358` 이후 R03 신규 파일은 manifest의 정확한 파일 SHA로 고정했다. export 입력113개, 실제 검수의 observer/geometry를 포함한141개가 전후 동일하다. 최종 코드와 이 증거를 같은 완료 커밋으로 공유한다.
- Godot4.7.2 공식 macOS universal2(arm64/x86_64) 템플릿·Forward+/Metal. 실제 실행은 M1/arm64이며 Intel 실행을 확인한 것은 아니다.

[원 export manifest](r03/exports/final/manifest.json)는 정적 제작 시점의 불변 기록이다. 그 안의 `runtime_tested=false`/ZIP `roundtrip_verified=false`를 수정하지 않았다. 실제 ZIP 복원·앱 실행 성공은 [별도 최종 package_check](r03/final/package_check.json)가 증명한다. [공식 템플릿 취득](r03/exports/template_acquisition.json)과 같은 폴더의 import/export/서명 로그를 보존했다.

## 실제 실행과 판정

| 검사 | 결과 | 증거 |
|---|---|---|
| ZIP을 저장소 밖에 추출·파일/권한/링크·PCK·서명, 일반 기동, 원본 접근 차단, 사후 보존 | 58/58 PASS | [package_check](r03/final/package_check.json) |
| 두 품질·Esc/메뉴·복귀/스위치·출처·960/1152·설정 새 장면 복원/손상 처리 | 55/55 PASS, 짧은 검수 | [quality](r03/final/quality_check.json) |
| 같은 release 앱의 전체 N04 물리/동선/개체/카메라 | 398/398 PASS | [motion](r03/final/motion_check.json) |
| 도시 / 궁궐의 실제 표시 기하 | 58/58 / 76/76 PASS | [city](r03/final/city_check.json)·[palace](r03/final/palace_check.json) |
| 압축 보존 raw를 다시 읽는 독립 물리 재검산 | 398/398 PASS | [saved recheck](r03/retained_motion_recheck.json) |
| 최종 앱 PNG13장 직접 열기 | 완료 | [직접 화면 검토](r03/final_views.json) |

일반 실행은 QA 플래그 없이 V0 READY/기본 품질/2NPC/2차량을 확인하고 정상 종료했다. 내보내기 사본의 dispatcher는 두 명시적 QA 플래그가 함께 있을 때만 허용된 내장 검수기로 전환한다. 일반 플레이에 자동 보행을 넣지 않았다. 품질 검수는 파일 저장 뒤 새 장면으로 다시 읽은 결과이며, OS에서 앱을 닫고 다시 여는 시험과 구분한다. 종료 버튼의 실제 OS 클릭도 미실행이다.

전체 동적 구간은 **94,883tick / 물리1,581.383333초 / 실제1,581.386399초**, 렌더94,882frame이다. 원문11단계·334구간/계획3,327.048107m 여정은57,176tick / 실제952.923186초이며 체크포인트 도착21회를 확인했다. 실제 횡단 점유→정지→비움→재개3회와 별도 경내 NPC 막힘→비움→회복3회를 같은 개체/시계에서 검산했다. NPC 왕복19/12회·차량의 guard가 있는 반복31/24회, 표본16,169개와 전tick 요약을 보존했다.

전tick player94,883/NPC189,766/차량189,766 접지, player영역이탈0·pose호출0·복귀0·차량/사람접촉0·카메라관통/overlap/near0이다. 최대 player침투2.178mm, 차량 step0.083336234m/NPC0.020007415m이며 기존5mm/step/실제시계2% 기준을 유지했다. 메뉴/낙하/경계 복귀의 의도적 주입은 이 연속 구간 뒤 별도 시험이다.

## 독립 실행과 출처

앱/ZIP을 저장소 밖으로 복원한 뒤 네트워크와 저장소 읽기/쓰기를 차단했다. 외부 파일 읽기 성공과 저장소 파일 읽기 거부를 실제 대조 시험으로 확인했다. 앱은 편집기·Python·전국 지도·지도 서버 없이 시작하고 경로/NPC/차량을 실행했다. Python은 앱 밖에서 증거를 검산한 도구다.

[실제 release 문맥](r03/final/runtime/full.json.package_context.json)은 editor/debug=false, V0 main/실제 장면, 실행 파일 SHA, standard 배율1/그림자ON/far200m/2명2대와 PCK 내 ICU·두 품질·출처/라이선스5개의 FileAccess bytes/SHA를 기록한다. loose license와 최종 화면의 출처도 확인했다. 로컬 ad-hoc 서명은 strict 검사를 통과했으며 Developer ID 서명·공증은 하지 않았다. 대중 공개 배포와 다른 Mac의 전송/격리 최초 실행을 승인하거나 검증한 결과가 아니다.

## 실패·수정·재시험

| 시도 | 실제 문제와 수정 | 보존 |
|---|---|---|
| full01 | `.tres`가 binary resource로 바뀌어 기존 원문 SHA 검사가 거부. 임시 export의 텍스트 resource 변환만 끄고 loader 유지 | [첫 실패](r03/development/full01/package_check.json)·[export](r03/exports/attempt01/manifest.json) |
| full02 | 공식 템플릿은 경로 override 비활성이라 `--script` QA가 시작되지 않아 timeout. 고정된 내장 dispatcher와 공식 API 확인으로 대체 | [두 번째 실패](r03/development/full02/package_check.json)·[API 검수](r03/development/dispatch_api01/api_check.json) |
| full03 | 실제 최초 화면의 HUD가1471px로 world/player를 덮음. 조기 중단·원본 보존 후 no-resize0 재현, minimum 높이119px로 조정 | [중단](r03/development/full03/interruption.json)·[수정 전후](r03/development/hud_fix_summary.json) |
| full04 | 수정된 새 앱에서 일반 기동·품질·전체 여정과13PNG 직접 검토 통과 | [최종 요약](r03/summary.json) |

이전 R02의 resize후 화면만으로 최초 시작을 검증할 수 없었던 점을 정정했다. 수정은 V0 HUD/검수에 한정하며 기존 좌표·지도·충돌·속도·개체수·판정 허용치를 바꾸지 않았다.

## 원시 자료와 재현

[보존 색인](r03/final_retention.json)에 원래 경로·보존 경로·bytes/SHA를 기록했다. 원본 raw200,934,421 bytes는 [full.json.gz](r03/final/runtime/full.json.gz)로만 인코딩했고, 해제 SHA `f46fb27f025cf1b08da11c3d679e145a9ccd618ddcb6302d7e0eb7b87ce00f92`와 원문 bytes가 일치한다. 원래 cache/raw는 변경하지 않았다. 최종 로그·context·13PNG와 기타 JSON은 동일 바이트다. 다음은 생성 자료를 준비한 사본에서 보존 raw를 다시 검산하는 명령이다. 출력에는 새 경로를 사용한다.

```sh
.venv-data/bin/python -B tools/check_urban_motion_evidence.py --record data/reports/r03/final/runtime/full.json.gz --bundle game/data/generated/traffic.json --itinerary game/data/generated/walkable_itinerary.json --public game/data/generated/public_walk.json --world game/resources/world_geometry/world.json --w01 game/data/generated/daehanmun.json --output data/cache/r03_replay/motion_check.json
```

실제 앱을 다시 검수하는 명령과 다른 clone의 절대경로 재결합은 [CROSS_MAC](../../docs/CROSS_MAC.md)의 마지막 절을 따른다. 원 manifest를 수정하거나 과거 PASS 파일을 덮어쓰지 않는다.

## 남은 범위

[OS입력 UNRUN](r03/os_input_status.json): CUA의 실제 읽기 시도에서 Mac 잠금으로 접근이 거부됐고 입력은0회다. 엔진 합성 입력을 키보드/마우스·초점 전달이나 사람 조작감으로 바꾸지 않았다. [M4 UNRUN](performance_m4pro.json)과 전송 Gatekeeper도 별도다. R01 1080p/20분 측정은 이전 native Standard 실행의 성능이며, 이 release 앱의 성능 측정으로 쓰지 않는다. y0 지면/추정 높이·문 폭, 현실 위치/통행, L04의 약한3랜드마크와 실내/생활AI의 범위는 [첫 버전 판정](first_version_acceptance.md)에 남겼다.
