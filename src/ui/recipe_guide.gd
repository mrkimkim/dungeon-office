class_name RecipeGuide
extends RefCounted

## Builds a presentation-only production plan from the authoritative catalog.
## The result is derived data: it must not be written into round state or saves.


static func build(
	catalog: Dictionary,
	target_item_id: String,
	target_level: int = 0,
	target_count: int = 1
) -> Dictionary:
	var context := {
		"items_by_id": _index_by_id(catalog.get("items", [])),
		"facilities_by_id": _index_by_id(catalog.get("facilities", [])),
		"producers_by_output": _index_producers(catalog.get("recipes", [])),
		"visiting": {},
		"recipe_runs": {},
		"step_order": [],
		"raw_counts": {},
		"errors": [],
	}
	if target_item_id.is_empty():
		_add_error(context, "target item ID must not be empty")
	elif target_level < 0:
		_add_error(context, "target enhancement level must not be negative")
	elif target_count <= 0:
		_add_error(context, "target count must be positive")
	else:
		_expand_required(context, target_item_id, target_level, target_count)

	var target := _item_amount_view(
		context,
		{
			"item_id": target_item_id,
			"enhancement_level": target_level,
			"count": target_count,
		}
	)
	var raw_materials: Array = []
	var steps: Array = []
	var errors: Array = context.get("errors", [])
	if errors.is_empty():
		raw_materials = _build_raw_materials(context)
		steps = _build_steps(context)
		errors = context.get("errors", [])
	if not errors.is_empty():
		return {
			"ok": false,
			"target": target,
			"raw_materials": [],
			"steps": [],
			"errors": errors.duplicate(),
		}

	return {
		"ok": true,
		"target": target,
		"raw_materials": raw_materials,
		"steps": steps,
		"errors": [],
	}


static func build_for_target(
	catalog: Dictionary,
	target_item_id: String,
	target_level: int = 0,
	target_count: int = 1
) -> Dictionary:
	return build(catalog, target_item_id, target_level, target_count)


static func _expand_required(
	context: Dictionary,
	item_id: String,
	enhancement_level: int,
	required_count: int
) -> bool:
	if required_count <= 0:
		_add_error(context, "required count for %s must be positive" % item_id)
		return false

	var items_by_id: Dictionary = context.get("items_by_id", {})
	if not items_by_id.has(item_id):
		_add_error(context, "unknown item %s" % item_id)
		return false

	var key := _item_key(item_id, enhancement_level)
	var visiting: Dictionary = context.get("visiting", {})
	if visiting.has(key):
		_add_error(context, "recipe cycle detected at %s" % key)
		return false

	var producers_by_output: Dictionary = context.get("producers_by_output", {})
	var producers: Array = producers_by_output.get(key, [])
	if producers.is_empty():
		var item_definition: Dictionary = items_by_id[item_id]
		if (
			str(item_definition.get("category", "")) == "raw_material"
			and enhancement_level == 0
		):
			var raw_counts: Dictionary = context.get("raw_counts", {})
			raw_counts[key] = int(raw_counts.get(key, 0)) + required_count
			return true
		_add_error(context, "missing producer for %s" % key)
		return false
	if producers.size() != 1:
		_add_error(context, "multiple producers for %s" % key)
		return false

	var recipe: Dictionary = producers[0]
	var recipe_id := str(recipe.get("id", ""))
	if recipe_id.is_empty():
		_add_error(context, "producer for %s has no recipe ID" % key)
		return false
	var output: Dictionary = (
		recipe.get("output", {}) if recipe.get("output", {}) is Dictionary else {}
	)
	var output_count := int(output.get("count", 0))
	if output_count <= 0:
		_add_error(context, "recipe %s has an invalid output count" % recipe_id)
		return false
	var run_count := ceili(float(required_count) / float(output_count))

	var inputs_value: Variant = recipe.get("inputs", [])
	if not inputs_value is Array or inputs_value.is_empty():
		_add_error(context, "recipe %s has no inputs" % recipe_id)
		return false

	visiting[key] = true
	var valid := true
	for input_value: Variant in inputs_value:
		if not input_value is Dictionary:
			_add_error(context, "recipe %s has an invalid input" % recipe_id)
			valid = false
			continue
		var input: Dictionary = input_value
		var input_count := int(input.get("count", 0))
		if input_count <= 0:
			_add_error(context, "recipe %s has a non-positive input count" % recipe_id)
			valid = false
			continue
		if not _expand_required(
			context,
			str(input.get("item_id", "")),
			int(input.get("enhancement_level", 0)),
			input_count * run_count
		):
			valid = false
	visiting.erase(key)
	if not valid:
		return false

	var recipe_runs: Dictionary = context.get("recipe_runs", {})
	if not recipe_runs.has(recipe_id):
		var step_order: Array = context.get("step_order", [])
		step_order.append(recipe_id)
		recipe_runs[recipe_id] = {"recipe": recipe, "run_count": 0}
	var accumulated: Dictionary = recipe_runs[recipe_id]
	accumulated["run_count"] = int(accumulated.get("run_count", 0)) + run_count
	return true


