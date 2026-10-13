# 공간·데이터·게임 계약

상태: 구현 기본안. 사용자 확정 사항과 구분하며, 변경 시 영향받는 작업·검증을 함께 갱신한다. E02 정식 구조·입력/메뉴·로컬 계약과 E03 서울 표시 코드는 있다. 캐릭터 이동·충돌은 아직 없다.

D04에서 원천 사용·보류·추정 정책을 [config/data_usage.json](../config/data_usage.json)에 정리했다. 좌표 수치는 기존 `config/region.json`이 기준이며 사용 정책이 좌표 계약을 대체하지 않는다. [data_gaps](data_gaps.md)와 [수동 검토 큐](../data/manual/review_queue.json)는 G02–G04/W 단계의 입력이다.

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

G01에서 기존 수치·축을 변경하지 않고 수평 변환과 로컬 단위 계약 버전 1을 고정했다. 재사용 구현은 [coordinate_system.py](../tools/coordinate_system.py), 증거는 [coordinate_check.json](../data/reports/coordinate_check.json)이다. UTM의 east/north는 격자 방향이며 측지 동/북과 자오선 수렴각만큼 차이가 난다. 로컬 방위각은 `atan2(dx, -dz)`로 투영 평면 방위각과 비교하고, 측지 초기 방위각과의 차이는 별도로 기록한다. 이를 맞추려고 월드 전체를 회전하지 않는다.

`y=local_height_m`는 지역 수직 좌표 규칙이다. G01 대표점의 y=0과 위쪽 10m는 합성 검사값이며 실제 지면이 아니다. 해발고도 기준은 계속 미확정이다. G03은 로컬 지지 평면 y=0을 임시 기준으로 정하고 전체 보존 도형 외접 범위+10m를 기술적 범위로 기록했다. 계단/교량/터널/0이 아니거나 해석 불가한 layer/지하/물 예외 132개에는 지면 높이를 배정하지 않는다. 평면은 플레이 경계·스폰·통행 허가가 아니며 DSM 표고나 건물 height를 원점의 해발고도로 취급하지 않는다. [규칙](../config/height_rules.json)·[검토](../data/reports/height_review.md).

## C02. 경계의 세 종류

1. `investigation_bbox`: 자료 추출과 주변 비교용. 현재 약 1km급이며 확정 플레이 영역 아님.
2. `playable_boundary`: 실제로 걷는 폴리곤과 경계의 막음 방식. 필수 동선을 포함한 뒤 고정.
3. `background_boundary`: 멀리 보이는 빌딩·지형 범위. 접근 가능성을 의미하지 않음.

G04 `boundary_candidate.json`의 후보는 R1/R2/R3 원문 연결과 참조 윤곽의 합집합+임시 12m 여유에서 영국대사관 경내를 제외한 검토 도형이다. `finalized_playable_boundary=null`, `spawn_point=null`, 접근 권한 없음이다. 경계 안에 차도/건물/정원이 있어도 통행 허가를 의미하지 않는다. 실제 경계 막음·낙하 복귀는 P/W에서 필수 동선을 검증한 뒤 고정한다.

영역을 가로지르는 건물과 관계 도형은 원본 참조를 먼저 완성한다. 단순한 bbox 정점 필터로 도형을 잘라버리지 않는다. 잘라야 한다면 원본 ID와 잘린 경계를 기록한다. 배경 건물은 본래 위치를 유지한다.

## C03. 출처와 재생성

권장 경로(아직 없는 경로는 이후 작업의 산출물):

