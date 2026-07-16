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

현재 코드는 **R1~R5 직접 조작 가능한 오프라인 플레이테스트 구현**이며, 그레이박스 위에 `ART-MVP-001`의 캐주얼 의사 3D 1차 아트 패스를 적용했다. 자동화와 에뮬레이터 확인은 사람과 물리 기기가 필요한 수동 게이트를 대신하지 않는다.

구현됨:

- 부팅 → 타이틀 → 지도·브리핑 → R1~R5 직접 조작 → 정산·해금·재도전
- 아이템을 시설·인벤토리·납품대·쓰레기통으로 직접 옮기는 드래그 우선 제작·납품 UI와 탭 대체 조작
- 의뢰별 원자재 총량·선행 공정을 표시하며 열람 중 실제 라운드를 멈추는 제작법 화면
- 일시정지·백그라운드 자동 중단·자동 저장·이어하기·재시작·포기
- 게임 내 골드 상점, R5 강화 설비와 결정론적 +1 강화
- R1~R5 콘텐츠·밸런스 JSON과 참조 검증
- 렌더링과 분리된 20Hz 시뮬레이션 계약
- `ProfileV1`, `RoundSnapshotV1` 원자적 저장·백업 복구
- 설정·기본 접근성·플레이테스트용 효과음/햅틱과 법적 고지의 오프라인 표시
- `art/mvp/runtime/`의 타이틀 배경 1장·시설 7종·아이템 8종과 콘텐츠 ID 기반 표현 카탈로그
- Android debug APK와 서명 AAB export/검증 도구
- 문서 DAG, R1~R5 결정론·도달 경로, 저장·재개, 직접 조작 UI·앱 흐름 자동 테스트

아직 완성되지 않음:

- 물리 Android 기기의 R1~R5·수명주기·세이프 에어리어·성능 수동 검증
- 개발에 참여하지 않은 5인의 1차 아트 패스 플레이테스트와 결과 기반 밸런스 확정
- 최종 아트·애니메이션·음악·사운드 폴리시와 접근성 실기 검증
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

1. [`QA-MVP-001`](docs/qa-release.md)의 체크리스트로 물리 Android 기기의 R1~R5·중단 복귀·오프라인·세이프 에어리어·성능을 확인한다.
2. 발견한 P0·P1과 플레이를 막는 UX 결함을 수정하고 같은 후보 빌드로 회귀한다.
3. 1차 아트 패스 5인 플레이테스트를 실행해 관찰·인터뷰 결과를 `QA-MVP-001` 양식에 집계한다.
4. 실패한 재미·이해도 기준에 한해 코어 UX·밸런스를 수정하고 재검증한다.
5. 통과한 뒤 최종 표현과 Play 등록 에셋을 만든다.

마지막 갱신: 2026-07-15, Android 무료 오프라인 플레이테스트와 캐주얼 의사 3D 1차 아트 패스 기준.
