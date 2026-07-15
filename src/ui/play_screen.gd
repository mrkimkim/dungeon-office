class_name PlayScreen
extends VBoxContainer

const RoundReadModelScript = preload("res://src/sim/round_read_model.gd")
const VisualCatalogScript = preload("res://src/ui/visual_catalog.gd")

signal source_requested(source: Dictionary)
signal destination_requested(destination: Dictionary)
signal start_requested(facility_id: String)
signal store_requested(facility_id: String)
signal pause_requested()

const FACILITY_ORDER: Array[String] = [
	"FAC_SUPPLY",
	"FAC_FURNACE",
	"FAC_TRASH",
	"FAC_WEAPON_BENCH",
	"FAC_SYNTH_BENCH",
	"FAC_ENHANCE_ANVIL",
]
const MINIMUM_TAP_SIZE: Vector2 = Vector2(44, 44)
const FACILITY_SPRITE_SIZE: int = 56
const ITEM_ICON_SIZE: int = 24

var _catalog: Dictionary = {}
var _round_definition: Dictionary = {}
var _round_state: Dictionary = {}
var _read_model: Dictionary = {}
var _selected_source: Dictionary = {}
var _round_interactive: bool = false
var _large_text_enabled: bool = false
var _color_assist_enabled: bool = false
var _structure_signature: String = ""


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)
	clip_contents = true


func set_display_options(settings: Dictionary) -> void:
	var large_text := bool(settings.get("large_text_enabled", false))
	var color_assist := bool(settings.get("color_assist_enabled", false))
	if large_text != _large_text_enabled or color_assist != _color_assist_enabled:
		_structure_signature = ""
	_large_text_enabled = large_text
	_color_assist_enabled = color_assist


func render(
	round_definition: Dictionary,
	round_state: Dictionary,
	catalog: Dictionary,
	selected_source: Dictionary,
	feedback: String
) -> void:
	_round_definition = round_definition
	_round_state = round_state
	_catalog = catalog
	_selected_source = selected_source.duplicate(true)
	_read_model = RoundReadModelScript.build(
		_round_state,
		_round_definition,
		_catalog,
		_selected_source
	)
	_round_interactive = (
		str(_round_state.get("status", "")) == "running"
		and not bool(_round_state.get("paused", false))
	)
	var next_signature := _make_structure_signature()
	if next_signature == _structure_signature and get_child_count() > 0:
		_update_dynamic_text(feedback)
		return
	_structure_signature = next_signature
	_clear()
	_build_header()
	_build_feedback(feedback)
	_build_requests()
	_build_facilities()
	_build_worker_and_inventory()
	_build_destinations()
	_update_dynamic_text(feedback)


func _clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()


func _make_structure_signature() -> String:
	var parts: Array[String] = [
		str(_round_definition.get("id", "")),
		str(_round_state.get("status", "")),
		str(bool(_round_state.get("paused", false))),
		JSON.stringify(_selected_source),
		str(_round_state.get("waiting_requests", []).size()),
		str(_large_text_enabled),
		str(_color_assist_enabled),
	]
	for request_value: Variant in _round_state.get("active_requests", []):
		var request: Dictionary = request_value
		parts.append("request:%s:%s:%d" % [
			request.get("event_id", ""),
			request.get("item_id", ""),
			int(request.get("required_level", 0)),
		])
	var facility_ids: Array = _round_state.get("facilities", {}).keys()
	facility_ids.sort()
	for facility_id_value: Variant in facility_ids:
		var facility_id := str(facility_id_value)
		var facility: Dictionary = _round_state["facilities"][facility_id]
		parts.append("facility:%s:%s" % [facility_id, facility.get("status", "")])
		for input_value: Variant in facility.get("inputs", []):
			parts.append("input:%s:%d" % [
				input_value.get("item_id", ""),
				int(input_value.get("enhancement_level", 0)),
			])
		if facility.get("output") is Dictionary:
			parts.append("output:%s:%d" % [
				facility["output"].get("item_id", ""),
				int(facility["output"].get("enhancement_level", 0)),
			])
	for item_value: Variant in _round_state.get("inventory", []):
		if item_value == null:
			parts.append("inventory:-")
		else:
			parts.append("inventory:%s:%d" % [
				item_value.get("item_id", ""),
				int(item_value.get("enhancement_level", 0)),
			])
	for worker_value: Variant in _round_state.get("workers", []):
		parts.append("worker:%s" % worker_value.get("facility_id", ""))
	return "|".join(parts)


