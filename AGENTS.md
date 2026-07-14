# AGENTS.md — 던전 오피스 작업 안내

이 저장소에서 작업을 시작할 때 먼저 읽는 짧은 핸드오프다. 규범적 설계의 시작점은 [`docs/README.md`](docs/README.md)이며, 이 파일은 현재 상태와 작업 규칙만 요약한다.

## 프로젝트 한 줄 요약

**던전 오피스**는 던전 원정대의 의뢰를 받아 제한된 일손과 시설로 장비를 제작·납품하는 Android 세로형 오프라인 타임 매니지먼트 게임이다. 플레이는 확률 판정이 아닌 20Hz 정수 틱 결정론을 따른다.

## 확정된 MVP 경계

- 플랫폼: Android 단독
- application ID: `com.mrkimkim.dungeonoffice`
- 엔진: Godot `4.7-stable`, typed GDScript
- 콘텐츠: 거래처 1곳, R1~R5
- 획득 가격: 현재 MVP는 무료
- 현재 앱 내부 결제·광고·분석·계정·서버·인터넷 권한: 없음
- 미래 선택지: 후속 스테이지의 비소모성 유료 해금은 가능성만 열어 두며 현재 코드·SDK·상품·화면에는 미리 만들지 않음
- 저장: 앱 전용 로컬 저장소, 자체 클라우드 없음
- 지원 이메일: `2020promoking@gmail.com`
- 공개 지원/정책: `https://mrkimkim.github.io/dungeon-office/`

가격과 미래 유료 확장 경계는 `BUS-MVP-001`, Play·개인정보 경계는 `REL-PLAY-001`이 소유한다. GDD에 상업 정책이나 구체 규칙을 되돌려 넣지 않는다.

## 현재 구현 상태

현재 코드는 **완성 MVP가 아니라 실제 개발 계약을 실행하는 수직 뼈대**다.

구현됨:

- 부팅 → 타이틀 → 새 게임/이어하기 → 결정론적 R1 데모 → 정산
- R1~R5 콘텐츠·밸런스 JSON과 참조 검증
- 렌더링과 분리된 20Hz 시뮬레이션 계약
- `ProfileV1`, `RoundSnapshotV1` 원자적 저장·백업 복구
- 개인정보처리방침·오픈소스 고지의 오프라인 표시
- Android debug APK와 서명 AAB export/검증 도구
- 문서 DAG, 데이터, 시뮬레이션, 저장·정산, 법적 UI 자동 테스트

아직 완성되지 않음:

- 플레이어가 직접 조작하는 R1~R5 전체 게임 화면과 모든 UX 예외 경로
- 최종 아트·애니메이션·오디오·햅틱·접근성 구현
- 최종 밸런스와 5인 외부 플레이테스트
- 스토어용 아이콘·기능 그래픽·실제 후보 스크린샷
- 실제 upload key와 Play Console 등록

계획을 현재 기능처럼 표현하지 않는다. 정확한 현재 범위는 루트 [`README.md`](README.md), 최종 완료 조건은 `MVP-001`과 `QA-MVP-001`을 따른다.

## 문서 작업 규칙

1. `docs/README.md`의 문서 카탈로그와 dependency DAG를 먼저 확인한다.
2. 각 결정은 해당 문서 ID의 Source of Truth에서만 정의한다.
3. 하위 문서는 내용을 복제하지 않고 안정적인 문서 ID와 절을 참조한다.
4. 확정 수치·공식은 `BAL-MVP-001`, 항목의 정체성·관계는 각 콘텐츠 문서가 소유한다.
5. UX는 사용자 상태·행동·결과를, UI는 이를 충족하는 화면·컴포넌트를 소유한다.
6. 의존성 순환이 생기면 공통 전제를 상위 계약으로 추출한다.
7. 문서 추가·삭제·dependency 변경 후 `./tools/test.sh`의 문서 그래프 검사를 통과시킨다.

## 개발 환경과 검증

필수 도구와 정확한 버전은 [`README.md`](README.md) 및 `TECH-MVP-001`을 따른다. 기본 로컬 게이트:

```bash
./tools/check_env.sh
./tools/check_offline.sh
./tools/test.sh
godot --headless --path . --export-debug "Android Debug" build/android/dungeon-office-debug.apk
./tools/verify_android_apk.sh build/android/dungeon-office-debug.apk
```

실기 smoke 직전에는 `./tools/check_env.sh --require-device`를 사용한다. Play 후보 AAB는 Dungeon Office 전용 upload key가 준비된 승인된 출시 작업에서만 만든다.

## 보안·생성물 규칙

- 다른 앱의 keystore를 복사하거나 재사용하지 않는다.
- keystore, 암호, 인증서 개인키와 Play 계정 복구 정보는 저장소·로그·PR에 넣지 않는다.
- 공개 SHA-256 upload certificate fingerprint만 릴리스 기록에 남긴다.
- `.godot/`, `android/`, `build/`, `*.apk`, `*.aab`, `*.jks`, `*.p12`는 생성물 또는 비밀이며 추적하지 않는다.
- `android/`는 Godot 4.7 공식 Gradle template를 AAB export 때 재생성하는 로컬 작업 디렉터리다.

## 다음 개발 우선순위

1. `UX-MVP-001`·`UI-MVP-001`을 따라 R1의 직접 조작 루프를 완성한다.
2. 같은 명령/상태 계약을 유지하며 R2~R5 기능과 골든 fixture를 순차 추가한다.
3. 저장·중단·손상·복구·설비/재화 부족 등 예외 경로를 실제 화면에 연결한다.
4. 물리 Android 기기에서 수명주기·세이프 에어리어·성능을 확인한다.
5. 그레이박스 5인 플레이테스트가 통과한 뒤 최종 표현과 Play 등록 에셋을 만든다.

마지막 갱신: 2026-07-14, Android 무료 오프라인 MVP 구현 기준선 수립.
