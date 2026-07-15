extends RefCounted

const DataRepositoryScript = preload("res://src/data/data_repository.gd")
const LegalRepositoryScript = preload("res://src/data/legal_text_repository.gd")
const ProfileScript = preload("res://src/app/profile_v1.gd")
const SaveRepositoryScript = preload("res://src/app/save_repository.gd")
const MainScript = preload("res://src/ui/main.gd")

const TEST_ROOT: String = "user://tests/app_flow"


static func run(test: TestFramework) -> void:
	var save_repository := SaveRepositoryScript.new(TEST_ROOT)
	save_repository.delete_all()
	var data_repository := DataRepositoryScript.new()
	var data_result := data_repository.load_all()
	test.assert_true(bool(data_result.get("ok", false)), "app flow requires valid data")
	if not bool(data_result.get("ok", false)):
		return

	var app = MainScript.new()
	app._build_shell()
	app._data_repository = data_repository
	app._legal_repository = LegalRepositoryScript.new()
	app._save_repository = save_repository
	app._profile = ProfileScript.create(data_repository.get_round_ids())
	test.assert_true(
		bool(save_repository.save_profile(app._profile).get("ok", false)),
		"app flow profile setup"
	)

	app._notice = "지도 안내 테스트"
	app._show_map()
	test.assert_equal(app._screen, "map", "new profile can open the round map")
	test.assert_equal(
		(app.find_child("PendingNoticeLabel", true, false) as Label).text,
		"지도 안내 테스트",
		"map feedback must be visible instead of being silently stored"
	)
	test.assert_true(app._notice.is_empty(), "visible map feedback is consumed once")
	var map_buttons := app.find_children("*", "Button", true, false)
	test.assert_true(map_buttons.size() >= 7, "map exposes five rounds and navigation")
	var locked_r2 := app.find_child("RoundButton_R2", true, false) as Button
	test.assert_false(
		locked_r2.disabled,
		"a locked round remains inspectable so its unlock condition is not hidden"
	)
	locked_r2.pressed.emit()
	test.assert_equal(app._screen, "map", "locked round inspection remains on the map")
	test.assert_contains(
		(app.find_child("PendingNoticeLabel", true, false) as Label).text,
		"앞 라운드",
		"locked round inspection explains its prerequisite"
	)

	app._show_brief("R1")
	test.assert_equal(app._screen, "brief", "R1 opens a briefing before play")
	app._start_round("R1")
	test.assert_equal(app._screen, "play", "briefing starts the playable screen")
	test.assert_equal(str(app._round_state.get("round_id", "")), "R1", "R1 state created")
	test.assert_true(
		app.find_child("SourceSupply_MAT_IRON_ORE", true, false) != null,
		"play screen exposes a direct iron-ore source"
	)
	var tick_before_recipe := int(app._round_state.get("tick", -1))
	var recipe_button := app.find_child("RecipeButton_R1-E1", true, false) as Button
	test.assert_true(recipe_button != null, "the active request exposes its recipe action")
	recipe_button.pressed.emit()
	test.assert_equal(app._screen, "recipe", "recipe action opens the paused recipe guide")
	test.assert_true(
		bool(app._round_state.get("paused", false)),
		"opening a recipe pauses the round"
	)
	test.assert_equal(
		int(app._round_state.get("tick", -2)),
		tick_before_recipe,
		"opening a recipe spends no simulation tick"
	)
	test.assert_contains(
		(app.find_child("RecipeTitleLabel", true, false) as Label).text,
		"단검",
		"recipe guide identifies the requested equipment"
	)
	test.assert_true(
		app.find_child("RecipeStep_RCP_SMELT_IRON", true, false) != null,
		"dagger recipe includes its iron-smelting prerequisite"
	)
	test.assert_true(
		app.find_child("RecipeStep_RCP_CRAFT_DAGGER", true, false) != null,
		"dagger recipe includes its final crafting step"
	)
	test.assert_equal(
		(app.find_child("RecipeStep_RCP_SMELT_IRON", true, false) as Control).mouse_filter,
		Control.MOUSE_FILTER_PASS,
		"recipe process cards must pass finger drags to the parent scroll view"
	)
	test.assert_equal(
		(app.find_child("RecipeRawMaterials", true, false) as Control).mouse_filter,
		Control.MOUSE_FILTER_PASS,
		"recipe material cards must pass finger drags to the parent scroll view"
	)
	test.assert_true(app._handle_back_request(), "Android Back handles an open recipe guide")
	test.assert_equal(app._screen, "play", "Back returns from the recipe guide to play")
	test.assert_false(
		bool(app._round_state.get("paused", true)),
		"Back resumes the round after recipe inspection"
	)
	test.assert_equal(
		int(app._round_state.get("tick", -2)),
		tick_before_recipe,
		"closing a recipe with Back spends no simulation tick"
	)

	recipe_button = app.find_child("RecipeButton_R1-E1", true, false) as Button
	recipe_button.pressed.emit()
	var recipe_close := app.find_child("RecipeCloseButton", true, false) as Button
	test.assert_true(recipe_close != null, "recipe guide exposes an explicit close action")
	app._round_state["status"] = "completed"
	recipe_close.pressed.emit()
	test.assert_equal(
		app._screen,
		"recipe",
		"a rejected resume keeps the recipe guide open"
	)
	test.assert_true(
		bool(app._round_state.get("paused", false)),
		"a rejected resume cannot make the paused round look active"
	)
	test.assert_true(
		app.find_child("RecipeResumeError", true, false) != null,
		"a rejected resume exposes an inline retry explanation"
	)
	app._round_state["status"] = "running"
	app._snapshot_save_failed = false
	recipe_close.pressed.emit()
	test.assert_equal(app._screen, "play", "recipe close action returns to play")
	test.assert_false(
		bool(app._round_state.get("paused", true)),
		"recipe close action resumes the round"
	)
	test.assert_equal(
		int(app._round_state.get("tick", -2)),
		tick_before_recipe,
		"explicitly closing a recipe spends no simulation tick"
	)
	var tick_before_hitch := int(app._round_state.get("tick", -1))
	app._process(90.0)
	test.assert_equal(
		int(app._round_state.get("tick", -2)),
		tick_before_hitch,
		"the first play frame discards stale wall time after a screen transition"
	)
	app._process(90.0)
	test.assert_true(
		int(app._round_state.get("tick", -1)) - tick_before_hitch <= 5,
		"an Android scheduler hitch cannot fast-forward more than 250ms"
	)
	var score_before_rejected_delivery := int(app._round_state.get("score", 0))
	var deliveries_before_rejected_delivery: int = int(
		app._round_state.get("deliveries", []).size()
	)
	test.assert_false(
		app._attempt_item_transfer(
			{"kind": "supply", "item_id": "MAT_IRON_ORE"},
			{"kind": "delivery"}
		),
		"delivery rejects raw materials"
	)
	test.assert_equal(
		int(app._round_state.get("score", 0)),
		score_before_rejected_delivery,
		"a rejected delivery cannot change score"
	)
	test.assert_equal(
		app._round_state.get("deliveries", []).size(),
		deliveries_before_rejected_delivery,
		"a rejected delivery cannot record completion"
	)
	test.assert_true(
		app._pending_play_effects.is_empty(),
		"a rejected delivery cannot queue success feedback"
	)

	app._on_item_drop_requested(
		{"kind": "supply", "item_id": "MAT_IRON_ORE"},
		{
			"kind": "facility_input",
			"facility_id": "FAC_FURNACE",
		}
	)
	test.assert_equal(
		str(app._round_state["facilities"]["FAC_FURNACE"].get("status", "")),
		"working",
		"dropping ore starts the automatic furnace"
	)
	_advance_until_output(app, "FAC_FURNACE")
	app._on_item_drop_requested(
		{"kind": "facility_output", "facility_id": "FAC_FURNACE"},
		{"kind": "inventory", "slot": 0}
	)
	test.assert_equal(
		str(app._round_state["inventory"][0].get("item_id", "")),
		"MAT_IRON_INGOT",
		"dropping a furnace output stores it in the chosen inventory slot"
	)
	app._on_item_drop_requested(
		{"kind": "inventory", "slot": 0},
		{
			"kind": "facility_input",
			"facility_id": "FAC_WEAPON_BENCH",
		}
	)
	app._on_start_requested("FAC_WEAPON_BENCH")
	test.assert_equal(
		str(app._round_state["facilities"]["FAC_WEAPON_BENCH"].get("status", "")),
		"working",
		"ready worker facility starts from the HUD action"
	)
	_advance_until_output(app, "FAC_WEAPON_BENCH")
	app._on_item_drop_requested(
		{"kind": "facility_output", "facility_id": "FAC_WEAPON_BENCH"},
		{"kind": "delivery"}
	)
	test.assert_equal(int(app._round_state.get("score", 0)), 10, "direct R1 cycle awards score")
	test.assert_equal(app._round_state.get("deliveries", []).size(), 1, "direct R1 cycle records delivery")
	test.assert_true(app._selected_source.is_empty(), "atomic drops leave no stale tap selection")
	test.assert_contains(app._feedback, "납품 완료", "delivery exposes a persistent success message")
	test.assert_contains(app._feedback, "+10점", "delivery feedback connects success to awarded score")
	var delivery_impact := app.find_child("DeliveryImpactLayer", true, false) as Control
	test.assert_true(delivery_impact != null, "accepted delivery flushes its effect after the rebuilt play UI")
	test.assert_equal(
		str(delivery_impact.get_meta("event_id", "")),
		"R1-E1",
		"app forwards the simulator's matched request identity to the impact"
	)
	test.assert_equal(
		int(delivery_impact.get_meta("score", 0)),
		10,
		"app forwards the exact awarded score to the impact"
	)
	test.assert_true(app._pending_play_effects.is_empty(), "render consumes each delivery effect exactly once")
	test.assert_equal(
		str(delivery_impact.get_meta("run_id", "")),
		app._run_id,
		"delivery effects are scoped to the active run"
	)

	var tick_before_pause := int(app._round_state.get("tick", -1))
	app._pause_round()
	test.assert_true(bool(app._round_state.get("paused", false)), "pause screen pauses simulation")
	test.assert_equal(int(app._round_state.get("tick", -2)), tick_before_pause, "pause spends no tick")
	app._resume_round()
	test.assert_false(bool(app._round_state.get("paused", true)), "resume returns to running state")
	test.assert_equal(int(app._round_state.get("tick", -2)), tick_before_pause, "resume spends no tick")
	app.set_process(false)

	var loaded_snapshot := save_repository.load_snapshot(1, 1)
	test.assert_equal(loaded_snapshot.get("status"), "ok", "direct actions persist a resumable snapshot")
	test.assert_equal(
		int(loaded_snapshot.get("value", {}).get("round_state", {}).get("score", -1)),
		10,
		"snapshot contains latest delivered score"
	)

	app._profile["rounds"]["R4"]["first_cleared"] = true
	app._profile["gold"] = 200
	app._show_shop()
	var purchase_button := app.find_child("PurchaseEnhancementButton", true, false) as Button
	test.assert_true(purchase_button != null, "eligible profile sees the enhancement purchase")
	purchase_button.pressed.emit()
	test.assert_equal(app._screen, "confirm", "soft-currency purchase requires confirmation")
	test.assert_true(
		app._confirm_cancel_callback.is_valid(),
		"purchase confirmation retains a safe cancel route"
	)
	app._confirm_cancel_callback.call()
	test.assert_equal(app._screen, "shop", "purchase confirmation cancel returns to the shop")
	test.assert_equal(int(app._profile.get("gold", -1)), 200, "cancel does not spend gold")

	app._show_brief("R1")
	app._start_round("R1")
	app._round_state["deadline_ticks"] = int(app._round_state.get("tick", 0)) + 1
	app._on_item_drop_requested(
		{"kind": "supply", "item_id": "MAT_IRON_ORE"},
		{"kind": "inventory", "slot": 0}
	)
	test.assert_equal(
		str(app._round_state.get("status", "")),
		"ended",
		"a command on the final tick can end a round"
	)
	app._process(0.0)
	test.assert_equal(
		app._screen,
		"result",
		"a round ended by the final input command is settled on the next process pass"
	)

	app.free()
	test.assert_true(bool(save_repository.delete_all().get("ok", false)), "app flow cleanup")


static func _advance_until_output(app: Variant, facility_id: String) -> void:
	while (
		str(app._round_state.get("status", "")) == "running"
		and str(app._round_state["facilities"][facility_id].get("status", "")) != "output"
	):
		app._step_commands([])