func _update_dynamic_text(feedback: String) -> void:
	var tick_rate := maxi(1, int(_catalog.get("rules", {}).get("tick_rate", 20)))
	var remaining_ticks := maxi(
		0,
		int(_round_state.get("deadline_ticks", 0)) - int(_round_state.get("tick", 0))
	)
	var timer_label := find_child("RoundTimerLabel", true, false) as Label
	if timer_label != null:
		timer_label.text = "%s %s · %s%s" % [
			str(_round_definition.get("id", "?")),
			str(_round_definition.get("display_name", "")),
			_format_seconds(ceili(float(remaining_ticks) / float(tick_rate))),
			" · 일시정지" if bool(_round_state.get("paused", false)) else "",
		]
	var score_label := find_child("ScoreLabel", true, false) as Label
	if score_label != null:
		var cutlines: Array = _round_definition.get("cutlines", [])
		var cutline_text := ""
		if cutlines.size() >= 3:
			cutline_text = " · ★%d ★★%d ★★★%d" % [
				int(cutlines[0]),
				int(cutlines[1]),
				int(cutlines[2]),
			]
		score_label.text = "점수 %d%s" % [int(_round_state.get("score", 0)), cutline_text]
	var selection_label := find_child("SelectedSourceLabel", true, false) as Label
	if selection_label != null:
		selection_label.text = (
			"선택 없음"
			if _selected_source.is_empty()
			else "선택: %s" % _source_description(_selected_source)
		)
	var feedback_label := find_child("FeedbackLabel", true, false) as Label
	if feedback_label != null:
		feedback_label.text = (
			"아이템을 고른 뒤 시설·납품·수납·파기를 탭하세요."
			if feedback.strip_edges().is_empty()
			else feedback.strip_edges()
		)
	var waiting_label := find_child("WaitingRequestLabel", true, false) as Label
	if waiting_label != null:
		waiting_label.text = "대기 %d" % _round_state.get("waiting_requests", []).size()
	for request_value: Variant in _round_state.get("active_requests", []):
		var request: Dictionary = request_value
		var request_timer := find_child(
			"RequestTimer_%s" % str(request.get("event_id", "unknown")),
			true,
			false
		) as Label
		if request_timer != null:
			request_timer.text = "%d점 · %d초" % [
				int(request.get("score", 0)),
				ceili(float(maxi(0, int(request.get("remaining_patience_ticks", 0)))) / float(tick_rate)),
			]
	for facility_id_value: Variant in _round_state.get("facilities", {}).keys():
		var facility_id := str(facility_id_value)
		var facility: Dictionary = _round_state["facilities"][facility_id]
		var status_label := find_child("FacilityStatus_%s" % facility_id, true, false) as Label
		if status_label != null:
			status_label.text = _facility_status_text(facility)
			status_label.modulate = _status_color(str(facility.get("status", "empty")))
	var workers: Array = _round_state.get("workers", [])
	var idle_workers := 0
	for worker_value: Variant in workers:
		if str(worker_value.get("facility_id", "")).is_empty():
			idle_workers += 1
	var worker_label := find_child("WorkerStatusLabel", true, false) as Label
	if worker_label != null:
		worker_label.text = "일꾼 %d/%d 유휴 · 인벤토리" % [idle_workers, workers.size()]


