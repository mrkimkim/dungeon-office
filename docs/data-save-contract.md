# 던전 오피스 — MVP 데이터·저장 계약

| 메타데이터 | 값 |
|---|---|
| 문서 ID | `TECH-DATA-001` |
| 제목 | 던전 오피스 — MVP 데이터·저장 계약 |
| 목적 | 콘텐츠 투영 데이터와 로컬 저장의 스키마·버전·원자성·복구·마이그레이션을 구현자가 추측 없이 재현하도록 고정한다. |
| 담당 영역 | `CatalogV1`, `RoundDefinitionV1`, `ProfileV1`, `RoundSnapshotV1`, 정규 JSON, 버전 규칙, 원자 저장, 정산·구매 멱등성, 손상 복구 |
| 상태 | Draft |
| 버전 | 0.1.0 |
| 적용 범위 | Android 로컬 프로필 1개와 동시에 진행 가능한 라운드 1개 |
| 상위 원칙 문서 | `GDD-001`, `MVP-001` |
| `depends_on` | `SYS-CORE-001`, `SYS-PROG-001`, `SYS-ECON-001`, `CNT-ITEM-001`, `CNT-RECIPE-001`, `CNT-MVP-ROUND-001`, `BAL-MVP-001`, `UX-MVP-001`, `TECH-SIM-001` |
| `consumed_by` | `TECH-MVP-001`, `QA-MVP-001` |
| Source of Truth | 런타임 JSON 스키마, 영속 파일 필드·경로·버전, 원자 교체와 후보 선택, 정산·구매 트랜잭션 순서, 손상·불일치 복구 |
| 명시적 비담당 | 아이템·레시피·라운드의 의미, 확정 밸런스 숫자, 게임 규칙, 사용자 문구·화면 배치, Android 빌드·서명 |
| 미결정 사항 | 없음 |
| 마지막 갱신일 | 2026-07-14 |

## 1. 이 문서가 답하는 질문

- 문서의 콘텐츠·수치를 런타임 JSON에 어떤 타입으로 투영하는가?
- 저장해야 하는 영구 상태와 라운드 한정 상태는 정확히 무엇인가?
- 앱이 정산 또는 구매 중 어느 지점에서 종료되어도 왜 중복 지급·부분 구매가 생기지 않는가?
- 주본·임시본·백업본 중 무엇을 신뢰하고 어떻게 복구하는가?
- 앱 업데이트 때 프로필과 진행 중 라운드는 각각 어떻게 처리하는가?
- `save_version`, `sim_version`, `data_version`은 어떤 변경에서 올라가는가?
- Markdown 규범 문서와 실행 JSON이 어긋나는 것을 어떻게 차단하는가?

이 문서는 스키마와 영속 처리의 유일한 Source of Truth다. 콘텐츠의 정체성·관계·숫자는 선행 문서가 소유하며, 런타임 JSON은 그 결정을 실행하기 위한 **생성된 투영물**이다.

## 2. 저장과 데이터의 불변 원칙

1. 모든 플레이·저장·복구는 네트워크 없이 완료된다.
2. MVP는 계정, 클라우드 세이브, 원격 설정, 원격 콘텐츠를 사용하지 않는다.
3. 영속 파일은 앱 전용 `user://` 아래에만 두며 외부 저장소 권한을 요구하지 않는다.
4. 한 파일 안에서는 정수·불리언·문자열·배열·객체·`null`만 사용한다. 게임 판정 소수는 없다.
5. 알 수 없는 필드, 누락된 필수 필드, 범위를 벗어난 값은 조용히 보정하지 않고 검증 실패로 처리한다.
6. 프로필과 라운드 스냅샷은 서로 다른 수명과 복구 정책을 가진다.
7. 정산과 상점 구매는 UI 표시가 아니라 영속 트랜잭션 완료가 성공 경계다.
8. 저장 파일에는 가격·영수증·구매 토큰·상업 entitlement 필드를 만들지 않는다. `enhancement_capability_owned`는 게임 내 골드로 얻는 진행 플래그다.

## 3. 물리 파일과 권한

### 3.1 패키지에 포함되는 읽기 전용 데이터

```text
res://data/catalog.json
res://data/rounds.json
```

| 파일 | 타입 | 책임 |
|---|---|---|
| `catalog.json` | `CatalogV1` | 아이템·시설·일꾼·레시피·의뢰·경제·임계값의 실행 투영 |
| `rounds.json` | `RoundCatalogV1` | 거래처와 R1~R5 실행 정의 |

릴리스 빌드는 이 파일을 쓰지 않는다. 원격 다운로드·캐시·핫픽스 경로는 없다.

### 3.2 앱 전용 영속 파일

