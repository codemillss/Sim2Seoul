# 데이터 출처와 확보 상태

확인일: 2026-10-12. **파일을 확보한 경로와 공식 안내만 확인한 후보를 구분한다.** 세부 수량·검증 결과는 [WORK_STATUS.md](WORK_STATUS.md)와 감사 보고서가 기준이다.

## D01 인수 검수 완료

실제 로컬 파일 6개를 대조했고, 원본/지역 추출의 크기·SHA-256, 원본 MD5·기준 시각, 미완성 다운로드 유무, 도구 버전 등 17개 검사를 통과했다. [D01 검증 기록](../data/reports/d01_verification.json)과 [파일·후보 목록](../data/reports/source_manifest.json)에 증거를 남겼다. 기존 자료를 재사용했으며 새 원본 다운로드는 수행하지 않았다.

D01 당시 후보 6개는 원본 파일 미수신 상태였다. 현재 보완 상태는 아래 D03 결과가 기준이다. 이전 Overpass 실패 2건의 정확한 요청 시각·전체 HTTP 응답 파일은 현재 기록에 없어 미확인으로 표시했다. 출처 안내 확인과 로컬 파일 확보를 구분한다.

## D03 취득·검토 완료

Overture 지역 건물 GeoJSON과 Copernicus DSM 지역 참고 사본, VWorld 컬럼 정의서, 덕수궁 공식 경내·접근 근거를 실제 확보했다. 자료별 미수신·접근 요구·한계는 [supplemental_status](../data/reports/supplemental_status.json), 실물 값·도형·해시 검사는 [D03 결과](evidence/D03_SUPPLEMENTAL_REVIEW.md)에 있다. 현재 다음 작업은 D04다.

Overture 원본 수신 736개 중 실제 도형이 조사 상자와 교차하는 것은 733개다. 기존 OSM 711개와 비OSM 후보 22개이며, 높이 100개는 모두 OSM 원천이어서 독립적인 높이 보완은 아니다. 원천 ID와 시점을 유지하고 자동 병합하지 않는다.

DSM은 약 30m 해상도 지표 자료이며 건물·수목을 포함한다. 지역 사본의 좌표와 원본 픽셀을 확인했으나 문턱·계단·보도 턱·보행 지면으로 사용하지 않는다. 상세 지형은 미수신 결손으로 남는다.

국내 건물 본체는 실제 로그인 모달에 막혔다. 공개 정의서 원본 224,314 bytes는 HTTP 200·ZIP CRC 검사를 통과했다. `테이블정의서(전체)`의 `AL_D010`에서 **A16 높이(m), A26 지상층_수, A27 지하층_수, A28 데이터생성변경일자**를 직접 확인했다. 실제 서울 SHP/DBF/PRJ와 해당 구역 값은 미수신이므로 별도 확인해야 한다. [정의서 검사](../data/reports/vworld_schema_acquisition-d03.json), [국내 접근 조사](evidence/D03_KOREAN_SOURCE_ACCESS.md).

공식 덕수궁 지도는 명칭·접근 도식 참고로 확인했다. [경내·통제 근거](evidence/D03_PALACE_ROUTE_SOURCES.md)는 일반 경내와 석조전 실내, 과거 통제 해제와 현재/예정 공사를 구분한다. 이미지 재배포 허가는 아직 확정하지 않았다.

## 1. 실제 확보: Geofabrik의 OpenStreetMap 원본

