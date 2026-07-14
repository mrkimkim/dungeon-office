class_name DataRepository
extends RefCounted

const CATALOG_PATH: String = "res://data/catalog.json"
const ROUNDS_PATH: String = "res://data/rounds.json"

var catalog: Dictionary = {}
var round_catalog: Dictionary = {}

func load_all() -> Dictionary:
	var errors: Array[String] = []
	var catalog_result := _load_json(CATALOG_PATH)
	var rounds_result := _load_json(ROUNDS_PATH)
	if not bool(catalog_result.get("ok", false)):
		errors.append(str(catalog_result.get("error", "catalog load failed")))
	if not bool(rounds_result.get("ok", false)):
		errors.append(str(rounds_result.get("error", "round catalog load failed")))
	if not errors.is_empty():
		return {"ok": false, "errors": errors}

	catalog = catalog_result["value"]
	round_catalog = rounds_result["value"]
	errors.append_array(validate(catalog, round_catalog))
	return {"ok": errors.is_empty(), "errors": errors}

func get_round(round_id: String) -> Dictionary:
	return find_by_id(round_catalog.get("rounds", []), round_id)

func get_round_ids() -> Array[String]:
	var result: Array[String] = []
	for round_value: Variant in round_catalog.get("rounds", []):
		result.append(str(round_value.get("id", "")))
	return result

static func find_by_id(entries: Array, id: String) -> Dictionary:
	for entry_value: Variant in entries:
		if entry_value is Dictionary and str(entry_value.get("id", "")) == id:
			return entry_value
	return {}

static func validate(catalog_value: Dictionary, rounds_value: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if str(catalog_value.get("schema", "")) != "CatalogV1":
		errors.append("catalog.schema must be CatalogV1")
	if str(rounds_value.get("schema", "")) != "RoundCatalogV1":
		errors.append("rounds.schema must be RoundCatalogV1")
	if int(catalog_value.get("data_version", 0)) != 1:
		errors.append("catalog.data_version must be 1")
	if int(rounds_value.get("data_version", 0)) != int(catalog_value.get("data_version", 0)):
		errors.append("catalog and rounds data_version must match")
	_validate_source_documents(catalog_value.get("source_documents"), "catalog", errors)
	_validate_source_documents(rounds_value.get("source_documents"), "rounds", errors)

	var item_ids := _collect_unique_ids(catalog_value.get("items", []), "catalog.items", errors)
	var facility_ids := _collect_unique_ids(catalog_value.get("facilities", []), "catalog.facilities", errors)
	var recipe_ids := _collect_unique_ids(catalog_value.get("recipes", []), "catalog.recipes", errors)
	var request_ids := _collect_unique_ids(catalog_value.get("requests", []), "catalog.requests", errors)
	var product_ids := _collect_unique_ids(catalog_value.get("shop_products", []), "catalog.shop_products", errors)
	var round_ids := _collect_unique_ids(rounds_value.get("rounds", []), "rounds.rounds", errors)

	if item_ids.size() != 8:
		errors.append("MVP catalog must contain exactly 8 items")
	if facility_ids.size() != 7:
		errors.append("MVP catalog must contain exactly 7 facilities")
	if recipe_ids.size() != 7:
		errors.append("MVP catalog must contain exactly 7 recipes")
	if request_ids.size() != 7:
		errors.append("MVP catalog must contain exactly 7 request templates")
	if product_ids != {"SHOP_ENHANCEMENT_KIT": true}:
		errors.append("MVP catalog must contain only SHOP_ENHANCEMENT_KIT")
	if round_ids.keys() != ["R1", "R2", "R3", "R4", "R5"]:
		errors.append("round IDs must be ordered R1 through R5")

	_validate_rules(catalog_value.get("rules", {}), errors)
	_validate_items(catalog_value.get("items", []), errors)
	_validate_recipes(catalog_value.get("recipes", []), item_ids, facility_ids, errors)
	_validate_requests(catalog_value.get("requests", []), item_ids, errors)
	_validate_rounds(rounds_value.get("rounds", []), item_ids, facility_ids, request_ids, errors)
	return errors

static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "%s does not exist" % path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "cannot open %s (error %d)" % [path, FileAccess.get_open_error()]}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		return {
			"ok": false,
			"error": "%s:%d: %s" % [path, parser.get_error_line(), parser.get_error_message()],
		}
	if not parser.data is Dictionary:
		return {"ok": false, "error": "%s root must be an object" % path}
	return {"ok": true, "value": parser.data}

