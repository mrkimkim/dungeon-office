extends SceneTree

const TestFrameworkScript = preload("res://tests/test_framework.gd")
const TestDataRepository = preload("res://tests/test_data_repository.gd")
const TestSimulator = preload("res://tests/test_simulator.gd")
const TestSaveRepository = preload("res://tests/test_save_repository.gd")
const TestDocumentGraph = preload("res://tests/test_document_graph.gd")
const TestUi = preload("res://tests/test_ui.gd")

func _init() -> void:
	var test := TestFrameworkScript.new()
	print("Dungeon Office headless tests (Godot %s)" % Engine.get_version_info().get("string", "unknown"))
	TestDataRepository.run(test)
	TestSimulator.run(test)
	TestSaveRepository.run(test)
	TestDocumentGraph.run(test)
	TestUi.run(test)
	if test.has_failures():
		for failure: String in test.failures:
			printerr("FAIL: %s" % failure)
		printerr("FAILED: %d assertions, %d failures" % [test.assertion_count, test.failures.size()])
		quit(1)
		return
	print("PASS: %d assertions" % test.assertion_count)
	quit(0)
