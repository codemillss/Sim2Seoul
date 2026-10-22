# 서울 생활 시뮬레이션의 참조·구현 방향

작성·공식 자료 확인: **2026-10-22**. 사용자 방향은 **GTA의 자연스러운 도시 이동과 The Sims의 생활·꾸미기 사이에 있는 서울 생활 시뮬레이션**이다. 사용자가 말한 `rea`는 리버스엔지니어링(RE)을 뜻한다. 이 문서는 참조 방법과 제작 기준이며, 기능 완료와 실제 실행 결과는 [WORK_STATUS](WORK_STATUS.md)를 따른다.

## 경험에서 가져올 기준

| 참조 | 확인한 공식 설명 | Sim2Seoul의 적용 방향 |
|---|---|---|
| GTA V | Rockstar의 [2014년 시점·조작 안내](https://www.rockstargames.com/newswire/article/25o2411812oa29/rockstar-game-tips-playing-with-perspective-in-gtav)는 보행·차량의 시점을 따로 고르고 시선 감도·머리 흔들림을 조절하는 기능을 설명한다. | 사람의 눈높이, 보폭과 이동 속도, 출발·정지·방향 전환, 탈것과 보행 사이의 자연스러운 연결을 측정·개선한다. 사용자가 싫어한 카메라 진동은 더하지 않는다. |
| The Sims 4 | EA의 [공식 소개](https://www.ea.com/games/the-sims/the-sims-4)는 외모·성격·의상, 집의 배치·가구, 동네 방문과 사회 활동을 설명한다. | 서울의 상점·의상·식사·운동·샤워·수영·주거 활동이 실제 선택과 상태 변화로 이어지게 한다. 기존 기능과 앞으로 확장할 생활 기능을 구분한다. |

위 적용 방향은 공식 설명을 바탕으로 정한 프로젝트의 설계 선택이다. 다른 게임의 품질·규모를 이미 달성했다는 뜻은 아니다. 실제 서울의 배치·미터 축척과 게임용 시설의 구분도 유지한다.

## RE의 이번 적용 범위

현재 선택은 **관찰 → 측정 → 기능 사양 → 독립 구현 → 같은 조건의 비교 검증**이다. 공식 기능 설명과 사용자의 조작감 피드백을 먼저 활용한다. 별도 플레이 관찰을 수행할 때도 눈높이, 가속·정지 시간, 회전 반경, 보폭, 시설 이용 전환 같은 기능 사양과 원본 파일·코드·표현의 이용을 구분한다. 참조 영상이나 이미지가 공개돼 있거나 사용자에게 있다는 이유만으로 게임에 포함하거나 AI 도구에 제공하지 않는다.

현재 GTA/The Sims의 특정 게임 바이너리·버전·수락한 이용약관·별도 허가는 제공되지 않았다. 이번 작업에서 원본 게임을 취득·분해하거나 모델·리깅·모션·음향·UI·로고를 추출하지 않았다. 특정 바이너리 분석이나 자산 추출의 허용 여부는 아직 확정하지 않았다.

확인한 약관에는 제한과 예외가 함께 있다.

- [Take-Two 공식 약관 §2](https://www.take2games.com/legal/en-US/) — 페이지 갱신일 2025-02-28. 복제·배포·역분석·파생 작업 등을 제한하며 별도 명시 허가와 적용 법률상 예외를 구분한다. 역분석에는 EU Directive 2009/24 및 기타 적용 법률의 예외가 명시돼 있다. Rockstar의 기존 `/eula` 주소는 현재 [공식 법률 페이지](https://www.rockstargames.com/legal)로 이동한다.
- 같은 약관 §2.3은 콘텐츠를 생성형 AI 도구의 원천 자료 등으로 사용하는 행위도 별도로 제한한다. GTA 영상·스크린샷·게임 데이터를 AI 입력으로 제공하는 방식은 현재 선택하지 않았으며, 실제 허가·적용 조건을 먼저 확인해야 한다. 이번 인체 교체는 개별 재배포 권한이 확인된 외부 모델을 사용하는 별개의 작업이다.
- [EA User Agreement §2](https://www.ea.com/legal/user-agreement) — 페이지 갱신일 2026-05-14. 역분석과 소스 코드·데이터 추출 등을 제한하되 EA의 명시 허가 또는 법률상 허용 예외를 둔다.
- [Rockstar 저작물 게시 정책](https://support.rockstargames.com/articles/7bNaeoMFTV0iUDGhStTXvz/policy-on-posting-copyrighted-rockstar-games-material)은 무단 콘텐츠 포팅을 문제 사례로 명시한다. 팬 플레이 영상 게시에 관한 설명을 독립 게임의 자산 재사용 허가로 해석하지 않는다.

따라서 RE 전체를 일괄 불법 또는 일괄 허용으로 판정하지 않는다. 실제 적용 여부는 대상 버전·동의한 약관·작업 방법·허가·적용 법률에 따라 별도로 확인한다. 이 문서는 확인한 조건을 작업에 반영한 기록이며 법률 판단이나 모든 권리에 대한 보증이 아니다.

## 자산을 도입하는 기준

새 자산은 제작자·원본 URL·취득일·정확한 버전과 파일 해시, 라이선스 원문, 변경 내용, 게임 포함·수정·재배포 허용 범위를 함께 기록한다. “무료”·검색 결과·업로더의 설명만으로 이용권을 확정하지 않는다. 자체 제작도 외부 모델·녹음·스캔·모션 사용 여부를 구분한다. 확인한 파일만 도입하고 표시·제공 조건을 실제 배포물에 반영한다.

| 현재 원천 | 유지할 조건과 기록 |
|---|---|
| OpenStreetMap | [공식 저작권 안내](https://www.openstreetmap.org/copyright)와 [ODbL](https://opendatacommons.org/licenses/odbl/1-0/)에 따라 기여자·라이선스를 표시한다. 파생 데이터의 공개 사용에는 해당 데이터 또는 전체 변경 내용/방법을 제공하는 §4.6 조건을 확인한다. [게임·시뮬레이션 표시 지침](https://osmfoundation.org/wiki/Licence/Attribution_Guidelines#Computer_games_and_simulations)에 맞춰 게임 내 고지도 유지한다. |
| Overture 건물 | [공식 출처·라이선스](https://docs.overturemaps.org/attribution/#buildings)의 건물 테마는 ODbL이다. 개별 원천과 추가 CC BY 표시를 보존하며 빈 `sources.license`를 무조건 자유 이용으로 해석하지 않는다. |
| Kenney City Kit Commercial 2.1 | [공식 배포 페이지](https://kenney.nl/assets/city-kit-commercial)의 CC0와 로컬 [License.txt](../game/assets/vendor/kenney_city_kit_commercial/License.txt)·[취득/파일 해시](../game/assets/vendor/kenney_city_kit_commercial/provenance.json)를 유지한다. CC0의 범위 밖인 제3자 상표·초상 등은 [CC0 설명](https://creativecommons.org/publicdomain/zero/1.0/)과 구분한다. |
| Godot와 프로젝트 코드 | [Godot MIT](https://godotengine.org/license/)는 엔진에 적용되며 게임 콘텐츠를 자동으로 MIT로 만들지 않는다. 현재 프로젝트 코드의 별도 배포 라이선스는 미지정이다. 공개 저장소라는 사실도 라이선스 부여를 대신하지 않는다([GitHub 안내](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)). |

자료별 실제 포함 파일·공식 사진 참고·자체 생성 음향/텍스처와 세부 고지는 [ATTRIBUTION](ATTRIBUTION.md), 자료 확보 상태는 [DATA_SOURCES](DATA_SOURCES.md)에 보존한다. 데이터 라이선스, 외부 자산 라이선스, 프로젝트 코드의 배포 조건을 하나로 합치지 않는다.
