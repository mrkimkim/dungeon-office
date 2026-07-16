class_name RoundSimulator
extends RefCounted

## Pure deterministic 20 Hz simulator.
## This file intentionally has no Node, SceneTree, Input, OS, Time, FileAccess,
## networking, or random-number dependency.

const Contract = preload("res://src/sim/sim_contract.gd")
const Canonical = preload("res://src/sim/canonical_json.gd")

static func create_state(round_definition: Dictionary, catalog: Dictionary) -> Dictionary:
	var inventory: Array = []
	for _slot: int in range(int(round_definition.get("inventory_capacity", 0))):
		inventory.append(null)

	var workers: Array = []
	for worker_index: int in range(int(round_definition.get("worker_count", 0))):
		workers.append({
			"worker_id": "WORKER_%02d" % (worker_index + 1),
			"facility_id": "",
		})

	var facilities: Dictionary = {}
	for facility_id_value: Variant in round_definition.get("facilities", []):
		var facility_id := str(facility_id_value)
		facilities[facility_id] = {
			"facility_id": facility_id,
			"status": "empty",
			"inputs": [],
			"recipe_id": "",
			"remaining_ticks": 0,
			"worker_id": "",
			"output": null,
			"overheat_remaining_ticks": 0,
			"overheat_danger_emitted": false,
		}

	var state: Dictionary = {
		"schema": Contract.ROUND_STATE_SCHEMA,
		"sim_version": Contract.SIM_VERSION,
		"data_version": int(catalog.get("data_version", 0)),
		"round_id": str(round_definition.get("id", "")),
		"tick": 0,
		"deadline_ticks": int(round_definition.get("deadline_ticks", 0)),
		"status": "running",
		"paused": false,
		"next_command_sequence": 1,
		"next_request_index": 0,
		"score": 0,
		"workers": workers,
		"facilities": facilities,
		"inventory": inventory,
		"active_requests": [],
		"waiting_requests": [],
		"deliveries": [],
		"withdrawal_count": 0,
		"overheat_loss_count": 0,
		"threshold_flags": {
			"deadline_warning_emitted": false,
			"deadline_countdown_emitted": false,
		},
	}
	var ignored_events: Array = []
	_release_due_requests(state, round_definition, catalog, ignored_events)
	return state

static func step(
	state: Dictionary,
	commands_for_tick: Array,
	round_definition: Dictionary,
	catalog: Dictionary
) -> Dictionary:
	var next_state: Dictionary = state.duplicate(true)
	var events: Array = []
	var command_results: Array = []
	var commands: Array = commands_for_tick.duplicate(true)
	var control_command_present := false
	commands.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("sequence", 0)) < int(right.get("sequence", 0))
	)

	for raw_command: Variant in commands:
		var command: Dictionary = raw_command if raw_command is Dictionary else {}
		if str(command.get("type", "")) in [Contract.COMMAND_PAUSE, Contract.COMMAND_RESUME]:
			control_command_present = true
		var result := _apply_command(next_state, command, round_definition, catalog)
		result["tick"] = int(command.get("tick", -1))
		result["sequence"] = int(command.get("sequence", -1))
		result["type"] = str(command.get("type", ""))
		command_results.append(result)
		events.append_array(result.get("events", []))

	if str(next_state.get("status", "")) != "running":
		return {"state": next_state, "command_results": command_results, "events": events}

	# Pause and resume are control-only calls. Even a rejected control request must not
	# accidentally spend a simulation interval while the UI reconciles its state.
	if control_command_present:
		return {"state": next_state, "command_results": command_results, "events": events}

	if bool(next_state.get("paused", false)):
		return {"state": next_state, "command_results": command_results, "events": events}

	# Existing hot outputs lose grace before newly completed outputs are created,
	# so a completion receives the full configured grace period.
	_advance_overheat(next_state, events)
	_advance_work(next_state, catalog, events)
	_advance_request_patience(next_state, round_definition, catalog, events)
	_emit_threshold_events(next_state, catalog, events)

	next_state["tick"] = int(next_state.get("tick", 0)) + 1
	_release_due_requests(next_state, round_definition, catalog, events)

	if int(next_state["tick"]) >= int(next_state.get("deadline_ticks", 0)):
		next_state["status"] = "ended"
		next_state["paused"] = false
		next_state["active_requests"] = []
		next_state["waiting_requests"] = []
		events.append({"type": "round_ended", "tick": int(next_state["tick"]), "score": int(next_state["score"])})

	return {"state": next_state, "command_results": command_results, "events": events}

