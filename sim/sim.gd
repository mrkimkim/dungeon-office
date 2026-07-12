# 던전 오피스 — 시뮬레이션 코어 (GDScript, 플랫폼 §3·§6.1)
#
# tools/ref/sim.py의 1:1 미러. 정수 전용 순수 로직(엔진·시계·전역 참조 없음).
# 결정론·리플레이·골든 해시는 Python 레퍼런스에서 검증됐고, 이 포트의 파리티는
# tools/verify_replay.gd(헤드리스)가 tests/fixtures/replay_*.json을 재생해 대조한다.
#
# 규율(플랫폼 §3.2): 상태는 정수 전용, step()은 순수 함수, RNG는 의뢰 생성기만.
class_name Sim
extends RefCounted

const MUL := 6364136223846793005

# ── 콘텐츠 로딩 ───────────────────────────────────────────────────────
static func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "데이터 파일 없음: " + path)
	return JSON.parse_string(f.get_as_text())

static func load_content(data_dir: String) -> Dictionary:
	var items: Dictionary = _load_json(data_dir + "/items.json")
	var recipes := {}
	for r in _load_json(data_dir + "/recipes.json"):
		recipes[r["id"]] = r
	var requests := {}
	for r in _load_json(data_dir + "/requests.json"):
		requests[r["id"]] = r
	var equipment := {}
	for e in items["equipment"]:
		equipment[e["id"]] = e
	var raws := {}
	for x in items["raws"]:
		raws[x] = true
	var by_facility := {}
	for rid in recipes:
		var fac: String = recipes[rid]["facility"]
		if not by_facility.has(fac):
			by_facility[fac] = []
		by_facility[fac].append(rid)
	return {
		"items": items, "recipes": recipes, "requests": requests,
		"equipment": equipment, "raws": raws, "by_facility": by_facility,
	}

static func load_round(data_dir: String, round_id: String) -> Dictionary:
	return _load_json(data_dir + "/rounds/" + round_id + ".json")

# ── 시드 (플랫폼 §3.3) ────────────────────────────────────────────────
static func round_seed(round_id: String, attempt_index: int) -> int:
	var buf := ("%s:%d" % [round_id, attempt_index]).sha256_buffer()
	var v := 0
	for i in range(8):
		v |= buf[i] << (8 * i)  # little-endian 8바이트 → 64비트 패턴
	return v

# ── 인벤토리 키 ───────────────────────────────────────────────────────
static func eq_key(eq: String, stage: int) -> String:
	return "%s+%d" % [eq, stage]

static func is_eq_key(key: String) -> bool:
	return key.find("+") != -1

static func parse_eq(key: String) -> Array:
	var idx := key.rfind("+")
	return [key.substr(0, idx), int(key.substr(idx + 1))]

# ── 상태 생성 ─────────────────────────────────────────────────────────
static func new_state(content: Dictionary, rd: Dictionary, attempt_index: int) -> Dictionary:
	var rng := Pcg32.new()
	rng.seed_with(round_seed(rd["id"], attempt_index), 0xDA)
	var facilities := []
	var i := 0
	for f in rd["facilities"]:
		facilities.append({
			"idx": i, "kind": f["kind"],
			"recipe": null, "ticks_left": 0,
			"out_key": null, "overheat_left": -1, "pending_eq": null,
		})
		i += 1
	var script_ev: Array = rd.get("script", []).duplicate(true)
	script_ev.sort_custom(func(a, b): return a["at_ticks"] < b["at_ticks"])
	var pools := []
	for p in rd.get("pools", []):
		pools.append({
			"from": p["from_ticks"], "to": p["to_ticks"],
			"pool": p["pool"].duplicate(), "interval": p["interval_ticks"].duplicate(),
			"next_at": p["from_ticks"],
		})
	return {
		"tick": 0,
		"rng": [rng.state, rng.inc],
		"deadline": rd["deadline_ticks"],
		"inv_cap": rd["inventory_cap"],
		"inv": {},
		"workers_total": rd["workers"],
		"workers_busy": 0,
		"facilities": facilities,
		"req_slots": rd["request_slots"],
		"active": [],
		"next_uid": 1,
		"gen": {"script": script_ev, "script_cursor": 0, "pools": pools},
		"score": 0,
		"cutlines": rd["cutlines"],
		"cmd_seq": 0,
		"done": false,
	}

# ── 인벤토리 헬퍼 ─────────────────────────────────────────────────────
static func inv_count(state: Dictionary) -> int:
	var n := 0
	for k in state["inv"]:
		n += state["inv"][k]
	return n

static func inv_add(state: Dictionary, key: String, n: int = 1) -> void:
	state["inv"][key] = state["inv"].get(key, 0) + n

static func inv_take(state: Dictionary, key: String, n: int = 1) -> bool:
	var have: int = state["inv"].get(key, 0)
	if have < n:
		return false
	if have == n:
		state["inv"].erase(key)
	else:
		state["inv"][key] = have - n
	return true

