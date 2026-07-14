# Dungeon Office

Android 전용 무료 MVP를 위한 Godot 4.7 프로젝트다. 현재 구현은 화려한 최종 게임이 아니라, 아래 개발 계약을 실제로 실행하고 테스트하는 수직 뼈대다.

- 부팅 → 타이틀 → 새 게임/이어하기 → 결정론적 라운드 → 정산
- R1~R5 카탈로그·밸런스 JSON 로드와 참조 검증
- 렌더링과 분리된 20Hz 정수 틱 시뮬레이션
- `ProfileV1`, `RoundSnapshotV1` 원자적 로컬 저장과 백업 복구
- 외부 애드온·서버·광고·분석·결제·네트워크 권한 없음
- Android application ID: `com.mrkimkim.dungeonoffice`

설계의 Source of Truth는 [`docs/README.md`](docs/README.md)에서 시작한다.

## 요구 환경

- Godot `4.7-stable` 및 같은 버전의 APK·Gradle source export templates
- OpenJDK `17`
- Android SDK Platform `36`
- Android SDK Build Tools `36.1.0`
- Android SDK Platform Tools (`adb`)
- Android NDK `29.0.14206865`
- CMake `3.10.2.4988404`
- Android 실기기 또는 `adb`가 연결된 에뮬레이터
- Play AAB 검증 시 `bundletool` `1.18.3`

Godot 4.7 template의 Android 범위는 minSdk 24, target/compileSdk 36이다. 따라서 MVP의 공식 지원 하한은 Android API 24이며, target API 35 이상을 요구하는 Play 출시 게이트도 충족한다. debug APK는 standard template를 사용하고, Play AAB를 만들 때만 같은 Godot 버전의 공식 Gradle template를 무시된 `android/` 작업 디렉터리에 자동 설치한다. Android 소스를 별도로 커스터마이즈하거나 저장소에 복제하지 않는다.

환경 확인:

```bash
./tools/check_env.sh
# 실제 설치 smoke 직전
./tools/check_env.sh --require-device
```

## 실행

```bash
godot --editor --path .
```

에디터에서 프로젝트를 실행하면 최소 UI가 열린다. R1 화면의 `R1 결정론 데모 실행`은 실제 공급→제련→제작→납품 명령을 20Hz 시뮬레이터에 넣고 기한까지 진행한 뒤 정산한다.

## 테스트

외부 테스트 애드온 없이 자체 headless runner를 사용한다.

```bash
./tools/test.sh
```

테스트는 19개 문서 DAG·역참조·Wave, 데이터 trace, 명령 거절의 무변경성, R1 골든 fixture 결정론, 저장 백업 복구, 정산 멱등성과 프로필 저장 직후 중단 복구를 검사한다.

## Android export

`export_presets.cfg`에는 standard-template debug APK와 Gradle-template Play AAB preset이 있지만 서명 비밀은 없다. 두 preset 모두 minSdk 24, target/compileSdk 36, `INTERNET` 권한 없음, Android 자동 백업 비활성화를 유지한다.

debug APK를 만든 뒤 manifest와 번들 경계를 검사할 수 있다.

```bash
godot --headless --path . --export-debug "Android Debug" /tmp/dungeon-office-debug.apk
./tools/verify_android_apk.sh /tmp/dungeon-office-debug.apk
```

Play 후보가 필요해지면 먼저 Dungeon Office 전용 upload key를 대화형으로 만든다. 다른 앱의 key를 재사용하지 않는다.

```bash
./tools/create_upload_keystore.sh
```

keystore와 암호를 각각 저장소 밖에 백업한 뒤 아래 환경 변수로만 release export에 주입한다.

```bash
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$HOME/.config/dungeon-office/signing/dungeon-office-upload.p12"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="dungeon-office-upload"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="..."
./tools/export_android_release.sh
./tools/verify_android_aab.sh build/android/dungeon-office-release.aab
```

검증기는 위 keystore에서 공개 SHA-256 인증서 지문을 읽어 AAB signer와 대조한다. private keystore에 접근하지 않는 환경에서는 대신 공개값인 `EXPECTED_UPLOAD_CERT_SHA256`을 지정해야 하며, 둘 다 없으면 임의의 자체 서명 키를 통과시키지 않고 실패한다. 암호를 shell history에 남기지 않으려면 마지막 변수는 현재 shell에서 `read -s` 등으로 입력한다. Google Play에서는 Play App Signing을 사용하고, 이 로컬 key는 upload key 역할로만 쓴다.

`src/ui/app_icon.svg`는 export 오류 없이 개발 빌드를 식별하기 위한 임시 앱 아이콘이며 최종 스토어 아트가 아니다.

## 저장 파일

Godot의 `user://save/` 아래에 다음 파일이 생긴다.

- `profile.json`: 영구 진행과 설정
- `round_snapshot.json`: 진행 중 라운드 전체 상태
- 각 파일의 `.bak`: 직전 정상 저장 후보

저장은 checksum envelope와 임시 파일 → rename 순서를 사용한다. 주 파일이 손상되면 유효한 `.bak`을 복구 후보로 반환하며 자동으로 새 게임을 만들지 않는다.

## 지원·개인정보

GitHub Pages가 공개 지원 채널과 개인정보처리방침을 제공한다.

- 지원: <https://mrkimkim.github.io/dungeon-office/>
- 개인정보처리방침: <https://mrkimkim.github.io/dungeon-office/privacy/>
- 오픈소스 고지: <https://mrkimkim.github.io/dungeon-office/licenses/>

Pages와 앱 내부 법적 고지는 같은 `site/**/*.md` 원문을 사용한다. 웹사이트에 접근하지 못해도 설치된 앱의 게임·저장·법적 고지는 모두 오프라인으로 동작한다.
