## EXP36 인체 원형의 큰 면과 손발 · 2026-10-25

같은 성인 원형에서 흉근·흉곽 아래·배·장골·둔부와 대퇴/무릎/종아리의 큰 면을 다듬었다. 몸체의397개 제어점을 수정하고 기존829정점/794사각면·관절 위치·목/손목/발목 경계를 유지했다. [소스 비교 감사](../data/reports/resident_form_refinement/20261025/body_source_audit.json)는 순수 제어 좌표/위상 검사이며 실제 렌더나 미술 수용을 뜻하지 않는다.

손바닥의 두께/컵과 엄지 두툼한 면, 손등/손가락 관절·길이/굽힘을 나눴다. 발은 신발 모양 cap 대신 발등/발바닥 grid·실제 발목 입구·안쪽 아치·공유 web으로 연결된5개 발가락으로 작성했다. 머리는 코·볼·턱과 안와를 다듬고, 돌출된 안구를 얼굴 표면 안쪽에 넣었으며 좁은 입술 틈과 닫힌 구강을 연결했다. 여전히 인물의 표정/홍채·머리카락·세밀한 인체 면은 없는 무채색 검토 원형이다.

새 가중치 실험은 v01의 안쪽 대퇴가 골반에 남아 치마처럼 늘어나는 회귀와 v02의 팔올림 겨드랑이 능선 때문에 채택하지 않았다. 기본 shoulder/hip 귀속은 EXP35 방식으로 복원하고, 현재 cage의 실제 pose에서 LBS와 부피 보존 평가의 차 일부만 국소 보정으로 사용한다. 6/8/6mm bind-space 상한의 세 보정은 연조직 측정이나 사실적 근육 시뮬레이션이 아니다. 실제 export는 기존 LBS다.

이전 EXP35 v04는 원본 GLB/manifest를 그대로 보존해 네 자세·네 방향을 같은 카메라·조명·회색 재질로 비교한다. 실제 Blender 상세 렌더와 게임 화면·OS 캡처를 구분하며, 선택 v03의3,918제어정점·64,854내보내기정점과 현재 실행/실패는 [EXP36 집계](../data/reports/resident_form_refinement/20261025/summary.json)를 따른다. 제작용 외부 몸·스캔·모션·이미지 입력은 없다. [OpenStax의 구조 설명 참조](../data/reports/resident_form_refinement/20261025/reference_observation.json)는 독립적인 형태 조형의 참고이며 교재 그림/메시를 복사하지 않았다.

## EXP35 인체 원형 비교 · 2026-10-25

무채색 성인 남성 원형 한 명을 1.78m 기준으로 새로 제작했다. [편집 가능한 Blender 원본](../art/characters/resident_form_m01.blend)은 직접 작성한 제어 메시와 Subsurf를 유지하며, 수동 브러시 조각을 수행한 결과로 표현하지 않는다.
새 22본 골격과 총 3,270개 제어 정점으로 구성했다. 몸체는 829개 제어 정점의 사각면 cage이고, 머리·손·발을 별도로 직접 작성해 연결했다.
외부 인체·스캔·이미지 입력은 0개이며, 기존 주민의 SDF·정점·52본 위치를 재사용하지 않았다. 원본은 [새 제작 모듈](../tools/sculpted_character/)과 manifest로 추적한다.
Subsurf와 세 가지 자세 보정 shape를 사용해 A 자세·팔 올림·깊게 앉기·한발 지지의 네 자세를 검토한다. 자세 보정은 측정한 연조직 시뮬레이션을 뜻하지 않는다.
게임 메뉴의 ‘인체 원형 비교’와 [독립 검토 씬](../game/scenes/study/resident_form_study.tscn)에서 비교한다. 기존 생산 캐릭터 12종을 교체한 결과가 아니며 도시와 플레이어 충돌 캡슐은 유지한다.
목·손목·눈·발 pitch 및 촬영의 초기 실패는 [v01](../data/reports/resident_form_study/20261025/candidates/v01/)·[v02](../data/reports/resident_form_study/20261025/candidates/v02/) 이력으로 보존한다. [v03](../data/reports/resident_form_study/20261025/candidates/v03/)에서 제작 화면과 내보내기 분할 단계가 달랐던 점을 고쳐, 실제 자세 평가·화면·내보내기를 모두 Subsurf 2로 맞춘 [v04](../data/reports/resident_form_study/20261025/candidates/v04/)를 선택했다. 현재도 prototype 검토용이며 최종 미술 수용은 미완료다.
몸의 큰 면이 여전히 매끈하고 겨드랑이·고관절 형태도 단순하다. 신규 실행 검사와 수치 결과는 현재 검증을 묶는 [WORK_STATUS](WORK_STATUS.md)를 따른다.

