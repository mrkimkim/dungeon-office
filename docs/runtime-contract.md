# 던전 오피스 — MVP 결정론적 런타임 계약

| 메타데이터 | 값 |
|---|---|
| 문서 ID | `TECH-SIM-001` |
| 제목 | 던전 오피스 — MVP 결정론적 런타임 계약 |
| 목적 | R1~R5 시뮬레이션의 상태·명령·이벤트·틱 경계를 구현자가 해석 없이 재현할 수 있도록 고정한다. |
| 담당 영역 | 고정 틱, 라운드 상태 타입, 명령·결과·거절 타입, 이벤트 순서, 동시 사건 우선순위, UI 읽기 모델, 결정론 fixture |
| 상태 | Draft |
| 버전 | 0.1.0 |
| 적용 범위 | `CLIENT_MVP_01`의 R1~R5 로컬 싱글플레이 |
| 상위 원칙 문서 | `GDD-001`, `MVP-001` |
| `depends_on` | `SYS-CORE-001`, `SYS-PROG-001`, `CNT-ITEM-001`, `CNT-RECIPE-001`, `CNT-MVP-ROUND-001`, `BAL-MVP-001`, `UX-MVP-001`, `UI-MVP-001` |
| `consumed_by` | `TECH-DATA-001`, `TECH-MVP-001`, `QA-MVP-001` |
| Source of Truth | 시뮬레이션의 정확한 시간 의미, 직렬화 대상 상태 타입, 명령·거절·이벤트 계약, 한 틱 안의 순서, 런타임 읽기 모델 |
| 명시적 비담당 | 게임 규칙의 존재 이유, 콘텐츠 목록·관계, 확정 밸런스 값, JSON 저장 형식, 화면 배치, 플랫폼·빌드 구조 |
| 미결정 사항 | 없음 |
| 마지막 갱신일 | 2026-07-14 |

## 1. 이 문서가 답하는 질문

- `tick=0` 의뢰는 언제 보이고 언제부터 인내가 줄어드는가?
- 같은 틱에 납품과 기한 만료, 회수와 과열 소실이 겹치면 무엇이 이기는가?
- 작업 시작 틱이 작업 시간에 포함되는가?
- 일시정지와 재개는 틱과 타이머를 소비하는가?
- UI 입력은 어떤 타입으로 시뮬레이션에 들어가고, 실패하면 어떤 단일 사유를 받는가?
- 화면은 내부 상태를 직접 해석하지 않고 어떤 읽기 모델을 소비하는가?
- 동일 명령열의 동일 결과를 어떤 fixture로 증명하는가?

게임 규칙과 콘텐츠의 의미는 선행 문서가 소유한다. 이 문서는 그 결정을 실행 가능한 이산 시간 계약으로 번역한다. 이 문서에 나오는 합성 테스트 값은 경계 검증용이며 `BAL-MVP-001`의 출시 수치를 대체하지 않는다.

## 2. 시뮬레이션 순수성

시뮬레이션 코어는 다음 입력만 받는다.

1. 검증 완료된 카탈로그와 라운드 정의의 불변 뷰
2. `RoundStateV1`
3. 현재 틱에 예약된 `SimCommandV1` 목록

시뮬레이션 코어는 다음에 접근하지 않는다.

- `Node`, SceneTree, 렌더 프레임과 애니메이션 상태
- `Input`, 터치 좌표, Android 생명주기 API
- OS 벽시계, 타임존, 프레임 델타
- 파일·네트워크 I/O
- 난수 API와 순회 순서가 보장되지 않은 해시 컨테이너

핵심 함수의 관찰 가능한 계약은 다음과 같다.

```text
step(state, commands_for_state_tick, catalog, round_definition)
  -> StepResult(next_state, command_results, events)
```

모든 입력이 동일하면 정규 직렬화된 `next_state`, `command_results`, `events`의 바이트가 동일해야 한다. 표현 계층은 이벤트를 소비할 수 있지만 시뮬레이션 상태를 직접 변경할 수 없다.

## 3. 시간 모델

### 3.1 단위와 표기

- 시뮬레이션은 **20Hz 고정 틱**이며 한 틱은 정확히 50ms다.
- 런타임의 모든 시간은 0 이상의 정수 틱이다.
- `BAL-MVP-001`의 초 단위 정수 `s`는 `s × 20`으로 변환한다. 나눗셈·반올림은 없다.
- `state.tick`은 **다음에 실행할 틱의 0 기반 번호**다.
- `remaining_ticks`는 해당 시점 이후 남은 완전한 시간 구간 수다.
- 렌더 보간에 실수를 사용할 수 있지만 판정·저장·해시에는 들어가지 않는다.