static func state_hash(state: Dictionary) -> String:
	return Canonical.sha256(state)

static func preview_command(
	state: Dictionary,
	type: String,
	payload: Dictionary,
	round_definition: Dictionary,
	catalog: Dictionary
) -> Dictionary:
	## Runs the authoritative command validator against a deep copy. UI read models use
	## this instead of duplicating recipe, inventory, worker, or delivery rules.
	var probe: Dictionary = state.duplicate(true)
	var command := Contract.command(
		int(probe.get("tick", 0)),
		int(probe.get("next_command_sequence", 1)),
		type,
		payload
	)
	return _apply_command(probe, command, round_definition, catalog)

static func inspect_source(
	state: Dictionary,
	source: Dictionary,
	round_definition: Dictionary
) -> Dictionary:
	var inspected := _peek_source(state, source, round_definition)
	return inspected.duplicate(true)

static func _apply_command(
	state: Dictionary,
	command: Dictionary,
	round_definition: Dictionary,
	catalog: Dictionary
) -> Dictionary:
	if str(state.get("status", "")) != "running":
		return Contract.rejected(Contract.REJECT_ROUND_NOT_RUNNING)
	if int(command.get("tick", -1)) != int(state.get("tick", 0)):
		return Contract.rejected(Contract.REJECT_WRONG_TICK)

	var sequence := int(command.get("sequence", -1))
	var expected_sequence := int(state.get("next_command_sequence", 1))
	if sequence < expected_sequence:
		return Contract.rejected(Contract.REJECT_STALE_SEQUENCE)
	if sequence > expected_sequence:
		return Contract.rejected(Contract.REJECT_SEQUENCE_GAP)
	state["next_command_sequence"] = sequence + 1

	var type := str(command.get("type", ""))
	var payload: Dictionary = command.get("payload", {}) if command.get("payload", {}) is Dictionary else {}
	if bool(state.get("paused", false)) and type not in [Contract.COMMAND_RESUME, Contract.COMMAND_PAUSE]:
		return Contract.rejected(Contract.REJECT_PAUSED)

	match type:
		Contract.COMMAND_MOVE:
			return _command_move(state, payload, round_definition, catalog)
		Contract.COMMAND_START:
			return _command_start(state, payload, catalog)
		Contract.COMMAND_STORE:
			return _command_store(state, payload)
		Contract.COMMAND_DELIVER:
			return _command_deliver(state, payload, round_definition, catalog)
		Contract.COMMAND_DISCARD:
			return _command_discard(state, payload, round_definition, catalog)
		Contract.COMMAND_PAUSE:
			if bool(state.get("paused", false)):
				return Contract.rejected(Contract.REJECT_ALREADY_PAUSED)
			state["paused"] = true
			return Contract.accepted([{"type": "paused", "tick": int(state["tick"])}])
		Contract.COMMAND_RESUME:
			if not bool(state.get("paused", false)):
				return Contract.rejected(Contract.REJECT_NOT_PAUSED)
			state["paused"] = false
			return Contract.accepted([{"type": "resumed", "tick": int(state["tick"])}])
		_:
			return Contract.rejected(Contract.REJECT_UNKNOWN_COMMAND)

