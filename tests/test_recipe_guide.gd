extends RefCounted

const DataRepositoryScript = preload("res://src/data/data_repository.gd")
const RecipeGuideScript = preload("res://src/ui/recipe_guide.gd")


static func run(test: TestFramework) -> void:
	var repository := DataRepositoryScript.new()
	var load_result := repository.load_all()
	test.assert_true(
		bool(load_result.get("ok", false)),
		"recipe guide fixtures require the validated catalog"
	)
	if not bool(load_result.get("ok", false)):
		return

	_test_dagger(repository.catalog, test)
	_test_iron_sword(repository.catalog, test)
	_test_dagger_p1(repository.catalog, test)
	_test_iron_sword_p1(repository.catalog, test)
	_test_cycle_failure(repository.catalog, test)
	_test_missing_producer_failure(repository.catalog, test)


static func _test_dagger(catalog: Dictionary, test: TestFramework) -> void:
	var result := RecipeGuideScript.build(catalog, "EQ_DAGGER", 0)
	test.assert_true(bool(result.get("ok", false)), "dagger recipe chain must build")
	test.assert_equal(
		_step_ids(result),
		["RCP_SMELT_IRON", "RCP_CRAFT_DAGGER"],
		"dagger chain must contain only its prerequisite and craft recipe"
	)
	test.assert_equal(
		_raw_count(result, "MAT_IRON_ORE"),
		1,
		"one dagger must require one iron ore"
	)
	test.assert_equal(
		_raw_count(result, "MAT_WOOD"),
		0,
		"dagger chain must exclude unrelated charcoal recipes"
	)
	var craft := _step(result, "RCP_CRAFT_DAGGER")
	test.assert_equal(
		str(craft.get("facility_id", "")),
		"FAC_WEAPON_BENCH",
		"dagger step must expose its facility"
	)
	test.assert_equal(
		str(craft.get("facility_display_name", "")),
		"무기 제작대",
		"dagger step must expose facility display metadata"
	)
	test.assert_equal(
		int(craft.get("duration_ticks", 0)),
		120,
		"dagger step must expose per-run duration"
	)
	test.assert_equal(
		str(craft.get("worker_mode", "")),
		"one",
		"dagger step must expose worker metadata"
	)


static func _test_iron_sword(catalog: Dictionary, test: TestFramework) -> void:
	var result := RecipeGuideScript.build(catalog, "EQ_IRON_SWORD", 0)
	test.assert_true(bool(result.get("ok", false)), "iron sword recipe chain must build")
	test.assert_equal(
		_step_ids(result),
		["RCP_SMELT_IRON", "RCP_CRAFT_IRON_SWORD"],
		"iron sword chain must exclude dagger and enhancement recipes"
	)
	test.assert_equal(
		_raw_count(result, "MAT_IRON_ORE"),
		2,
		"one iron sword must require two iron ore"
	)
	var smelt := _step(result, "RCP_SMELT_IRON")
	test.assert_equal(int(smelt.get("run_count", 0)), 2, "iron sword must smelt twice")
	test.assert_equal(
		int(smelt.get("total_duration_ticks", 0)),
		320,
		"scaled recipe metadata must include total duration"
	)
	test.assert_equal(
		_amount_count(smelt.get("inputs", []), "MAT_IRON_ORE", 0),
		2,
		"scaled smelting input must preserve the two-ore requirement"
	)
	test.assert_equal(
		int(smelt.get("output", {}).get("count", 0)),
		2,
		"scaled smelting output must provide two ingots"
	)


static func _test_dagger_p1(catalog: Dictionary, test: TestFramework) -> void:
	var result := RecipeGuideScript.build(catalog, "EQ_DAGGER", 1)
	test.assert_true(bool(result.get("ok", false)), "+1 dagger recipe chain must build")
	test.assert_equal(
		_step_ids(result),
		[
			"RCP_SMELT_IRON",
			"RCP_CRAFT_DAGGER",
			"RCP_BURN_CHARCOAL",
			"RCP_SYNTH_ENHANCEMENT_STONE",
			"RCP_ENHANCE_DAGGER_P1",
		],
		"+1 dagger chain must be dependency ordered without sword recipes"
	)
	_assert_enhancement_raw_materials(result, 1, test, "+1 dagger")
	test.assert_equal(
		str(result.get("target", {}).get("display_name", "")),
		"단검 +1",
		"enhancement target must carry its display level"
	)


