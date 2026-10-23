# 포함한 자료의 출처

> 저장소 공개 상태: 2026-10-21 GitHub API에서 PUBLIC으로 확인했습니다. 아래 R03 등 과거 비공개 배포 관련 설명은 해당 버전 당시의 기록입니다. 데이터·외부 자산의 고지는 각각 유지합니다.

## EXP29 사람 모델과 수영복 전용 몸체 (2026-10-22)

**Microsoft Rocketbox Avatar Library — MIT, Copyright (c) Microsoft Corporation.** [공식 저장소](https://github.com/microsoft/Microsoft-Rocketbox)의 고정 커밋 `0943055db6ec570bcef9f2c8b41c9e5467c808f9`에서 `Male_Adult_04`, `Female_Adult_07`의 FBX·텍스처를 도입했다. [라이선스 원문](../game/assets/vendor/microsoft_rocketbox/LICENSE.md)과 [파일별 원본 URL·SHA·변환 기록](../game/assets/vendor/microsoft_rocketbox/PROVENANCE.json)을 보존한다. TGA를 무손실 PNG로 바꾸고 FBX의 텍스처 확장자/경로를 맞췄으며, 게임에서 미터 높이·방향·자체 동작 리타게팅·의복 색을 적용한다. 선택한 두 FBX는 실제 검사에서 각각 81본과 가중치가 있는 단일 메시를 가졌다. 전체 라이브러리의 여러 LOD 설명을 이 두 파일에 그대로 적용하지 않는다.

**MakeHuman Community core/system data assets — CC0 1.0.** [공식 라이선스의 데이터 범위](https://github.com/makehumancommunity/makehuman/blob/a8bc2d54ff0ac92e78ff71431b1023eda42bf482/LICENSE.md)와 [시스템 자산 팩](https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html)을 확인했다. 앱 소스 코드와 데이터 자산의 조건을 구분하며, MakeHuman 앱의 AGPL 코드를 복사하지 않았다. [CC0 원문](../game/assets/vendor/makehuman_swim/LICENSE.CC0.md)·[라이선스 범위](../game/assets/vendor/makehuman_swim/UPSTREAM_LICENSE_SCOPE.md)·[원본/산출물 SHA 및 제작 내용](../game/assets/vendor/makehuman_swim/provenance.json)을 보존한다. 실제 인체 데이터·UV·가중치에서 별도 수영복 몸체를 만들고 불투명 반바지/수영복으로 덮으며, 숨은 보정 형상은 렌더하지 않는다. 도입한 GLB는 재생성 기록을 가진 파생 자산이다. 각 수영 몸체는 원본 스킨 가중치의163본을 보존한다. 수영복은 CC0 core의 helper-tights 형상에서 만든 불투명 남성 반바지/여성 shorty 수영복이며 별도 커뮤니티 수영복의 이용 조건을 이 고지로 대신하지 않는다. 피부·의복·눈의 원본/파생 파일과 가려진 몸 표면 제외 범위는 해당 provenance를 따른다.

실행 중 정규화·방향 보정·자체 IK 리타게팅, 원본 머리를 유지한 수영 몸체 접합, 기존 원본 UV를 이용한 의상 색상 처리는 프로젝트의 연결 코드다. 의상 색은 실제 옷 표면의 평균 선형RGB와 StandardMaterial/정점색으로 처리하며 원본 normal map·피부 형상을 새 스캔 자산으로 설명하지 않는다. 기존59개 자체 절차형 외형은 숨긴 호환용 기준으로만 보존한다. 상점의 아이보리/코발트/차콜 컬러 상의는 같은 공급자 원본 의복 형상의 색상 변형이며 독립된 후드/카디건/재킷 자산을 추가한 것은 아니다. 공급자 사진/preview와 실제 게임 GPU 캡처, 데이터 이용 조건과 외형 품질 수용을 구분한다. 최신 XYZ 목 접합·실제 의상 화면 검수의 완료 판정은 통합 검증 대기이며 이 출처 문서가 수용 증명서는 아니다. 사람 스캔·모션 캡처·GTA 원본 자산을 도입했다는 주장은 하지 않는다. 보행·기구 접촉·골반/척추 연결의 보정은 프로젝트의 자체 코드이며, 고정 시선과 숨긴 접촉 관절을 실제 가중치 몸의 높이/골반 회전 제한으로 혼동하지 않는다. 최신 보행 변형과 외형 수용은 별도 검증 대기다.

기존 자체 도형은 보이지 않는 동작·시설 접촉·의상 호환 기준으로 남긴다. 그 도형을 새 사실적 외형의 증거로 사용하지 않는다. 위 라이선스는 해당 외부 자산에 적용하며 프로젝트 전체 코드·지도·다른 자산에 일괄 적용하지 않는다. GTA/The Sims 모델·리깅·모션·음향을 추출한 자산은 포함하지 않았다. [참조·RE 범위](REFERENCE_DIRECTION.md)와 실제 수용 상태는 [WORK_STATUS](WORK_STATUS.md)를 따른다.

## 서울시 등고선·표고점 지역 원천 (2026-10-18)

출처: 서울특별시 도시공간본부 도시계획상임기획과, [서울시 경사도 제공 페이지의 서울시 등고선.zip](https://data.seoul.go.kr/dataList/OA-22241/F/1/datasetView.do), 2025-03-20 갱신/제공 설명은 국토지리정보원2023년 기준 수치지형도. 공공누리1유형: 출처표시 조건으로 상업 이용·변경 가능, 제3저작권자 없음. 정확한 제공 파일/원문·취득 SHA는 [지역 manifest](../data/raw/supplemental/seoul_terrain/20261018/manifest.json)와 [이용 조건](../data/raw/supplemental/seoul_terrain/20261018/source_license.json)에 보존했다.

변경: 현재 bbox+주변200m만 자르고 EPSG5174→EPSG32652/고정 원점 XZ로 변환했으며 원본 HEIGHT/CONT/NUME 등 속성을 보존했다. WGS84 GeoJSON도 별도로 제공한다. 원본 전체 ZIP은 공유하지 않는다. EXP21은 이 지역 등고선·표고점의 연속 역거리 보간을5m 간격으로 표본화하고, 건물별 수평 기초와 주변 연결을 추정해 게임 지면에 적용했다. 원본 HEIGHT와 고정 원점31.362231m를 뺀 게임 상대Y를 분리한다. 수직 datum은 확정하지 않았으며5m 실측 DEM·건축 기초·도로 단면의 측량 정확도를 주장하지 않는다. [변경 방법·교차검증·한계](TERRAIN_INTEGRATION.md). FABDEM/Mapzen은 별도 취득 비교 참고이고 현재 게임이 이들을 지면으로 사용하지 않는다.


2026-10-17 추가: `game/assets/audio/stonewall_guitar.wav`는 외부 음원/노래 입력 없이 `tools/make_busking_music.py`로 직접 만든 기타 PCM이며 해당 원본 생성 자산은 CC0-1.0으로 제공한다. 코드/지도 전체의 조건을 이 음원 조건으로 대체하지 않는다. 추가 편의점은 기존 소지역 OSM 스냅샷을 사용하므로 기존 OSM 표시/제공 조건을 유지한다. 교회/호텔 표지·대기 줄·피크닉·이정표·풀은 출처 위치 위의 게임용 시각/시설 표현이다.

현재 포함하는 두 지역 지도 `.osm.pbf`와 OSM에서 파생한 감사 자료:

**© OpenStreetMap contributors — Open Database License (ODbL) 1.0.**

- [OpenStreetMap 저작권·라이선스](https://www.openstreetmap.org/copyright)
- [ODbL 1.0 전문](https://opendatacommons.org/licenses/odbl/1-0/)
- 공급 경로: [Geofabrik 한국](https://download.geofabrik.de/asia/south-korea.html)
- 원본 기준 시각: 2026-10-09T20:21:04Z.
- 지역 범위·해시·처리 내용: `data/reports/extract_manifest.json`, `data/reports/source_manifest.json`.

v2는 같은 원본에서 기존 지역 추출물에 보행 공간 관계와 참조를 보완한 것이다. 원본 데이터의 ODbL 조건을 보존한다. 이 표시가 게임 코드·문서 전체에 ODbL을 일괄 적용한다는 뜻은 아니다.

## D03에 추가한 Overture 지역 건물 자료

**© OpenStreetMap contributors, Overture Maps Foundation — ODbL 1.0.**

- 지역 파일: `data/raw/supplemental/overture/2026-09-23.1/buildings.geojson`.
- 공급 릴리스: 2026-09-23.1, 취득 2026-10-12. bbox 조회 결과와 원천 `sources`를 그대로 보존했다. 실제 도형 교차로 제외한 3개도 원본에는 남아 있다.
- [Overture 건물 안내](https://docs.overturemaps.org/guides/buildings/)·[출처 및 라이선스](https://docs.overturemaps.org/attribution/)·[ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/).
- 이 구역의 비OSM 원천: Qian Shi et al., *A First High-quality Vector Data of Buildings in East Asian Countries Based on a Comprehensive Large-scale Mapping Framework*, Zenodo, 22 July 2023, [doi:10.5281/zenodo.8174931](https://doi.org/10.5281/zenodo.8174931), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Overture 공식 출처 목록의 허가 근거다. 개별 `sources.license`가 비어 있어도 원본 값을 임의로 수정하지 않았다.
- 변경: 지역 조회, 조사 영역 교차 분류, SVG 대조 그림의 미터 투영·시각 표현. 현실 정확도나 원천 기관의 승인·보증을 의미하지 않는다.

## D03에 추가한 Copernicus DSM 지역 참고 사본

파일: `data/raw/supplemental/copernicus/20261012/deoksugung_cityhall-dsm-reference.tif`. 원본은 [AWS 공개 저장소](https://registry.opendata.aws/copernicus-dem/)의 GLO-30 타일이며 전체 타일에서 원래 픽셀 38×32개를 추출했다. 건물·수목을 포함한 지표 자료로, 보행 지면 자산이 아니다.

Copernicus WorldDEM-30를 사용해 만든 지역 추출 사본이다. 출처 표시:

> produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved.

법률 또는 위임에 따라 Copernicus 프로그램을 담당하는 기관은 이 자료의 사용에 대해 책임을 지지 않는다.

[사용·배포·수정 조건](https://documentation.dataspace.copernicus.eu/APIs/SentinelHub/Data/DEM/resources/license/License-COPDEM-30.pdf)에 따른 출처·책임 문구다. 재배포하는 사용자는 해당 조건과 후속 사용자에 대한 표시 의무도 보존한다. 프로젝트나 게임이 제공기관의 공식 승인을 받았다는 의미가 아니다.

## 로컬 참고 자료와 이후 작업

국내 SHP·NGII 지역 원본·사진·거리뷰는 포함하지 않았다. 외부 3D 모델은 아래 L03 CC0와 위 EXP29 사람 자산의 개별 고지를 따른다. VWorld 컬럼 정의서와 공식 궁궐 안내 HTML은 로컬 참고용이며 Git에서는 제외한다. 공개 열람만으로 지도·사진의 게임 재사용을 허용하지 않는다. 출처 URL·해시·조사 요약은 공유한다.

D04에서 실제 공유 파일·원천·사용 판정을 대조했다. 사용 범위는 [data_gaps](data_gaps.md), 기계 판독 규칙은 [data_usage](../config/data_usage.json)를 따른다. 국내 본체나 미허가 이미지가 새로 들어오면 이 판정을 다시 확인한다.

## 파생 자료와 게임 배포에 적용할 기준

OSM/Overture에서 만든 공간 데이터에는 ODbL 표시·원천·변경 기록을 함께 관리한다. 데이터베이스를 만드는 프로그램의 조건은 별도로 관리한다. ODbL의 데이터/프로그램/Produced Work 구분과 공개 사용 조건은 [원문 2.3·4.3–4.6](https://opendatacommons.org/licenses/odbl/1-0/)을 따른다.

수정 데이터베이스나 그 데이터베이스에서 나온 결과물을 공개 사용하면, 수정 데이터베이스 또는 전체 변경 내용/재현 방법을 기계 판독 가능한 형태로 제공해야 하는 조건을 확인한다. 공개 배포 시에는 실제 파일 성격·결합 방식에 맞춰 제공 묶음과 접근 경로를 정한다. **현재 비공개 Git 링크는 대중이 받을 수 있는 제공 경로가 아니다.** R03은 개인용 로컬 패키지를 만드는 단계이며 대중 공개 배포와 구분한다.

R03의 게임 표시 기준은 시작 안내에 읽을 수 있는 `© OpenStreetMap contributors, Overture Maps Foundation`를 두고, 메뉴의 ‘자료 출처’에서 OSM 저작권·ODbL·Overture·추가 원천·추정 범위 및 제공 데이터/변경 방법에 접근할 수 있게 하는 것이다. 상세 위치·읽기 가능성은 실제 화면에서 검증한다. [OSMF 게임·시뮬레이션 지침](https://osmfoundation.org/wiki/Licence/Attribution_Guidelines#Computer_games_and_simulations).

비OSM 원천의 저자·라이선스·변경 표시는 파생 자료에도 보존한다. `sources.license=null`을 사용 조건이 없는 것으로 해석하지 않는다. Copernicus 사본을 재배포할 때는 위 변형 출처·책임·후속 사용자 조건을 동봉한다. 게임 입력으로 쓰지 않더라도 저장소의 참고 파일에는 이 표시를 유지한다.

Godot과 새 자산은 실제 사용하는 버전·파일에 따라 출처를 추가한다. 이번 단계는 확인한 자료에 대한 사용 기준이며 미래 산출물 전체의 라이선스 검증을 대신하지 않는다.

## L01 공식 외관 참조

2026-10-15의 [참조 목록](../data/manual/landmark_references.json)·[제작 기준](landmark_reference.md)은 공식 본문 사실/사진 관찰의 짧은 요약과 URL을 보존한다. 사진·도면·3D모델·로고·텍스처 파일은 도입하지 않았다. 관찰한 공공누리 유형/권리 유보·페이지/사진 날짜의 미확인을 자료별로 남겼으며 무료 열람을 자산 재사용 허락으로 확대하지 않는다. 지붕·열주·창 리듬 등의 단순 외형은 후속 L02/L03에서 자체 제작한다. 이 기록은 아직 만들지 않은 자산이나 향후 배포의 이용권을 일괄 확정하지 않는다. 기존 OSM 공간 파생물의 출처·배포 조건은 계속 유지한다.

## L02 궁궐 절차형 외형

[recipes/설명](../game/assets/authored/landmarks/palace/README.md)과 생성 코드는 독립 제작한 색·비례·부재 배치 규칙이다. 외형의 원본 footprint는 기존 OSM 파생 입력을 그대로 사용하므로 공간 원천·변경 재현 방법과 위 ODbL 표시를 유지한다. 사진/도면 추적·외부 텍스처/모델·로고/서체 이미지 파일은 추가하지 않았다. 공식 참조의 사실/관찰과 제작상 비율은 구분한다. 기존 모델을 수정하는 [대안 조사](ASSET_REUSE_OPTIONS.md)는 실제 파일 확보나 개별 이용권 확인이 아니며 새 자산을 도입할 때 파일별로 기록한다.

## L03 Kenney 원본과 수정한 도시 외형

**Kenney — City Kit Commercial 2.1, CC0 1.0.** [공식 배포 페이지](https://kenney.nl/assets/city-kit-commercial)에서 ZIP을 실제 수신하고 동봉된 [License.txt](../game/assets/vendor/kenney_city_kit_commercial/License.txt)를 확인했다. 원본 `building-skyscraper-a.glb`·상대 경로 `Textures/colormap.png`·라이선스 문구와 [취득 해시](../game/assets/vendor/kenney_city_kit_commercial/provenance.json)를 공유한다. 배포 모델과 팔레트 PNG는 수정하지 않았다. 전체 ZIP은 캐시에만 둔다.

게임용 수정은 방향/높이 외곽에 비균일하게 맞추기, 지도 footprint로 자르기, 법선 재계산, 세 가지 색으로 줄이기와 석재 저층부·얇은 층 분할 추가다. 원본 삼각형 연결과 재현 코드는 [L03 결과](../data/reports/city_landmarks.md)에 남긴다. 이 모델은 실제 서울파이낸스센터를 표현한 원본이 아니며 수정본도 정확한 복제가 아니다. CC0 원본 조건과 OSM에서 파생한 공간 배치의 ODbL 조건을 구분해 보존한다.

시청·도서관·광장 표시 규칙은 독립 제작했다. 공식 참조의 사진·도면·로고는 가져오지 않았다. 이번 실제 수입 결과는 위 L01/L02 당시 ‘외부 모델 미수입’ 기록 이후의 변경이며, 다른 후보의 파일 이용권을 함께 확정하지 않는다.

## R03 개인용 패키지의 자료와 변경 방법

개인용 앱은 미리 준비한 지역 실행 자료를 읽으며 지도 서버를 호출하지 않는다. 원본·변경 재현 자료의 저장소는 [Sim2Seoul](https://github.com/codemillss/Sim2Seoul)이며 접근 권한이 있는 사용자만 받을 수 있다. 이 링크를 대중에게 공개된 데이터 제공 경로로 설명하지 않는다. 공개 배포를 하려면 앞 절의 제공 조건과 실제 포함 파일을 다시 확인한다.

동일 버전의 `data/reports/source_manifest.json`, `extract_manifest.json`과 `data/raw/deoksugung_cityhall-v2.osm.pbf`에서 OSM 입력을 확인한다. `config/region.json`, `data/manual/`의 수동 보정과 외형/동선 결정, `tools/prepare_*.py` 및 각 단계 보고서가 좌표 변환·높이 추정·단순화·문과 지지면 보정·표시 자산의 변경 방법이다. Overture 지역 원본은 `data/raw/supplemental/overture/2026-09-23.1/buildings.geojson`이며 게임 윤곽을 독립 측량 자료로 교체했다는 뜻이 아니다.

앱의 `resources/legal/`과 앱 번들의 `Contents/Resources/`에 출처, Godot MIT/추가 고지, Kenney CC0, 자료·변경 안내를 동봉한다. Godot 고지는 실제 사용한 엔진 API에서 추출하며 파일 포함 여부·해시·실행 성공은 별도 R03 결과에 기록한다. 준비용 Copernicus TIFF·전국 지도·개발 환경·자격 증명은 앱에 넣지 않는다. 개인용 앱 제작이 미확인 외부 자료나 이후 공개 배포를 일괄 허가하는 것은 아니다.

## EXP03 사진 참고·AI 석재 자산·서울도서관 로비

2026-10-16, 기준 커밋 `5eac7d8` 이후의 최신 탐험 장면 추가분이다. 앞선 L01/L02/EXP02의 ‘외부 텍스처 미수입’ 기록과 기존 V0/R03의 실내 제외 설명은 당시 범위를 보존한다. 이번에 포함한 새로운 bitmap은 아래 **AI 신규 생성 albedo 1개**이며 외부 공식 사진 원본을 게임 자산으로 가져온 수는 0이다. OSM/Overture·Kenney·Godot의 기존 표시와 조건은 계속 유지한다.

### 관찰에 사용한 공식 자료

- `PALACE_2020`: [서울시 내 손안에 서울 기사](https://mediahub.seoul.go.kr/archives/1504168), 게시 2020-10-29, 사진 오세훈. [대한문](https://mediahub.seoul.go.kr/wp-content/uploads/editor/images/000507/P1050874-%ED%8E%B8%EC%A7%91.jpg), [돌담](https://mediahub.seoul.go.kr/wp-content/uploads/editor/images/000506/P1050892-%ED%8E%B8%EC%A7%91.jpg), [석재/기와](https://mediahub.seoul.go.kr/wp-content/uploads/editor/images/000506/P1050928-%ED%8E%B8%EC%A7%91.jpg)를 브라우저 화면에서 관찰했다. 사진의 붉은 목재·공포·기와 끝·사각 화강석 줄과 색 대비를 참고했으며 파일 다운로드·편집·게임 포함은 하지 않았다.
- `CIVIC_2012`: [서울 신청사 준공·입주 설명](https://news.seoul.go.kr/citybuild/archives/205773)과 [2012년 준공 시기 청사 사진](https://news.seoul.go.kr/citybuild/files/2012/09/newcityhall_09_07.jpg). 도서관의 가는 세로 창/중앙부, 신청사의 곡면 유리/대각 격자를 실제 화면에서 관찰했다. 2012년 사건·페이지 수정일 2018-11-08·현재 열람 시점을 구분하며 현재 현장 상태의 증거로 사용하지 않는다. 원본 사진 픽셀을 수입하거나 추적하지 않았다.
- `LIBRARY_FLOOR`: [서울도서관 공식 1층 안내](https://lib.seoul.go.kr/rwww/html/ko/floorInfo1F.jsp)의 대체 텍스트와 [공식 도면 PNG](https://lib.seoul.go.kr/image/ko/local/guide/floorInfo1.png)를 브라우저 화면에서 실제 확인했다. 중앙 출입구 전실·양옆 계단/승강기·좌우 열람 공간의 관계를 참고했다. 도면 이미지와 로고를 게임에 넣거나 정확한 치수/가구 배치를 복제하지 않았다. 16×12×4.8m 로비는 별도 제작한 게임 공간이며 실제 1층 평면도 재현이 아니다.

열람일은 모두 2026-10-16이며 개별 촬영일·1층 안내도 작성일은 미확인이다. 위 관찰은 무료 열람을 재사용 허가로 해석한 것이 아니다. URL·관찰 범위·날짜와 생성 자산 정보는 [photo_realism_references.json](../data/manual/photo_realism_references.json), 특징별 제작 판단은 [landmark_reference](landmark_reference.md)에 남긴다.

### 포함한 신규 AI 생성 파일

| 항목 | 기록 |
|---|---|
| 파일 | [game/assets/textures/seoul/palace_granite_albedo.png](../game/assets/textures/seoul/palace_granite_albedo.png) |
| 제작 | built-in `image_gen` imagegen tool로 새로 생성한 원본. 입력 참조 이미지 0장. 공식 사진의 편집본·사진측량·현장 scan이 아님 |
| 생성 요청 | 사각 화강석을 수평으로 쌓은 거친 회색 석재·옅은 모르타르·평평한 확산광·반복 가능한 albedo. 전체 원문 prompt와 사용 범위는 위 manifest에 보존 |
| 크기 | 4,409,390 bytes |
| SHA-256 | `57784a5b3843a63e0e822b3e10cf63707e39b49d1c1e604fb56b8f67545c025d` |
| 게임에서의 처리 | 원본 PNG는 보존하고 import의 mipmap 생성과 shader의 anisotropic filtering·월드 미터 투영·1.8m 반복·색/풍화 조정·미분 bump 계수 0.0015m를 적용. 반복 크기와 요철은 제작 가정 |
| 한계 | colour/albedo 1장. 촬영한 normal/roughness map이나 완전한 seamless scan을 제공했다는 뜻이 아님. 이 AI 생성 파일을 공식 사진의 이용조건이나 Kenney CC0 자산으로 분류하지 않음 |

궁궐·시청 세부 부재, 지면 shader·절차형 하늘과 로비/가구는 자체 제작 코드/기본 형상이다. 사진·도면·로고의 원본 미디어 파일을 새로 포함하지 않았다. 게임 ‘자료 출처’의 최신 탐험 설명에는 석재 텍스처가 AI로 새로 제작되었다는 점, 공식 사진 미포함, 로비의 단순화와 상층/다른 건물 실내 제외를 표시한다.

최종 실행 판정은 [EXP03 요약](../data/reports/photo_realism/20261016/summary.json)에 연결한다. M5/Metal에서 외형 59개·실내 56개·탐험 회귀 51개, 총 166개 GPU 검사가 통과했다. PNG/shader 실제 실행·실내 입출입과 기존 외부 body/fragment 692개의 shape·변환 등 보존, 추가 로비 body 47개를 확인한 결과이며 사진 수준의 복제나 원천 기관의 승인·보증은 아니다. [일반 GUI 시작 로그](../data/reports/photo_realism/20261016/launch.log)의 준비 완료·시작 오류 0과 실제 네이티브 창도 확인했다. 출처/생성 기록과 실행 검사 결과를 각각 보존하며, 이 문서 자체가 포함하지 않은 외부 자산의 이용권을 확정하지 않는다.


## EXP27 공공시설·차량 음향 (2026-10-22)

차량 엔진·타이어·버스 문·헬기 로터·비·방수와 서로 다른 경찰/소방 사이렌 9개는 [자체 생성 도구](../tools/make_city_vehicle_audio.py)의 결정적 수학 합성으로 제작했다. 외부 녹음·음원·샘플을 가져오지 않았으며 실제 한국 긴급차량의 음향을 녹음하거나 정확히 복제한 자료가 아니다. [파일별 PCM 형식·길이·SHA·제작 기록](../game/assets/audio/city_vehicles/provenance.json)을 보존한다. 프로젝트의 별도 배포 라이선스 미지정 상태는 유지하며 이 파일을 MIT·CC0 외부 자산으로 잘못 분류하지 않는다.

세종로파출소의 위치/명칭은 보존된 OSM 건물 형상과 [종로경찰서 공식 지구대·파출소 안내](https://www.smpa.go.kr/user/nd9096.do)의 세종대로141 표기를 대조했다. 2026-10-22 확인이며 공식 원본 사진·문장·로고를 게임에 수입하지 않았다. 외관 부재·게임 로비와 순찰 운영은 자체 제작이며 실제 내부 평면이나 현장 운영을 조사해 복원했다는 뜻이 아니다. 서소문파출소의 존재는 [남대문경찰서 공식 안내](https://www.smpa.go.kr/user/nd93412.do)에서도 확인하되, 해당 페이지로 정확한 현장 치수/배치를 확정하지 않는다.

새 119안전센터는 사용자가 선택한 현재 권역 외곽의 게임 시설이다. 현재 원천 지도에 실제 소방서 건물이 없으므로 실재 기관의 명칭/주소를 임의로 붙이지 않는다. 원본 토지·사유지·보행로와 시설의 제작 경계를 [소방 배치 자료](../game/assets/authored/fire_station_service.json)에 기록한다. 경찰/소방 차량·청사 세부·표지·조명은 자체 기본 형상이며 실제 기관의 승인·시설 배치·법적 절차를 재현했다는 주장은 하지 않는다.

## EXP28 가상 대형 시설·인체·치수 비교 (2026-10-22)

사용자는 현재 지도 외곽의 실제 크기 기준 게임용 대형 병원/소방서/경찰서를 선택했다. [병원](../game/assets/authored/city_hospital.json)·[대형 경찰청사](../game/assets/authored/police_headquarters.json)·[소방서](../game/assets/authored/fire_station_service.json)는 자체 기본 형상과 미터 설계이며 실제 서울 기관의 상호/부지/현재 평면·운영을 복원한 자산이 아니다. 병원 본체는 원본 `landuse=construction` 필지 안에 놓고 두 출입 경사로는 인접한 비사유지 게임 지면까지 연결한다. 원본 건물/도로/보도·사유지·나무와 원본 TIN을 유지하는 범위와 동결 입력 SHA를 각 자료/실행 기록에 남긴다.

EXP28 당시 인체 외형과 관절/동작, 치수 선/숫자·1m 격자는 자체 절차적 제작이었다. 당시에는 외부 캐릭터·GTA 자산·모션 캡처를 가져오지 않았다. EXP29의 현재 보이는 사람은 위 MIT/CC0 텍스처·스킨 자산으로 교체하며 이 문장은 이전 단계의 출처 이력이다. [원본 전수 치수 감사](../data/reports/real_scale/20261022/source_audit.json)는 보존된 OSM 기반 원자료 재투영/표시 외곽과 이격거리의 비교이며, 모든 건물의 실측 치수를 새로 확보한 자료가 아니다. 높이 근거의 추정/태그 구분과 원래 ODbL 고지는 유지한다.

## EXP32 원본 경적과 운전자 반응

도로 차 H 경적은 `traffic_car_takeover.gd`가384/512Hz 두 파형과 자체 envelope로 생성하는0.5초 PCM이다. 외부 녹음·게임 음원을 사용하지 않았다. 추가 운전자 배우는 이미 고지한 MIT Microsoft Rocketbox 인체와 기존 자체 avatar 동작을 사용하며 별도의 새 자산 다운로드가 없다. 원래 도로 차 body/model은 보존한다.