# ── 커맨드 적용 ───────────────────────────────────────────────────────
static func apply_command(content: Dictionary, state: Dictionary, cmd: Array, events: Array) -> void:
	var kind: String = cmd[0]
	if kind == "supply":
		var raw: String = cmd[1]
		if not content["raws"].has(raw):
			events.append(["reject", "supply", "not_raw"]); return
		if inv_count(state) >= state["inv_cap"]:
			events.append(["reject", "supply", "inv_full"]); return
		inv_add(state, raw); return

	if kind == "start":
		var fi: int = cmd[1]
		var rid: String = cmd[2]
		var fac: Dictionary = state["facilities"][fi]
		var r: Dictionary = content["recipes"][rid]
		if fac["kind"] != r["facility"]:
			events.append(["reject", "start", "wrong_facility"]); return
		if fac["recipe"] != null or fac["out_key"] != null:
			events.append(["reject", "start", "busy"]); return
		var needs_worker: bool = r["type"] != "transform"
		if needs_worker and state["workers_busy"] >= state["workers_total"]:
			events.append(["reject", "start", "no_idle_worker"]); return  # 대기열 없음(§6)
		if r["type"] == "enhance":
			var eqk = cmd[3] if cmd.size() > 3 else null
			if eqk == null or not is_eq_key(eqk) or state["inv"].get(eqk, 0) < 1:
				events.append(["reject", "start", "no_equipment"]); return
			if state["inv"].get("enh_stone", 0) < 1:
				events.append(["reject", "start", "no_stone"]); return
			inv_take(state, eqk); inv_take(state, "enh_stone")
			var parsed := parse_eq(eqk)
			fac["pending_eq"] = [parsed[0], parsed[1] + 1]
		else:
			var need := {}
			for it in r["in"]:
				need[it] = need.get(it, 0) + 1
			for it in need:
				if state["inv"].get(it, 0) < need[it]:
					events.append(["reject", "start", "no_input"]); return
			for it in need:
				inv_take(state, it, need[it])
		fac["recipe"] = rid
		fac["ticks_left"] = r["work_ticks"]
		if needs_worker:
			state["workers_busy"] += 1
		events.append(["start", fi, rid]); return

	if kind == "store":
		var fi2: int = cmd[1]
		var fac2: Dictionary = state["facilities"][fi2]
		if fac2["out_key"] == null:
			events.append(["reject", "store", "nothing"]); return
		if inv_count(state) >= state["inv_cap"]:
			events.append(["reject", "store", "inv_full"]); return
		inv_add(state, fac2["out_key"])
		fac2["out_key"] = null
		fac2["overheat_left"] = -1
		events.append(["store", fi2]); return

	if kind == "deliver":
		var eq: String = cmd[1]
		var best_score := -1
		var best_ai := -1
		var best_key := ""
		for stage in range(0, 4):
			var key := eq_key(eq, stage)
			if state["inv"].get(key, 0) < 1:
				continue
			var ai := 0
			for a in state["active"]:
				var rq: Dictionary = content["requests"][a["req_id"]]
				if rq["equipment"] == eq and rq["min_enhance"] <= stage:
					if rq["score"] > best_score:
						best_score = rq["score"]; best_ai = ai; best_key = key
				ai += 1
		if best_ai < 0:
			events.append(["reject", "deliver", "no_match"]); return
		inv_take(state, best_key)
		state["score"] += best_score
		var removed: Dictionary = state["active"][best_ai]
		state["active"].remove_at(best_ai)
		events.append(["deliver", eq, best_score, removed["req_id"]]); return

	if kind == "trash":
		var key2: String = cmd[1]
		if inv_take(state, key2):
			events.append(["trash", key2])
		else:
			events.append(["reject", "trash", "absent"])
		return

	events.append(["reject", "unknown", kind])

# ── 의뢰 생성기 (유일한 RNG 소비자) ──────────────────────────────────
static func _spawn_request(content: Dictionary, state: Dictionary, req_id: String, events: Array) -> bool:
	if state["active"].size() >= state["req_slots"]:
		return false
	var rq: Dictionary = content["requests"][req_id]
	var uid: int = state["next_uid"]; state["next_uid"] += 1
	state["active"].append({"uid": uid, "req_id": req_id, "patience_left": rq["patience_ticks"]})
	events.append(["arrive", uid, req_id])
	return true

