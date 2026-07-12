# 헤드리스 골든 리플레이 검증 (플랫폼 §7.4)
#
# 실행:  godot --headless --script tools/verify_replay.gd
#
# tests/fixtures/replay_*.json (Python 레퍼런스가 생성·검증)을 GDScript 시뮬에
# 재생하고, 체크포인트·최종 상태 해시가 픽스처와 일치하는지 대조한다. 일치하면
# GDScript 포트가 Python 레퍼런스와 결정론적으로 동일하다는 뜻이다(교차 구현 검증).
extends SceneTree

const DATA := "res://data"
const ROUNDS := ["r1", "r2"]


func _coerce(v: Variant) -> Variant:
	# JSON 정수가 float으로 들어오는 경우를 대비해 정수형으로 정규화.
	if typeof(v) == TYPE_FLOAT and v == floor(v):
		return int(v)
	return v


func _to_cmd(raw: Array) -> Array:
	var cmd := []
	for x in raw:
		cmd.append(_coerce(x))
	return cmd


func _init() -> void:
	var content := Sim.load_content(DATA)
	var fails := 0
	print("================================================================")
	print("던전 오피스 — GDScript 시뮬 골든 리플레이 검증")
	print("================================================================")

	for rid in ROUNDS:
		var rd := Sim.load_round(DATA, rid)
		var rec: Dictionary = Sim._load_json("res://tests/fixtures/replay_%s.json" % rid)

		var by_tick := {}
		for entry in rec["commands"]:
			var t := int(entry[0])
			var cmds := []
			for c in entry[1]:
				cmds.append(_to_cmd(c))
			by_tick[t] = cmds

		var cp := {}
		for c in rec["checkpoints"]:
			cp[int(c[0])] = c[1]

		var state := Sim.new_state(content, rd, int(rec["attempt"]))
		var round_ok := true
		var detail := ""
		while not state["done"]:
			var t: int = state["tick"]
			var cmds: Array = by_tick.get(t, [])
			Sim.step(content, state, cmds)
			if cp.has(state["tick"]):
				var h := Sim.state_hash(state)
				if h != cp[state["tick"]]:
					round_ok = false
					detail = "체크포인트 불일치 @tick %d: got %s, want %s" % [state["tick"], h, cp[state["tick"]]]
					break

		var final_h := Sim.state_hash(state)
		if round_ok and final_h != rec["final_hash"]:
			round_ok = false
			detail = "최종 해시 불일치: got %s, want %s" % [final_h, rec["final_hash"]]

		if round_ok:
			print("  %s: OK  점수 %d  별 %d  최종 %s  (체크포인트 %d개 일치)" % [
				rid, state["score"], Sim.stars(state), final_h, cp.size()])
		else:
			print("  %s: FAIL — %s" % [rid, detail])
			fails += 1

	print("================================================================")
	if fails == 0:
		print("결과: 전 라운드 통과 ✅  — GDScript 포트가 Python 레퍼런스와 결정론 일치")
	else:
		print("결과: 실패 %d건 — GDScript 포트가 레퍼런스와 어긋남(위 detail 참조)" % fails)
	print("================================================================")
	quit(1 if fails > 0 else 0)
