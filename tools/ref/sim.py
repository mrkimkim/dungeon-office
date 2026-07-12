"""
던전 오피스 — 시뮬레이션 코어 Python 레퍼런스 (M0)

목적: 플랫폼 §3의 결정론 시뮬을 정수 전용 순수 함수로 구현하고, 이 환경에서
실제로 돌려 결정론을 검증한다. 이 파일은 GDScript sim/의 오라클이다 — GDScript는
이 로직을 그대로 미러링하고, 로컬 Godot 헤드리스에서 동일한 상태 해시를 내야 한다.

규율(플랫폼 §3.2):
 - 상태는 정수 전용. 부동소수 금지.
 - step(state, commands) -> (state', events)는 순수 함수. 전역·시계·엔진 참조 없음.
 - 유일한 RNG 소비자는 의뢰 생성기(§3.3). 승패 주사위 없음(원칙 4).
"""

import copy
import hashlib
import json

MASK64 = (1 << 64) - 1
MASK32 = (1 << 32) - 1


# ── PCG32 (플랫폼 §3.3) ────────────────────────────────────────────────
# GDScript 미러는 부호 없는 64/32비트 시프트를 마스킹으로 흉내 낸다.
class Pcg32:
    __slots__ = ("state", "inc")

    def __init__(self, state=0, inc=0):
        self.state = state & MASK64
        self.inc = inc & MASK64

    @staticmethod
    def seeded(init_state, init_seq):
        r = Pcg32(0, ((init_seq << 1) | 1) & MASK64)
        r.next_u32()
        r.state = (r.state + (init_state & MASK64)) & MASK64
        r.next_u32()
        return r

    def next_u32(self):
        old = self.state
        self.state = (old * 6364136223846793005 + self.inc) & MASK64
        xorshifted = (((old >> 18) ^ old) >> 27) & MASK32
        rot = old >> 59
        return ((xorshifted >> rot) | (xorshifted << ((-rot) & 31))) & MASK32

    def below(self, bound):
        # bound>0. 편향 제거(rejection) — 결정론·이식성 유지.
        if bound <= 0:
            return 0
        threshold = (MASK32 + 1 - bound) % bound
        while True:
            r = self.next_u32()
            if r >= threshold:
                return r % bound

    def between(self, lo, hi):  # [lo, hi]
        return lo + self.below(hi - lo + 1)


# ── 시드 (플랫폼 §3.3): seed = hash64(round_id, attempt_index) ──────────
def round_seed(round_id, attempt_index):
    h = hashlib.sha256(f"{round_id}:{attempt_index}".encode()).digest()
    return int.from_bytes(h[:8], "little")


# ── 콘텐츠 로딩 ─────────────────────────────────────────────────────────
class Content:
    def __init__(self, data_dir):
        self.items = _load(f"{data_dir}/items.json")
        self.recipes = {r["id"]: r for r in _load(f"{data_dir}/recipes.json")}
        self.requests = {r["id"]: r for r in _load(f"{data_dir}/requests.json")}
        self.equipment = {e["id"]: e for e in self.items["equipment"]}
        self.raws = set(self.items["raws"])
        # facility kind -> 이 시설에서 가능한 레시피 id 목록
        self.by_facility = {}
        for rid, r in self.recipes.items():
            self.by_facility.setdefault(r["facility"], []).append(rid)

    def load_round(self, data_dir, round_id):
        return _load(f"{data_dir}/rounds/{round_id}.json")


def _load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


# ── 인벤토리 키: 재료=id, 장비=f"{id}+{stage}" ──────────────────────────
def eq_key(eq, stage):
    return f"{eq}+{stage}"


def is_eq_key(key):
    return "+" in key


def parse_eq(key):
    eq, stage = key.rsplit("+", 1)
    return eq, int(stage)


