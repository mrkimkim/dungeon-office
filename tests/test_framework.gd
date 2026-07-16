class_name TestFramework
extends RefCounted

var assertion_count: int = 0
var failures: Array[String] = []

func assert_true(value: bool, message: String) -> void:
	assertion_count += 1
	if not value:
		failures.append(message)

func assert_false(value: bool, message: String) -> void:
	assert_true(not value, message)

func assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	assertion_count += 1
	if actual != expected:
		failures.append("%s\n  expected: %s\n  actual:   %s" % [message, expected, actual])

func assert_contains(haystack: String, needle: String, message: String) -> void:
	assertion_count += 1
	if needle not in haystack:
		failures.append("%s\n  missing: %s" % [message, needle])

func fail(message: String) -> void:
	assertion_count += 1
	failures.append(message)

func has_failures() -> bool:
	return not failures.is_empty()
