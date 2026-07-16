extends RefCounted

const DataRepositoryScript = preload("res://src/data/data_repository.gd")
const RoundSimulatorScript = preload("res://src/sim/round_simulator.gd")
const RoundReadModelScript = preload("res://src/sim/round_read_model.gd")
const SimContractScript = preload("res://src/sim/sim_contract.gd")
const SettlementServiceScript = preload("res://src/app/settlement_service.gd")

static func run(test: TestFramework) -> void:
	var repository := DataRepositoryScript.new()
	var load_result := repository.load_all()
	if not bool(load_result.get("ok", false)):
		test.fail("simulator tests require valid data")
		return
	var fixture := _load_fixture(test)
	if fixture.is_empty():
		return
	var first_run := _run_fixture(repository, fixture, test)
	var second_run := _run_fixture(repository, fixture, test)
	if first_run.is_empty() or second_run.is_empty():
		return
	test.assert_equal(
		RoundSimulatorScript.state_hash(first_run),
		RoundSimulatorScript.state_hash(second_run),
		"same fixture must produce the same final state hash"
	)
	var expected: Dictionary = fixture.get("expected", {})
	test.assert_equal(int(first_run.get("score", -1)), int(expected.get("score", -2)), "R1 fixture score")
	test.assert_equal(str(first_run.get("status", "")), str(expected.get("status", "")), "R1 fixture status")
	test.assert_equal(first_run.get("deliveries", []).size(), int(expected.get("deliveries", -1)), "R1 delivery count")
	var settlement := SettlementServiceScript.calculate(repository.get_round("R1"), first_run, "fixture:r1")
	test.assert_equal(int(settlement.get("stars", 0)), int(expected.get("stars", -1)), "R1 fixture stars")

	_test_rejection_contract(repository, test)
	_test_specific_inventory_destination(repository, test)
	_test_same_facility_input_drop_rejected(repository, test)
	_test_tick_boundary(repository, test)
	_test_sequence_gap(repository, test)
	_test_pause_resume_control_ticks(repository, test)
	_test_waiting_request_activation(repository, test)
	_test_simultaneous_withdrawal_order(repository, test)
	_test_facility_status_after_input_recovery(repository, test)
	_test_output_lifetimes(repository, test)
	_test_threshold_events(repository, test)
	_test_round_read_model(repository, test)

static func _run_fixture(repository: DataRepository, fixture: Dictionary, test: TestFramework) -> Dictionary:
	var round_definition := repository.get_round(str(fixture.get("round_id", "")))
	var state := RoundSimulatorScript.create_state(round_definition, repository.catalog)
	var commands_by_tick: Dictionary = {}
	for command_value: Variant in fixture.get("commands", []):
		var tick := int(command_value.get("tick", -1))
		if not commands_by_tick.has(tick):
			commands_by_tick[tick] = []
		commands_by_tick[tick].append(command_value)
	while str(state.get("status", "")) == "running":
		var step_result := RoundSimulatorScript.step(
			state,
			commands_by_tick.get(int(state.get("tick", 0)), []),
			round_definition,
			repository.catalog
		)
		for command_result: Variant in step_result.get("command_results", []):
			test.assert_true(
				bool(command_result.get("accepted", false)),
				"fixture command %s/%s rejected: %s" % [
					command_result.get("tick", "?"),
					command_result.get("sequence", "?"),
					command_result.get("reason", "?"),
				]
			)
		state = step_result["state"]
	return state

static func _test_rejection_contract(repository: DataRepository, test: TestFramework) -> void:
	var round_definition := repository.get_round("R1")
	var state := RoundSimulatorScript.create_state(round_definition, repository.catalog)
	var command := SimContractScript.command(0, 1, SimContractScript.COMMAND_MOVE, {
		"source": {"kind": "supply", "item_id": "MAT_WOOD"},
		"destination": {"kind": "facility_input", "facility_id": "FAC_FURNACE"},
	})
	var result := RoundSimulatorScript.step(state, [command], round_definition, repository.catalog)
	var rejection: Dictionary = result["command_results"][0]
	test.assert_false(bool(rejection.get("accepted", true)), "invalid R1 supply item must be rejected")
	test.assert_equal(rejection.get("reason"), SimContractScript.REJECT_ITEM_NOT_FOUND, "rejection reason must be stable")
	test.assert_equal(result["state"]["inventory"], state["inventory"], "rejected move must not change inventory")
	test.assert_equal(result["state"]["facilities"], state["facilities"], "rejected move must not change facilities")
	test.assert_equal(int(result["state"]["score"]), 0, "rejected move must not change score")