```text
user://save/profile.json
user://save/profile.json.tmp
user://save/profile.json.bak
user://save/round_snapshot.json
user://save/round_snapshot.json.tmp
user://save/round_snapshot.json.bak
```

MVP는 프로필 하나와 진행 중 라운드 하나만 허용한다. 파일 이름에 사용자 입력, 계정 ID, 날짜를 넣지 않는다.

## 4. JSON 공통 규칙

### 4.1 타입과 ID

- 모든 정수는 부호 있는 64비트 범위 안에 있어야 하며 각 필드의 더 좁은 제약을 우선한다.
- `StringID`는 정규식 `^[A-Z][A-Z0-9_:\-]{0,63}$`를 만족하는 ASCII 문자열이다.
- `RunID`는 로컬 단조 번호를 표현하는 정규식 `^run:[0-9]{8}$` 문자열이다.
- `SemVerString`은 정규식 `^[0-9]+\.[0-9]+\.[0-9]+$`, `StringHex64`는 `^[0-9a-f]{64}$`를 만족한다.
- 파일 경로, 표시 문구, 사용자 입력을 `StringID`로 사용하지 않는다.
- 열거형은 이 문서에 적힌 대문자 문자열만 허용한다.
- 모든 필드는 필수다. `?`로 표기한 필드는 생략하지 않고 JSON `null`을 쓴다.
- 스키마가 명시하지 않은 추가 필드는 오류다.

### 4.2 정규 JSON

해시와 골든 fixture에는 다음 정규 바이트를 사용한다.

1. UTF-8, BOM 없음
2. 객체 키를 Unicode code point 오름차순으로 정렬
3. 배열 순서는 보존
4. 공백·개행 없음
5. 정수는 선행 0 없는 10진수, `-0` 금지
6. 불리언은 `true`/`false`, 빈 값은 `null`
7. 문자열은 JSON 표준 최소 이스케이프를 사용하고 Unicode는 NFC로 정규화

SHA-256은 이 바이트에 적용하고 소문자 64자리 16진수로 저장한다.

### 4.3 저장 파일 체크섬

각 영속 파일은 §11.1의 `SaveEnvelopeV1.checksum_sha256`에 payload 정규 JSON 해시를 둔다. 로드할 때 JSON 파싱, envelope 확인, 체크섬, payload 필드·도메인 불변식 순으로 검증한다.

## 5. 문서에서 실행 데이터로의 단일 방향 투영

콘텐츠와 수치의 규범 소유자는 다음과 같다.

| 데이터 영역 | 규범 문서 |
|---|---|
| 아이템·시설·일꾼 | `CNT-ITEM-001` |
| 레시피 입력·출력 | `CNT-RECIPE-001` |
| 거래처·라운드·의뢰 순서 | `CNT-MVP-ROUND-001` |
| 모든 실행 숫자 | `BAL-MVP-001` |
| 진행·경제 의미 | `SYS-PROG-001`, `SYS-ECON-001` |

`catalog.json`과 `rounds.json`은 새로운 결정을 내리는 장소가 아니라 앱이 읽는 versioned projection이다. MVP에서는 별도 생성기와 manifest 파일을 만들지 않는다. 대신 모든 변경은 반드시 다음 단일 커밋 순서를 따른다.

1. 규범 문서와 문서 버전을 먼저 변경한다.
2. 같은 커밋에서 두 JSON 중 영향을 받는 투영을 변경한다.
3. `source_documents`의 해당 문서 버전을 맞춘다.
4. 실행 의미가 바뀌면 두 파일의 공통 `data_version`을 함께 1 올린다.
5. 같은 커밋에서 영향받는 fixture와 기대 해시를 갱신하고 변경 이유를 리뷰에 기록한다.

각 파일은 다음 trace 타입을 가진다.

```text
SourceRef {
  id: StringID,
  version: SemVerString
}
```

`source_documents`에는 해당 파일이 실제 투영하는 모든 규범 문서를 정확히 한 번 넣는다. 배열 순서는 의미가 없으며 중복 ID는 오류다. CI는 문서 metadata의 현재 버전과 일치하는지, 필수 문서 ID가 빠지지 않았는지 검사한다. JSON의 숫자·ID를 임의 변경하고 문서·fixture를 그대로 둔 커밋은 승인하지 않는다.

## 6. `CatalogV1`

### 6.1 최상위 타입

```text
CatalogV1 {
  schema: "CatalogV1",
  data_version: int,
  source_documents: Array<SourceRef>,
  rules: CatalogRulesV1,
  items: Array<ItemDefinitionV1>,
  facilities: Array<FacilityDefinitionV1>,
  recipes: Array<RecipeDefinitionV1>,
  requests: Array<RequestTemplateV1>,
  shop_products: Array<ShopProductV1>
}
```