재생성은 별도 후보 폴더에 출력한다. 공식 Blender4.5.15LTS의 `Blender` 실행 파일을 사용해 저장소 루트에서 다음을 실행한다. 게임을 실행할 때는 재생성이 필요 없다.

```sh
Blender --background --factory-startup \
  --python tools/sculpted_character/build_resident_study.py -- \
  --output-dir /private/tmp/sim2seoul-form-candidate \
  --render-dir /private/tmp/sim2seoul-form-candidate/blender_views
```

현재 기능 검사는 `python3 tools/run_resident_form_study_acceptance.py headless <새태그>`와 `native <새태그>`로 실행한다. 원본 인수 무결성은 `python3 tools/check_resident_form_handoff.py`로 확인한다. 검사 숫자가 미술 수용을 대신하지 않는다.

# 주민 얼굴·헤어 제작 기록

**EXP34 첫 남녀 모델 적용 · 2026-10-24 · 기능/방향별 검토와 최종 미술 수용을 구분**

서울을 걷는 주민을 프로젝트에 맞는 가상의 성인으로 직접 만들고 있다. 인체·얼굴·의복·헤어의 수치 모델링, 피부색 입력, 실제 게임 화면 검토를 구분해 기록한다. 현재 결과를 AAA급 또는 실사 인물의 완성품으로 평가하지 않는다.

## 무엇을 직접 만드는가

| 구성 | 제작 방법과 원본 |
| --- | --- |
| 몸·손·의복·52본 리그 | [원본 생성기](../tools/authored_character/build_seoul_resident.py)와 [해부 표면 필드](../tools/authored_character/anatomical_surface_fields.py)로 정점·스킨 가중치·UV를 생성한다. 게임 내 기본·통통·근육 체형이며 인체 스캔이나 의학적 분류가 아니다. |
| 얼굴·귀·눈꺼풀·헤어 | [얼굴 조형 모듈](../tools/authored_character/resident_identity_mesh.py)에서 얼굴 표면, 실제 안구와 눈꺼풀 구멍, 귀, 머리카락 갈래를 만든다. 기존 게임의 모델·리그·애니메이션을 추출하지 않는다. |
| 홍채·머리색·기본 피부색 | [수치 재질 모듈](../tools/authored_character/portrait_materials.py)이 자체 색 필드와 작은 텍스처를 만든다. 눈의 반사는 실제 장면 조명과 재질이 담당한다. |
| 피부의 지역별 색 | 프로젝트에서 `image_gen`으로 생성한 가상 성인 정면 페인트 두 장을 [정합 모듈](../tools/authored_character/portrait_paint_bake.py)이 읽어 피부 정점에 적용한다. **이 페인트는 게임 실행 화면이 아니며**, 측정한 무조명 알베도도 아니다. |

## 페인트 출처와 적용

생성 프롬프트·입력 후보 화면은 [원본 생성 기록](../data/reports/character_identity/20261024/imagegen_paint_sources.json)에 있다. PNG 원본은 수정하지 않는다.

| 입력 | 크기 | SHA-256 |
| --- | --- | --- |
| [남성형 페인트](../game/assets/original/seoul_resident/portrait_sources/portrait_albedo_m01_v01.png) | 1254×1254 | `cb52bc58189849120d5f781d61543d686fd3d9e1014f23f997c577f20727bc2a` |
| [여성형 페인트](../game/assets/original/seoul_resident/portrait_sources/portrait_albedo_f01_v01.png) | 1254×1254 | `071c642ba1cdf7e8dc4f25fdc311c98eea433576e2bd3c57aeaf0e234581c740` |

원본의 눈·코·입·턱·윤곽 17개 지점을 수동으로 지정하고 thin-plate spline으로 자체 얼굴 좌표에 정합한다. 몸의 기존 피부색을 기준으로 원본 피부 표본의 평균적인 색 차이를 보정한다. 눈·눈썹·헤어에는 정면 그림을 덧씌우지 않으며, 목·측면·뒤통수로 갈수록 적용을 줄인다.

생성 그림에는 요청과 달리 일부 명암과 눈 반사점이 남았다. 따라서 피부의 밝기 변화에 상한을 두고 피부·입술에 서로 다른 면적 평균 샘플을 사용한다. 원본의 작은 모공을 성긴 정점에 그대로 읽어 큰 얼룩처럼 보였던 v05 관찰에 따라, v06 후보용 샘플 반경을 피부 8px·입술 3px로 조정했다. 이 처리는 메모리에서 수행하며 원본 PNG를 다시 저장하지 않는다.