기존 Overpass 두 서버의 실패 이후, [Geofabrik 한국 다운로드](https://download.geofabrik.de/asia/south-korea.html)에서 날짜가 고정된 국가 원본을 직접 받았다. 원본을 로컬에서 한 번 읽어 지역을 추출하므로 공개 조회 서버의 실행 시간 제한에 의존하지 않는다.

| 항목 | 확인 값 |
|---|---|
| 원본 | `south-korea-261009.osm.pbf` |
| 공급자 | Geofabrik / OpenStreetMap contributors |
| 파일 | [공식 날짜 고정 PBF](https://download.geofabrik.de/asia/south-korea-261009.osm.pbf) |
| 크기 | 288,878,500 bytes, 약 275.5 MiB |
| 원본 헤더의 OSM 기준 시각 | 2026-10-09T20:21:04Z |
| 취득 시각 | 2026-10-12 02:38 KST |
| 무결성 | 공급자 MD5와 일치, SHA-256 별도 기록 |
| 현재 지역 파일 | `data/raw/deoksugung_cityhall-v2.osm.pbf`, 188,346 bytes |
| 추출 범위 | 서 126.9710, 남 37.5608, 동 126.9815, 북 37.5694 |
| 범위의 의미 | 조사용. 플레이 경계는 아직 미정 |
| 이용 조건 | [ODbL / OSM 저작권 안내](https://www.openstreetmap.org/copyright) |

출처 manifest: [source_manifest.json](../data/reports/source_manifest.json). 추출 정책·한계·해시: [extract_manifest.json](../data/reports/extract_manifest.json). 속성·참조 검사: [osm_audit.json](../data/reports/osm_audit.json).

D02에서 국가 원본과 대조해 보행 복합 면 18개의 누락을 수정했다. 현재 보행 면은 69개이며 참조 누락·지역 면 조립 오류는 없다. 이전 지역 파일 187,286 bytes는 보존했다. 자세한 변경과 한계는 [D02 검토 결과](evidence/D02_EXTRACT_REVIEW.md)를 따른다.

원본에는 도로/보행로 선뿐 아니라 보행 면, 지하/터널, 계단, 건물 부분 도형이 섞여 있다. 모두 같은 지상 도로나 하나의 건물 상자로 변환하면 안 된다. `highway` 객체의 `width` 태그는 이번 원본 검사에서 없었으므로 도로폭을 실제값으로 확정할 수 없다.

## 2. 추가 확보 후보와 우선순위

| 우선 | 공식 자료 | 역할 | 실제 상태 / 접근 조건 |
|---|---|---|---|
| 1 | [국토부 GIS건물통합정보](https://www.data.go.kr/data/15083092/fileData.do) | 건물 높이·층수·도형 보완 | 서울 129MB 목록(기준 2026-10-09/갱신 10-11) 확인, 로그인 단계로 본체 미수신. 최신 컬럼 정의서 실물 확보 |
| 2 | [국토지리정보원 연속수치지형도](https://www.data.go.kr/data/15059721/fileData.do) | 1:5,000 도로·건물·지형 계층 검토 | SHP/NGI·무료·공공누리 1유형 확인. 로그인·대용량 전송 소프트웨어 안내 있음. Mac 다운로드 가능 여부와 지역 계층은 미확인 |
| 3 | [Overture Buildings](https://docs.overturemaps.org/guides/buildings/) | 건물 윤곽 누락 비교 | 2026-09-23.1 소구역 원본 확보, 733개 교차 도형 검토. ODbL 및 비OSM 원천 표시 보존 |
| 지표 보조 | [Copernicus GLO-30](https://registry.opendata.aws/copernicus-dem/) | 넓은 범위의 지표 고도 참고 | 38×32 픽셀 사본 확보. 지면 DTM 아님, 상세 단차 사용 금지 |
| 보조 | [국토부 연속수치지형도 건물](https://www.data.go.kr/data/15125047/fileData.do) | 건물 평면 대조 | 포털의 SHP·무료·출처표시 안내 확인, 원본 미수신. 높이 보유를 가정하지 않음 |
| 필수 대조 | [궁능유적본부 덕수궁 관람코스](https://royal.khs.go.kr/ROYAL/contents/R701000000.do?schGroupCode=dsg) | 전각 명칭·보행 목적지·접근 제한 대조 | 공식 HTML/지도 메타데이터 확보, 지도 렌더 확인. 측량·현재 전 동선 개방·게임 이미지 재사용 검증과 구분 |
| 보조 | [국가기록원 석조전 공사 도면 목록](https://www.archives.go.kr/next/newsearch/showDetailPopup.do?rc_code=1310377&rc_rfile_no=201003360323&rc_ritem_no=&sitePage=) | 전체 배치·핵심 건물 도면 참고 | 2006년 생산 도면 목록 확인. 원본 도면 다운로드·치수·재사용권 미확인. 현재 배치 기준으로 단독 사용하지 않음 |

GIS건물통합정보는 기관별 구축 차이로 참고용이라는 제공기관의 안내가 있다. 다운로드 후 최신 필드 정의와 실제 값을 검사한다. [국가교통DB 공식 보고서](https://www.ktdb.go.kr/DATA/pblcte/20250805093928585.pdf)에는 A16 높이(m), A26 지상층수, A27 지하층수 정의가 나오지만, 이를 현재 SHP의 검증을 대신하는 근거로 쓰지 않는다.

Overture는 OSM을 포함하는 여러 원천을 사용할 수 있어 OSM과 완전히 독립된 정답 데이터가 아니다. 각 건물의 sources를 보존하고 자동 중복 병합을 피한다.

## 3. 미수신 상세 자료를 재개할 때의 취득 순서

이 절은 남은 자료의 재개 절차다. 현재 실행 순서는 D04이며, 이미 확보한 소구역을 다시 받을 필요는 없다. 접근 환경이 준비될 때 필요한 자료만 재개한다.

1. 먼저 현재 감사 결과로 부족한 대상을 정한다. 건물 711개에 일괄 임의 높이를 넣기 전에 주요 빌딩·궁궐의 우선순위를 정한다.
2. GIS건물통합정보의 [원본 VWorld 연결](https://www.vworld.kr/dtmk/dtmk_ntads_s002.do?svcCde=NA&dsId=18)에서 서울 파일과 컬럼 정의를 확인한다. `.shp/.shx/.dbf/.prj`와 인코딩 파일을 함께 보존한다.
3. 서울 파일을 실제 `.prj` 기준으로 변환하고 조사 구역만 추출한다. OSM과 겹침·주소·명칭을 검토해 높이를 연결한다. 공식 포털 화면 접근만으로 파일 확보 완료 처리하지 않는다.
4. 필요할 때 NGII에서 덕수궁 주변 1:5,000 계층을 신청·다운로드한다. 로그인/도구가 필요하면 그 단계와 사용 기기를 기록한다. 무관한 전국 자료를 반복 수집하지 않는다.
5. 두 경로가 지연되면 Overture 소구역 파일을 보조로 확보한다. 건물 누락을 비교하고 높이 충실도는 실제 값으로 판단한다.
6. 대한문·담장·필수 세 동선은 별도 근거 목록과 수동 보정 레이어로 관리한다. 외부 자료 취득이 지연돼도 엔진 기동·캐릭터 독립 장면은 진행할 수 있다.

## 4. 실패 이력과 재시도 규칙

- `overpass-api.de` 소구역 조회: HTTP 504.
- `overpass.private.coffee` 소구역 조회: HTTP 500.
- 두 실패 모두 현재 [availability_check.json](../data/availability_check.json)에 보존했다. 지도에 데이터가 없다는 뜻이 아니다.
- Geofabrik 경로 성공 후 같은 Overpass 조회를 반복할 이유는 없다. 새 변경분이 필요하거나 특정 관계 누락을 좁혀 확인할 때만 재사용한다.
- 국가 원본이 이미 있고 해시가 맞으면 다시 내려받지 않는다. 이 원본은 날짜 고정 스냅샷이다.

## 5. 표시와 재사용 원칙

OSM/Geofabrik에는 OSM 기여자와 ODbL 출처를 기록한다. 데이터·가공 데이터의 배포 조건과 게임 코드의 라이선스를 혼동하지 않는다. 국내 자료는 해당 파일의 공공누리 유형과 원본 공급자의 조건을 함께 보존한다.

[OSM 타일 정책](https://operations.osmfoundation.org/policies/tiles/)에 맞춰 지도 이미지 대량 다운로드를 자료 확보 대안으로 쓰지 않는다. 거리뷰·3D 화면·사진은 공개 열람과 게임 자산 복제 권한을 구분한다. 궁궐 안내 이미지도 [제공기관 저작권 정책](https://royal.khs.go.kr/ROYAL/contents/R802000000.do)와 개별 조건 확인 전 텍스처로 넣지 않는다.

최종 앱은 내려받은 지역 자산으로 오프라인 실행한다. 원본 전국 파일과 데이터 준비 환경은 앱에 포함하지 않는다.