static func _test_specific_inventory_destination(
	repository: DataRepository,
	test: TestFramework
) -> void:
	var round_definition := repository.get_round("R1")
	var state := RoundSimulatorScript.create_state(round_definition, repository.catalog)
	var place_in_fourth := SimContractScript.command(0, 1, SimContractScript.COMMAND_MOVE, {
		"source": {"kind": "supply", "item_id": "MAT_IRON_ORE"},
		"destination": {"kind": "inventory", "slot": 3},
	})
	var placed := RoundSimulatorScript.step(
		state,
		[place_in_fourth],
		round_definition,
		repository.catalog
	)
	test.assert_true(
		bool(placed["command_results"][0].get("accepted", false)),
		"a drop can target a specific empty inventory slot"
	)
	test.assert_equal(
		str(placed["state"]["inventory"][3].get("item_id", "")),
		"MAT_IRON_ORE",
		"the simulator preserves the inventory slot chosen by the drop"
	)
	for slot: int in range(3):
		test.assert_true(
			placed["state"]["inventory"][slot] == null,
			"placing in slot four must not silently fill an earlier slot"
		)

	state = placed["state"]
	var occupied := SimContractScript.command(1, 2, SimContractScript.COMMAND_MOVE, {
		"source": {"kind": "supply", "item_id": "MAT_IRON_ORE"},
		"destination": {"kind": "inventory", "slot": 3},
	})
	var rejected := RoundSimulatorScript.step(
		state,
		[occupied],
		round_definition,
		repository.catalog
	)
	test.assert_false(
		bool(rejected["command_results"][0].get("accepted", true)),
		"dropping on an occupied inventory slot is rejected"
	)
	test.assert_equal(
		str(rejected["command_results"][0].get("reason", "")),
		SimContractScript.REJECT_INVENTORY_FULL,
		"occupied-slot rejection uses the stable inventory-full reason"
	)


static func _test_same_facility_input_drop_rejected(
	repository: DataRepository,
	test: TestFramework
) -> void:
	var round_definition := repository.get_round("R2")
	var state := RoundSimulatorScript.create_state(round_definition, repository.catalog)
	state["facilities"]["FAC_WEAPON_BENCH"]["inputs"] = [
		{"item_id": "MAT_IRON_INGOT", "enhancement_level": 0},
	]
	state["facilities"]["FAC_WEAPON_BENCH"]["status"] = "input"
	var command := SimContractScript.command(0, 1, SimContractScript.COMMAND_MOVE, {
		"source": {
			"kind": "facility_input",
			"facility_id": "FAC_WEAPON_BENCH",
			"slot": 0,
		},
		"destination": {
			"kind": "facility_input",
			"facility_id": "FAC_WEAPON_BENCH",
		},
	})
	var result := RoundSimulatorScript.step(
		state,
		[command],
		round_definition,
		repository.catalog
	)
	test.assert_false(
		bool(result["command_results"][0].get("accepted", true)),
		"an input cannot be dropped back onto the same facility"
	)
	test.assert_equal(
		str(result["command_results"][0].get("reason", "")),
		SimContractScript.REJECT_INVALID_DESTINATION,
		"same-facility drops use the stable invalid-destination reason"
	)
	test.assert_equal(
		result["state"]["facilities"]["FAC_WEAPON_BENCH"]["inputs"],
		state["facilities"]["FAC_WEAPON_BENCH"]["inputs"],
		"a rejected same-facility drop preserves every input"
	)

static func _test_tick_boundary(repository: DataRepository, test: TestFramework) -> void:
	var round_definition := repository.get_round("R1")
	var state := RoundSimulatorScript.create_state(round_definition, repository.catalog)
	test.assert_equal(state["active_requests"].size(), 1, "release_tick 0 request must be active in initial state")
	var command := SimContractScript.command(0, 1, SimContractScript.COMMAND_MOVE, {
		"source": {"kind": "supply", "item_id": "MAT_IRON_ORE"},
		"destination": {"kind": "facility_input", "facility_id": "FAC_FURNACE"},
	})
	var result := RoundSimulatorScript.step(state, [command], round_definition, repository.catalog)
	test.assert_equal(int(result["state"]["tick"]), 1, "accepted work-start command advances one simulation tick")
	test.assert_equal(
		int(result["state"]["facilities"]["FAC_FURNACE"]["remaining_ticks"]),
		159,
		"work timer decrements on its start tick by contract"
	)

