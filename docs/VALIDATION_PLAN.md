# 검증 계획과 완료 판정

## EXP12 — 연속 점프·옥상 도착 입력과 실제 이동 동작

[최종 요약](../data/reports/exploration_motion/20261016/summary.json): M5 Metal/Forward+ GPU60/60·headless54/54, 기본 점프24/24·공중42/42·옥상44/44·방문77/77·수영27/27 PASS. 최종 동작6장을 열어 확인했다. W 유지 도착/새 Space 거절의 전후 재현과 높이 제한 분리 진단은 development에 보존한다.

`check_exploration_motion.gd`에서 실제 E/승강기로 정원·풀·펜트하우스 옥상에 도착한 뒤 첫 점프와 6회 이상 연속 새 Space 입력을 확인한다. 기존 높이 상한을 넘겨도 잘못 복귀하지 않고 XZ·하단 낙하 복귀·물리 천장을 보존하는지 분리한다. 승강기 도착 때 유지된 이동키와 새 Space, 홀드 자동 점프 거절·메뉴/시설 사용 중립을 검사한다. 관절형 모델의 실제 노드 변환, 걸음/달리기의 반대 팔다리와 주기, 정지/벽/공중 자세·메뉴 정지, 물리 캡슐과 외부 충돌 보존을 관측한다. 최종 GPU/물리 판정과 소스 해시를 기록하며 과거 2회 점프 검사 결과로 현재 무제한 동작을 대체하지 않는다.

## EXP11 — 시설 사용의 실제 입력·진행·효과·안전 복귀

[최종 요약](../data/reports/facility_interactions/20261016/summary.json): GPU132/132·headless109/109·전수 지점10/10·안전 복귀/외부 이동17/17 PASS. 125동/1,205층의 사용 지점1,083개에서 캡슐/바닥 검사 각각7,479회, 대표 호텔/업무 건물의 실제 E·보행/승강기와 음식 감소·물줄기·기구/팔 변환·수치/메뉴/종료를 확인했다. 최종6장을 열어 검토했다. 전수 지점의 동작 완주나 실제 업장 서비스 판정은 아니다.

새 `check_facility_interactions.gd`로 실제 E 짧은 입력/홀드, 메뉴 정지, 식사 완료/포만감, 물줄기/청결 진행/정지, 운동 기구/소품의 시간별 변환과 기록, 사용 중 이동·점프 및 종료 후 중립을 확인한다. 너무 멀거나 다른 층/벽 뒤 설비의 거절, 안전 위치와 외부 충돌 보존, 리셋/건물 교체 정리를 검사한다. 대표 호텔과 다른 용도 건물의 실제 물리 입력/층 이동 및 GPU 화면을 분리해 기록한다. 모든 시설의 전 여정이나 장시간 성능으로 확대하지 않는다. 최종 실행 결과와 소스 해시·실패/수정 기록은 위 보고서에 보존했다. 합계 GPU192/headless404는 중복 회귀를 포함하며 11개 최종 보고서의 현재 소스 해시 불일치는0이다.

재현은 저장소 루트에서 기존 Godot 실행 형식의 `--script ../tests/game/check_facility_interactions.gd`와 `check_exploration_motion.gd`, `-- --automatic-probe --report=<절대 JSON 경로>`를 사용한다. 먼저 `--headless`로 검사하고 실제 Metal 검수에서는 뺀다. `check_facility_targets.gd`·`check_facility_faults.gd`는 별도 전수/고장 검사다. 검사별 임시 settings/quality JSON은 ignored cache로 옮겨 실행 증거와 분리한다.

작은 창 검사에는 실제 `RenderingServer.frame_post_draw` 뒤의 화면/UI 상태를 사용한다. resize 직후 물리 catch-up과 process_frame 시작 신호 사이에는 한 프레임 이전 prompt가 남을 수 있어, 렌더 전 표본을 실제 겹침으로 잘못 판정했던132개 중1건을 수정했다. 동일한 겹침 거절 기준은 유지했다. 일반 실행에서는 자동 검사 옵션을 붙이지 않아 창 전환 시 기존 일시정지를 유지한다. headless의 기존 macOS CA 경고는 스크립트/기능 실패와 구분한다.

## EXP10 — 용도별 시설의 실제 기하·동선·화면

[최종 요약](../data/reports/interior_facilities/20261016/summary.json)에 현재 소스·보고서 해시와 실행별 결과를 연결한다. **시설 GPU150/150·headless129/129**, 새 층 안내/승강기 **GPU78/78·headless71/71**, 기존 방문77/77·옥상 수영27/27 headless PASS다. 합계 GPU228/headless304는 중복 회귀를 포함한 실행 판정 수다.

전수 검사는 원본125동/1,205층의 기존32,660개 캡슐/2,410개 바닥 ray를 유지하고,860개 시설의 선언한 입구와 보행 구간을0.45m 이하 간격으로 표본화해21,372개 캡슐/21,372개 지지 ray를 추가한다. 시설 메타를 가진 실제 충돌 형상5,341개와 한글 glyph 표지1,615개를 관측한다. 노드 이름/자기보고만으로 장비 존재를 인정하지 않으며 시설별 필수 실제 형상·재질·한글판 가독성과 GPU MultiMesh의 위치/크기/세 회전축/primitive 종류를 대조한다. 대표5동68층의 GPU검사와 headless 전수 결과는 소스 해시가 일치해야 연결된다.

대표12시설은 물리 E로 입장하고 실제 승강기8회·시설 내부 보행을 수행한다. 샤워실 앞문→안쪽→복귀→탕의10경유점553물리표본을 확인했다. 초기 건물/촬영 배치는 명시한 시험 fixture이며 모든 시설을 연속 완주한 결과가 아니다. 시설14장과 UI/객실7장을 열어 검토했다. 근접2장은 정상 줌2m를 쓰며 spa는 실제 보행 종점을 유지한다. 일부 근접 시야의 캐릭터 가림은 남아 있고 모든 각도의 시각 품질 판정이 아니다.

초기 headless의8개 랙 누락은 실제 안전 배치와 생성 조건을 고쳤다. GPU01의4건 변환 누락은90도 회전의 IEEE `-0.000/+0.000` 문자열 차이였다. 정수 lookup 뒤 실제 위치0.2mm/세 scaled축0.02mm 이내와 메시 종류를 별도로 비교하며 회전 삭제·잘못된 크기·다른 primitive를 거절하는 순수 엔진 계약 검사도 보존했다. 실제 모델의 회전을 지우지 않았다. [실행 이력](EXECUTION_LOG.md)과 development의 초기 실패를 유지한다.

재현은 기존 공통 실행 형식의 `--script ../tests/game/check_interior_facilities.gd`와 절대 `--report`로 headless 전수 검사부터 수행한다. native는 `--headless`를 빼고 `--catalog-evidence=<같은 소스의 headless JSON 절대경로>`를 추가한다. 층 선택은 `check_lift_experience.gd`, 회귀는 `check_building_visits.gd`·`check_rooftop_swimming.gd`다. 음식 섭취·샤워/탕 부력·기구 작동·실제 시설 현황·장시간 성능·export·다른Mac 판정은 포함하지 않는다.

## EXP08·EXP09 — 승강기·추가 점프·옥상과 입수

2026-10-16 동결본의 [승차/점프 요약](../data/reports/lift_jump/20261016/summary.json)·[옥상/수영 요약](../data/reports/rooftops/20261016/summary.json). 실행별 **GPU162·headless439개 판정** PASS이며 중복 회귀를 포함한 합계다.601개 서로 다른 기능이나 여정으로 세지 않는다.

| 실행 | GPU / headless PASS | 실제 범위 |
|---|---:|---|
| 승강기 |76 /69|실제 문/카메라/승객·논리층 미분·메뉴·도착 차단/장거리,1152/640 선택창·키보드28층/옥상·3D29버튼/숫자/손잡이와7PNG|
| 옥상 |55 /44|125개 source-XZ/회전basis/외곽·원본692보존,456개 캡슐/지지 관측,대표3곳E/lift왕복·별도4가장자리21m/s/추가점프/난간위체공·복귀/문왕복·입수와11PNG|
| 수영 |31 /27|99접지표본계단→림→점프입수·실14이펙트메시/2파문·메뉴·부력깊이1m/안정구간변동약2mm·3m/s제한·Space탈출/기존deck착지·실내외해제와4PNG|
| 더블점프·기존점프 |— /39·24|공중1회·세번째/홀드/메뉴재충전거절·낙하/천장/포탈/복귀·기존높이|
| 기존방문·실내·속도·야외 |— /77·81·27·51|기존안전·계단·사람·입퇴장,125동/1,205층32,660캡슐/2,410지지ray,속도/외부벽/경계/설정|

옥상456회는 스폰=승강장인 고유125곳을 두 번 검사한250회,풀 입구/림14회,펜트하우스16곳 열린문192회를 합친다.125개 전체 시설 여정이 아니다. 대표 장면의 초기 배치는 명시한 fixture이고 실제 이동/E/GUI키·점프는 production제어다. 객실은 분리된 고정승객의 논리운행, 풀은 게임 부력이다. 실제 시설 현황·유체·모든 카메라/가구 사이 이동·사람 조작감·장시간 성능·export·다른Mac 검수로 확대하지 않는다. 최종22PNG를 열어 확인했으며 초기 실패와 시각 수정은 [실행이력](EXECUTION_LOG.md)과 각 development에 보존한다. 모든 보고서의 소스해시를 현재와 대조했다. startup해시가 없는 기존jump/야외 형식은 최종동결뒤 재실행하고 summary의동결소스/로그에연결했다.

저장소루트에서 `Godot --headless --fixed-fps 60 --path game --log-file /private/tmp/<name>.log --script ../tests/game/<script>.gd -- --automatic-probe --report=/private/tmp/<name>.json`으로 재현한다. script는 `check_lift_experience`, `check_rooftops`, `check_rooftop_swimming`, `check_double_jump`, `check_jump`, `check_building_visits`, `check_interior_identity`, `check_fast_exploration`, `check_exploration`이다. 실제GPU는`--headless`를빼고일반게임과동시에조작하지않는다. 사용자설정은격리한다. 아래EXP07은당시코드의이력이다.

## 앞선 실내 EXP07 — 용도·층별 기하와 한국어 디테일

