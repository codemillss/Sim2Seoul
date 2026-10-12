# 공간·데이터·게임 계약

상태: 구현 기본안. 사용자 확정 사항과 구분하며, 변경 시 영향받는 작업·검증을 함께 갱신한다. 게임 코드는 아직 없다.

## C01. 단위와 좌표

- 원본 OSM: WGS84, EPSG:4326. GeoJSON 좌표는 `[경도, 위도]` 순서.
- 작업용 수평 좌표: WGS84 / UTM zone 52N, EPSG:32652. `Transformer(..., always_xy=True)`로 축 순서 고정.
- 고정 원점: `config/region.json`의 `origin_lon_lat`. 조사 상자 중심에 둔 기술적 원점이며 대한문 위치나 시작 지점이라는 뜻이 아니다.
- 변환: `east, north = project(lon, lat)`; `world_x=east-origin_east`, `world_z=-(north-origin_north)`, `world_y=local_height_m`.
- 1 Godot 단위=1m. 아트 자산을 가져올 때 루트 전체에 임의 스케일을 곱하지 않는다. glTF의 축 변환은 엔진 가져오기 단계와 중복하지 않는다.
- 국내 SHP: 원본 `.prj`/메타데이터를 확인해 그 좌표계에서 변환한다. 익숙한 EPSG 번호로 추정하지 않는다.
- 높이 기준은 별도다. OSM `height`는 일반적으로 건물 높이이지 해발고도가 아니다. `min_height`, 지면고도, 지붕고도를 섞지 않는다.
- 지형 원본이 없으면 임시 평면을 사용한 구간을 명시한다. 문턱·보도 턱·경사는 수동 보정 또는 지형으로 교체한다. 임시 평면을 서울 지형 재현으로 보고하지 않는다.
- 원점·축·CRS 변경은 전체 데이터 재생성과 이동 경로·수동 보정·저장 위치의 변환을 필요로 한다. 파일마다 중심점을 다시 계산하지 않는다.

## C02. 경계의 세 종류

1. `investigation_bbox`: 자료 추출과 주변 비교용. 현재 약 1km급이며 확정 플레이 영역 아님.
2. `playable_boundary`: 실제로 걷는 폴리곤과 경계의 막음 방식. 필수 동선을 포함한 뒤 고정.
3. `background_boundary`: 멀리 보이는 빌딩·지형 범위. 접근 가능성을 의미하지 않음.

영역을 가로지르는 건물과 관계 도형은 원본 참조를 먼저 완성한다. 단순한 bbox 정점 필터로 도형을 잘라버리지 않는다. 잘라야 한다면 원본 ID와 잘린 경계를 기록한다. 배경 건물은 본래 위치를 유지한다.

## C03. 출처와 재생성

권장 경로(아직 없는 경로는 이후 작업의 산출물):

```text
config/region.json                    # 경계/원점/축/단위
data/raw/                             # 원본, 재작성 금지. 지정한 작은 지역 PBF만 Git 포함
data/raw/geofabrik/source.json         # 취득 URL/해시/이용조건
data/reports/                         # 작은 감사 결과·출처 증거
data/processed/                       # 재생성 가능한 지도 중간물, Git 제외
data/manual/                          # 검토한 보정, 자동 생성기가 덮어쓰지 않음
tools/                               # 데이터 준비/변환 도구
game/assets/generated/               # 생성 자산
game/assets/authored/                # 수동 모델·장식
game/data/                            # 게임 실행용 작은 manifest/경로/ID
game/scenes/                          # 지면/플레이어/도시/경로 장면
game/scripts/                         # 이동·카메라·상호작용
docs/evidence/                        # 검증 결과·측정표·로그 위치
builds/                              # 로컬 실행 파일, Git 제외
```

원본 manifest: 공급자, URL/요청식, 취득일, 데이터 기준 시각, 라이선스 URL, SHA-256, 크기, CRS, 범위, 변환기 버전. 작은 사본을 `data/reports/source_manifest.json`에 두어 원본을 Git에서 제외해도 출처가 남게 한다.

원본 갱신은 기존 스냅샷 덮어쓰기가 아니라 새 버전으로 수행한다. 생성 자산 manifest에 원본 해시·설정 해시·도구 버전을 기록한다. 자동 생성과 수동 보정을 분리해 두 번 생성해도 같은 ID와 배치가 유지돼야 한다.

## C04. 공간 객체 스키마

