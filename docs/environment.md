# 엔진과 현재 개발 환경

확인: 2026-10-13 · E01 · [실행 결과](../data/reports/engine_startup.md)

## 고정한 개발 기준

| 항목 | 실제 확인 / 선택 |
|---|---|
| 엔진 | Godot **4.7.2.stable.official.ed1daf0bf**, Standard, GDScript |
| 개발 렌더러 / 드라이버 | **Forward+ / Metal** (`forward_plus` / `metal`) |
| 설치 위치 | `/Applications/Godot.app` |
| 실행 파일 | `/Applications/Godot.app/Contents/MacOS/Godot` |
| 공식 배포 | [4.7.2 안정판](https://godotengine.org/download/archive/4.7.2-stable/)의 macOS Universal Standard |
| 현재 Mac | Apple M1 Pro, CPU 8코어(성능 6/효율 2), GPU 14코어, RAM 16GB, arm64 |
| OS | macOS 27.0, build 26A428 |
| 시작 시 디스크 여유 | 12,600,000 KiB, 약 12.02 GiB |
| 설치 앱 크기 | `du -sk` 345,424 KiB, 약 337.3 MiB |
| 추가 Mac | M4 Pro, SSD 1TB는 사용자 제공. RAM·OS·기동 결과는 미확인 |
| 내보내기 템플릿 | **미설치**. 편집기/장면 실행에는 불필요하며 R03 패키지 작업 전에 **4.7.2.stable**로 준비·검증 |

기본 Forward+가 현재 기기에서 정상 기동했고 Mobile/Metal과 Compatibility/OpenGL도 비교해 결함이 없었다. 기본을 바꿀 기동 문제가 없으므로 Forward+를 채택한다. 이는 도시 장면 성능 순위나 1080p 목표 달성의 근거가 아니다. E03/R 단계에서 실제 지도·그림자·개체 수를 고정해 재평가한다. [렌더러 공식 설명](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html).

## 설치 출처와 무결성

정확 파일명은 `Godot_v4.7.2-stable_macos.universal.zip`, 170,622,178 bytes다. 공식 다운로드 버튼은 아래 주소를 거쳐 공식 저장소로 연결됐다.

- [공식 다운로드](https://downloads.godotengine.org/?flavor=stable&platform=macos.universal&slug=macos.universal.zip&version=4.7.2)
- [공식 배포 체크섬](https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/SHA512-SUMS.txt)
- ZIP SHA-256: `c58a24e31d720be9d62f60cb5627c4e695fb72f21b0cfe1bc9ccaa9a3b3ba63e`
- 공급자 SHA-512와 로컬 파일이 일치했다. 전체 값·서명/공증 결과는 [설치 검사](../data/reports/e01/installation.json)에 남겼다.

앱은 arm64/x86_64 Universal이며 현재 arm64 Mac에서 실행했다. `codesign --verify --deep --strict`를 통과했고 `spctl --assess --type execute`는 `accepted / Notarized Developer ID`였다. 기존 앱을 덮어쓰지 않고 설치했다. 격리 속성 삭제나 시스템 보안 변경은 하지 않았다. .NET SDK·추가 플러그인은 설치하지 않았다.

## 다른 Mac에서 준비하고 실행하기

1. 기존 Godot 설치가 있다면 버전을 먼저 확인한다. 다른 버전을 임의로 덮어쓰거나 업데이트하지 않는다.
2. 위 공식 **4.7.2 Standard macOS Universal** ZIP을 받아 공식 SHA-512와 대조한다. 압축을 풀어 앱을 Applications에 놓는다. 기존 앱을 보존할 필요가 있으면 별도 이름/경로에 두고 아래 `GODOT_BIN`으로 지정한다.
3. 현재 Mac의 칩·RAM·OS·여유 공간과 서명/공증을 확인한다. 설치된 버전이 고정 버전과 같은지 확인한다.
4. 저장소 루트에서 아래 시험을 실행한다. Python 데이터 준비·전국 지도·템플릿은 이 시험에 필요하지 않다.

```sh
sh tools/run_engine_smoke.sh editor
sh tools/run_engine_smoke.sh run
sh tools/run_engine_smoke.sh observe
```

`editor`는 빈 3D 편집기를 연다. `run`은 상자가 회전하는 GPU 시험창을 유지하며 **Close 버튼 또는 Esc**로 끝낸다. `observe`는 장면 처리 누적 약 12초 뒤 화면/환경을 `data/cache/engine_smoke/`에 기록하고 종료한다. 렌더러를 명시해 비교할 수 있다.

```sh
sh tools/run_engine_smoke.sh observe mobile
sh tools/run_engine_smoke.sh observe gl_compatibility
GODOT_BIN=/Applications/Godot-4.7.2.app/Contents/MacOS/Godot sh tools/run_engine_smoke.sh run
```

명령은 [공식 CLI 규칙](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)을 사용한다. 버전 불일치나 실행 파일 없음은 중단한다. 실제 GUI 화면·종료·로그를 함께 확인하며 headless 성공만으로 기동 완료를 판단하지 않는다. 렌더러 자동 대체가 발생하면 runtime JSON의 실제 renderer/driver를 확인하고 보고한다.

## 공유 범위

[E01 시험 프로젝트](../tests/engine_smoke/project.godot)는 서울 지도·캐릭터·충돌·입력/월드 구조가 없는 독립 장면이다. 정식 `game/`은 E02에서 만든다. `.godot`, 시험용 UID sidecar, 앱/설치 ZIP, 사용자 설정, 캐시와 내보내기 결과는 Git으로 옮기지 않는다. 작은 소스 장면·시험 실행 도구·이번 관찰 보고서와 화면만 공유한다. M4 Pro에서는 같은 버전의 실제 GUI 기동부터 재검증한다.