2026-10-16 [최종 요약](../data/reports/interior_identity/20261016/summary.json)에 실행별 증거와 소스 SHA-256을 연결한다. 원본 평면 크기와 층수를 유지하면서 생긴 실내 가구 차이가 색상·문구만의 차이인지, 새 충돌 가구가 출입·계단·승강장·복귀와 중앙 통로를 막는지를 실제 엔진에서 검사한다. 아래 EXP06 이전 수치는 당시 결과로 유지한다.

| 실행 | 결과와 범위 | 증거 |
|---|---|---|
| 실내 정체성 headless | **81/81 PASS**. 125동·1,205층 원본 너비/깊이·층간/층수 유지, 캡슐 질의32,660회·바닥 ray2,410회에서 오류0. 8개 프로필 분류, 실제 새 가구 충돌체16,606개, 대표5종의 형상·층별 차이·한글 표지, 교회/주거/은행의 실제 가구 형상, 물리 E5곳·도서관 승강기/계단 하강·사람4명 이동/정지·외부692개 동일성·촬영시점의 실제 가구 투영/카메라 공간/정상 줌 범위 | [headless.json](../data/reports/interior_identity/20261016/headless.json)·[로그](../data/reports/interior_identity/20261016/headless.log) |
| 실내 정체성 GPU | **92/92 GPU PASS**. 대표5동·68층의 실제 MultiMesh 변환 읽기5회, production E·승강기·계단·보행자와 화면9장. 전체125동 검사는 반복하지 않고 같은 소스 해시의 위 headless 보고서를 검사기에 전달 | [identity.json](../data/reports/interior_identity/20261016/identity.json)·[로그](../data/reports/interior_identity/20261016/identity.log) |
| 기존 방문 회귀 headless | **77/77 PASS**. 기존 `check_building_visits.gd`의 출입·계단 왕복·승강기 선택/차단/취소·복귀·메뉴·위층 카메라/보행자와 외부 충돌 보존. GPU 캡처 판정을 포함한 과거82개와 구분 | [visits_regression.json](../data/reports/interior_identity/20261016/visits_regression.json)·[로그](../data/reports/interior_identity/20261016/visits_regression.log) |

### 검사 관측과 전수/대표 범위

[check_interior_identity.gd](../tests/game/check_interior_identity.gd)는 headless에서 각 원본 레코드의 실제 방을 하나씩 만들고 제거한다. 모든 층의 스폰·승강장, 중앙 통로 양쪽의 깊이9점씩, 양 계단 접근점, 앞쪽 횡단 통로5점과 1층 출구에 반경0.30m·높이1.70m 캡슐로 실제 `intersect_shape`를 수행한다. 모든 층의 스폰/승강장 바닥은 별도 ray로 확인한다. 32,660회는 이 명시된 위치의 질의 수이며 전체 평면의 모든 위치나 모든 실내 경로 완주를 뜻하지 않는다. 보호 구간 밖 가구 사이의 모든 간격·모든 소품의 시각 겹침을 전수 판정한 것도 아니다.

고정 카탈로그의 분류 기대값은 `bank3/chapel3/civic6/gallery5/hotel9/library1/office97/residential1`이다. 대표는 서울도서관4층·신청사12층·서울파이낸스센터28층·더플라자호텔22층·정동1928아트센터2층, 합계68층이다. 도서관의 실제 서가·반납기·독서 책상, 공공 로비의 접수/상담·대기석·번호표, 업무 공간의 안내 데스크와 업무층, 호텔의 라운지와 3층 침대/객실 번호, 원본 `kind=civic`인 아트센터의 전시 패널/전시대를 직접 관측한다. 교회 긴 의자·주거 우편함·은행 창구는 headless의 추가 실제 shape 관측이다. `detail_counts`나 `features`의 자기 보고만으로 차이를 인정하지 않으며 실제 충돌체의 shape 크기·XZ 위치를 층끼리 비교해 노드 이름만 바꾼 복제를 구분한다. 한국어 표지도 실제 새 Label3D 내용을 읽으며 기존 층수/엘리베이터 글자를 새 디테일로 합산하지 않는다.

headless dummy renderer는 실제 GPU MultiMesh 변환을 읽을 수 없으므로 대표5곳의 읽기를 `deferred_checks`에 보류한다. native 실행은 각 배치의 실제 변환을 읽고 `placements`의 위치·크기·basis와 대조하며, 원통/구형 장식 배치도 포함한다. GPU의 `--catalog-evidence`는 headless PASS·125동/1,205층과 모든 검사 대상 소스 SHA-256 일치를 요구한다. 같은 항목을 headless/GPU에서 반복한 수를 별개의 새 기능 수나 전체 동선 수로 합산하지 않는다.

### 실제 제어·화면과 한계

초기 배치와 촬영을 위한 위치 이동은 보고서의 `scenario_starts`에 명시한 시험용 순간이동이다. 입퇴장은 production 물리 E 바인딩의 짧은 눌렀다 놓기 이벤트이고, 도서관 승강기 이동은 실제 전환 controller를 거친다. 도서관 계단 하강은 경유점 사이의 순간이동 없이 실제 이동 입력으로 수행한다. 사람4명의 이동과 메뉴에서의 정지, 외부 원본 body/shape692개의 동일성을 확인한다. 이 여정은 125개 건물의 모든 층에서 E·승강기·계단을 각각 완주한 결과가 아니다.

최종 GPU 화면9장은 도서관 안내 로비·열람층·책/독서등 근접, 신청사 시민 로비, 업무 로비·실제 업무 프로그램층, 호텔 로비·객실층, 아트센터 로비다. 넓은 입장 시점은 유지하고 세부 촬영은 실제 접수대/책상/침대의 위치를 읽어 플레이어 옆에 놓이도록 조준한다. 일반 화면에서 선택할 수 있는 줌2m/4m만 사용하고 실제 카메라 overlap0·대상이 화면 안에 투영되면서 상단 안내 UI에 가리지 않는지를 검사한다. 실제 저장 이미지의 조도·천장/시야·가구 방향·한글 가독성은 파일을 열어 별도로 검토하며, 저장 성공만으로 외관 품질을 통과 처리하지 않는다. **92/92 GPU PASS** — 9장 모두 열어 검토했고 넓은 로비 코어·유리 파티션·열린 객실 베이의 차이를 확인했다. 실행 이력·최종 요약에 연결한다. 모든 카메라 각도에서의 가림·좁은 가구 옆 이동·사람의 전체 조작감·장시간 렌더 성능·export·M4/다른 Mac은 이번 판정에 포함하지 않는다. 책·반납기·번호표·커피 기기·게이트·객실 문 등 새 소품은 대부분 보기용이며, 표지가 존재한다는 이유로 실제 조작 기능을 제공한다고 보고하지 않는다.

[참조 manifest](../data/manual/interior_identity_references.json)의 공식 사진 관찰·텍스트 안내·과거/현재 용도를 구분한다. 사진 픽셀은 게임에 수입하지 않았으며, 가구와 층별 용도·칸막이·재질·치수는 원본 안에 맞춘 게임 해석이다. 실측 복원·현장 출입 권한이나 실제 현재 입주사를 검증한 결과가 아니다. EXP04 이전 사진은 해당 소스 버전의 비교 자료이며 같은 코드의 단일 설정만 바꾼 대조군이 아니다.

최초 [headless_01.json](../data/reports/interior_identity/20261016/development/headless_01.json)·[로그](../data/reports/interior_identity/20261016/development/headless_01.log)의 53개 중1개 실패는 같은 이름의 가구 sibling을 Godot이 자동 재명명해 2층 독서 책상을 세지 못한 관측 오류였다. 충돌을 끄거나 실제 가구를 옮기지 않고, 각 실제 body의 `geometry_id` 의미와 shape/위치를 함께 읽도록 검사기를 수정했다. 중간 `headless_02`의 53개 PASS는 캐시 개발 이력으로 남기고, 대표 전시관·특수3종·분류 기대값까지 추가한65개와 구분한다. 첫 [GPU01 보고서](../data/reports/interior_identity/20261016/development/gpu01/identity.json)·[로그](../data/reports/interior_identity/20261016/development/gpu01/identity.log)는 76/76 PASS였으나, 실제 화면9장을 열자 업무/호텔 가구가 멀리 벽에만 붙어 입구 중앙이 비어 보였고 가까운 촬영에서는 플레이어 외형이 디테일을 가렸다. [화면 검토 기록](../data/reports/interior_identity/20261016/development/review_notes.json)을 남기고 중앙 가까운 로비 구역·업무 파티션·호텔 객실 구획을 보강하며 촬영 방향도 실제 가구에 맞춰 수정한다. 첫GPU의 자동 판정 성공을 최종 시각 품질 통과로 대신하지 않는다. 새 충돌 가구가 생기므로 최종 headless/GPU를 다시 실행하고 위 결과행과 소스 해시를 갱신한다. headless의 기존 macOS 시스템 CA 조회 `Condition "ret != noErr"` 메시지는 기록하고 parse/runtime/physics 실패와 구분한다.

