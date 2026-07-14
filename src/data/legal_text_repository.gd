class_name LegalTextRepository
extends RefCounted

const PRIVACY_PATH: String = "res://site/privacy/index.md"
const LICENSE_PATHS: Array[String] = [
	"res://site/licenses/index.md",
	"res://site/licenses/android-runtime.md",
	"res://site/licenses/godot-copyright.md",
]
const SUPPORT_EMAIL: String = "2020promoking@gmail.com"

func load_privacy() -> Dictionary:
	return _load_markdown(PRIVACY_PATH, "개인정보처리방침을 불러올 수 없습니다.")

func load_licenses() -> Dictionary:
	var documents: Array[String] = []
	for path: String in LICENSE_PATHS:
		var result := _load_markdown(path, "오픈소스 라이선스 고지를 불러올 수 없습니다.")
		if not bool(result.get("ok", false)):
			return result
		documents.append(str(result["text"]))
	return {
		"ok": true,
		"text": "\n\n".join(documents),
		"path": ",".join(LICENSE_PATHS),
	}

static func strip_front_matter(source: String) -> String:
	var normalized := source.replace("\r\n", "\n")
	if not normalized.begins_with("---\n"):
		return normalized.strip_edges()
	var closing_index := normalized.find("\n---\n", 4)
	if closing_index < 0:
		return normalized.strip_edges()
	return normalized.substr(closing_index + 5).strip_edges()

static func _load_markdown(path: String, fallback: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "text": fallback, "path": path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "text": fallback, "path": path}
	var text := strip_front_matter(file.get_as_text())
	if text.is_empty():
		return {"ok": false, "text": fallback, "path": path}
	return {"ok": true, "text": text, "path": path}