### 3.2 라운드 생성과 `tick=0`

`create_round()`는 다음을 원자적으로 수행한다.

1. 콘텐츠가 정한 시설·일꾼·인벤토리의 초기 상태를 만든다.
2. `state.tick = 0`, `phase = RUNNING`으로 둔다.
3. `release_tick = 0`인 의뢰 이벤트를 콘텐츠 순서대로 공개한다.
4. 빈 활성 슬롯에는 즉시 활성화하고 나머지는 FIFO 대기에 넣는다.
5. `next_schedule_index`를 첫 `release_tick > 0` 이벤트로 옮긴다.

이 부트스트랩은 틱을 소비하지 않으며 작업·인내·과열·기한을 감소시키지 않는다. 따라서 플레이어가 첫 입력을 볼 때 `release_tick=0` 의뢰는 이미 활성 상태이고 인내는 원래 값 그대로다.

### 3.3 작업 시간 경계

작업이 틱 `t`의 명령 단계에서 시작되면 `remaining_work_ticks`를 레시피의 전체 작업 틱으로 설정한다. 같은 틱의 시간 진행 단계에서 1을 감소시킨다.

```text
start_tick = t
duration_ticks = d
completion_tick = t + d - 1
```

`d=1`인 합성 fixture 작업은 틱 `t` 끝에 완료된다. 출시 데이터의 `d`는 `BAL-MVP-001`을 변환한 값만 사용한다. 작업 완료로 새로 생긴 과열 유예 타이머는 완료 틱에는 감소하지 않고 다음 진행 틱부터 감소한다.

### 3.4 마지막 유효 틱

라운드의 전체 길이가 `D`틱이면 플레이 가능한 틱은 `0..D-1`이다. 틱 `D-1`의 명령을 처리한 뒤 기한 잔량이 0이 되고 라운드가 끝난다. `tick=D` 명령은 존재할 수 없다.

- 틱 `D-1`에 유효하게 납품한 점수는 최종 점수에 포함한다.
- 같은 틱의 명령보다 뒤에서 인내·과열·기한 만료를 처리한다.
- 종료 뒤에는 새 명령을 평가하지 않는다.

## 4. `RoundStateV1`

아래 타입은 메모리와 스냅샷이 공유하는 규범적 상태다. JSON 표현은 `TECH-DATA-001`이 소유한다.

### 4.1 최상위 상태

| 필드 | 타입 | 제약·의미 |
|---|---|---|
| `round_id` | `StringID` | 현재 `RoundDefinitionV1`의 ID |
| `tick` | `int` | 다음 실행 틱, `0..deadline_ticks` |
| `deadline_ticks` | `int` | 양수, 라운드 정의와 일치 |
| `phase` | enum | `RUNNING`, `PAUSED`, `ENDED` |
| `score` | `int` | 0 이상 |
| `next_command_sequence` | `int` | 다음 정상 envelope의 일련번호, 0부터 증가 |
| `next_event_sequence` | `int` | 다음 이벤트의 라운드 전역 일련번호, 0부터 증가 |
| `next_item_sequence` | `int` | 다음 아이템 인스턴스 번호, 0부터 증가 |
| `next_activation_sequence` | `int` | 다음 의뢰 활성화 순번, 0부터 증가 |
| `next_schedule_index` | `int` | 아직 공개하지 않은 라운드 의뢰 이벤트 배열 인덱스 |
| `workers` | `Array<WorkerState>` | `worker_id` 오름차순 |
| `facilities` | `Array<FacilityState>` | `facility_id` 오름차순 |
| `items` | `Array<ItemInstance>` | `instance_id` 오름차순 |
| `inventory_slots` | `Array<StringID?>` | 고정 길이, 각 값은 `items`의 인스턴스 ID 또는 `null` |
| `active_requests` | `Array<RequestState?>` | 라운드의 활성 슬롯 수와 같은 고정 길이 |
| `waiting_requests` | `Array<WaitingRequest>` | 공개 순서 FIFO |
| `deliveries` | `Array<DeliveryRecord>` | `delivered_tick`, 이벤트 순서 오름차순 |
| `withdrawn_count` | `int` | 0 이상 |
| `overheat_loss_count` | `int` | 0 이상 |
| `threshold_flags` | `ThresholdFlags` | 일회성 경계 이벤트 발행 여부 |
| `result` | `RoundResultPacket?` | `ENDED`에서만 존재 |