static func _command_move(
	state: Dictionary,
	payload: Dictionary,
	round_definition: Dictionary,
	catalog: Dictionary
) -> Dictionary:
	var source: Dictionary = payload.get("source", {}) if payload.get("source", {}) is Dictionary else {}
	var destination: Dictionary = payload.get("destination", {}) if payload.get("destination", {}) is Dictionary else {}
	var peek := _peek_source(state, source, round_definition)
	if not bool(peek.get("ok", false)):
		return Contract.rejected(str(peek.get("reason", Contract.REJECT_INVALID_SOURCE)))
	var item: Dictionary = peek["item"].duplicate(true)
	var destination_kind := str(destination.get("kind", ""))

	if destination_kind == "inventory":
		var inventory_slot := int(destination.get("slot", -1))
		if destination.has("slot") and inventory_slot < 0:
			return Contract.rejected(Contract.REJECT_INVALID_DESTINATION)
		if inventory_slot >= state["inventory"].size():
			return Contract.rejected(Contract.REJECT_INVALID_DESTINATION)
		if inventory_slot >= 0 and state["inventory"][inventory_slot] != null:
			return Contract.rejected(Contract.REJECT_INVENTORY_FULL)
		if inventory_slot < 0:
			inventory_slot = _first_empty_inventory_slot(state)
		if inventory_slot < 0:
			return Contract.rejected(Contract.REJECT_INVENTORY_FULL)
		_remove_source(state, source, catalog)
		state["inventory"][inventory_slot] = item
		return Contract.accepted([{
			"type": "item_moved",
			"item": item,
			"destination": {"kind": "inventory", "slot": inventory_slot},
		}])

	if destination_kind == "facility_input":
		var facility_id := str(destination.get("facility_id", ""))
		if not state["facilities"].has(facility_id):
			return Contract.rejected(Contract.REJECT_FACILITY_UNAVAILABLE)
		if (
			str(source.get("kind", "")) == "facility_input"
			and str(source.get("facility_id", "")) == facility_id
		):
			return Contract.rejected(Contract.REJECT_INVALID_DESTINATION)
		var facility: Dictionary = state["facilities"][facility_id]
		if str(facility.get("status", "")) in ["working", "output"]:
			return Contract.rejected(Contract.REJECT_FACILITY_BUSY)
		var trial_inputs: Array = facility.get("inputs", []).duplicate(true)
		trial_inputs.append(item)
		if _matching_recipes_for_inputs(catalog, facility_id, trial_inputs, false).is_empty():
			return Contract.rejected(Contract.REJECT_INVALID_RECIPE_INPUT)
		_remove_source(state, source, catalog)
		facility["inputs"].append(item)
		var exact_recipes := _matching_recipes_for_inputs(catalog, facility_id, facility["inputs"], true)
		facility["status"] = "ready" if not exact_recipes.is_empty() else "input"
		var emitted: Array = [{"type": "facility_input_added", "facility_id": facility_id, "item": item}]
		if not exact_recipes.is_empty() and str(exact_recipes[0].get("worker_mode", "")) == "none":
			_begin_recipe(state, facility, exact_recipes[0], "", emitted)
		return Contract.accepted(emitted)

	return Contract.rejected(Contract.REJECT_INVALID_DESTINATION)

static func _command_start(state: Dictionary, payload: Dictionary, catalog: Dictionary) -> Dictionary:
	var facility_id := str(payload.get("facility_id", ""))
	if not state["facilities"].has(facility_id):
		return Contract.rejected(Contract.REJECT_FACILITY_UNAVAILABLE)
	var facility: Dictionary = state["facilities"][facility_id]
	if str(facility.get("status", "")) in ["working", "output"]:
		return Contract.rejected(Contract.REJECT_FACILITY_BUSY)
	var exact_recipes := _matching_recipes_for_inputs(catalog, facility_id, facility.get("inputs", []), true)
	if exact_recipes.is_empty():
		return Contract.rejected(Contract.REJECT_INPUT_INCOMPLETE)
	var recipe: Dictionary = exact_recipes[0]
	if str(recipe.get("worker_mode", "")) != "one":
		return Contract.rejected(Contract.REJECT_UNKNOWN_COMMAND)
	var worker_index := _first_idle_worker_index(state)
	if worker_index < 0:
		return Contract.rejected(Contract.REJECT_NO_IDLE_WORKER)
	var worker: Dictionary = state["workers"][worker_index]
	worker["facility_id"] = facility_id
	var emitted: Array = []
	_begin_recipe(state, facility, recipe, str(worker["worker_id"]), emitted)
	return Contract.accepted(emitted)