static func _build_raw_materials(context: Dictionary) -> Array:
	var result: Array = []
	var raw_counts: Dictionary = context.get("raw_counts", {})
	var keys: Array = raw_counts.keys()
	keys.sort()
	for key_value: Variant in keys:
		var parts := str(key_value).split("@", false, 1)
		if parts.size() != 2:
			continue
		result.append(_item_amount_view(context, {
			"item_id": str(parts[0]),
			"enhancement_level": int(parts[1]),
			"count": int(raw_counts[key_value]),
		}))
	return result


static func _build_steps(context: Dictionary) -> Array:
	var result: Array = []
	var recipe_runs: Dictionary = context.get("recipe_runs", {})
	var step_order: Array = context.get("step_order", [])
	var facilities_by_id: Dictionary = context.get("facilities_by_id", {})
	for recipe_id_value: Variant in step_order:
		var recipe_id := str(recipe_id_value)
		var accumulated: Dictionary = recipe_runs.get(recipe_id, {})
		var recipe: Dictionary = accumulated.get("recipe", {})
		var run_count := int(accumulated.get("run_count", 0))
		var facility_id := str(recipe.get("facility_id", ""))
		if not facilities_by_id.has(facility_id):
			_add_error(context, "recipe %s references unknown facility %s" % [
				recipe_id,
				facility_id,
			])
			continue
		var facility: Dictionary = facilities_by_id[facility_id]
		var inputs: Array = []
		for input_value: Variant in recipe.get("inputs", []):
			if not input_value is Dictionary:
				continue
			var scaled_input: Dictionary = input_value.duplicate(true)
			scaled_input["count"] = int(scaled_input.get("count", 0)) * run_count
			inputs.append(_item_amount_view(context, scaled_input))
		var scaled_output: Dictionary = recipe.get("output", {}).duplicate(true)
		scaled_output["count"] = int(scaled_output.get("count", 0)) * run_count
		var duration_ticks := int(recipe.get("duration_ticks", 0))
		result.append({
			"recipe_id": recipe_id,
			"facility_id": facility_id,
			"facility_display_name": str(facility.get("display_name", facility_id)),
			"run_count": run_count,
			"inputs": inputs,
			"output": _item_amount_view(context, scaled_output),
			"duration_ticks": duration_ticks,
			"total_duration_ticks": duration_ticks * run_count,
			"worker_mode": str(recipe.get("worker_mode", "")),
			"overheat_output": bool(recipe.get("overheat_output", false)),
		})
	return result


static func _item_amount_view(context: Dictionary, amount: Dictionary) -> Dictionary:
	var item_id := str(amount.get("item_id", ""))
	var enhancement_level := int(amount.get("enhancement_level", 0))
	var items_by_id: Dictionary = context.get("items_by_id", {})
	var definition: Dictionary = items_by_id.get(item_id, {})
	var display_name := str(definition.get("display_name", item_id))
	if enhancement_level > 0:
		display_name += " +%d" % enhancement_level
	return {
		"item_id": item_id,
		"enhancement_level": enhancement_level,
		"count": int(amount.get("count", 0)),
		"display_name": display_name,
		"category": str(definition.get("category", "")),
	}


static func _index_by_id(entries_value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not entries_value is Array:
		return result
	for entry_value: Variant in entries_value:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var entry_id := str(entry.get("id", ""))
		if not entry_id.is_empty():
			result[entry_id] = entry
	return result


static func _index_producers(recipes_value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not recipes_value is Array:
		return result
	for recipe_value: Variant in recipes_value:
		if not recipe_value is Dictionary:
			continue
		var recipe: Dictionary = recipe_value
		if not recipe.get("output") is Dictionary:
			continue
		var output: Dictionary = recipe["output"]
		var key := _item_key(
			str(output.get("item_id", "")),
			int(output.get("enhancement_level", 0))
		)
		var producers: Array = result.get(key, [])
		producers.append(recipe)
		result[key] = producers
	return result


static func _item_key(item_id: String, enhancement_level: int) -> String:
	return "%s@%d" % [item_id, enhancement_level]


static func _add_error(context: Dictionary, message: String) -> void:
	var errors: Array = context.get("errors", [])
	if message not in errors:
		errors.append(message)