ID 배열은 구현 언어의 사전 순회 순서에 의존하지 않는다. 상태를 바꾸는 다중 대상 처리는 위 표의 안정 정렬 순서를 따른다.

### 4.2 하위 타입

```text
WorkerState {
  worker_id: StringID,
  worker_type_id: StringID,
  assigned_facility_id: StringID?
}

FacilityState {
  facility_id: StringID,
  phase: EMPTY | INPUT_READY | WORKING | OUTPUT_READY,
  input_instance_ids: Array<StringID>,
  job: JobState?,
  output_instance_id: StringID?,
  overheat_remaining_ticks: int?,
  overheat_danger_event_emitted: bool
}

JobState {
  recipe_id: StringID,
  worker_id: StringID?,
  remaining_work_ticks: int
}

ItemInstance {
  instance_id: StringID,
  item_id: StringID,
  enhancement_level: int,
  location: LocationRef
}

LocationRef =
  { kind: INVENTORY, slot_index: int }
  | { kind: FACILITY_INPUT, facility_id: StringID }
  | { kind: FACILITY_OUTPUT, facility_id: StringID }

RequestState {
  request_instance_id: StringID,
  request_template_id: StringID,
  slot_index: int,
  activated_tick: int,
  activation_sequence: int,
  remaining_patience_ticks: int,
  urgent_event_emitted: bool
}

WaitingRequest {
  request_instance_id: StringID,
  request_template_id: StringID,
  release_tick: int
}

DeliveryRecord {
  request_instance_id: StringID,
  item_id: StringID,
  enhancement_level: int,
  awarded_score: int,
  delivered_tick: int
}

ThresholdFlags {
  deadline_warning_event_emitted: bool,
  deadline_countdown_event_emitted: bool
}
```

아이템 인스턴스 ID는 성공적으로 새 아이템을 만들 때만 `ITEM_%06d` 형식으로 발급한다. 공급함 이동이 거절되거나 작업 시작이 실패하면 번호를 소비하지 않는다. 의뢰 인스턴스 ID는 라운드 이벤트 ID를 그대로 사용한다.

`ThresholdFlags`는 라운드 기한 경계 두 개의 발행 여부를 가진다. 시설 과열과 의뢰 임박의 발행 여부는 각각 `FacilityState.overheat_danger_event_emitted`, `RequestState.urgent_event_emitted`가 관리한다. 임계값의 숫자는 `BAL-MVP-001` §4.1이 소유한다.

### 4.3 종료 결과 패킷

```text
RoundResultPacket {
  round_id: StringID,
  final_score: int,
  deliveries: Array<DeliveryRecord>,
  withdrawn_count: int,
  overheat_loss_count: int,
  ended_at_tick: int
}
```

run ID, 별·골드·최초 클리어·기록·계약은 이 패킷에 포함하지 않는다. 앱 계층이 현재 snapshot의 `run_id`를 결과에 결합하고, `SYS-PROG-001`, `SYS-ECON-001`의 판정을 `TECH-DATA-001`의 멱등 정산으로 영속화한다.

## 5. 명령 계약

### 5.1 Envelope와 payload

```text
SimCommandV1 {
  tick: int,
  sequence: int,
  type: CommandType,
  payload: object
}
```

| `CommandType` | 정확한 payload |
|---|---|
| `MOVE` | `{ source: SourceRef, destination: DestinationRef, item_ref: ItemRef }` |
| `START` | `{ facility_id: StringID }` |
| `STORE` | `{ facility_id: StringID }` |
| `DELIVER` | `{ item_instance_id: StringID }` |
| `DISCARD` | `{ item_instance_id: StringID }` |
| `PAUSE` | `{}` |
| `RESUME` | `{}` |

```text
SourceRef =
  { kind: SUPPLY, facility_id: StringID }
  | { kind: INVENTORY, slot_index: int }
  | { kind: FACILITY_INPUT, facility_id: StringID }
  | { kind: FACILITY_OUTPUT, facility_id: StringID }

DestinationRef =
  { kind: INVENTORY, slot_index: int | FIRST_EMPTY }
  | { kind: FACILITY_INPUT, facility_id: StringID }

ItemRef =
  { kind: CATALOG_ITEM, item_id: StringID }
  | { kind: INSTANCE, item_instance_id: StringID }
```