헤어의 v01 올리브색은 매우 어두운 선형 정점색이 GPU용 8비트 값으로 절삭되면서 생겼다. [Godot의 해당 색 저장 코드](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/rendering_server.cpp#L649-L662)에 맞춰 색 채널이 남는 기준으로 교정했고, 실제 후속 화면에서 붉은 두피와 올리브색 갈래의 차이가 해소됐음을 확인했다.

## 재현과 판정

표준 체형 남녀의 사복·수영복 후보 4개는 생산 자산과 다른 폴더에 생성한다. 같은 소스에서 `--without-portrait-paint`를 추가하면 수치 색만 사용하는 조형 대조군을 만들 수 있다.

```sh
python3 tools/authored_character/build_seoul_resident.py \
  --candidate-standard --output-dir /private/tmp/sim2seoul-portrait-candidate
python3 tools/authored_character/portrait_paint_bake.py \
  --report /private/tmp/sim2seoul-paint-alignment.json
```

각 출력의 `AUTHORED_MANIFEST.json`에는 생성기·모듈·GLB·실제로 읽은 페인트의 해시와 정합·색 처리 방법을 기록한다. [검토 후보와 원본 화면](../data/reports/character_identity/20261024/candidates/)을 보존해 수정 전후를 구분한다.

수치 검사는 파일 형식, 입력 해시, 정합 오차와 색 범위를 검증한다. **검사 통과나 캡처 성공은 얼굴의 미술 수용을 뜻하지 않는다.** 정면·사선·측면·후면, 조명 변화와 실제 움직임에서 눈 노출·눈썹 연결·피부 얼룩·턱과 귀·헤어 실루엣을 별도로 검토한다.

v06 남녀 표준 체형을 우선 게임플레이 검증 후보로 선택했다. [정면·측면·사선·후면 원본 8장 검토](../data/reports/character_identity/20261024/materials/v06_visual_review.json)에서는 v05의 작은 밝은 피부 얼룩이 줄고 눈썹이 이어진 선으로 보이며, 입술의 지역색과 헤어의 안정적인 갈색이 유지됐다. 이 비교에는 조형과 색 처리 변경이 함께 포함돼 개선 전체를 필터만의 효과로 해석하지 않는다.

코·볼의 넓고 각진 면, 단순한 눈매와 시선, 반복되는 굵은 헤어 갈래는 남아 있다. 실제 사람 같은 얼굴이나 미남·미형의 완성 판정은 내리지 않았다. 전체 체형·복장과 움직임, 조명·사용자 조작의 최종 검증 결과는 별도 실행 기록에서 확정한다.

## 게임 적용과 현재 검증

선택v06은12개 실제 사복/수영복·체형 자산에 적용했다. [현재11실행·220PNG 집계](../data/reports/character_identity/20261024/summary.json), [원래 몸/52본 보존](../data/reports/character_identity/20261024/production_body_preservation.json), [실제 일반OS 남녀 선택과 재기동](../data/reports/character_identity/20261024/normal_launch.json)을 따른다. 전체4185assertion은 중복 회귀를 포함하며 미형 점수가 아니다. 선택한11실행은 실제 엔진 종료0·원문 ERROR0·소스 일치를 확인했다. native12GLB3730개 검사와 별도 해제 수명9개 검사를 포함한다.

[남성 일반게임 확대](../data/reports/character_identity/20261024/os_release06/male_face.png)와 [여성 일반게임 확대](../data/reports/character_identity/20261024/os_release06/female_face.png)는 실제 마우스 조작으로 얻은 무보정 화면이다. Esc → 캐릭터 꾸미기의 앞/뒤/옆/얼굴 버튼으로 직접 비교할 수 있다. 표정/시선·모발 움직임·각진 코/볼과 손/의복은 후속 과제이며, GTA/사진 수준의 인물이나 연속동작 자연스러움 완료로 평가하지 않는다.

초기 headless16건을 dummy 전용 현상으로 보았지만 이후 native 해제에서도32건을 재현했다. 기존 Body 표시 복원의 지연 처리만으로 해결되지 않았고, 부모 Surface가8개 복제 override 재질 모두를 자식 렌더 인스턴스 삭제까지 보유하도록 수정했다. 같은 fixture의 materialnull12→0 대조와 최종9/9·전체 release06 무오류를 [수명 진단](../data/reports/character_identity/20261024/lifecycle_diagnosis/material_owner_patch.json)에 연결한다. 과거 실패 로그는 보존한다.
