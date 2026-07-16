extends RefCounted

const DataRepositoryScript = preload("res://src/data/data_repository.gd")
const RoundSimulatorScript = preload("res://src/sim/round_simulator.gd")
const SimContractScript = preload("res://src/sim/sim_contract.gd")
const SettlementServiceScript = preload("res://src/app/settlement_service.gd")

const R1_FIXTURE_PATH: String = "res://tests/fixtures/r1_commands.json"
const REPRODUCTION_RUNS: int = 100
const SNAPSHOT_CHECKPOINT_COUNT: int = 20


static func run(test: TestFramework) -> void:
	var repository := DataRepositoryScript.new()
	var load_result := repository.load_all()
	if not bool(load_result.get("ok", false)):
		test.fail("MVP QA tests require valid data")
		return

	_test_r1_fixture_repeats_100_times(repository, test)
	var star_three_plans := _test_round_star_routes(repository, test)
	if star_three_plans.has("R5"):
		_test_twenty_json_resume_points(repository, star_three_plans["R5"], test)


static func _test_r1_fixture_repeats_100_times(
	repository: DataRepository,
	test: TestFramework
) -> void:
	var fixture := _load_json_fixture(R1_FIXTURE_PATH, test)
	if fixture.is_empty():
		return
	var timeline := _commands_by_tick(fixture.get("commands", []))
	var expected_hash := ""
	for run_index: int in range(REPRODUCTION_RUNS):
		var replay := _replay_timeline(
			repository,
			str(fixture.get("round_id", "")),
			timeline,
			test,
			"R1 reproduction run %d" % (run_index + 1),
			true
		)
		if replay.is_empty():
			return
		var final_hash := RoundSimulatorScript.state_hash(replay)
		if run_index == 0:
			expected_hash = final_hash
		else:
			test.assert_equal(
				final_hash,
				expected_hash,
				"the same R1 fixture must have one final hash on reproduction run %d" % (run_index + 1)
			)


static func _test_round_star_routes(
	repository: DataRepository,
	test: TestFramework
) -> Dictionary:
	var star_three_plans: Dictionary = {}
	for round_id: String in repository.get_round_ids():
		var round_definition := repository.get_round(round_id)
		var cutlines: Array = round_definition.get("cutlines", [])
		if cutlines.size() != 3:
			test.fail("%s needs three cutlines before route QA" % round_id)
			continue

		var star_one_plan := _generate_bot_plan(
			repository,
			round_id,
			int(cutlines[0]),
			test,
			"%s star-1 planner" % round_id
		)
		if not star_one_plan.is_empty():
			_assert_plan_result(
				repository,
				round_id,
				star_one_plan,
				1,
				1,
				test,
				"%s minimum star route" % round_id
			)

		var star_three_plan := _generate_bot_plan(
			repository,
			round_id,
			int(cutlines[2]),
			test,
			"%s star-3 planner" % round_id
		)
		if star_three_plan.is_empty():
			continue
		_assert_plan_result(
			repository,
			round_id,
			star_three_plan,
			3,
			3,
			test,
			"%s star-3 route" % round_id
		)
		star_three_plans[round_id] = star_three_plan
	return star_three_plans


static func _assert_plan_result(
	repository: DataRepository,
	round_id: String,
	plan: Dictionary,
	minimum_stars: int,
	maximum_stars: int,
	test: TestFramework,
	label: String
) -> void:
	var final_state: Dictionary = plan.get("state", {})
	var round_definition := repository.get_round(round_id)
	var settlement := SettlementServiceScript.calculate(
		round_definition,
		final_state,
		"qa:%s" % label
	)
	test.assert_equal(final_state.get("status"), "ended", "%s reaches the deadline" % label)
	var stars := int(settlement.get("stars", 0))
	test.assert_true(
		stars >= minimum_stars,
		"%s reaches at least %d star(s) (actual: %d stars, %d score)" % [
			label,
			minimum_stars,
			stars,
			int(final_state.get("score", 0)),
		]
	)
	test.assert_true(stars <= maximum_stars, "%s does not cross the intended star band" % label)
	var replay := _replay_timeline(
		repository,
		round_id,
		plan.get("timeline", {}),
		test,
		"%s deterministic replay" % label,
		true
	)
	if replay.is_empty():
		return
	test.assert_equal(
		RoundSimulatorScript.state_hash(replay),
		RoundSimulatorScript.state_hash(final_state),
		"%s final state hash survives deterministic command replay" % label
	)


