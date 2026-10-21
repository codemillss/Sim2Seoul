<p align="center">
  <img src="docs/media/sim2seoul-banner.svg" alt="Sim2Seoul — From spatial data to a walkable Seoul" width="100%">
</p>

<p align="center">
  <strong>지도 위의 서울을, 직접 걸어 들어가는 공간으로.</strong><br>
  덕수궁의 돌담길과 시청 앞 광장을 걷고, 건물에 들어가고, 자전거와 킥보드를 타는 3D 탐험 프로젝트입니다.
</p>

<p align="center">
  <code>Godot 4.7.2</code> · <code>GDScript</code> · <code>Python 3.14</code> · <code>GIS</code> · <code>macOS</code><br><br>
  <a href="docs/ENGINEERING.md">기술적 문제 해결</a> ·
  <a href="docs/RUN_GUIDE.md">실행 안내</a> ·
  <a href="docs/WORK_STATUS.md">현재 구현·검증</a> ·
  <a href="docs/README.md">문서 둘러보기</a>
</p>

## 왜 만들었나요?

**익숙한 서울의 한 구역을, 바라보는 배경에서 직접 돌아다니며 머물 수 있는 공간으로 만들고 싶었습니다.** 전통 궁궐과 현대 빌딩이 맞닿아 있는 덕수궁·시청 주변을 첫 무대로 골랐습니다. 실제 도로와 건물의 위치·축척을 바탕으로 동네의 연결감을 유지하면서, 그 안에 이동과 생활 경험을 쌓아가는 개인 프로젝트입니다.

출발점은 공개 지도였지만, 지도에 건물을 표시하는 것만으로는 걸을 수 있는 도시가 되지 않았습니다. 지면과 출입구의 높이를 맞추고, 카메라가 건물을 뚫지 않게 하고, 차에서 내린 뒤 다시 걸을 수 있게 해야 했습니다. **공간 데이터를 플레이 가능한 환경으로 바꾸는 과정**을 이 프로젝트의 핵심 과제로 삼았습니다.

