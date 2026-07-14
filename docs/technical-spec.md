# 던전 오피스 — MVP Android·Godot 기술 명세

| 메타데이터 | 값 |
|---|---|
| 문서 ID | `TECH-MVP-001` |
| 제목 | 던전 오피스 — MVP Android·Godot 기술 명세 |
| 목적 | 승인된 5라운드 MVP를 Android 앱으로 구현·검증·빌드·배포하는 프로젝트와 도구 체인 경계를 고정한다. |
| 담당 영역 | Godot 프로젝트 구조, Android 앱 설정, 오프라인·생명주기 경계, 로컬 진단, 개발 환경, export·서명·CI |
| 상태 | Draft |
| 버전 | 2.0.0 |
| 적용 범위 | Google Play에 배포할 Android 단독 무료 MVP |
| 상위 원칙 문서 | `GDD-001`, `MVP-001` |
| `depends_on` | `MVP-001`, `BUS-MVP-001`, `REL-PLAY-001`, `UX-MVP-001`, `UI-MVP-001`, `TECH-SIM-001`, `TECH-DATA-001` |
| `consumed_by` | `QA-MVP-001` |
| Source of Truth | application ID, Android·Godot 버전과 빌드 설정, 모듈 의존 방향, 오프라인 플랫폼 경계, export·서명·CI 방식 |
| 명시적 비담당 | 게임 규칙, 콘텐츠·밸런스, 시뮬레이션 타입·틱 순서, 데이터·저장 스키마, 화면 배치, 상업 정책, Play 등록 문구·에셋 |
| 미결정 사항 | 없음. 업로드 키 비밀값과 Play가 보관하는 앱 서명 키는 저장소 밖 운영값이다. |
| 마지막 갱신일 | 2026-07-14 |

## 1. 이 문서가 답하는 질문

- 어떤 엔진·SDK·JDK 버전으로 재현 가능한 Android 빌드를 만드는가?
- package name과 지원 Android 범위는 무엇인가?
- 시뮬레이션, 데이터·저장, 앱 흐름, UI와 플랫폼 어댑터의 의존 방향은 무엇인가?
- 완전 오프라인 원칙을 권한·코드·의존성·테스트에서 어떻게 지키는가?
- 백그라운드, 강제 종료, 외부 메일·브라우저 앱 왕복을 어떻게 처리하는가?
- 저장소에 서명 비밀을 넣지 않고 어떤 APK·AAB를 만드는가?
- 로컬과 CI에서 어떤 명령이 성공해야 개발 준비·병합·출시 후보가 되는가?

정확한 시뮬레이션 의미는 `TECH-SIM-001`, 데이터와 저장은 `TECH-DATA-001`을 따른다. 이 문서는 그 계약을 Android용 Godot 프로젝트로 조립하는 방법만 소유한다.

## 2. 확정 플랫폼 계약

### 2.1 앱 식별과 배포

| 항목 | 확정값 |
|---|---|
| 엔진 | Godot `4.7-stable`, Standard 빌드 |
| 언어 | 타입드 GDScript |
| 렌더러 | Compatibility / GL Compatibility |
| 앱 이름 | 던전 오피스 |
| application ID | `com.mrkimkim.dungeonoffice` |
| 초기 `versionCode` | `1` |
| 초기 `versionName` | `0.1.0` |
| 대상 | Android 단독 |
| 화면 방향 | 세로 고정 |
| 제품 지원·QA 하한 | API 24 / Android 7.0 |
| 표준 template manifest | Godot 4.7 기준 `minSdk 24`, `targetSdk 36`, `compileSdk 36` |
| Google Play 제출 하한 | `targetSdk 35` 이상. 현재 표준 template의 36으로 충족 |
| 출시 산출물 | Google Play용 AAB |
| 실기 개발 산출물 | adb 설치 가능한 debug APK |
| ABI | `arm64-v8a` 필수, MVP 공개 산출물은 이것만 포함 |

application ID는 첫 Play 트랙 생성 전에 위 값으로 동결하며 같은 앱 업데이트에서 바꾸지 않는다. `versionCode`는 Play에 업로드할 때마다 증가하고 재사용하지 않는다.

