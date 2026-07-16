class_name SettlementService
extends RefCounted

static func calculate(round_definition: Dictionary, round_state: Dictionary, run_id: String) -> Dictionary:
	var score := int(round_state.get("score", 0))
	var cutlines: Array = round_definition.get("cutlines", [])
	var stars := 0
	if cutlines.size() == 3:
		if score >= int(cutlines[2]):
			stars = 3
		elif score >= int(cutlines[1]):
			stars = 2
		elif score >= int(cutlines[0]):
			stars = 1
	var rewards: Dictionary = round_definition.get("rewards", {})
	return {
		"schema": "SettlementV1",
		"result_id": run_id,
		"round_id": str(round_definition.get("id", "")),
		"score": score,
		"stars": stars,
		"repeat_reward": int(rewards.get(str(stars), 0)),
		"first_clear_bonus": int(round_definition.get("first_clear_bonus", 0)),
		"deliveries": round_state.get("deliveries", []).duplicate(true),
		"withdrawal_count": int(round_state.get("withdrawal_count", 0)),
		"overheat_loss_count": int(round_state.get("overheat_loss_count", 0)),
	}
