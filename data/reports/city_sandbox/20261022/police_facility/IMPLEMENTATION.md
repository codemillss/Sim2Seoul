# EXP28 경찰 시설·차량 확장 기록

2026-10-22 작성. EXP27 주먹·60초 추격·조사실의 후속 확장이다. WIP 체크포인트`69db9ca`와 이후`codex/real-scale-civic`의 새 작업을 구분한다. 이 문서의 headless 결과는 외관·청감·사용자 체감의 검증을 대신하지 않는다. 최종 화면/실제 OS 입력 검토와 Git 정리는 root 작업이다.

## 실제 원본 파출소와 새 게임 청사의 구분

원본 `data/processed/features.json`의 경찰 관련 원본은 정확히 두 개다. 세종로파출소(`osm:way:1215689854:building`,151.650m²)와 서울남대문경찰서 서소문파출소(`osm:way:847214800:building`,49.11m²)이며 남대문경찰서 **본서** footprint는 없다. 후보 원본은 `source_police_candidates.json`에 기록했다.

[서울경찰청 공식 세종로파출소 안내](https://www.smpa.go.kr/user/nd9096.do)의 기관명·주소는 서울 중구 세종대로141이다. 이 기관의 원본 위치·외곽·높이 proxy·충돌은 유지했다. 추가한 청색 간판, 석재·창틀, 캐노피·자동문·안내판·태극 색상 깃발과52m² 민원실은 게임용 설계다. 현재 실제 외관/실내 측량·현장 주차·운영 절차를 재현했다고 주장하지 않는다. 원본9m 높이는 실측이 아닌 기존 proxy다.

작은 파출소를 대형 경찰서로 늘리지 않았다. 사용자가 승인한 별도 게임 경찰청사는 북쪽 빈 지면XZ(−120,−420)에30×22m, 층고3.9m×4층=구조체15.6m로 추가했다. 외관의 `게임용 가상 경찰청사 · 실제 기관 위치 아님` 표시는 유지한다. 1층660m²는 벽·가구를 포함한 총 바닥 면적이고, 2~4층은 외관상 직원 업무층이다. 상층의 공개 출입이나 내부 운영 구현을 주장하지 않는다.

## 부지와 크기 검사

- 원본 세종로파출소 로비:8×6.5m=52m² inscribed rectangle, 원본 footprint 밖 면적0m². 정문 양문2.06×2.30m, 문틀2.20×2.45m, 로비 높이3.35m. detached authored room이라는 기존 실내 방식으로 E 출입한다.
- 새 청사 부지:40×30m reserve에서336개 원본 native/TIN 지원점 모두 존재, private/bounds 거절0, ground 높이 범위0.7724m,34×15×26m 사전 native 빈 공간 검사 접촉0. 원본 건물·barrier·highway line/area 교차0, 원본·게임 나무 중심4m 이내0. 원본 TIN을 평탄화하거나 지우지 않았다.
- SW(−400,390)는 일부 지원이 없어 거절, SW(−410,380)는3.99m 고도 차로 거절했다. 북측은 실제 학교·명명 공원·원본 건물 footprint를 덮지 않는다. 남동 건설 부지는 병원, 서측은 소방서로 별도 예약했다.
- 청사 입구:폭4m·길이7m의 실제 native 경사로, 높이 차0.28954m, 경사4.1363%. 원본 support/private/bounds75개 추가 표본을 통과한다.3.2×2.6m native 자동문을 E로 연 뒤 같은 world에서 직접 걷는다. 실내 teleport나 별도 입력 owner가 없다.
- 새 청사에는 안내데스크3곳, 대기석8개, 안내 kiosk, 상담 구역, 직원 전용 표시, 실내 조명, 현관과 창틀을 배치했다. 추가 정차 경찰차는 폭2.2×높이1.65×길이4.5m 충돌체로, 기존14대 traffic 배열에 들어가지 않고 정차 시 소리는 끈다.

## 실제 주행 순찰차

세종로 원본 인근의 비공개 아님·native 지면 지지·전체 차체 여유를 확인한 게임용 bay XZ(42,−430)에 추가 차량 한 대를 배치했다. 기존14대 AI 차량이나 원본 경로·배열·identity를 바꾸지 않는다. 흰 차체·청색/형광 띠·경찰/POLICE112·적청 경광등과 운전자가 보인다.

도로 원본은 세종대로37403012(양방향),620634303(남행 단방향),183272478(북서행 단방향)이다. 이 원본 방향을 따른263.043m 블록 순환과 낮은 속도 bay 후진/복귀를 게임용으로 작성했다.532개 밀집 표본에서2.20×1.65×4.50m 전체 native 차체와5×7 지면 표본/private/정문 setback을 사전 검사하며, 실제 이동마다 동적 사람·차량과 native body sweep을 다시 검사한다.

이 차량은 신고 시 실제로 출동하고60초 추격 종료/검거 후 물리적으로 bay에 복귀한다. 광역 자동 경로탐색이나 전 도시 자동차 추격 AI를 구현했다고 주장하지 않는다. 기존 네 명의 보행 경찰이 실제 체포·시야·거리 판정을 맡는다. 개별 순찰차의 차량 탈취/직접 운전은 제공하지 않는다.

## 발견한 실패와 수정

1. native preflight의 지면 RID 제외를 `query.exclude.append()`로 쓴 초기본은 getter 배열 사본을 수정해 실제 지면이 제외되지 않았다. 완성한 로컬 RID 배열을 한 번 대입하도록 수정했다. 접촉 mask/private/원본 충돌은 약화하지 않았다. `startup01~03` 실패를 보존했다.
2. 복귀 커브가 파출소 정문 setback을 침범해 source 검사에서 거절됐다. 복귀 커브를 도로 북측으로 옮겼다. source 조건 자체를 완화하지 않았다.
3. 정문 앞에 완전히 접지한 플레이어의 캡슐/지면 접촉을 장애물로 잘못 취급했다. 출입은 실제 `is_on_floor()`와2.5cm 위 전체 캡슐 여유로 확인하고, teleport 목적지 검증은 기존의 엄격한 캡슐·바닥 조건을 유지했다. `headless_dev02`의 실패와`dev03`의 실제 E 통과를 보존했다.
4. 민원실 안에서 detached 조사실로 전환할 때 일반 `end_interior()`의 외부 경계 보호가 목적지를 거절했다. root의 이미 전체 native 캡슐/바닥을 검증한 내부 custody flag에만 한정해 별도로 검증한 원래 외부 anchor에서 recovery owner를 해제하고, 같은 tick에 검증된 조사실 좌표로 전환한다. 보통 teleport에는 이 경로를 쓰지 않는다. 실제 E opening/inside 각각의 owner interruption→8/12초 release→stale callback 없음 검사를 추가했다.
5. 새 청사의 AnimatableBody 기본 `sync_to_physics`가 초기 문 위치를 가로채 native 문이 청사 원점에 놓였다. 실제 W가 닫힌 문을 통과하는 검사가 이를 잡았다. sync 설정을 parenting/배치보다 먼저 적용하고, native door 위치/진짜 입구 접촉 및 닫힌 문 W 차단 검사를 유지했다. `headquarters_headless_dev01~02` 실패와`dev04` 통과를 보존했다.
6. `headquarters_headless_dev03`은 소방서 개발 중 전체 장면 runtime 거절로1/2 실패했다. 이 결과도 지우지 않았으며 runtime 보호를 우회하지 않았다.

## 검증 범위

- `headless_dev03.json`: 파출소 출입·순찰차22/22. 실제 E opening/menu pause/walk/E exit/실패 목적지 owner 유지/정상 shortcut cleanup, 실제 native263m loop/roadblock 정지/자연60초 만료/복귀.
- `headless_dev04.json`: custody opening/inside interruption4개를 더해26/26. 이 네 검사는 owner 전환에 대한 명시적 내부 요청 fixture이며 실제 길거리 체포를 대신하지 않는다. 원본 성인 NPC의 실제 F·추격·검거는 별도 public-safety acceptance가 검증한다.
- `headquarters_headless_dev04.json`:15/15. 단 한 번의 공개된 player-only 외부 시작 외에는 W/S/A/D/E로 실제 native 경사로·닫힌 문·문 열기·로비 보행·외부 복귀를 검증한다. 문 상태나 플레이어 위치를 중간에 강제하지 않는다.
- 실제 순찰 이동 관측:263.038m, 최대 물리 tick 이동0.276m, 임시 실제 native 장애물 앞114 blocked ticks 후 진행 재개, 신고 후65.3게임초에 한 바퀴/bay 복귀.60초 신고 타이머를 강제로 바꾸지 않았다.
- 계속 유지하는 회귀 조건:원본 성인28명·개2마리·차14대 identity, 네 보행 경찰, 대여소16곳의 fixture/탑승 공간/8m 전방 출발 여유, F fresh edge/hold/menu, LOS/공중·고속 이동 체포 거절,8/12초 release 및 free-roam 복원.

새 검증을 돌릴 때는 저장된 결과의 source hash와 현재 파일을 비교한다. 이 디렉터리의 개발 실패본은 최종 성공 증거로 집계하지 않는다.

최신 구성 회귀: `headless_final01.json`26/26, `public_safety_real_scale_headless01.json`28/28 통과. `summary.json`에 현재 source 일치 여부와 파일/보고서 SHA를 기록했다. 새 청사15/15와 합쳐 현재 component headless69개가 통과했으며, 최종 native 분모는 파출소·순찰차29, 새 청사17, 기존경찰32이다. native 화면·OS 입력 수락은 아직 root 확인 대상이다.
