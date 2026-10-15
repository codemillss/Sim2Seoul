# 포함한 자료의 출처

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

국내 SHP·NGII 지역 원본·사진·거리뷰는 포함하지 않았다. 외부 3D 모델은 아래 L03 CC0 파일만 추가했다. VWorld 컬럼 정의서와 공식 궁궐 안내 HTML은 로컬 참고용이며 Git에서는 제외한다. 공개 열람만으로 지도·사진의 게임 재사용을 허용하지 않는다. 출처 URL·해시·조사 요약은 공유한다.

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