`CATALOG_ITEM`은 `FAC_SUPPLY`에서 꺼낼 때만 허용한다. 나머지 출발지는 `INSTANCE`만 허용한다. 납품과 파기는 의도를 분리하기 위해 `DestinationRef`로 표현하지 않는다. 재시작·포기·라운드 나가기는 결과를 만들지 않고 앱 계층이 새 상태 생성 또는 스냅샷 폐기로 처리하므로 `SimCommandV1`이 아니다.

### 5.2 일련번호와 예약

- 터치 입력은 수신한 렌더 프레임이 아니라 **다음 실행 가능한 시뮬레이션 틱**에 예약한다.
- 한 틱의 명령은 `sequence` 오름차순으로 평가한다.
- `sequence == next_command_sequence`인 구조적으로 유효한 명령만 게임 규칙 평가로 들어간다.
- 규칙상 거절된 명령도 일련번호를 하나 소비한다.
- 더 작은 번호는 `SEQUENCE_DUPLICATE`, 더 큰 번호는 `SEQUENCE_GAP`이며 상태와 일련번호를 바꾸지 않는다.
- `command.tick != state.tick`이면 `COMMAND_TICK_INVALID`이며 상태를 바꾸지 않는다.

### 5.3 일시정지와 재개

일시정지 상태 변경을 포함한 `step`은 **제어 전용 호출**이다.

- `RUNNING`에서 `PAUSE`가 승인되면 그 명령보다 앞선 같은 배치의 게임 명령은 유지되고, 뒤 명령은 `ROUND_PAUSED`로 거절된다. 타이머와 틱은 진행하지 않는다.
- `PAUSED`에서 게임 명령은 `ROUND_PAUSED`로 거절된다.
- `PAUSED`에서 `RESUME`가 승인되면 `phase=RUNNING`으로 바뀌지만 그 호출에서 타이머와 틱은 진행하지 않는다.
- `RUNNING`의 `RESUME`는 `NOT_PAUSED`, `PAUSED`의 `PAUSE`는 `ALREADY_PAUSED`다.
- 앱 백그라운드 전환은 다음 실행 틱에 `PAUSE`를 주입한 뒤 스냅샷 저장을 요청한다.

따라서 정지와 재개 자체는 작업·인내·과열·기한을 1틱도 소비하지 않는다.

## 6. `CommandResultV1`과 거절 계약

### 6.1 결과 타입

```text
CommandResultV1 {
  tick: int,
  sequence: int,
  accepted: bool,
  rejection: RejectionCode,
  first_event_sequence: int?,
  event_count: int
}
```

승인 시 `rejection=NONE`이다. 규칙 평가까지 들어간 명령의 거절은 `COMMAND_REJECTED` 이벤트 하나를 만들고 그 이벤트 범위를 결과에 기록한다. envelope 거절은 상태를 전혀 바꾸지 않으므로 이벤트를 만들지 않는다.

### 6.2 안정적인 `RejectionCode`

```text
NONE
UNKNOWN_COMMAND_TYPE
PAYLOAD_INVALID
COMMAND_TICK_INVALID
SEQUENCE_DUPLICATE
SEQUENCE_GAP
ROUND_ENDED
ROUND_PAUSED
NOT_PAUSED
ALREADY_PAUSED
UNKNOWN_SOURCE
UNKNOWN_DESTINATION
UNKNOWN_FACILITY
UNKNOWN_ITEM
ITEM_NOT_AT_SOURCE
ITEM_NOT_SUPPLIED
ITEM_NOT_MOVABLE
DESTINATION_REJECTS_ITEM
DESTINATION_OCCUPIED
INVENTORY_FULL
FACILITY_BUSY
FACILITY_OUTPUT_OCCUPIED
RECIPE_INPUT_INVALID
RECIPE_INCOMPLETE
NO_IDLE_WORKER
NO_FACILITY_OUTPUT
ITEM_NOT_OWNED
ITEM_NOT_EQUIPMENT
NO_MATCHING_REQUEST
```

문자열은 저장·테스트·UI 매핑에 쓰이는 안정 ID다. 표시 문구로 직접 사용하지 않는다.

### 6.3 공통 우선순위