static func _test_sequence_gap(repository: DataRepository, test: TestFramework) -> void:
	var round_definition := repository.get_round("R1")
	var state := RoundSimulatorScript.create_state(round_definition, repository.catalog)
	var gap_command := SimContractScript.command(0, 2, SimContractScript.COMMAND_MOVE, {
		"source": {"kind": "supply", "item_id": "MAT_IRON_ORE"},
		"destination": {"kind": "facility_input", "facility_id": "FAC_FURNACE"},
	})
	var result := RoundSimulatorScript.step(state, [gap_command], round_definition, repository.catalog)
	var command_result: Dictionary = result["command_results"][0]
	test.assert_false(bool(command_result.get("accepted", true)), "sequence gap must be rejected")
	test.assert_equal(
		command_result.get("reason"),
		SimContractScript.REJECT_SEQUENCE_GAP,
		"sequence gap has a stable rejection reason"
	)
	test.assert_equal(
		int(result["state"].get("next_command_sequence", 0)),
		1,
		"sequence gap cannot consume the expected sequence"
	)
	test.assert_equal(
		result["state"]["facilities"]["FAC_FURNACE"].get("status"),
		"empty",
		"sequence gap cannot apply its gameplay command"
	)

static func _test_pause_resume_control_ticks(repository: DataRepository, test: TestFramework) -> void:
	var round_definition := repository.get_round("R1")
	var state := RoundSimulatorScript.create_state(round_definition, repository.catalog)
	var start_furnace := SimContractScript.command(0, 1, SimContractScript.COMMAND_MOVE, {
		"source": {"kind": "supply", "item_id": "MAT_IRON_ORE"},
		"destination": {"kind": "facility_input", "facility_id": "FAC_FURNACE"},
	})
	state = RoundSimulatorScript.step(
		state, [start_furnace], round_definition, repository.catalog
	)["state"]
	var frozen_tick := int(state["tick"])
	var frozen_work := int(state["facilities"]["FAC_FURNACE"]["remaining_ticks"])
	var frozen_patience := int(state["active_requests"][0]["remaining_patience_ticks"])

	var pause := SimContractScript.command(
		frozen_tick,
		int(state["next_command_sequence"]),
		SimContractScript.COMMAND_PAUSE
	)
	state = RoundSimulatorScript.step(state, [pause], round_definition, repository.catalog)["state"]
	test.assert_true(bool(state.get("paused", false)), "pause command changes pause state")
	test.assert_equal(int(state["tick"]), frozen_tick, "pause command does not advance the tick")
	test.assert_equal(
		int(state["facilities"]["FAC_FURNACE"]["remaining_ticks"]),
		frozen_work,
		"pause command does not advance work"
	)
	test.assert_equal(
		int(state["active_requests"][0]["remaining_patience_ticks"]),
		frozen_patience,
		"pause command does not advance request patience"
	)

	var resume := SimContractScript.command(
		frozen_tick,
		int(state["next_command_sequence"]),
		SimContractScript.COMMAND_RESUME
	)
	state = RoundSimulatorScript.step(state, [resume], round_definition, repository.catalog)["state"]
	test.assert_false(bool(state.get("paused", true)), "resume command changes pause state")
	test.assert_equal(int(state["tick"]), frozen_tick, "resume command does not advance the tick")
	test.assert_equal(
		int(state["facilities"]["FAC_FURNACE"]["remaining_ticks"]),
		frozen_work,
		"resume command does not advance work"
	)
	test.assert_equal(
		int(state["active_requests"][0]["remaining_patience_ticks"]),
		frozen_patience,
		"resume command does not advance request patience"
	)

	state = RoundSimulatorScript.step(state, [], round_definition, repository.catalog)["state"]
	test.assert_equal(int(state["tick"]), frozen_tick + 1, "first normal step after resume advances")
	test.assert_equal(
		int(state["facilities"]["FAC_FURNACE"]["remaining_ticks"]),
		frozen_work - 1,
		"work resumes on the first normal step"
	)

