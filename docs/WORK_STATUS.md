# 실제 작업 상태와 다음 행동

갱신: 2026-10-12 · 이번 실행: **D02 지역 추출 검토·보완 완료** · 게임 구현은 아직 시작하지 않음

이 파일이 진행 상태의 단일 기준이다. IMPLEMENTATION_TASKS의 완료 체크는 아래 증거와 연결하며, 이미 끝난 준비를 재사용한다.

## 완료한 일

| 작업 | 실제 결과 | 증거 |
|---|---|---|
| 대체 경로 다운로드 | Geofabrik 한국 PBF 288,878,500 bytes 수신, 공급자 MD5 일치 | [source_manifest.json](../data/reports/source_manifest.json) |
| 지역 원본 추출 | 현재 v2 소구역 188,346 bytes, 누락 보행 복합 면 18개 보완. 이전 파일 보존 | [extract_manifest.json](../data/reports/extract_manifest.json) |
| 기본 자료 검사 | 미해결 참조 0, 미리보기 도형 비유효 0, 변환 예외 0 | [osm_audit.json](../data/reports/osm_audit.json) |
| 좌표 변환 준비 검사 | 왕복 오차 약 7.11e-15도. 대각 거리 차이 약 0.00065% | 같은 감사 보고서. 전체 G01 검증 완료는 아님 |
| 랜드마크 태그 확인 | 대한문·중화전·석조전·돈덕전·서울시청·서울도서관·서울광장 이름과 ID 확인 | [named_features.json](../data/reports/named_features.json) |
| 로컬 준비 환경 | Python 3.14 가상환경, osmium 4.3.1 / pyproj 3.8.0 / shapely 2.2.0 | [requirements-data.txt](../requirements-data.txt) |
| 상세 계획 | 8단계 32작업, 공간 계약, 검증, Sol 인수 안내 | [MASTER_PLAN.md](MASTER_PLAN.md) |
| 문서·환경 검수 | 로컬 링크, JSON, 32개 작업 필수 필드, 의존성 패키지 검사 통과. 계획 선행 의존성 검토 후 시험 장면 순서 수정 | [preparation_checks.json](../data/reports/preparation_checks.json) |
| D01 자료 현황 인수 | 파일 6개·후보 6개·조회 실패 2건 분리. 원본/지역 파일 해시·크기 등 17개 대조 통과, 새 다운로드 0건 | [d01_verification.json](../data/reports/d01_verification.json) |
| D02 지역 추출 검토 | 경계 교차 웨이 211개·주요 관계·국가 원본 교차/포함 면 검사. 보완 후 13개 검사 통과 | [D02 검토 결과](evidence/D02_EXTRACT_REVIEW.md) |
| Git 공유 준비 | 서울 전용 독립 저장소, 작은 지역 지도 두 파일 포함. 국가 원본 없는 새 복제본에서 환경 설치·지역 감사·미리보기 생성 통과 | [git_portability_check.json](../data/reports/git_portability_check.json) |

OSM 기준 시각은 **2026-10-09T20:21:04Z**이다. 모든 객체가 그날 측량/갱신됐다는 뜻은 아니다.

## 이번 실제 데이터에서 확인한 점

미리보기 도형 수(조사 bbox와 교차한 도형 기준, 현실 객체의 유일 개수 아님):

| 분류 | 수량 | 해석 |
|---|---:|---|
| building 도형 | 711 | 관계/부분 중복의 최종 감사 전 |
| building_part 도형 | 83 | 지붕·기둥·벽체 등 부분 포함. 독립 건물로 세지 않음 |
| highway 선 | 409 | 도로·보행로·계단·지하 구간 혼합 |
| highway 면 | 69 | D02에서 복합 보행 면 18개 보완. 내부 건물 구멍 보존 |
| barrier 선 | 47 | 담장 등. 모든 실제 담장 포함 보장 아님 |
| barrier 면 | 13 | 선과 겹칠 수 있으므로 합산 개수 해석 금지 |
| gate 노드 | 13 | gate/entrance/lift_gate 태그. 문 폭·실제 통행 허가 확인 전 |
| land_area | 178 | 공원·토지이용·역사시설 등 검사 대상 면 |

건물 도형 711개 중 `height` 태그 101개(14.2%), `building:levels` 134개(18.8%), 둘 중 하나 154개(21.7%), 둘 다 없음 557개(78.3%). **태그 존재 수이며 높이 값의 정확도나 단위 검증 결과가 아니다.**

원본 highway 웨이 460개 중 `width` 태그 0개, `lanes` 43개, `tunnel` 39개, `bridge` 5개가 확인됐다. 계단(`highway=steps`)은 34개다. 도로/보행로를 모두 같은 폭·같은 지면 높이로 생성하면 오류가 생긴다.

핵심 대상 ID:

| 대상 | OSM 원본 ID | 다음 확인 |
|---|---|---|
| 대한문 | way/377289797 | 건물은 있으나 통과할 구멍·문 폭·충돌은 별도 제작 |
| 중화전 | way/181574577 | 기단·지붕·높이 근거 |
| 석조전 | relation/19357693 | 다수 building_part와 부모 외곽의 중복 방지 |
| 돈덕전 | way/517072312 | 현재 배치/외형 대조 |
| 서울특별시청 | way/198561926 | 12층 태그 존재, 실제 높이로 자동 간주 금지 |
| 서울도서관 | relation/10757525 | 구 시청 건물, 신 시청과 구분 |
| 서울광장 | way/370019676 | park/recreation_ground 면. 같은 이름의 버스 정류장과 구분 |

## 아직 하지 않은 일