```text
config/region.json                    # 경계/원점/축/단위
data/raw/                             # 원본, 재작성 금지. 명시한 지역 PBF/보완 소구역만 Git 포함
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

E02는 `game/`를 Godot의 프로젝트 경계로 정했다. authored `world_config.tres`는 manifest 경로만 보유하며 `config/region.json`의 좌표 값은 중복 작성하지 않는다. G01 원천 해시를 대조한 뒤 Git 제외 `game/data/generated/region.json` 원본 바이트 사본과 manifest를 생성한다. 런타임은 허용된 `res://` 계약만 읽고 외부 원본/가공물/Python/네트워크를 요구하지 않는다. E02 당시 자산 목록은 비어 있었고, E03은 manifest v2/`E03_display_only`에서 로컬 `world.json` 하나를 체크섬/크기로 연결한다. 28개 필수 원천/정책/근거 해시를 실행 준비 때 대조한다. [실제 경로·입력·처리 역할](GAME_PROJECT.md). 수동 모델은 `game/assets/authored/`, 자동 생성 결과는 별도 경계에서 재생성한다.

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

G02 중간물은 `data/processed/features.json`의 **별도 JSON 형식**이다. 위경도 GeoJSON으로 읽지 않는다. `coordinate_system`에 EPSG:32652·고정 원점·단위를 적고 `geometry`는 `[x,z]` 미터 좌표, `source_geometry`는 원본 `[경도,위도]`와 EPSG:4326을 보존한다. y/지면/건물 높이는 아직 배정하지 않는다. 같은 원천의 선/면 등 여러 표현은 `feature_id=정식 원천 ID:source_kind`로 구분하고 `entity_id`와 직접 원천·노드/관계 참조를 남긴다.

XZ 폴리곤의 외곽은 반시계·구멍은 시계 방향으로 정규화한다. 이는 중간물 링 규칙이며 E03은 시계 방향 앞면/명시 법선과 실제 엔진 배열을 검증했으며, 고정 거리·기준물 검증은 E04에서 수행한다. 빈/비유효 도형을 조용히 수리하지 않고 작업을 중단하며 원본 오류를 기록한다. 조사 bbox에서 도형을 자르거나 도로폭 버퍼를 만들지 않는다. [생성 규칙](../config/geometry_rules.json)·[G02 증거](../data/reports/geometry_check.json).

G03의 높이 가공물은 `heights.json`이며 G02 feature_id로 연결한다. 실제 필드는 `height_class`, `height_m`, `min_height_m`, `vertical_span_m`, `source_tags`, 원문 파싱 상태, `source_levels`, `assumption_id`, `component_evidence_ids`, `emit_coarse_body`다. 단일 유효 height를 우선하고, 원문이 있지만 다중/해석 불가면 보류한다. height가 없는 부분/지붕은 전체 높이를 임의로 만들지 않는다. 석조전은 명시 부분의 유효 상단 최대값으로 단순 외곽 상한을 도출한다. 랜드마크 임시값·층수 환산·용도 기본값과 계수는 [height_rules.json](../config/height_rules.json)에 구분한다. 원문 height에는 지붕이 포함되며 min_height와의 차이가 수직 길이다. 원문 min_height가 없을 때 하단 오프셋 0은 관측값이 아닌 로컬 기본안이다. 일반 빌딩 높이를 궁궐 전각에 일괄 적용하지 않는다.

`terrain.json`은 객체별 `ground_class`, `ground_y_m`, 예외 사유, `physical_elevation_m=null`, `walkable_permission=null`, `terrain_shape_verified=false`를 기록한다. 지면 기준·높이 유효성·단순 본체 선택은 통행 허가와 별개다. 정관헌 주변 sand 관계는 원본 전체 면·구멍과 로컬 도형을 참조로 보존한다. 원문·현재 G02 검사·정책/큐·G03 규칙·수동 결정·근거 파일·생성 도구 해시가 달라지면 검토 후 재생성한다. 원문 정확도는 별도 검증이며 모든 추정은 가정 ID를 유지한다.

도로 추가 필드: 중심선과 면을 구분, `width_m`, `width_source`, `lanes_raw`, `oneway`, `layer`, `bridge`, `tunnel`, `pedestrian_allowed`. 폭 추정으로 만든 도로 면이 건물·담장을 덮으면 결함 목록에 넣는다. 중심선 버퍼만으로 실제 보도와 차선을 확정하지 않는다.