static func _advance_generator(content: Dictionary, state: Dictionary, events: Array) -> void:
	var gen: Dictionary = state["gen"]
	while gen["script_cursor"] < gen["script"].size():
		var ev: Dictionary = gen["script"][gen["script_cursor"]]
		if ev["at_ticks"] > state["tick"]:
			break
		if state["active"].size() < state["req_slots"]:
			_spawn_request(content, state, ev["request"], events)
			gen["script_cursor"] += 1
		else:
			break
	var rng := Pcg32.new()
	rng.state = state["rng"][0]; rng.inc = state["rng"][1]
	for p in gen["pools"]:
		if state["tick"] < p["from"] or state["tick"] > p["to"]:
			continue
		if state["tick"] >= p["next_at"]:
			if state["active"].size() < state["req_slots"]:
				var pick: String = p["pool"][rng.below(p["pool"].size())]
				_spawn_request(content, state, pick, events)
				var gap := rng.between(p["interval"][0], p["interval"][1])
				p["next_at"] = state["tick"] + gap
	state["rng"][0] = rng.state; state["rng"][1] = rng.inc

# ── 틱 진행 ───────────────────────────────────────────────────────────
static func _advance_facilities(content: Dictionary, state: Dictionary, events: Array) -> void:
	for fac in state["facilities"]:
		if fac["recipe"] != null:
			fac["ticks_left"] -= 1
			if fac["ticks_left"] <= 0:
				var r: Dictionary = content["recipes"][fac["recipe"]]
				if r["type"] == "enhance":
					var pe: Array = fac["pending_eq"]
					fac["out_key"] = eq_key(pe[0], pe[1])
					fac["overheat_left"] = -1
					fac["pending_eq"] = null
				elif r["type"] == "transform":
					fac["out_key"] = r["out"]
					fac["overheat_left"] = r["overheat_grace_ticks"]
				elif r["type"] == "craft":
					fac["out_key"] = eq_key(r["out"], 0)
					fac["overheat_left"] = -1
				else:  # synthesize
					fac["out_key"] = r["out"]
					fac["overheat_left"] = -1
				if r["type"] != "transform":
					state["workers_busy"] -= 1
				events.append(["complete", fac["idx"], fac["out_key"]])
				fac["recipe"] = null
		elif fac["out_key"] != null and fac["overheat_left"] >= 0:
			fac["overheat_left"] -= 1
			if fac["overheat_left"] == 0:
				events.append(["overheat_loss", fac["idx"], fac["out_key"]])
				fac["out_key"] = null
				fac["overheat_left"] = -1

static func _advance_patience(content: Dictionary, state: Dictionary, events: Array) -> void:
	var survivors := []
	for a in state["active"]:
		a["patience_left"] -= 1
		if a["patience_left"] <= 0:
			events.append(["withdraw", a["uid"], a["req_id"]])
		else:
			survivors.append(a)
	state["active"] = survivors

static func step(content: Dictionary, state: Dictionary, commands: Array) -> Array:
	var events := []
	if state["done"]:
		return events
	for cmd in commands:
		state["cmd_seq"] += 1
		apply_command(content, state, cmd, events)
	_advance_facilities(content, state, events)
	_advance_patience(content, state, events)
	_advance_generator(content, state, events)
	state["tick"] += 1
	if state["tick"] >= state["deadline"]:
		state["done"] = true
		events.append(["deadline", state["score"], stars(state)])
	return events

static func stars(state: Dictionary) -> int:
	var c: Dictionary = state["cutlines"]
	var s: int = state["score"]
	if s < c["fail_under"]:
		return 0
	if s >= c["star3"]:
		return 3
	if s >= c["star2"]:
		return 2
	if s >= c["star1"]:
		return 1
	return 0

# ── 정규 문자열·해시 (플랫폼 §7.4, Python canonical과 일치) ───────────
static func canonical(state: Dictionary) -> String:
	var p := "t=%d;sc=%d;wb=%d" % [state["tick"], state["score"], state["workers_busy"]]
	p += ";uid=%d;done=%d" % [state["next_uid"], 1 if state["done"] else 0]
	p += ";rng=%d,%d" % [state["rng"][0], state["rng"][1]]  # 부호 있는 64비트 십진(Python과 동일)
	var keys := state["inv"].keys()
	keys.sort()
	var inv_parts := []
	for k in keys:
		inv_parts.append("%s:%d" % [k, state["inv"][k]])
	p += ";inv=" + ",".join(inv_parts)
	var fac_parts := []
	for f in state["facilities"]:
		var recipe_s: String = f["recipe"] if f["recipe"] != null else "-"
		var out_s: String = f["out_key"] if f["out_key"] != null else "-"
		fac_parts.append("%s:%s:%d:%s:%d" % [f["kind"], recipe_s, f["ticks_left"], out_s, f["overheat_left"]])
	p += ";fac=" + "|".join(fac_parts)
	var act_parts := []
	for a in state["active"]:
		act_parts.append("%d:%s:%d" % [a["uid"], a["req_id"], a["patience_left"]])
	p += ";act=" + "|".join(act_parts)
	var pool_nexts := []
	for pl in state["gen"]["pools"]:
		pool_nexts.append(str(pl["next_at"]))
	p += ";gen=%d/%s" % [state["gen"]["script_cursor"], ",".join(pool_nexts)]
	return p

static func state_hash(state: Dictionary) -> String:
	return canonical(state).sha256_text().substr(0, 16)
