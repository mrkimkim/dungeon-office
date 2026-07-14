extends RefCounted

const DataRepositoryScript = preload("res://src/data/data_repository.gd")
const RoundSimulatorScript = preload("res://src/sim/round_simulator.gd")
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
	_test_tick_boundary(repository, test)

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