정식 중간물은 미터 좌표 계약을 따라야 한다. 현재 `osm_preview.geojson`은 WGS84 **검사용 미리보기**이므로 게임 입력으로 바로 사용하지 않는다.

필수 공통 필드:

| 필드 | 규칙 |
|---|---|
| `feature_id` | 예: `osm:way:12345`. 노드/웨이/릴레이션을 구분. 실제 ID는 원본에서 읽음 |
| `source_refs` | 제공자·원본 ID·스냅샷 해시. 병합 때 기존 출처를 보존 |
| `kind` | building, building_part, road, footpath, barrier, gate, ground, landmark 등 |
| `geometry` | 도형, 원본 CRS 또는 정규화 CRS, 단위, hole을 포함한 링 구조 |
| `quality` | source_geometry / derived / estimated / manually_verified. 위치와 높이를 각각 구분 |
| `access` | 원본 접근 태그와 게임 허용 규칙을 별도 기록 |
| `override_ref` | 수동 보정이 있으면 보정 ID와 사유 |

건물 추가 필드: `height_m`, `min_height_m`, `height_source`, `height_raw`, `levels_raw`, `height_assumption_id`. 높이는 단위·형식·범위를 검사해 유효하면 사용하고, 없으면 층수 추정, 그마저 없으면 용도별 임시값을 쓴다. 층당 높이와 기본 높이는 별도 설정표로 관리하며 실제값으로 이름 붙이지 않는다. 일반 빌딩 높이를 궁궐 전각에 일괄 적용하지 않는다.

도로 추가 필드: 중심선과 면을 구분, `width_m`, `width_source`, `lanes_raw`, `oneway`, `layer`, `bridge`, `tunnel`, `pedestrian_allowed`. 폭 추정으로 만든 도로 면이 건물·담장을 덮으면 결함 목록에 넣는다. 중심선 버퍼만으로 실제 보도와 차선을 확정하지 않는다.

게이트/연결 필드: 벽 ID, 문 위치, 통과 가능 폭, 전후 지면 높이, 근거, 검토 상태. OSM 문 노드 하나가 건물 충돌체에 자동 구멍을 만들어주지는 않는다.

## C05. 도형과 중복

- 닫힌 건물 면, 복합 관계, 내부 구멍을 보존한다. 중정에 바닥/건물 충돌체를 잘못 채우지 않는다.
- 건물 외곽과 `building:part`가 겹쳐도 단순히 중복 삭제하지 않는다. 부모 외곽과 부분별 높이의 역할을 먼저 정한다.
- relation의 외곽 웨이가 다시 독립 건물로 생성되는지 검사한다.
- 유효하지 않은 도형 자동 수리 후에는 면적·부분 수·holes 변화를 기록한다. 큰 변화는 수동 검토, 조용히 삭제 금지.
- 나라 전체 파일에서 뽑았다고 모든 지역 관계가 완전한 것은 아니다. 추출 정책의 한계와 참조 검사 결과를 보존한다.
- 현재 데이터 감사 수량은 **OSM 객체/미리보기 도형 수**이지 현실의 건물 개수나 독립 조사 대비 포괄률이 아니다.

## C06. 게임 구성과 이동

권장 장면 구성:

```text
World
  Ground
  GeneratedCity
  LandmarkOverrides
  ManualCollisionAndGates
  Player (CharacterBody3D)
    CollisionShape3D
    Visual
    CameraPivot
      SpringArm3D
        Camera3D
  Routes
  Pedestrians
  Vehicles
  UI
```

초기 제안: 키보드 WASD/방향키, 마우스 카메라, Shift 달리기, Esc 마우스 잠금 해제, 재시작 버튼/키. 걷기 1.4m/s, 달리기 3.5m/s, 키 1.7m, 반경 약 0.3m를 임시 기준으로 삼고 계단·문턱과 함께 조정한다. 점프는 필수 요구가 아니며 조작 설계를 확정할 때 결정한다.

`CharacterBody3D.velocity`는 m/s로 관리하고 `_physics_process`에서 이동한다. `move_and_slide`에 쓰는 속도에 delta를 또 곱하지 않는다. 입력 벡터는 대각선에서 정규화한다. 카메라 기준 수평 방향과 중력을 분리한다.

카메라는 SpringArm 계열 충돌 탐색을 사용하되 플레이어 자신은 제외한다. 초기 근접 거리·회전 한계·감도는 설정으로 둔다. 건물 모서리/문 아래/담장/계단에서 카메라가 벽 뒤로 이동하는지 확인한다.