static func _test_waiting_request_activation(repository: DataRepository, test: TestFramework) -> void:
	var round_definition: Dictionary = repository.get_round("R1").duplicate(true)
	round_definition["events"] = [
		{"event_id": "WAIT-E1", "request_id": "REQ_DAGGER_STD", "release_tick": 0},
		{"event_id": "WAIT-E2", "request_id": "REQ_DAGGER_STD", "release_tick": 0},
	]
	var state := RoundSimulatorScript.create_state(round_definition, repository.catalog)
	state["inventory"][0] = {"item_id": "EQ_DAGGER", "enhancement_level": 0}
	var deliver := SimContractScript.command(0, 1, SimContractScript.COMMAND_DELIVER, {
		"source": {"kind": "inventory", "slot": 0},
	})
	state = RoundSimulatorScript.step(state, [deliver], round_definition, repository.catalog)["state"]
	test.assert_equal(state["active_requests"].size(), 1, "waiting request fills a delivered slot")
	test.assert_equal(
		state["active_requests"][0].get("event_id"),
		"WAIT-E2",
		"waiting requests activate in FIFO order"
	)
	test.assert_equal(
		int(state["active_requests"][0]["remaining_patience_ticks"]),
		900,
		"request activated after delivery keeps full patience for that step"
	)
	state = RoundSimulatorScript.step(state, [], round_definition, repository.catalog)["state"]
	test.assert_equal(
		int(state["active_requests"][0]["remaining_patience_ticks"]),
		899,
		"newly activated request starts spending patience on the next step"
	)

static func _test_simultaneous_withdrawal_order(
	repository: DataRepository,
	test: TestFramework
) -> void:
	var round_definition: Dictionary = repository.get_round("R2").duplicate(true)
	round_definition["events"] = [
		{"event_id": "WITHDRAW-E1", "request_id": "REQ_DAGGER_STD", "release_tick": 0},
		{"event_id": "WITHDRAW-E2", "request_id": "REQ_SWORD_STD", "release_tick": 0},
		{"event_id": "WITHDRAW-E3", "request_id": "REQ_DAGGER_STD", "release_tick": 0},
		{"event_id": "WITHDRAW-E4", "request_id": "REQ_SWORD_STD", "release_tick": 0},
	]
	var state := RoundSimulatorScript.create_state(round_definition, repository.catalog)
	for request_value: Variant in state["active_requests"]:
		request_value["remaining_patience_ticks"] = 1
	var result := RoundSimulatorScript.step(state, [], round_definition, repository.catalog)
	state = result["state"]
	var withdrawn_ids: Array[String] = []
	for event_value: Variant in result.get("events", []):
		if str(event_value.get("type", "")) == "request_withdrawn":
			withdrawn_ids.append(str(event_value.get("event_id", "")))
	test.assert_equal(
		withdrawn_ids,
		["WITHDRAW-E1", "WITHDRAW-E2"],
		"simultaneous withdrawals use stable activation order"
	)
	test.assert_equal(state["active_requests"].size(), 2, "all empty request slots are refilled")
	test.assert_equal(
		state["active_requests"][0].get("event_id"),
		"WITHDRAW-E3",
		"first waiting request fills first after all withdrawals"
	)
	test.assert_equal(
		state["active_requests"][1].get("event_id"),
		"WITHDRAW-E4",
		"second waiting request fills second after all withdrawals"
	)
	test.assert_equal(
		int(state["active_requests"][0]["remaining_patience_ticks"]),
		900,
		"refilled request does not lose patience in its activation step"
	)

static func _test_facility_status_after_input_recovery(
	repository: DataRepository,
	test: TestFramework
) -> void:
	var round_definition := repository.get_round("R2")
	var state := RoundSimulatorScript.create_state(round_definition, repository.catalog)
	state["facilities"]["FAC_WEAPON_BENCH"]["inputs"] = [
		{"item_id": "MAT_IRON_INGOT", "enhancement_level": 0},
		{"item_id": "MAT_IRON_INGOT", "enhancement_level": 0},
	]
	state["facilities"]["FAC_WEAPON_BENCH"]["status"] = "ready"
	var recover_input := SimContractScript.command(0, 1, SimContractScript.COMMAND_MOVE, {
		"source": {"kind": "facility_input", "facility_id": "FAC_WEAPON_BENCH", "slot": 0},
		"destination": {"kind": "inventory"},
	})
	state = RoundSimulatorScript.step(
		state, [recover_input], round_definition, repository.catalog
	)["state"]
	test.assert_equal(
		state["facilities"]["FAC_WEAPON_BENCH"].get("status"),
		"ready",
		"remaining exact dagger recipe is ready after recovering one sword input"
	)


