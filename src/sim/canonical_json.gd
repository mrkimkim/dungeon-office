class_name CanonicalJson
extends RefCounted

## Deterministic JSON encoder for hashing and save checksums.
## It performs no I/O and sorts every Dictionary key lexicographically.

static func stringify(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			if is_nan(value) or is_inf(value):
				return "null"
			if value == floor(value):
				return str(int(value))
			return JSON.stringify(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return JSON.stringify(str(value))
		TYPE_ARRAY:
			var encoded_items: Array[String] = []
			for item: Variant in value:
				encoded_items.append(stringify(item))
			return "[" + ",".join(encoded_items) + "]"
		TYPE_DICTIONARY:
			var keys: Array = value.keys()
			keys.sort_custom(func(left: Variant, right: Variant) -> bool: return str(left) < str(right))
			var encoded_fields: Array[String] = []
			for key: Variant in keys:
				encoded_fields.append(JSON.stringify(str(key)) + ":" + stringify(value[key]))
			return "{" + ",".join(encoded_fields) + "}"
		_:
			push_error("CanonicalJson cannot encode type %s" % type_string(typeof(value)))
			return "null"

static func sha256(value: Variant) -> String:
	return stringify(value).sha256_text()
