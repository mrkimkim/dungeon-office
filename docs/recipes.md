# 던전 오피스 MVP 레시피·생산 그래프

| 메타데이터 | 값 |
|---|---|
| 문서 ID | `CNT-RECIPE-001` |
| 제목 | 던전 오피스 MVP 레시피·생산 그래프 |
| 목적 | 유효한 입력 조합이 어떤 시설에서 어떤 출력으로 바뀌는지 정의한다. |
| 담당 영역 | 생산·제작·강화 입력/출력, 수량, 시설, 일꾼 사용 유형, 과열 적용 여부 |
| 상태 | Draft |
| 버전 | 0.1.0 |
| 상위 원칙 문서 | `GDD-001` |
| `depends_on` | `SYS-CORE-001`, `CNT-ITEM-001` |
| `consumed_by` | `CNT-MVP-ROUND-001`, `BAL-MVP-001`, `UI-MVP-001`, `TECH-SIM-001`, `TECH-DATA-001`, `QA-MVP-001` |
| Source of Truth | MVP 전체 레시피 ID, 입력·출력·수량, 실행 시설, 작업자 유형, 생산 그래프 |
| 명시적 비담당 | 아이템 정체성, 작업 상태 전이, 시간·점수, 라운드 배치, UX·UI |
| 미결정 사항 | 철검의 복수 입력 전달성과 R5 병렬 계획 발생 여부는 §11에서 검증한다. |
| 마지막 갱신일 | 2026-07-13 |

## 1. 목적과 범위

이 문서는 어떤 입력 조합이 어떤 시설에서 어떤 출력으로 바뀌는지를 정의한다. 아래 표에 없는 조합은 유효한 MVP 레시피가 아니다.

## 2. 명시적 비범위

- 아이템의 정체성·분류: `CNT-ITEM-001`
- 시설 작동, 일꾼 배정, 과열, 취소 불가 규칙: `SYS-CORE-001`
- 작업 시간과 점수: `BAL-MVP-001`
- 레시피의 라운드별 교육·사용 위치: `CNT-MVP-ROUND-001`
- 조작 순서와 화면 표현: `UX-MVP-001`, `UI-MVP-001`
- 해금 이후의 추가 레시피

## 3. 레시피 표기 계약

| 필드 | 의미 |
|---|---|
| `recipe_id` | 저장·콘텐츠 데이터가 참조하는 안정적인 ID |
| `facility_id` | 작업이 실행되는 시설 |
| `inputs` | 작업 시작 시 소비되는 아이템과 수량 |
| `output` | 작업 완료 시 생성되는 아이템과 상태 |
| `worker_mode` | `none` 또는 `one` |
| `overheat_output` | 완료 산출물에 과열 유예가 적용되는지 여부 |

작업 시간은 레시피 속성으로 구현할 수 있지만 그 값의 Source of Truth는 `BAL-MVP-001`이다.

## 4. 변환 레시피

| recipe_id | 시설 | 입력 | 출력 | worker_mode | 과열 |
|---|---|---|---|:---:|:---:|
| `RCP_SMELT_IRON` | `FAC_FURNACE` | `MAT_IRON_ORE` ×1 | `MAT_IRON_INGOT` ×1 | `none` | 예 |
| `RCP_BURN_CHARCOAL` | `FAC_FURNACE` | `MAT_WOOD` ×1 | `MAT_CHARCOAL` ×1 | `none` | 예 |

두 레시피는 유효 입력이 용광로에 들어오면 별도의 `start` 명령 없이 즉시 시작한다.

## 5. 합성 레시피

| recipe_id | 시설 | 입력 | 출력 | worker_mode | 과열 |
|---|---|---|---|:---:|:---:|
| `RCP_SYNTH_ENHANCEMENT_STONE` | `FAC_SYNTH_BENCH` | `MAT_MANA_SHARD` ×1 + `MAT_CHARCOAL` ×1 | `MAT_ENHANCEMENT_STONE` ×1 | `one` | 아니오 |

마력 파편은 공급함에서 직접 받고, 목탄은 용광로에서 만들어야 한다. 이 비대칭이 R5에서 용광로 시간과 일꾼 시간을 함께 계획하게 한다.

## 6. 장비 제작 레시피

| recipe_id | 시설 | 입력 | 출력 | worker_mode | 과열 |
|---|---|---|---|:---:|:---:|
| `RCP_CRAFT_DAGGER` | `FAC_WEAPON_BENCH` | `MAT_IRON_INGOT` ×1 | `EQ_DAGGER` +0 ×1 | `one` | 아니오 |
| `RCP_CRAFT_IRON_SWORD` | `FAC_WEAPON_BENCH` | `MAT_IRON_INGOT` ×2 | `EQ_IRON_SWORD` +0 ×1 | `one` | 아니오 |

