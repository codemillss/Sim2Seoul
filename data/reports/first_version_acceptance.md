# V0 첫 탐험 버전 인수 판정

2026-10-16 · **M1 Pro 로컬 V0의 자동 엔진·패키지 검수 PASS. R04 기기별 판정 완료, M4 Pro는 접근 불가 대안으로 UNRUN.** 원래32작업의 기능·증거·제한을 모은 인수 결과이며 모든 기기/사람 시험이 PASS라는 뜻은 아니다. [WORK_STATUS](../../docs/WORK_STATUS.md)·[실행 안내](../../docs/RUN_GUIDE.md).

고정된 최종 ZIP에서 오프라인 일반 기동·품질55검사·전체 물리398검사·도시58/궁궐76검사·package58검사와 직접13PNG 검토를 완료했다. [R03 최종 증거](package_check.md). OS입력/초점과 사람 조작감·전송 Gatekeeper·M4는 아래와 같이 미실행이며, 그 항목을 M1 합성 입력으로 대신하지 않았다.

## 원래 요구와 현재 증거

| V0의 기능 요구 | 현재 확인한 내용 | 증거와 남은 조건 |
|---|---|---|
| 실제 도로·건물 배치, 미터 축척과 출처 | D/G의 지역 원본·좌표·도형·높이 분류를 E의 실제 장면으로 전달. EPSG:32652 고정 원점, 1단위=1m와 엔진 거리/비례 확인 | [D02 원본](../../docs/evidence/D02_EXTRACT_REVIEW.md)·[D03 보완/한계](../../docs/evidence/D03_SUPPLEMENTAL_REVIEW.md)·[G01 좌표](../../docs/evidence/G01_COORDINATE_CHECK.md)·[G02 도형](../../docs/evidence/G02_GEOMETRY_REVIEW.md)·[G03 높이](height_review.md)·[E01 기동](engine_startup.md)·[E03 표시](world_import.md)·[E04 축척](scale_view/README.md). 현장 측량/실제 지형의 정확도 판정은 아님 |
| 사람 크기 캐릭터의 3인칭 걷기·달리기, 지면·벽·카메라 충돌 | P01–P04에서 1.70m 캡슐, 이동/중력/복귀, 마우스·휠, 충돌 역할과 관통 기준 확인 | [사람 크기](player_scale.md)·[이동/복귀](movement.md)·[카메라](camera.md)·[충돌](collision.md). 자동 입력 관측이며 사람 조작감과 구분 |
| 대한문을 통과해 경내 길·마당·전각 사이, 광장·시청·돌담길 탐험 | W01–W04의 R1/R2/R3 연결을 보존. N04는 같은 2NPC/2차량과 원문11단계·334구간/약3.33km를 한 세션으로 연속 검수 | [대한문](daehanmun_walk.md)·[경내](palace_walk.md)·[도심/경계](public_walk.md)·[W0 통합](walkable_milestone.md)·[N04 최종](urban_motion.md). 경내 진입과 전각 실내 진입은 다른 범위 |
| 전통 건축·현대 도시의 주요 형태와 높이감 | L01 참조에 따라 L02/L03의 대한문·중화전·석조전·시청/구청사·주변 빌딩 형태를 구현하고 L04에서 배치/축척·결합 화면을 검토 | [궁궐 외형](palace_landmarks.md)·[도시 외형](city_landmarks.md)·[L04 직접 화면/한계](landmark_review.md). 돈덕전·정관헌 가림, 중화문 문 인지 약함은 남음 |
| 허용된 경로의 보행자·차량, 정지·재시작·막힘 회복 | N01의 원천 경로/우선순위를 N02/N03의 2명/2대에 연결. N04에서 횡단 정지·재개3회와 경내 막힘·회복3회, 실제 이동/반복을 관측 | [경로](route_review.md)·[보행자](pedestrians.md)·[차량](vehicles.md)·[도시 통합](urban_motion.md). 정해진 경로의 간단한 움직임이며 생활AI/실제 교통 수요 모형은 아님 |
| 출처·추정 범위, 조작 안내·복귀·품질 선택 | D04의 사용 범위를 R02 V0 leaf에 표시. 메뉴/팝업/복귀/이동 스위치/품질 저장과 잘못된 설정 복구, 작은 화면 배치를 검증 | [출처](../../docs/ATTRIBUTION.md)·[R02 결과](performance_comparison.md)·[64/68 검사](r02/summary.json)·[R02 한글/배치](r02/views.json)·[R03 최초 HUD 수정/전후](r03/development/hud_fix_summary.json)·[최종13PNG 직접 검토](r03/final_views.json). 품질 스키마1만 저장하며 위치/생활 진행 저장은 없음 |
| M1 Pro에서 성능 측정 | R01은 실제1920×1080, A0/0 10분·B2/2 20분. B p95 9.6133ms를 근거로 R02 기본 배율1/그림자ON/시야200m 유지 | [R01 수치](performance_m1pro.json)·[측정 조건](../../docs/performance_notes.md)·[품질 채택](performance_comparison.md). low 개선율·새 HUD/실제 release 앱 성능은 미측정 |
| 편집기 없이 로컬 실행 파일 사용 | 같은 ZIP을 저장소 밖에 복원해 오프라인 일반 기동·전체 여정/NPC/차량 검수 PASS | [R03 결과](package_check.md)·[최종 원시/검산](r03/summary.json). 실제 OS 입력은 Mac 잠금으로 UNRUN |
| 같은 자료/버전으로 M4 Pro 실행 확인 | 이번 세션에서는 실행하지 못함 | **UNRUN**. 아래 같은 ZIP·기기 확인·시나리오 조건으로 재개 |