static func _collect_unique_ids(entries: Variant, path: String, errors: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	if not entries is Array:
		errors.append("%s must be an array" % path)
		return result
	for index: int in range(entries.size()):
		if not entries[index] is Dictionary:
			errors.append("%s[%d] must be an object" % [path, index])
			continue
		var id := str(entries[index].get("id", ""))
		if id.is_empty():
			errors.append("%s[%d].id must not be empty" % [path, index])
		elif result.has(id):
			errors.append("duplicate ID %s in %s" % [id, path])
		else:
			result[id] = true
	return result

static func _validate_rules(rules: Variant, errors: Array[String]) -> void:
	if not rules is Dictionary:
		errors.append("catalog.rules must be an object")
		return
	for field: String in [
		"tick_rate",
		"overheat_grace_ticks",
		"overheat_danger_ticks",
		"request_urgent_ticks",
		"deadline_warning_ticks",
		"deadline_countdown_ticks",
	]:
		if not _is_positive_integer(rules.get(field)):
			errors.append("catalog.rules.%s must be a positive integer" % field)
	if int(rules.get("tick_rate", 0)) != 20:
		errors.append("catalog.rules.tick_rate must be 20")
	if int(rules.get("overheat_danger_ticks", 0)) >= int(rules.get("overheat_grace_ticks", 0)):
		errors.append("overheat danger threshold must be smaller than grace")
	if int(rules.get("deadline_countdown_ticks", 0)) > int(rules.get("deadline_warning_ticks", 0)):
		errors.append("deadline countdown must start inside warning window")

static func _validate_source_documents(value: Variant, path: String, errors: Array[String]) -> void:
	if not value is Array or value.is_empty():
		errors.append("%s.source_documents must be a non-empty array" % path)
		return
	var seen: Dictionary = {}
	for trace_value: Variant in value:
		if not trace_value is Dictionary:
			errors.append("%s.source_documents entries must be objects" % path)
			continue
		var document_id := str(trace_value.get("id", ""))
		var version := str(trace_value.get("version", ""))
		if document_id.is_empty() or version.is_empty():
			errors.append("%s.source_documents entries need id and version" % path)
		elif seen.has(document_id):
			errors.append("%s.source_documents duplicates %s" % [path, document_id])
		seen[document_id] = true

static func _validate_items(items: Array, errors: Array[String]) -> void:
	for item_value: Variant in items:
		var item: Dictionary = item_value
		var category := str(item.get("category", ""))
		if category not in ["raw_material", "processed_material", "equipment"]:
			errors.append("item %s has invalid category" % item.get("id", ""))
		if str(item.get("display_name", "")).is_empty():
			errors.append("item %s needs display_name" % item.get("id", ""))
		if category != "equipment" and bool(item.get("enhanceable", false)):
			errors.append("non-equipment %s cannot be enhanceable" % item.get("id", ""))

static func _validate_recipes(
	recipes: Array,
	item_ids: Dictionary,
	facility_ids: Dictionary,
	errors: Array[String]
) -> void:
	for recipe_value: Variant in recipes:
		var recipe: Dictionary = recipe_value
		var recipe_id := str(recipe.get("id", ""))
		if not facility_ids.has(str(recipe.get("facility_id", ""))):
			errors.append("recipe %s references unknown facility" % recipe_id)
		if str(recipe.get("worker_mode", "")) not in ["none", "one"]:
			errors.append("recipe %s has invalid worker_mode" % recipe_id)
		if not _is_positive_integer(recipe.get("duration_ticks")):
			errors.append("recipe %s duration_ticks must be a positive integer" % recipe_id)
		var inputs: Variant = recipe.get("inputs", [])
		if not inputs is Array or inputs.is_empty():
			errors.append("recipe %s needs at least one input" % recipe_id)
		else:
			for input_value: Variant in inputs:
				_validate_item_amount(input_value, "recipe %s input" % recipe_id, item_ids, errors)
		_validate_item_amount(recipe.get("output", {}), "recipe %s output" % recipe_id, item_ids, errors)
		if int(recipe.get("output", {}).get("count", 0)) != 1:
			errors.append("recipe %s output count must be 1 in MVP" % recipe_id)

static func _validate_item_amount(value: Variant, path: String, item_ids: Dictionary, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("%s must be an object" % path)
		return
	if not item_ids.has(str(value.get("item_id", ""))):
		errors.append("%s references unknown item" % path)
	if int(value.get("enhancement_level", -1)) not in [0, 1]:
		errors.append("%s enhancement_level must be 0 or 1" % path)
	if not _is_positive_integer(value.get("count")):
		errors.append("%s count must be a positive integer" % path)

static func _validate_requests(requests: Array, item_ids: Dictionary, errors: Array[String]) -> void:
	for request_value: Variant in requests:
		var request: Dictionary = request_value
		var request_id := str(request.get("id", ""))
		if not item_ids.has(str(request.get("item_id", ""))):
			errors.append("request %s references unknown item" % request_id)
		if int(request.get("required_level", -1)) not in [0, 1]:
			errors.append("request %s required_level must be 0 or 1" % request_id)
		if not _is_positive_integer(request.get("score")):
			errors.append("request %s score must be a positive integer" % request_id)
		if not _is_positive_integer(request.get("patience_ticks")):
			errors.append("request %s patience_ticks must be a positive integer" % request_id)

static func _validate_rounds(
	rounds: Array,
	item_ids: Dictionary,
	facility_ids: Dictionary,
	request_ids: Dictionary,
	errors: Array[String]
) -> void:
	var event_ids: Dictionary = {}
	var total_events := 0
	for round_value: Variant in rounds:
		var round: Dictionary = round_value
		var round_id := str(round.get("id", ""))
		for field: String in ["deadline_ticks", "active_request_slots", "worker_count", "inventory_capacity"]:
			if not _is_positive_integer(round.get(field)):
				errors.append("round %s %s must be a positive integer" % [round_id, field])
		var cutlines: Variant = round.get("cutlines", [])
		if not cutlines is Array or cutlines.size() != 3:
			errors.append("round %s needs exactly 3 cutlines" % round_id)
		elif not (int(cutlines[0]) < int(cutlines[1]) and int(cutlines[1]) < int(cutlines[2])):
			errors.append("round %s cutlines must be strictly increasing" % round_id)
		for item_id_value: Variant in round.get("supply_items", []):
			if not item_ids.has(str(item_id_value)):
				errors.append("round %s references unknown supply item %s" % [round_id, item_id_value])
		for facility_id_value: Variant in round.get("facilities", []):
			if not facility_ids.has(str(facility_id_value)):
				errors.append("round %s references unknown facility %s" % [round_id, facility_id_value])
		var previous_release := -1
		for event_value: Variant in round.get("events", []):
			total_events += 1
			var event: Dictionary = event_value
			var event_id := str(event.get("event_id", ""))
			if event_id.is_empty() or event_ids.has(event_id):
				errors.append("event ID %s is empty or duplicated" % event_id)
			event_ids[event_id] = true
			if not request_ids.has(str(event.get("request_id", ""))):
				errors.append("event %s references unknown request" % event_id)
			var release_tick := int(event.get("release_tick", -1))
			if release_tick < 0 or not _is_integer_number(event.get("release_tick")):
				errors.append("event %s release_tick must be a non-negative integer" % event_id)
			if release_tick < previous_release:
				errors.append("round %s events are not sorted by release_tick" % round_id)
			if release_tick >= int(round.get("deadline_ticks", 0)):
				errors.append("event %s releases at or after the deadline" % event_id)
			previous_release = release_tick
	if total_events != 39:
		errors.append("MVP rounds must contain exactly 39 scripted events")

static func _is_integer_number(value: Variant) -> bool:
	return value is int or (value is float and value == floor(value))

static func _is_positive_integer(value: Variant) -> bool:
	return _is_integer_number(value) and int(value) > 0
