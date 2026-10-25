# EXP38 · 실제 도시 탐험의 Web/Sites 배포

현재 선택은 `attempt04`다. 원래 `explore_walk.tscn`을 그대로 WebGL2로 실행한다. 원본 Mac 프로젝트 설정은 유지하고 별도 캐시 프로젝트에서만 Compatibility·단일 스레드·한글 폰트 설정을 적용했다. `game/` 원본5,214파일이 선택 빌드의 해시와 같은지 [선택 산출물 검사](selected_artifact_check.json)로 다시 확인했다.

## 실제 결과

- [import/export/repack 기록](attempt04/build.json): 각 exit0·ERROR0. 원본 내보내기5,095항목을 보존하고 `FileAccess`/SHA/음향에 필요한 원본 WAV/GLB25개를 추가했다.
- [실제 PCK 검사](attempt04/pack_integrity.json): 원본213파일의 바이트 SHA 일치, 한글 폰트 ResourceLoader 로드 성공.
- WASM39,514,754B, PCK307,439,668B. 8MiB 단위42조각의 압축 전/전체 해시를 검증한다. 압축 전송141,134,734B, 가장 큰 정적 파일8,378,982B다.
- [도시](local_final_world_complete.jpg)·[메뉴](local_final_menu_complete.jpg)·[실제 엔진 DOM 로그](local_final_runtime_dom.txt): 대한문 세계·한국어·완전한 Esc 메뉴·원형 갤러리·Q 킥보드 호출 표시는 실제 브라우저에서 관찰했다. 숨겨진 오류 패널이 아닌 실제 `EXPLORATION_READY`로 시작을 판정했다.
- 게임 상단 도구막대54px를 제외한 캔버스1280×746을 실제 DOM으로 확인했다. Godot 자동 canvasResizePolicy2가 CSS 크기를 덮던 문제를 policy0 및 ResizeObserver로 수정했다.
- 지속 보행/탑승, 실제 음향 청취, 저장 후 재접속, 모바일 및 장시간 성능은 수용하지 않았다. 자동 입력 중 반복 키가 메뉴로 빠진 화면도 보존했으며 `local_attempt04_movement.jpg`, `local_attempt04_walk_scooter.jpg`, `local_attempt04_actual_walk.jpg`라는 파일명만으로 연속 이동 성공을 뜻하지 않는다. 미술·인체 실사 수용이나 native 전체 회귀 결과도 아니다.

## 실패와 구체적인 수정

1. `attempt01`: 첫 폰트 import 전 custom_font 설정으로 import 자체는 exit0이나 ERROR2. 검사에서 거절하고 폰트 import 뒤에 설정한다.
2. `attempt02`: 일반 export가 include_filter에도 원본 WAV/GLB25개를 누락. 실제 PCK 읽기 검사에서 발견했다. Godot PCKPacker로 원래 항목을 보존하고 원본을 추가한다.
3. `attempt03`: Uint8Array를 preloadFile에 넘겨 파일 크기 조회 시 문자열 변환 `RangeError Invalid string length`. 공식 API에 ArrayBuffer를 넘겨 고쳤다. 이후 실제 엔진에서 GLES3 shader instance uniform 저장 한도 오류를 발견했다. Web만 건물별 보통 uniform 재질을 유지하고 native instance uniform 경로는 유지한다. [실제 첫 실패](local_attempt03_failure.jpg)·[shader 실패](local_attempt03_shader_failure.jpg)·[원문 로그](local_attempt03_shader_logs.json)를 보존했다.
4. `attempt04`: 위 수정을 포함한 실제 도시 시작을 확인했다. UI 마지막 수정은 [선택 산출물 검사](selected_artifact_check.json)의 frontend 해시로 결합한다.
5. 최초 Site 소스 push와 일부를 제외한 다음 push도 `receive-pack request exceeds maximum size`로 거절됐다. 같은 Site와 원본 커밋을 보존하고9MiB 이하 추가분의 정상 fast-forward push로 나누었다. 일부만 올라간 중간 커밋은 배포하지 않는다. 최종 트리가 최초 전체 검증 파일과 같은지 확인한다. [업로드 기록](source_upload.json)을 따른다. 서버의 정확한 제한값을 임의로 단정하지 않는다.

## 재현과 출처

실행은 [Web 안내](../../../../docs/RUN_GUIDE.md#exp38-web-체험과-재생성)를 따른다. 공식4.7.2 export template의 SHA512를 검증했고 [원본 출처·검증값](export_templates.json)을 보존했다. NotoSansKR는 OFL이며 [법적 고지15파일](../../../../game/resources/legal/)을 게임과 사이트 양쪽에 포함했다. 기존 terrain projection geometry `.res`4,694개는 실제 세계 배치 데이터이므로 제외하지 않는다.

빌드 manifest의 `buildCommit=6825154...`는 내보내기 당시 native 기준 HEAD다. 이번 Web 수정이 그 과거 커밋에 들어 있었다는 뜻이 아니다. 실제 수정 입력은 attempt04의 전체 원본 해시와 선택 frontend 해시, 실제 게시 소스 커밋으로 결합한다. 캐시·템플릿·PCK·WASM·Site 별도 Git은 main 저장소에서 제외한다. 자격 증명은 저장하지 않았다.

게시 결과는 [Site 상태](site_identity.json)를 따른다. 게시 도구의 성공만으로 연속 게임플레이 검증을 대신하지 않는다.

## 게시 결과

[실제 배포 주소](https://sim2seoul-play-20261025-e7d4.rocky-lily-7307.chatgpt.site) · [성공 응답과 검증 범위](deployment.json). 소유자 전용 Site의 실제 terminal `succeeded`를 확인했다. 배포 주소에서 로그인 게이트는 확인했으며 로그인 세션이 없어 인증 후 게임 실행은 미확인이다. 원래 Mac 게임 프로세스48203은 유지했다.
