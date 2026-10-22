# EXP26 자전거·킥보드 분산 배치 검증

현재 판정은 `headless_final01.json` **88/88 PASS**다. 27개 관련 입력 SHA가 실행 전후 일치했고, 실제 엔진 로그에 SCRIPT ERROR/Parse Error가 없다. 원본 world.json의 **1,233개 mesh ID 전체**, 사람28명·개2마리·기존 AI차량14대, 기존 플레이어 capsule과 TIN을 유지했다.

8개 구역의 자전거8대·킥보드8대 모두에서 지지와 capsule이 검증된 **플레이어 관찰 시작점만** 배치했다. 실제 physical KEY_E 누름/해제로 기존 공통 대상 선택을 거쳐 정확한 탈것에 타고, 실제 W 이동·Space 제동·E 하차/반납을 확인했다. 유지 입력은 시험용 합성 action이며 사람의 OS 키보드 조작 수용과 구분한다. 직접 mount 호출, 차량·NPC·원본 지형 위치 쓰기, 충돌 제거는 없다.

모든 주차 body의 원본 보도·차도/사유지 제외·정문 여유와 지지를720지점에서 확인했다. 실제 대여소 mesh368개의 보수적 envelope를9,280지점에서 지면에 투영해 원본 보도 안에 있는지 확인했고, 다른 대여소의 표지/기둥이 출발 body 공간을 가리지 않는지도 읽었다. 지형을 따라 최대0.150m 간격으로 시행한 전체 body cast368개가3.4m 출발 경로를 확인했다. 이들은 샘플/질의 수이며 고유 요구사항 수가 아니다.

16회 실제 W 이동·제동 거리는2.127~3.126m였고, 전진489 physics 관찰 중 지지 상실0·차단0이었다. 반납 범위를 넘은 경우 실제 저속 S로 돌아온 뒤 E를 눌렀다. 모두 capsule·입력·상호 충돌 예외 해제를 복원했다. 시작5,588ms는 이 Mac에서 전체 장면+8 physics tick+입력 SHA를 포함한 단일 관찰이며 FPS나 반복 성능 측정이 아니다.

`development_attempts.json`에 초기79/88 실패와 테스트 보정·실제 배치 수정의 경계를 기록했다. 첫 parse 실패, 좁은 보도의 주차판 가장자리, Sejong04 실제 이동 차단, 잘못된 과거 source 개수와 경사 위 평평한 긴 cast 실패도 원문을 남겼다. 두 번째88/88은 최종 생산 guard의 yaw 보정 전 개발 기록이다.

현재 소스 재현은 저장소 루트에서 다음을 실행한다. 기존 파일을 덮어쓰지 않도록 새 태그를 쓴다.

```sh
.venv-data/bin/python tools/run_urban_transit_acceptance.py distribution headless replay01 --output-dir data/reports/mobility_distribution/20261022/coverage
```

Native 화면과 일반 실행/OS 조작은 상위 EXP26 집계에서 별도로 확인한다. 이 폴더의 headless PASS를 그래픽·주관적 승차감·다른 Mac·장시간 성능의 수용으로 확대하지 않는다.