G04 보행/차량 가공물은 동일 478개 도로선·보행면의 모드별 기록이다. `source_geometry`는 G02 XZ 원문 도형, `candidate_surface_geometry`는 원문 면 또는 명시 폭 버퍼이며 실제 메시가 아니다. `structural_candidate`, `mode_class`, `access_basis`, 폭/가정 ID·원문 방향, 지면/노드 검토 사유를 분리한다. foot은 access를, motorcar는 motor_vehicle/vehicle/access를 우선한다. 조건/제한은 보류하고 보행면·정원·차도 사이에 자동 권한을 주지 않는다. 관계 member way 노드까지 barrier/access를 보존한다. `runtime_permission=null`, `runtime_surface_ready=false`이며 표고/폭/허가의 독립 확인을 뜻하지 않는다. [규칙](../config/movement_rules.json).

선↔선은 원본 공유 노드, 선↔면/면↔면은 실제 원문 도형 접촉을 연결 후보로 기록하며 근접 스냅을 하지 않는다. 2D 접촉 그래프·원본 노드 체크포인트는 상세 경로/차량 제어/통행 검증이 아니다. gate/passsage와 계단·노드 제약을 유지하고 원문 면의 구멍은 채우지 않는다. 건물/담장 겹침·횡단 후보 차량 접촉을 삭제하거나 자동 절단하지 않고 후속 검토 목록으로 넘긴다. R1 경내·R2 북측 지상 횡단·R3 남측 구간의 원천 연결은 [수동 검토](../data/manual/movement_review.json)에 고정했다. 북측 전체 일주·실내·광장 잔디·사유지를 자유 보행으로 확장하지 않는다.

게이트/연결 필드: 벽 ID, 문 위치, 통과 가능 폭, 전후 지면 높이, 근거, 검토 상태. OSM 문 노드 하나가 건물 충돌체에 자동 구멍을 만들어주지는 않는다.

## C05. 도형과 중복

- 닫힌 건물 면, 복합 관계, 내부 구멍을 보존한다. 중정에 바닥/건물 충돌체를 잘못 채우지 않는다.
- 건물 외곽과 `building:part`가 겹쳐도 단순히 중복 삭제하지 않는다. 부모 외곽과 부분별 높이의 역할을 먼저 정한다.
- relation의 외곽 웨이가 다시 독립 건물로 생성되는지 검사한다.
- 유효하지 않은 도형 자동 수리 후에는 면적·부분 수·holes 변화를 기록한다. 큰 변화는 수동 검토, 조용히 삭제 금지.
- 나라 전체 파일에서 뽑았다고 모든 지역 관계가 완전한 것은 아니다. 추출 정책의 한계와 참조 검사 결과를 보존한다.
- 현재 데이터 감사 수량은 **OSM 객체/미리보기 도형 수**이지 현실의 건물 개수나 독립 조사 대비 포괄률이 아니다.

G02의 보수적 생성 역할은 명시 `type=building` 관계의 outline/part를 먼저 연결하며 공간 겹침은 부모 후보로만 기록한다. 부모 외곽과 부분을 동시에 전체 건물 볼륨으로 생성하지 않는다. 기본 몸체 후보에는 primary 외곽만 넣고 `building:part`와 `building=roof`는 역할을 보존한 참조다. G03 이후 실제 부분 표현을 채택할 때 부모 전체 볼륨과 겹치지 않도록 전략을 교체한다. 이 목록은 실제 메시가 아니다.

동일 유형의 도형과 원본 태그(높이 의미 포함)가 모두 같을 때만 별칭으로 묶고 원본 기록은 남긴다. 설명되지 않은 본체 겹침은 양쪽을 기본 몸체 생성에서 보류한다. 겹침 보고 임계값 0.01㎡는 수치적인 검토 기준이지 측량 정확도가 아니다. 같은 원천의 담장 선/면은 선을 기본 표현, 면을 참조로 구분한다. 모든 보류·별칭과 Overture 22개 미승인 후보의 사유는 검사 보고서에 기록한다.