한 명령에서 여러 문제가 동시에 성립하면 아래의 첫 항목 하나만 반환한다.

1. 닫힌 명령 enum에 없음: `UNKNOWN_COMMAND_TYPE`
2. 해당 타입의 필수 payload 키·타입 불일치: `PAYLOAD_INVALID`
3. `COMMAND_TICK_INVALID`
4. `SEQUENCE_DUPLICATE` 또는 `SEQUENCE_GAP`
5. `ROUND_ENDED`
6. 현재 pause 상태와 맞지 않는 명령: `ROUND_PAUSED`, `NOT_PAUSED`, `ALREADY_PAUSED`
7. source·destination·facility ID 존재 여부
8. item 존재와 source 소속 여부
9. 명령별 상태 조건

명령별 상태 조건의 우선순위는 다음과 같다.

| 명령 | 공통 검사 뒤 거절 우선순위 |
|---|---|
| `MOVE` | `ITEM_NOT_SUPPLIED` → `ITEM_NOT_MOVABLE` → `DESTINATION_REJECTS_ITEM` → `FACILITY_BUSY` → `FACILITY_OUTPUT_OCCUPIED` → `RECIPE_INPUT_INVALID` → `DESTINATION_OCCUPIED` → `INVENTORY_FULL` |
| `START` | `FACILITY_BUSY` → `FACILITY_OUTPUT_OCCUPIED` → `RECIPE_INCOMPLETE` → `NO_IDLE_WORKER` |
| `STORE` | `NO_FACILITY_OUTPUT` → `INVENTORY_FULL` |
| `DELIVER` | `ITEM_NOT_OWNED` → `ITEM_NOT_EQUIPMENT` → `NO_MATCHING_REQUEST` |
| `DISCARD` | `ITEM_NOT_OWNED` → `ITEM_NOT_MOVABLE` |

`DELIVER`와 `DISCARD`에서 “소유”는 인벤토리, 시작 전 시설 입력, 시설 완료 산출물에 있는 인스턴스를 뜻한다. 작업에 이미 소비된 입력은 소유 인스턴스가 아니다.

## 7. 한 틱의 정확한 처리 순서

일시정지 상태 변경이 없는 정상 진행 호출은 아래 순서를 한 번 수행한다.

1. **예약 공개:** `release_tick == state.tick`인 의뢰를 이벤트 ID의 콘텐츠 순서로 공개한다. 빈 슬롯이 있으면 활성화하고, 없으면 FIFO 대기에 넣는다.
2. **명령:** 현재 틱 명령을 `sequence` 오름차순으로 처리한다.
3. **타이머:** 이 틱 시작 전에 존재했거나 명령으로 시작된 작업, 활성 의뢰, 기존 과열 유예, 라운드 기한을 각각 1 감소시킨다. 이 틱 작업 완료로 새로 생길 과열 유예는 아직 존재하지 않으므로 감소하지 않는다.
4. **작업 완료:** 잔량 0인 작업을 `facility_id` 오름차순으로 완료하고 일꾼을 해제하며 산출물을 만든다.
5. **과열 소실:** 잔량 0인 기존 과열 산출물을 `facility_id` 오름차순으로 제거한다.
6. **의뢰 철회:** 인내 0인 활성 의뢰를 `slot_index` 오름차순으로 철회한다.
7. **빈 슬롯 보충:** 대기 FIFO에서 빈 활성 슬롯의 낮은 `slot_index` 순으로 활성화한다. 이 단계에서 활성화된 의뢰의 인내는 다음 진행 틱부터 감소한다.
8. **경계 이벤트:** 감소 전에는 경계 밖이고 감소 후 처음 경계 안에 들어온 과열·의뢰·기한 이벤트를 발행한다. 이미 소실·철회된 대상에는 임박 이벤트를 추가로 발행하지 않는다.
9. **기한 종료:** 기한 잔량이 0이면 결과 패킷을 만들고 `phase=ENDED`로 바꾼다.
10. **틱 증가:** `state.tick += 1` 한다. 종료 상태의 최종 `tick`은 `deadline_ticks`다.

### 7.1 동시 사건 판정표