철검은 철 주괴 두 개가 필요하므로 단검보다 깊은 생산 그래프를 가진다. 복수 입력을 시설에 전달하는 상태 전이는 `SYS-CORE-001` §6을 따른다.

## 7. +1 강화 레시피

| recipe_id | 시설 | 입력 | 출력 | worker_mode | 과열 |
|---|---|---|---|:---:|:---:|
| `RCP_ENHANCE_DAGGER_P1` | `FAC_ENHANCE_ANVIL` | `EQ_DAGGER` +0 ×1 + `MAT_ENHANCEMENT_STONE` ×1 | `EQ_DAGGER` +1 ×1 | `one` | 아니오 |
| `RCP_ENHANCE_IRON_SWORD_P1` | `FAC_ENHANCE_ANVIL` | `EQ_IRON_SWORD` +0 ×1 + `MAT_ENHANCEMENT_STONE` ×1 | `EQ_IRON_SWORD` +1 ×1 | `one` | 아니오 |

강화는 확률 판정 없이 입력 장비의 ID를 유지하고 단계만 1로 바꾼다. +1 장비를 입력으로 받는 강화 레시피는 없다.

## 8. 생산 그래프

```text
MAT_IRON_ORE
  -> RCP_SMELT_IRON @ FAC_FURNACE
  -> MAT_IRON_INGOT
       -> RCP_CRAFT_DAGGER @ FAC_WEAPON_BENCH
       -> EQ_DAGGER +0
       -> RCP_CRAFT_IRON_SWORD @ FAC_WEAPON_BENCH
       -> EQ_IRON_SWORD +0

MAT_WOOD
  -> RCP_BURN_CHARCOAL @ FAC_FURNACE
  -> MAT_CHARCOAL --+
                    +-> RCP_SYNTH_ENHANCEMENT_STONE @ FAC_SYNTH_BENCH
MAT_MANA_SHARD -----+       -> MAT_ENHANCEMENT_STONE

EQ_DAGGER +0 / EQ_IRON_SWORD +0
  + MAT_ENHANCEMENT_STONE
  -> FAC_ENHANCE_ANVIL
  -> 같은 장비 +1
```

## 9. 유효성·예외 규칙

- 입력 ID·수량·강화 단계가 표와 일치하지 않으면 유효한 레시피가 아니다.
- 입력 순서는 결과에 영향을 주지 않는다.
- 같은 레시피는 같은 입력에서 항상 같은 출력을 만든다.
- 강화 단계가 요구 입력과 다르면 강화 모루가 장비를 받지 않는다.
- 입력 접수 거절, 작업 시작, 작업 중 변경 금지와 산출물 대기 상태는 `SYS-CORE-001`이 소유한다.

## 10. 시스템 인터페이스

| 대상 | 이 문서가 제공하는 것 | 이 문서가 받는 것 |
|---|---|---|
| `CNT-ITEM-001` | 아이템 사이 생산 관계 | 유효 아이템 ID·분류 |
| `SYS-CORE-001` | 시설별 유효 입력·출력 | 작업 상태 전이 |
| `CNT-MVP-ROUND-001` | 요청 장비의 이행 가능 경로 | 라운드별 사용 시설 |
| `BAL-MVP-001` | 시간 값을 붙일 레시피 ID | 작업 시간 |
| `TECH-SIM-001` | 실행할 전체 레시피 관계 | 작업 상태·완료 순서 |
| `TECH-DATA-001` | JSON에 투영할 전체 레시피 집합 | 데이터 스키마와 검증기 |

## 11. 미결정 사항

| 질문 | MVP 처리 | 결정 방법 |
|---|---|---|
| 철검의 두 주괴 투입이 초보자에게 명확한가? | 입력 슬롯 두 칸을 요구한다. | R2 관찰 테스트 |
| 강화석 합성과 장비 제작의 병렬 계획이 발생하는가? | 한 작업당 일꾼 한 명 규칙을 유지한다. | R5 리플레이와 유휴율 검증 |

## 12. 검증 방법

- 모든 입력과 출력 ID가 `CNT-ITEM-001`에 존재해야 한다.
- `FAC_FURNACE` 레시피만 `worker_mode=none`, `overheat_output=true`여야 한다.
- 제작 출력은 항상 +0 장비여야 한다.
- 강화 레시피는 강화석 하나를 소비하고 동일 장비 ID의 +1을 내야 한다.
- 원자재에서 모든 R1~R5 요청 장비까지 닫힌 생산 경로가 존재해야 한다.

## 13. 완료 기준

- MVP의 유효 조합 전수가 한 번씩 정의되어 있다.
- R1의 단검부터 R5의 +1 철검까지 생산 그래프가 연결된다.
- 시간·점수·라운드 배치가 중복되지 않는다.
- 구현 검증기가 표의 모든 무결성 조건을 자동 검사할 수 있다.