static func _generate_bot_plan(
	repository: DataRepository,
	round_id: String,
	goal_score: int,
	test: TestFramework,
	label: String
) -> Dictionary:
	var round_definition := repository.get_round(round_id)
	var target_event_ids := _select_target_events(round_definition, repository.catalog, goal_score)
	var state := RoundSimulatorScript.create_state(round_definition, repository.catalog)
	var timeline: Dictionary = {}
	while str(state.get("status", "")) == "running":
		var command := _next_bot_command(
			state,
			round_definition,
			repository.catalog,
			target_event_ids
		)
		var commands: Array = []
		if not command.is_empty():
			commands.append(command)
			timeline[int(state.get("tick", 0))] = [command.duplicate(true)]
		var result := RoundSimulatorScript.step(
			state,
			commands,
			round_definition,
			repository.catalog
		)
		for command_result_value: Variant in result.get("command_results", []):
			var command_result: Dictionary = command_result_value
			test.assert_true(
				bool(command_result.get("accepted", false)),
				"%s emitted only accepted commands at tick %d: %s" % [
					label,
					int(state.get("tick", -1)),
					str(command_result.get("reason", "missing reason")),
				]
			)
			if not bool(command_result.get("accepted", false)):
				return {}
		state = result.get("state", {})
		if state.is_empty():
			test.fail("%s simulator returned no state" % label)
			return {}
	return {
		"state": state,
		"timeline": timeline,
		"target_event_ids": target_event_ids,
	}


static func _next_bot_command(
	state: Dictionary,
	round_definition: Dictionary,
	catalog: Dictionary,
	target_event_ids: Array[String]
) -> Dictionary:
	var desired_requests := _desired_requests(
		state,
		round_definition,
		catalog,
		target_event_ids
	)
	var sequence := int(state.get("next_command_sequence", 1))
	var tick := int(state.get("tick", 0))

	# Scoring always wins over production. The simulator itself chooses the highest
	# scoring compatible active request, so this remains the authoritative policy.
	for source: Dictionary in _equipment_sources(state, catalog):
		var deliver := SimContractScript.command(
			tick,
			sequence,
			SimContractScript.COMMAND_DELIVER,
			{"source": source}
		)
		if _is_accepted(state, deliver, round_definition, catalog):
			return deliver

	# Fill or start each worker facility from the current unmet request graph.
	for facility_id: String in ["FAC_ENHANCE_ANVIL", "FAC_WEAPON_BENCH", "FAC_SYNTH_BENCH"]:
		if not state.get("facilities", {}).has(facility_id):
			continue
		var recipe := _choose_recipe_for_facility(
			state,
			catalog,
			desired_requests,
			facility_id
		)
		if recipe.is_empty():
			continue
		var facility: Dictionary = state["facilities"][facility_id]
		if _inputs_exact(facility.get("inputs", []), recipe.get("inputs", [])):
			var start := SimContractScript.command(
				tick,
				sequence,
				SimContractScript.COMMAND_START,
				{"facility_id": facility_id}
			)
			if _is_accepted(state, start, round_definition, catalog):
				return start
		var missing_input := _first_missing_recipe_input(
			facility.get("inputs", []),
			recipe.get("inputs", [])
		)
		if not missing_input.is_empty():
			for source: Dictionary in _sources_for_item(
				state,
				round_definition,
				str(missing_input.get("item_id", "")),
				int(missing_input.get("enhancement_level", 0))
			):
				var move := SimContractScript.command(
					tick,
					sequence,
					SimContractScript.COMMAND_MOVE,
					{
						"source": source,
						"destination": {
							"kind": "facility_input",
							"facility_id": facility_id,
						},
					}
				)
				if _is_accepted(state, move, round_definition, catalog):
					return move

	# The furnace is the shared bottleneck. Pick ore or wood according to the first
	# outstanding request whose component chain is not already represented in state.
	if state.get("facilities", {}).has("FAC_FURNACE"):
		var furnace: Dictionary = state["facilities"]["FAC_FURNACE"]
		if str(furnace.get("status", "")) == "empty":
			var furnace_item := _needed_furnace_supply(state, catalog, desired_requests)
			if not furnace_item.is_empty() and furnace_item in round_definition.get("supply_items", []):
				var furnace_move := SimContractScript.command(
					tick,
					sequence,
					SimContractScript.COMMAND_MOVE,
					{
						"source": {"kind": "supply", "item_id": furnace_item},
						"destination": {
							"kind": "facility_input",
							"facility_id": "FAC_FURNACE",
						},
					}
				)
				if _is_accepted(state, furnace_move, round_definition, catalog):
					return furnace_move

	# Preserve every completed output when it cannot be consumed immediately. This
	# also guarantees that a hot furnace output is removed well inside its grace.
	for facility_id_value: Variant in _sorted_facility_ids(state):
		var facility_id := str(facility_id_value)
		var facility: Dictionary = state["facilities"][facility_id]
		if str(facility.get("status", "")) != "output":
			continue
		var store := SimContractScript.command(
			tick,
			sequence,
			SimContractScript.COMMAND_STORE,
			{"facility_id": facility_id}
		)
		if _is_accepted(state, store, round_definition, catalog):
			return store
	return {}


