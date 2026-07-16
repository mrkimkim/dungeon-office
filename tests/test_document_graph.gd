extends RefCounted

const INDEX_PATH: String = "res://docs/README.md"
const EXPECTED_DOCUMENT_COUNT: int = 19

static func run(test: TestFramework) -> void:
	var documents := _load_documents(test)
	test.assert_equal(documents.size(), EXPECTED_DOCUMENT_COUNT, "normative document count must remain explicit")
	if documents.size() != EXPECTED_DOCUMENT_COUNT:
		return

	for document_id: String in documents:
		var document: Dictionary = documents[document_id]
		for dependency_id: String in document["depends_on"]:
			test.assert_true(documents.has(dependency_id), "%s depends on known document %s" % [document_id, dependency_id])
			if not documents.has(dependency_id):
				continue
			test.assert_true(
				document_id in documents[dependency_id]["consumed_by"],
				"%s consumed_by must include dependent %s" % [dependency_id, document_id]
			)
			if str(document["status"]) == "Approved":
				test.assert_equal(
					str(documents[dependency_id]["status"]),
					"Approved",
					"Approved %s cannot depend on unapproved %s" % [document_id, dependency_id]
				)

	test.assert_false(_has_cycle(documents), "document dependency graph must be acyclic")
	_assert_index_waves(documents, test)

static func _load_documents(test: TestFramework) -> Dictionary:
	var result: Dictionary = {}
	var directory := DirAccess.open("res://docs")
	test.assert_true(directory != null, "docs directory must be readable")
	if directory == null:
		return result
	var file_names: Array[String] = []
	for file_name: String in directory.get_files():
		if file_name.ends_with(".md") and file_name != "README.md":
			file_names.append(file_name)
	file_names.sort()
	for file_name: String in file_names:
		var path := "res://docs/" + file_name
		var file := FileAccess.open(path, FileAccess.READ)
		test.assert_true(file != null, "%s must be readable" % path)
		if file == null:
			continue
		var source := file.get_as_text()
		var document_id := _first_id(_metadata_value(source, "문서 ID"))
		test.assert_false(document_id.is_empty(), "%s must declare a document ID" % path)
		if document_id.is_empty():
			continue
		test.assert_false(result.has(document_id), "document ID %s must be unique" % document_id)
		result[document_id] = {
			"path": path,
			"status": _metadata_value(source, "상태"),
			"depends_on": _all_ids(_metadata_value(source, "`depends_on`")),
			"consumed_by": _all_ids(_metadata_value(source, "`consumed_by`")),
		}
	return result

static func _metadata_value(source: String, key: String) -> String:
	var prefix := "| %s |" % key
	for line: String in source.split("\n"):
		if line.begins_with(prefix):
			return line.trim_prefix(prefix).trim_suffix("|").strip_edges()
	return ""

static func _first_id(value: String) -> String:
	var ids := _all_ids(value)
	return ids[0] if not ids.is_empty() else ""

static func _all_ids(value: String) -> Array[String]:
	var result: Array[String] = []
	var regex := RegEx.new()
	regex.compile("`([A-Z][A-Z0-9-]*-[0-9]{3})`")
	for match_result: RegExMatch in regex.search_all(value):
		result.append(match_result.get_string(1))
	return result

static func _has_cycle(documents: Dictionary) -> bool:
	var visit_state: Dictionary = {}
	for document_id: String in documents:
		if _visit_cycle(document_id, documents, visit_state):
			return true
	return false

static func _visit_cycle(document_id: String, documents: Dictionary, visit_state: Dictionary) -> bool:
	var state := int(visit_state.get(document_id, 0))
	if state == 1:
		return true
	if state == 2:
		return false
	visit_state[document_id] = 1
	for dependency_id: String in documents[document_id]["depends_on"]:
		if documents.has(dependency_id) and _visit_cycle(dependency_id, documents, visit_state):
			return true
	visit_state[document_id] = 2
	return false

static func _assert_index_waves(documents: Dictionary, test: TestFramework) -> void:
	var file := FileAccess.open(INDEX_PATH, FileAccess.READ)
	test.assert_true(file != null, "document index must be readable")
	if file == null:
		return
	var waves: Dictionary = {}
	var id_regex := RegEx.new()
	id_regex.compile("`([A-Z][A-Z0-9-]*-[0-9]{3})`")
	for line: String in file.get_as_text().split("\n"):
		if not line.begins_with("|"):
			continue
		var columns := line.split("|")
		if columns.size() < 4:
			continue
		var wave_text := str(columns[1]).strip_edges()
		if not wave_text.is_valid_int():
			continue
		var match_result := id_regex.search(str(columns[2]))
		if match_result == null:
			continue
		var document_id := match_result.get_string(1)
		test.assert_false(waves.has(document_id), "index must list %s exactly once" % document_id)
		waves[document_id] = int(wave_text)

	test.assert_equal(waves.size(), documents.size(), "index must list every normative document")
	for document_id: String in documents:
		test.assert_true(waves.has(document_id), "index must include %s" % document_id)
		if not waves.has(document_id):
			continue
		for dependency_id: String in documents[document_id]["depends_on"]:
			if not waves.has(dependency_id):
				continue
			test.assert_true(
				int(waves[dependency_id]) < int(waves[document_id]),
				"index wave of %s must follow %s" % [document_id, dependency_id]
			)