debug APK는 Godot 4.7의 공식 standard Android export template를 사용한다. Google Play AAB는 Godot가 요구하는 같은 버전의 공식 Gradle build template를 export 시 `android/` 작업 디렉터리에 설치해 사용한다. 이 대용량 생성 디렉터리는 Git에서 제외하며 Android 소스를 커스터마이즈하거나 별도 제품 계층으로 소유하지 않는다. 두 산출물의 manifest와 제품 지원 하한을 API 24, target/compile을 36으로 맞춘다. 공개 전 API 24 emulator smoke와 현재 보유 물리 기기 실기 회귀를 모두 통과해야 한다. 향후 Godot template의 min/target SDK가 바뀌면 실제 APK·AAB manifest와 지원 행렬을 함께 갱신한다.

### 2.2 화면과 입력 구성

- 논리 viewport는 `UI-MVP-001`의 `360×640` 세로 기준을 사용한다.
- stretch mode는 `canvas_items`, aspect는 `expand`다.
- 기준 영역을 비균일 확대하지 않고 Android display cutout과 safe area를 UI layout 입력으로 제공한다.
- 게임플레이 입력은 단일 포인터 탭을 기준으로 하며 멀티터치 제스처를 게임 규칙에 사용하지 않는다.
- Android 뒤로가기는 현재 화면의 UX 계약에 따라 취소·일시정지·뒤로 이동으로 번역하며 앱을 임의 종료하지 않는다.

### 2.3 런타임 권한

허용되는 앱 권한은 MVP 기능에 실제 필요한 최소 집합뿐이다.

- `INTERNET`: **금지**
- 외부 저장소 read/write: **금지**
- 광고 ID, 위치, 연락처, 카메라, 마이크, 알림: **금지**
- 햅틱을 위한 `VIBRATE`: Godot export가 필요로 할 때만 허용

지원 메일과 공개 정책 URL은 주소 복사와 선택적 OS 외부 앱 intent만 사용한다. 메일·브라우저 앱 발견을 위해 광범위한 package 조회 권한을 추가하지 않는다. 외부 앱이 없거나 intent가 실패해도 로컬 원문 열람과 게임은 동작한다.

## 3. 고정 개발 도구 체인

| 구성요소 | 버전·조건 |
|---|---|
| Godot Editor·headless | `4.7-stable` |
| Godot export templates | Editor와 정확히 같은 `4.7.stable`; APK와 Gradle `android_source.zip` 포함 |
| JDK | OpenJDK 17 |
| Android SDK Platform | `platforms;android-36` |
| Android Build Tools | `36.1.0` |
| Android Platform Tools | 35 이상 |
| Android NDK | `29.0.14206865` |
| CMake | `3.10.2.4988404` |
| bundletool | `1.18.3`, release AAB 검증 시에만 필요 |
| Android Command-line Tools | 설치 시점 latest, 실제 빌드는 위 개별 패키지 고정 |

로컬 머신에 다른 버전이 함께 있어도 환경 검사는 위 패키지의 존재를 확인한다. debug standard template의 내장 manifest와 release Gradle preset의 min/target 값은 모두 API 24/36이어야 하며 최종 산출물 검사로 확인한다. Godot 버전 또는 Android 도구 체인 핀 변경은 다음을 같은 변경으로 수행한다.

1. 이 표와 환경 검사 갱신
2. headless 전체 테스트
3. debug APK 설치·실행
4. R1~R5 골든 해시 Android 실기 일치
5. 저장 round-trip과 업데이트 설치 회귀

## 4. 저장소 구조와 모듈 경계

```text
project.godot
export_presets.cfg
src/
  sim/          # 순수 상태·명령·step·canonical hash
  data/         # catalog/round 로드와 검증, 법적 원문 로드
  app/          # ProfileV1, 저장 repository, 정산·구매 도메인 서비스
  ui/           # composition root, scene, 화면, 입력·생명주기 adapter
data/
  catalog.json
  rounds.json
site/           # Pages와 앱이 함께 읽는 개인정보·라이선스 원문
tests/
  run_tests.gd
  test_*.gd
  fixtures/
tools/
```