static func _choose_recipe_for_facility(
	state: Dictionary,
	catalog: Dictionary,
	desired_requests: Array,
	facility_id: String
) -> Dictionary:
	var facility: Dictionary = state["facilities"][facility_id]
	if str(facility.get("status", "")) in ["working", "output"]:
		return {}
	var current_inputs: Array = facility.get("inputs", [])
	var candidates: Array = []
	match facility_id:
		"FAC_WEAPON_BENCH":
			for request_value: Variant in _missing_equipment_requests(state, catalog, desired_requests):
				var request: Dictionary = request_value
				var recipe := _recipe_producing(
					catalog,
					facility_id,
					str(request.get("item_id", "")),
					0
				)
				if not recipe.is_empty() and _inputs_fit(current_inputs, recipe.get("inputs", [])):
					candidates.append(recipe)
		"FAC_ENHANCE_ANVIL":
			for request_value: Variant in _missing_enhanced_requests(state, catalog, desired_requests):
				var request: Dictionary = request_value
				var recipe := _recipe_producing(
					catalog,
					facility_id,
					str(request.get("item_id", "")),
					1
				)
				if not recipe.is_empty() and _inputs_fit(current_inputs, recipe.get("inputs", [])):
					candidates.append(recipe)
		"FAC_SYNTH_BENCH":
			if _enhancement_stones_needed(state, catalog, desired_requests) > 0:
				var recipe := _recipe_producing(
					catalog,
					facility_id,
					"MAT_ENHANCEMENT_STONE",
					0
				)
				if not recipe.is_empty() and _inputs_fit(current_inputs, recipe.get("inputs", [])):
					candidates.append(recipe)
	if not candidates.is_empty():
		return candidates[0]
	return {}


