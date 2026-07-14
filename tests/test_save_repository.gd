extends RefCounted

const DataRepositoryScript = preload("res://src/data/data_repository.gd")
const ProfileScript = preload("res://src/app/profile_v1.gd")
const SaveRepositoryScript = preload("res://src/app/save_repository.gd")
const RoundSimulatorScript = preload("res://src/sim/round_simulator.gd")
const SettlementServiceScript = preload("res://src/app/settlement_service.gd")

const TEST_ROOT: String = "user://tests/save_repository"

static func run(test: TestFramework) -> void:
	_cleanup()
	var data_repository := DataRepositoryScript.new()
	var data_result := data_repository.load_all()
	if not bool(data_result.get("ok", false)):
		test.fail("save tests require valid data")
		return
	var round_ids := data_repository.get_round_ids()
	var save_repository := SaveRepositoryScript.new(TEST_ROOT)
	var first_profile := ProfileScript.create(round_ids)
	test.assert_true(bool(save_repository.save_profile(first_profile).get("ok", false)), "first profile save")
	var second_profile: Dictionary = first_profile.duplicate(true)
	second_profile["gold"] = 99
	test.assert_true(bool(save_repository.save_profile(second_profile).get("ok", false)), "second profile save creates backup")

	var main_file := FileAccess.open(TEST_ROOT + "/profile.json", FileAccess.WRITE)
	main_file.store_string("{corrupt")
	main_file.close()
	var recovered := save_repository.load_profile(round_ids)
	test.assert_equal(recovered.get("status"), "recovered", "corrupt primary profile must use valid backup")
	test.assert_equal(int(recovered.get("value", {}).get("gold", -1)), 0, "backup must contain previous valid profile")

	var state := RoundSimulatorScript.create_state(data_repository.get_round("R1"), data_repository.catalog)
	var snapshot_save := save_repository.save_snapshot("run:test", state)
	test.assert_true(bool(snapshot_save.get("ok", false)), "snapshot must save atomically")
	var snapshot_load := save_repository.load_snapshot(1, 1)
	test.assert_equal(snapshot_load.get("status"), "ok", "snapshot must round-trip")
	test.assert_equal(snapshot_load.get("value", {}).get("run_id"), "run:test", "snapshot run ID must round-trip")

	_test_settlement_idempotency(data_repository, round_ids, test)
	_cleanup()
	_test_crash_after_profile_commit(data_repository, round_ids, test)
	_cleanup()

static func _test_settlement_idempotency(
	data_repository: DataRepository,
	round_ids: Array[String],
	test: TestFramework
) -> void:
	var profile := ProfileScript.create(round_ids)
	var state := RoundSimulatorScript.create_state(data_repository.get_round("R1"), data_repository.catalog)
	state["score"] = 10
	state["status"] = "ended"
	var settlement := SettlementServiceScript.calculate(data_repository.get_round("R1"), state, "run:idempotent")
	var first_apply := ProfileScript.apply_settlement(profile, settlement, round_ids)
	test.assert_true(bool(first_apply.get("ok", false)), "first settlement apply")
	test.assert_equal(int(first_apply.get("gold_awarded", 0)), 40, "first clear grants repeat reward plus first-clear bonus")
	var second_apply := ProfileScript.apply_settlement(first_apply["profile"], settlement, round_ids)
	test.assert_true(bool(second_apply.get("duplicate", false)), "same result ID must be idempotent")
	test.assert_equal(int(second_apply["profile"]["gold"]), 40, "duplicate settlement cannot award gold twice")
	test.assert_equal(int(second_apply["profile"]["rounds"]["R1"]["completion_count"]), 1, "duplicate settlement cannot increment completion count")

static func _test_crash_after_profile_commit(
	data_repository: DataRepository,
	round_ids: Array[String],
	test: TestFramework
) -> void:
	var repository_before_crash := SaveRepositoryScript.new(TEST_ROOT)
	var profile := ProfileScript.create(round_ids)
	test.assert_true(
		bool(repository_before_crash.save_profile(profile).get("ok", false)),
		"crash fixture must persist its initial profile"
	)

	var state := RoundSimulatorScript.create_state(data_repository.get_round("R1"), data_repository.catalog)
	state["score"] = 10
	state["status"] = "ended"
	var run_id := "run:crash-after-profile-commit"
	test.assert_true(
		bool(repository_before_crash.save_snapshot(run_id, state).get("ok", false)),
		"crash fixture must persist the ended round snapshot"
	)

	var settlement := SettlementServiceScript.calculate(data_repository.get_round("R1"), state, run_id)
	var first_apply := ProfileScript.apply_settlement(profile, settlement, round_ids)
	test.assert_true(bool(first_apply.get("ok", false)), "crash fixture settlement must apply")
	test.assert_true(
		bool(repository_before_crash.save_profile(first_apply["profile"]).get("ok", false)),
		"profile commit must succeed before the simulated crash"
	)
	# Simulate process death here: the committed profile contains result_id, while the
	# ended snapshot is intentionally left on disk because delete_snapshot did not run.

	var repository_after_restart := SaveRepositoryScript.new(TEST_ROOT)
	var reloaded_profile := repository_after_restart.load_profile(round_ids)
	var reloaded_snapshot := repository_after_restart.load_snapshot(1, 1)
	test.assert_equal(reloaded_profile.get("status"), "ok", "restart must load the committed profile")
	test.assert_equal(reloaded_snapshot.get("status"), "ok", "restart must retain the stale ended snapshot")

	var snapshot: Dictionary = reloaded_snapshot.get("value", {})
	var replayed_settlement := SettlementServiceScript.calculate(
		data_repository.get_round("R1"),
		snapshot.get("round_state", {}),
		str(snapshot.get("run_id", ""))
	)
	var replay_apply := ProfileScript.apply_settlement(
		reloaded_profile.get("value", {}),
		replayed_settlement,
		round_ids
	)
	test.assert_true(bool(replay_apply.get("duplicate", false)), "restart must identify the same result_id")
	test.assert_equal(int(replay_apply["profile"]["gold"]), 40, "replay after crash cannot award gold twice")
	test.assert_equal(
		int(replay_apply["profile"]["rounds"]["R1"]["completion_count"]),
		1,
		"replay after crash cannot increment completion twice"
	)
	test.assert_equal(replay_apply.get("gold_awarded"), 0, "duplicate replay reports zero newly awarded gold")
	test.assert_true(
		bool(repository_after_restart.save_profile(replay_apply["profile"]).get("ok", false)),
		"duplicate replay profile save must still commit atomically"
	)
	test.assert_true(
		bool(repository_after_restart.delete_snapshot().get("ok", false)),
		"snapshot is deleted only after the profile commit succeeds"
	)

	var final_repository := SaveRepositoryScript.new(TEST_ROOT)
	var final_profile := final_repository.load_profile(round_ids)
	var final_snapshot := final_repository.load_snapshot(1, 1)
	test.assert_equal(int(final_profile.get("value", {}).get("gold", -1)), 40, "final gold remains single-award")
	test.assert_equal(
		int(final_profile.get("value", {}).get("rounds", {}).get("R1", {}).get("completion_count", -1)),
		1,
		"final completion remains single-counted"
	)
	test.assert_equal(final_snapshot.get("status"), "missing", "restart cleanup removes the stale snapshot")

static func _cleanup() -> void:
	for file_name: String in [
		"profile.json",
		"profile.json.tmp",
		"profile.json.bak",
		"round_snapshot.json",
		"round_snapshot.json.tmp",
		"round_snapshot.json.bak",
	]:
		var path := TEST_ROOT + "/" + file_name
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
