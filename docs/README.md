# Sim2Seoul 문서 안내

## EXP37 — 현재 얼굴·관절 검토 경로

**현재 기술 검증:** final01 headless **85/85**, native **141/141**, 원본 **44 PNG(전체32·확대12)**이며 두 실행 모두 actual exit0·ERROR0·capture 오류0·source 변경0이다. [headless 원문](../data/reports/resident_face_joints/20261025/face_joints_headless_final01.json)·[native 원문](../data/reports/resident_face_joints/20261025/face_joints_native_final01.json)·[44장 직접 열람 peer 검토](../data/reports/resident_face_joints/20261025/visual_review_peer.json)를 구분한다. [root의 일반 OS 기록](../data/reports/resident_face_joints/20261025/normal_launch.json)은 실제 JPEG11장·ERROR0 로그2개·설정4파일 동일을 보존했다. 메뉴/확대/신구/자세·거리 복귀/재진입을 확인했으며, peer는 이 저장 기록을 읽기 검토했다. 복귀 도구는16.698초에 시간초과였지만 다음 실제 화면에서 거리 복귀를 확인했다. 로딩 성능 수용은 포함하지 않는다. 실사 미술·연속 동작 수용은 false다.

[현재 작업 상태](WORK_STATUS.md) → [원형 제작과 한계](CHARACTER_IDENTITIES.md) → [전체/얼굴/어깨/골반 사용법](RUN_GUIDE.md) → [이번 원본·보고서 폴더](../data/reports/resident_face_joints/20261025/) 순으로 확인합니다. 현재 v03의 엔진·native 검증과 root 일반 OS 기록의 peer 결합을 마쳤습니다. 같은22본/네 자세의 새 원형과 동결 EXP36 v03을 같은 조건에서 비교하며, 확대에서는 관심 부위와 전체 프레임의 판정을 구분합니다.

실사 인체·매력·연속 보행을 수용하거나 기존 플레이어/NPC를 교체한 단계가 아닙니다. 저장 증거의 현재 경로는 `tools/check_resident_face_joints_handoff.py`이며, 아래 목록의 EXP36 이하 집계는 각 당시 소스의 이력으로 보존합니다.

[프로젝트 소개와 플레이 화면](../README.md)에서 시작하고, 필요한 내용에 따라 아래 문서를 선택하세요. 현재 구현의 기준은 WORK_STATUS이며, 과거 실행 기록은 당시 소스의 이력입니다.

| 알고 싶은 내용 | 읽을 문서 |
|---|---|
| 무엇을 만들었고 어떤 문제를 해결했나 | [프로젝트 소개](../README.md) · [기술적 문제 해결](ENGINEERING.md) |
| 설치하고 직접 실행하기 | [실행 안내](RUN_GUIDE.md) · [새 Mac 준비](CROSS_MAC.md) · [환경](environment.md) |
| 현재 완료한 기능과 남은 작업 | [현재 작업 상태](WORK_STATUS.md) · [상세 작업 계획](IMPLEMENTATION_TASKS.md) |
| 왜 이 장소·범위·표현을 골랐나 | [프로젝트 맥락과 결정](PROJECT_CONTEXT.md) · [전체 계획](MASTER_PLAN.md) |
| GTA·The Sims에서 무엇을 참고하고 직접 만들 것인가 | [참조·RE 적용 범위와 자산 도입 기준](REFERENCE_DIRECTION.md) |
| 무채색 인체 원형·큰 면/손발·이전 원형 비교 | [제작과 한계](CHARACTER_IDENTITIES.md) · [EXP36 현재 집계](../data/reports/resident_form_refinement/20261025/summary.json) |
| 이전 남녀 얼굴·방향별 확인 | [캐릭터 제작·검토](CHARACTER_IDENTITIES.md) · [EXP34 실행 집계](../data/reports/character_identity/20261024/summary.json) |
| 직접 만든 캐릭터·주먹·실제60초 경찰 출동 | [자체 원본과 사건 대응](AUTHORED_CHARACTER_COMBAT.md) · [EXP33 실행 집계](../data/reports/authored_character_combat/20261024/summary.json) |
| 좌표·충돌·입력·지형의 구현 규칙 | [기술 계약](TECHNICAL_CONTRACTS.md) · [지형 통합](TERRAIN_INTEGRATION.md) |
| 무엇을 어떻게 검증했나 | [검증 계획](VALIDATION_PLAN.md) · [현재 실행 집계](../data/reports/resident_form_refinement/20261025/summary.json) |
| 실패·수정·개발 순서 | [실행 이력](EXECUTION_LOG.md) · [원시 증거 폴더](../data/reports/) |
| 데이터와 모델의 출처·이용 조건 | [자료 출처](DATA_SOURCES.md) · [자료·자산 고지](ATTRIBUTION.md) |
| 다른 기기에서 개발 이어가기 | [에이전트 시작 지침](../AGENTS.md) · [인수 안내](SOL_HANDOFF.md) |

## 현재 개발 진입점

- 실행: `sh tools/run_exploration.sh run`
- 장면: `game/scenes/world/explore_walk.tscn`
- 탐험 기능 조립: `game/scripts/explore_walk.gd`
- 이동 정책·교통: `transport_motion_policy.gd`, `city_bus_service.gd`, `city_subway_service.gd`, `city_helicopter_rope.gd`
- 자동차 탈취·킥보드 호출: `traffic_car_takeover.gd`, `city_scooter_service.gd`
- 경찰·119·비/화재: `city_public_safety.gd`, `city_weather_emergency.gd`
- 대형 병원/청사·치수 비교: `city_hospital.gd`, `city_police_headquarters.gd`, `fire_station_facility.gd`, `city_metric_overlay.gd`, `civic_facility_guidance.gd`
- 인체/자연스러운 동작·차량 음향: `player/exploration_avatar.gd`, `player/free_roam_player.gd`, `city_vehicle_audio.gd`
- 자체 인물 원본: `tools/authored_character/build_seoul_resident.py`, `game/assets/original/seoul_resident/`
- 주먹·전신 자세/실제 피격: `player/human_combat_poses.gd`, `actor_hit_reaction.gd`
- 층간·지하 연결: `interior_escalator.gd`, `game_underground_connections.gd`, `building_interior_space.gd`
- GIS 준비·생성: `tools/prepare_*.py`
- 엔진 상호작용 검사: `tests/game/`

기능 동작 검증과 소개 문서 검수는 별도로 기록합니다. [2026-10-21 GitHub 소개 정리 기록](../data/reports/project_showcase/20261021/summary.json)은 당시 문서·화면·연결·저장소 소개를 확인한 결과입니다. [EXP24 생활 기능 집계](../data/reports/city_life/20261021/summary.json)도 당시 소스의 이력입니다. 이전 [EXP25 교통](../data/reports/urban_transit/20261021/summary.json)·[EXP26 분산 대여](../data/reports/mobility_distribution/20261022/summary.json)와 함께 보존하며, 변경된 EXP29의 실행 판정을 대신하지 않습니다.