## 구조와 현실 구현의 경계

준비 단계의 Python 도구는 원본/수동 보정→미터 도형·분류→manifest가 있는 실행 번들을 만든다. Godot의 World, Actors, Presentation, InputRouter/Interface는 지도·충돌·동적 개체·카메라·메뉴 역할을 나눈다. 표시 자산을 바꿔도 원천 ID·배치·보행 연결을 따로 유지하며, R02 `v0_walk`는 동결된 교통 장면을 상속한다. [프로젝트/데이터 경계](../../docs/GAME_PROJECT.md)·[현재 구현 결정](../../docs/PROJECT_CONTEXT.md). Python·원본 GIS·지도 서버 없이 최종 앱이 실행됨은 R03의 저장소/네트워크 차단 실행으로 별도 확인했다.

지면은 임시 y=0 지원 평면이며, 높이는 원문 수치·층수 추정·임시값을 구분한다. Copernicus DSM은 참고 자료이고 보행 지면이 아니다. 게임의 확정 경계는 현장 출입 허가·현재 공사 통로·실제 단차/폭을 확정하지 않는다. 중화문·계단·잔디·사유지 등 제외 범위를 우회한 출처 있는 동선이며, 장소를 보이게 하려고 건물이나 길을 임의 배치하지 않았다.

대한문·주요 전각·석조전·시청의 형태 대비를 내부 검토했지만 모든 랜드마크의 장소 식별을 통과한 것은 아니다. **돈덕전·정관헌은 가림, 중화문은 약한 문 인지**가 남는다. 사람의 장소 인상·직접 키보드/마우스 조작감은 미검증이다. 개별 건물의 실내·방/복도·층별 엘리베이터, 생활·꾸미기·주민 AI는 미정 또는 후속이며 V0에 구현한 것으로 쓰지 않는다.

## R03 최종 앱과 실행 증거

