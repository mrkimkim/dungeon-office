class_name RoundReadModel
extends RefCounted

## Pure, presentation-ready projection for the graybox play screen. All action
## availability is obtained by probing RoundSimulator's authoritative validator.

const Contract = preload("res://src/sim/sim_contract.gd")
const Simulator = preload("res://src/sim/round_simulator.gd")

const STATUS_LABELS: Dictionary = {
	"empty": "비어 있음",
	"input": "재료 투입 중",
	"ready": "작업 가능",
	"working": "작업 중",
	"output": "완료품 대기",
}

static func build(
	state: Dictionary,
	round_definition: Dictionary,
	catalog: Dictionary,
	selected_source: Dictionary = {}
) -> Dictionary:
	var rules: Dictionary = catalog.get("rules", {}) if catalog.get("rules", {}) is Dictionary else {}
	var facilities: Array = []
	var startable_facility_ids: Array[String] = []
	var storable_facility_ids: Array[String] = []
	var facility_ids: Array = state.get("facilities", {}).keys()
	facility_ids.sort()
	for facility_id_value: Variant in facility_ids:
		var facility_id := str(facility_id_value)
		var facility: Dictionary = state["facilities"][facility_id]
		var start_preview := Simulator.preview_command(
			state,
			Contract.COMMAND_START,
			{"facility_id": facility_id},
			round_definition,
			catalog
		)
		var store_preview := Simulator.preview_command(
			state,
			Contract.COMMAND_STORE,
			{"facility_id": facility_id},
			round_definition,
			catalog
		)
		if bool(start_preview.get("accepted", false)):
			startable_facility_ids.append(facility_id)
		if bool(store_preview.get("accepted", false)):
			storable_facility_ids.append(facility_id)
		facilities.append(_facility_view(facility, catalog, rules, start_preview, store_preview))

	var inventory: Array = []
	for slot: int in range(state.get("inventory", []).size()):
		var item_value: Variant = state["inventory"][slot]
		if item_value == null:
			inventory.append(null)
		else:
			var view := _item_view(item_value, catalog)
			view["source"] = {"kind": "inventory", "slot": slot}
			inventory.append(view)

	var supply_items: Array = []
	for item_id_value: Variant in round_definition.get("supply_items", []):
		var item_id := str(item_id_value)
		var view := _item_view({"item_id": item_id, "enhancement_level": 0}, catalog)
		view["source"] = {"kind": "supply", "item_id": item_id}
		supply_items.append(view)

	var active_requests: Array = []
	for request_value: Variant in state.get("active_requests", []):
		active_requests.append(_request_view(request_value, catalog, rules))

	var pause_preview := Simulator.preview_command(
		state,
		Contract.COMMAND_PAUSE,
		{},
		round_definition,
		catalog
	)
	var resume_preview := Simulator.preview_command(
		state,
		Contract.COMMAND_RESUME,
		{},
		round_definition,
		catalog
	)
	return {
		"round_id": str(state.get("round_id", "")),
		"round_display_name": str(round_definition.get("display_name", "")),
		"tick": int(state.get("tick", 0)),
		"status": str(state.get("status", "")),
		"paused": bool(state.get("paused", false)),
		"remaining_ticks": maxi(
			0,
			int(state.get("deadline_ticks", 0)) - int(state.get("tick", 0))
		),
		"score": int(state.get("score", 0)),
		"idle_worker_count": _idle_worker_count(state),
		"worker_count": state.get("workers", []).size(),
		"supply_items": supply_items,
		"inventory": inventory,
		"facilities": facilities,
		"active_requests": active_requests,
		"waiting_request_count": state.get("waiting_requests", []).size(),
		"commands": {
			"startable_facility_ids": startable_facility_ids,
			"storable_facility_ids": storable_facility_ids,
			"can_pause": bool(pause_preview.get("accepted", false)),
			"can_resume": bool(resume_preview.get("accepted", false)),
		},
		"selected_actions": _selected_actions(
			state,
			round_definition,
			catalog,
			selected_source
		),
	}

static func _facility_view(
	facility: Dictionary,
	catalog: Dictionary,
	rules: Dictionary,
	start_preview: Dictionary,
	store_preview: Dictionary
) -> Dictionary:
	var facility_id := str(facility.get("facility_id", ""))
	var definition := _find_by_id(catalog.get("facilities", []), facility_id)
	var inputs: Array = []
	for slot: int in range(facility.get("inputs", []).size()):
		var input_view := _item_view(facility["inputs"][slot], catalog)
		input_view["source"] = {
			"kind": "facility_input",
			"facility_id": facility_id,
			"slot": slot,
		}
		inputs.append(input_view)
	var output: Variant = null
	if facility.get("output") is Dictionary:
		output = _item_view(facility["output"], catalog)
		output["source"] = {"kind": "facility_output", "facility_id": facility_id}
	var overheat_remaining := int(facility.get("overheat_remaining_ticks", 0))
	return {
		"facility_id": facility_id,
		"display_name": str(definition.get("display_name", facility_id)),
		"status": str(facility.get("status", "empty")),
		"status_label": str(STATUS_LABELS.get(str(facility.get("status", "empty")), "알 수 없음")),
		"inputs": inputs,
		"output": output,
		"remaining_ticks": int(facility.get("remaining_ticks", 0)),
		"overheat_remaining_ticks": overheat_remaining,
		"overheat_danger": (
			overheat_remaining > 0
			and overheat_remaining <= int(rules.get("overheat_danger_ticks", 0))
		),
		"worker_id": str(facility.get("worker_id", "")),
		"can_start": bool(start_preview.get("accepted", false)),
		"start_reject_reason": str(start_preview.get("reason", Contract.REJECT_NONE)),
		"can_store": bool(store_preview.get("accepted", false)),
		"store_reject_reason": str(store_preview.get("reason", Contract.REJECT_NONE)),
	}

