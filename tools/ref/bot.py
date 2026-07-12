"""
탐욕 봇 플레이어 (플랫폼 §7.5의 bot_player 레퍼런스).

목적:
 1) 시뮬이 라운드를 처음부터 끝까지 결정론적으로 완주하는지 확인.
 2) 달성 가능 하한(봇 점수)과 일꾼 가동률을 산출 → C-3(병렬 운영 자생력)·
    C-4(2일꾼 답답함)의 첫 정량 관측.

봇은 최적이 아니라 탐욕이다. 매 틱 우선순위대로 커맨드를 발행한다:
  치우기(과열 방지·병목 해소) → 납품 → 워커 스테이션 착수 → 화로 착수.
"""

import sim as S


def _idle_workers(state):
    return state["workers_total"] - state["workers_busy"]


def _facs(state, kind):
    return [f for f in state["facilities"] if f["kind"] == kind]


def greedy_commands(content, state):
    cmds = []
    inv = state["inv"]

    # 1) 산출물이 있는 시설은 즉시 치운다(과열 방지 + 병목 해소). 인벤 여유 조건.
    def inv_room():
        return S.inv_count(state) + _pending_stores(cmds) < state["inv_cap"]

    def _pending_stores(_c):
        return sum(1 for x in _c if x[0] == "store")

    for f in state["facilities"]:
        if f["out_key"] is not None and inv_room():
            cmds.append(("store", f["idx"]))

    # 인벤 예측 반영을 위해 현재 인벤 사본에 store 결과를 미리 더한다(탐욕 근사).
    proj = dict(inv)
    for c in cmds:
        if c[0] == "store":
            f = state["facilities"][c[1]]
            if f["out_key"]:
                proj[f["out_key"]] = proj.get(f["out_key"], 0) + 1

    # 2) 납품: 활성 의뢰와 매칭되는 완성 장비가 인벤(예측)에 있으면 납품.
    for a in list(state["active"]):
        rq = content.requests[a["req_id"]]
        eq = rq["equipment"]
        for stage in range(rq["min_enhance"], 4):
            key = S.eq_key(eq, stage)
            if proj.get(key, 0) > 0:
                cmds.append(("deliver", eq))
                proj[key] -= 1
                break

    # 3) 워커 스테이션(제작대) 착수: 유휴 일꾼 & 재료 있으면 수요 장비 제작.
    idle = _idle_workers(state)
    demand = _demand(content, state)  # eq -> 남은 수요 수
    for f in _facs(state, "weapon_bench"):
        if idle <= 0:
            break
        if f["recipe"] is not None or f["out_key"] is not None:
            continue
        # 검(2재료) 수요가 있고 재료 충분하면 검, 아니면 단검
        made = None
        if demand.get("sword", 0) > 0 and proj.get("ingot", 0) >= 1 and proj.get("charcoal", 0) >= 1:
            made = ("c_sword", {"ingot": 1, "charcoal": 1}, "sword")
        elif demand.get("dagger", 0) > 0 and proj.get("ingot", 0) >= 1:
            made = ("c_dagger", {"ingot": 1}, "dagger")
        elif proj.get("ingot", 0) >= 1:
            made = ("c_dagger", {"ingot": 1}, "dagger")  # 수요 예측 실패 시 단검 비축
        if made:
            rid, cost, eq = made
            cmds.append(("start", f["idx"], rid))
            for it, n in cost.items():
                proj[it] = proj.get(it, 0) - n
            demand[eq] = demand.get(eq, 0) - 1
            idle -= 1

    # 4) 화로 착수(일꾼 불필요): 유휴 화로에 원자재 공급 후 변환. ingot 우선, charcoal 보충.
    ingot_have = proj.get("ingot", 0)
    char_have = proj.get("charcoal", 0)
    want_char = demand.get("sword", 0) > 0 and char_have < 2
    for f in _facs(state, "furnace"):
        if f["recipe"] is not None or f["out_key"] is not None:
            continue
        if S.inv_count(state) + _net_supply(cmds) >= state["inv_cap"]:
            break  # 인벤 여유 없음 → 공급 보류
        if want_char and char_have < 2:
            cmds.append(("supply", "wood"))
            cmds.append(("start", f["idx"], "t_charcoal"))
            char_have += 1
        else:
            cmds.append(("supply", "ore"))
            cmds.append(("start", f["idx"], "t_ingot"))
            ingot_have += 1
    return cmds


def _net_supply(cmds):
    return sum(1 for c in cmds if c[0] == "supply") - sum(1 for c in cmds if c[0] in ("start",) and False)


def _demand(content, state):
    d = {}
    for a in state["active"]:
        rq = content.requests[a["req_id"]]
        d[rq["equipment"]] = d.get(rq["equipment"], 0) + 1
    return d


def play(content, round_data, attempt_index=0, trace=False):
    state = S.new_state(content, round_data, attempt_index)
    idle_ticks = 0
    total_worker_ticks = 0
    delivered = 0
    overheat_losses = 0
    while not state["done"]:
        cmds = greedy_commands(content, state)
        evs = S.step(content, state, cmds)
        for e in evs:
            if e[0] == "deliver":
                delivered += 1
            elif e[0] == "overheat_loss":
                overheat_losses += 1
        # 가동률: 이 틱 동안 바쁜 일꾼 / 전체 일꾼 (step 후 상태 기준)
        total_worker_ticks += state["workers_total"]
        idle_ticks += (state["workers_total"] - state["workers_busy"])
    util = 1.0 - (idle_ticks / total_worker_ticks) if total_worker_ticks else 0.0
    return {
        "round": round_data["id"],
        "score": state["score"],
        "stars": S.stars(state),
        "delivered": delivered,
        "overheat_losses": overheat_losses,
        "worker_util": round(util, 3),
        "final_hash": S.state_hash(state),
    }


def upper_bound(content, round_data):
    """느슨한 이론 상한(플랫폼 §7.5): 워커 스테이션 처리량 × 최고 매칭 점수.
    정확한 최적이 아니라 보수적 상한 — ★3 ≤ 상한 성립을 보기 위한 것."""
    deadline = round_data["deadline_ticks"]
    benches = sum(1 for f in round_data["facilities"] if f["kind"] == "weapon_bench")
    # 가장 빠른 제작(단검 160t) 기준 크래프트 슬롯 수
    craft_ticks = min(content.recipes[r]["work_ticks"]
                      for r in content.by_facility.get("weapon_bench", []))
    slots = benches * (deadline // craft_ticks)
    # 등장할 수 있는 최고 점수 의뢰(스크립트+풀에서 참조되는 request의 최대 score)
    ref_reqs = set()
    for e in round_data.get("script", []):
        ref_reqs.add(e["request"])
    for p in round_data.get("pools", []):
        ref_reqs.update(p["pool"])
    max_score = max((content.requests[r]["score"] for r in ref_reqs), default=0)
    return slots * max_score