func _build_header() -> void:
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 44)
	header.add_theme_constant_override("separation", 4)
	add_child(header)

	var summary := VBoxContainer.new()
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_theme_constant_override("separation", 0)
	header.add_child(summary)

	var tick_rate := maxi(1, int(_catalog.get("rules", {}).get("tick_rate", 20)))
	var remaining_ticks := maxi(
		0,
		int(_round_state.get("deadline_ticks", 0)) - int(_round_state.get("tick", 0))
	)
	var remaining_seconds := ceili(float(remaining_ticks) / float(tick_rate))
	var paused_suffix := " · 일시정지" if bool(_round_state.get("paused", false)) else ""
	var timer_label := _add_label(
		summary,
		"%s %s · %s%s" % [
			str(_round_definition.get("id", "?")),
			str(_round_definition.get("display_name", "")),
			_format_seconds(remaining_seconds),
			paused_suffix,
		],
		15
	)
	timer_label.name = "RoundTimerLabel"

	var cutlines: Array = _round_definition.get("cutlines", [])
	var cutline_text := ""
	if cutlines.size() >= 3:
		cutline_text = " · ★%d ★★%d ★★★%d" % [
			int(cutlines[0]),
			int(cutlines[1]),
			int(cutlines[2]),
		]
	var score_label := _add_label(
		summary,
		"점수 %d%s" % [int(_round_state.get("score", 0)), cutline_text],
		12,
		Color("d8c7aa")
	)
	score_label.name = "ScoreLabel"

	var pause_button := _make_button(
		"재개" if bool(_round_state.get("paused", false)) else "정지",
		Callable(self, "_emit_pause")
	)
	pause_button.name = "PauseButton"
	pause_button.custom_minimum_size = Vector2(58, 44)
	pause_button.disabled = not bool(
		_read_model.get("commands", {}).get("can_pause", false)
	)
	header.add_child(pause_button)


func _build_feedback(feedback: String) -> void:
	var selected_text := "선택 없음"
	if not _selected_source.is_empty():
		selected_text = "선택: %s" % _source_description(_selected_source)
	var selection_label := _add_label(self, selected_text, 12, Color("efe1c6"))
	selection_label.name = "SelectedSourceLabel"
	selection_label.custom_minimum_size = Vector2(0, 18)
	selection_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	selection_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	var message := feedback.strip_edges()
	if message.is_empty():
		message = "아이템을 고른 뒤 시설·납품·수납·파기를 탭하세요."
	var feedback_label := _add_label(self, message, 12, Color("f2bd69"))
	feedback_label.name = "FeedbackLabel"
	feedback_label.custom_minimum_size = Vector2(0, 40 if _large_text_enabled else 34)
	feedback_label.max_lines_visible = 2
	feedback_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _build_requests() -> void:
	var title_row := HBoxContainer.new()
	add_child(title_row)
	var request_title := _add_label(title_row, "의뢰", 13)
	request_title.name = "RequestTitleLabel"
	request_title.custom_minimum_size = Vector2(48, 20)
	request_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	var waiting_count := int(_round_state.get("waiting_requests", []).size())
	if waiting_count > 0:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_row.add_child(spacer)
		var waiting_label := _add_label(title_row, "대기 %d" % waiting_count, 11, Color("b8aa94"))
		waiting_label.name = "WaitingRequestLabel"

	var request_row := HBoxContainer.new()
	request_row.add_theme_constant_override("separation", 4)
	request_row.custom_minimum_size = Vector2(0, 54)
	add_child(request_row)
	var active_requests: Array = _round_state.get("active_requests", [])
	if active_requests.is_empty():
		var empty_panel := _make_panel()
		empty_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		request_row.add_child(empty_panel)
		_add_label(empty_panel, "현재 의뢰 없음", 12, Color("a99d8a"), HORIZONTAL_ALIGNMENT_CENTER)
		return

	var tick_rate := maxi(1, int(_catalog.get("rules", {}).get("tick_rate", 20)))
	for request_value: Variant in active_requests:
		var request: Dictionary = request_value
		var panel := _make_panel()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		request_row.add_child(panel)
		var request_content := HBoxContainer.new()
		request_content.add_theme_constant_override("separation", 2)
		panel.add_child(request_content)
		var request_icon := _make_texture_decoration(
			VisualCatalogScript.item_texture(str(request.get("item_id", ""))),
			ITEM_ICON_SIZE,
			0.9
		)
		if request_icon != null:
			request_icon.name = "RequestIcon_%s" % str(request.get("event_id", "unknown"))
			request_content.add_child(request_icon)
		var request_box := VBoxContainer.new()
		request_box.add_theme_constant_override("separation", 0)
		request_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		request_content.add_child(request_box)
		var request_definition := _find_entry(
			_catalog.get("requests", []),
			str(request.get("request_id", ""))
		)
		var forecast := bool(request_definition.get("forecast", false))
		var item_text := _item_name(
			str(request.get("item_id", "")),
			int(request.get("required_level", 0))
		)
		var request_item := _add_label(
			request_box,
			("[예고] " if forecast else "") + item_text,
			11,
			Color("f3e6ce"),
			HORIZONTAL_ALIGNMENT_CENTER
		)
		request_item.name = "RequestItem_%s" % str(request.get("event_id", "unknown"))
		var patience_seconds := ceili(
			float(maxi(0, int(request.get("remaining_patience_ticks", 0)))) / float(tick_rate)
		)
		var request_timer := _add_label(
			request_box,
			"%d점 · %d초" % [int(request.get("score", 0)), patience_seconds],
			10,
			Color("cbbda5"),
			HORIZONTAL_ALIGNMENT_CENTER
		)
		request_timer.name = "RequestTimer_%s" % str(request.get("event_id", "unknown"))