# ── 상태 생성 ───────────────────────────────────────────────────────────
def new_state(content, round_data, attempt_index):
    seed = round_seed(round_data["id"], attempt_index)
    rng = Pcg32.seeded(seed, 0xDA)  # 0xDA = Dungeon office 상수(임의 고정)
    facilities = []
    for i, f in enumerate(round_data["facilities"]):
        facilities.append({
            "idx": i, "kind": f["kind"],
            "recipe": None, "ticks_left": 0,
            "out_key": None, "overheat_left": -1,  # -1 = 과열 없음/미해당
        })
    # 의뢰 생성기: script 이벤트 큐 + 각 pool의 다음 발화 틱
    gen = {
        "script": sorted(round_data.get("script", []), key=lambda e: e["at_ticks"]),
        "script_cursor": 0,
        "pools": [],
    }
    for p in round_data.get("pools", []):
        gen["pools"].append({
            "from": p["from_ticks"], "to": p["to_ticks"],
            "pool": list(p["pool"]), "interval": list(p["interval_ticks"]),
            "next_at": p["from_ticks"],  # 첫 발화는 from에서 스케줄
            "primed": False,
        })
    return {
        "tick": 0,
        "rng": [rng.state, rng.inc],
        "deadline": round_data["deadline_ticks"],
        "inv_cap": round_data["inventory_cap"],
        "inv": {},                      # key -> count
        "workers_total": round_data["workers"],
        "workers_busy": 0,
        "facilities": facilities,
        "req_slots": round_data["request_slots"],
        "active": [],                   # {uid, req_id, patience_left}
        "next_uid": 1,
        "gen": gen,
        "score": 0,
        "cutlines": round_data["cutlines"],
        "cmd_seq": 0,
        "done": False,
    }


def _rng_obj(state):
    r = Pcg32(state["rng"][0], state["rng"][1])
    return r


def _rng_save(state, r):
    state["rng"][0] = r.state
    state["rng"][1] = r.inc


def inv_count(state):
    return sum(state["inv"].values())


def inv_add(state, key, n=1):
    state["inv"][key] = state["inv"].get(key, 0) + n


def inv_take(state, key, n=1):
    have = state["inv"].get(key, 0)
    if have < n:
        return False
    if have == n:
        del state["inv"][key]
    else:
        state["inv"][key] = have - n
    return True


# ── 커맨드 ──────────────────────────────────────────────────────────────
# ("supply", raw_id)              공급함에서 원자재 1개를 인벤토리로(무한, 즉시)
# ("start", facility_idx, recipe_id)  시설에 레시피 착수(입력을 인벤토리에서 소모)
# ("store", facility_idx)         완성 산출물을 인벤토리로, 시설 비움
# ("deliver", equipment_id)       장비 1개 납품(요구 단계 이하 의뢰 중 최고점 매칭)
# ("trash", inv_key)              인벤토리 아이템 1개 파기
def apply_command(content, state, cmd, events):
    kind = cmd[0]
    if kind == "supply":
        raw = cmd[1]
        if raw not in content.raws:
            events.append(("reject", "supply", "not_raw")); return
        if inv_count(state) >= state["inv_cap"]:
            events.append(("reject", "supply", "inv_full")); return
        inv_add(state, raw); return

    if kind == "start":
        fi, rid = cmd[1], cmd[2]
        fac = state["facilities"][fi]
        r = content.recipes[rid]
        if fac["kind"] != r["facility"]:
            events.append(("reject", "start", "wrong_facility")); return
        if fac["recipe"] is not None or fac["out_key"] is not None:
            events.append(("reject", "start", "busy")); return
        needs_worker = r["type"] != "transform"
        if needs_worker and state["workers_busy"] >= state["workers_total"]:
            events.append(("reject", "start", "no_idle_worker")); return  # 대기열 없음(§6)
        ins = list(r["in"])
        # enhance는 입력에 강화석 + '장비 인스턴스'가 필요 → 별도 처리
        if r["type"] == "enhance":
            eqk = cmd[3] if len(cmd) > 3 else None
            if eqk is None or not is_eq_key(eqk) or state["inv"].get(eqk, 0) < 1:
                events.append(("reject", "start", "no_equipment")); return
            if state["inv"].get("enh_stone", 0) < 1:
                events.append(("reject", "start", "no_stone")); return
            inv_take(state, eqk); inv_take(state, "enh_stone")
            eq, stage = parse_eq(eqk)
            fac["pending_eq"] = (eq, stage + 1)
        else:
            # 입력 재고 확인
            need = {}
            for it in ins:
                need[it] = need.get(it, 0) + 1
            for it, n in need.items():
                if state["inv"].get(it, 0) < n:
                    events.append(("reject", "start", "no_input")); return
            for it, n in need.items():
                inv_take(state, it, n)
        fac["recipe"] = rid
        fac["ticks_left"] = r["work_ticks"]
        if needs_worker:
            state["workers_busy"] += 1
        events.append(("start", fi, rid)); return

    if kind == "store":
        fi = cmd[1]
        fac = state["facilities"][fi]
        if fac["out_key"] is None:
            events.append(("reject", "store", "nothing")); return
        if inv_count(state) >= state["inv_cap"]:
            events.append(("reject", "store", "inv_full")); return
        inv_add(state, fac["out_key"])
        fac["out_key"] = None
        fac["overheat_left"] = -1
        events.append(("store", fi)); return

    if kind == "deliver":
        eq = cmd[1]
        # 인벤토리에서 이 장비의 가장 낮은 단계부터 찾되, 매칭 가능한 최고점 의뢰 선택
        best = None  # (score, active_index, inv_key)
        for stage in range(0, 4):
            key = eq_key(eq, stage)
            if state["inv"].get(key, 0) < 1:
                continue
            for ai, a in enumerate(state["active"]):
                rq = content.requests[a["req_id"]]
                if rq["equipment"] == eq and rq["min_enhance"] <= stage:
                    if best is None or rq["score"] > best[0]:
                        best = (rq["score"], ai, key)
        if best is None:
            events.append(("reject", "deliver", "no_match")); return
        score, ai, key = best
        inv_take(state, key)
        state["score"] += score
        removed = state["active"].pop(ai)
        events.append(("deliver", eq, score, removed["req_id"])); return

    if kind == "trash":
        key = cmd[1]
        if inv_take(state, key):
            events.append(("trash", key))
        else:
            events.append(("reject", "trash", "absent"))
        return

    events.append(("reject", "unknown", kind))