G03은 [잠정 생성 결정](../data/manual/height_review_decisions.json)에 따라 정관헌의 이름 윤곽 `w/381755268`과 상동교회 본체 `w/1128365145`만 단순 본체에 복원했다. 정관헌의 큰 윤곽/sand 구멍과 교회의 52.1m 작은 면은 참조로 보존한다. 좌표 수정·부분 높이 승인·탑의 시작 높이 추정은 하지 않는다. 상세 부분 전략으로 교체할 때 본체 전체 부피와 동시 생성하지 않도록 다시 검사한다.

E03은 G03 본체 635개만 실제 부피로 표시하며 부분/지붕 참조·지면 예외는 그대로 보류한다. G04 면 370개를 별도 보기용 길/도로로 표시하고 `runtime_permission=null`, `runtime_surface_ready=false`, 충돌 없음 상태를 유지한다. 토지 참조 178개를 색으로 표시해도 통행 권한은 주지 않는다. 겹침을 자동 절단하지 않는다. 담장 두께 0.35m, 15–21/35/55mm 표면 분리는 시각 가정이며 측량값/단차가 아니다. [표시 설정](../config/world_display.json)·[E03 증거](../data/reports/world_import.md). `game/resources/world_geometry/`는 기기별 생성 경계이며 Git 제외다.

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
- E01 현재 개발 기준: Godot **4.7.2 Standard / Forward+ / Metal**. 현재 M1의 편집기·실제 GPU 장면과 세 후보를 확인했다. [환경/기동 증거](environment.md). 내보내기 템플릿은 미설치이며 R03 전에 **4.7.2.stable**로 준비한다. 빈 장면 결과는 도시 성능·M4 기동 판정이 아니다.
- 작은 지도를 한 장면에 다 넣을 수 있는지 먼저 측정한다. 처음부터 대규모 월드 스트리밍을 구현하지 않는다. 필요 시 구역 분할·표시 거리·LOD·그림자·반복 자산 인스턴싱 순으로 줄인다.
- 실행 중 지도 API/네트워크가 없어도 돌아가야 한다. 원본 전국 PBF·Python 환경은 배포 앱에 넣지 않는다.
- 저장 대상이 생기면 사용자 데이터 경로와 스키마 버전을 사용한다. V0 필수 저장은 마지막 위치/설정 정도로 제한하거나 재시작 기준을 명시한다.
- 두 기기의 `.godot` 캐시·가상환경·빌드 결과를 동기화하지 않는다. 코드/설정/수동 자산과 생성 manifest를 공유하고 환경별로 재생성한다.
- 현재 작은 지역 지도 v2와 이전 v1은 Git으로 함께 공유한다. 국가 전체 원본은 로컬에 유지하며 [CROSS_MAC.md](CROSS_MAC.md)를 따른다.
- D03 Overture 지역 원본과 DSM 지역 참고 사본도 명시한 파일만 공유한다. DSM은 지면 자산이나 게임 수직 기준이 아니며, 전체 타일·국내 컬럼 정의서·참고 HTML은 로컬에 둔다. 새 Mac 기본 검사는 공유 파일 해시를 확인한다.
- 파일 이동/커밋/외부 공개는 각각 별도 행동이다. 계획 문서가 자동 push나 클라우드 업로드를 지시하지 않는다.

## 공식 구현 참고

- [Godot CharacterBody3D](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html)
- [Godot Spring arm](https://docs.godotengine.org/en/stable/tutorials/3d/spring_arm.html)
- [Godot macOS 내보내기](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html)
- [pyproj Transformer](https://pyproj4.github.io/pyproj/stable/api/transformer.html)
- [pyosmium 참조 완성 writer](https://docs.osmcode.org/pyosmium/latest/reference/Data-Writers/)

이 문서의 수치·구조는 이 프로젝트의 구현 제안이다. 공식 문서가 프로젝트 성능·정확도를 보장하는 것은 아니다.