`data_version`은 1 이상의 정수이며 `rounds.json`과 같아야 한다. 모든 정의 배열은 문서의 규범 순서를 보존한다. 순회가 판정에 영향을 주는 곳은 런타임이 명시적으로 ID 또는 콘텐츠 순서로 정렬한다. 표시명은 콘텐츠 문서의 한국어 이름 투영이며 UI 문장 카피의 Source of Truth가 아니다.

### 6.2 공통 실행 규칙

```text
CatalogRulesV1 {
  tick_rate: 20,
  overheat_grace_ticks: int,
  overheat_danger_ticks: int,
  request_urgent_ticks: int,
  deadline_warning_ticks: int,
  deadline_countdown_ticks: int
}
```

모든 tick 값은 양수다. `overheat_danger_ticks < overheat_grace_ticks`, `deadline_countdown_ticks < deadline_warning_ticks`여야 한다. 값은 `BAL-MVP-001`을 `TECH-SIM-001`의 20Hz 변환으로 투영한다.

### 6.3 아이템·시설

```text
ItemDefinitionV1 {
  id: StringID,
  display_name: String,
  category: "raw_material" | "processed_material" | "equipment",
  enhanceable: bool
}

FacilityDefinitionV1 {
  id: StringID,
  display_name: String,
  role: "supply" | "processor" | "worker_processor" |
        "delivery" | "trash"
}
```

- `enhanceable=true`는 `equipment`에만 허용한다.
- 납품 가능 여부는 `category=equipment`, 공급 가능 여부는 `RoundDefinitionV1.supply_items`로 판정한다.
- 시설 role은 `CNT-ITEM-001`의 코어 역할을 위 문자열에 투영한다.
- 일꾼은 MVP에서 `ENT_WORKER` 한 종류뿐이므로 별도 실행 정의를 만들지 않고 라운드의 `worker_count`와 안정적인 `WORKER_%02d` 인스턴스 규칙을 사용한다.

### 6.4 레시피

```text
RecipeItemV1 {
  item_id: StringID,
  enhancement_level: 0 | 1,
  count: int
}

RecipeDefinitionV1 {
  id: StringID,
  facility_id: StringID,
  inputs: Array<RecipeItemV1>,
  output: RecipeItemV1,
  worker_mode: "none" | "one",
  overheat_output: bool,
  duration_ticks: int
}
```

- `count`와 `duration_ticks`는 양수다. MVP 출력 수량은 콘텐츠 문서 계약을 만족해야 한다.
- 입력 배열은 `(item_id, enhancement_level)` 오름차순이며 같은 키를 두 번 쓰지 않는다.
- `overheat_output=true`와 `worker_mode=none`의 허용 관계는 `CNT-RECIPE-001` 검증을 따른다.
- `duration_ticks`는 `BAL-MVP-001` 값을 `TECH-SIM-001`의 변환식으로 만든 투영값이다.

### 6.5 의뢰

```text
RequestTemplateV1 {
  id: StringID,
  item_id: StringID,
  required_level: 0 | 1,
  score: int,
  patience_ticks: int,
  forecast: bool
}
```

요청 대상은 납품 가능한 장비여야 한다. `score`와 `patience_ticks`는 양수이며 `BAL-MVP-001`의 투영값이다.

### 6.6 상점 상품

```text
ShopProductV1 {
  id: StringID,
  display_name: String,
  price_gold: int,
  requires_round_clear: StringID,
  grants_capability: "enhancement_capability_owned"
}
```

MVP 배열은 `SHOP_ENHANCEMENT_KIT` 한 항목만 가진다. 가격은 0 이상이며 숫자의 Source of Truth는 `BAL-MVP-001`, 상품 의미는 `SYS-ECON-001`이다.

## 7. `RoundCatalogV1`과 `RoundDefinitionV1`

### 7.1 파일과 라운드 타입

```text
RoundCatalogV1 {
  schema: "RoundCatalogV1",
  data_version: int,
  source_documents: Array<SourceRef>,
  client: ClientDefinitionV1,
  rounds: Array<RoundDefinitionV1>
}

ClientDefinitionV1 {
  id: "CLIENT_MVP_01",
  display_name: String
}

RoundDefinitionV1 {
  id: StringID,
  display_name: String,
  deadline_ticks: int,
  active_request_slots: int,
  worker_count: int,
  inventory_capacity: int,
  required_capability: "" | "enhancement_capability_owned",
  supply_items: Array<StringID>,
  facilities: Array<StringID>,
  cutlines: [int, int, int],
  rewards: { "0": int, "1": int, "2": int, "3": int },
  first_clear_bonus: int,
  events: Array<RequestEventV1>
}

RequestEventV1 {
  event_id: StringID,
  request_id: StringID,
  release_tick: int
}
```

### 7.2 검증 불변식