static func _command_store(state: Dictionary, payload: Dictionary) -> Dictionary:
	var facility_id := str(payload.get("facility_id", ""))
	if not state["facilities"].has(facility_id):
		return Contract.rejected(Contract.REJECT_FACILITY_UNAVAILABLE)
	var facility: Dictionary = state["facilities"][facility_id]
	if str(facility.get("status", "")) != "output" or facility.get("output") == null:
		return Contract.rejected(Contract.REJECT_NO_OUTPUT)
	var inventory_slot := _first_empty_inventory_slot(state)
	if inventory_slot < 0:
		return Contract.rejected(Contract.REJECT_INVENTORY_FULL)
	var item: Dictionary = facility["output"].duplicate(true)
	state["inventory"][inventory_slot] = item
	_clear_facility_output(facility)
	return Contract.accepted([{
		"type": "item_stored",
		"facility_id": facility_id,
		"slot": inventory_slot,
		"item": item,
	}])

static func _command_deliver(
	state: Dictionary,
	payload: Dictionary,
	round_definition: Dictionary,
	catalog: Dictionary
) -> Dictionary:
	var source: Dictionary = payload.get("source", {}) if payload.get("source", {}) is Dictionary else {}
	var peek := _peek_source(state, source, round_definition)
	if not bool(peek.get("ok", false)):
		return Contract.rejected(str(peek.get("reason", Contract.REJECT_INVALID_SOURCE)))
	var item: Dictionary = peek["item"]
	var item_definition := _find_by_id(catalog.get("items", []), str(item.get("item_id", "")))
	if item_definition.is_empty() or str(item_definition.get("category", "")) != "equipment":
		return Contract.rejected(Contract.REJECT_NOT_EQUIPMENT)

	var selected_index := -1
	for request_index: int in range(state["active_requests"].size()):
		var request: Dictionary = state["active_requests"][request_index]
		if str(request.get("item_id", "")) != str(item.get("item_id", "")):
			continue
		if int(item.get("enhancement_level", 0)) < int(request.get("required_level", 0)):
			continue
		if selected_index < 0 or _request_precedes(request, state["active_requests"][selected_index]):
			selected_index = request_index
	if selected_index < 0:
		return Contract.rejected(Contract.REJECT_NO_MATCHING_REQUEST)

	var selected_request: Dictionary = state["active_requests"][selected_index]
	_remove_source(state, source, catalog)
	state["active_requests"].remove_at(selected_index)
	state["score"] = int(state.get("score", 0)) + int(selected_request.get("score", 0))
	state["deliveries"].append({
		"event_id": selected_request.get("event_id", ""),
		"request_id": selected_request.get("request_id", ""),
		"item": item.duplicate(true),
		"score": int(selected_request.get("score", 0)),
		"tick": int(state.get("tick", 0)),
	})
	var emitted: Array = [{
		"type": "delivered",
		"event_id": selected_request.get("event_id", ""),
		"score": int(selected_request.get("score", 0)),
		"total_score": int(state["score"]),
	}]
	return Contract.accepted(emitted)

static func _command_discard(
	state: Dictionary,
	payload: Dictionary,
	round_definition: Dictionary,
	catalog: Dictionary
) -> Dictionary:
	var source: Dictionary = payload.get("source", {}) if payload.get("source", {}) is Dictionary else {}
	if str(source.get("kind", "")) == "supply":
		return Contract.rejected(Contract.REJECT_INVALID_SOURCE)
	var peek := _peek_source(state, source, round_definition)
	if not bool(peek.get("ok", false)):
		return Contract.rejected(str(peek.get("reason", Contract.REJECT_INVALID_SOURCE)))
	var item: Dictionary = peek["item"]
	_remove_source(state, source, catalog)
	return Contract.accepted([{"type": "item_discarded", "item": item}])