| 같은 틱의 사건 | 확정 결과 |
|---|---|
| 납품 vs 해당 의뢰 인내 0 | 명령이 먼저이므로 납품 성공, 철회 없음 |
| 납품 vs 라운드 기한 0 | 마지막 유효 틱 납품은 점수에 포함 |
| 회수·이동 vs 과열 0 | 명령이 먼저이므로 회수 성공, 소실 없음 |
| 작업 완료 vs 라운드 기한 0 | 완료 이벤트 뒤 라운드 종료. 산출물은 생기지만 추가 납품 기회와 점수는 없음 |
| 여러 작업 완료 | `facility_id` 오름차순 |
| 여러 의뢰 철회 | 활성 `slot_index` 오름차순 |
| 여러 대기 의뢰 활성화 | 공개 FIFO, 빈 슬롯의 낮은 인덱스 우선 |
| 의뢰 납품으로 빈 슬롯 발생 | 대기 의뢰 보충은 타이머·철회 처리 뒤 §7.7에서 수행하며 새 의뢰는 그 틱에 인내가 줄지 않음 |
| 과열 산출물 완료와 즉시 유예 | 완료 틱에는 유예가 줄지 않음 |

## 8. 이벤트 계약

### 8.1 Envelope

```text
SimEventV1 {
  tick: int,
  sequence: int,
  type: EventType,
  payload: object
}
```

`sequence`는 라운드 전체에서 0부터 연속 증가한다. 이벤트 배열 순서와 `sequence`가 다르면 오류다.

### 8.2 이벤트 타입

| `EventType` | 필수 payload |
|---|---|
| `COMMAND_REJECTED` | `{ command_sequence, rejection }` |
| `ITEM_MOVED` | `{ item_instance_id, from, to }` |
| `WORK_STARTED` | `{ facility_id, recipe_id, worker_id, completes_at_tick }` |
| `WORK_COMPLETED` | `{ facility_id, recipe_id, output_instance_id }` |
| `ITEM_STORED` | `{ facility_id, item_instance_id, slot_index }` |
| `ITEM_DELIVERED` | `{ item_instance_id, request_instance_id, awarded_score }` |
| `ITEM_DISCARDED` | `{ item_instance_id, from }` |
| `OVERHEAT_GRACE_STARTED` | `{ facility_id, item_instance_id }` |
| `OVERHEAT_DANGER_ENTERED` | `{ facility_id, item_instance_id }` |
| `ITEM_LOST_OVERHEAT` | `{ facility_id, item_id, enhancement_level }` |
| `REQUEST_RELEASED` | `{ request_instance_id, request_template_id }` |
| `REQUEST_QUEUED` | `{ request_instance_id, queue_position }` |
| `REQUEST_ACTIVATED` | `{ request_instance_id, slot_index, activation_sequence }` |
| `REQUEST_URGENT_ENTERED` | `{ request_instance_id, slot_index }` |
| `REQUEST_WITHDRAWN` | `{ request_instance_id, slot_index }` |
| `SCORE_CHANGED` | `{ delta, total }` |
| `DEADLINE_WARNING_ENTERED` | `{ remaining_ticks }` |
| `DEADLINE_COUNTDOWN_ENTERED` | `{ remaining_ticks }` |
| `ROUND_PAUSED` | `{}` |
| `ROUND_RESUMED` | `{}` |
| `ROUND_ENDED` | `{ result: RoundResultPacket }` |

`ITEM_DELIVERED` 뒤에 `SCORE_CHANGED`를 발행한다. 작업 시작·완료 이벤트 안에 일꾼 배정·해제를 별도 중복 이벤트로 만들지 않는다. 화면은 이벤트 누락 시에도 읽기 모델을 다시 그리면 정확한 최종 상태를 보여야 한다.

## 9. 임계 상태 계약

숫자는 `BAL-MVP-001` §4.1의 네 파라미터가 소유하며 런타임 데이터에 틱으로 투영한다.

| 파라미터 ID | 상태·이벤트 진입 조건 |
|---|---|
| `overheat_danger_at` | 과열 잔량이 처음 `0 < remaining <= threshold`가 될 때 `OVERHEAT_DANGER_ENTERED` |
| `request_urgent_at` | 의뢰 인내가 처음 `0 < remaining <= threshold`가 될 때 `REQUEST_URGENT_ENTERED` |
| `deadline_warning_at` | 기한이 처음 `0 < remaining <= threshold`가 될 때 `DEADLINE_WARNING_ENTERED` |
| `deadline_countdown_at` | 기한이 처음 `0 < remaining <= threshold`가 될 때 `DEADLINE_COUNTDOWN_ENTERED` |