# ── 의뢰 생성기 (유일한 RNG 소비자) ─────────────────────────────────────
def _spawn_request(content, state, req_id, events):
    if len(state["active"]) >= state["req_slots"]:
        return False  # 칸이 없으면 이번 틱엔 못 옴(다음 틱 재시도는 호출부가 관리)
    rq = content.requests[req_id]
    uid = state["next_uid"]; state["next_uid"] += 1
    state["active"].append({"uid": uid, "req_id": req_id, "patience_left": rq["patience_ticks"]})
    events.append(("arrive", uid, req_id))
    return True


def _advance_generator(content, state, events):
    gen = state["gen"]
    # script: 예고·고정 의뢰(시드 무관). at_ticks 도달 시 발화.
    while gen["script_cursor"] < len(gen["script"]):
        ev = gen["script"][gen["script_cursor"]]
        if ev["at_ticks"] > state["tick"]:
            break
        if len(state["active"]) < state["req_slots"]:
            _spawn_request(content, state, ev["request"], events)
            gen["script_cursor"] += 1
        else:
            break  # 칸이 없으면 대기(다음 틱 재시도)
    # pools: 시드 변주. next_at 도달 시 풀에서 추첨 후 다음 간격 예약.
    r = _rng_obj(state)
    for p in gen["pools"]:
        if state["tick"] < p["from"] or state["tick"] > p["to"]:
            continue
        if state["tick"] >= p["next_at"]:
            if len(state["active"]) < state["req_slots"]:
                pick = p["pool"][r.below(len(p["pool"]))]
                _spawn_request(content, state, pick, events)
                gap = r.between(p["interval"][0], p["interval"][1])
                p["next_at"] = state["tick"] + gap
            # 칸이 없으면 next_at 유지 → 다음 틱 재시도(RNG 미소비)
    _rng_save(state, r)