func _build_facilities() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)

	for facility_id: String in FACILITY_ORDER:
		_build_facility_cell(grid, facility_id)


func _build_facility_cell(parent: Container, facility_id: String) -> void:
	var panel := _make_panel()
	panel.name = "FacilityCell_%s" % facility_id
	panel.custom_minimum_size = Vector2(100, 104)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	_add_facility_sprite(panel, facility_id)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	var facility_name_label := _add_label(
		box,
		_facility_name(facility_id),
		11,
		Color("f1dfc1"),
		HORIZONTAL_ALIGNMENT_CENTER
	)
	facility_name_label.name = "FacilityName_%s" % facility_id

	if facility_id == "FAC_SUPPLY":
		_build_supply_cell(box)
		return
	if facility_id == "FAC_TRASH":
		_add_label(box, "선택 아이템 제거", 9, Color("b9aa95"), HORIZONTAL_ALIGNMENT_CENTER)
		var discard_button := _make_button(
			"파기",
			Callable(self, "_emit_destination").bind({"kind": "trash"}),
			10
		)
		discard_button.name = "DestinationTrash"
		discard_button.disabled = not _can_discard_selection()
		box.add_child(discard_button)
		return

	var facilities: Dictionary = _round_state.get("facilities", {})
	if not facilities.has(facility_id):
		_add_label(box, "미설치", 11, Color("82796d"), HORIZONTAL_ALIGNMENT_CENTER)
		return

	var facility: Dictionary = facilities[facility_id]
	var status := str(facility.get("status", "empty"))
	var status_label := _add_label(
		box,
		_facility_status_text(facility),
		9,
		_status_color(status),
		HORIZONTAL_ALIGNMENT_CENTER
	)
	status_label.name = "FacilityStatus_%s" % facility_id

	var item_row := HBoxContainer.new()
	item_row.add_theme_constant_override("separation", 2)
	item_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(item_row)
	for input_index: int in range(facility.get("inputs", []).size()):
		var input_item: Dictionary = facility["inputs"][input_index]
		var input_source := {
			"kind": "facility_input",
			"facility_id": facility_id,
			"slot": input_index,
		}
		var input_button := _make_source_button(
			_item_name(
				str(input_item.get("item_id", "")),
				int(input_item.get("enhancement_level", 0))
			),
			input_source,
			9
		)
		input_button.name = "SourceInput_%s_%d" % [facility_id, input_index]
		_decorate_item_button(
			input_button,
			str(input_item.get("item_id", "")),
			"ItemIcon_%s" % input_button.name,
			9
		)
		item_row.add_child(input_button)

	if status == "output" and facility.get("output") is Dictionary:
		var output: Dictionary = facility["output"]
		var output_source := {"kind": "facility_output", "facility_id": facility_id}
		var output_button := _make_source_button(
			_item_name(
				str(output.get("item_id", "")),
				int(output.get("enhancement_level", 0))
			),
			output_source,
			9
		)
		output_button.name = "SourceOutput_%s" % facility_id
		_decorate_item_button(
			output_button,
			str(output.get("item_id", "")),
			"ItemIcon_%s" % output_button.name,
			9
		)
		item_row.add_child(output_button)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 2)
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(action_row)
	if status not in ["working", "output"]:
		var destination := {"kind": "facility_input", "facility_id": facility_id}
		var destination_button := _make_button(
			"투입",
			Callable(self, "_emit_destination").bind(destination),
			9
		)
		destination_button.name = "Destination_%s" % facility_id
		destination_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		destination_button.disabled = not _can_move_selection_to({
			"kind": "facility_input",
			"facility_id": facility_id,
		})
		action_row.add_child(destination_button)
	if status == "ready":
		var start_button := _make_button(
			"시작",
			Callable(self, "_emit_start").bind(facility_id),
			9
		)
		start_button.name = "Start_%s" % facility_id
		start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		start_button.disabled = not _facility_command_available(facility_id, "can_start")
		action_row.add_child(start_button)
	elif status == "output":
		var store_button := _make_button(
			"수납",
			Callable(self, "_emit_store").bind(facility_id),
			9
		)
		store_button.name = "Store_%s" % facility_id
		store_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		store_button.disabled = not _facility_command_available(facility_id, "can_store")
		action_row.add_child(store_button)