스폰은 원점과 별도다. 검증된 지면 위 위치·회전으로 시작하고 낙하/영역 이탈 때 해당 위치로 복귀한다. UI로 조작 잠금이 풀렸을 때 입력이 캐릭터로 새지 않게 한다.

## C07. 충돌과 경로

예시 충돌 레이어 번호(비트마스크 값이 아님, 확정 후 이름으로 관리): 1=정적 지면·벽, 2=플레이어, 3=보행자, 4=차량. 마스크 행렬은 해당 구현 작업에서 문서화하고, 모든 레이어를 무차별로 켜지 않는다.

- 플레이어는 지면·벽·건물과 충돌. 보행자와의 반응은 밀침 대신 정지/우회 등 명시한 규칙 사용.
- 카메라 탐색은 정적 장애물을 포함하고 플레이어/장식/필요 없는 NPC는 제외.
- 움직이는 객체에 복잡한 정적 삼각형 충돌체를 그대로 붙이지 않는다.
- 시각 도형과 충돌체는 분리 가능하되, 체감되는 벽 위치·문 폭은 맞춰야 한다.
- 단차는 플레이어 이동 능력에 맞춰 실제 메시/간소화 충돌 램프를 선택하고 보정 사실을 기록.
- NPC/차량의 시각 경로 보간만으로 벽 관통을 막았다고 판정하지 않는다. 경로의 폭과 장애물 여유를 검사한다.
- 차량은 도로 중심선에서 임의로 달리는 대신 확인한 방향·차로 위치의 소수 경로를 사용한다. 보행 구간/궁궐로 진입하지 않는다.
- 처음에는 보행자/차량 경로를 분리하고 교차 구간에서는 간단한 정지 규칙을 사용한다. 검증하지 않은 신호·교통 현실성을 주장하지 않는다.

교통·군중 개체 수는 설정 파일에 둔다. 임시 부하 프로필은 성능 검증 문서가 기준이다. 멀리 있는 개체를 줄이더라도 가까운 개체가 눈앞에서 소멸하지 않도록 재생성 위치를 검토한다.

## C08. 자산·실행·두 기기

- Godot 정확 버전·렌더러·내보내기 템플릿 버전을 기동 성공 후 기록한다. 두 기기에 동일 버전 사용.
- 먼저 간단한 장면으로 기본 렌더러를 시험한다. 기기/OS 결함이면 Compatibility 등 대안을 비교하고 측정 결과로 선택한다. 기능 이름만으로 성능을 가정하지 않는다.
- 작은 지도를 한 장면에 다 넣을 수 있는지 먼저 측정한다. 처음부터 대규모 월드 스트리밍을 구현하지 않는다. 필요 시 구역 분할·표시 거리·LOD·그림자·반복 자산 인스턴싱 순으로 줄인다.
- 실행 중 지도 API/네트워크가 없어도 돌아가야 한다. 원본 전국 PBF·Python 환경은 배포 앱에 넣지 않는다.
- 저장 대상이 생기면 사용자 데이터 경로와 스키마 버전을 사용한다. V0 필수 저장은 마지막 위치/설정 정도로 제한하거나 재시작 기준을 명시한다.
- 두 기기의 `.godot` 캐시·가상환경·빌드 결과를 동기화하지 않는다. 코드/설정/수동 자산과 생성 manifest를 공유하고 환경별로 재생성한다.
- 현재 작은 지역 지도 v2와 이전 v1은 Git으로 함께 공유한다. 국가 전체 원본은 로컬에 유지하며 [CROSS_MAC.md](CROSS_MAC.md)를 따른다.
- 파일 이동/커밋/외부 공개는 각각 별도 행동이다. 계획 문서가 자동 push나 클라우드 업로드를 지시하지 않는다.

## 공식 구현 참고

- [Godot CharacterBody3D](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html)
- [Godot Spring arm](https://docs.godotengine.org/en/stable/tutorials/3d/spring_arm.html)
- [Godot macOS 내보내기](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html)
- [pyproj Transformer](https://pyproj4.github.io/pyproj/stable/api/transformer.html)
- [pyosmium 참조 완성 writer](https://docs.osmcode.org/pyosmium/latest/reference/Data-Writers/)

이 문서의 수치·구조는 이 프로젝트의 구현 제안이다. 공식 문서가 프로젝트 성능·정확도를 보장하는 것은 아니다.