| 확인 항목 | 최종 결과/증거 |
|---|---|
| source/입력·엔진 | base `fc348ad45c71`와 파일별 SHA 고정, runtime141입력 전후 동일. 공식 Godot4.7.2 universal2, M1/Metal 실행. [원 manifest](r03/exports/final/manifest.json) |
| 최종 파일 | `.app`192,828,113B / ZIP64,884,999B. ZIP SHA `feb939b72ecd9d077b563e77aeacf0b2b8d4892dc0a00800eadc68cd65d8facb`. 앱/PCK/실행 파일의 전체 식별값은 [최종 요약](r03/summary.json)·manifest |
| 정상 기동/실제 설정 | QA 없는 V0 기동·standard/2명2대, source/network 차단, QA dispatcher 비발동 확인. [package58검사](r03/final/package_check.json)·[release context](r03/final/runtime/full.json.package_context.json) |
| 전체 경로/개체/카메라 | 334구간/11단계, 실제1,581.386399초·94,883tick, 횡단3회/NPC막힘회복3회·전tick접지·pose/복귀0. [398검사](r03/final/motion_check.json) |
| 조작/설정/종료의 관측 경계 | 엔진 합성 입력과 UI signal·파일 저장/새 장면 복원을 검사. 일반 process 정상 종료 확인. OS 입력/초점·메뉴 종료 버튼 OS 클릭·OS process 품질 재기동·사람 조작감은 미실행. [이유](r03/os_input_status.json) |
| 독립 실행/출처/서명 | PCK와 loose 고지, 실제 FileAccess/화면 출처, 오프라인/원본 차단 실행 및 strict ad-hoc 서명 PASS. Developer ID/공증·전송 Gatekeeper·공개 배포는 미실행/미승인 |
| raw/실패/화면 보존 | [원문 바이트 보존 색인](r03/final_retention.json)·[압축 raw](r03/final/runtime/full.json.gz)·[독립 재검산](r03/retained_motion_recheck.json)·[13PNG 직접 검토](r03/final_views.json). full01/02 실패·full03 중단과 최종 수정 앱 full04를 [R03 기록](package_check.md)에서 구분 |

## R04 M4 실행 — UNRUN 대안과 재개 조건

현재 도구로 M4의 원격 명령을 실행할 수 없고, 해당 기기가 M4라고 확인된 SSH alias도 없다. 알려진 호스트 이름만으로 칩/RAM/OS를 추정하거나 M1 성공을 M4 성공으로 바꾸지 않는다. SSD1TB는 RAM 확인이 아니다. 이 상태는 시험 실패가 아닌 **UNRUN**이며 [두 Mac 안내](../../docs/CROSS_MAC.md)와 같은 파일의 인수 자료를 넘기는 대안을 사용한다.

1. R03 최종 ZIP과 SHA가 확정되고, 실제 M4에서 실행할 수 있는 접속 수단이나 로컬 실행 환경이 확보되면 재개한다. **같은 ZIP의 SHA를 먼저 대조**하고, 별도 재빌드/다른 설정 결과를 같은 앱의 재현으로 합치지 않는다.
2. 실제 칩 모델·RAM·OS·GPU/렌더러·출력 크기·전원/품질 설정을 기록한다. 기기 이름이나 SSD 용량을 하드웨어 확인의 대체물로 쓰지 않는다.
3. 같은 앱의 기본 품질/2명2대에서 기동, 대한문 양방향·경내/중화전 앞마당·석조전 계단 아래·대한문 복귀(R1), 광장/시청(R2), 돌담길 왕복(R3)을 정해진 순서로 확인한다. 문/벽/근접 카메라·보행자/차량 정지·재개/막힘 회복, 메뉴·복귀·품질 저장/재시작·출처·종료를 확인한다. 확정된 R03 내장 QA와 기존 package checker의 동일 버전을 사용하며 CROSS_MAC의 마지막 절을 따른다.
4. 자동 입력/OS 입력/사람 조작을 구분해 기기별 PASS·FAIL·UNRUN과 raw/check/log/화면을 별도 보존한다. 성능을 비교할 때는 R01의 실제1920×1080·기본 품질·같은2/2·카메라 경로·준비/측정 시간을 고정하고 새 기기 측정값을 따로 남긴다.

[M4 기기별 기록](performance_m4pro.json)에 실제 사양/성능을 null, 시나리오를 UNRUN으로 보존했다. [경로 재결합 도구의29검사](r04/manifest_relocation_checks.json)와 [실제 최종 ZIP/앱·113source 바인딩](r04/final_path_binding/source_check.json)은 M1에서만 확인했으며 M4 실행 증거가 아니다. 원 manifest를 고치지 않고 다섯 경로만 바꾸는 재개 절차는 [CROSS_MAC](../../docs/CROSS_MAC.md)의 마지막 절을 따른다.

판정은 **M1의 개인용 첫 탐험 프로토타입 인수, M4/OS 입력/사람 조작감/전송 Gatekeeper 미실행**이다. R04는 원래 대안에 따라 기기별 판정을 완료했으며 두 기기 실행 성공이나 모든32작업의 모든 시험 PASS로 표현하지 않는다. 원래 계획 밖의 실내·생활 요소와 남은 외형 개선은 이후 우선순위를 정할 확장 작업이다.