- `rounds`는 `R1`부터 `R5`까지 콘텐츠 진행 순서이며 각 ID를 정확히 한 번 가진다.
- `data_version`은 `CatalogV1`과 같은 1 이상의 정수다.
- 시간·용량·슬롯·일꾼 수·커트라인·보상은 `BAL-MVP-001`의 투영값이다.
- `deadline_ticks`, `active_request_slots`, `inventory_capacity`는 양수다.
- `0 <= release_tick < deadline_ticks`다.
- `events`는 `(release_tick, 콘텐츠 이벤트 순서)`로 정렬하며 이벤트 ID는 전 라운드에서 유일하다.
- `cutlines[0] < cutlines[1] < cutlines[2]`이며 모두 양수다.
- `rewards`는 별 0~3 키를 정확히 한 번 가지고 값은 0 이상이다.
- 모든 시설·의뢰·공급 아이템·capability 참조가 존재해야 한다.
- 사용 가능한 레시피는 설치된 `facilities`와 그 레시피의 `facility_id`로 결정한다.
- 모든 의뢰 산출물이 해당 라운드의 시설·레시피·공급 재료로 제작 가능해야 한다.
- MVP 데이터에는 요청 풀, 가중치, 난수 seed, 원격 URL, **Google Play 상품 ID**, 상업 entitlement 필드가 없다.

## 8. `ProfileV1`

### 8.1 전체 스키마

```text
ProfileV1 {
  schema: "ProfileV1",
  save_version: 1,
  gold: int,
  enhancement_capability_owned: bool,
  rounds: Object<StringID, RoundRecordV1>,
  client_contract_completed: bool,
  mvp_completed: bool,
  tutorial_flags: Object<StringID, bool>,
  settings: SettingsV1,
  next_run_sequence: int,
  applied_result_ids: Array<RunID>
}

RoundRecordV1 {
  unlocked: bool,
  best_score: int,
  best_stars: int,
  first_cleared: bool,
  completion_count: int
}

SettingsV1 {
  music_volume: int,
  sfx_volume: int,
  haptics_enabled: bool,
  color_assist_enabled: bool,
  large_text_enabled: bool
}
```

### 8.2 불변식과 파생 상태

- `gold`, 점수, 완료 횟수는 0 이상이다. `best_stars`는 0~3이다.
- `rounds`는 현재 데이터의 R1~R5 키를 정확히 한 번 가진다.
- `R1.unlocked=true`다. Rn을 처음 클리어하면 R(n+1)의 `unlocked=true`를 같은 프로필 커밋에서 저장한다.
- `first_cleared == (best_stars >= 1)`이며 true에서 false로 돌아가지 않는다. 이 플래그가 최초 클리어 보너스 지급 여부다.
- `client_contract_completed`와 `mvp_completed`는 모두 `R5.first_cleared`와 같은 값이다.
- 볼륨은 0~100 정수다.
- `tutorial_flags`의 키는 승인된 튜토리얼 step ID만 허용한다.
- `next_run_sequence`는 1 이상의 단조 증가 정수다.
- 새 run ID는 현재 값을 사용한 `run:%08d`이고, 값을 1 올린 프로필 저장이 성공한 뒤에만 라운드를 만든다.
- `applied_result_ids`는 중복 없는 적용 순서 배열이며 최대 64개다. 초과하면 가장 오래된 ID부터 제거한다.

`unlocked`, `first_cleared`, 계약 플래그는 UI가 빠르게 읽는 MVP용 영속 투영이다. 정산 시 `SYS-PROG-001`과의 위 불변식을 한 프로필 객체에서 함께 검증하며 부분 갱신하지 않는다. R5 입장 가능 여부는 `R5.unlocked`와 `enhancement_capability_owned`를 모두 확인한다.

### 8.3 새 프로필 기본값

새 프로필은 다음 기술 기본값으로 시작한다.

```text
enhancement_capability_owned = false
R1 record = { unlocked: true, best_score: 0, best_stars: 0,
              first_cleared: false, completion_count: 0 }
R2~R5 record = 위와 같되 unlocked: false
client_contract_completed = false
mvp_completed = false
tutorial_flags = {}
settings = { music: 100, sfx: 100, haptics: true,
             color_assist: false, large_text: false }
next_run_sequence = 1
applied_result_ids = []
```

시작 골드 숫자는 `BAL-MVP-001`을 투영해 넣으며 이 문서에 복제하지 않는다. 새 프로필 파일의 영속화가 완료되기 전에는 지도에 진입하지 않는다.

## 9. `RoundSnapshotV1`

```text
RoundSnapshotV1 {
  schema: "RoundSnapshotV1",
  save_version: 1,
  sim_version: int,
  data_version: int,
  run_id: RunID,
  round_state: RoundStateV1
}
```

