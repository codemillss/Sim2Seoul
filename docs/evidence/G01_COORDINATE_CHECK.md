# G01 좌표 기준과 검증

검증일: 2026-10-12. 기존 OSM v2와 M1 Pro의 데이터 환경을 사용했다. **고정 원점·미터 단위·수평 변환 검사 13개가 통과했다.** 좌표 설정 수치는 변경하지 않았다. 다음 작업은 G02 도형 정리다.

## 고정한 기준

- 원본 EPSG:4326의 `[경도, 위도]`를 보존하며 EPSG:32652로 변환한다.
- 원점 `[126.97625, 37.5651]`의 투영 좌표는 `[321266.3692172853, 4159488.62345062]`m다. 스폰이 아닌 고정 기술 원점이다.
- `x=east-origin_east`, `z=-(north-origin_north)`, `y=local_height_m`, 1단위=1m. 파일별 중심 이동이나 추가 회전을 하지 않는다.
- 조사 bbox는 계속 조사용이며 플레이 경계는 미정이다. 실제 지면 배정은 G03, 실제 Godot 전달은 E04에서 확인한다.

설정은 [region.json](../../config/region.json), 재사용 변환은 [coordinate_system.py](../../tools/coordinate_system.py), 실제 입력/도구 해시·대표점·검사값은 [coordinate_check.json](../../data/reports/coordinate_check.json)에 있다.

## 대표점의 의미

대한문·중화전·석조전·돈덕전·서울시청·서울도서관·서울광장의 OSM 면에서 **외곽링 정점을 경도·위도 순으로 정렬한 첫 점**을 선택했다. 선택한 정점의 원본 위경도와 도형 내 인덱스를 보존하고, 지역 PBF에서 좌표가 정확히 같은 노드도 확인했다. 관계 도형도 같은 방식이다. 문 입구, 건물 중심, 스폰 위치, 경로 끝점으로 해석하지 않는다.

| 기준점 쌍 | 투영 직선 거리 | WGS84 측지 거리 | 상대 차이 |
|---|---:|---:|---:|
| 대한문 → 중화전 | 183.406983m | 183.408125m | 0.000623% |
| 석조전 → 돈덕전 | 107.393624m | 107.394217m | 0.000552% |
| 서울광장 → 서울시청 | 134.359898m | 134.360849m | 0.000708% |
| 중화전 → 서울시청 | 308.364062m | 308.366066m | 0.000650% |

4쌍 모두 0.2% 허용치 이내이며 최대 절대 차이는 약 0.002004m다. **선택한 윤곽 정점 사이의 직선 비교**이고 실제 보행 거리나 현장 치수 정확도가 아니다.

## 실제 검사

원본 크기/해시, 미리보기 크기/해시와 원본/설정 연결, 7개 기준점의 원본 노드 좌표, 조사 상자의 투영 적용 범위, 원점·네 모서리·7개 기준점 역변환, 원점 0 좌표를 확인했다. 왕복 최대 오차는 `1.42e-14`도이며 `1e-8`도 조건을 통과했다.

투영/로컬 거리와 방위각이 일치하며 투영 격자 동/서/북/남 및 로컬 위 10m 합성점이 단위·부호 검사에 통과했다. 측지 동/북 10m의 주축 부호도 확인했다. 위경도 순서를 뒤집거나 NaN/무한대 좌표·높이를 전달하면 거부한다.

격자 방위각과 측지 초기 방위각은 이 지역에서 약 1.23° 차이가 난다. 자오선 수렴각 등의 투영 효과를 별도로 기록했고 같은 값으로 강제하지 않았다. 축 순서는 [pyproj 공식 Transformer 설명](https://pyproj4.github.io/pyproj/stable/api/transformer.html), 수렴각은 [Proj API](https://pyproj4.github.io/pyproj/stable/api/proj.html), 투영은 [PROJ UTM 설명](https://proj.org/en/stable/operations/projections/utm.html)을 참고했다.

## 재현과 남은 검증

```sh
.venv-data/bin/python tools/prepare_osm.py audit data/raw/deoksugung_cityhall-v2.osm.pbf
.venv-data/bin/python tools/check_coordinates.py
```

`tools/setup_mac.sh`도 기본 준비 후 좌표 검사를 실행한다. 전국 원본·추가 보완 의존성·DSM 전체 타일은 필요 없다. `data/processed/coordinate_reference.json`은 Git 제외 가공물이므로 새 Mac에서 생성하며, 같은 기준점을 추적 보고서 안에도 보존한다. 과거 검사 보고서를 바꾸지 않고 재확인하려면 `--report /tmp/sim2seoul-g01-check.json --reference /tmp/sim2seoul-g01-reference.json`을 사용한다.

별도 작업 사본에서의 재현·실패 감지 증거는 [G01 인수 검사](../../data/reports/g01_verification.json)에 기록한다. 이는 현재 M1의 기존 도구 환경에서 한 검사이며 M4 설치/실행 검증이 아니다.

독립 측량 좌표 대비 실제 위치 정확도, 수직 표고·지면·계단, 문 진입·보행 동선, Godot 전달 후 거리/축, 게임 성능은 미검증이다. 임시 y=0은 수평 검사값이다. W0/V0는 계속 미완료다.