static func _request_view(request_value: Variant, catalog: Dictionary, rules: Dictionary) -> Dictionary:
	var request: Dictionary = request_value if request_value is Dictionary else {}
	var item := _item_view({
		"item_id": str(request.get("item_id", "")),
		"enhancement_level": int(request.get("required_level", 0)),
	}, catalog)
	var remaining := int(request.get("remaining_patience_ticks", 0))
	var urgent_threshold := int(rules.get("request_urgent_ticks", 0))
	return {
		"event_id": str(request.get("event_id", "")),
		"request_id": str(request.get("request_id", "")),
		"item_id": str(request.get("item_id", "")),
		"required_level": int(request.get("required_level", 0)),
		"item_display_name": str(item.get("display_name", "")),
		"display_name": "%s · %d점" % [item.get("display_name", ""), int(request.get("score", 0))],
		"score": int(request.get("score", 0)),
		"remaining_patience_ticks": remaining,
		"urgent": urgent_threshold > 0 and remaining > 0 and remaining <= urgent_threshold,
	}

static func _selected_actions(
	state: Dictionary,
	round_definition: Dictionary,
	catalog: Dictionary,
	selected_source: Dictionary
) -> Dictionary:
	if selected_source.is_empty():
		return {
			"has_selection": false,
			"move_destinations": [],
			"can_move": false,
			"can_deliver": false,
			"can_discard": false,
		}
	var inspected := Simulator.inspect_source(state, selected_source, round_definition)
	if not bool(inspected.get("ok", false)):
		return {
			"has_selection": false,
			"source": selected_source.duplicate(true),
			"reason": str(inspected.get("reason", Contract.REJECT_INVALID_SOURCE)),
			"move_destinations": [],
			"can_move": false,
			"can_deliver": false,
			"can_discard": false,
		}

	var destinations: Array = []
	_add_destination_if_legal(
		destinations,
		state,
		round_definition,
		catalog,
		selected_source,
		{"kind": "inventory"},
		"인벤토리"
	)
	for facility_id_value: Variant in round_definition.get("facilities", []):
		var facility_id := str(facility_id_value)
		var definition := _find_by_id(catalog.get("facilities", []), facility_id)
		_add_destination_if_legal(
			destinations,
			state,
			round_definition,
			catalog,
			selected_source,
			{"kind": "facility_input", "facility_id": facility_id},
			str(definition.get("display_name", facility_id))
		)

	var deliver_preview := Simulator.preview_command(
		state,
		Contract.COMMAND_DELIVER,
		{"source": selected_source.duplicate(true)},
		round_definition,
		catalog
	)
	var discard_preview := Simulator.preview_command(
		state,
		Contract.COMMAND_DISCARD,
		{"source": selected_source.duplicate(true)},
		round_definition,
		catalog
	)
	return {
		"has_selection": true,
		"source": selected_source.duplicate(true),
		"item": _item_view(inspected.get("item", {}), catalog),
		"move_destinations": destinations,
		"can_move": not destinations.is_empty(),
		"can_deliver": bool(deliver_preview.get("accepted", false)),
		"deliver_reject_reason": str(deliver_preview.get("reason", Contract.REJECT_NONE)),
		"can_discard": bool(discard_preview.get("accepted", false)),
		"discard_reject_reason": str(discard_preview.get("reason", Contract.REJECT_NONE)),
	}

static func _add_destination_if_legal(
	destinations: Array,
	state: Dictionary,
	round_definition: Dictionary,
	catalog: Dictionary,
	source: Dictionary,
	destination: Dictionary,
	display_name: String
) -> void:
	var preview := Simulator.preview_command(
		state,
		Contract.COMMAND_MOVE,
		{
			"source": source.duplicate(true),
			"destination": destination.duplicate(true),
		},
		round_definition,
		catalog
	)
	if bool(preview.get("accepted", false)):
		var view := destination.duplicate(true)
		view["display_name"] = display_name
		destinations.append(view)

static func _item_view(item_value: Variant, catalog: Dictionary) -> Dictionary:
	var item: Dictionary = item_value if item_value is Dictionary else {}
	var item_id := str(item.get("item_id", ""))
	var definition := _find_by_id(catalog.get("items", []), item_id)
	var level := int(item.get("enhancement_level", 0))
	var display_name := str(definition.get("display_name", item_id))
	if level > 0:
		display_name += " +%d" % level
	return {
		"item_id": item_id,
		"enhancement_level": level,
		"display_name": display_name,
		"category": str(definition.get("category", "")),
	}

static func _idle_worker_count(state: Dictionary) -> int:
	var count := 0
	for worker_value: Variant in state.get("workers", []):
		if worker_value is Dictionary and str(worker_value.get("facility_id", "")).is_empty():
			count += 1
	return count

static func _find_by_id(entries: Array, id: String) -> Dictionary:
	for entry_value: Variant in entries:
		if entry_value is Dictionary and str(entry_value.get("id", "")) == id:
			return entry_value
	return {}