static func _test_iron_sword_p1(catalog: Dictionary, test: TestFramework) -> void:
	var result := RecipeGuideScript.build(catalog, "EQ_IRON_SWORD", 1)
	test.assert_true(bool(result.get("ok", false)), "+1 iron sword recipe chain must build")
	test.assert_equal(
		_step_ids(result),
		[
			"RCP_SMELT_IRON",
			"RCP_CRAFT_IRON_SWORD",
			"RCP_BURN_CHARCOAL",
			"RCP_SYNTH_ENHANCEMENT_STONE",
			"RCP_ENHANCE_IRON_SWORD_P1",
		],
		"+1 iron sword chain must be dependency ordered without dagger recipes"
	)
	_assert_enhancement_raw_materials(result, 2, test, "+1 iron sword")


static func _test_cycle_failure(catalog: Dictionary, test: TestFramework) -> void:
	var broken: Dictionary = catalog.duplicate(true)
	var smelt := _entry(broken.get("recipes", []), "RCP_SMELT_IRON")
	smelt["inputs"] = [{
		"item_id": "MAT_IRON_INGOT",
		"enhancement_level": 0,
		"count": 1,
	}]
	var result := RecipeGuideScript.build(broken, "EQ_DAGGER", 0)
	test.assert_false(bool(result.get("ok", true)), "recipe cycles must fail safely")
	test.assert_equal(result.get("steps", []).size(), 0, "cycle failure must expose no partial steps")
	test.assert_contains(
		str(result.get("errors", [])),
		"cycle",
		"cycle failure must provide a diagnostic"
	)


static func _test_missing_producer_failure(catalog: Dictionary, test: TestFramework) -> void:
	var broken: Dictionary = catalog.duplicate(true)
	var filtered: Array = []
	for recipe_value: Variant in broken.get("recipes", []):
		if str(recipe_value.get("id", "")) != "RCP_CRAFT_DAGGER":
			filtered.append(recipe_value)
	broken["recipes"] = filtered
	var result := RecipeGuideScript.build_for_target(broken, "EQ_DAGGER", 0)
	test.assert_false(bool(result.get("ok", true)), "missing producers must fail safely")
	test.assert_equal(
		result.get("raw_materials", []).size(),
		0,
		"missing producer failure must expose no partial raw-material plan"
	)
	test.assert_contains(
		str(result.get("errors", [])),
		"missing producer",
		"missing producer failure must provide a diagnostic"
	)


static func _assert_enhancement_raw_materials(
	result: Dictionary,
	iron_count: int,
	test: TestFramework,
	label: String
) -> void:
	test.assert_equal(
		_raw_count(result, "MAT_IRON_ORE"),
		iron_count,
		"%s must expose the correct iron total" % label
	)
	test.assert_equal(
		_raw_count(result, "MAT_WOOD"),
		1,
		"%s must require one wood" % label
	)
	test.assert_equal(
		_raw_count(result, "MAT_MANA_SHARD"),
		1,
		"%s must require one mana shard" % label
	)


static func _step_ids(result: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for step_value: Variant in result.get("steps", []):
		ids.append(str(step_value.get("recipe_id", "")))
	return ids


static func _step(result: Dictionary, recipe_id: String) -> Dictionary:
	return _entry(result.get("steps", []), recipe_id, "recipe_id")


static func _raw_count(result: Dictionary, item_id: String) -> int:
	return _amount_count(result.get("raw_materials", []), item_id, 0)


static func _amount_count(entries: Array, item_id: String, enhancement_level: int) -> int:
	for entry_value: Variant in entries:
		if (
			str(entry_value.get("item_id", "")) == item_id
			and int(entry_value.get("enhancement_level", 0)) == enhancement_level
		):
			return int(entry_value.get("count", 0))
	return 0


static func _entry(entries: Array, id: String, id_field: String = "id") -> Dictionary:
	for entry_value: Variant in entries:
		if entry_value is Dictionary and str(entry_value.get(id_field, "")) == id:
			return entry_value
	return {}
