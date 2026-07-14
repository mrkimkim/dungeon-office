extends RefCounted

const DataRepositoryScript = preload("res://src/data/data_repository.gd")
const LegalTextRepositoryScript = preload("res://src/data/legal_text_repository.gd")

const DOCUMENT_PATHS: Dictionary = {
	"CNT-ITEM-001": "res://docs/items.md",
	"CNT-RECIPE-001": "res://docs/recipes.md",
	"CNT-MVP-ROUND-001": "res://docs/mvp-rounds.md",
	"SYS-PROG-001": "res://docs/progression.md",
	"SYS-ECON-001": "res://docs/economy-rewards.md",
	"BAL-MVP-001": "res://docs/balance.md",
	"TECH-SIM-001": "res://docs/runtime-contract.md",
}

static func run(test: TestFramework) -> void:
	var repository := DataRepositoryScript.new()
	var result := repository.load_all()
	test.assert_true(bool(result.get("ok", false)), "catalog and rounds must validate: %s" % [result.get("errors", [])])
	test.assert_equal(repository.catalog.get("items", []).size(), 8, "catalog must expose 8 items")
	test.assert_equal(repository.catalog.get("recipes", []).size(), 7, "catalog must expose 7 recipes")
	test.assert_equal(repository.get_round_ids(), ["R1", "R2", "R3", "R4", "R5"], "round order must be stable")
	var event_count := 0
	for round_value: Variant in repository.round_catalog.get("rounds", []):
		event_count += round_value.get("events", []).size()
	test.assert_equal(event_count, 39, "all 39 scripted events must be present")
	test.assert_equal(repository.catalog.get("source_documents", []).size(), 5, "catalog must trace source documents")
	test.assert_equal(repository.round_catalog.get("source_documents", []).size(), 4, "rounds must trace source documents")
	_assert_source_document_versions(repository.catalog.get("source_documents", []), test)
	_assert_source_document_versions(repository.round_catalog.get("source_documents", []), test)
	var rules: Dictionary = repository.catalog.get("rules", {})
	test.assert_equal(int(rules.get("overheat_danger_ticks", 0)), 60, "BAL overheat danger projection must be 3 seconds")
	test.assert_equal(int(rules.get("request_urgent_ticks", 0)), 200, "BAL request urgency projection must be 10 seconds")
	test.assert_equal(int(rules.get("deadline_warning_ticks", 0)), 600, "BAL deadline warning projection must be 30 seconds")
	test.assert_equal(int(rules.get("deadline_countdown_ticks", 0)), 200, "BAL deadline countdown projection must be 10 seconds")

	var legal_repository := LegalTextRepositoryScript.new()
	var privacy := legal_repository.load_privacy()
	test.assert_true(bool(privacy.get("ok", false)), "bundled privacy text must load")
	test.assert_false(str(privacy.get("text", "")).begins_with("---"), "YAML front matter must be stripped")
	test.assert_contains(str(privacy.get("text", "")), "개인정보처리방침", "privacy body must remain")
	var licenses := legal_repository.load_licenses()
	test.assert_true(bool(licenses.get("ok", false)), "bundled license text must load")
	test.assert_contains(str(licenses.get("text", "")), "Godot Engine", "Godot license notice must remain")
	test.assert_contains(str(licenses.get("text", "")), "androidx.fragment:fragment:1.8.6", "resolved AndroidX notice must remain")
	test.assert_contains(str(licenses.get("text", "")), "Apache License", "Android runtime license text must remain")
	test.assert_contains(str(licenses.get("text", "")), "Exhaustive licensing information", "Godot third-party notice must remain")

static func _assert_source_document_versions(traces: Array, test: TestFramework) -> void:
	for trace_value: Variant in traces:
		var trace: Dictionary = trace_value
		var document_id := str(trace.get("id", ""))
		var version := str(trace.get("version", ""))
		var path := str(DOCUMENT_PATHS.get(document_id, ""))
		test.assert_false(path.is_empty(), "trace %s must map to a normative document" % document_id)
		if path.is_empty():
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		test.assert_true(file != null, "source document %s must be readable" % document_id)
		if file == null:
			continue
		var source := file.get_as_text()
		test.assert_contains(
			source,
			"| 버전 | %s |" % version,
			"%s projection version must match document metadata" % document_id
		)