static func _needed_furnace_supply(
	state: Dictionary,
	catalog: Dictionary,
	desired_requests: Array
) -> String:
	var missing_equipment := _missing_equipment_requests(state, catalog, desired_requests)
	var ingots_required := 0
	for request_value: Variant in missing_equipment:
		var item_id := str(request_value.get("item_id", ""))
		ingots_required += 2 if item_id == "EQ_IRON_SWORD" else 1
	var ingots_present := _count_item_everywhere(state, catalog, "MAT_IRON_INGOT", 0)

	var stones_needed := _enhancement_stones_needed(state, catalog, desired_requests)
	var charcoal_present := _count_item_everywhere(state, catalog, "MAT_CHARCOAL", 0)
	var charcoal_required := maxi(0, stones_needed - charcoal_present)
	if ingots_required <= ingots_present and charcoal_required <= 0:
		return ""

	# Respect request order: base equipment for the first missing request precedes
	# enhancement components unless the first missing enhanced request is earlier.
	var first_equipment_index := _first_request_index(desired_requests, missing_equipment)
	var missing_enhanced := _missing_enhanced_requests(state, catalog, desired_requests)
	var first_enhanced_index := _first_request_index(desired_requests, missing_enhanced)
	if charcoal_required > 0 and (
		ingots_required <= ingots_present
		or first_enhanced_index >= 0
		and (first_equipment_index < 0 or first_enhanced_index < first_equipment_index)
	):
		return "MAT_WOOD"
	if ingots_required > ingots_present:
		return "MAT_IRON_ORE"
	return "MAT_WOOD" if charcoal_required > 0 else ""


static func _missing_equipment_requests(
	state: Dictionary,
	catalog: Dictionary,
	desired_requests: Array
) -> Array:
	var available: Dictionary = {}
	for item_id: String in ["EQ_DAGGER", "EQ_IRON_SWORD"]:
		available[item_id] = (
			_count_item_everywhere(state, catalog, item_id, 0)
			+ _count_item_everywhere(state, catalog, item_id, 1)
		)
	var missing: Array = []
	for request_value: Variant in desired_requests:
		var request: Dictionary = request_value
		var item_id := str(request.get("item_id", ""))
		if int(available.get(item_id, 0)) > 0:
			available[item_id] = int(available[item_id]) - 1
		else:
			missing.append(request)
	return missing


static func _missing_enhanced_requests(
	state: Dictionary,
	catalog: Dictionary,
	desired_requests: Array
) -> Array:
	var available: Dictionary = {
		"EQ_DAGGER": _count_item_everywhere(state, catalog, "EQ_DAGGER", 1),
		"EQ_IRON_SWORD": _count_item_everywhere(state, catalog, "EQ_IRON_SWORD", 1),
	}
	var missing: Array = []
	for request_value: Variant in desired_requests:
		var request: Dictionary = request_value
		if int(request.get("required_level", 0)) < 1:
			continue
		var item_id := str(request.get("item_id", ""))
		if int(available.get(item_id, 0)) > 0:
			available[item_id] = int(available[item_id]) - 1
		else:
			missing.append(request)
	return missing


static func _enhancement_stones_needed(
	state: Dictionary,
	catalog: Dictionary,
	desired_requests: Array
) -> int:
	var enhancements_needed := _missing_enhanced_requests(state, catalog, desired_requests).size()
	var stones_present := _count_item_everywhere(
		state,
		catalog,
		"MAT_ENHANCEMENT_STONE",
		0
	)
	return maxi(0, enhancements_needed - stones_present)


static func _desired_requests(
	state: Dictionary,
	round_definition: Dictionary,
	catalog: Dictionary,
	target_event_ids: Array[String]
) -> Array:
	var live_requests: Dictionary = {}
	for request_value: Variant in state.get("active_requests", []):
		live_requests[str(request_value.get("event_id", ""))] = request_value
	for request_value: Variant in state.get("waiting_requests", []):
		live_requests[str(request_value.get("event_id", ""))] = request_value

	var desired: Array = []
	var next_request_index := int(state.get("next_request_index", 0))
	var events: Array = round_definition.get("events", [])
	for event_index: int in range(events.size()):
		var event: Dictionary = events[event_index]
		var event_id := str(event.get("event_id", ""))
		if event_id not in target_event_ids:
			continue
		if live_requests.has(event_id):
			desired.append(live_requests[event_id])
		elif event_index >= next_request_index:
			var request_definition := _find_by_id(
				catalog.get("requests", []),
				str(event.get("request_id", ""))
			)
			if not request_definition.is_empty():
				var future_request: Dictionary = request_definition.duplicate(true)
				future_request["event_id"] = event_id
				future_request["release_tick"] = int(event.get("release_tick", 0))
				desired.append(future_request)
	return desired