### 4.1 의존 방향

```text
ui ─> app
ui ─> sim
ui ─> data
app ─> TECH-DATA-001 DTO와 canonical JSON
sim ─> 외부 모듈 없음
data ─> 패키지 JSON·Markdown
```

- `sim/`은 `Node`, SceneTree, Input, OS, Time, FileAccess, 네트워크, 난수를 참조하지 않는다.
- `data/`는 패키지 안의 `res://data/*.json`과 `res://site/**/*.md`만 읽고 쓰지 않는다.
- `app/`의 save repository는 `user://save/`만 읽고 쓰며 UI·SceneTree를 참조하지 않는다. Profile·정산 서비스도 UI 노드 경로나 터치 좌표를 저장하지 않는다.
- `ui/main.gd`가 MVP composition root다. repository와 서비스를 생성하고, 입력을 `SimCommandV1` 또는 앱 서비스 호출로 변환하며, Android 생명주기·safe area·외부 intent 결과를 앱 의미로 번역한다.
- UI가 규칙·가격·커트라인을 재계산하지 않는다. 정산·구매는 `app/`, 시뮬 판정은 `sim/`, 콘텐츠 값은 `data/`가 제공한다.
- 플랫폼 결과가 시뮬레이션을 직접 변경하지 않는다. `ui/main.gd`가 pause·save 명령을 먼저 거친다.
- MVP에는 비어 있는 `platform/`, `save/`, `main/` 계층과 범용 DI framework를 만들지 않는다. 실제 책임이 독립적으로 커질 때 별도 변경으로 추출한다.

역방향 참조를 피하기 위해 신호·인터페이스는 소비자가 요구하는 최소 결과형을 사용한다. 순환이 생기면 공통 DTO를 `app/` 또는 규범 계약 타입으로 올리고 UI 노드 참조를 하위 모듈로 내린다.

## 5. 앱 유스케이스 경계

완성 MVP의 composition root는 최소 다음 유스케이스 경계를 제공한다. 현재 작은 스캐폴드에서는 별도 빈 coordinator 클래스를 만들지 않고 `ui/main.gd`의 private 함수와 `app/` 서비스 조합으로 시작할 수 있다. 기능이 추가되어 UI가 파일·프로필을 직접 조작하게 되는 시점에는 화면 독립 coordinator로 추출한다.

```text
boot()
create_profile()
load_map()
prepare_round(round_id)
start_round(round_id)
resume_saved_round()
submit_sim_command(command)
pause_and_save(reason)
restart_round()
abandon_round()
commit_settlement(result_packet)
purchase_enhancement_kit()
update_settings(settings)
load_legal_document(document_id)
open_external_support_target(target)
```

각 호출은 성공/복구/오류 결과형을 반환하고 UI가 파일·JSON·프로필 필드를 직접 수정하지 않게 한다. `start_round`, 정산, 구매의 저장 성공 경계는 `TECH-DATA-001`이 소유한다.

## 6. Godot 실행 구성

### 6.1 프레임과 틱

- `_process(delta)`는 화면 표현과 누적 시간만 담당한다.
- 앱 coordinator는 누적 시간이 `TECH-SIM-001` §3.1의 한 고정 틱 이상일 때 `step`을 0회 이상 호출한다.
- 한 렌더 프레임에 따라잡을 수 있는 최대 틱 수를 제한할 수 있으나 남은 누적 시간을 버리거나 판정 시간을 늘리면 안 된다. 제한에 걸리면 시각 프레임을 건너뛰고 시뮬 틱을 우선한다.
- 일시정지·백그라운드에서는 누적 시간을 초기화하고 복귀 시간을 보상하지 않는다.
- 터치는 다음 실행 틱에 연속 sequence로 예약한다.

### 6.2 생명주기

