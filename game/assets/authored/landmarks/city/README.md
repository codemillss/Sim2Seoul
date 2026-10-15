# L03 도시 외형

시청·서울도서관·서울광장의 표시 규칙은 `recipes.json`과 `tools/prepare_city_authored.py`에서 독립 제작한다. 주변 빌딩은 실제로 가져온 Kenney CC0 모델을 수정한다. 원본 모델·팔레트 PNG·CC0 문구·취득 해시는 `game/assets/vendor/kenney_city_kit_commercial/`에 보존한다. 수정본은 정확한 서울파이낸스센터 복제가 아니다.

`tools/prepare_city_landmarks.py`는 Godot GLTFDocument로 원본을 읽고, 현재 건물의 방향·높이 외곽에 비균일하게 맞춘 뒤 원본 footprint로 자른다. 면별 원본 삼각형 번호·barycentric 연결을 남겨 별도 검사기가 원본 GLB에서 역대조한다. 색을 세 가지로 줄이고 낮은 석재부·얇은 층 분할선을 추가한다. 원본 파일은 바꾸지 않는다.

시청 곡률·처마·창 간격, 도서관 부조, 광장 안쪽 0.6m 포장 테두리는 실측이 아닌 표현 가정이다. 광장의 2025년 목재 길/식재는 좌표가 확보되지 않아 추가하지 않았다. 지면 Y=0.017·광장 외곽·구멍·기존 높이 분류·충돌·보행 경로는 유지한다. 표시 면의 존재가 새 실내나 보행 권한을 만들지 않는다.

준비와 실행은 [CROSS_MAC](../../../../../docs/CROSS_MAC.md), 실제 비교·검사와 한계는 [L03 결과](../../../../../data/reports/city_landmarks.md)를 따른다. 생성한 실행 JSON/manifest는 Git에 넣지 않는다.
