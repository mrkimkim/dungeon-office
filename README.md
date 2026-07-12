# 던전 오피스 (Dungeon Office)

던전 레이드 회사들을 거래처로 둔 대장간의 백오피스를 운영하는 1인용 모바일 게임.
현재 단계: **M0 프로토타입** (마스터 플랜 §1). 재미 게이트 검증이 목표.

## 문서
기획 문서는 [`docs/`](./docs)에 있다. 시작점은 [GDD](./docs/GDD.md)(코어 시스템 명세)와
[마스터 플랜](./docs/master-plan.md)(전 영역 실행 계획).

## 프로젝트 구조 (플랫폼 §6.1)
```
sim/     순수 시뮬레이션 — 엔진 비의존(RefCounted만). 결정론 코어.
  rng.gd   PCG32 (플랫폼 §3.3)
  sim.gd   상태·step()·의뢰 생성기·채점·정규 해시
game/    표현·입출력 (뷰) — M1의 주작업. 현재 스캐폴드.
data/    콘텐츠 JSON (플랫폼 §4) — 재료·레시피·의뢰·라운드. M0는 임시 데이터.
tools/   헤드리스 도구
  ref/     Python 레퍼런스 시뮬 + 봇 + 검증 (이 저장소에서 결정론을 실제로 검증)
  verify_replay.gd  Godot 헤드리스 골든 리플레이 검증
tests/   골든·리플레이 픽스처
```

## 왜 Python 레퍼런스가 있는가
시뮬 코어는 정수 전용 순수 함수라(플랫폼 §3.2) 언어 독립적으로 결정론이 성립한다.
`tools/ref/`의 Python 구현은 GDScript `sim/`의 **오라클**이다 — 개발 환경에 Godot가
없어도 알고리즘의 결정론을 검증하고 골든 픽스처를 생성한다. GDScript 포트는 그 픽스처를
재생해 동일 해시를 내야 한다(교차 구현 결정론).

## 검증 실행

### Python 레퍼런스 (Godot 불요)
```bash
cd tools/ref
python3 run.py          # T1~T6: 결정론·시드변주·스냅샷왕복·봇완주·상한정합
python3 gd_emu.py       # GDScript식 PCG32가 레퍼런스와 일치하는지(400 draw)
python3 gen_replay.py   # 리플레이 픽스처 생성 + 재생 검증
```

### GDScript 시뮬 (Godot 4.4 필요)
```bash
godot --headless --script tools/verify_replay.gd
```
`tests/fixtures/replay_*.json`을 GDScript 시뮬에 재생해 골든 해시와 대조한다.
전부 일치하면 GDScript 포트가 Python 레퍼런스와 결정론적으로 동일하다.

## M0 현재 상태
- ✅ 시뮬 코어 결정론 — Python 레퍼런스에서 T1~T6 전부 통과
- ✅ PCG32 GDScript 이식 — 부호-64비트 에뮬로 400 draw 일치 확인
- ✅ GDScript 시뮬·헤드리스 테스트 작성
- ⏳ `verify_replay.gd` 로컬 Godot 실행 — 교차 구현 결정론 최종 확인(사장님)
- ⏳ 뷰(탭 조작·도형 스프라이트) — 다음 작업
- ⏳ 사람 플레이테스트로 재미 게이트 판정 ([QA 계획](./docs/qa-plan.md))