static func _select_target_events(
	round_definition: Dictionary,
	catalog: Dictionary,
	goal_score: int
) -> Array[String]:
	var selected: Array[String] = []
	var potential_score := 0
	var cutlines: Array = round_definition.get("cutlines", [])
	var include_all_events := cutlines.size() == 3 and goal_score >= int(cutlines[2])
	for event_value: Variant in round_definition.get("events", []):
		var event: Dictionary = event_value
		var request := _find_by_id(
			catalog.get("requests", []),
			str(event.get("request_id", ""))
		)
		selected.append(str(event.get("event_id", "")))
		potential_score += int(request.get("score", 0))
		if not include_all_events and potential_score >= goal_score:
			break
	return selected


static func _equipment_sources(state: Dictionary, catalog: Dictionary) -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	for facility_id_value: Variant in _sorted_facility_ids(state):
		var facility_id := str(facility_id_value)
		var facility: Dictionary = state["facilities"][facility_id]
		if str(facility.get("status", "")) != "output" or facility.get("output") == null:
			continue
		if _is_equipment(catalog, facility["output"]):
			sources.append({"kind": "facility_output", "facility_id": facility_id})
	for slot: int in range(state.get("inventory", []).size()):
		var item: Variant = state["inventory"][slot]
		if item is Dictionary and _is_equipment(catalog, item):
			sources.append({"kind": "inventory", "slot": slot})
	return sources


static func _sources_for_item(
	state: Dictionary,
	round_definition: Dictionary,
	item_id: String,
	enhancement_level: int
) -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	for slot: int in range(state.get("inventory", []).size()):
		var item: Variant = state["inventory"][slot]
		if item is Dictionary and _item_matches(item, item_id, enhancement_level):
			sources.append({"kind": "inventory", "slot": slot})
	for facility_id_value: Variant in _sorted_facility_ids(state):
		var facility_id := str(facility_id_value)
		var facility: Dictionary = state["facilities"][facility_id]
		if (
			str(facility.get("status", "")) == "output"
			and facility.get("output") is Dictionary
			and _item_matches(facility["output"], item_id, enhancement_level)
		):
			sources.append({"kind": "facility_output", "facility_id": facility_id})
	if item_id in round_definition.get("supply_items", []) and enhancement_level == 0:
		sources.append({"kind": "supply", "item_id": item_id})
	return sources


static func _count_item_everywhere(
	state: Dictionary,
	catalog: Dictionary,
	item_id: String,
	enhancement_level: int
) -> int:
	var count := 0
	for item_value: Variant in state.get("inventory", []):
		if item_value is Dictionary and _item_matches(item_value, item_id, enhancement_level):
			count += 1
	for facility_id_value: Variant in _sorted_facility_ids(state):
		var facility: Dictionary = state["facilities"][facility_id_value]
		for input_value: Variant in facility.get("inputs", []):
			if input_value is Dictionary and _item_matches(input_value, item_id, enhancement_level):
				count += 1
		if facility.get("output") is Dictionary and _item_matches(
			facility["output"], item_id, enhancement_level
		):
			count += 1
		if str(facility.get("status", "")) == "working":
			var recipe := _find_by_id(
				catalog.get("recipes", []),
				str(facility.get("recipe_id", ""))
			)
			var output: Dictionary = recipe.get("output", {})
			if _item_matches(output, item_id, enhancement_level):
				count += int(output.get("count", 1))
	return count


static func _first_missing_recipe_input(actual_items: Array, required_entries: Array) -> Dictionary:
	var actual_counts := _item_counts(actual_items, false)
	for entry_value: Variant in required_entries:
		var entry: Dictionary = entry_value
		var key := _item_key(
			str(entry.get("item_id", "")),
			int(entry.get("enhancement_level", 0))
		)
		if int(actual_counts.get(key, 0)) < int(entry.get("count", 0)):
			return entry
	return {}


