class_name SaveRepository
extends RefCounted

const Canonical = preload("res://src/sim/canonical_json.gd")
const Profile = preload("res://src/app/profile_v1.gd")

const ENVELOPE_SCHEMA: String = "SaveEnvelopeV1"
const SNAPSHOT_SCHEMA: String = "RoundSnapshotV1"
const PROFILE_FILE: String = "profile.json"
const SNAPSHOT_FILE: String = "round_snapshot.json"

var _root_path: String

func _init(root_path: String = "user://save") -> void:
	_root_path = root_path.trim_suffix("/")
	if _root_path.begins_with("user://"):
		var user_directory := DirAccess.open("user://")
		if user_directory == null:
			push_error("cannot open app-private user directory")
			return
		var relative_root := _root_path.trim_prefix("user://")
		if not relative_root.is_empty():
			var create_error := user_directory.make_dir_recursive(relative_root)
			if create_error != OK:
				push_error("cannot create save directory (error %d)" % create_error)
		return
	var absolute_root := ProjectSettings.globalize_path(_root_path)
	var create_error := DirAccess.make_dir_recursive_absolute(absolute_root)
	if create_error != OK:
		push_error("cannot create save directory (error %d)" % create_error)

func save_profile(profile: Dictionary) -> Dictionary:
	return _atomic_write(PROFILE_FILE, profile)

func load_profile(round_ids: Array[String]) -> Dictionary:
	var primary := _read_payload(_path(PROFILE_FILE))
	if bool(primary.get("ok", false)):
		var primary_errors := Profile.validate(primary["value"], round_ids)
		if primary_errors.is_empty():
			return {"status": "ok", "value": primary["value"], "errors": []}
		primary["error"] = "; ".join(primary_errors)
	var backup := _read_payload(_path(PROFILE_FILE) + ".bak")
	if bool(backup.get("ok", false)):
		var backup_errors := Profile.validate(backup["value"], round_ids)
		if backup_errors.is_empty():
			return {
				"status": "recovered",
				"value": backup["value"],
				"errors": [str(primary.get("error", "primary profile missing"))],
			}
	if not FileAccess.file_exists(_path(PROFILE_FILE)) and not FileAccess.file_exists(_path(PROFILE_FILE) + ".bak"):
		return {"status": "missing", "value": {}, "errors": []}
	return {
		"status": "corrupt",
		"value": {},
		"errors": [str(primary.get("error", "profile corrupt")), str(backup.get("error", "backup corrupt"))],
	}

func save_snapshot(run_id: String, round_state: Dictionary) -> Dictionary:
	var snapshot := {
		"schema": SNAPSHOT_SCHEMA,
		"save_version": Profile.SAVE_VERSION,
		"sim_version": int(round_state.get("sim_version", 0)),
		"data_version": int(round_state.get("data_version", 0)),
		"run_id": run_id,
		"round_state": round_state.duplicate(true),
	}
	return _atomic_write(SNAPSHOT_FILE, snapshot)

func load_snapshot(expected_sim_version: int, expected_data_version: int) -> Dictionary:
	var primary := _read_payload(_path(SNAPSHOT_FILE))
	if bool(primary.get("ok", false)):
		var primary_errors := _validate_snapshot(primary["value"], expected_sim_version, expected_data_version)
		if primary_errors.is_empty():
			return {"status": "ok", "value": primary["value"], "errors": []}
		primary["error"] = "; ".join(primary_errors)
	var backup := _read_payload(_path(SNAPSHOT_FILE) + ".bak")
	if bool(backup.get("ok", false)):
		var backup_errors := _validate_snapshot(backup["value"], expected_sim_version, expected_data_version)
		if backup_errors.is_empty():
			return {
				"status": "recovered",
				"value": backup["value"],
				"errors": [str(primary.get("error", "primary snapshot missing"))],
			}
	if not FileAccess.file_exists(_path(SNAPSHOT_FILE)) and not FileAccess.file_exists(_path(SNAPSHOT_FILE) + ".bak"):
		return {"status": "missing", "value": {}, "errors": []}
	return {
		"status": "corrupt",
		"value": {},
		"errors": [str(primary.get("error", "snapshot corrupt")), str(backup.get("error", "backup corrupt"))],
	}