재현은 저장소 루트에서 아래 순서로 실행한다. 각 보고서 경로에서 별도의 탐험/품질 설정 파일을 사용해 사용자 저장 설정을 변경하지 않는다. GPU 검사는 일반 게임과 동시에 조작하지 않고 순서대로 실행한다.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --fixed-fps 60 --path game --log-file /private/tmp/sim2seoul-identity-headless.log --script ../tests/game/check_interior_identity.gd -- --automatic-probe --report=/private/tmp/sim2seoul-identity-headless.json
/Applications/Godot.app/Contents/MacOS/Godot --fixed-fps 60 --path game --log-file /private/tmp/sim2seoul-identity-gpu.log --script ../tests/game/check_interior_identity.gd -- --automatic-probe --report=/private/tmp/sim2seoul-identity-gpu.json --catalog-evidence=/private/tmp/sim2seoul-identity-headless.json
/Applications/Godot.app/Contents/MacOS/Godot --headless --fixed-fps 60 --path game --log-file /private/tmp/sim2seoul-visits-regression.log --script ../tests/game/check_building_visits.gd -- --automatic-probe --report=/private/tmp/sim2seoul-visits-regression.json
```

## 최신 출입구 안내 EXP06 — 원본 좌표·방향·물리 E

2026-10-16 [최종 요약](../data/reports/entrance_wayfinding/20261016/summary.json) 기준이다. EXP04의 125개 게임 문 좌표에 청록 문틀·정문/입구 표지·바닥 E를 연결하고, 150m 화면 방향/직선거리 안내와 120m 벽 표지의 표시를 검증했다. 가까운 5m 입구 우선·실제 조준 건물 우선·8m 안의 즉시 가림 검사와 원래 E 출입을 함께 확인한다. 아래 EXP05·EXP04 수치는 이전 실행의 증거로 보존한다.

| 실행 | 결과와 검증 범위 | 증거 |
|---|---|---|
| 안내 headless | 31/31. 125개 원본 외곽/지면 anchor·CPU에 준비해 renderer로 제출한 문틀/패드 좌표, 실제 100m 카메라 조준·거리·방향·후면/화면 밖·640×480 배치, 벽/바닥 글자 각 최대3개, 메뉴/실내 숨김, 도서관/일반 건물의 짧은 물리 E·먼 곳/가림벽 거절·안전 퇴장·원래 사람4명·외부692개/이름149개 보존 | [guidance_headless.json](../data/reports/entrance_wayfinding/20261016/guidance_headless.json)·[로그](../data/reports/entrance_wayfinding/20261016/guidance_headless.log) |
| 안내 GPU | 34/34. 위 31개와 실제 PNG3장 저장. 125개 문틀과 바닥 패드는 실제 GPU MultiMesh transform을 읽어 대조하며, 높은 카메라의 뒤쪽 화살표 방향과 내려다볼 때의 바닥 E도 확인 | [guidance.json](../data/reports/entrance_wayfinding/20261016/guidance.json)·[로그](../data/reports/entrance_wayfinding/20261016/guidance.log) |
| 벽 접촉 회귀 headless | 35/35. 실제 W 이동으로 문 중앙·좌우±1.8/±2.2m 벽 접촉 후 E, 짧은 물리 E 탭·유지 입력·먼 곳/가림벽/공중 거절·안전 복귀 | [contact.json](../data/reports/entrance_wayfinding/20261016/contact.json)·[로그](../data/reports/entrance_wayfinding/20261016/contact.log) |

실행별 판정 합계 **100건(GPU34·headless66)**이다. headless와 GPU의 공통 검사항목을 별개의 새 기능으로 세지 않는다. Godot headless dummy renderer의 `MultiMesh.get_instance_transform()`은 identity를 반환하므로 이 실행은 CPU 제출 좌표까지만 검사하고 실제 읽기를 `deferred_checks`에 남겼다. 최종 GPU 실행은 실제 MultiMesh 읽기까지 통과했다. 최종 보고서의 소스 해시는 현재 파일과 대조했다.

GPU와 [일반 실행 로그](../data/reports/entrance_wayfinding/20261016/launch.log)의 ERROR는0건이다. headless 안내/접촉 로그에는 기존 macOS 시스템 CA 조회의 `Condition "ret != noErr"` 메시지가 남았으며 script/runtime/parse 오류와 구분한다. 일반 창도 다시 띄워 실제 화면의 ‘초고속(3배)’ HUD와 새 입구 방향 카드를 확인했다. 이 화면 확인을 사람의 전체 출입·연속 보행 검증으로 확대하지 않는다.

[도서관100m](../data/reports/entrance_wayfinding/20261016/guidance_library_far_100m.png)·[정문 근접](../data/reports/entrance_wayfinding/20261016/guidance_library_near_door.png)·[일반 건물에서 화면 밖 입구 안내](../data/reports/entrance_wayfinding/20261016/guidance_generic_offscreen_near_door.png)를 실제 GPU로 저장하고 열어 검토했다. 화면 카드는 실제 카메라 투영을 사용하고 640×480에서도 화면 안에 들어오며, 뒤쪽 화살표가 아래를 가리키는지 확인했다. 높은 벽 표지가 화면 밖일 때 바닥 E가 별도로 남는지도 검사했다. 캡처는 `force_draw` 뒤 저장하며 과거 `frame_post_draw` 대기 문제를 반복하지 않는다.

초기 [headless_01.json](../data/reports/entrance_wayfinding/20261016/development/headless_01.json)의 30개 중6개 실패는 dummy MultiMesh 읽기와 카메라를 돌릴 때의 정상 대상 변경·근접 표식 투영을 잘못 가정한 시험 조건이었다. ID를 강제하거나 충돌을 끄지 않고 실제 ray·투영을 관측하도록 고쳤다. 이어 [headless_03.json](../data/reports/entrance_wayfinding/20261016/development/headless_03.json)은 31개 중1개 실패로, HBoxContainer가 직접 자식 화살표의 회전을 정렬 때 초기화하는 실제 표시 문제를 검출했다. 별도 Control 안에 화살표를 넣어 수정한 `headless_04`가 최종31개를 통과했다. 실패 JSON/로그와 최종 증거를 함께 보존한다.

재현은 저장소 루트에서 아래처럼 실행한다. 각 실행의 설정·품질 저장 경로는 `--report`에서 분리하며 사용자 설정을 바꾸지 않는다. GPU 실행은 일반 게임과 동시에 조작하지 않고 순서대로 수행한다.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --fixed-fps 60 --path game --log-file /private/tmp/sim2seoul-guidance-headless.log --script ../tests/game/check_entrance_guidance.gd -- --automatic-probe --report=/private/tmp/sim2seoul-guidance-headless.json
/Applications/Godot.app/Contents/MacOS/Godot --fixed-fps 60 --path game --log-file /private/tmp/sim2seoul-guidance-gpu.log --script ../tests/game/check_entrance_guidance.gd -- --automatic-probe --report=/private/tmp/sim2seoul-guidance-gpu.json
/Applications/Godot.app/Contents/MacOS/Godot --headless --fixed-fps 60 --path game --log-file /private/tmp/sim2seoul-contact.log --script ../tests/game/check_library_entry_contact.gd -- --automatic-probe --report=/private/tmp/sim2seoul-contact.json
```

시작 위치와 퇴장 위치는 명시적인 시험 배치이며 연속 야외 이동 경로가 아니다. 가림벽은 시야 차단을 재현하는 시험 물체이고, 물리 E는 production 키 바인딩의 실제 짧은 눌렀다 놓기 이벤트다. 실제 정문 측량·현장 출입·경로 탐색·125곳 모든 방문·사람의 전체 조작감·장시간 성능·export·M4 검수는 이번 판정에 포함하지 않는다.

## 최신 속도 EXP05 — 최대21m/s

[보고서](../data/reports/fast_exploration/20261016/summary.json) 기준으로 `check_fast_exploration.gd` headless27개, 기존 `check_exploration.gd` headless51개를 통과했다. 새 프로필 실제 거리와 대각선 정규화, 21m/s 원본 충돌·사유지/4면 경계·실내·계단, 메뉴/저장 호환을 검증한다. [원문](../data/reports/fast_exploration/20261016/speed.json)·[로그](../data/reports/fast_exploration/20261016/speed.log)·[기존 회귀](../data/reports/fast_exploration/20261016/regression.json)에 시험 배치와 관측값을 남긴다.

최초 실행의 세 실패는 차량이 가로지른 측정 경로, 중첩 소스 벽의 contact ID, 사유지 후보 탐색의 과도한 ray 제외 조건이었다. [개발 원문](../data/reports/fast_exploration/20261016/development/speed_before_fixture_fix.json)을 보존했고 실제 충돌이나 사유지를 끄지 않고 배치/관측을 고쳤다. 계단45표본 중34접지, 복귀/경계이탈0·2층접지완료다. 일반 창의 메뉴에서 쾌속5.60/14.0m/s를 확인했으며 이 네이티브 관측을 실제 키보드 거리·새 GPU 물리/성능 검사로 확대하지 않는다.

재현: `/Applications/Godot.app/Contents/MacOS/Godot --headless --fixed-fps 60 --path game --script ../tests/game/check_fast_exploration.gd -- --automatic-probe --report=/private/tmp/sim2seoul-fast.json`. 제한된 headless 실행의 macOS 시스템 CA 경고는 로그에 남겼고 물리/기능 실패와 구분한다. 아래 EXP04 GPU 수치는 이전 증거다.

## 최신 탐험 EXP04 — 실제 접촉 출입·다층·계단·승강기

2026-10-16 Apple M5·Godot4.7.2·Metal4/Forward+의 [최종 증거](../data/reports/building_visits/20261016/summary.json)다. 기존 EXP03의 anchor 순간이동만으로 실제 벽 접촉의 안정성을 보장할 수 없었던 한계를 추가 검사로 보완했다.

| 실행 | 실제 결과/범위 | 증거 |
|---|---|---|
| 건물 방문 | 82/82 GPU. 원본 크기/층수·125개 문·대표3곳 입퇴장, 도서관 실제 계단 왕복·사람4명·위층36카메라·층 선택·이동 중 메뉴/차단/복구·즉시 카메라·정문 바로가기·외부692개 동일, PNG5장 | [buildings.json](../data/reports/building_visits/20261016/buildings.json)·[로그](../data/reports/building_visits/20261016/buildings.log) |
| 벽 밀착 E | 35/35 GPU. 중앙/±1.8/±2.2m에서 실제 W로 벽에 붙어 E, 짧은 물리 E 탭·유지 E·막힌 실외 복귀·먼 누름·가림벽·점프 중 거절 | [contact.json](../data/reports/building_visits/20261016/contact.json)·[로그](../data/reports/building_visits/20261016/contact.log) |
| 기존 야외 회귀 | 51/51 GPU. 속도·바닥/경계·원래 충돌·개체 이동·정지/설정·작은 창·저장/복구 | [regression.json](../data/reports/building_visits/20261016/regression.json)·[로그](../data/reports/building_visits/20261016/regression.log) |
| 전체 실내 기하 | headless 125건물/1,205층/2,410개 지원/캡슐 지점 실패0, 최대 한 건물 body2,149; 별도 최소12×16m/3m층고·5m층고·실제 도서관의 총14회 층간 보행 | [geometry.json](../data/reports/building_visits/20261016/geometry.json), `check_interior_geometry.gd`·`check_interior_stairs_geometry.gd` |

GPU 합계168개이며 headless 기하 표본이나 이전 EXP03 수치를 중복 합산하지 않는다. 시작 배치/퇴장·승강장 시험 배치는 명시한 fixture 순간이동이며 계단 경유점 사이와 벽 접촉은 실제 이동이다. 실제 도면·현장 출입·125개 모든 경로 완주·장시간 성능·export·M4는 미검증이다.