static func _inputs_fit(actual_items: Array, required_entries: Array) -> bool:
	var actual_counts := _item_counts(actual_items, false)
	var required_counts := _item_counts(required_entries, true)
	for key: Variant in actual_counts:
		if not required_counts.has(key) or int(actual_counts[key]) > int(required_counts[key]):
			return false
	return true


static func _inputs_exact(actual_items: Array, required_entries: Array) -> bool:
	return _item_counts(actual_items, false) == _item_counts(required_entries, true)


static func _item_counts(entries: Array, entries_have_count: bool) -> Dictionary:
	var counts: Dictionary = {}
	for value: Variant in entries:
		if not value is Dictionary:
			continue
		var key := _item_key(
			str(value.get("item_id", "")),
			int(value.get("enhancement_level", 0))
		)
		counts[key] = int(counts.get(key, 0)) + (int(value.get("count", 0)) if entries_have_count else 1)
	return counts


static func _recipe_producing(
	catalog: Dictionary,
	facility_id: String,
	item_id: String,
	enhancement_level: int
) -> Dictionary:
	for recipe_value: Variant in catalog.get("recipes", []):
		var recipe: Dictionary = recipe_value
		var output: Dictionary = recipe.get("output", {})
		if (
			str(recipe.get("facility_id", "")) == facility_id
			and _item_matches(output, item_id, enhancement_level)
		):
			return recipe
	return {}


static func _is_accepted(
	state: Dictionary,
	command: Dictionary,
	round_definition: Dictionary,
	catalog: Dictionary
) -> bool:
	var preview := RoundSimulatorScript.preview_command(
		state,
		str(command.get("type", "")),
		command.get("payload", {}),
		round_definition,
		catalog
	)
	return bool(preview.get("accepted", false))


static func _test_twenty_json_resume_points(
	repository: DataRepository,
	plan: Dictionary,
	test: TestFramework
) -> void:
	var round_id := "R5"
	var round_definition := repository.get_round(round_id)
	var timeline: Dictionary = plan.get("timeline", {})
	var baseline_state: Dictionary = plan.get("state", {})
	var baseline_hash := RoundSimulatorScript.state_hash(baseline_state)
	var deadline := int(round_definition.get("deadline_ticks", 0))
	var checkpoint_hashes: Dictionary = {}
	for checkpoint_index: int in range(SNAPSHOT_CHECKPOINT_COUNT):
		var checkpoint_tick := int(
			(checkpoint_index + 1) * deadline / float(SNAPSHOT_CHECKPOINT_COUNT + 1)
		)
		var checkpoint_state := _replay_until_tick(
			repository,
			round_id,
			timeline,
			checkpoint_tick
		)
		var encoded := JSON.stringify(checkpoint_state)
		var decoded: Variant = JSON.parse_string(encoded)
		var checkpoint_hash := RoundSimulatorScript.state_hash(checkpoint_state)
		test.assert_false(
			checkpoint_hashes.has(checkpoint_hash),
			"R5 checkpoint %d is a distinct simulation state" % (checkpoint_index + 1)
		)
		checkpoint_hashes[checkpoint_hash] = true
		test.assert_true(
			decoded is Dictionary,
			"R5 checkpoint %d parses back to a Dictionary" % (checkpoint_index + 1)
		)
		if not decoded is Dictionary:
			continue
		test.assert_equal(
			RoundSimulatorScript.state_hash(decoded),
			checkpoint_hash,
			"R5 checkpoint %d preserves its state hash through JSON" % (checkpoint_index + 1)
		)
		var resumed := _continue_timeline(
			decoded,
			round_definition,
			repository.catalog,
			timeline,
			test,
			"R5 JSON checkpoint %d" % (checkpoint_index + 1)
		)
		test.assert_equal(
			RoundSimulatorScript.state_hash(resumed),
			baseline_hash,
			"R5 checkpoint %d continuation matches uninterrupted final hash" % (checkpoint_index + 1)
		)