현재는 탐험과 상호작용을 중심으로 개발하고 있습니다. 장기적으로는 이 공간 위에 생활·꾸미기·주민 시뮬레이션을 확장하려 합니다. [장소 선택과 개발 방향](docs/PROJECT_CONTEXT.md#왜-이-공간을-만드는가)

## 플레이 화면

2026-10-17–20 개발판의 실제 Godot 실행 화면입니다. 실내·옥상 시설은 게임용으로 구성했으며, 각 화면에 캡처 날짜를 표시했습니다.

<table>
  <tr>
    <td width="50%"><img src="data/reports/personal_mobility/20261020/bike_visibility_native_final02_production_mount.png" alt="서울도서관 앞에서 자전거를 빌려 탄 실제 게임 화면" width="100%"><br><strong>광장에서 시작하는 이동</strong><br>자전거 대여와 3인칭 탑승 시점 · 2026-10-20</td>
    <td width="50%"><img src="data/reports/personal_mobility/20261020/scooter_native_final04_production_mount.png" alt="발판에 서서 핸들을 잡고 전동 킥보드에 탄 실제 게임 화면" width="100%"><br><strong>직접 타는 전동 킥보드</strong><br>서 있는 자세·가속·조향·제동 · 2026-10-20</td>
  </tr>
  <tr>
    <td><img src="data/reports/realism_rework/20261017/final/interior_gpu_library_population_roles.png" alt="서가와 계단형 독서 공간이 있는 게임용 서울도서관 내부" width="100%"><br><strong>문 안으로 이어지는 탐험</strong><br>용도별 실내·층 이동·시설 · 2026-10-17</td>
    <td><img src="data/reports/terrain_integration/20261018/final/entries_gpu_plaza_actual_swimming_rebased_pool.png" alt="도심 옥상의 게임용 수영장에서 캐릭터가 수영하는 모습" width="100%"><br><strong>옥상에서 머무는 경험</strong><br>게임용 야외 풀·입수·수영·탈출 · 2026-10-18</td>
  </tr>
  <tr>
    <td><img src="data/reports/street_detail/20261019/native_dog_keeper_close.png" alt="돌담길 옆 보도에서 반려견과 산책하는 사람" width="100%"><br><strong>조금씩 살아나는 거리</strong><br>산책하는 사람과 반려견 · 2026-10-19</td>
    <td><img src="data/reports/personal_mobility/20261020/signals_native_daehanmun_vehicle_view_vehicle_green_pedestrian_red.png" alt="대한문 앞 횡단보도와 차량 녹색·보행 적색 신호의 실제 렌더링" width="100%"><br><strong>움직임을 조율하는 신호</strong><br>주기·잔여 시간·차량 정지/재개 · 2026-10-20<br><sub>차량 접근 방향에 배치한 검수 시점</sub></td>
  </tr>
</table>

## 무엇을 할 수 있나요?

| 경험 | 구현 내용 |
|---|---|
| **서울을 걸어서 탐험** | 대한문을 지나 덕수궁 경내·돌담길·서울광장·시청 주변을 이동합니다. 3인칭 카메라, 달리기, 연속 점프와 속도 선택을 지원합니다. |
| **건물 안과 위로 이동** | 126개 방문 대상 건물·1,242개 게임 층을 구성했습니다. 도서관·공공·업무·호텔 등 용도별 실내, 계단·승강기와 다양한 옥상을 제공합니다. |
| **시설을 실제로 사용** | 가까운 설비에서 E로 식사·샤워·운동을 시작하거나 종료합니다. 게임용 옥상 수영장에서는 물에 들어가 수영하고 밖으로 나올 수 있습니다. |
| **다른 방식으로 이동** | 자전거 2대·킥보드 2대를 대여해 가감속·조향·제동합니다. 버스는 2개 정류장을 연결하는 작은 승하차 체험 구간입니다. |
| **거리의 생활감 관찰** | 사람 28명·반려견 2마리·기존 이동 자동차 14대와 상점 외관·버스킹·수목·가로등을 배치했습니다. 낮·해질녘·밤을 선택할 수 있습니다. |
| **작동하는 횡단 신호** | 7개 횡단 구역에 차량 신호 15개·보행 신호 14개를 배치했습니다. 46초 게임 주기, 잔여 시간·점멸과 차량의 정지·재출발을 연결했습니다. |

기능·수량 기준은 [현재 작업 상태](docs/WORK_STATUS.md)와 [2026-10-20 검증 집계](data/reports/street_detail/20261020/summary.json)입니다. 건물별 시설과 층 배치는 실제 입주·시설 현황을 뜻하지 않습니다.

## 어떻게 만들었나요?

**Python은 공간 자료를 준비하고, Godot는 그 공간에서 실제로 이동하고 상호작용하는 경험을 담당합니다.** 원천 자료·추정·수동 보정을 분리해 지도 갱신과 게임 제작을 이어갈 수 있도록 구성했습니다.

```mermaid
flowchart LR
    A["공개 공간정보<br/>OSM · Overture · 서울시 지형"] --> B["Python GIS 전처리<br/>좌표 · 도형 · 높이 · 보행 영역"]
    B --> C["Godot 공간 구성<br/>메시 · 지형 · 충돌 · 출입구"]
    C --> D["3인칭 탐험<br/>실내 · 시설 · 교통 상호작용"]
    D --> E["검증과 피드백<br/>물리 검사 · 실제 화면 · OS 조작"]
    E --> B
    E --> D
```

| 기술적 과제 | 선택한 접근 |
|---|---|
| **지도와 게임의 축척 연결** | 위경도를 EPSG:32652 미터 좌표와 지역 원점으로 변환하고 **게임 1단위 = 1m**를 유지합니다. |
| **높이가 다른 공간의 연결** | 서울시 등고선 41개·표고점 96개를 보간하고, 동일한 지형 삼각형을 표시·충돌·높이 조회에 사용합니다. 기초 평탄화와 입구 연결은 별도 제작 가정으로 남깁니다. |
| **상호작용의 일관성** | 짧은 E 입력과 메뉴에서 누른 키를 구분하고, 안내와 실제 동작이 같은 대상을 선택하게 합니다. 자전거·킥보드·버스 사이의 제어권과 하차 복원을 함께 관리합니다. |
| **보이는 성공과 실제 성공의 구분** | 저장된 증거 대조, 엔진 물리 검사, 그래픽 화면 검토와 OS 키보드 조작을 구분해 기록합니다. 실패 사례도 수정 근거로 보존합니다. |

[E 입력 경합·하차 충돌·지형 정합성을 해결한 과정 →](docs/ENGINEERING.md)

## 실행하기

개발 실행의 기준 환경은 **macOS · Python 3.14 · Godot 4.7.2 Standard**입니다. Python과 Godot를 먼저 설치한 뒤 진행하세요. 최신 장면은 `explore_walk.tscn`이며 아래 실행기를 사용합니다. [환경 준비](docs/environment.md) · [기기별 상세 안내](docs/CROSS_MAC.md)

```sh
git clone https://github.com/codemillss/Sim2Seoul.git
cd Sim2Seoul
bash tools/setup_mac.sh
```

<details>
<summary><strong>처음 복제한 Mac: 실행 자료를 한 번 준비하세요</strong></summary>

`setup_mac.sh` 이후 아래 순서로 실행합니다. 이미 같은 실행 자료를 준비한 Mac은 반복하지 않아도 됩니다. `prepare_city_landmarks.py`부터는 설치된 공식 Godot를 사용합니다. 기본 실행파일은 `/Applications/Godot.app/Contents/MacOS/Godot`이며 다른 위치는 `GODOT_BIN`에 실행파일 경로를 지정합니다.

```sh
.venv-data/bin/python tools/prepare_collision.py
.venv-data/bin/python tools/prepare_daehanmun.py
.venv-data/bin/python tools/prepare_palace_walk.py
.venv-data/bin/python tools/prepare_public_walk.py
.venv-data/bin/python tools/prepare_walkable_itinerary.py
.venv-data/bin/python tools/prepare_landmark_spec.py
.venv-data/bin/python tools/prepare_palace_landmarks.py
.venv-data/bin/python tools/prepare_city_landmarks.py
.venv-data/bin/python tools/prepare_routes.py
.venv-data/bin/python tools/prepare_pedestrians.py
.venv-data/bin/python tools/prepare_traffic.py
```

각 명령이 성공하면 다음으로 진행합니다. 기존에 준비된 지역 자료를 사용하며, 국가 전체 지도를 다시 받을 필요는 없습니다. [생성 순서와 의존성](docs/CROSS_MAC.md#v0-개발-자료를-처음-만드는-mac의-추가-준비)

</details>

준비를 마친 뒤 최신 탐험을 엽니다. 실행기가 로컬 지형을 준비하고 Godot 리소스를 가져옵니다.

```sh
sh tools/run_exploration.sh run
```

이후에는 `Sim2Seoul.command`로도 열 수 있습니다. 생성 캐시·개발 환경·앱 빌드는 Git에 포함하지 않습니다.

| 조작 | 키 |
|---|---|
| 걷기·달리기·점프 | **WASD / 방향키**, **Shift**, **Space** 새 입력마다 연속 점프 |
| 카메라 | **마우스** 회전 · **휠** 거리 조절 |
| 출입·시설·대여 | 대상 근처에서 **E** |
| 자전거·킥보드 | **W** 가속 · **A/D** 조향 · **S / Space** 제동 · **E** 하차/반납 |
| 버스 | 정차한 열린 문에서 **E** 탑승 · 탑승 중 **E** 다음 정류장 하차 예약 |
| 메뉴·장소 이동 | **Esc** → 도서관·옥상 풀·산책 구간·대여소 등 바로가기 |

## 검증은 어떻게 남겼나요?

최근 기능 실행은 **2026-10-20, Apple M5 16GB / macOS 26.6.2 / Metal 4 · Forward+** 환경에서 확인했습니다. 아래는 대표 결과이며 서로 겹치는 실행 검사를 합산하지 않습니다.

| 대표 시나리오 | 실행 결과 | 증거 |
|---|---:|---|
| 자전거 E 입력·접근·메뉴 복귀 | 그래픽 환경 **60/60** | [물리 키 이벤트 검사](data/reports/personal_mobility/20261020/bike_entry_native_final02.json) |
| 킥보드 주행·승하차·화면 | 그래픽 환경 **37/37** | [실행 보고서](data/reports/personal_mobility/20261020/scooter_native_final04.json) |
| 신호의 자연 두 주기·렌즈·메뉴 정지 | 그래픽 환경 **28/28** | [실행 보고서](data/reports/personal_mobility/20261020/signals_native.json) |

별도로 [실제 OS 키보드의 탑승·이동·제동](data/reports/personal_mobility/20261020/normal_launch.json)과 [최종 그래픽 화면 19장 검토](data/reports/personal_mobility/20261020/visual_review.json)를 기록했습니다. 위 결과는 기록된 날짜와 소스에 해당하며, 다른 Mac·배포판의 실행과 장시간 성능은 별도 확인 대상입니다.

```sh
# 저장된 코드·입력·증거의 일치 확인. 엔진을 재실행하는 명령은 아닙니다.
python3 tools/check_street_detail_handoff.py

# 이 Mac의 실행 자료까지 준비한 경우
python3 tools/check_street_detail_handoff.py --prepared
```

## 프로젝트 구조

```text
Sim2Seoul/
├── config/          # 조사 범위·좌표·공간 정책
├── data/
│   ├── raw/         # 확보한 지역 원천 자료
│   ├── manual/      # 수동 판단·제작 가정·참조
│   └── reports/     # 실행 결과·실패·화면·소스 해시
├── tools/           # GIS 전처리·생성·실행·검사 도구
├── game/
│   ├── assets/      # 제작 자산·외부 자산과 출처
│   ├── scenes/      # 공간·플레이 장면
│   ├── scripts/     # 지형·보행·실내·시설·교통 제어
│   └── shaders/     # 표면과 시각 표현
├── tests/game/      # 실제 Godot 장면의 검증 시나리오
└── docs/            # 설계 판단·사용법·개발 이력
```

## 개발 방향과 범위

현재 중심은 **덕수궁·시청 한 권역의 로컬 3D 탐험 프로토타입**입니다. 지형은 공개 자료의 보간이고 실내·시설·신호 주기·대여소는 게임 구성입니다. 정밀 측량 수준의 도시 복원이나 실제 교통·대여 서비스 연동을 의미하지 않습니다.

다음 확장 방향은 장소별 외형·생활 경험 보강, 대중교통 체험의 단계적 확장, 생활·꾸미기·주민 시뮬레이션입니다. 범위와 우선순위는 [현재 상태](docs/WORK_STATUS.md)와 [개발 계획](docs/IMPLEMENTATION_TASKS.md)에 기록합니다.

개발에는 Codex 등 AI 코딩 도구를 활용했습니다. 실제 플레이 피드백을 구현·수정으로 연결하고, 설계 선택과 실패·검증 과정을 저장소에 함께 남깁니다.

## 출처와 이용 조건

공간 자료는 OpenStreetMap·Overture Maps와 서울시 공개 지형 자료를 사용했습니다. Godot, Kenney CC0 모델 및 개별 자산의 고지는 [자료·자산 출처](docs/ATTRIBUTION.md)에 정리했습니다. 프로젝트 코드의 별도 배포 라이선스는 현재 지정하지 않았으며, 데이터·외부 자산에는 각각의 이용 조건이 적용됩니다.

---

[기술 설명](docs/ENGINEERING.md) · [문서 목차](docs/README.md) · [실행 이력](docs/EXECUTION_LOG.md) · [최신 검증 집계](data/reports/street_detail/20261020/summary.json)