- `sim_version`은 실행 코드가 선언한 현재 버전과 같아야 한다.
- `data_version`은 패키지 `CatalogV1`과 `RoundCatalogV1`의 공통 값과 같아야 한다.
- `round_state`는 `TECH-SIM-001` §4의 모든 필드를 동일 이름·타입으로 직렬화한다. 열거형은 문자열, nullable 필드는 `null`, 정렬 배열은 규정 순서를 유지한다.
- 진행 중에는 실행 상태를 저장하고, 기한 종료 직후에는 `ENDED` 결과 상태를 먼저 snapshot으로 저장한 뒤 정산한다. 이 종료 snapshot이 crash 뒤 같은 `result_id` 정산을 재구성하는 근거다.
- 복원해 화면에 넘길 때는 상태를 `PAUSED`로 강제하되 틱과 다른 타이머는 바꾸지 않는다.

라운드 개시 직후, 일시정지, 앱 백그라운드 진입, 사용자의 저장 후 나가기, 플레이 중 30초 간격에 저장한다. 30초는 저장 주기라는 기술값이며 게임 판정에 들어가지 않는다.

## 10. 버전 계약

| 버전 | 형식 | bump 조건 | 호환 처리 |
|---|---|---|---|
| `save_version` | 1부터 증가하는 정수 | 프로필·스냅샷 필드, 타입, 불변식 또는 정규화 의미 변경 | 프로필은 순차 migration, 스냅샷은 현재 판 재시작 |
| `sim_version` | 1부터 증가하는 정수 | 틱 순서, 명령·거절·이벤트, 상태 전이, 해시 결과 변경 | 기존 스냅샷 폐기 후 라운드 재시작 |
| `data_version` | 1부터 증가하는 정수 | catalog 또는 rounds의 실행 의미·값 변경 | 기존 스냅샷 폐기 후 라운드 재시작, 프로필 보존 |
| 런타임 `schema` 이름 | `CatalogV1`, `RoundCatalogV1` | catalog·rounds 구조 변경 시 새 이름 | 지원 parser가 없으면 빌드 실패/부팅 차단 |
| Android `versionCode` | 배포 정수 | Play에 올리는 빌드마다 증가 | 저장 호환 판정에 직접 사용하지 않음 |

`source_documents`의 문서 버전만 동기화되고 실행 필드가 같으면 `data_version`을 올리지 않는다. 화면 문구·아트·사운드만 바뀌어 시뮬 상태와 실행 데이터가 같으면 `sim_version`과 `data_version`을 올리지 않는다. 골든 해시 변화가 있는 코드 변경인데 `sim_version` 또는 `data_version`이 그대로면 CI가 실패한다.

## 11. 원자 파일 교체

### 11.1 `SaveEnvelopeV1`

프로필과 스냅샷 payload는 같은 envelope로 감싼다.

```text
SaveEnvelopeV1 {
  schema: "SaveEnvelopeV1",
  checksum_sha256: StringHex64,
  payload: ProfileV1 | RoundSnapshotV1
}
```

체크섬은 payload의 §4.2 정규 JSON SHA-256이다. envelope 바깥의 값으로 게임 상태를 결정하지 않는다.

### 11.2 커밋 순서

모든 영속 파일은 같은 디렉터리에서 다음 순서로 쓴다.

1. 완전한 새 payload와 `SaveEnvelopeV1`을 메모리에서 만든다.
2. `<name>.tmp`를 새로 쓰고 `flush`, `close`한다.
3. `.tmp`를 다시 읽어 JSON·체크섬·payload 스키마·도메인 불변식을 검증한다.
4. 기존 `.bak`을 제거한다.
5. 정상 주본이 있으면 주본을 `.bak`으로 rename한다.
6. 검증된 `.tmp`를 주본 이름으로 rename한다.
7. 주본을 다시 읽어 검증한 뒤에만 호출자에게 성공을 반환한다.

6단계가 실패하고 `.bak`만 남아 있으면 즉시 주본 이름으로 되돌리기를 시도한다. 부분 파일을 주본에 덮어쓰지 않는다. 쓰기 실패는 메모리 상태를 성공으로 확정하지 않는다.

### 11.3 부팅 후보 선택

주본과 `.bak`을 각각 독립 검증한 뒤 다음 규칙으로 고른다.

1. 주본이 유효하면 주본을 사용한다.
2. 주본이 없거나 무효이고 `.bak`이 유효하면 백업을 사용하고 복구 사실을 로컬 로그와 UI에 전달한다.
3. 둘 다 없으면 해당 저장 종류가 없는 상태다.
4. 하나라도 존재하지만 둘 다 무효면 복구 불가 상태다.

