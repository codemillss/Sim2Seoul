# Sim2Seoul 문서 안내

[프로젝트 소개와 플레이 화면](../README.md)에서 시작하고, 필요한 내용에 따라 아래 문서를 선택하세요. 현재 구현의 기준은 WORK_STATUS이며, 과거 실행 기록은 당시 소스의 이력입니다.

| 알고 싶은 내용 | 읽을 문서 |
|---|---|
| 무엇을 만들었고 어떤 문제를 해결했나 | [프로젝트 소개](../README.md) · [기술적 문제 해결](ENGINEERING.md) |
| 설치하고 직접 실행하기 | [실행 안내](RUN_GUIDE.md) · [새 Mac 준비](CROSS_MAC.md) · [환경](environment.md) |
| 현재 완료한 기능과 남은 작업 | [현재 작업 상태](WORK_STATUS.md) · [상세 작업 계획](IMPLEMENTATION_TASKS.md) |
| 왜 이 장소·범위·표현을 골랐나 | [프로젝트 맥락과 결정](PROJECT_CONTEXT.md) · [전체 계획](MASTER_PLAN.md) |
| 좌표·충돌·입력·지형의 구현 규칙 | [기술 계약](TECHNICAL_CONTRACTS.md) · [지형 통합](TERRAIN_INTEGRATION.md) |
| 무엇을 어떻게 검증했나 | [검증 계획](VALIDATION_PLAN.md) · [2026-10-20 실행 집계](../data/reports/street_detail/20261020/summary.json) |
| 실패·수정·개발 순서 | [실행 이력](EXECUTION_LOG.md) · [원시 증거 폴더](../data/reports/) |
| 데이터와 모델의 출처·이용 조건 | [자료 출처](DATA_SOURCES.md) · [자료·자산 고지](ATTRIBUTION.md) |
| 다른 기기에서 개발 이어가기 | [에이전트 시작 지침](../AGENTS.md) · [인수 안내](SOL_HANDOFF.md) |

## 현재 개발 진입점

- 실행: `sh tools/run_exploration.sh run`
- 장면: `game/scenes/world/explore_walk.tscn`
- 탐험 기능 조립: `game/scripts/explore_walk.gd`
- GIS 준비·생성: `tools/prepare_*.py`
- 엔진 상호작용 검사: `tests/game/`

기능 동작 검증과 소개 문서 검수는 별도로 기록합니다. [2026-10-21 GitHub 소개 정리 기록](../data/reports/project_showcase/20261021/summary.json)은 문서·화면·연결·저장소 소개를 확인한 결과이며 게임을 다시 실행한 수용 검사가 아닙니다.
