# Dungeon Office

Android 전용 무료 MVP를 위한 Godot 4.7 프로젝트다. 현재 구현은 전체 흐름과 핵심 재미를 검증하는 **오프라인 플레이테스트 빌드**이며, 그레이박스 위에 캐주얼 의사 3D 1차 아트 패스를 적용하는 단계다.

- 부팅 → 타이틀 → 지도·브리핑 → R1~R5 직접 조작 → 정산·해금·재도전
- 아이템을 시설·인벤토리·납품대·쓰레기통 사이로 직접 끌어 놓는 제작·납품 화면
- 의뢰별 원자재 총량과 전체 선행 공정을 보여주는 일시정지 제작법 화면
- 일시정지·백그라운드 자동 중단, 5초 자동 저장, 이어하기·재시작·포기
- R4 이후 게임 내 골드로 여는 강화 설비와 R5의 결정론적 +1 강화
- R1~R5 카탈로그·밸런스 JSON 로드와 참조 검증
- 렌더링과 분리된 20Hz 정수 틱 시뮬레이션
- `ProfileV1`, `RoundSnapshotV1` 원자적 로컬 저장과 백업 복구
- 큰 글씨·색 보조·음량·햅틱 설정과 오프라인 법적 고지
- 3/4 직교 렌더형 2D PNG 타이틀 배경 1장·시설 7종·아이템 8종의 1차 아트 패스
- 외부 애드온·서버·광고·분석·결제·네트워크 권한 없음
- Android application ID: `com.mrkimkim.dungeonoffice`

이 빌드는 **현재 R1~R5가 전부 무료**이며 현금 결제·페이월·구매 복원 코드나 화면이 없다. 후속 스테이지 유료 해금은 별도 승인 시 새로 설계할 미래 선택지일 뿐 현재 기능이 아니다.

설계의 Source of Truth는 [`docs/README.md`](docs/README.md)에서 시작한다.

## 1차 아트 패스

비주얼 테마는 장난감 디오라마처럼 둥글고 읽기 쉬운 **던전 배달 대장간**이다. 실제 3D 런타임 대신 같은 3/4 직교 카메라와 조명을 미리 렌더한 2D PNG를 사용한다. 정확한 카메라·재질·상태색·에셋 전수와 개별 PNG→선택적 아틀라스 전환 조건은 [`ART-MVP-001`](docs/art-spec.md)을 따른다.

현재 `art/mvp/runtime/`에는 타이틀 배경 1장, `384×384` 시설 7장과 `256×256` 아이템 8장이 있다. 검토한 외부 CC0 후보는 런타임에 포함하지 않았으므로 이 패스에 추가 제3자 에셋 고지는 필요하지 않다. 특정 상용 게임의 캐릭터·주방·로고·UI·소품 같은 고유 표현을 모사하지 않는다.

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

에디터에서 프로젝트를 실행하면 세로형 직접 조작 UI와 1차 아트 패스가 열린다. 새 게임을 시작해 R1부터 공급→변환→제작→납품을 직접 조작하고, 별 1개 이상으로 완료하면 다음 라운드로 진행한다.

## 테스트

외부 테스트 애드온 없이 자체 headless runner를 사용한다.

```bash
./tools/test.sh
```

테스트는 문서 DAG·역참조·Wave, 데이터 trace, 명령 거절의 무변경성, R1~R5의 유효한 ★1·★3 명령 경로, R1 fixture 100회 재현, R5의 20개 저장 지점 재개, 저장 백업 복구, 정산 멱등성, 직접 조작 화면과 앱 흐름을 검사한다.

자동화와 에뮬레이터 확인만으로 외부 플레이테스트 완료나 출시 준비 완료를 선언하지 않는다. 남은 수동 게이트는 [`QA-MVP-001`](docs/qa-release.md)의 체크리스트와 결과 양식에 기록한다.

- 보유한 물리 Android 기기에서 설치·R1~R5·중단 복귀·오프라인·세이프 에어리어·성능 확인
- 개발에 참여하지 않은 첫 플레이어 5명의 무설명 1차 아트 패스 테스트와 관찰·인터뷰
- 테스트 결과에 따른 코어 UX·밸런스 수정과 재검증
- 그 이후의 최종 캐릭터·애니메이션·VFX·스토어 이미지, Dungeon Office 전용 upload key, Play Console 등록

## Android export

`export_presets.cfg`에는 standard-template debug APK와 Gradle-template Play AAB preset이 있지만 서명 비밀은 없다. 두 preset 모두 minSdk 24, target/compileSdk 36, `INTERNET` 권한 없음, 햅틱용 `VIBRATE`만 허용, Android 자동 백업 비활성화를 유지한다.

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