수정 전 접촉 24개 중4개 실패를 [contact_before.json](../data/reports/building_visits/20261016/development/contact_before.json)에 보존했다. 실내 기하에서 층고3m의 다음 경사판 아래면 막힘을 얇은 평행 경사판으로 고쳤다. 최초 확장 GPU79개 PASS 후 독립 검토로 승차 화면의 메뉴 가림과 실패 복귀 카메라 피벗 갱신 누락을 찾아 수정했고, 메뉴 캡처와 즉시 복귀 검사까지 최종82개로 확인했다. 모든 최종 신형 검사에 기록된 소스 해시를 현재 파일과 대조했다.

재현은 저장소 루트에서 다음으로 실행한다. GPU는 headless 옵션을 빼며 실제 실행 시 현재 게임 창과 함께 중복 조작하지 않는다.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path game --script ../tests/game/check_building_visits.gd -- --automatic-probe --report=/private/tmp/sim2seoul-buildings.json
/Applications/Godot.app/Contents/MacOS/Godot --path game --script ../tests/game/check_library_entry_contact.gd -- --automatic-probe --report=/private/tmp/sim2seoul-contact.json
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --fixed-fps 60 --script ../tests/game/check_interior_geometry.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --fixed-fps 60 --script ../tests/game/check_interior_stairs_geometry.gd
```

일반 실행은 별도 `sh tools/run_exploration.sh run`으로 재기동해 창·Esc 메뉴·정문 바로가기 클릭과 도착을 확인했다. 이후 네이티브 W/E/층 버튼 검수는 앱 상태 변경으로 중단되어 자동 물리 E 검사와 직접 OS 여정을 구분한다. 최신 창은 열린 상태다.

## 후속 탐험 EXP03 — 사진 외형과 첫 실내의 실제 검증

2026-10-16 Apple M5·Godot 4.7.2·Metal 4.0/Forward+에서 [최종 결과](../data/reports/photo_realism/20261016/summary.json)를 기록했다. 원래 V0 및 EXP02의 과거 결과는 보존한다.

| 실행 | 결과와 범위 | 증거 |
|---|---|---|
| 사진 외형·도시 통합 | `check_photo_realism.gd` 59/59. 기존 실제 도시 점프/카메라/충돌/6차량과 200창·741대각부재·신규 텍스처·8932기와 끝·주광/품질·로비 초기화, 여섯 외형 PNG | [photo.json](../data/reports/photo_realism/20261016/photo.json)·[photo.log](../data/reports/photo_realism/20261016/photo.log) |
| 실제 실내 제어 | `check_interior_visit.gd` 56/56. 실제 E 입퇴장/키 유지·벽/원거리 거부·바닥 결손 rollback·걷기·천장 충돌·36카메라 각도·낙하 복귀·640×480 안내·정지/재개·실내 설정·모든 귀환 후보 막힘·메뉴 대한문 복귀와 즉시 카메라, 외부692동일/47실내body, PNG3장 | [interior.json](../data/reports/photo_realism/20261016/interior.json)·[interior.log](../data/reports/photo_realism/20261016/interior.log) |
| 기존 자유 탐험 회귀 | `check_exploration.gd` 51/51. 속도·영역·사유지/외부 충돌·설정/재기동·작은 메뉴·2보행자6차량 유지 | [regression.json](../data/reports/photo_realism/20261016/regression.json)·[regression.log](../data/reports/photo_realism/20261016/regression.log) |
| 별도 카메라 fixture | 7상황·8,450 보간 표본, 겹침·반전·비유한 좌표0. 메뉴 즉시 스냅 API 추가 후 재실행 | [camera.json](../data/reports/photo_realism/20261016/camera.json)·[camera.log](../data/reports/photo_realism/20261016/camera.log) |

GPU 합계166개다. Headless 실내52개 통과는 최종 표지 방향·정지 카메라 수정 전의 개발 이력이며 최종56개 GPU와 구분한다. 실내 천장 시험에서만 점프 목표를 잠깐4m로 올려 천장 접촉을 만들고 생산3m로 복원했다. 순간이동·가림벽·결손 바닥·귀환점 차단은 기록한 시험 fixture다. 실제 위치/치수 정확도·전체 연속 여정·장시간 성능·새 패키지·M4 인수를 뜻하지 않는다.

최초 실내 GPU 검수는 물리 판정32개 뒤 퇴장 사진의 조건부 `frame_post_draw` 대기에서 timeout됐다. 원문 [실패 보고](../data/reports/photo_realism/20261016/development/interior01_timeout.json)를 유지하고 검사기에서 명시 draw로 바꾼 뒤 최종56개를 통과했다. 텍스처 mipmap/약한 bump, 유리 앞뒤 깊이와 현판 위치를 실제 근접 사진으로 고쳤고 최종 `photo04`를 채택했다. [돌담](../data/reports/photo_realism/20261016/stone_wall_close.png)·[대한문](../data/reports/photo_realism/20261016/gate_close.png)·[정문](../data/reports/photo_realism/20261016/library_entrance.png)·[로비](../data/reports/photo_realism/20261016/lobby.png)를 직접 열어 확인했다.

별도 출력 경로로 재검사한다. 실제 GUI 검사는 하나씩 끝낸 뒤 다음을 실행하며 기존 증거를 덮어쓰지 않는다.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path game --script ../tests/game/check_photo_realism.gd -- --automatic-probe --report=/private/tmp/sim2seoul-photo-recheck.json
/Applications/Godot.app/Contents/MacOS/Godot --path game --script ../tests/game/check_interior_visit.gd -- --automatic-probe --report=/private/tmp/sim2seoul-interior-recheck.json
/Applications/Godot.app/Contents/MacOS/Godot --path game --script ../tests/game/check_exploration.gd -- --automatic-probe --report=/private/tmp/sim2seoul-explore-recheck.json
```


## 후속 탐험 EXP02 — 2026-10-16 M5 실제 실행

사용자의 외형·높은 점프·건물 이름·차량 요청과 “시야를 돌리면 건물이나 지붕 일부가 사라지거나 잘려 보임” 설명을 대상으로 검사했다. 기기는 Apple M5/16GB, Godot4.7.2 Standard/Metal4.0/Forward+다. [요약과 원시 증거](../data/reports/seoul_detail/20261016/summary.json)는 이 탐험 개발판의 결과이며 아래 E–R의 과거 기기/장면/패키지 실행을 덮어쓰지 않는다.

| 검사 | 실제 결과와 판정 범위 | 증거 |
|---|---|---|
| 최신 도시 통합 | `check_seoul_detail.gd` GPU 49/49 PASS, 615tick/10.25물리초. 외형 9곳/돌담 3표시/장식 267개→6메시/재질16개, 지붕17surface의 양면 shader, 이름149개/실제 시청 ray, 최신 mask/지원면, 양 품질 far1400m를 대조 | [detail.json](../data/reports/seoul_detail/20261016/detail.json), [엔진 로그](../data/reports/seoul_detail/20261016/detail.log) |
| 기존 탐험 회귀 | `check_exploration.gd` GPU 51/51 PASS, 23.716667물리초. EXP01의 속도·대각선·야외3곳·네 경계·건물/담장 접촉·메뉴/중립·1152×720/960×600·설정 재시작/손상 복구와 2보행자/6차량 실제 이동 | [regression.json](../data/reports/seoul_detail/20261016/regression.json), [엔진 로그](../data/reports/seoul_detail/20261016/regression.log) |
| 점프 제어 | `check_jump.gd` 별도 headless 물리 fixture 22/22 PASS. 기본 3m의 실제 최고점3.000829m, 설정4m에서4.000314m. 접지 착지·누른 채 반복 없음·공중 추가/예약 없음·천장 접촉·공중 수평 속도·경계·메뉴/복귀 뒤 해제 latch 확인. 실제 도시의 입력/물리 점프는 별도 GPU 통합에서3.002864m/착지/반복 없음 확인 | [jump.json](../data/reports/seoul_detail/20261016/jump.json), [도시 점프 관측](../data/reports/seoul_detail/20261016/detail.json) |
| 카메라 충돌/보간 | `check_exploration_camera.gd` 별도 정적 fixture 7상황/보간 표본8,450개에서 overlap·비유한값·축 반전0. 열린공간/벽/모서리 회전·최저/최고 pitch·공중 추적/문 상부를 확인. 최저 눈높이0.2154m, 열린공간 점프 최대 추적 step0.1311m. 모서리 최대3.1564m 즉시 축소는 충돌 회피 동작으로 보존. 실제 도시는 별도 GPU12고정 yaw의 sphere 겹침0/유한값/지면 위와 단일 변환 게시/렌더 갱신 확인 | [camera.json](../data/reports/seoul_detail/20261016/camera.json), [도시 카메라 관측](../data/reports/seoul_detail/20261016/detail.json) |
| 충돌 보존 | 외형 helper 적용 전후 모든 충돌 객체·shape instance/resource ID·layer/mask·활성 상태의 동일성 확인. 실제 도시 GPU에서는 원천685개(활성682)+활성 조각5개=기존687을 별도로 검사하고 원천 shape 형식과 backface collision 유지 확인. EXP01 바닥과 N03 도로 지원체는 별도 집계 | [identity_probe.json](../data/reports/seoul_detail/20261016/identity_probe.json), [detail.json](../data/reports/seoul_detail/20261016/detail.json) |
| 차량 | 총6대의 고유 route key·layer8/mask31·실제 누적거리 증가·메뉴 정지/재개 확인. 두 원래 도로선과 사람 우선/FIFO 제어를 사용하며 신규차4대의 초기 배치를 명시 | [detail.json](../data/reports/seoul_detail/20261016/detail.json), [8actor 이동 회귀](../data/reports/seoul_detail/20261016/regression.json) |

GPU 검사는 합계100개이며 합성 점프22개·카메라7상황은 별도다. 모든 검사는 물리 입력을 격리하고 시험용 초기 위치/카메라 배치를 기록한다. 실제 도시 한곳의 점프나 12고정 yaw를 연속 전체 동선 완주로 설명하지 않는다. 충돌 fixture 통과를 모든 도시 가림/주관적 조작감 개선의 보장으로 확대하지 않는다. 같은 개발판의 장시간 성능·내보낸 앱·M4·사진 일치도와 사용자의 최종 외형 만족도는 이번 판정에 포함하지 않는다.