static func _test_output_lifetimes(repository: DataRepository, test: TestFramework) -> void:
	var round_definition := repository.get_round("R1")
	var state := RoundSimulatorScript.create_state(round_definition, repository.catalog)
	var furnace: Dictionary = state["facilities"]["FAC_FURNACE"]
	furnace["status"] = "output"
	furnace["output"] = {"item_id": "MAT_IRON_INGOT", "enhancement_level": 0}
	furnace["overheat_remaining_ticks"] = 2
	var bench: Dictionary = state["facilities"]["FAC_WEAPON_BENCH"]
	bench["status"] = "output"
	bench["output"] = {"item_id": "EQ_DAGGER", "enhancement_level": 0}
	bench["overheat_remaining_ticks"] = 0

	var first := RoundSimulatorScript.step(state, [], round_definition, repository.catalog)
	state = first["state"]
	test.assert_equal(
		str(state["facilities"]["FAC_FURNACE"].get("status", "")),
		"output",
		"a hot furnace output remains available on its penultimate grace tick"
	)
	test.assert_equal(
		int(state["facilities"]["FAC_FURNACE"].get("overheat_remaining_ticks", -1)),
		1,
		"the furnace grace countdown reaches one before any loss"
	)
	test.assert_equal(
		_count_events(first.get("events", []), "overheat_loss"),
		0,
		"the furnace output cannot disappear before grace reaches zero"
	)

	var second := RoundSimulatorScript.step(state, [], round_definition, repository.catalog)
	state = second["state"]
	test.assert_equal(
		str(state["facilities"]["FAC_FURNACE"].get("status", "")),
		"empty",
		"only the furnace output clears when its explicit grace reaches zero"
	)
	test.assert_true(
		state["facilities"]["FAC_FURNACE"].get("output") == null,
		"overheat loss removes the expired furnace output from authoritative state"
	)
	test.assert_equal(
		_count_events(second.get("events", []), "overheat_loss"),
		1,
		"overheat expiration emits one visible loss event"
	)
	test.assert_equal(
		int(state.get("overheat_loss_count", 0)),
		1,
		"overheat expiration records one loss"
	)
	test.assert_equal(
		str(state["facilities"]["FAC_WEAPON_BENCH"]["output"].get("item_id", "")),
		"EQ_DAGGER",
		"a non-hot crafted item survives the furnace expiration tick"
	)

	for _extra_tick: int in range(200):
		state = RoundSimulatorScript.step(state, [], round_definition, repository.catalog)["state"]
	test.assert_equal(
		str(state["facilities"]["FAC_WEAPON_BENCH"]["output"].get("item_id", "")),
		"EQ_DAGGER",
		"crafted equipment never expires merely because time passes"
	)
	for request_value: Variant in state.get("active_requests", []):
		request_value["remaining_patience_ticks"] = 1
	var withdrawal_step := RoundSimulatorScript.step(
		state,
		[],
		round_definition,
		repository.catalog
	)
	state = withdrawal_step["state"]
	test.assert_true(
		_count_events(withdrawal_step.get("events", []), "request_withdrawn") > 0,
		"the lifetime fixture crosses an actual request-withdrawal boundary"
	)
	test.assert_equal(
		str(state["facilities"]["FAC_WEAPON_BENCH"]["output"].get("item_id", "")),
		"EQ_DAGGER",
		"request withdrawal cannot delete already crafted equipment"
	)
	state["deadline_ticks"] = int(state.get("tick", 0)) + 1
	state = RoundSimulatorScript.step(state, [], round_definition, repository.catalog)["state"]
	test.assert_equal(str(state.get("status", "")), "ended", "the fixture reaches the round deadline")
	test.assert_equal(
		str(state["facilities"]["FAC_WEAPON_BENCH"]["output"].get("item_id", "")),
		"EQ_DAGGER",
		"the deadline transition does not masquerade as an equipment-expiry rule"
	)

