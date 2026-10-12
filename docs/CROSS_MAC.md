# 두 Mac에서 이어서 개발하기

전용 저장소: [codemillss/Sim2Seoul](https://github.com/codemillss/Sim2Seoul). 비공개 저장소이므로 GitHub 계정에 접근 권한이 필요하다. 이 프로젝트 폴더에는 독립 `.git`을 사용한다.

## 공유되는 것

- 코드·데이터 준비 도구·설정·32개 작업 계획·진행 기록·검증 증거.
- 현재 지역 지도 `data/raw/deoksugung_cityhall-v2.osm.pbf` — 188,346 bytes.
- 비교용 이전 지역 지도 `data/raw/deoksugung_cityhall.osm.pbf` — 187,286 bytes.
- 지도 출처·ODbL 표시·스냅샷 SHA-256과 고정 Python 의존성.

국가 전체 PBF, `.venv-data`, `data/processed`, Godot 캐시와 빌드 파일은 각 기기의 로컬 자료다. 지역 지도가 포함돼 있으므로 평소 개발을 재개할 때 289MB 국가 원본을 다시 받을 필요가 없다.

## 다른 Mac의 최초 준비

Git과 Python 3.14를 준비한다. Python 환경은 기기별로 만들며 `.venv-data`를 복사하지 않는다. 다음은 아직 `Sim2Seoul` 폴더가 없는 위치에서 실행한다.

```sh
git clone https://github.com/codemillss/Sim2Seoul.git
cd Sim2Seoul
bash tools/setup_mac.sh
```

GitHub HTTPS 인증이 준비되지 않았고 해당 Mac의 SSH 인증이 이미 설정돼 있다면 복제 명령은 다음을 사용한다. 인증 정보나 SSH 개인키를 저장소에 넣지 않는다.

```sh
git clone git@github.com:codemillss/Sim2Seoul.git
```

Python 명령 이름이 다르면 Python 3.14를 가리키는 실행 파일을 지정한다.

```sh
SIM2SEOUL_PYTHON=python3 bash tools/setup_mac.sh
```

준비 도구는 공유 지도 두 파일의 해시를 확인하고, 고정 의존성을 설치하며, 현재 지역 지도로 미리보기를 재생성한다. 전국 원본과 게임 엔진은 설치하지 않는다. Godot은 E01에서 버전·렌더러가 결정된 뒤 두 기기에 같은 버전을 설치한다.

환경 설치 전 지도 파일만 확인하려면 다음을 실행한다.

```sh
python3 tools/check_checkout.py
```

## 작업을 이어가는 순서

1. 작업 시작 전 `git status`로 남은 변경을 확인한다. 작업을 커밋한 뒤 `git pull --ff-only`로 최신 상태를 받는다. 미완료 작업이 있으면 백업/커밋 없이 덮어쓰지 않는다.
2. `docs/WORK_STATUS.md` → `docs/SOL_HANDOFF.md` → 수행할 작업 ID 부분만 읽는다. 현재 다음 작업은 D03이다.
3. 해당 작업을 수행·검증하고 WORK_STATUS의 결과·다음 행동을 갱신한다.
4. 의도한 파일을 선택해 커밋한다. `git diff --cached --check`와 파일 목록을 확인한 뒤 `git push`한다.
5. 다른 Mac에서는 최신 커밋을 받은 뒤 같은 진행 기록을 이어간다. 같은 파일을 두 기기에서 동시에 수정했다면 변경을 비교해 합친다. 강제 push를 사용하지 않는다.

기능 작업용 새 브랜치 이름은 `codex/<작업명>`을 기본으로 한다. 최초 공유 상태와 정리된 작업은 `main`에 둔다.

## 국가 원본이 필요한 경우

일반 지역 감사는 공유된 작은 지도만 사용한다.

```sh
.venv-data/bin/python tools/prepare_osm.py audit data/raw/deoksugung_cityhall-v2.osm.pbf
```

`tools/review_osm_extract.py`는 국가 원본과 지역 전체를 다시 대조하는 선택 작업이다. 이 전체 D02 검사를 재실행하거나 조사 범위를 넓힐 때만 [날짜 고정 국가 원본](https://download.geofabrik.de/asia/south-korea-261009.osm.pbf)을 `data/raw/geofabrik/south-korea-261009.osm.pbf`에 받아 manifest의 SHA-256과 대조한다.

기대 SHA-256:

```text
70007aa979f8e362ca609fdc2d6302164c2f1379f11c8fc5fd39a7a2e79d3c17
```

국가 원본이 없는 복제본에서도 기존 D02 증거를 읽고 D03 이후를 진행할 수 있다. 국가 원본을 받기 전 전체 검토 도구를 실행하면 필요한 파일과 선택 작업이라는 안내가 표시된다.

## 검증 범위

현재 기기에서 국가 원본이 없는 새 복제본과 새 Python 3.14 환경으로 지역 지도 검사·미리보기 재생성을 확인했다. 준비 후 추적 파일 변경도 없었다. [준비 검증 기록](../data/reports/git_portability_check.json)을 참고한다. 실제 M4 Pro의 실행/성능 검증은 R04에서 별도로 기록한다. 아직 실행 가능한 Godot 게임은 없다.
