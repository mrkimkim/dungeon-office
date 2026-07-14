class_name ProfileV1
extends RefCounted

const SCHEMA: String = "ProfileV1"
const SAVE_VERSION: int = 1
const MAX_APPLIED_RESULT_IDS: int = 64

static func create(round_ids: Array[String]) -> Dictionary:
	var round_records: Dictionary = {}
	for index: int in range(round_ids.size()):
		round_records[round_ids[index]] = {
			"unlocked": index == 0,
			"best_score": 0,
			"best_stars": 0,
			"first_cleared": false,
			"completion_count": 0,
		}
	return {
		"schema": SCHEMA,
		"save_version": SAVE_VERSION,
		"gold": 0,
		"enhancement_capability_owned": false,
		"rounds": round_records,
		"client_contract_completed": false,
		"mvp_completed": false,
		"tutorial_flags": {},
		"settings": {
			"music_volume": 100,
			"sfx_volume": 100,
			"haptics_enabled": true,
			"color_assist_enabled": false,
			"large_text_enabled": false,
		},
		"next_run_sequence": 1,
		"applied_result_ids": [],
	}

static func validate(profile: Variant, round_ids: Array[String]) -> Array[String]:
	var errors: Array[String] = []
	if not profile is Dictionary:
		return ["profile root must be an object"]
	if str(profile.get("schema", "")) != SCHEMA:
		errors.append("profile.schema must be ProfileV1")
	if int(profile.get("save_version", 0)) != SAVE_VERSION:
		errors.append("unsupported profile save_version")
	if not _is_non_negative_integer(profile.get("gold")):
		errors.append("profile.gold must be a non-negative integer")
	if not profile.get("rounds") is Dictionary:
		errors.append("profile.rounds must be an object")
	else:
		for round_id: String in round_ids:
			if not profile["rounds"].has(round_id):
				errors.append("profile is missing round %s" % round_id)
				continue
			var record: Variant = profile["rounds"][round_id]
			if not record is Dictionary:
				errors.append("profile round %s must be an object" % round_id)
				continue
			for field: String in ["best_score", "best_stars", "completion_count"]:
				if not _is_non_negative_integer(record.get(field)):
					errors.append("profile round %s.%s must be a non-negative integer" % [round_id, field])
			if int(record.get("best_stars", 0)) > 3:
				errors.append("profile round %s.best_stars cannot exceed 3" % round_id)
			for flag: String in ["unlocked", "first_cleared"]:
				if not record.get(flag) is bool:
					errors.append("profile round %s.%s must be a boolean" % [round_id, flag])
	for flag: String in [
		"enhancement_capability_owned",
		"client_contract_completed",
		"mvp_completed",
	]:
		if not profile.get(flag) is bool:
			errors.append("profile.%s must be a boolean" % flag)
	if not _is_positive_integer(profile.get("next_run_sequence")):
		errors.append("profile.next_run_sequence must be a positive integer")
	if not profile.get("applied_result_ids") is Array:
		errors.append("profile.applied_result_ids must be an array")
	else:
		var seen_result_ids: Dictionary = {}
		var max_applied_sequence := 0
		for result_id_value: Variant in profile["applied_result_ids"]:
			var result_id := str(result_id_value)
			var sequence := parse_run_sequence(result_id)
			if sequence < 1:
				errors.append("profile.applied_result_ids contains an invalid run ID")
				continue
			if seen_result_ids.has(result_id):
				errors.append("profile.applied_result_ids contains a duplicate")
			seen_result_ids[result_id] = true
			max_applied_sequence = maxi(max_applied_sequence, sequence)
		if _is_positive_integer(profile.get("next_run_sequence")):
			if int(profile.get("next_run_sequence")) <= max_applied_sequence:
				errors.append("profile.next_run_sequence must exceed applied result IDs")
	if not profile.get("tutorial_flags") is Dictionary:
		errors.append("profile.tutorial_flags must be an object")
	if not profile.get("settings") is Dictionary:
		errors.append("profile.settings must be an object")
	else:
		var settings: Dictionary = profile["settings"]
		for volume: String in ["music_volume", "sfx_volume"]:
			if not _is_integer_number(settings.get(volume)) or int(settings.get(volume, -1)) not in range(0, 101):
				errors.append("profile.settings.%s must be an integer from 0 to 100" % volume)
		for flag: String in ["haptics_enabled", "color_assist_enabled", "large_text_enabled"]:
			if not settings.get(flag) is bool:
				errors.append("profile.settings.%s must be a boolean" % flag)
	return errors

static func allocate_run(profile: Dictionary) -> Dictionary:
	var updated: Dictionary = profile.duplicate(true)
	var sequence := int(updated.get("next_run_sequence", 1))
	updated["next_run_sequence"] = sequence + 1
	return {"profile": updated, "run_id": "run:%08d" % sequence}