static func _test_threshold_events(repository: DataRepository, test: TestFramework) -> void:
	var round_definition := repository.get_round("R1")
	var state := RoundSimulatorScript.create_state(round_definition, repository.catalog)
	state["tick"] = 1199
	state["next_request_index"] = round_definition.get("events", []).size()
	state["active_requests"][0]["remaining_patience_ticks"] = 201
	state["active_requests"][0].erase("urgent_emitted")
	var furnace: Dictionary = state["facilities"]["FAC_FURNACE"]
	furnace["status"] = "output"
	furnace["output"] = {"item_id": "MAT_IRON_INGOT", "enhancement_level": 0}
	furnace["overheat_remaining_ticks"] = 61
	furnace.erase("overheat_danger_emitted")
	state.erase("threshold_flags")

	var first := RoundSimulatorScript.step(state, [], round_definition, repository.catalog)
	state = first["state"]
	test.assert_equal(
		_count_events(first.get("events", []), "overheat_danger_entered"),
		1,
		"overheat danger threshold emits once on entry"
	)
	test.assert_equal(
		_count_events(first.get("events", []), "request_urgent_entered"),
		1,
		"request urgency threshold emits once on entry"
	)
	test.assert_equal(
		_count_events(first.get("events", []), "deadline_warning_entered"),
		1,
		"deadline warning threshold emits once on entry"
	)
	var second := RoundSimulatorScript.step(state, [], round_definition, repository.catalog)
	state = second["state"]
	test.assert_equal(
		_count_events(second.get("events", []), "overheat_danger_entered"),
		0,
		"overheat danger event does not repeat inside threshold"
	)
	test.assert_equal(
		_count_events(second.get("events", []), "request_urgent_entered"),
		0,
		"request urgency event does not repeat inside threshold"
	)
	test.assert_equal(
		_count_events(second.get("events", []), "deadline_warning_entered"),
		0,
		"deadline warning event does not repeat inside threshold"
	)
	state["tick"] = 1599
	state["threshold_flags"]["deadline_warning_emitted"] = true
	state["threshold_flags"]["deadline_countdown_emitted"] = false
	var countdown := RoundSimulatorScript.step(state, [], round_definition, repository.catalog)
	test.assert_equal(
		_count_events(countdown.get("events", []), "deadline_countdown_entered"),
		1,
		"deadline countdown threshold emits once on entry"
	)

static func _test_round_read_model(repository: DataRepository, test: TestFramework) -> void:
	var round_definition := repository.get_round("R1")
	var state := RoundSimulatorScript.create_state(round_definition, repository.catalog)
	var original_hash := RoundSimulatorScript.state_hash(state)
	var read_model := RoundReadModelScript.build(
		state,
		round_definition,
		repository.catalog,
		{"kind": "supply", "item_id": "MAT_IRON_ORE"}
	)
	test.assert_equal(
		RoundSimulatorScript.state_hash(state),
		original_hash,
		"building the read model cannot mutate simulation state"
	)
	test.assert_equal(int(read_model.get("idle_worker_count", -1)), 2, "read model exposes idle workers")
	test.assert_equal(
		read_model.get("active_requests", [])[0].get("item_display_name"),
		"단검",
		"request read model exposes Korean item display name"
	)
	var destination_names: Array[String] = []
	for destination_value: Variant in read_model["selected_actions"]["move_destinations"]:
		destination_names.append(str(destination_value.get("display_name", "")))
	test.assert_true("인벤토리" in destination_names, "supply selection exposes legal inventory destination")
	test.assert_true("용광로" in destination_names, "supply selection exposes legal furnace destination")
	test.assert_false(
		bool(read_model["selected_actions"].get("can_deliver", true)),
		"raw material selection cannot be delivered"
	)
	test.assert_true(bool(read_model["commands"].get("can_pause", false)), "running read model can pause")
	test.assert_false(bool(read_model["commands"].get("can_resume", true)), "running read model cannot resume")

	state["facilities"]["FAC_WEAPON_BENCH"]["inputs"] = [
		{"item_id": "MAT_IRON_INGOT", "enhancement_level": 0},
	]
	state["facilities"]["FAC_WEAPON_BENCH"]["status"] = "ready"
	read_model = RoundReadModelScript.build(state, round_definition, repository.catalog)
	test.assert_true(
		"FAC_WEAPON_BENCH" in read_model["commands"]["startable_facility_ids"],
		"read model obtains startable facilities from authoritative command validation"
	)

static func _count_events(events: Array, event_type: String) -> int:
	var count := 0
	for event_value: Variant in events:
		if event_value is Dictionary and str(event_value.get("type", "")) == event_type:
			count += 1
	return count

static func _load_fixture(test: TestFramework) -> Dictionary:
	var path := "res://tests/fixtures/r1_commands.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		test.fail("cannot open %s" % path)
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		test.fail("cannot parse %s" % path)
		return {}
	return parser.data