| Android·Godot 사건 | 기술 처리 |
|---|---|
| 앱 focus 상실·background 진입 | 다음 틱을 진행하지 않고 `PAUSE` 제어 적용 → snapshot 저장 → 오디오·햅틱 중단 |
| foreground 복귀 | 저장 상태 검증 → pause read model 표시, 자동 resume 금지 |
| 화면·safe area 변경 | pause 유지 → UI 재배치 → 사용자 resume |
| OS 강제 종료 | 마지막 검증 완료 snapshot에서 복구 |
| 외부 메일·브라우저 intent | 먼저 pause·save, 복귀 시 자동 resume 금지 |
| 저메모리 알림 | 캐시 가능한 아트·오디오만 해제, 규범 상태는 바꾸지 않음 |

background 저장 실패가 발생해도 성공으로 숨기지 않는다. 앱이 살아 있으면 `UX-SAVE-05` 경고를 유지하고 재시도하며, 마지막 정상 snapshot은 보존한다.

## 7. 완전 오프라인 구현 경계

### 7.1 금지 항목

- Android manifest의 `android.permission.INTERNET`
- `HTTPClient`, `HTTPRequest`, `WebSocketPeer`, raw TCP/UDP, WebView
- Firebase, Google Analytics, Crashlytics, 광고·푸시·원격 설정 SDK
- 로그인, 계정, 클라우드 저장, 원격 콘텐츠와 서버 시간
- Google Play Billing 라이브러리와 상품·entitlement 코드
- 원격 폰트·이미지·음원·개인정보 문서

모든 게임 데이터, 한국어 카피, 폰트, 개인정보처리방침과 오픈소스 고지는 AAB 안에 포함한다. 인터넷이 전혀 없고 Play 서비스가 비활성인 기기에서도 신규 시작부터 R5 정산까지 동작해야 한다.

### 7.2 외부 앱 경계

`mailto:`와 정책 URL은 OS intent로만 전달한다.

- 호출 전에 라운드를 pause·save한다.
- 저장·로그·기기 정보·본문을 자동 첨부하지 않는다.
- intent 성공을 네트워크 성공으로 해석하지 않는다.
- 실패는 비차단 결과로 UI에 돌려주고 주소 복사를 유지한다.
- 인앱 WebView와 URL fetch fallback을 만들지 않는다.

### 7.3 자동 검증

`tools/check_offline.sh`는 소스·project·export preset·Android manifest 산출물을 검사해 다음을 0건으로 강제한다.

- 금지 네트워크 클래스·URL scheme 호출
- 알려진 원격 SDK 의존성
- INTERNET·광범위 저장소 권한
- Billing 플러그인·상품 ID·상업 entitlement 필드

소스 문자열 검색만으로 출시 승인하지 않고 최종 APK와 AAB의 merged manifest도 검사한다.

## 8. 로컬 진단과 플레이테스트 기록

MVP 공개 빌드에는 원격 분석을 넣지 않는다. 개발·내부 테스트 빌드는 `user://logs/playtest.jsonl`에만 구조화 기록을 남길 수 있다.

```text
LocalPlaytestEventV1 {
  schema_version: 1,
  session_sequence: int,
  app_version: String,
  sim_version: int,
  data_version: int,
  run_id: StringID?,
  round_id: StringID?,
  tick: int?,
  type: ROUND_STARTED | COMMAND_REJECTED | ITEM_OVERHEATED |
        REQUEST_WITHDRAWN | ITEM_DELIVERED | ROUND_ENDED |
        SNAPSHOT_RECOVERED | SAVE_FAILED,
  values: Object<String, int | bool | StringID>
}
```

- 이름·이메일·기기 ID·광고 ID·경로·자유 입력·벽시각을 기록하지 않는다.
- 파일은 최대 1MiB, 현재본과 이전본 하나만 유지한다.
- 앱 안에서 전송·업로드하지 않는다. 개발자가 물리 기기에서 adb로 명시적으로 꺼내 분석한다.
- 공개 후보 export에서는 기본 비활성이다. 로컬 오류 코드의 작은 순환 로그는 `REL-PLAY-001`의 선언 범위 안에서 기기 내부에만 둘 수 있다.
- 지표 정의와 성공 판정은 `QA-MVP-001`이 소유하며 로그 스키마가 게임 설계를 결정하지 않는다.

## 9. 콘텐츠·저장 연결