static func _peek_source(state: Dictionary, source: Dictionary, round_definition: Dictionary) -> Dictionary:
	match str(source.get("kind", "")):
		"supply":
			var item_id := str(source.get("item_id", ""))
			if item_id not in round_definition.get("supply_items", []):
				return {"ok": false, "reason": Contract.REJECT_ITEM_NOT_FOUND}
			return {"ok": true, "item": {"item_id": item_id, "enhancement_level": 0}}
		"inventory":
			var slot := int(source.get("slot", -1))
			if slot < 0 or slot >= state["inventory"].size():
				return {"ok": false, "reason": Contract.REJECT_INVALID_SOURCE}
			if state["inventory"][slot] == null:
				return {"ok": false, "reason": Contract.REJECT_ITEM_NOT_FOUND}
			return {"ok": true, "item": state["inventory"][slot]}
		"facility_input":
			var facility_id := str(source.get("facility_id", ""))
			var input_slot := int(source.get("slot", -1))
			if not state["facilities"].has(facility_id):
				return {"ok": false, "reason": Contract.REJECT_FACILITY_UNAVAILABLE}
			var facility: Dictionary = state["facilities"][facility_id]
			if str(facility.get("status", "")) in ["working", "output"]:
				return {"ok": false, "reason": Contract.REJECT_FACILITY_BUSY}
			if input_slot < 0 or input_slot >= facility["inputs"].size():
				return {"ok": false, "reason": Contract.REJECT_ITEM_NOT_FOUND}
			return {"ok": true, "item": facility["inputs"][input_slot]}
		"facility_output":
			var output_facility_id := str(source.get("facility_id", ""))
			if not state["facilities"].has(output_facility_id):
				return {"ok": false, "reason": Contract.REJECT_FACILITY_UNAVAILABLE}
			var output_facility: Dictionary = state["facilities"][output_facility_id]
			if str(output_facility.get("status", "")) != "output" or output_facility.get("output") == null:
				return {"ok": false, "reason": Contract.REJECT_NO_OUTPUT}
			return {"ok": true, "item": output_facility["output"]}
		_:
			return {"ok": false, "reason": Contract.REJECT_INVALID_SOURCE}

static func _remove_source(state: Dictionary, source: Dictionary, catalog: Dictionary) -> void:
	match str(source.get("kind", "")):
		"supply":
			pass
		"inventory":
			state["inventory"][int(source["slot"])] = null
		"facility_input":
			var facility: Dictionary = state["facilities"][str(source["facility_id"])]
			facility["inputs"].remove_at(int(source["slot"]))
			_recompute_facility_input_status(facility, catalog)
		"facility_output":
			_clear_facility_output(state["facilities"][str(source["facility_id"])])

static func _recompute_facility_input_status(facility: Dictionary, catalog: Dictionary) -> void:
	var inputs: Array = facility.get("inputs", [])
	if inputs.is_empty():
		facility["status"] = "empty"
		return
	var exact_recipes := _matching_recipes_for_inputs(
		catalog,
		str(facility.get("facility_id", "")),
		inputs,
		true
	)
	facility["status"] = "ready" if not exact_recipes.is_empty() else "input"

static func _begin_recipe(
	state: Dictionary,
	facility: Dictionary,
	recipe: Dictionary,
	worker_id: String,
	events: Array
) -> void:
	facility["status"] = "working"
	facility["inputs"] = []
	facility["recipe_id"] = str(recipe.get("id", ""))
	facility["remaining_ticks"] = int(recipe.get("duration_ticks", 0))
	facility["worker_id"] = worker_id
	facility["output"] = null
	facility["overheat_remaining_ticks"] = 0
	facility["overheat_danger_emitted"] = false
	events.append({
		"type": "work_started",
		"facility_id": facility.get("facility_id", ""),
		"recipe_id": facility.get("recipe_id", ""),
		"worker_id": worker_id,
		"tick": int(state.get("tick", 0)),
	})

