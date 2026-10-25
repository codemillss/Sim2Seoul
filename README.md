<p align="center">
  <img src="docs/media/sim2seoul-banner.svg" alt="Sim2Seoul — From spatial data to a walkable Seoul" width="100%">
</p>

<p align="center">
  <strong>지도 위의 서울을, 직접 걸어 들어가는 공간으로.</strong><br>
  덕수궁·시청 주변을 걷고, 상점·건물·옥상에서 이동과 생활 경험을 넓혀가는 3D 탐험 프로젝트입니다.
</p>

<p align="center">
  <code>Godot 4.7.2</code> · <code>GDScript</code> · <code>Python 3.14</code> · <code>GIS</code> · <code>macOS</code><br><br>
  <a href="docs/ENGINEERING.md">기술적 문제 해결</a> ·
  <a href="docs/RUN_GUIDE.md">실행 안내</a> ·
  <a href="docs/WORK_STATUS.md">현재 구현·검증</a> ·
  <a href="docs/README.md">문서 둘러보기</a>
</p>

## 브라우저로 체험하기

**[Sim2Seoul 웹 실행](https://sim2seoul-play-20261025-e7d4.rocky-lily-7307.chatgpt.site)** · 현재 소유자 전용으로, 배포한 ChatGPT 계정의 로그인이 필요합니다.

현재 도시 탐험 게임을 WebGL2로 내보냈습니다. PC 키보드·마우스 기준이며 첫 실행에 약141MB를 내려받습니다. 웹의 실제 도시·한국어 HUD·메뉴는 로컬 브라우저에서 확인했고, 배포 도구의 게시 성공 및 실제 주소의 로그인 화면을 확인했습니다. 인증 후 배포본의 연속 플레이·음향·저장 재접속은 추가 검증 대상입니다. [웹 실행 안내](docs/RUN_GUIDE.md#exp38-web-체험과-재생성) · [빌드·실패·검증 기록](data/reports/web_sites/20261025/README.md)

## 왜 만들었나요?

**지도에서 보던 서울을, 직접 걷고 들어가고 살아볼 수 있는 공간으로 바꾸고 싶었습니다.** 건물이 어디 있는지 보여주는 데서 멈추지 않고, 돌담길을 걷다가 상점에 들어가 옷을 고르고, 자동차로 이동하거나 헬리콥터로 도시를 내려다보는 경험을 연결하는 개인 프로젝트입니다. 장기적으로는 이 공간에 생활·꾸미기·주민 시뮬레이션을 쌓아가려 합니다.

그 과정의 핵심은 **공개 공간정보를 플레이 가능한 도시로 만드는 것**입니다. 실제 위치와 미터 축척을 유지하면서도 지면·문·계단·옥상의 높이가 이어져야 하고, 빠른 탈것에서 내려도 다시 안전하게 걸을 수 있어야 합니다. 지도 처리와 3D 상호작용을 하나의 환경에서 만들고, 실제 실행 중 발견한 문제를 고쳐가는 과정 자체가 이 프로젝트의 개발 주제입니다.

지향점은 **자연스럽게 몸으로 이동하는 도시와, 옷·시설·일상을 선택하는 생활 시뮬레이션의 연결**입니다. GTA와 The Sims의 경험 원칙을 참고하며 자체 기능을 구현합니다. [참조·RE 범위와 자산 도입 기준](docs/REFERENCE_DIRECTION.md)에 공식 자료와 이용 조건을 기록합니다.

### 왜 서울, 그중에서도 시청·덕수궁 주변인가요?

서울은 전통 건축과 현대적인 도시 생활을 같은 공간에서 경험할 수 있고, 많은 사람이 장소의 인상을 공유할 수 있는 무대입니다. 그중 **시청·덕수궁 주변은 작은 보행 권역 안에 궁궐과 돌담길, 서울광장과 공공건물, 업무용 빌딩과 상점이 함께 있습니다.** 한국적인 분위기와 서울의 스카이라인을 함께 표현하고 싶다는 초기 방향에 맞춰 이곳을 첫 구역으로 선택했습니다.

또한 서로 다른 공간을 연결하는 개발 문제를 한 구역에서 다룰 수 있습니다. 담장과 문은 통과·충돌을, 광장과 도로는 보행·교통을, 도서관과 빌딩은 실내·층·옥상 이동을 시험하는 장소가 됩니다. 익숙한 장소를 기준으로 삼아, 배치와 축척의 어색함을 실제 플레이 피드백으로 확인하기에도 좋습니다. 이 선택과 이후 범위 변화는 [프로젝트 맥락과 결정](docs/PROJECT_CONTEXT.md#왜-이-공간을-만드는가)에 남겼습니다.

## 새로 이어진 생활 경험

- 골반·다리의 연결과 발 접지를 유지하며, 어깨 회전·팔꿈치 굽힘·출발/정지까지 걷기와 달리기를 다듬었습니다.
- 몸·의복·손발·수영복·52본 스킨에 더해 남녀 얼굴·눈꺼풀·코·입술·턱·귀·헤어를 직접 조형했습니다. 피부색에는 자체 생성한 가상 인물 페인트를 사용합니다. Esc에서 남성형/여성형의 기본·통통·근육 체형과 피부·머리·옷·신발 색을 고르고 저장할 수 있습니다. [남녀 얼굴 제작과 실제 검토](docs/CHARACTER_IDENTITIES.md)
- 주먹을 쥔 전신 타격·밀기/방어 자세와 실제 성인 캡슐의 피격 반응을 연결했습니다. 폭행 신고 때 가까운 경찰이 실제로 접근하고, 잡지 못한 채60초가 지나면 포기·복귀합니다.
- 원래 도로 차의 정차·문 접근·운전자 반응·승차와 경적을 연결했습니다. [도시 액션 안내](docs/CITY_ACTION_FREEDOM.md)
- 서울도서관 열람석에서 **E로 앉아 공부하고, 다시 E로 일어납니다.**
- 야외 풀에는 바로 입수할 수 있습니다. 탈의·샤워는 선택 보너스를 주며, 저녁 조명 아래 바텐더에게 무료 무알코올 음료도 주문할 수 있습니다.

[조작과 실제 검증·남은 한계](docs/HUMAN_GAIT_AND_LIFE.md)에서 현재 범위를 확인할 수 있습니다.

## 얼굴·관절 원형 비교 · 2026-10-25

눈꺼풀·안와·코·입술·귀의 형태와 겨드랑이·골반 연결을 **편집 가능한 Blender 원본**에서 다듬고 있습니다. Esc 메뉴의 **인체 원형 비교 · 무채색**에서 새 원형과 이전 EXP36 원형을 같은 조명·재질·포즈로 비교합니다. **전체·얼굴·어깨·골반** 버튼으로 부위를 확대하고 정면·옆·뒤·45도에서 확인할 수 있습니다.

현재는 조형을 검토하는 원형입니다. 눈·귀·턱과 몸통의 인공적인 인상이 남아 있으며, 실사 인체나 연속 움직임의 완성을 뜻하지 않습니다. 일반 플레이 캐릭터는 유지합니다. 실제 화면에서 거절한 두 후보와 수정 과정도 함께 보존했습니다. [Blender 원본](art/characters/resident_form_m01.blend) · [현재 검사·실패 기록](data/reports/resident_face_joints/20261025/summary.json) · [제작 방식과 한계](docs/CHARACTER_IDENTITIES.md)

<details>
<summary>일반 게임에서 직접 연 새 원형 확대 화면</summary>

![일반 게임 창에서 마우스로 연 새 원형 얼굴45도 확대](data/reports/resident_face_joints/20261025/os/11_final_open_face_oblique.jpg)

</details>

## 플레이 화면

2026-10-17–24 개발판의 실제 Godot 실행 화면입니다. 첫 두 장은 일반 게임의 꾸미기 화면에서 직접 조형한 남녀 얼굴을 확대한 실제 OS 캡처입니다. 피부 제작용 생성 그림과 게임 결과를 구분하며, 현재 얼굴·헤어는 실사 완성품이 아닌 첫 자체 모델입니다. 실내·옥상 시설은 게임용으로 구성했으며, 각 화면에 캡처 날짜를 표시했습니다. 과거 날짜의 도시 화면에는 당시 캐릭터가 보입니다.

<table>
  <tr>
    <td width="50%"><img src="data/reports/character_identity/20261024/os_release06/male_face.png" alt="프로젝트 생성 코드로 직접 만든 52본 남성 캐릭터의 실제 Godot 표시" width="100%"><br><strong>직접 조형한 첫 남성 얼굴</strong><br>눈·코·입술·턱·귀·헤어 · 실제 꾸미기 확대 · 2026-10-24<br><sub>일반 게임 창에서 마우스로 얼굴 버튼 선택</sub></td>
    <td width="50%"><img src="data/reports/character_identity/20261024/os_release06/female_face.png" alt="자체 제작 얼굴·머리·의상을 가진 여성 캐릭터의 실제 Godot 표시" width="100%"><br><strong>별도 눈매·턱선과 단발의 여성 얼굴</strong><br>같은52본·세 체형/사복·수영복 연결 · 2026-10-24<br><sub>피부색은 자체 생성 페인트 · 실사/미형 완성은 후속 과제</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="data/reports/real_scale/20261022/hospital/hospital_native_final02_independent_full_height_hospital_exterior.png" alt="48×34m 외곽과 12층 주 외피를 가진 가상 종합병원의 실제 Godot 전경" width="100%"><br><strong>사람과 같은 미터로 만든 대형 병원</strong><br>12층 외피 · 실제 보행 공용1층/응급 접수 · 별도 관찰 카메라 · 2026-10-22</td>
    <td width="50%"><img src="data/reports/real_scale/20261022/acceptance/weather_fire_native_final01_initial_daylight_119_station_front.png" alt="3개 차고와 두 8m급 펌프차가 보이는 가상 대형 소방서" width="100%"><br><strong>도시의 공공시설과 실제 출동</strong><br>36×30m 청사 · 펌프차2대 · 방수/진화/복귀 · 2026-10-22</td>
  </tr>
  <tr>
    <td><img src="data/reports/real_scale/20261022/acceptance/police_headquarters_native_final01_full_scale_frontage.png" alt="거리와 같은 세계에서 걸어 들어가는 4층 가상 경찰청사" width="100%"><br><strong>문을 열고 걸어 들어가는 민원실</strong><br>30×22m 대형 청사와 별도 원본 세종로파출소 · 2026-10-22</td>
    <td><img src="data/reports/real_scale/20261022/hospital/hospital_native_final02_source_width_depth_and_gap_comparison.png" alt="1m 눈금과 사람 옆에서 건물 폭·추정 높이·이격거리를 비교하는 실제 게임 화면" width="100%"><br><strong>비율을 눈으로 확인하는 도구</strong><br>성인 인체 비례 · 건물 너비/깊이/간격 · 자료/추정 구분 · 2026-10-22</td>
  </tr>
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
  <tr>
    <td><img src="data/reports/city_life/20261021/acceptance/shop_native_final03_inventory_hoodie_actual_avatar.png" alt="가상 의류점에서 구매한 파란 후디를 실제 캐릭터가 입은 모습" width="100%"><br><strong>고르고, 사고, 갈아입기</strong><br>게임 상점·상의 3종·소지품 · 2026-10-21<br><sub>빈 통로의 명시적 의상 관찰 시점</sub></td>
    <td><img src="data/reports/city_life/20261021/acceptance/pool_native_final03_ordinary_pool_arrival.png" alt="옥상 수영장 앞의 탈의실과 샤워실, 중앙 통로" width="100%"><br><strong>수영 전 준비부터</strong><br>탈의·샤워 시설의 당시 화면 · 2026-10-21<br><sub>EXP33부터 준비는 선택 보너스</sub></td>
  </tr>
  <tr>
    <td><img src="data/reports/city_life/20261021/acceptance/car_native_final03_production_mount.png" alt="운전석에 탄 캐릭터와 도로 위 게임 자동차의 실제 실행 화면" width="100%"><br><strong>운전석에서 보는 서울</strong><br>자동차 운전·조향·제동·안전 하차 · 2026-10-21</td>
    <td><img src="data/reports/city_life/20261021/acceptance/helicopter_native_final03_airborne.png" alt="서울광장 위를 비행하는 게임 헬리콥터의 실제 실행 화면" width="100%"><br><strong>하늘에서 넓어지는 탐험</strong><br>헬리콥터 이륙·비행·착륙 · 2026-10-21</td>
  </tr>
</table>

## 무엇을 할 수 있나요?

| 경험 | 구현 내용 |
|---|---|
| **서울을 걸어서 탐험** | 대한문을 지나 덕수궁 경내·돌담길·서울광장·시청 주변을 이동합니다. 3인칭 카메라, 달리기, 연속 점프와 속도 선택을 지원합니다. |
| **건물 안과 위로 이동** | 126개 방문 대상 건물·1,242개 지상 게임 층에 용도별 실내·계단·승강기·옥상을 구성했습니다. 서울파이낸스센터의 게임 에스컬레이터는 1↔2↔3↔4층을 연결합니다. |
| **지하로 이어지는 탐험** | 시청역·을지로입구역의 원본 출구 위치에서 게임 지하역에 들어가 열차를 탑니다. 시청역 대합실에서는 서울도서관·서울특별시청의 게임 B1으로 이동하고 계단·승강기로 지상층에 올라갑니다. |
| **시설을 실제로 사용** | 가까운 설비에서 E로 식사·샤워·운동을 시작하거나 종료합니다. 게임용 옥상 수영장에서는 물에 들어가 수영하고 밖으로 나올 수 있습니다. |
| **직접 만든 캐릭터 꾸미기** | 남녀 기본형과 기본·통통·근육 체형, 피부·머리·상의·바지·신발 색을 선택하고 별도 로컬 설정에 저장합니다. 자체 인체 표면과 관절 연결을 다듬는 중이며 실사 완성 모델은 아닙니다. |
| **옷을 고르고 갈아입기** | 편의점·식당·가상 의류점에서 게임머니로 상품을 구매합니다. 세 가지 컬러 상의는 실제 텍스처 모델에 적용하고, I 소지품에서 다시 입습니다. 현재 원본 의복 형태를 공유하는 색상 변형입니다. |
| **자유롭게 수영하기** | 준비 없이 입수할 수 있습니다. 수영복은 수영 속도 +15%, 샤워는 청결 회복과90초 동안 +10%이며 함께 최대 +25%입니다. WASD 수영·Space 출수, 장소를 옮기면 입고 온 의상으로 돌아옵니다. |
| **직접 운전하고 비행** | 별도 주차 자동차·헬기 각 1대에 더해, 원래 주행 자동차 14대도 문 옆 E로 멈춰 빼앗아 운전할 수 있습니다. 내린 차에는 다시 탑승합니다. 헬기는 지면·지원되는 게임 옥상에 착륙하거나 공중 R 로프로 오르내립니다. |
| **근처로 부르는 킥보드** | 대여소가 없어도 안전한 야외 공공 길에서 Q로 세션 개인 킥보드 한 대를 부르고 E로 탑니다. 재호출은 같은 개체를 다시 쓰며 기존 8곳의 대여 재고를 유지합니다. |
| **신고와 경찰 추격** | 가까운 성인 NPC를 향한 F 주먹은 짧은 비유혈 반응을 만들고 반려견은 제외합니다. 명중·자동차 탈취 신고에 초기 권역 경찰14명 중 가까운2명이 실제로 접근해60게임초 추격하며, 붙잡히면 가상 조사실 8초 또는 유치장 12초를 거쳐 자동 귀가합니다. 별도 순찰차는 원본 도로 방향을 따르는 약263m 구간에 출동/복귀합니다. |
| **대형 병원·공공청사** | 미터 기준의 가상 종합병원·소방서·경찰청사를 외곽에 배치합니다. 병원/경찰청사는 실제 자동문을 열고 거리와 같은 세계의 공용1층으로 걸어 들어갑니다. 실제 세종로파출소는 원래 작은 외곽으로 별도 유지합니다. |
| **사람 비례·치수 비교** | 프로젝트에서 직접 만든 인체·스킨 모델을 적용하고, 3인칭 눈높이와 걷기/달리기·가감속·회전을 개선합니다. 선택형1m 눈금에서 건물의 동서/남북 폭·회전 외곽 긴/짧은 변·인접 간격과 자료/추정 높이를 비교합니다. |
| **거리 음향** | 실제 차체 위치·속도에 따라 엔진·타이어·사이렌·헬기·버스 문·비·방수를 재생합니다. 차량 음량/음소거를 따로 조절하고 두 대기차의 엔진은 꺼져 있습니다. |
| **비와 소방 출동** | 맑음·비가 반복되고 제한된 게임 화재에 8m급 펌프차 2대 중 한 대와 소방관 2명이 실제 출동·방수·진화·복귀하고 한 대는 대기합니다. Esc의 119 체험으로 바로 관찰할 수도 있습니다. |
| **달리기보다 빠른 탈것** | 8개 구역의 자전거 8대·킥보드 8대와 자동차·헬기의 전진 최고 속도가 선택한 달리기 속도에 맞춰 높아집니다. 초고속 설정의 최고 속도는 각각 33.6·42·52.5·84m/s인 게임용 이동입니다. |
| **함께 움직이는 탑승 화면** | 자전거·킥보드·자동차·버스·지하철·헬기에서 차체·탑승자·카메라의 표시 시점을 맞춰 떨림을 줄였습니다. 로프 하네스와 양 끝도 같은 시점을 따릅니다. |
| **기다리고 타는 대중교통** | 게임 버스 3대가 지도 안 약 812m·4개 정류장을 실제 순환합니다. 지하철은 지역 원본 선형에서 가져온 약 338m 구간을 연속 이동하며 승차·다음 역 하차를 지원합니다. |
| **거리의 생활감 관찰** | 사람 28명·반려견 2마리·기존 이동 자동차 14대와 상점 외관·버스킹·수목·가로등을 배치했습니다. 낮·해질녘·밤을 선택할 수 있습니다. |
| **구분되는 도로와 작동하는 신호** | 차도 위에 겹치던 보도 표시를 정리하고 이중 황색 중앙선·흰 차선·횡단부를 연결했습니다. 7개 횡단 구역의 차량 15개·보행 14개 신호는 46초 게임 주기로 전환합니다. |

기능·수량과 최신 실행 범위는 [현재 작업 상태](docs/WORK_STATUS.md)와 [EXP32 도시 액션·차량 집계](data/reports/city_action_freedom/20261023/summary.json)를 따릅니다. [EXP26 분산 대여](data/reports/mobility_distribution/20261022/summary.json)와 이전 검사는 당시 소스의 이력으로 보존합니다. 경찰·119 배치, 신고·조사/유치, 날씨·화재는 가상 게임 규칙입니다. 실내·B1·지하 연결통로·역 평면·운행 주기와 옥상 시설은 게임 구성입니다. 338m는 확보한 지역 선형의 범위로 실제 두 역 사이 전체 거리가 아니며, 실제 입주·지하 연결망·노선 운영을 복원했다는 뜻은 아닙니다. 차량의 최고 속도와 실제 정차·회피를 포함한 여행 시간도 구분합니다.

## 어떻게 만들었나요?

**Python은 공간 자료를 준비하고, Godot는 그 공간에서 실제로 이동하고 상호작용하는 경험을 담당합니다.** 원천 자료·추정·수동 보정을 분리해 지도 갱신과 게임 제작을 이어갈 수 있도록 구성했습니다.

```mermaid
flowchart LR
    A["공개 공간정보<br/>OSM · Overture · 서울시"] --> B["Python GIS<br/>좌표 · 도형 · 높이"]
    B --> C["Godot 3D 탐험<br/>지형 · 충돌 · 상호작용"]
    C --> D["플레이 검증<br/>물리 · 화면 · 직접 조작"]
    D -. 피드백 .-> B
```

| 기술적 과제 | 선택한 접근 |
|---|---|
| **지도와 게임의 축척 연결** | 위경도를 EPSG:32652 미터 좌표와 지역 원점으로 변환하고 **게임 1단위 = 1m**를 유지합니다. |
| **높이가 다른 공간의 연결** | 서울시 등고선 41개·표고점 96개를 보간하고, 동일한 지형 삼각형을 표시·충돌·높이 조회에 사용합니다. 기초 평탄화와 입구 연결은 별도 제작 가정으로 남깁니다. |
| **상호작용의 일관성** | 짧은 E 입력과 메뉴에서 누른 키를 구분하고 안내와 실제 동작이 같은 대상을 선택하게 합니다. 탈것·건물·역 사이의 제어권, 캡슐과 카메라 복원을 함께 관리합니다. |
| **속도와 안전한 이동의 연결** | 보행 설정에 맞춰 탈것의 가속·제동을 조정합니다. 빠른 이동에서도 경로 중간의 지지면과 연속 충돌을 검사하고, 열차·버스의 정차와 앞차 대기는 유지합니다. |
| **보이는 성공과 실제 성공의 구분** | 저장된 증거 대조, 엔진 물리 검사, 그래픽 화면 검토와 OS 키보드 조작을 구분해 기록합니다. 실패 사례도 수정 근거로 보존합니다. |

[E 입력·하차 충돌·지형·빠른 탈것·지하 연결을 구현한 과정 →](docs/ENGINEERING.md)

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
| 출입·쇼핑·시설·승하차 | 대상 근처에서 **E** |
| 소지품·갈아입기 | **I** · 의류점에서 구매한 옷 재착용 |
| 킥보드 호출·주먹 | 야외 보행 중 **Q** 호출 후 **E** 탑승 · 가까운 성인 NPC를 향해 **F** |
| 도로 자동차 탈취 | 실제 문 옆에서 새 **E** → 감속·정지 후 탑승 · 신고와 경찰 추격 시작 |
| 자동차 | **W** 가속 · **A/D** 조향 · **S** 제동/후진 · **Space** 제동 · 멈춘 뒤 **E** 하차 |
| 헬리콥터 | **Space** 상승 · **Ctrl** 하강 · **W/S** 전후 · **A/D** 회전 · 착륙 후 **E** 하차 · 공중 **R** 로프 하강/회수 |
| 자전거·킥보드 | **W** 가속 · **A/D** 조향 · **S / Space** 제동 · **E** 하차/반납 |
| 버스 | 정차한 열린 문에서 **E** 탑승 · 탑승 중 **E** 다음 정류장 하차 예약 |
| 지하철·지하 연결 | 출구 **E** → 개찰구 **E** → 계단으로 승강장 → 열린 열차 **E** · 시청역 대합실 연결문 **E**로 건물 B1 |
| 에스컬레이터 | 서울파이낸스센터 게임 실내 오른쪽, 층별 화살표를 따라 걸어서 탑승 |
| 메뉴·장소 이동 | **Esc** → 대형 병원·경찰청사·소방서·도로 자동차·119 출동 체험·역 출구 등 바로가기 |

## 검증은 어떻게 남겼나요?

최신 EXP33의 실행 범위·입력 해시·실패와 수정은 [실행 집계](data/reports/authored_character_combat/20261024/summary.json)와 [현재 상태](docs/WORK_STATUS.md)에 기록합니다. [EXP25 교통](data/reports/urban_transit/20261021/summary.json)·[EXP26 분산 대여](data/reports/mobility_distribution/20261022/summary.json)는 당시 결과입니다. 저장 증거의 일치, 엔진 물리, 그래픽 화면 검토와 실제 OS 조작을 구분합니다. 최고 속도 확인을 도시 전체 평균 이동 시간이나 장시간 성능으로 확대하지 않습니다.

아래는 **EXP24 당시 소스**의 상점·운전·비행·수영 준비 검사입니다. 2026-10-21, Apple M5 16GB / macOS 26.6.2 / Metal 4 · Forward+에서 실행했으며, 변경된 EXP33의 판정을 대신하지 않습니다. 서로 겹치는 검사 수를 고유 요구사항 수로 합산하지 않습니다.

| 대표 시나리오 | 실행 결과 | 증거 |
|---|---:|---|
| 상점·구매·의상·수영복·작은 화면 UI | 그래픽 환경 **75/75** | [실행 보고서](data/reports/city_life/20261021/acceptance/shop_native_final03.json) |
| 자동차 운전·충돌·안전 하차 | 그래픽 환경 **30/30** | [실행 보고서](data/reports/city_life/20261021/acceptance/car_native_final03.json) |
| 헬리콥터 이착륙·기체 충돌·회수 | 그래픽 환경 **34/34** | [실행 보고서](data/reports/city_life/20261021/acceptance/helicopter_native_final03.json) |
| 탈의·샤워·실제 수영·출수·의상 복원 | 그래픽 환경 **34/34** | [실행 보고서](data/reports/city_life/20261021/acceptance/pool_native_final03.json) |
| 상점·탈것·건물·옥상 간 소유권 전환 | headless **33/33** | [통합 보고서](data/reports/city_life/20261021/acceptance/integration_headless_final03.json) |

[EXP24 집계](data/reports/city_life/20261021/summary.json)와 [당시 대표 화면 15장 검토](data/reports/city_life/20261021/visual_review.json), [당시 일반 실행 기록](data/reports/city_life/20261021/normal_launch.json)을 함께 보존했습니다. 테스트의 물리 키 이벤트·유지 액션과 관찰자 배치는 실제 OS 키보드 체험과 구분합니다. 다른 Mac·배포판과 장시간 성능은 별도 확인 대상입니다.

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

현재 중심은 **덕수궁·시청 한 권역의 로컬 3D 탐험 프로토타입**입니다. 지형은 공개 자료의 보간이고 실내·시설·신호 주기·대여소·경찰/119·기상/화재는 게임 구성입니다. 정밀 측량 수준의 도시 복원이나 실제 교통·대여 서비스 연동을 의미하지 않습니다.

635개 원본의 너비·깊이·간격을 재투영/런타임 경계로 비교했지만 **479동의 기본 높이 등은 아직 추정**입니다. 원본 일치와 모든 실제 치수의 독립 실측 완료를 구분합니다. 새 병원·대형 청사는 사용자가 선택한 가상 게임 설계이며 위층 외피와 걸어 들어갈 수 있는 공용1층의 범위도 구분합니다. 캐릭터는 절차적 게임 모델/동작이고 GTA 자산·모션 캡처 품질을 뜻하지 않습니다. 개편 전 진행 중 버전은 [`codex/archive-before-real-scale-20261022`](https://github.com/codemillss/Sim2Seoul/tree/codex/archive-before-real-scale-20261022)에 보관했습니다.

다음 확장 방향은 장소별 외형·생활 경험 보강, 대중교통 체험의 단계적 확장, 생활·꾸미기·주민 시뮬레이션입니다. 범위와 우선순위는 [현재 상태](docs/WORK_STATUS.md)와 [개발 계획](docs/IMPLEMENTATION_TASKS.md)에 기록합니다.

개발에는 Codex 등 AI 코딩 도구를 활용했습니다. 실제 플레이 피드백을 구현·수정으로 연결하고, 설계 선택과 실패·검증 과정을 저장소에 함께 남깁니다.

## 출처와 이용 조건

공간 자료는 OpenStreetMap·Overture Maps와 서울시 공개 지형 자료를 사용했습니다. Godot, Kenney CC0 모델 및 개별 자산의 고지는 [자료·자산 출처](docs/ATTRIBUTION.md)에 정리했습니다. 프로젝트 코드의 별도 배포 라이선스는 현재 지정하지 않았으며, 데이터·외부 자산에는 각각의 이용 조건이 적용됩니다.

---

[기술 설명](docs/ENGINEERING.md) · [문서 목차](docs/README.md) · [실행 이력](docs/EXECUTION_LOG.md) · [최신 검증 집계](data/reports/human_presence/20261022/summary.json)