- 부팅 시 UI scene을 열기 전에 `catalog.json`, `rounds.json`을 로드하고 `TECH-DATA-001`의 스키마·trace·참조 검증을 전부 수행한다.
- 개발·CI에서는 데이터 오류가 하나라도 있으면 실행을 실패시킨다.
- 공개 빌드의 패키지 데이터 오류는 복구할 수 없는 설치 결함 화면으로 차단하며 부분 콘텐츠로 진행하지 않는다.
- 시뮬레이션은 repository의 검증 완료 불변 뷰만 받는다.
- save repository는 모든 I/O를 직렬화한다. 동시에 두 profile 또는 transaction write를 실행하지 않는다.
- 앱 종료 요청은 진행 중 쓰기의 완료 또는 명시적 실패 결과까지 기다리되 OS가 강제 종료할 수 있음을 전제로 원자 교체를 사용한다.

## 10. Android export

### 10.1 preset

현재 `export_presets.cfg`에는 `Android Debug`와 `Android Release` 두 preset이 있다. Release preset에는 경로·alias·암호를 저장하지 않으며 Google Play 후보를 만들 때 upload key를 저장소 밖에서 주입한다.

| preset | 산출물 | 용도 | 서명 |
|---|---|---|---|
| `Android Debug` | APK | 로컬·실기 반복 | Android debug key |
| `Android Release` | AAB | Play 후보 출시 gate | 저장소 밖 upload key |

두 preset은 같은 package ID, ABI, 리소스와 오프라인 권한을 사용한다. Debug는 `gradle_build/use_gradle_build=false`, Release AAB는 `true`다. Release export 도구는 `android/.build_version`이 없을 때 `--install-android-build-template`로 Godot 공식 template를 만들며 `android/` 전체는 Git에서 제외한다. release preset은 `release` custom feature를 제공한다. 현재 스캐폴드에는 개발 전용 원격 기능이나 플레이테스트 로그가 없으며, 이후 로컬 진단을 추가하면 이 feature로 공개 후보에서 비활성임을 테스트해야 한다. `docs/`, `tests/`, `tools/`, `.github/`, `build/`, `dist/`는 앱에 넣지 않고 `data/*.json`, 앱 리소스, `site/**/*.md` 법적 원문만 포함한다.

### 10.2 산출물 검증

export 성공만으로 완료하지 않는다.

1. APK/AAB package ID 확인
2. versionCode·versionName 확인
3. 실제 APK·AAB manifest의 target SDK가 35 이상인지 확인(현재 두 산출물은 36)하고 ABI 확인
4. merged manifest 권한 검사
5. 금지 SDK·Billing 의존성 검사
6. 개인정보·라이선스 원문 포함 확인
7. debug APK 신규 설치와 업데이트 설치
8. 비행기 모드 cold start와 snapshot 복구

## 11. 앱 서명

### 11.1 키 분리

- Dungeon Office 전용 **새 upload key**를 만든다.
- 다른 앱·저장소의 keystore를 복사하거나 재사용하지 않는다.
- Google Play App Signing을 사용하고 앱 서명 키는 Play가 생성·보관하게 한다.
- 로컬 upload keystore, alias, 암호, 인증서 개인키는 git에 넣지 않는다.
- public upload certificate SHA-256 fingerprint만 릴리스 기록에 남길 수 있다.

다른 프로젝트에 존재하는 keystore는 이 앱의 서명 근거가 아니다. 파일이 존재한다는 사실만으로 upload key인지 Play 앱 서명 키인지 추측하지 않는다.

### 11.2 비밀 주입

CI release가 승인될 때만 다음 secret 이름으로 주입한다. 값은 문서·로그·PR·artifact에 출력하지 않는다.

```text
ANDROID_UPLOAD_KEYSTORE_BASE64
ANDROID_UPLOAD_KEY_ALIAS
ANDROID_UPLOAD_KEY_PASSWORD
ANDROID_UPLOAD_STORE_PASSWORD
```