static func _advance_work(state: Dictionary, catalog: Dictionary, events: Array) -> void:
	var facility_ids: Array = state["facilities"].keys()
	facility_ids.sort()
	for facility_id_value: Variant in facility_ids:
		var facility: Dictionary = state["facilities"][facility_id_value]
		if str(facility.get("status", "")) != "working":
			continue
		facility["remaining_ticks"] = int(facility.get("remaining_ticks", 0)) - 1
		if int(facility["remaining_ticks"]) > 0:
			continue
		var recipe := _find_by_id(catalog.get("recipes", []), str(facility.get("recipe_id", "")))
		var output_definition: Dictionary = recipe.get("output", {}) if recipe.get("output", {}) is Dictionary else {}
		facility["output"] = {
			"item_id": str(output_definition.get("item_id", "")),
			"enhancement_level": int(output_definition.get("enhancement_level", 0)),
		}
		facility["status"] = "output"
		facility["remaining_ticks"] = 0
		facility["overheat_danger_emitted"] = false
		if bool(recipe.get("overheat_output", false)):
			facility["overheat_remaining_ticks"] = int(catalog.get("rules", {}).get("overheat_grace_ticks", 0))
		var worker_id := str(facility.get("worker_id", ""))
		if not worker_id.is_empty():
			_release_worker(state, worker_id)
		facility["worker_id"] = ""
		events.append({
			"type": "work_completed",
			"facility_id": str(facility_id_value),
			"recipe_id": str(recipe.get("id", "")),
			"output": facility["output"].duplicate(true),
			"tick": int(state.get("tick", 0)),
		})

static func _advance_overheat(state: Dictionary, events: Array) -> void:
	var facility_ids: Array = state["facilities"].keys()
	facility_ids.sort()
	for facility_id_value: Variant in facility_ids:
		var facility: Dictionary = state["facilities"][facility_id_value]
		if str(facility.get("status", "")) != "output":
			continue
		if int(facility.get("overheat_remaining_ticks", 0)) <= 0:
			continue
		facility["overheat_remaining_ticks"] = int(facility["overheat_remaining_ticks"]) - 1
		if int(facility["overheat_remaining_ticks"]) > 0:
			continue
		var lost_item: Dictionary = facility["output"].duplicate(true)
		_clear_facility_output(facility)
		state["overheat_loss_count"] = int(state.get("overheat_loss_count", 0)) + 1
		events.append({
			"type": "overheat_loss",
			"facility_id": str(facility_id_value),
			"item": lost_item,
			"tick": int(state.get("tick", 0)),
		})

static func _advance_request_patience(
	state: Dictionary,
	round_definition: Dictionary,
	_catalog: Dictionary,
	events: Array
) -> void:
	var withdrawn_requests: Array = []
	var surviving_requests: Array = []
	for request_value: Variant in state["active_requests"]:
		var request: Dictionary = request_value
		request["remaining_patience_ticks"] = int(request.get("remaining_patience_ticks", 0)) - 1
		if int(request["remaining_patience_ticks"]) <= 0:
			withdrawn_requests.append(request)
		else:
			surviving_requests.append(request)
	state["active_requests"] = surviving_requests
	withdrawn_requests.sort_custom(_request_activation_precedes)
	for withdrawn_value: Variant in withdrawn_requests:
		var withdrawn: Dictionary = withdrawn_value
		state["withdrawal_count"] = int(state.get("withdrawal_count", 0)) + 1
		events.append({
			"type": "request_withdrawn",
			"event_id": withdrawn.get("event_id", ""),
			"tick": int(state.get("tick", 0)),
		})
	_fill_active_request_slots(state, round_definition, events)

static func _release_due_requests(
	state: Dictionary,
	round_definition: Dictionary,
	catalog: Dictionary,
	events: Array
) -> void:
	var round_events: Array = round_definition.get("events", [])
	while int(state.get("next_request_index", 0)) < round_events.size():
		var event_index := int(state["next_request_index"])
		var event_definition: Dictionary = round_events[event_index]
		if int(event_definition.get("release_tick", 0)) > int(state.get("tick", 0)):
			break
		state["next_request_index"] = event_index + 1
		var request_definition := _find_by_id(catalog.get("requests", []), str(event_definition.get("request_id", "")))
		var request_instance: Dictionary = {
			"event_id": str(event_definition.get("event_id", "")),
			"request_id": str(request_definition.get("id", "")),
			"item_id": str(request_definition.get("item_id", "")),
			"required_level": int(request_definition.get("required_level", 0)),
			"score": int(request_definition.get("score", 0)),
			"patience_ticks": int(request_definition.get("patience_ticks", 0)),
				"remaining_patience_ticks": int(request_definition.get("patience_ticks", 0)),
				"release_tick": int(event_definition.get("release_tick", 0)),
				"activated_tick": -1,
				"urgent_emitted": false,
			}
		if state["active_requests"].size() < int(round_definition.get("active_request_slots", 0)):
			_activate_request(state, request_instance, events)
		else:
			state["waiting_requests"].append(request_instance)
			events.append({
				"type": "request_waiting",
				"event_id": request_instance["event_id"],
				"tick": int(state.get("tick", 0)),
			})