func delete_snapshot() -> Dictionary:
	var errors: Array[String] = []
	for suffix: String in ["", ".tmp", ".bak"]:
		var path := _path(SNAPSHOT_FILE) + suffix
		if FileAccess.file_exists(path):
			var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			if remove_error != OK:
				errors.append("cannot remove %s (error %d)" % [path, remove_error])
	return {"ok": errors.is_empty(), "errors": errors}

func _atomic_write(file_name: String, payload: Dictionary) -> Dictionary:
	var path := _path(file_name)
	var temporary_path := path + ".tmp"
	var backup_path := path + ".bak"
	var envelope := {
		"schema": ENVELOPE_SCHEMA,
		"checksum_sha256": Canonical.sha256(payload),
		"payload": payload,
	}
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot open temporary save (error %d)" % FileAccess.get_open_error()}
	file.store_string(JSON.stringify(envelope, "\t") + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return {"ok": false, "error": "cannot flush temporary save (error %d)" % write_error}

	var absolute_path := ProjectSettings.globalize_path(path)
	var absolute_temporary := ProjectSettings.globalize_path(temporary_path)
	var absolute_backup := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(backup_path):
		var remove_backup_error := DirAccess.remove_absolute(absolute_backup)
		if remove_backup_error != OK:
			return {"ok": false, "error": "cannot rotate save backup (error %d)" % remove_backup_error}
	if FileAccess.file_exists(path):
		var backup_error := DirAccess.rename_absolute(absolute_path, absolute_backup)
		if backup_error != OK:
			return {"ok": false, "error": "cannot create save backup (error %d)" % backup_error}
	var install_error := DirAccess.rename_absolute(absolute_temporary, absolute_path)
	if install_error != OK:
		if FileAccess.file_exists(backup_path) and not FileAccess.file_exists(path):
			DirAccess.rename_absolute(absolute_backup, absolute_path)
		return {"ok": false, "error": "cannot install save (error %d)" % install_error}
	return {"ok": true}

func _read_payload(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "%s is missing" % path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "cannot open %s" % path}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK or not parser.data is Dictionary:
		return {"ok": false, "error": "%s is not valid JSON" % path}
	var envelope: Dictionary = parser.data
	if str(envelope.get("schema", "")) != ENVELOPE_SCHEMA:
		return {"ok": false, "error": "%s has an unknown envelope" % path}
	if not envelope.get("payload") is Dictionary:
		return {"ok": false, "error": "%s payload must be an object" % path}
	var expected_checksum := str(envelope.get("checksum_sha256", ""))
	var actual_checksum := Canonical.sha256(envelope["payload"])
	if expected_checksum != actual_checksum:
		return {"ok": false, "error": "%s checksum mismatch" % path}
	return {"ok": true, "value": envelope["payload"]}

func _validate_snapshot(snapshot: Variant, expected_sim_version: int, expected_data_version: int) -> Array[String]:
	var errors: Array[String] = []
	if not snapshot is Dictionary:
		return ["snapshot root must be an object"]
	if str(snapshot.get("schema", "")) != SNAPSHOT_SCHEMA:
		errors.append("snapshot.schema must be RoundSnapshotV1")
	if int(snapshot.get("save_version", 0)) != Profile.SAVE_VERSION:
		errors.append("unsupported snapshot save_version")
	if int(snapshot.get("sim_version", 0)) != expected_sim_version:
		errors.append("snapshot sim_version mismatch")
	if int(snapshot.get("data_version", 0)) != expected_data_version:
		errors.append("snapshot data_version mismatch")
	if str(snapshot.get("run_id", "")).is_empty():
		errors.append("snapshot.run_id must not be empty")
	if not snapshot.get("round_state") is Dictionary:
		errors.append("snapshot.round_state must be an object")
	return errors

func _path(file_name: String) -> String:
	return _root_path + "/" + file_name