func _build_supply_cell(parent: VBoxContainer) -> void:
	_add_label(parent, "공급 슬롯", 9, Color("b9aa95"), HORIZONTAL_ALIGNMENT_CENTER)
	var supply_grid := GridContainer.new()
	supply_grid.columns = 2
	supply_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	supply_grid.add_theme_constant_override("h_separation", 2)
	supply_grid.add_theme_constant_override("v_separation", 2)
	parent.add_child(supply_grid)
	for item_id_value: Variant in _round_definition.get("supply_items", []):
		var item_id := str(item_id_value)
		var source := {"kind": "supply", "item_id": item_id}
		var button := _make_source_button(_item_name(item_id, 0), source, 9)
		button.name = "SourceSupply_%s" % item_id
		_decorate_item_button(
			button,
			item_id,
			"ItemIcon_%s" % button.name,
			9
		)
		supply_grid.add_child(button)


func _build_worker_and_inventory() -> void:
	var workers: Array = _round_state.get("workers", [])
	var idle_workers := 0
	for worker_value: Variant in workers:
		if str(worker_value.get("facility_id", "")).is_empty():
			idle_workers += 1
	var worker_label := _add_label(
		self,
		"일꾼 %d/%d 유휴 · 인벤토리" % [idle_workers, workers.size()],
		12,
		Color("d8c7aa")
	)
	worker_label.name = "WorkerStatusLabel"

	var inventory_row := HBoxContainer.new()
	inventory_row.add_theme_constant_override("separation", 4)
	inventory_row.custom_minimum_size = Vector2(0, 44)
	add_child(inventory_row)
	var inventory: Array = _round_state.get("inventory", [])
	var capacity := int(_round_definition.get("inventory_capacity", inventory.size()))
	for slot: int in range(capacity):
		var item_value: Variant = inventory[slot] if slot < inventory.size() else null
		if item_value == null:
			var empty_button := _make_button(
				"%d\n빈칸" % (slot + 1),
				Callable(self, "_emit_destination").bind({"kind": "inventory"}),
				9
			)
			empty_button.name = "DestinationInventory_%d" % slot
			empty_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			empty_button.disabled = not _can_move_selection_to({"kind": "inventory"})
			inventory_row.add_child(empty_button)
			continue
		var item: Dictionary = item_value
		var source := {"kind": "inventory", "slot": slot}
		var item_button := _make_source_button(
			"%d\n%s" % [
				slot + 1,
				_item_name(
					str(item.get("item_id", "")),
					int(item.get("enhancement_level", 0))
				),
			],
			source,
			9
		)
		item_button.name = "SourceInventory_%d" % slot
		item_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_decorate_item_button(
			item_button,
			str(item.get("item_id", "")),
			"ItemIcon_%s" % item_button.name,
			9
		)
		inventory_row.add_child(item_button)