초기 잔량이 이미 경계 안인 합성 테스트나 향후 데이터에서도 첫 진행 틱의 경계 평가 때 한 번 발행한다. `remaining=0`이면 소실·철회·종료 이벤트만 발행한다. 저장·복원 뒤 일회 이벤트가 반복되지 않도록 발행 플래그를 상태에 보존한다.

## 10. `RoundReadModelV1`

UI는 `RoundStateV1`이나 콘텐츠 JSON을 직접 조합하지 않고 매 틱 또는 이벤트 뒤 생성되는 불변 읽기 모델을 소비한다.

```text
RoundReadModelV1 {
  round_id: StringID,
  tick: int,
  phase: RUNNING | PAUSED | ENDED,
  remaining_ticks: int,
  deadline_level: NORMAL | WARNING | COUNTDOWN,
  score: int,
  workers: Array<WorkerView>,
  facilities: Array<FacilityView>,
  inventory: Array<ItemView?>,
  active_requests: Array<RequestView?>,
  waiting_request_count: int,
  legal_actions: LegalActionView,
  result: RoundResultPacket?
}
```

| 하위 뷰 | 필수 필드 |
|---|---|
| `WorkerView` | `worker_id`, `is_idle`, `assigned_facility_id` |
| `ItemView` | `instance_id`, `item_id`, `enhancement_level`, `location` |
| `FacilityView` | `facility_id`, `phase`, `input_items`, `output_item`, `remaining_work_ticks`, `overheat_remaining_ticks`, `overheat_level`(`NONE/GRACE/DANGER`), `worker_id` |
| `RequestView` | `request_instance_id`, `request_template_id`, `requested_item_id`, `minimum_enhancement_level`, `score`, `remaining_patience_ticks`, `urgency`(`NORMAL/URGENT`), `slot_index` |
| `LegalActionView` | `startable_facility_ids`, `storable_facility_ids`, `legal_destinations_by_item_instance`, `deliverable_item_instance_ids`, `discardable_item_instance_ids`, `supply_item_destinations` |

`LegalActionView`는 동일한 명령 검증기를 읽기 전용으로 호출해 만든다. UI가 레시피, 인벤토리, 일꾼, 납품 우선순위를 다시 구현하면 안 된다. 읽기 모델은 표시명·문구·색·좌표를 포함하지 않는다.

## 11. 결정론 fixture

### 11.1 합성 경계 fixture

아래 fixture는 `tests/fixtures/sim_edges/`에 명령 로그와 기대 상태 JSON으로 보관한다. 수치는 경계를 짧게 재현하기 위한 테스트 전용이다.

| fixture ID | 준비 상태·입력 | 정확한 기대 |
|---|---|---|
| `SIM-EDGE-001` | `release_tick=0`, 인내 3틱 의뢰로 라운드 생성 | 첫 `step` 전 활성·인내 3, 첫 진행 뒤 2 |
| `SIM-EDGE-002` | 작업 시간 3틱, 틱 4에 `START` | 틱 4 뒤 2, 틱 5 뒤 1, 틱 6 끝 완료 |
| `SIM-EDGE-003` | 기한 1틱, 마지막 틱에 매칭 장비 `DELIVER` | 납품·점수 이벤트 뒤 `ROUND_ENDED`, 최종 점수 포함 |
| `SIM-EDGE-004` | 의뢰 인내 1틱, 같은 틱에 `DELIVER` | 납품 성공, `REQUEST_WITHDRAWN` 없음 |
| `SIM-EDGE-005` | 과열 잔량 1틱, 같은 틱에 `STORE` | 수납 성공, `ITEM_LOST_OVERHEAT` 없음 |
| `SIM-EDGE-006` | 작업 두 건이 같은 틱 완료 | `facility_id` 오름차순 완료 이벤트 |
| `SIM-EDGE-007` | 실행 중 `PAUSE`, 이후 `RESUME` | 두 제어 호출 사이와 각 호출에서 `tick`·모든 타이머 불변 |
| `SIM-EDGE-008` | 활성 슬롯 하나, 대기 의뢰 존재, 활성 의뢰 납품 | 대기 의뢰는 같은 틱 보충되며 전체 인내, 다음 진행 틱부터 감소 |
| `SIM-EDGE-009` | 인내·과열이 1틱이고 미처리 | 철회는 슬롯 순, 소실은 시설 ID 순, 임박 이벤트는 0에서 미발행 |