- 국내 SHP/NGII/Overture 지역 원본 수신, 높이·층수 값 검증.
- 독립 기준 대비 위치·누락률 검증, 건물 관계/부분 중복 최종 정리.
- 지면·계단·도로폭·대한문 개구부·세 필수 동선 검증.
- Godot 설치/버전·렌더러 결정/기동, 캐릭터·충돌·카메라, 3D 자산 생성.
- 실제 플레이, 성능 측정, M4 Pro 확인, 패키지 제작.

따라서 **W0 보행 중간 버전과 V0 첫 버전은 모두 미완료**다. 원본 무결성 확인만으로 실제 공간 완성도나 보행 가능성을 판정하지 않는다.

## 계획 작업 ID와 연결

- **D01 완료:** 원본과 지역 파일의 실제 크기·해시·기준 시각, 준비 파일·도구 버전을 재확인했다. 파일별 출처/상태, 미수신 후보, 실패 증거를 manifest에 추가했다. 원본 변경이나 새 자료가 생길 때만 해당 항목을 갱신한다.
- **D02 완료:** 국가 원본 대비 검토에서 빠진 보행 관계 18개를 복구한 v2를 만들었다. 모든 지역 객체가 원본과 일치하고 참조·면 조립 검사를 통과했다. 현재 파일은 `data/raw/deoksugung_cityhall-v2.osm.pbf`다.
- **D03 → D04:** 다음 실행 순서. 보완 자료 확보와 핵심 동선 근거 검토부터 진행한다.
- **G01:** 변환 smoke test만 실행. 대표 지점 3쌍/게임 배치까지의 정식 검증은 남음.
- **E01 이후:** 미실행. E01의 빈 엔진 기동 검증은 보완 자료 확보와 독립적으로 진행 가능.

## 다음 작업: D03 보완 자료와 핵심 동선 감사

첫 행동은 `osm_audit.json`과 위 핵심 ID를 읽고, 대한문·경내·광장 연결의 원본 도형을 지도 형태로 검토하는 것이다. 이어 GIS건물통합정보 서울 SHP 경로에서 원본 다운로드·필드 정의·좌표계를 확인한다. 자세한 절차는 [DATA_SOURCES.md](DATA_SOURCES.md) 3절을 따른다.

D03의 산출물 `data/reports/supplemental_status.json`에는 **확보/실패/권한 필요/후보**를 구분한다. 자료가 없으면 특정 결손·수동 보완 근거·다음 확보 행동을 적는다. 모든 후보를 반드시 받기 위해 멈추지 않는다. D04에서 구현 가능한 부분과 미확정 부분을 분리한 다음 G01로 진행한다.

## 파일과 재현 방법

현재 원본과 지역 추출물이 있으므로 다운로드·추출을 반복할 필요는 없다. 로컬 환경이 그대로면 필요한 감사만 다음과 같이 실행한다.

```sh
.venv-data/bin/python tools/prepare_osm.py audit data/raw/deoksugung_cityhall-v2.osm.pbf
```

다른 기기에서 데이터 준비 환경이 필요할 때(현재 기기에는 완료):

```sh
python3 -m venv .venv-data
.venv-data/bin/python -m pip install -r requirements-data.txt
```

지역 추출물을 새로 생성할 때만 실행한다. 기존 파일은 자동 덮어쓰기하지 않는다. 원본 갱신은 새 스냅샷/출력 이름과 manifest로 관리해야 한다. 아래 명령의 새 출력 이름은 실제 새 스냅샷에 맞게 지정한다.

```sh
.venv-data/bin/python tools/prepare_osm.py extract data/raw/geofabrik/south-korea-261009.osm.pbf --output data/raw/deoksugung_cityhall-new.osm.pbf
.venv-data/bin/python tools/review_osm_extract.py
```

`data/processed/osm_preview.geojson`은 WGS84 검사 결과이지 게임용 미터 좌표 자산이 아니다. 현재 지역 지도 v2와 비교용 v1은 Git 공유 대상이다. 국가 원본과 `.venv-data`, 가공물은 제외하며 보고서/설정/도구/수동 보정은 추적한다. 전용 저장소는 [codemillss/Sim2Seoul](https://github.com/codemillss/Sim2Seoul), 다른 Mac 준비는 [CROSS_MAC.md](CROSS_MAC.md)를 따른다. 현재 다음 구현 작업은 D03이다.

## 개발 환경 기록

- 현재 기기: M1 Pro, CPU 8코어/GPU 14코어, RAM 16GB, macOS 27.0. 직접 확인한 사양.
- 추가 기기: 사용자 제공 M4 Pro, SSD 1TB. RAM·OS는 아직 확인하지 않음.
- 지도 다운로드와 데이터 환경 준비 후 작업 볼륨 여유: 약 18GiB. 엔진/템플릿 설치 전에 재확인.
- Godot는 일반 앱 폴더/실행 경로에서 발견하지 못했으며 이번 요청에서는 설치하지 않음.

## 이번 검증의 한계

추출기는 교차 웨이와 선택된 관계의 뒤쪽 참조를 보완한다. D02는 국가 원본의 관련 복합 면을 조사 영역과 교차/포함 비교하고 부모 관계를 반복 추적해 누락을 보완했다. 국가 원본에서 조립되지 않은 37개 복합 면은 위치를 확정하지 못하며 현재 지역 구성원과의 연결도 발견되지 않았다. 국경/행정/긴 노선 관계는 목적에 따라 제외했다. 세부 한계는 D02 결과와 추출 manifest에 남겼다.

참조 0건 누락과 기하 유효성 통과는 데이터 구조 검사다. 현재 실제 서울의 위치·높이·접근 가능성에 대한 완전성을 증명하지 않는다. 현장 수준 정확도와 게임 검증을 구분해 보고한다.
