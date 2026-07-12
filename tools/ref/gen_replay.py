"""
리플레이 픽스처 생성 (플랫폼 §3.4: 리플레이 = 시드 + 틱 스탬프 커맨드 로그).

봇을 돌리며 매 틱 발행 커맨드를 기록해 tests/fixtures/replay_<round>.json에 저장한다.
GDScript 헤드리스 테스트는 이 로그를 시뮬에 재생하고 체크포인트 해시만 대조하면 되므로,
GDScript는 '시뮬'만 포팅하면 된다(봇 포팅 불요).

여기서 리플레이가 봇 실행과 동일 해시를 재현하는지도 확인한다 — GDScript가 통과해야 할
바로 그 검사를 Python에서 먼저 통과시켜 픽스처의 정당성을 보증한다.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import sim as S
import bot as B

DATA = os.path.join(os.path.dirname(__file__), "..", "..", "data")
FIX = os.path.join(os.path.dirname(__file__), "..", "..", "tests", "fixtures")
CHECKPOINT_EVERY = 300  # 틱


def record(content, round_data, attempt=0):
    state = S.new_state(content, round_data, attempt)
    log = []           # [[tick, [cmd,...]], ...]  (커맨드 있는 틱만)
    checkpoints = []   # [[tick, hash], ...]
    while not state["done"]:
        t = state["tick"]
        cmds = B.greedy_commands(content, state)
        if cmds:
            log.append([t, [list(c) for c in cmds]])
        S.step(content, state, cmds)
        if state["tick"] % CHECKPOINT_EVERY == 0 or state["done"]:
            checkpoints.append([state["tick"], S.state_hash(state)])
    return {
        "round": round_data["id"],
        "attempt": attempt,
        "seed": S.round_seed(round_data["id"], attempt),
        "final_tick": state["tick"],
        "final_score": state["score"],
        "final_stars": S.stars(state),
        "final_hash": S.state_hash(state),
        "checkpoints": checkpoints,
        "commands": log,
    }


def replay(content, round_data, rec):
    """기록된 커맨드 로그를 새 상태에 재생 → 체크포인트/최종 해시 재현 확인.
    (이것이 GDScript 헤드리스 테스트가 수행할 검사의 Python판이다.)"""
    state = S.new_state(content, round_data, rec["attempt"])
    by_tick = {t: cmds for t, cmds in rec["commands"]}
    cp = {t: h for t, h in rec["checkpoints"]}
    while not state["done"]:
        t = state["tick"]
        cmds = [tuple(c) for c in by_tick.get(t, [])]
        S.step(content, state, cmds)
        if state["tick"] in cp:
            if S.state_hash(state) != cp[state["tick"]]:
                return False, f"체크포인트 불일치 @tick {state['tick']}"
    if S.state_hash(state) != rec["final_hash"]:
        return False, "최종 해시 불일치"
    return True, "재생 = 원본 (전 체크포인트·최종 일치)"


def main():
    content = S.Content(DATA)
    os.makedirs(FIX, exist_ok=True)
    print("리플레이 픽스처 생성 + 재생 검증")
    for rid in ("r1", "r2"):
        rd = content.load_round(DATA, rid)
        rec = record(content, rd)
        ok, msg = replay(content, rd, rec)
        path = os.path.join(FIX, f"replay_{rid}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(rec, f, ensure_ascii=False)
        status = "OK" if ok else "FAIL"
        print(f"  {rid}: {status} — {msg}  (커맨드 틱 {len(rec['commands'])}개, "
              f"체크포인트 {len(rec['checkpoints'])}개, 최종 {rec['final_hash']})")
        if not ok:
            sys.exit(1)
    print("완료 — replay_r1.json, replay_r2.json 기록. GDScript는 이 로그를 재생해 대조한다.")


if __name__ == "__main__":
    main()