CI는 복호화된 keystore를 작업 디렉터리의 임시 권한 제한 파일로 만들고 export 종료 후 삭제한다. fork PR과 일반 pull request에는 release secret을 제공하지 않는다. 현재 일반 CI는 release AAB를 만들지 않으며, Play 후보 생성은 출시 승인을 받은 보호 작업으로 둔다. 후보 AAB 검증은 서명된 모든 entry와 단일 signer를 확인한 뒤 `EXPECTED_UPLOAD_CERT_SHA256` 공개값 또는 주입된 upload keystore에서 구한 SHA-256 인증서 지문과 signer를 반드시 대조한다.

## 12. 로컬 명령 계약

```bash
./tools/check_env.sh
./tools/check_offline.sh
./tools/test.sh
godot --headless --path . --editor --quit
godot --headless --path . --export-debug "Android Debug" build/android/dungeon-office-debug.apk
./tools/verify_android_apk.sh build/android/dungeon-office-debug.apk
./tools/check_env.sh --require-device
adb install -r build/android/dungeon-office-debug.apk
# upload key를 환경 변수로 주입한 출시 gate에서만 실행
./tools/export_android_release.sh
./tools/verify_android_aab.sh build/android/dungeon-office-release.aab
```

- `check_env.sh`: §3의 Godot·template·JDK·SDK package를 검사하고 adb 기기 상태를 보고한다. 실기 gate의 `--require-device`는 연결 기기가 없으면 실패한다.
- `check_offline.sh`: §7.3 금지 의존성과 설정을 검사한다.
- `test.sh`: 데이터, sim, save, app 유스케이스의 자체 headless runner를 실행한다.
- `export_android_release.sh`: 비밀 환경 변수를 검사하고 버전 일치 Gradle template를 필요할 때 설치한 뒤 서명 AAB를 만든다.
- `verify_android_apk.sh`, `verify_android_aab.sh`: package·SDK·금지 권한·게임 카테고리·HOME 부재·arm64 단독 ABI·금지 SDK·백업·런처·법적 원문을 최종 산출물에서 검사한다. AAB는 서명 누락과 임의 signer도 거부한다.
- import check는 누락 리소스·GDScript parse 오류를 차단한다.
- adb 설치는 연결된 물리 기기가 없으면 환경 미준비로 보고 자동 통과시키지 않는다.

스크립트는 성공 0, 실패 비0 exit code를 반환하고 사람이 읽을 요약과 실패 파일·테스트 ID를 출력한다. 비밀과 저장 payload를 출력하지 않는다.

## 13. CI와 로컬 출시 gate

### 13.1 현재 GitHub Actions gate

일반 push와 pull request의 현재 Linux headless 작업은 의도적으로 작다.

1. 저장소 checkout
2. Godot `4.7-stable` headless 설치와 버전 확인
3. `tools/check_offline.sh`로 금지 소스·설정 검사
4. `tools/test.sh`로 프로젝트 import와 현재 데이터·sim·save headless 테스트 실행

하나라도 실패하면 병합할 수 없다. 간헐적 해시 차이는 재실행으로 통과시키지 않는다. 현재 CI는 Android SDK·keystore를 설치하지 않고 APK/AAB, JUnit, 테스트 artifact를 만들지 않는다. MVP 초기 스캐폴드에 사용하지 않는 CI 구조를 미리 추가하지 않는다.

### 13.2 로컬 Android gate

Android 관련 확인은 현재 연결된 물리 기기와 로컬 SDK에서 §12 명령으로 수행한다.

1. 고정 환경 검사
2. debug APK export
3. APK package·manifest·ABI 검사
4. adb clean install·update install
5. 비행기 모드 cold start·R1 smoke·snapshot 복귀
6. API 24 emulator smoke

결과는 릴리스 체크 기록에 commit SHA, 기기·API, APK SHA-256과 함께 남긴다. 기기 serial과 서명 비밀은 기록하지 않는다.

### 13.3 Play 후보 전 추가할 보호 gate

Play 비공개 테스트 AAB를 처음 만들 때 다음을 보호 gate로 활성화한다.

- 현재 `Android Release` preset 검증과 저장소 밖 upload key 주입
- AAB export, 실제 manifest의 target SDK 35+·INTERNET 없음 검사
- versionCode 재사용 방지
- 같은 commit의 headless·로컬 debug APK gate 통과 증거