func _build_destinations() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.custom_minimum_size = Vector2(0, 44)
	add_child(row)

	var inventory_button := _make_button(
		"인벤토리",
		Callable(self, "_emit_destination").bind({"kind": "inventory"}),
		10
	)
	inventory_button.name = "DestinationInventory"
	inventory_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_button.disabled = not _can_move_selection_to({"kind": "inventory"})
	row.add_child(inventory_button)

	var delivery_button := _make_button(
		"납품",
		Callable(self, "_emit_destination").bind({"kind": "delivery"}),
		10
	)
	delivery_button.name = "DestinationDelivery"
	delivery_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delivery_button.disabled = not _can_deliver_selection()
	_decorate_button_with_texture(
		delivery_button,
		VisualCatalogScript.facility_texture("FAC_DELIVERY"),
		"FacilityActionIcon_FAC_DELIVERY",
		10
	)
	row.add_child(delivery_button)

	var trash_button := _make_button(
		"파기",
		Callable(self, "_emit_destination").bind({"kind": "trash"}),
		10
	)
	trash_button.name = "DestinationTrashAction"
	trash_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trash_button.disabled = not _can_discard_selection()
	row.add_child(trash_button)

	var cancel_button := _make_button(
		"선택 취소",
		Callable(self, "_emit_destination").bind({"kind": "cancel"}),
		10
	)
	cancel_button.name = "DestinationCancel"
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_button.disabled = _selected_source.is_empty()
	row.add_child(cancel_button)


func _add_facility_sprite(panel: PanelContainer, facility_id: String) -> void:
	var texture := VisualCatalogScript.facility_texture(facility_id)
	if texture == null:
		return
	var installed: bool = (
		facility_id in ["FAC_SUPPLY", "FAC_TRASH"]
		or _round_state.get("facilities", {}).has(facility_id)
	)
	var layer := CenterContainer.new()
	layer.name = "FacilityArtLayer_%s" % facility_id
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(layer)
	var sprite := _make_texture_decoration(
		texture,
		FACILITY_SPRITE_SIZE,
		0.62 if installed else 0.18
	)
	if sprite == null:
		return
	sprite.name = "FacilitySprite_%s" % facility_id
	layer.add_child(sprite)


func _decorate_item_button(
	button: Button,
	item_id: String,
	icon_name: String,
	font_size: int
) -> void:
	_decorate_button_with_texture(
		button,
		VisualCatalogScript.item_texture(item_id),
		icon_name,
		font_size
	)