`.tmp`는 호출자가 성공을 받지 못한 미커밋 후보이므로 부팅 데이터로 채택하지 않는다. 자동 복구가 발생하면 사용자가 확인하기 전 백업·손상 파일을 삭제하지 않는다. 다음 정상 저장은 복구한 payload를 기반으로 새 주본과 백업을 만든다.

## 12. 멱등 트랜잭션

MVP는 별도 pending transaction 파일과 범용 트랜잭션 엔진을 만들지 않는다. 동시에 한 프로필·한 라운드만 존재한다는 범위 안에서 `run_id`와 전체 Profile 원자 교체로 정산을 멱등하게 만든다.

### 12.1 `SettlementV1`

```text
SettlementV1 {
  schema: "SettlementV1",
  result_id: RunID,
  round_id: StringID,
  score: int,
  stars: int,
  repeat_reward: int,
  first_clear_bonus: int,
  deliveries: Array<DeliveryRecord>,
  withdrawal_count: int,
  overheat_loss_count: int
}
```

`result_id`는 해당 snapshot의 `run_id`와 같다. 종료 snapshot과 현재 `RoundCatalogV1`에서 같은 `SettlementV1`을 재구성할 수 있어야 한다. `stars`, 보상, 기록 갱신은 `SYS-PROG-001`, `SYS-ECON-001`과 projection 데이터로 계산한다.

### 12.2 라운드 시작과 run ID

1. 브리핑에서 입장 조건을 현재 프로필로 검증한다.
2. `run_id`에 현재 `next_run_sequence`를 할당하고 값을 1 증가시킨 프로필을 원자 저장한다.
3. 저장 성공 뒤 해당 run의 초기 `RoundSnapshotV1`을 원자 저장한다.
4. 스냅샷 성공 뒤에만 플레이 화면과 틱 실행을 연다.

3단계가 실패하면 라운드를 시작하지 않는다. 이미 소비된 run 번호는 재사용하지 않으며 이는 진행·재화 손실이 아니다.

### 12.3 정산 커밋 순서

1. `ROUND_ENDED` 상태를 `round_snapshot.json`에 먼저 원자 저장한다.
2. 종료 상태와 `run_id`에서 `SettlementV1`을 만든다.
3. `result_id`가 현재 `profile.applied_result_ids`에 있으면 골드·기록·완료 횟수를 다시 바꾸지 않고 이미 적용된 성공으로 판정한다.
4. 새 ID면 프로필의 메모리 복사본에서 골드, 기록, 최초 클리어, 순차 해금, 계약 플래그를 모두 계산하고 ID를 배열 끝에 추가한다.
5. 배열이 64개를 넘으면 가장 오래된 ID부터 제거한다.
6. 변경한 **ProfileV1 전체를 한 번 원자 교체**한다.
7. 저장된 프로필을 다시 읽어 `result_id`와 결과 불변식을 검증한다.
8. 그 뒤에만 해당 snapshot 주본·tmp·bak을 삭제한다.
9. snapshot 삭제 뒤 결과 화면을 저장 완료 상태로 열고 지도·재도전을 허용한다.

프로필 저장 실패 시 snapshot을 유지하고 결과 화면에서 재시도한다. 메모리에서만 지급하거나 프로필 성공 전에 snapshot을 삭제하지 않는다. 64개 cap은 동시에 snapshot 하나만 존재하고, 적용 성공 직후 그 snapshot을 삭제하며, 새 run이 그 뒤에만 시작된다는 MVP 전제에서 안전하다. 오래된 ID가 제거된 뒤 그 결과의 snapshot이 다시 나타날 정상 경로가 없다.

### 12.4 구매 커밋 순서

1. 상품 노출, 미소유, 골드 충분 조건을 현재 프로필로 다시 검증한다.
2. 현재 프로필의 메모리 복사본에서 골드 차감과 `enhancement_capability_owned=true`를 함께 적용한다.
3. 변경한 ProfileV1 전체를 한 번 원자 교체한다.
4. 주본 재검증 뒤에만 구매 완료와 R5 입장 가능 상태를 표시한다.

저장 전에 보여 준 애니메이션은 확정 표시가 아니다. 프로필 쓰기가 실패하면 메모리 표시를 마지막 정상 프로필로 되돌리고 `UX-SAVE-07`을 따른다.

구매는 capability가 이미 true면 `already_owned`로 거절하므로 저장 성공 뒤 같은 입력이 재실행되어도 이중 차감되지 않는다. 정산·구매 저장이 진행되는 동안 다른 프로필 저장과 새 라운드 시작을 받지 않는다.

## 13. 크래시 복구 행렬

부팅은 프로필 후보를 먼저 복구하고 snapshot을 처리한다.