### 11.2 출시 골든 fixture

R1~R5 각각 최소 다음 두 로그를 둔다.

- 별 1 도달 유효 명령 로그
- 문서가 주장하는 최고 목표를 달성하는 유효 명령 로그

manifest는 다음을 가진다.

```text
fixture_id
sim_version
data_version
round_id
initial_state_sha256
commands_sha256
expected_final_state_sha256
expected_event_stream_sha256
```

해시는 `TECH-DATA-001`의 정규 JSON 바이트에 SHA-256을 적용한 소문자 64자리 16진수다. 개발 머신, Linux CI, Android ARM 실기에서 모두 일치해야 한다. 해시가 바뀌면 코드·데이터·기대값을 조용히 함께 갱신하지 않고 변경 원인과 해당 버전 bump를 리뷰에 기록한다.

## 12. 시스템 인터페이스

| 대상 | 입력으로 받는 것 | 출력으로 제공하는 것 |
|---|---|---|
| `SYS-CORE-001` | 상태 전이와 명령의 게임 의미 | 정확한 틱·거절·동시 사건 의미 |
| `CNT-ITEM-001`, `CNT-RECIPE-001` | 안정 ID와 생산 관계 | 인스턴스·시설·작업 상태 타입 |
| `CNT-MVP-ROUND-001`, `BAL-MVP-001` | 일정·수치·임계값 | 이산 틱 실행과 이벤트 스트림 |
| `UI-MVP-001` | 화면이 필요로 하는 정보·행동 | `RoundReadModelV1`, `CommandResultV1` |
| `TECH-DATA-001` | 없음 | 직렬화할 전체 상태와 결과 패킷 |
| `TECH-MVP-001` | 없음 | 구현할 순수 코어 API와 금지 의존성 |
| `QA-MVP-001` | 없음 | 경계 fixture와 결정론 판정 기준 |

## 13. 예외·경계 상태

- 한 틱에 명령이 없더라도 정상 진행 중이면 타이머와 틱은 진행한다.
- 잘못된 명령은 상태를 부분 변경하지 않는다. 성공 또는 완전 무변경 둘 중 하나다.
- `STORE`가 인벤토리 만석으로 실패하면 시설 산출물과 과열 잔량은 그 뒤 같은 틱의 타이머 단계에서 계속 진행한다.
- 작업 완료 산출물 위치가 이미 점유된 상태는 유효 상태가 아니다. 검증기가 시작 전에 차단하고 로드 시 손상으로 판정한다.
- 라운드 종료와 함께 남은 작업·아이템·의뢰를 별도 제거 이벤트로 쏟아내지 않는다. `ROUND_ENDED`와 결과 패킷이 최종 사실이다.
- 스냅샷 복원은 `PAUSED` 상태로만 사용자에게 제시한다. 원래 실행 상태였더라도 자동으로 시간을 진행하지 않는다.

## 14. 검증 방법

- 모든 명령 타입에 승인 1건과 각 거절 코드의 도달 fixture를 둔다.
- §11.1 경계 fixture를 100회 반복해 상태와 이벤트 해시가 같아야 한다.
- 명령 배열 입력 순서를 무작위로 섞어도 `sequence` 정렬 뒤 결과가 같아야 한다.
- R1~R5 골든 로그를 중간 임의 틱에서 저장→복원해도 무중단 결과와 같아야 한다.
- 렌더 FPS 15·30·60·120을 모사해도 실행된 틱과 결과 해시가 같아야 한다.
- 시뮬레이션 소스에서 금지 API 참조가 0건이어야 한다.

## 15. 완료 조건

- 모든 상태·명령·결과·거절·이벤트 필드와 열거형이 닫힌 집합으로 정의되어 있다.
- `tick=0`, 작업 시작 틱, 마지막 틱, 인내·과열·기한 동시 사건이 fixture로 고정되어 있다.
- UI가 규칙을 재구현하지 않고 화면을 만들 수 있는 읽기 모델이 정의되어 있다.
- 상태와 이벤트의 안정 정렬 규칙이 모든 다중 대상 처리에 존재한다.
- 출시 수치가 복제되지 않고 `BAL-MVP-001`을 참조한다.
- `TECH-DATA-001`이 추측 없이 저장 스키마를 만들고 `QA-MVP-001`이 자동 회귀를 구현할 수 있다.