func _decorate_button_with_texture(
	button: Button,
	texture: Texture2D,
	icon_name: String,
	font_size: int
) -> void:
	if texture == null:
		return
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var visible_text := button.text
	var icon := _make_texture_decoration(texture, ITEM_ICON_SIZE, 0.92)
	if icon == null:
		return
	icon.name = icon_name
	button.add_child(icon)
	icon.anchor_left = 0.0
	icon.anchor_top = 0.5
	icon.anchor_right = 0.0
	icon.anchor_bottom = 0.5
	icon.offset_left = 2.0
	icon.offset_top = -float(ITEM_ICON_SIZE) / 2.0
	icon.offset_right = 2.0 + float(ITEM_ICON_SIZE)
	icon.offset_bottom = float(ITEM_ICON_SIZE) / 2.0

	# Keep Button.text as the semantic/test contract while drawing an outlined copy
	# above the decorative icon. This avoids changing minimum widths in the dense
	# 3x2 mobile grid and keeps disabled buttons visibly disabled.
	for color_name: String in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_hover_pressed_color",
		"font_focus_color",
		"font_disabled_color",
	]:
		button.add_theme_color_override(color_name, Color.TRANSPARENT)
	var text_overlay := Label.new()
	text_overlay.name = "%s_Text" % icon_name
	text_overlay.text = visible_text
	text_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_overlay.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_overlay.max_lines_visible = 2
	text_overlay.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_overlay.add_theme_font_size_override("font_size", _scaled_font_size(font_size))
	text_overlay.add_theme_constant_override("outline_size", 2)
	text_overlay.add_theme_color_override("font_outline_color", Color("241c19"))
	text_overlay.modulate = Color("91877a") if button.disabled else Color("f4e7d0")
	button.add_child(text_overlay)
	text_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _make_texture_decoration(
	texture: Texture2D,
	size: int,
	alpha: float
) -> TextureRect:
	if texture == null:
		return null
	var decoration := TextureRect.new()
	decoration.texture = texture
	decoration.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.custom_minimum_size = Vector2(size, size)
	decoration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	decoration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	decoration.modulate = Color(1.0, 1.0, 1.0, alpha)
	return decoration


func _make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("2c2631")
	style.border_color = Color("695462")
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 3
	style.corner_radius_top_left = 9
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_left = 9
	style.corner_radius_bottom_right = 9
	style.content_margin_left = 3
	style.content_margin_top = 2
	style.content_margin_right = 3
	style.content_margin_bottom = 4
	style.shadow_color = Color(0.02, 0.015, 0.025, 0.65)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
	style.anti_aliasing = true
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_button(text: String, callback: Callable, font_size: int = 11) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = MINIMUM_TAP_SIZE
	button.add_theme_font_size_override("font_size", _scaled_font_size(font_size))
	button.pressed.connect(callback)
	return button


func _make_source_button(text: String, source: Dictionary, font_size: int = 10) -> Button:
	var selected_prefix := ("▣ " if _color_assist_enabled else "● ") if _is_selected(source) else ""
	var button := _make_button(
		selected_prefix + text,
		Callable(self, "_emit_source").bind(source.duplicate(true)),
		font_size
	)
	button.disabled = not _round_interactive
	return button