| 종료 지점 | 다음 부팅 처리 | 중복·손실 방지 근거 |
|---|---|---|
| 종료 snapshot 저장 전 | 마지막 정상 진행 snapshot으로 이어하기 | 프로필 변화 없음, 끝나지 않은 판으로 복귀 |
| 종료 snapshot 저장 후, 프로필 전 | 같은 종료 snapshot으로 정산 재시도 | `result_id` 고정 |
| 프로필 교체 후, snapshot 삭제 전 | 종료 snapshot을 다시 읽되 ID가 이미 있어 무지급·무증가 후 삭제 | 이중 지급 없음 |
| snapshot 삭제 후, 결과 표시 전 | 프로필이 완료 사실의 Source of Truth | 진행·골드는 보존, 결과 요약 재구성 가능 |
| 구매 프로필 교체 전 | 마지막 정상 프로필 사용 | 골드·capability 모두 구매 전 |
| 구매 프로필 교체 후, UI 표시 전 | capability=true 프로필 사용 | 골드·capability 모두 구매 후 |

프로필 저장 실패 시 메모리 변경도 확정하지 않는다. 반면 프로필 주본 검증이 성공한 뒤 앱이 종료되면 UI를 아직 못 봤더라도 트랜잭션은 성공이다.

## 14. 로드·손상·불일치 처리

### 14.1 프로필

- 주본이 손상됐지만 유효한 `.bak`이 있으면 §11.3으로 자동 복구하고 `UX-SAVE-01`을 표시한다.
- 주본과 `.bak`이 모두 **존재하지 않을 때만** 정상 최초 실행으로 보고 새 프로필 생성을 제안한다. 남은 `.tmp`는 실패한 미커밋 생성 시도로 제거 또는 격리한다.
- 파일 흔적은 있으나 유효 후보가 없으면 자동 초기화하지 않고 `UX-SAVE-02`로 간다.
- 현재 앱보다 높은 `save_version`은 손상이 아니라 `PROFILE_VERSION_TOO_NEW`다. 원본을 보존하고 덮어쓰지 않는다.
- 낮은 지원 버전은 §15 migration이 성공한 뒤 현재 형식으로 원자 저장한다.

### 14.2 스냅샷

- 손상되고 유효 백업도 없으면 프로필은 그대로 보존하고 `UX-SAVE-03`에서 현재 판 폐기를 확인한다.
- `save_version`, `sim_version`, `data_version` 중 하나라도 호환되지 않으면 snapshot을 로드·migration하지 않는다. `UX-SAVE-04`를 보여준 뒤 해당 라운드 브리핑부터 다시 시작한다.
- 종료 상태 snapshot이면 이어하기 화면보다 §12.3의 동일 `result_id` 정산 재시도를 우선한다.
- 프로필에 없는 round ID, 잘못된 item 위치, 중복 인스턴스, 시설 상태 불변식 위반은 손상이다.

### 14.3 삭제와 보존

- 사용자가 확인한 라운드 재시작·포기 또는 성공한 정산 뒤에만 snapshot 후보를 삭제한다.
- 새 게임 2단계 확인 전에는 복구 불가 프로필 파일을 덮어쓰지 않는다.
- 새 게임을 확정하면 기존 세 파일을 `user://save/quarantine/` 아래 세션 번호로 이동하고 새 프로필을 만든다. 진단용 격리 파일은 앱에서 외부 전송하지 않는다.

## 15. 프로필 migration

프로필 migration은 한 단계씩만 존재한다.

```text
migrate_v1_to_v2(v1) -> v2
migrate_v2_to_v3(v2) -> v3
...
```

- 버전을 건너뛰는 함수와 현재 버전으로의 임의 보정은 금지한다.
- 각 단계는 같은 입력에 같은 출력을 내는 순수 함수다.
- migration 전 원본을 `.bak`과 격리 fixture로 보존한다.
- 각 단계 뒤 새 스키마와 도메인 불변식을 검증한다.
- 전 단계가 성공한 뒤에만 최신 프로필을 원자 저장한다.
- 실패하면 원본을 유지하고 `PROFILE_MIGRATION_FAILED`로 차단한다.
- 지원한 모든 과거 버전의 최소·경계·실사용 익명 fixture를 테스트에 영구 보관한다.

MVP 첫 버전은 입력 버전 1만 존재하므로 migration 함수는 아직 없다. 빈 미래 인터페이스나 가짜 v0 fixture를 만들지 않는다. 첫 schema 변경과 함께 v1 fixture와 `v1_to_v2`를 같은 변경에 추가한다.

## 16. 데이터·저장 오류 코드