static func reconcile_next_run_sequence(profile: Dictionary, active_run_id: String) -> Dictionary:
	var active_sequence := parse_run_sequence(active_run_id)
	if active_sequence < 1:
		return {"ok": false, "reason": "invalid_run_id", "profile": profile}
	var updated: Dictionary = profile.duplicate(true)
	var required_next := active_sequence + 1
	var changed := int(updated.get("next_run_sequence", 1)) < required_next
	if changed:
		updated["next_run_sequence"] = required_next
	return {"ok": true, "changed": changed, "profile": updated}


static func parse_run_sequence(run_id: String) -> int:
	if not run_id.begins_with("run:") or run_id.length() != 12:
		return -1
	var sequence_text := run_id.trim_prefix("run:")
	if not sequence_text.is_valid_int():
		return -1
	var sequence := sequence_text.to_int()
	if sequence < 1 or run_id != "run:%08d" % sequence:
		return -1
	return sequence

static func can_enter(profile: Dictionary, round_id: String, round_definition: Dictionary) -> Dictionary:
	if not profile.get("rounds", {}).has(round_id):
		return {"allowed": false, "reason": "unknown_round"}
	if not bool(profile["rounds"][round_id].get("unlocked", false)):
		return {"allowed": false, "reason": "round_locked"}
	var capability := str(round_definition.get("required_capability", ""))
	if not capability.is_empty() and not bool(profile.get(capability, false)):
		return {"allowed": false, "reason": "missing_capability", "capability": capability}
	return {"allowed": true, "reason": "none"}

static func apply_settlement(
	profile: Dictionary,
	settlement: Dictionary,
	round_ids: Array[String]
) -> Dictionary:
	var result_id := str(settlement.get("result_id", ""))
	var round_id := str(settlement.get("round_id", ""))
	if parse_run_sequence(result_id) < 1 or round_id not in round_ids:
		return {"ok": false, "reason": "invalid_settlement", "profile": profile}
	if result_id in profile.get("applied_result_ids", []):
		return {"ok": true, "duplicate": true, "gold_awarded": 0, "profile": profile.duplicate(true)}

	var updated: Dictionary = profile.duplicate(true)
	var record: Dictionary = updated["rounds"][round_id]
	var score := int(settlement.get("score", 0))
	var stars := clampi(int(settlement.get("stars", 0)), 0, 3)
	var first_clear := stars >= 1 and not bool(record.get("first_cleared", false))
	var gold_awarded := int(settlement.get("repeat_reward", 0))
	if first_clear:
		gold_awarded += int(settlement.get("first_clear_bonus", 0))

	record["completion_count"] = int(record.get("completion_count", 0)) + 1
	record["best_score"] = maxi(int(record.get("best_score", 0)), score)
	record["best_stars"] = maxi(int(record.get("best_stars", 0)), stars)
	if stars >= 1:
		record["first_cleared"] = true
		var round_index := round_ids.find(round_id)
		if round_index + 1 < round_ids.size():
			updated["rounds"][round_ids[round_index + 1]]["unlocked"] = true
		if round_id == "R5":
			updated["client_contract_completed"] = true
			updated["mvp_completed"] = true
	updated["gold"] = int(updated.get("gold", 0)) + gold_awarded
	updated["applied_result_ids"].append(result_id)
	while updated["applied_result_ids"].size() > MAX_APPLIED_RESULT_IDS:
		updated["applied_result_ids"].pop_front()
	return {
		"ok": true,
		"duplicate": false,
		"gold_awarded": gold_awarded,
		"first_clear": first_clear,
		"profile": updated,
	}

static func purchase_enhancement_kit(profile: Dictionary, price_gold: int) -> Dictionary:
	if bool(profile.get("enhancement_capability_owned", false)):
		return {"ok": false, "reason": "already_owned", "profile": profile}
	if not bool(profile.get("rounds", {}).get("R4", {}).get("first_cleared", false)):
		return {"ok": false, "reason": "not_available", "profile": profile}
	if int(profile.get("gold", 0)) < price_gold:
		return {
			"ok": false,
			"reason": "insufficient_gold",
			"missing_gold": price_gold - int(profile.get("gold", 0)),
			"profile": profile,
		}
	var updated: Dictionary = profile.duplicate(true)
	updated["gold"] = int(updated["gold"]) - price_gold
	updated["enhancement_capability_owned"] = true
	return {"ok": true, "reason": "none", "profile": updated}

static func _is_integer_number(value: Variant) -> bool:
	return value is int or (value is float and value == floor(value))

static func _is_non_negative_integer(value: Variant) -> bool:
	return _is_integer_number(value) and int(value) >= 0

static func _is_positive_integer(value: Variant) -> bool:
	return _is_integer_number(value) and int(value) > 0
