class_name SimContract
extends RefCounted

## Stable runtime DTO names. Commands use strings so fixtures and save files remain
## readable; these enums provide a compile-time vocabulary for application code.

const SIM_VERSION: int = 1
const ROUND_STATE_SCHEMA: String = "RoundStateV1"

enum CommandType {
	MOVE,
	START,
	STORE,
	DELIVER,
	DISCARD,
	PAUSE,
	RESUME,
}

const COMMAND_MOVE: String = "move"
const COMMAND_START: String = "start"
const COMMAND_STORE: String = "store"
const COMMAND_DELIVER: String = "deliver"
const COMMAND_DISCARD: String = "discard"
const COMMAND_PAUSE: String = "pause"
const COMMAND_RESUME: String = "resume"

enum RejectReason {
	NONE,
	ROUND_NOT_RUNNING,
	WRONG_TICK,
	STALE_SEQUENCE,
	SEQUENCE_GAP,
	UNKNOWN_COMMAND,
	PAUSED,
	ALREADY_PAUSED,
	NOT_PAUSED,
	INVALID_SOURCE,
	ITEM_NOT_FOUND,
	INVALID_DESTINATION,
	FACILITY_UNAVAILABLE,
	FACILITY_BUSY,
	INVALID_RECIPE_INPUT,
	INPUT_INCOMPLETE,
	NO_IDLE_WORKER,
	NO_OUTPUT,
	INVENTORY_FULL,
	NOT_EQUIPMENT,
	NO_MATCHING_REQUEST,
}

const REJECT_NONE: String = "none"
const REJECT_ROUND_NOT_RUNNING: String = "round_not_running"
const REJECT_WRONG_TICK: String = "wrong_tick"
const REJECT_STALE_SEQUENCE: String = "stale_sequence"
const REJECT_SEQUENCE_GAP: String = "sequence_gap"
const REJECT_UNKNOWN_COMMAND: String = "unknown_command"
const REJECT_PAUSED: String = "paused"
const REJECT_ALREADY_PAUSED: String = "already_paused"
const REJECT_NOT_PAUSED: String = "not_paused"
const REJECT_INVALID_SOURCE: String = "invalid_source"
const REJECT_ITEM_NOT_FOUND: String = "item_not_found"
const REJECT_INVALID_DESTINATION: String = "invalid_destination"
const REJECT_FACILITY_UNAVAILABLE: String = "facility_unavailable"
const REJECT_FACILITY_BUSY: String = "facility_busy"
const REJECT_INVALID_RECIPE_INPUT: String = "invalid_recipe_input"
const REJECT_INPUT_INCOMPLETE: String = "input_incomplete"
const REJECT_NO_IDLE_WORKER: String = "no_idle_worker"
const REJECT_NO_OUTPUT: String = "no_output"
const REJECT_INVENTORY_FULL: String = "inventory_full"
const REJECT_NOT_EQUIPMENT: String = "not_equipment"
const REJECT_NO_MATCHING_REQUEST: String = "no_matching_request"

static func command(tick: int, sequence: int, type: String, payload: Dictionary = {}) -> Dictionary:
	return {
		"tick": tick,
		"sequence": sequence,
		"type": type,
		"payload": payload.duplicate(true),
	}

static func accepted(events: Array = []) -> Dictionary:
	return {"accepted": true, "reason": REJECT_NONE, "events": events}

static func rejected(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason, "events": []}