release AAB를 CI에서 만들기로 승인하면 기본 branch의 수동 보호 작업으로만 실행하고 fork·일반 PR에 secret을 전달하지 않는다. artifact는 AAB와 비밀이 없는 검증 요약만 허용하며 keystore, 암호, 사용자 save, 로컬 플레이 로그는 포함하지 않는다.

## 14. 미래 유료 스테이지에 열어 둘 최소 경계

현재 구현에는 Billing·상품·권한·잠금 UI를 만들지 않는다. 미래 가능성을 막지 않기 위해 지금 지킬 것은 다음뿐이다.

- `com.mrkimkim.dungeonoffice`와 Play App Signing 계보 유지
- `CLIENT_MVP_01`, `R1`~`R5`, 아이템·레시피 ID의 저장 호환성 유지
- `enhancement_capability_owned`를 상업 entitlement로 재사용하지 않음
- ProfileV1을 순차 migration할 수 있게 유지
- 게임 진행 해금 판정과 미래 구매 권한 판정을 다른 필드·서비스로 분리할 수 있는 app 경계 유지

후속 유료 스테이지가 제품·비즈니스 문서에서 승인되는 버전에만 Billing, 상품, 구매 승인·복원·환불, 오프라인 entitlement 정책과 UX를 별도 계약으로 추가한다.

## 15. 예외와 실패 처리

- Godot·template·SDK 핀이 다르면 빌드 전에 실패시키고 자동으로 다른 버전을 사용하지 않는다.
- 패키지 데이터 검증 실패는 부팅 차단 결함이며 저장 초기화로 해결하지 않는다.
- 외부 앱 intent 실패는 게임·설정·법적 원문 열람을 차단하지 않는다.
- 햅틱 미지원 기기에서는 기능을 숨기거나 미지원으로 표시하고 오류를 반복 기록하지 않는다.
- safe area API가 값을 주지 않으면 전체 viewport를 안전 영역으로 쓰되 QA 대상 기기에서 잘림이 없음을 별도 확인한다.
- Android 저장 공간 부족과 쓰기 권한 실패는 `TECH-DATA-001`의 저장 실패로 전달하고 성공 상태를 선반영하지 않는다.
- release signing secret이 없으면 release AAB 작업만 실패한다. debug 개발과 테스트가 임의 release key를 생성해 후보인 척하지 않는다.

## 16. 검증 방법

- `project.godot`과 export preset의 package·standard template·renderer·orientation을 자동 검사한다.
- 최종 APK manifest에서 INTERNET와 비허용 민감 권한이 0건인지 확인한다.
- 비행기 모드·Play 서비스 비활성 상태에서 신규 시작→R5, 저장→복구, 법적 원문 열람을 수행한다.
- API 24 emulator에서 cold start, R1 한 판, 일시정지·snapshot 복귀 smoke를 수행한다.
- 15·30·60·120 렌더 FPS에서 같은 명령 fixture의 sim·event 해시가 같다.
- background·화면 잠금·외부 intent·강제 종료 위치별 snapshot 복귀를 실기에서 검증한다.
- debug APK clean install과 이전 후보 위 update install을 모두 수행한다.
- CI와 Android ARM 실기의 `sim_version`, `data_version`, 골든 해시가 일치한다.
- repository와 CI 로그에서 keystore·암호·비밀값 노출 검색 결과가 0건이다.

## 17. 완료 조건

- 고정 도구 체인으로 로컬과 CI에서 같은 Godot 프로젝트를 import·test·export할 수 있다.
- debug APK가 물리 Android 기기에 설치되고 R1~R5와 중단 복귀를 오프라인으로 실행한다.
- release AAB가 정확한 package ID·target API·ABI·권한과 Play upload 서명으로 생성된다.
- 모듈 의존 방향을 위반하는 참조와 sim 금지 API가 없다.
- 데이터·저장·시뮬레이션 의미가 이 문서에 복제되지 않고 전용 계약을 참조한다.
- 최종 산출물에 네트워크·광고·분석·결제 SDK와 INTERNET 권한이 없다.
- `QA-MVP-001`의 자동·실기·Play 출시 게이트가 필요한 증거를 얻는다.