static func _activate_request(state: Dictionary, request: Dictionary, events: Array) -> void:
	request["activated_tick"] = int(state.get("tick", 0))
	request["remaining_patience_ticks"] = int(request.get("patience_ticks", 0))
	request["urgent_emitted"] = bool(request.get("urgent_emitted", false))
	state["active_requests"].append(request)
	events.append({
		"type": "request_activated",
		"event_id": request.get("event_id", ""),
		"request_id": request.get("request_id", ""),
		"tick": int(state.get("tick", 0)),
	})

static func _fill_active_request_slots(
	state: Dictionary,
	round_definition: Dictionary,
	events: Array
) -> void:
	var active_limit := int(round_definition.get("active_request_slots", 0))
	while state["active_requests"].size() < active_limit and not state["waiting_requests"].is_empty():
		var request: Dictionary = state["waiting_requests"].pop_front()
		_activate_request(state, request, events)

static func _emit_threshold_events(state: Dictionary, catalog: Dictionary, events: Array) -> void:
	var rules: Dictionary = catalog.get("rules", {}) if catalog.get("rules", {}) is Dictionary else {}
	var overheat_threshold := int(rules.get("overheat_danger_ticks", 0))
	var facility_ids: Array = state.get("facilities", {}).keys()
	facility_ids.sort()
	for facility_id_value: Variant in facility_ids:
		var facility: Dictionary = state["facilities"][facility_id_value]
		var remaining := int(facility.get("overheat_remaining_ticks", 0))
		if (
			overheat_threshold > 0
			and remaining > 0
			and remaining <= overheat_threshold
			and not bool(facility.get("overheat_danger_emitted", false))
		):
			facility["overheat_danger_emitted"] = true
			events.append({
				"type": "overheat_danger_entered",
				"facility_id": str(facility_id_value),
				"remaining_ticks": remaining,
				"tick": int(state.get("tick", 0)),
			})

	var request_threshold := int(rules.get("request_urgent_ticks", 0))
	var ordered_requests: Array = state.get("active_requests", []).duplicate()
	ordered_requests.sort_custom(_request_activation_precedes)
	for request_value: Variant in ordered_requests:
		var request: Dictionary = request_value
		var remaining := int(request.get("remaining_patience_ticks", 0))
		if (
			request_threshold > 0
			and remaining > 0
			and remaining <= request_threshold
			and not bool(request.get("urgent_emitted", false))
		):
			request["urgent_emitted"] = true
			events.append({
				"type": "request_urgent_entered",
				"event_id": str(request.get("event_id", "")),
				"remaining_ticks": remaining,
				"tick": int(state.get("tick", 0)),
			})

	var threshold_flags: Dictionary = (
		state.get("threshold_flags", {}) if state.get("threshold_flags", {}) is Dictionary else {}
	)
	state["threshold_flags"] = threshold_flags
	var remaining_deadline := maxi(
		0,
		int(state.get("deadline_ticks", 0)) - int(state.get("tick", 0)) - 1
	)
	var deadline_warning := int(rules.get("deadline_warning_ticks", 0))
	if (
		deadline_warning > 0
		and remaining_deadline > 0
		and remaining_deadline <= deadline_warning
		and not bool(threshold_flags.get("deadline_warning_emitted", false))
	):
		threshold_flags["deadline_warning_emitted"] = true
		events.append({
			"type": "deadline_warning_entered",
			"remaining_ticks": remaining_deadline,
			"tick": int(state.get("tick", 0)),
		})
	var deadline_countdown := int(rules.get("deadline_countdown_ticks", 0))
	if (
		deadline_countdown > 0
		and remaining_deadline > 0
		and remaining_deadline <= deadline_countdown
		and not bool(threshold_flags.get("deadline_countdown_emitted", false))
	):
		threshold_flags["deadline_countdown_emitted"] = true
		events.append({
			"type": "deadline_countdown_entered",
			"remaining_ticks": remaining_deadline,
			"tick": int(state.get("tick", 0)),
		})