static func _replay_timeline(
	repository: DataRepository,
	round_id: String,
	timeline: Dictionary,
	test: TestFramework,
	label: String,
	assert_commands: bool
) -> Dictionary:
	var round_definition := repository.get_round(round_id)
	var state := RoundSimulatorScript.create_state(round_definition, repository.catalog)
	return _continue_timeline(
		state,
		round_definition,
		repository.catalog,
		timeline,
		test,
		label,
		assert_commands
	)


static func _continue_timeline(
	state: Dictionary,
	round_definition: Dictionary,
	catalog: Dictionary,
	timeline: Dictionary,
	test: TestFramework,
	label: String,
	assert_commands: bool = true
) -> Dictionary:
	var current: Dictionary = state.duplicate(true)
	while str(current.get("status", "")) == "running":
		var tick := int(current.get("tick", 0))
		var result := RoundSimulatorScript.step(
			current,
			timeline.get(tick, []),
			round_definition,
			catalog
		)
		if assert_commands:
			for command_result_value: Variant in result.get("command_results", []):
				var command_result: Dictionary = command_result_value
				test.assert_true(
					bool(command_result.get("accepted", false)),
					"%s command at tick %d is accepted: %s" % [
						label,
						tick,
						str(command_result.get("reason", "missing reason")),
					]
				)
		current = result.get("state", {})
		if current.is_empty():
			test.fail("%s replay returned no state" % label)
			return {}
	return current


static func _replay_until_tick(
	repository: DataRepository,
	round_id: String,
	timeline: Dictionary,
	target_tick: int
) -> Dictionary:
	var round_definition := repository.get_round(round_id)
	var state := RoundSimulatorScript.create_state(round_definition, repository.catalog)
	while str(state.get("status", "")) == "running" and int(state.get("tick", 0)) < target_tick:
		var result := RoundSimulatorScript.step(
			state,
			timeline.get(int(state.get("tick", 0)), []),
			round_definition,
			repository.catalog
		)
		state = result.get("state", {})
	return state


static func _commands_by_tick(commands: Array) -> Dictionary:
	var timeline: Dictionary = {}
	for command_value: Variant in commands:
		var command: Dictionary = command_value
		var tick := int(command.get("tick", -1))
		if not timeline.has(tick):
			timeline[tick] = []
		timeline[tick].append(command.duplicate(true))
	return timeline


static func _load_json_fixture(path: String, test: TestFramework) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		test.fail("cannot open %s" % path)
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		test.fail("cannot parse %s" % path)
		return {}
	return parser.data


static func _first_request_index(all_requests: Array, subset: Array) -> int:
	var subset_ids: Dictionary = {}
	for request_value: Variant in subset:
		subset_ids[str(request_value.get("event_id", ""))] = true
	for index: int in range(all_requests.size()):
		if subset_ids.has(str(all_requests[index].get("event_id", ""))):
			return index
	return -1


static func _sorted_facility_ids(state: Dictionary) -> Array:
	var facility_ids: Array = state.get("facilities", {}).keys()
	facility_ids.sort()
	return facility_ids


static func _is_equipment(catalog: Dictionary, item: Dictionary) -> bool:
	var item_definition := _find_by_id(catalog.get("items", []), str(item.get("item_id", "")))
	return str(item_definition.get("category", "")) == "equipment"


static func _item_matches(item: Dictionary, item_id: String, enhancement_level: int) -> bool:
	return (
		str(item.get("item_id", "")) == item_id
		and int(item.get("enhancement_level", 0)) == enhancement_level
	)


static func _item_key(item_id: String, enhancement_level: int) -> String:
	return "%s@%d" % [item_id, enhancement_level]


static func _find_by_id(entries: Array, id: String) -> Dictionary:
	for entry_value: Variant in entries:
		if entry_value is Dictionary and str(entry_value.get("id", "")) == id:
			return entry_value
	return {}