실제1152×720 viewport PNG를 열어 [대한문 정면](../data/reports/seoul_detail/20261016/gate_front.png), [석재 돌담 근접](../data/reports/seoul_detail/20261016/stone_wall_close.png), [시청/서울도서관 대비](../data/reports/seoul_detail/20261016/city_hall_library.png), [가까운 기와 경사면·처마](../data/reports/seoul_detail/20261016/gate_roof_underside.png)를 확인했다. 마지막 파일의 이름은 검사 fixture ID이며 그 사진만으로 지붕 뒷면 가시성을 판정하지 않는다. 지붕 양면 적용은 위 코드/GPU 검사의 근거다. 캡처용 카메라와 플레이어는 분리 배치되어 HUD 거리가 캡처 카메라와 대상의 거리는 아니다. 최초 지붕 캡처의 가려진 위치와 이름 갱신 대기 부족은 fixture 위치/대기를 고쳐 재촬영한 개발 이력으로 구분한다.

같은 버전 엔진과 준비된 최신 도시 입력이 있는 저장소 루트에서 아래처럼 별도 출력으로 재검사한다. GUI 검사 두 개는 각각 종료 후 다음 것을 실행한다. 기존 증거 파일을 덮어쓰지 않는다.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path game --script ../tests/game/check_seoul_detail.gd -- --automatic-probe --report=/private/tmp/sim2seoul-detail-recheck.json
/Applications/Godot.app/Contents/MacOS/Godot --path game --script ../tests/game/check_exploration.gd -- --automatic-probe --report=/private/tmp/sim2seoul-exploration-recheck.json
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script ../tests/game/check_jump.gd -- --report=/private/tmp/sim2seoul-jump-recheck.json
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script ../tests/game/check_exploration_camera.gd -- --result=/private/tmp/sim2seoul-camera-recheck.json
```

## 후속 탐험 EXP01

`tests/game/check_exploration.gd`는 새 장면의 실제 입력/물리로 속도·대각선 거리, 길 밖 도로·광장/잔디 세 장소의 접지·복귀 없음, 최대 속도 네 경계 정지, 원본 건물·담장 접촉, 동적 개체 이동/지원면 격리, 메뉴 입력 정지/중립 복귀, UI 신호·저장/재시작·손상 복구, 1152×720/960×600 메뉴 범위를 검사한다. 초기 배치는 시험용 순간이동으로 명시한다. [M5 실제 Metal GPU 결과](../data/reports/exploration/20261016/summary.json)는 연속 전체 동선·사진 수준 외관·성능/패키지·사람의 최종 만족도 판정과 구분한다. 원래 V0/W04의 고정 속도 검사는 유지한다.

E01에서 현재 M1의 엔진 기동, E02에서 정식 빈 프로젝트의 앱별 네트워크 차단 GPU 기동·역할/입력/메뉴·로컬 계약을 검증했다. [E01 증거](../data/reports/engine_startup.md)·[E02 증거](../data/reports/project_setup.md). E02 직접 키 조작은 화면 잠금으로 미실행이며 엔진 이벤트 자동 검증과 구분한다. E03에서 실제 서울 표시·구멍/법선/높이·엔진 정점 전달·별도 game 사본의 오프라인 GPU 기동을 검증했다. [E03 화면/증거](../data/reports/world_import.md). E04 고정 거리/10m 기준물/카메라 투영 비례도 [실제 검증](../data/reports/scale_view/README.md)했다. 현재 실제 보행의 자동 엔진 검수는 W04 절과 결과를 따른다. 직접 사람 조작/OS 포커스·3인칭 조작감·도시 성능·M4 검증은 미실행이다. 실제 결과는 WORK_STATUS와 `data/reports/`에 기록한다. 아래 수치는 구현을 시작하기 위한 **검증 제안**이며 실제 성능이나 측량 정확도의 주장과 다르다.

## V01. 자료 준비 — D01–D04

| 항목 | 방법 | 통과 기준 |
|---|---|---|
| 원본 무결성 | 공급자 체크섬·수신 크기·로컬 SHA-256 | 체크섬 일치, 오류 응답/부분 파일 아님 |
| 추출물 | 재파싱, 참조 node/way/relation 검사 | 사용 객체의 미해결 참조 0. 추출 방식 자체의 누락 가능성도 별도 기록 |
| 집계 | OSM 객체 유형별 수량과 미리보기 도형 수 분리 | 실제 건물 수·독립 자료 대비 누락률로 잘못 해석하지 않음 |
| 이름·범위 | 대한문, 중화전, 석조전, 돈덕전, 시청/서울도서관, 서울광장을 확인 | 이름 누락과 도형 누락을 구분. 필수 동선의 핵심 대상에 대응 객체 또는 보정 근거 확보 |
| 높이/층수 | 태그 존재율과 숫자·단위 유효성 별도 검사 | 실제값·층수 추정·기본값의 건수와 분모 기록 |
| 보완 자료 | 원본 파일·`.prj`·필드 정의·기준일 확인 | 포털 페이지 열람을 원본 수신으로 표시하지 않음 |
| 출처 | 사용 자산과 라이선스 목록 대조 | 데이터/모델/텍스처별 근거와 표시 문구 존재 |

이름이 없는 대상은 위치·형태·공식 안내로 매칭한다. 그 과정 전에는 “대한문이 없다”나 “데이터가 완벽하다”라고 단정하지 않는다.

## V02. 좌표와 기하 — G01–G04, E03–E04

- 원점과 조사 상자 모서리의 왕복 변환 오차 ≤ `1e-8`도.
- 대표 지점 3쌍 이상에서 투영 거리와 WGS84 측지 거리 차이 ≤ `0.2%`. 이는 변환 구현 검사이며 원본 위치 정확도의 보장이 아니다.
- 지역 좌표를 Godot에 전달한 뒤 거리 오차 ≤ `0.05m` 또는 `0.1%` 중 큰 값. 메시 눈대중만으로 판정하지 않는다.
- 동쪽 점은 +x, 북쪽 점은 -z, 위쪽은 +y. 10m 기준물을 함께 검사한다.
- G01은 투영 격자의 동/서/북/남 10m 및 로컬 위 10m 합성점을 검사하고, 측지 동/북 10m는 주축 부호를 검사한다. 격자·측지 방향 차이 때문에 교차 성분을 0으로 강제하지 않는다. 투영 평면과 로컬 방위각/거리는 같아야 한다. E04에서 실제 Godot 5방향 기준물·큐브·정점/선의 위치·변환을 0.05m 내로, map 정사영의 논리 픽셀 투영을 0.05px 내로 검사했다. 원본 외곽 정점의 직선거리이며 출입구 간/보행 거리가 아니다. 정상 209개·실제 오류 10종·자료 거부 11종·반복/재생성 포함 계약 36개 통과. [E04 증거/재현](../data/reports/scale_view/README.md).
- 빈/비유효 도형 0 또는 근거가 기록된 제외 객체. 제외 객체가 필수 보행 동선을 끊으면 단계 실패.
- 건물 중복·중정 채움·뒤집힌 면·부품 높이 중첩 목록을 확인한다. 건물 하나를 두 번 세웠는지 지정 시점에서 대조한다.
- 중심선·보도·차로·담장 면의 겹침을 검사한다. 대한문 밖/안 지면 높이, 문 폭, 석조전 앞 접근로와 광장 연결이 핵심 점검 대상이다.
- 원본 좌표를 5개 이상 대표 대상에 표시하고 공식 자료와 비교한다. 독립된 기준 좌표를 확보하지 못한 경우 외부 위치 정확도는 “미검증”으로 남긴다.
- 자동 재생성 두 번으로 ID·기하·높이 결정 결과가 같고 수동 보정이 유지되는지 검사한다. 생성 시각 같은 비결정 필드는 비교에서 제외한다.
- G03은 원문 단일값/다중 보류·추정 가정·상단/하단/수직 길이·근거 상태·단순 본체/참조·지면 예외·전체 주변 면/구멍·결정 기록의 일치를 검사한다. 변형 입력은 지정된 검사가 거부해야 한다. 실제 부분 메시의 수직 중첩·측량 높이·지면 형상·통행은 분류 검사 통과만으로 완료 처리하지 않는다. [G03 결과](../data/reports/height_review.md).
- G04는 모드별 접근 우선순위·조건/금지·원문 node/member 제약·폭 추정·원문 면 구멍·버퍼·차량 방향·2D 연결·gate 증거·경계/사유지/권한·겹침 목록을 대조한다. R1/R2/R3 원문 후보 연결과 최종 물리 동선의 완주는 구분한다. 최종 폭/단차/문 개구부·면 내부 경로·차량 교차 제어·경계 충돌은 E/P/W/N 단계에서 실제 실행해 검사한다. [G04 결과](../data/reports/movement_review.md).

## V03. 캐릭터·카메라 — P01–P04

P01에서 충돌 지면·벽·시험용 문을 먼저 만든다. 아래 시험은 P 단계에서 이 독립 장면으로 검증하고, 실제 대한문·도시 구간 적용 결과는 W01–W04에서 다시 판정한다. P 단계가 아직 만들지 않은 실제 대한문 통과에 의존하지 않게 한다.

P01은 [실제 캡슐/시험장 검사](../data/reports/player_scale.md)를 완료했다. 캡슐 전체 높이/반경 1.70/0.30m, 외형/충돌 중심·부모 변환·활성 정적 구조 7개·개구부 1.20×2.20m·단차 0.15/0.30m·기준물·레이어/시작점·실제 overlap/ray를 확인했다. 정착 1초 뒤 GPU 실제 60.009초/3,600회 지면 접촉·정지 11개 그룹 통과, 가속 headless 10개·계약 15개·실제 오류 9종 감지도 통과했다. 발 접촉 ±2mm·전체 Y 범위/XZ 이동 1mm·수직 속도 0.001m/s를 기준으로 기록했다. 이는 아래 이동/문 통과/단차/카메라/복귀 시험의 완료를 뜻하지 않는다.

| 시험 | 조건 | 통과 기준 |
|---|---|---|
| 크기/속도 | 사람 크기 기준물, 평평한 직선 10초 | 계약 속도×시간 대비 거리 차이 ≤2%; 대각선 가속 없음 |
| 프레임 차이 | 가능한 환경에서 30/60fps 제한 비교 | 동일 시간 이동 거리가 위 허용치 내; 렌더 FPS와 물리 주기 기록 |
| 지면 | 정지 60초, 경사/보도 턱 이동 | 지속 낙하·진동·땅속 진입 없음 |
| 벽 | 정면·사선·모서리에서 걷기/달리기 | 시각적으로 벽 통과 없음; 관통이 발생하면 위치와 조건 기록 |
| 문 | 양방향 10회, 카메라 회전 병행 | 시험용 문 통과·벽 차단. W01 이후 실제 대한문에서도 통과 가능, 담장 통과 불가, 영구 고착 없음 |
| 카메라 | 문 아래·담장 옆·좁은 모서리·전각 기단 | 벽 내부 시점·검은 화면·심한 진동 없음; 플레이어 자기 충돌 제외 |
| 복귀 | 외곽 이탈·강제 낙하·재시작 | 확인된 시작 지면으로 복귀, 무한 낙하 없음 |
| 입력 | Esc/메뉴 열기와 닫기 | 메뉴 조작 중 캐릭터 이동 없음, 마우스 잠금 복구 가능 |

P02는 [실제 이동 증거](../data/reports/movement.md)로 위 속도/정지·벽6조건·문 양방향각10회·경사와 단차 진입 램프·복귀/입력 중립·메뉴 Actor 정지를 완료했다. 정상 headless302개와 실제 GPU 렌더30/60fps 각각35개·GPU60초 정지27개는 역할이 다르다. 렌더 frames/벽시계와 물리ticks/delta/벽시계는 별도 기록하고 실제/물리 시간 차이≤2%를 요구한다. 중력은 공중표본의−Δvy/Δt가9.8 대비1% 이내, 회전은 모든 표본이TAU rad/s 제한과 목표각에.01rad 이내임을 검사한다.

P02 이동 중 capsule-vs-axis-aligned box 거리의 수치 관통 허용은5mm이며 최대값과 경로를 기록한다. Convex 진입 램프는 이 box 계산에서 제외하고 실제 floor 접촉과 상승/하강 높이를 검사했다. 이는 실측 서울 표면 정밀도 허용이 아니다. 정지의 발±2mm/Y범위1mm 기준은 유지한다. 자동 계단 오르기·단차 측면 직접 진입은 확인하지 않았다. 문 시험에 카메라 회전 병행, 벽/문 가림·마우스 잠금은 P03 이후이며 V03 전체 완료로 표시하지 않는다.

P03는 [카메라 증거](../data/reports/camera.md)로 추적/회전·휠 거리/상하 범위·정적 구 탐색/자기 RID 제외·안전 확장·메뉴 native 잠금/재개·포커스 알림 주입·회전 병행 문 각10회와 램프/경사를 검증했다. Player 이동 후 arm 내부 탐색/최종 게시 순서를 기록하고, 모든 tick의 sphere overlap/near-corner ray hit0·pivot 오차≤2mm·거리상한 초과≤2mm·tick순서 불일치0을 요구한다. 보존10Hz표본에서는 camera sphere-vs-AABB와 near-plane 네 모서리/기저/추적축을 독립 재계산하며 모든 tick의 집계와 구분한다. 가만히 벽 옆3초의 거리범위≤5mm, 공간이 열린 후확장≤6m/s/2초내4.5m도 검사한다.

실제GPU30/60fps에서 물리/벽시계 시간차이≤2%와 렌더 frames/time을 따로 검사했다. 자동headless의 native mousemode0/모의 잠금 의도와 GPU의 native captured2/visible0을 구분한다. 근접 Visual 숨김1.5m/재표시1.8m는 임시 몸체 가림 완화이며 전신 상시 표시나 모든 벽 배치/화면비·사람 조작감 보장이 아니다. 실제 도시 대한문/담장과 세 동선·실제 OS 포커스 전환·M4·도시 성능은 후속으로 남는다.

P04는 [충돌 증거](../data/reports/collision.md)로 역할별 행렬·selected685/제외548·실제20,302삼각형/identity/hash·양면/구멍 보존, P03 카메라37사례+추가8접촉구간을 검증했다. capsule-vs-box 매tick 최대약2.175mm는 기존5mm 수치 기준 안이며 Convex/도시 전체 체적 검증으로 확대하지 않는다. 원천 선택44표면ray·24hole cap clear·8외부→건물 capsule stop은 다른 body를 제외한 질의다. 실제GPU30/60 시간 기준은 유지했고 첫30fps 지연 실패와 동일조건 재측정 성공을 함께 보존했다. 메뉴 실제 버튼 신호/합성 지면 복귀와 기술적 지원평면 ray는 headless 자동 검증이며 사람/OS 입력을 대신하지 않는다. 실제 대한문·담장/지면 연결·도시 보행·전체경로는 W01–W04에서 검증하므로 V03/V04 전체 완료로 표시하지 않는다.

## V04. 보행 중간 버전 W0 — W01–W04

MASTER_PLAN의 R1(궁궐), R2(도심), R3(돌담길)를 실제 엔진에서 각 1회 이상 왕복한다. W04 자동 입력/물리 관측 판정과 직접 사람 조작은 아래 W04 증거 범위에 따라 구분한다. 경로 파일에 체크포인트 좌표와 출처/보정 상태를 저장한다.

필수 조건:

- 대한문 밖에서 문을 통과해 경내 길·마당·전각 사이를 걷는다.
- 중화전 앞·석조전 앞의 확인된 접근 구간을 포함한다.
- 확인된 보행 연결로 서울광장·시청 전면에 도달한다.
- 확인된 돌담길 구간을 걷고 돌아온다.
- 지면 끊김, 필수 동선을 막는 충돌, 복구 불가능한 고착, 낙하, 카메라 관통이 없다.

검증 영상 또는 주요 체크포인트 화면과 시험 로그를 남긴다. 화면 하나, 게임 창 기동, 자동 이동 명령 성공만으로 완주를 대신하지 않는다. 게임 조작 도구가 없으면 사용자가 직접 검수할 수 있는 패키지와 경로 체크리스트를 제공하고 해당 시험을 미실행으로 표시한다.

실내가 미정이라는 이유로 경내를 빼면 실패다. 확인되지 않은 가상 횡단로로 완주했다면 실제 배치 보행 검증은 미완료다. 핵심 기능 실패를 “알려진 제한”으로 바꾸어 W0 완료 처리하지 않는다.

## V05. 랜드마크와 도시 움직임 — L01–N04

- 대한문·전각·석조전·시청이 지정 시점에서 구별되고 원래 위치·크기 범위를 유지한다. 같은 일반 상자에 이름만 붙인 것은 핵심 랜드마크 표현 완료로 보지 않는다.
- 모델 교체 후 V04 동선과 문/카메라 시험을 다시 실행한다.
- 보행자와 차량을 모두 켜고 10분 관찰한다. 각 개체는 최소 2회 순환하도록 경로 길이와 관찰 시간을 조정한다.
- 건물/담장 관통, 차량의 궁궐·광장 보행면 진입, 플레이어의 영구 고착, 눈앞에서의 비정상 재생성은 0건이어야 한다.
- 경로 교차 정지·재개와 일시적으로 막혔을 때의 회복을 각각 3회 시험한다.
- NPC 0명/차량 0대로 시험하면 개별 기능 없는 상태를 성능 성공으로 잘못 보고하지 않는다.

L01은 위 구현 결과의 선행 명세만 검수한다. `tools/check_landmark_spec.py`로 대상/원천 ID·원본 도형/높이 분류/실측 미확인·공식 참조와 제작 판단·자료 시점/차이·기존 개구부/중화문/부모-부분·W04 보호 해시를 대조한다. 준비된 입력만 다른 폴더에 복사해 표준 Python 환경 차단 상태에서 두 번 동일 생성되는지 확인한다. 사진/모델 수입·렌더된 장소 인지·새 외형의 보행 회귀·M4 시험은 미실행으로 남긴다. [L01 기준/검사](landmark_reference.md). 새 외형이 없는 L01에서 GPU 전체 주행을 이유 없이 반복하지 않는다.

L02는 실제 엔진의 표시 배열/재질·원본 높이/도형 연결·전체 삼각형 포함·대한문3m 아래 통로·새 충돌0개·전체1,233메시/7조각 가시성을 별도로 검사한다. 정점의 float32와 법선의 uint16 octahedral 저장/복원을 독립 재현해 대조한다. 지붕 숨김·표시 변환·새 충돌·통로를 막는 시각 상자·원본 다시 표시를 실제 엔진에 주입하고 각각 관련 검사에서 거부해야 한다.

교체 전후 여섯 고정 카메라는 이름표를 숨기고 동일1152×720/조명으로 비교한다. 단차/기둥의 존재만으로 보인다고 판단하지 않으며 가림이 있으면 근접 렌더로 확인한다. 고정 시점은 보행 권한이 아니다. 별도 새 장면에서 W04 전체 여정을 실제로 다시 관측하고, frozen 검사와의 차이는 의도된 대한문 시각 가시성3개로만 한정한다. body/경로/침투/시간 판정은 유지한다. [L02 실제 관측·실패·범위](../data/reports/palace_landmarks.md). 사람의 장소 인상·조작감/OS·M4·현실 정확도·L03 도시 외형/L04 결합 검토·도시 성능은 별도로 남긴다.

L03은 도시4대상 전후·실제 GLB 원본/수정본·궁궐과 도심 결합 화면을 남긴다. 전체 삼각형 footprint/높이·float32 정점/재질·oct 법선·곡선 유리의 비선형 단면·창 반복/중앙부·광장 잔디/포장 분할과 전체1,233원본/7조각 가시성을 실제 엔진에서 검사한다. 원본 GLB를 별도 판독해 수정 면의 lineage도 대조한다. 표시 숨김/변환·충돌 추가·원본 복원을 실제로 주입해 관련 실패를 확인하고 lineage 변조는 별도 기하 검사에서 거부한다.

L03 장면에서 W04 전체 여정과 L02 외형 검사를 다시 실행한다. 원시 관측은 보존한다. frozen W04 비교에는 기존 대한문 표시3개만, frozen L02 비교에는 추가로 바뀐 도시 원본 표시4개만 되돌려 검사하며 각각 차이 목록을 남긴다. 물리/경로/시간 관측과5mm/2% 기준은 바꾸지 않는다. 다른 폴더에서 원본 모델·상대 PNG와 준비 자료만으로 두 번 같은 실행 자산을 생성해야 한다. 이는 새 Mac 설치/사람 인지·조작·정확한 현장 재현·도시 성능 시험을 대신하지 않는다. [L03 실제 결과](../data/reports/city_landmarks.md).

## V06. M1 Pro 성능 제안 — R01–R02

성능 측정은 출시 앱 또는 편집기 외 실행을 우선한다. 편집기 실행만 가능하면 그 차이를 기록한다. 해상도는 화면 논리 크기가 아닌 **실제 렌더 해상도**로 기록한다.

초기 비교 프로필:

| 조건 | A: 보행 기준 | B: 첫 버전 부하 | C: 선택적 추가 부하 |
|---|---|---|---|
| 해상도 | 1920×1080 | 동일 | 동일 |
| 보행자/차량 | 0/0 | 12/4 제안 | 24/8 제안 |
| 조명·그림자·시야 | 고정 설정 | A와 동일 | B와 동일 |
| 경로 | R1–R3 지정 카메라 경로 | 동일 | 동일 |

개체 수는 현실 유동량이 아닌 초기 시험 부하다. 초기 목표는 B에서 p95 프레임 시간 ≤33.3ms이며, 달성 여부를 측정해 채택/조정한다. 평균 FPS만 보고 통과시키지 않는다.

기록: 평균 FPS, p50/p95/p99 프레임 시간, 최대 멈춤 구간, CPU/GPU 프레임 시간(측정 가능할 때), 프로세스 메모리, 시스템 메모리 압력/스왑 변화, 시작 시간, 앱·자산 크기, 기기/OS/렌더러/엔진 버전. API가 제공하지 않는 수치는 추정하여 실측처럼 채우지 않는다.

30초 준비 후 같은 5분 구간을 2회 측정한다. 절전 모드·전원 연결·다른 무거운 앱·화면 배율을 기록한다. 20분 연속 실행으로 메모리 증가·발열에 따른 변화도 확인한다. 수치 목표가 미달이면 병목 하나씩 조정하고 같은 조건으로 비교한다.

저품질 프리셋에서도 실제 축척·필수 동선·기본 보행자/차량은 유지한다. M1 16GB가 기준이며 M4의 결과로 이를 대신하지 않는다.

R01 실제 측정 부하는 현재 안전한 고유 경로의2명/2대다. B12/4와 C24/8은 위 최초 제안으로 남기며 실행했다고 쓰지 않는다. A600초/B1200초·실제1080p와모든5분창/11단계·RSS를관측했고[기준 결과](../data/reports/performance_m1pro.json)를보존했다. GPU시간/온도는미관측null이며render완료간격과엔진process/physics관측을서로다른값으로기록한다. CPU/GPU원인분리가안된것을가상의병목으로대신하지않는다.

R02는위실측의현재2/2부하에p95≤33.3ms를채택했다. 기본화면설정은바꾸지않고low0.75/그림자OFF를기능대안으로제공한다. 두설정의동일기하/actor·문왕복/카메라·중간실제설정·메뉴/복원/손상복구를[별도회귀](../data/reports/r02/summary.json)로판정했다. 새HUD/low의성능전후재측정은없으며속도개선이나최종앱FPS를보장하지않는다.

## V07. 패키지와 두 기기 — R03–R04

1. 앱 버전·파일 해시·자산 manifest 기록.
2. 네트워크 연결 없이 편집기 밖에서 기동.
3. 절대 개발 경로 없이 지도/자산/조작법/출처 표시가 로드됨.
4. V04와 V05 핵심 시험 실행.
5. 저장/설정 사용 시 재기동 후 복구 및 잘못된 저장 데이터 처리 확인.
6. M4 Pro의 RAM·GPU·OS를 확인하고 동일 해시의 앱으로 검사. 미접근이면 미실행.
7. macOS 실행 차단은 해당 앱/서명/아키텍처 문제로 진단. 시스템 전체 보안 설정을 꺼서 해결하지 않음.

## 결과 기록 양식

```text
작업 ID / 검증 ID:
실행일 / 수행 기기 / OS / 엔진:
입력 해시 / 설정 버전 / 앱 식별자:
명령 또는 실제 조작 절차:
예상 결과:
관측 결과 및 수치:
증거 파일:
판정: 통과 / 실패 / 미실행
해결되지 않은 문제와 다음 작업:
```

문서 계획 체크박스를 채우는 것과 시험 통과를 구분한다. 실제 결과의 단일 요약은 WORK_STATUS에 두고, 상세 로그는 링크로 연결한다.

## W01 연결 검증 기록과 남은 V04

[W01 증거](../data/reports/daehanmun_walk.md)는 실제 원문 연결 65.608m의 왕복 6leg, 문 각 방향 10회 camera 회전, 입구 앞뒤 좌우 차단 4구간, 정지·복귀/메뉴를 검증했다. 매 tick sphere/near query/floor/극값과 약 10Hz 독립 capsule/sphere-source 프리즘 거리·clip 면적/실제 face hash를 구분한다. 이동 5mm 수치 허용·정지 높이 범위 1mm·GPU 실제/물리 시간 2%·렌더 조건은 유지한다. 초기 판정 버전 혼재와 unplanned menu timeout은 보존했고 고정한 최종 도구로 재측정했다. 자동 입력 보호 helper는 일반 실행에 없고 OS 실제 입력/사람 조작/M4를 대신하지 않는다. 임시 치수/지면은 실측값이 아니다. W01 연결 완료로 전체 R1/R2/R3·V04/W0를 완료 표시하지 않는다.

W01 자동 GPU 판정은 12카메라 시점과 중립 정지의 준비 후 결과다. 측정 과정의 실제 이동/Shift 키 바인딩은 시험 프로세스에서만 제거하며 일반 `run`에는 그대로다. 기존 정지/관통/시간 허용치는 유지했고 초기 기동·첫 렌더링 끊김과 사람/OS 조작은 별도 검증이다. 준비 시간·pipeline count·입력 격리·최초 실패는 [W01 결과](../data/reports/daehanmun_walk.md)와 raw 기록에서 확인한다.

## W02 경내 연결 시험의 범위

[W02 기록](../data/reports/palace_walk.md)은 대한문 연결과 경내 원문 순환/중화전 앞마당의 경로 그룹 왕복, 문 양방향 회전, 10초 걷기/달리기, 60초 정지, 보행로·잔디·기단 구멍·석조전 계단 가장자리, 메뉴·복귀를 구분한다. GPU30은 짧은 9사례, GPU60은 전체 85사례를 측정한다. 원본 체적·실제 face hash·역할·몸체 수와 약 10Hz 독립 표본, 엔진의 매 tick 극값을 구분한다. 1tick짜리 짧은 굴곡은 경로 그룹의 실제/물리 시간 2%·렌더 20% 기준으로 판정하고 표준 속도/문/경계 구간은 개별 판정한다. 이동 5mm·정지 높이 범위 1mm 기준은 유지한다. 초기 경계 포함 오류와 수정 후 반복 증거를 함께 보존한다.

중화문·계단·실내를 피하는 출처 있는 대체 경내 경로이며 현재 현장 접근·실제 높이 검증이 아니다. W02 완료로 R2/R3·W04/V04 전체를 완료 표시하지 않는다. 사람/OS 직접 조작·M4는 별도 미실행이고 사용자 위임에 따라 자동 검증으로 현재 작업을 진행한다.

## W03 자동 장면 검증과 V04 인수 범위

W03은 R2/R3 전체 양방향 연속 이동(그룹 내부 teleport0), 담장 모서리 양방향,10초 속도·문 왕복·경계4종·메뉴/낙하/영역/수동/사유지 복귀·ray를 source 기하/actualbody와 대조한다. 정지1mm·이동/카메라침투5mm·GPU 실제/물리 시간2%·렌더20%의 기존 기준을 유지한다. 도로 접속은 source node/태그와 실제 그룹의 접속부 점유를 확인한다. source ring 순서와 node topology를 짝지어 잘못 해석하지 않는다.

GPU30은 짧은 marked/모서리 왕복·조작 시험, GPU60은 전체 R2/R3 및60초 정지다.16개 시점 준비·중립 정착 후 측정하고 cold startup/도시 성능 판정과 구분한다. 고정 도구/자료와 실제 고장6종·잘못된자료21종·prepared 입력 재생성을 함께 확인한다. [실제 관측과 실패](../data/reports/public_walk.md). 이 W03 자동 검사는 W04 전체 R1/R2/R3 통합 기록이나 직접 사용자의 조작감/OS focus·M4 결과를 대신하지 않는다.

## W04 자동 통합 검수의 증거 범위

V04 필수 동선을 새 W03 지원면 위에서 한 session의 물리 여정으로 검증한다. R1 양방향·중화전 앞마당 왕복·R2/R3 왕복·대한문 밖 복귀를 연속 기록한다. 입력 명령/기동/풍경 사진만으로 통과시키지 않는다. 원문 경로 구간과 실제 표본·전역 tick/이동량·도착 이벤트·물리/카메라 극값을 대조하고 필수 연결 실패를 허용하지 않는다.

W04 자동 엔진 검수와 직접 사람 조작감은 별도로 판정한다. 사용자 위임에 따라 사람 피드백은 진행 승인 조건이 아니지만, 사람/OS focus 검증을 미실행으로 표시한다. 전역 관측이 화면 저장 중의 물리 tick까지 포함해야 하며 순간이동·복귀0, 구간/단계 이음점 연속성·체크포인트 순서·기존 침투/시간 기준을 만족해야 한다. 새 입력이 없는 W03 static/source·이전30fps 증거는 동일 해시에서만 재사용하고 W04 GPU60 전체 여정은 새로 실행한다. 이것은 R01 도시 성능이나 M4 실측의 대체가 아니다. [관측·실패·결과](../data/reports/walkable_milestone.md), [직접 확인 안내](WALKABLE_CHECKLIST.md).


## L04 눈높이·가림·동선 회귀 판정

16개 지정 지점에서 이름표 없는 전후3인칭·눈높이 화면을 비교한다. 가까운 벽면이나 건물 뒷면만 보이면 기존 경로 안의 보충 시점을 추가하고 기존 화면도 보존한다. 주요 형태 대비는 내부 시각 검토로 판단하며 돈덕전·정관헌의 가림, 실제 장소 인상과 사용자 조작 미확인을 남긴다. 진단용 흑백 픽셀 수는 노출량만 뜻한다.

새 국소 시험은6개 기존 체크포인트의6초360도 회전, 대한문 양방향6구간, 광장 남측까지 왕복6구간이다. 시작점·도착점·이동량/시간·그룹 이음점과 실제 관측 tick을 계획에 대조한다. 매tick 지면/영역/침투/카메라 극값과10Hz 원시 표본을 구분하고 표본에는 원천 도형에서 독립 계산한 capsule/sphere/near-plane·이동 영역 검사를 적용한다. 기존5mm 침투/2% 실제 시간 기준을 유지한다. 정상 관측을 다른 시작점으로 복사하거나1tick 도착점으로 축약한 변조도 거부해야 한다.

실행 소스/자산/입력/기존 검사 SHA와 원관측/판정 SHA가 L03 합격본과 일치할 때만 과거3.3km 전체 결과를 재사용한다. 새 국소 시험을 새로운3.3km 완주로 설명하지 않는다. 외형의 실제 정점/높이/원본 표시/충돌은 도시58개·궁궐76개 frozen 검사로 대조하며 의도한 도시 표시flag4개 외의 원관측을 정규화하지 않는다. 새 Mac 설치·M4·직접 조작·실측 외관/현장 출입·도시 성능은 이 결과의 범위가 아니다. [실제 판정과 재현](../data/reports/landmark_review.md).


## N01 경로 계획의 정적 검증과 실제 동작 경계

생성기와 독립 검사기를 분리한다. 원문 누적거리 구간·XZ 오른쪽 miter를 별도 계산하고 전체 선/차체 띠·원천 방향/태그·모드별 영역·기존 모든 지상 건물/담장/사유지·경내·교차 누락/정지 여유·경로 간 분리를 대조한다. 점 표본만으로 전체 경로를 통과시키지 않는다. 출력의 역방향/좌표/NaN/hash/crossing/정지점/offset/domain/정책·범위/반복/차체띠 변조를 거부한다. 위험한 수동 정책·소수차로번호·오래된원천/출력도 별도 준비 사본에서 거부해야 한다.

공유 prepared 입력만으로 별도 폴더2회 동일 출력·폴더 이동·입력 불변을 확인한다. 이는 현재 설치의 N01-only 검사이며 새Mac설치/전체GIS/Godot/M4 검증이 아니다. 정상 출력2개는 검증용 gzip 스냅샷으로 공유하고 자동 가공물 자체는 Git에서 제외한다. 기존 game/config/manual/source/tools와 플레이어 경계를 유지했는지도 시작커밋과 대조한다. [실제108검사·거부·인수](../data/reports/route_review.md).

N01 계획의2NPC/2차량과1.2/5m/s는 초기 제안이다. 정적 검사로 실제 지지/접촉·제동 거리·점유/시야·반복/고착/성능을 통과시킬 수 없다. N02/N03은 각각 실제 왕복·정지/재개·상호 접촉, 차량 지지·확장 구역 진입 전 정지/사람 출현·FIFO·점유 해제·frustum/30m/빈진입 조건 반복과 눈앞 소멸0을 관측한다. N04의10분 이상/최소2주기·교차 정지/재개3회 요구는 유지한다.

## N02 왕복·회전·정지·접촉 검증

네트워크가 차단된 runtime-only 임시 복사본에서 실제 두 보행자를 실행한다. 280초 자유 보행에서 각 경로의 실제 위치/선 누적거리 표본으로 최소2왕복과 교대 끝점4회·정지 후 회전을 별도 계산하며 controller의 cycle counter만 믿지 않는다. 모든 물리tick의 개체수·수평step/속도·yaw·지면 접촉/높이·영역/침투를 관측하고, 10Hz 위치·속도·단계/끝점·플레이어 자료를 공유한다. 독립 checker는 원래 W03 선/전체 캡슐 지원 범위·원본 건물/담장과 지원면을 다시 대조한다. 전tick 요약과 저장 표본의 증거 수준은 구분한다.

정지2초/재개3초, 잠깐 막힘/비운 뒤 재개, 계속 막음/뒤로 회전·퇴각, 멈춘NPC에 플레이어 접근, 뒤로 빠진 뒤 전진, 실제 메뉴 SceneTree 정지/무이동·중복 생성 거부를 나눠 검사한다. case 사이에는 플레이어만 시험 위치로 옮기며 NPC의 위치·물리tick·누적거리는 계속 이어져야 한다. 실제 화면은60fps/물리60Hz·구간 시간 오차2%를 유지하고 캡처는 측정 구간 밖에서 찍는다. 표시 캡처에서 잠시 멈춘 보행자를 움직임 증거로 사용하지 않는다.

기존 정적 inventory 전체의 고정 digest와 실행 전후 동일성, 도시58개/궁궐76개 외형 검사도 유지한다. 새 두 경로의 동작/접촉 시험을 과거3.3km 동적 통합 완주로 설명하지 않는다. 실제 엔진의 NPC mask 결함과 저장 관측 변조·loader 자료 거부를 구분하여 보존한다. 다른 폴더 prepared 재생성은 새 Mac/M4 검사와 구분한다. 상세 기준/실패/재현은 [N02 결과](../data/reports/pedestrians.md)를 따른다. N03 차량과 N04 10분 이상 통합은 별도다.

## N03 차도 지지·차량·교차 검증

기존 N02 장면에서5m 간격92위치의 중심/차체4모서리460ray와 시작/중간/끝6개 전체 상자 낙하를 먼저 관측한다. 부족한 지지는 N01 차체 띠−기존 W03지원면 안에서만 차량용 바닥으로 추가하고 같은 시험을 다시 실행한다. production loader의 실제 두 바닥 layer16/mask8·identity/활성·float32 삼각형 SHA와 원래692/687 inventory digest는 별도로 대조한다. 바닥 추가를 사람 이동 허가나 실측 표고로 확대하지 않는다.

실제 engine19case의 전tick 요약과10Hz 저장 위치/회전·속도·지지·사람·점유/대기열·재배치 전후를 남긴다. 자유150초에서 두 차량의 원문 끝점 도달/정지·최소2회 반복을 실제 위치로 검산한다. 사람 점유55초/빈 상태0.8초/이후FIFO해제, 관측 중단/복원, 구역 내 사람 출현/이탈, layer4정지역할물체 앞 정지/제거 후 재개, 플레이어 실제 입력의 측면 접촉/탈출을 각각 확인한다. 두 실제 NPC선은 차도와 분리돼 있어 역할물체를 자연스런 NPC/차량 조우로 설명하지 않는다.

두 끝 전체 차체가 카메라frustum 밖인지6평면/8모서리로 다시 계산한다. 시야 안·사람30m 미만·진입 상자 점유를 각각 분리해 끝점 대기를 확인하고, 전부 해제한 뒤 최신tick guard·실제 정지/접지에서만 재배치했는지 검사한다. 메뉴SceneTree/이동 스위치·중복 생성 거부, 차량을 꺼 둔 동안 사람 관측/clear시간 초기화도 검사한다.

명령5.0002m/s·실제 위치 차분5.01m/s, tick당5/60m+1mm·누적거리/원문선 오차5mm·지면/침투5mm·실제 화면 시간2%를 유지한다. 실제 위치 차분 가속/제동의 float32 허용치는1.53/3.03m/s²다. 원래 도시58/궁궐76표시 및 사람 지지/경계/복귀0도 대조한다. 실제 collision_mask 결함1종, 저장 관측 변조5종, loader 자료 손상4종의 거부는 별개 증거로 보존한다. [N03 실행·실패·원시 자료·재현](../data/reports/vehicles.md). N04의 연속 필수 보행·10분 이상/각2주기/교차 정지·재개3회 기준은 그대로 남는다.

N04는같은2NPC/2차량·원문11단계/334구간의 실제도착·4회측면양보/원문선복귀와횡단3회/별도경내막힘회복3회를한전역시계에서검산했다. GPU94,883tick/1,581.406079실제초·전tick접지·pose/복귀0·NPC19/12왕복/차량31/24반복·headless396/GPU398독립검사를통과했다. 일반원문오차0.18m/검증된양보중1.05m·도착0.065m와기존지원/5mm/2%기준을구분한다. 실제2mteleport결함과5종저장변조의관련실패를확인하며, 최초proof갱신중실행은개발증거로남긴다. [N04실제관측·최초실패·판정·원시자료](../data/reports/urban_motion.md). 이것은실제1920×1080성능·독립앱·사람/M4시험을대신하지않는다.


## R03 실제 release 앱 재검증 규칙

정적 export 성공과 실제 앱 성공을 분리한다. 먼저 동일 ZIP을 저장소 밖에 추출하고 파일/권한/심볼릭 링크·PCK의 FileAccess 원문·universal2·ad-hoc 서명을 대조한다. 네트워크와 원본 저장소 읽기/쓰기를 차단하며, 외부 파일 읽기 성공/원본 읽기 거부를 실제 대조 시험으로 남긴다. 일반 실행은 V0 READY와 QA dispatcher 비발동을 확인한다.

품질 short phase는 두 품질·Esc/메뉴·복귀/스위치·출처·960/1152 배치·같은 저장 파일에서 새 장면의 품질 복원/손상 복구를 검사한다. 이것만으로 필수 여정 완료나 전체 R02 재시험을 선언하지 않는다. 별도 full phase에서 같은 release 앱의 standard/2NPC/2차량·원문11단계/334구간·횡단3회·NPC 막힘/회복3회와 기존 N04 독립 물리/도시/궁궐 기준을 그대로 적용한다. 실제 화면 시계·물리 tick·5mm/step·전tick 접지·복귀/pose0 기준을 낮추지 않는다.

최초 standard/no-resize0 및 최종 앱의 실제 PNG를 직접 열어 HUD/player 가림과 한글/출처를 확인한다. 화면 검사와 물리 검사는 서로 대신하지 않는다. OS 키보드·마우스/초점 전달, 사람 조작감, 타 Mac/Gatekeeper 최초 실행이 실행되지 않았으면 UNRUN으로 남긴다. 로그/캡처와 실패·중단 증거를 보존하고, 큰 raw JSON은 원문 바이트 SHA를 검증한 gzip으로만 보관할 수 있다.

## R03/R04 최종 기기별 판정

R03은 M1 실제 release 앱에서 package58·quality55·motion398·city58·palace76검사를 통과했고, 압축 raw 독립 재검산398검사와13PNG 직접 검토를 별도로 보존했다. [최종 패키지 증거](../data/reports/package_check.md). OS 입력/초점·사람 조작감과 전송 Gatekeeper는 미실행이다.

R04는 원래 미접근 대안으로 M4를 UNRUN 처리한다. 경로 adapter의29fixture검사와 실제 final ZIP/app·113source 검수는 M1에서의 바인딩 증거이며 다른 Mac 실행/성능 증거가 아니다. 원 manifest와 source/runtime SHA를 유지하고 실제 기기 사양·동일 품질/출력/전원·동일 시나리오로 재개한다. [M4 사양null/재개 조건](../data/reports/performance_m4pro.json)·[첫 버전 판정](../data/reports/first_version_acceptance.md).