static func _matching_recipes_for_inputs(
	catalog: Dictionary,
	facility_id: String,
	inputs: Array,
	require_exact: bool
) -> Array:
	var matches: Array = []
	for recipe_value: Variant in catalog.get("recipes", []):
		var recipe: Dictionary = recipe_value
		if str(recipe.get("facility_id", "")) != facility_id:
			continue
		if _inputs_fit_recipe(inputs, recipe.get("inputs", []), require_exact):
			matches.append(recipe)
	matches.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("id", "")) < str(right.get("id", ""))
	)
	return matches

static func _inputs_fit_recipe(actual_items: Array, required_entries: Array, require_exact: bool) -> bool:
	var actual_counts: Dictionary = {}
	for item_value: Variant in actual_items:
		var item: Dictionary = item_value
		var key := _item_key(str(item.get("item_id", "")), int(item.get("enhancement_level", 0)))
		actual_counts[key] = int(actual_counts.get(key, 0)) + 1
	var required_counts: Dictionary = {}
	for entry_value: Variant in required_entries:
		var entry: Dictionary = entry_value
		var key := _item_key(str(entry.get("item_id", "")), int(entry.get("enhancement_level", 0)))
		required_counts[key] = int(required_counts.get(key, 0)) + int(entry.get("count", 0))
	for key: Variant in actual_counts:
		if not required_counts.has(key) or int(actual_counts[key]) > int(required_counts[key]):
			return false
	if require_exact:
		return actual_counts == required_counts
	return true

static func _item_key(item_id: String, enhancement_level: int) -> String:
	return "%s@%d" % [item_id, enhancement_level]

static func _first_empty_inventory_slot(state: Dictionary) -> int:
	for slot: int in range(state["inventory"].size()):
		if state["inventory"][slot] == null:
			return slot
	return -1

static func _first_idle_worker_index(state: Dictionary) -> int:
	for worker_index: int in range(state["workers"].size()):
		if str(state["workers"][worker_index].get("facility_id", "")).is_empty():
			return worker_index
	return -1

static func _release_worker(state: Dictionary, worker_id: String) -> void:
	for worker_value: Variant in state["workers"]:
		var worker: Dictionary = worker_value
		if str(worker.get("worker_id", "")) == worker_id:
			worker["facility_id"] = ""
			return

static func _clear_facility_output(facility: Dictionary) -> void:
	facility["status"] = "empty"
	facility["recipe_id"] = ""
	facility["remaining_ticks"] = 0
	facility["worker_id"] = ""
	facility["output"] = null
	facility["overheat_remaining_ticks"] = 0
	facility["overheat_danger_emitted"] = false

static func _request_precedes(left: Dictionary, right: Dictionary) -> bool:
	if int(left.get("score", 0)) != int(right.get("score", 0)):
		return int(left.get("score", 0)) > int(right.get("score", 0))
	if int(left.get("activated_tick", 0)) != int(right.get("activated_tick", 0)):
		return int(left.get("activated_tick", 0)) < int(right.get("activated_tick", 0))
	return str(left.get("event_id", "")) < str(right.get("event_id", ""))

static func _request_activation_precedes(left: Dictionary, right: Dictionary) -> bool:
	if int(left.get("activated_tick", -1)) != int(right.get("activated_tick", -1)):
		return int(left.get("activated_tick", -1)) < int(right.get("activated_tick", -1))
	if int(left.get("release_tick", -1)) != int(right.get("release_tick", -1)):
		return int(left.get("release_tick", -1)) < int(right.get("release_tick", -1))
	return str(left.get("event_id", "")) < str(right.get("event_id", ""))

static func _find_by_id(entries: Array, id: String) -> Dictionary:
	for entry_value: Variant in entries:
		var entry: Dictionary = entry_value
		if str(entry.get("id", "")) == id:
			return entry
	return {}
