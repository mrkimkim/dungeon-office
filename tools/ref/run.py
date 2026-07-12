"""
M0 검증 러너 — 이 환경에서 실제로 돌려 시뮬 코어의 결정론을 증명한다.

검증 항목:
 T1 결정론      같은 (round, attempt) → 같은 최종 상태 해시(반복 실행)
 T2 시드 변주    다른 attempt → (대개) 다른 의뢰 전개 (플랫폼 §3.3 재도전 변주)
 T3 스냅샷 왕복  임의 틱에서 저장→로드→계속 = 무중단 실행과 해시 일치(플랫폼 §7.4)
 T4 골든 픽스처  대표 라운드의 (시드+최종해시)를 tests/fixtures에 기록 → GDScript 대조용
 T5 봇 완주·관측 봇이 완주하며 점수·일꾼 가동률 산출 (C-3/C-4 첫 읽기)
 T6 상한 정합    ★3 커트라인 ≤ 이론 상한 (플랫폼 §7.5 검증식)
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import sim as S
import bot as B

DATA = os.path.join(os.path.dirname(__file__), "..", "..", "data")
FIX = os.path.join(os.path.dirname(__file__), "..", "..", "tests", "fixtures")


def run_scripted(content, round_data, attempt, cmd_fn, stop_tick=None):
    state = S.new_state(content, round_data, attempt)
    saved = None
    while not state["done"]:
        if stop_tick is not None and state["tick"] == stop_tick:
            saved = S.snapshot(state)
        S.step(content, state, cmd_fn(content, state))
    return state, saved


def main():
    content = S.Content(DATA)
    rounds = {rid: content.load_round(DATA, rid) for rid in ("r1", "r2")}
    fails = []
    fixtures = {}

    print("=" * 64)
    print("던전 오피스 — M0 시뮬 코어 검증 (Python 레퍼런스)")
    print("=" * 64)

    # T1 결정론: 봇 플레이를 3회 반복, 최종 해시 동일해야.
    print("\n[T1] 결정론 (같은 seed → 같은 해시)")
    for rid, rd in rounds.items():
        hashes = set()
        for _ in range(3):
            st, _ = run_scripted(content, rd, 0, B.greedy_commands)
            hashes.add(S.state_hash(st))
        ok = len(hashes) == 1
        print(f"  {rid}: {'OK' if ok else 'FAIL'}  hash={list(hashes)[0]}  (반복 3회 해시 {'일치' if ok else '불일치 '+str(hashes)})")
        if not ok:
            fails.append(f"T1 {rid}")

    # T2 시드 변주: attempt 0..3의 의뢰 도착 순서가 서로 다른지(적어도 하나는 다름).
    print("\n[T2] 시드 변주 (다른 attempt → 다른 전개)")
    for rid, rd in rounds.items():
        seqs = []
        for att in range(4):
            st = S.new_state(content, rd, att)
            arrivals = []
            while not st["done"] and len(arrivals) < 12:
                evs = S.step(content, st, [])  # 커맨드 없이 의뢰 전개만 관찰
                arrivals += [e[2] for e in evs if e[0] == "arrive"]
            seqs.append(tuple(arrivals[:12]))
        distinct = len(set(seqs))
        # script 고정분은 동일, pool 변주분은 달라야 → distinct>1 기대
        print(f"  {rid}: attempt 4종 중 서로 다른 전개 {distinct}종  {'OK' if distinct > 1 else 'WARN(변주 약함)'}")
        if distinct <= 1:
            fails.append(f"T2 {rid} (변주 없음)")

    # T3 스냅샷 왕복: 중간 틱에서 저장→로드 계속 = 무중단과 동일 해시.
    print("\n[T3] 스냅샷 왕복 (저장→로드→계속 = 무중단)")
    for rid, rd in rounds.items():
        stop = rd["deadline_ticks"] // 2
        full, saved = run_scripted(content, rd, 0, B.greedy_commands, stop_tick=stop)
        # saved에서 재개
        resumed = saved
        while not resumed["done"]:
            S.step(content, resumed, B.greedy_commands(content, resumed))
        ok = S.state_hash(full) == S.state_hash(resumed)
        print(f"  {rid}: {'OK' if ok else 'FAIL'}  중단@{stop}  무중단={S.state_hash(full)} 재개={S.state_hash(resumed)}")
        if not ok:
            fails.append(f"T3 {rid}")

    # T5 봇 완주·관측 (C-3/C-4)
    print("\n[T5] 봇 완주 · 일꾼 가동률 (C-3/C-4 첫 읽기)")
    bot_results = {}
    for rid, rd in rounds.items():
        r = B.play(content, rd, 0)
        bot_results[rid] = r
        print(f"  {rid}: 점수 {r['score']}  별 {'★'*r['stars'] or '0'}  납품 {r['delivered']}  "
              f"과열손실 {r['overheat_losses']}  일꾼가동률 {r['worker_util']*100:.1f}%")

    # T6 상한 정합
    print("\n[T6] 이론 상한 정합 (★3 커트라인 ≤ 상한, 봇 하한 ≥ ★1 기대)")
    for rid, rd in rounds.items():
        ub = B.upper_bound(content, rd)
        star3 = rd["cutlines"]["star3"]
        star1 = rd["cutlines"]["star1"]
        botscore = bot_results[rid]["score"]
        ok3 = star3 <= ub
        print(f"  {rid}: 상한≈{ub}  ★3={star3} {'OK' if ok3 else 'FAIL(★3>상한)'}  "
              f"봇={botscore} vs ★1={star1} → {'봇 ★1 달성' if botscore>=star1 else '봇 ★1 미달(튜닝 필요)'}")
        if not ok3:
            fails.append(f"T6 {rid} (★3>상한)")

    # T4 골든 픽스처 기록 (GDScript 헤드리스 대조용)
    print("\n[T4] 골든 픽스처 기록 (GDScript --headless 대조 기준)")
    os.makedirs(FIX, exist_ok=True)
    for rid, rd in rounds.items():
        st, _ = run_scripted(content, rd, 0, B.greedy_commands)
        fixtures[rid] = {
            "round": rid,
            "attempt": 0,
            "seed": S.round_seed(rid, 0),
            "final_tick": st["tick"],
            "final_score": st["score"],
            "final_stars": S.stars(st),
            "final_hash": S.state_hash(st),
            "bot": bot_results[rid],
        }
    with open(os.path.join(FIX, "golden.json"), "w", encoding="utf-8") as f:
        json.dump(fixtures, f, ensure_ascii=False, indent=2)
    print(f"  tests/fixtures/golden.json 기록 ({len(fixtures)} 라운드)")

    print("\n" + "=" * 64)
    if fails:
        print(f"결과: 실패 {len(fails)}건 — {fails}")
        sys.exit(1)
    print("결과: 전 항목 통과 ✅  — 시뮬 코어 결정론 검증 완료")
    print("=" * 64)


if __name__ == "__main__":
    main()