func _add_label(
	parent: Node,
	text: String,
	font_size: int,
	color: Color = Color("f4e7d0"),
	alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", _scaled_font_size(font_size))
	label.modulate = color
	parent.add_child(label)
	return label


func _emit_source(source: Dictionary) -> void:
	source_requested.emit(source.duplicate(true))


func _emit_destination(destination: Dictionary) -> void:
	destination_requested.emit(destination.duplicate(true))


func _emit_start(facility_id: String) -> void:
	start_requested.emit(facility_id)


func _emit_store(facility_id: String) -> void:
	store_requested.emit(facility_id)


func _emit_pause() -> void:
	pause_requested.emit()


func _is_selected(source: Dictionary) -> bool:
	if str(source.get("kind", "")) != str(_selected_source.get("kind", "")):
		return false
	match str(source.get("kind", "")):
		"supply":
			return str(source.get("item_id", "")) == str(_selected_source.get("item_id", ""))
		"inventory":
			return int(source.get("slot", -1)) == int(_selected_source.get("slot", -2))
		"facility_input":
			return (
				str(source.get("facility_id", "")) == str(_selected_source.get("facility_id", ""))
				and int(source.get("slot", -1)) == int(_selected_source.get("slot", -2))
			)
		"facility_output":
			return str(source.get("facility_id", "")) == str(
				_selected_source.get("facility_id", "")
			)
		_:
			return false


func _source_description(source: Dictionary) -> String:
	match str(source.get("kind", "")):
		"supply":
			return _item_name(str(source.get("item_id", "")), 0)
		"inventory":
			return "인벤토리 %d번" % (int(source.get("slot", -1)) + 1)
		"facility_input":
			return "%s 투입물" % _facility_name(str(source.get("facility_id", "")))
		"facility_output":
			return "%s 산출물" % _facility_name(str(source.get("facility_id", "")))
		_:
			return "알 수 없는 선택"


func _facility_status_text(facility: Dictionary) -> String:
	var status := str(facility.get("status", "empty"))
	var prefix := ""
	if _color_assist_enabled:
		prefix = str({
			"empty": "○ ",
			"input": "◐ ",
			"ready": "▶ ",
			"working": "… ",
			"output": "✓ ",
		}.get(status, "? "))
	match status:
		"empty":
			return prefix + "비어 있음"
		"input":
			return prefix + "부분 투입"
		"ready":
			return prefix + "시작 가능"
		"working":
			return prefix + "작업 %d틱" % maxi(0, int(facility.get("remaining_ticks", 0)))
		"output":
			var overheat_ticks := int(facility.get("overheat_remaining_ticks", 0))
			return prefix + ("완료 · 과열 %d틱" % overheat_ticks if overheat_ticks > 0 else "완료")
		_:
			return prefix + status


func _status_color(status: String) -> Color:
	match status:
		"ready":
			return Color("9cd68b")
		"working":
			return Color("8ec5e8")
		"output":
			return Color("f0bf6a")
		_:
			return Color("b9aa95")


func _scaled_font_size(base_size: int) -> int:
	return int(round(float(base_size) * (1.25 if _large_text_enabled else 1.0)))


func _item_name(item_id: String, enhancement_level: int) -> String:
	var definition := _find_entry(_catalog.get("items", []), item_id)
	var display_name := str(definition.get("display_name", item_id))
	if enhancement_level > 0:
		display_name += " +%d" % enhancement_level
	return display_name


func _facility_name(facility_id: String) -> String:
	var definition := _find_entry(_catalog.get("facilities", []), facility_id)
	return str(definition.get("display_name", facility_id))


func _selected_actions() -> Dictionary:
	var actions: Variant = _read_model.get("selected_actions", {})
	return actions if actions is Dictionary else {}


func _can_move_selection_to(destination: Dictionary) -> bool:
	if not _round_interactive or not bool(_selected_actions().get("has_selection", false)):
		return false
	for destination_value: Variant in _selected_actions().get("move_destinations", []):
		if not destination_value is Dictionary:
			continue
		var candidate: Dictionary = destination_value
		if str(candidate.get("kind", "")) != str(destination.get("kind", "")):
			continue
		if str(destination.get("kind", "")) != "facility_input":
			return true
		if str(candidate.get("facility_id", "")) == str(destination.get("facility_id", "")):
			return true
	return false


func _can_deliver_selection() -> bool:
	return _round_interactive and bool(_selected_actions().get("can_deliver", false))


func _can_discard_selection() -> bool:
	return _round_interactive and bool(_selected_actions().get("can_discard", false))


func _facility_command_available(facility_id: String, key: String) -> bool:
	if not _round_interactive:
		return false
	for facility_value: Variant in _read_model.get("facilities", []):
		if not facility_value is Dictionary:
			continue
		var facility: Dictionary = facility_value
		if str(facility.get("facility_id", "")) == facility_id:
			return bool(facility.get(key, false))
	return false


func _format_seconds(seconds: int) -> String:
	var minutes := floori(float(seconds) / 60.0)
	return "%d:%02d" % [minutes, seconds % 60]


func _find_entry(entries: Array, id: String) -> Dictionary:
	for entry_value: Variant in entries:
		if entry_value is Dictionary and str(entry_value.get("id", "")) == id:
			return entry_value
	return {}