```text
DATA_PARSE_FAILED
DATA_CHECKSUM_MISMATCH
DATA_SCHEMA_UNSUPPORTED
DATA_INVARIANT_FAILED
PROFILE_NOT_FOUND
PROFILE_CORRUPT
PROFILE_VERSION_TOO_NEW
PROFILE_MIGRATION_FAILED
SNAPSHOT_CORRUPT
SNAPSHOT_VERSION_MISMATCH
SNAPSHOT_SIM_MISMATCH
SNAPSHOT_DATA_MISMATCH
SAVE_WRITE_FAILED
SAVE_VERIFY_FAILED
SETTLEMENT_INVALID
```

코드는 로컬 진단과 UI 카피 매핑의 안정 ID다. 파일 내용, 경로, 기기 식별자를 사용자 화면이나 외부 앱에 자동 첨부하지 않는다.

## 17. 시스템 인터페이스

| 대상 | 입력으로 받는 것 | 출력으로 제공하는 것 |
|---|---|---|
| 콘텐츠·밸런스 문서 | 안정 ID, 관계, 숫자 | 검증된 실행 투영과 `source_documents` 추적 |
| `TECH-SIM-001` | `RoundStateV1`, 결과 패킷, 버전 의미 | catalog·round 정의 뷰, snapshot 직렬화 |
| `SYS-PROG-001` | 별·기록·계약 판정 | 영속 프로필과 멱등 정산 결과 |
| `SYS-ECON-001` | 보상·구매 원자성 규칙 | gold·capability 단일 커밋 |
| `UX-MVP-001` | 오류·복구 사용자 보장 | 복구 상태, 오류 코드, 재시도 결과 |
| `TECH-MVP-001` | 없음 | 파일 경계, repository API, CI 검증 계약 |
| `QA-MVP-001` | 없음 | 손상·migration·crash fixture와 기대 결과 |

저장 계층의 앱 API는 최소 다음 결과형을 제공한다.

```text
LoadProfileResult = OK(profile) | RECOVERED(profile, source) | ERROR(code)
LoadSnapshotResult = NONE | OK(snapshot) | RESTART_REQUIRED(code) | ERROR(code)
SaveResult = OK | ERROR(code)
SettlementResult = APPLIED(result_id, profile)
                 | ALREADY_APPLIED(result_id, profile)
                 | ERROR(code)
```

UI는 파일을 직접 읽거나 골드·기록을 선반영하지 않는다.

## 18. 검증 방법

- `CatalogV1`과 `RoundDefinitionV1`의 모든 필드에 정상·누락·추가·범위 오류 fixture를 둔다.
- 각 JSON의 `source_documents` ID·version이 실제 규범 문서 metadata와 일치해야 한다.
- 카탈로그의 모든 ID 참조, 생산 그래프, 라운드 제작 가능성, 커트라인과 이벤트 순서를 검증한다.
- 저장 파일마다 write 단계 1~7 사이에 종료를 주입하고 유효한 주본 또는 직전 정상 백업을 복구해야 한다.
- 정산·구매 단계마다 종료를 주입해 골드 지급·차감과 capability가 정확히 0회 또는 1회만 적용돼야 한다.
- 프로필 정산 커밋 성공 직후 snapshot 삭제 전에 종료하는 fixture를 필수로 두고, 다음 부팅 정산에서 `ALREADY_APPLIED`, 추가 골드 0, 완료 횟수 무증가를 확인한 뒤 snapshot을 삭제해야 한다.
- `applied_result_ids`가 64개인 프로필에서 새 정산이 가장 오래된 ID 하나만 제거하고 현재 종료 snapshot의 ID를 보존하는지 검사한다.
- 주본·bak의 유효/손상 조합과 미커밋 tmp 잔존을 후보 선택 테이블 테스트로 검사한다.
- `TECH-SIM-001`의 골든 로그를 임의 20틱에서 snapshot round-trip한 결과가 무중단 해시와 같아야 한다.
- 현재보다 높은 save version, 다른 sim version, 다른 data version fixture가 프로필 보존·라운드 재시작으로 끝나야 한다.
- 앱을 비행기 모드로 두고 신규 프로필, R1~R5, 중단 복원, 정산, 구매, 설정 저장이 모두 동작해야 한다.

## 19. 완료 조건

- 네 규범 스키마와 모든 하위 타입·불변식이 닫힌 형태로 정의되어 있다.
- 문서→실행 JSON이 같은 커밋의 `source_documents`·공통 `data_version`·fixture로 추적된다.
- 주본·tmp·bak의 선택과 손상·버전 불일치 처리가 모든 조합에서 결정되어 있다.
- 정산과 구매가 크래시 지점과 관계없이 멱등이며 부분 적용될 수 없다.
- 프로필 migration과 스냅샷 폐기 정책이 분리되어 있다.
- 실행과 저장에 네트워크·계정·클라우드·상업 entitlement가 필요하지 않다.
- `TECH-MVP-001`과 `QA-MVP-001`이 구현·자동화할 경로와 결과형을 추측 없이 얻는다.