# ── 틱 진행 ─────────────────────────────────────────────────────────────
def _advance_facilities(content, state, events):
    for fac in state["facilities"]:
        if fac["recipe"] is not None:
            fac["ticks_left"] -= 1
            if fac["ticks_left"] <= 0:
                r = content.recipes[fac["recipe"]]
                if r["type"] == "enhance":
                    eq, stage = fac.pop("pending_eq")
                    fac["out_key"] = eq_key(eq, stage)
                    fac["overheat_left"] = -1
                elif r["type"] == "transform":
                    fac["out_key"] = r["out"]
                    fac["overheat_left"] = r["overheat_grace_ticks"]  # 과열 시작
                elif r["type"] == "craft":
                    fac["out_key"] = eq_key(r["out"], 0)  # 장비는 단계 포함 키
                    fac["overheat_left"] = -1
                else:  # synthesize
                    fac["out_key"] = r["out"]
                    fac["overheat_left"] = -1
                if r["type"] != "transform":
                    state["workers_busy"] -= 1  # 일꾼 해방
                events.append(("complete", fac["idx"], fac["out_key"]))
                fac["recipe"] = None
        elif fac["out_key"] is not None and fac["overheat_left"] >= 0:
            # 과열 카운트다운(변환 산출물만) — 유일한 비자발적 손실원(§8.3)
            fac["overheat_left"] -= 1
            grace_total = 0
            # 경고 이벤트(간단): 절반/25% 지점
            if fac["overheat_left"] == 0:
                events.append(("overheat_loss", fac["idx"], fac["out_key"]))
                fac["out_key"] = None
                fac["overheat_left"] = -1


def _advance_patience(content, state, events):
    survivors = []
    for a in state["active"]:
        a["patience_left"] -= 1
        if a["patience_left"] <= 0:
            events.append(("withdraw", a["uid"], a["req_id"]))  # 기회 상실뿐(§9.1)
        else:
            survivors.append(a)
    state["active"] = survivors


def step(content, state, commands):
    """순수 함수: (content, state, commands) -> events. state를 제자리 변경."""
    events = []
    if state["done"]:
        return events
    # 1) 입력(50ms 양자화된 커맨드) 적용
    for cmd in commands:
        state["cmd_seq"] += 1
        apply_command(content, state, cmd, events)
    # 2) 시설 진행 + 과열
    _advance_facilities(content, state, events)
    # 3) 인내 진행
    _advance_patience(content, state, events)
    # 4) 의뢰 생성(RNG)
    _advance_generator(content, state, events)
    # 5) 틱 증가 / 기한 판정
    state["tick"] += 1
    if state["tick"] >= state["deadline"]:
        state["done"] = True
        events.append(("deadline", state["score"], stars(state)))
    return events


def stars(state):
    c = state["cutlines"]; s = state["score"]
    if s < c["fail_under"]:
        return 0
    if s >= c["star3"]:
        return 3
    if s >= c["star2"]:
        return 2
    if s >= c["star1"]:
        return 1
    return 0


# ── 직렬화·해시 (플랫폼 §3.2, §7.4) ─────────────────────────────────────
def serialize(state):
    """상태 전부를 정규 JSON으로. 스냅샷(로컬 저장)의 기준."""
    return json.dumps(state, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _to_s64(v):
    """부호 없는 64비트 값을 GDScript와 같은 부호 있는 64비트 십진 표현으로."""
    v &= MASK64
    return v - (1 << 64) if v >= (1 << 63) else v


def canonical(state):
    """정수·문자열만으로 만드는 이식 가능한 정규 문자열.
    골든 해시의 기준 — Python과 GDScript가 '구성으로' 동일 문자열을 만들도록,
    JSON 포맷 차이(공백·부동소수·키 순서)에 의존하지 않는다."""
    p = []
    p.append(f"t={state['tick']};sc={state['score']};wb={state['workers_busy']}")
    p.append(f";uid={state['next_uid']};done={1 if state['done'] else 0}")
    # GDScript int는 부호 있는 64비트다. 양쪽 canonical이 같도록 부호 있는 형태로 출력.
    p.append(f";rng={_to_s64(state['rng'][0])},{_to_s64(state['rng'][1])}")
    inv = state["inv"]
    p.append(";inv=" + ",".join(f"{k}:{inv[k]}" for k in sorted(inv)))
    fac = []
    for f in state["facilities"]:
        fac.append(f"{f['kind']}:{f['recipe'] or '-'}:{f['ticks_left']}:{f['out_key'] or '-'}:{f['overheat_left']}")
    p.append(";fac=" + "|".join(fac))
    act = [f"{a['uid']}:{a['req_id']}:{a['patience_left']}" for a in state["active"]]
    p.append(";act=" + "|".join(act))
    g = state["gen"]
    pools = ",".join(str(pl["next_at"]) for pl in g["pools"])
    p.append(f";gen={g['script_cursor']}/{pools}")
    return "".join(p)


def state_hash(state):
    return hashlib.sha256(canonical(state).encode()).hexdigest()[:16]


def snapshot(state):
    return copy.deepcopy(state)
