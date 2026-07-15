class_name PlayScreen
extends VBoxContainer

const RoundReadModelScript = preload("res://src/sim/round_read_model.gd")
const RoundSimulatorScript = preload("res://src/sim/round_simulator.gd")
const SimContractScript = preload("res://src/sim/sim_contract.gd")
const VisualCatalogScript = preload("res://src/ui/visual_catalog.gd")

signal source_requested(source: Dictionary)
signal destination_requested(destination: Dictionary)
signal item_drop_requested(source: Dictionary, destination: Dictionary)
signal recipe_requested(item_id: String, enhancement_level: int)
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
const FACILITY_SPRITE_SIZE: int = 82
const ITEM_ICON_SIZE: int = 34
const DRAG_PREVIEW_ICON_SIZE: int = 44
const FACILITY_GRID_HEIGHT: int = 294
const DRAG_PAYLOAD_TYPE: String = "dungeon_office/item_source_v1"

var _catalog: Dictionary = {}
var _round_definition: Dictionary = {}
var _round_state: Dictionary = {}
var _read_model: Dictionary = {}
var _selected_source: Dictionary = {}
var _round_interactive: bool = false
var _large_text_enabled: bool = false
var _color_assist_enabled: bool = false
var _structure_signature: String = ""
var _drop_target_roots: Array[Control] = []


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 5)
	clip_contents = false


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
	var active_drag_data: Variant = _active_drag_data()
	if (
		get_child_count() > 0
		and active_drag_data is Dictionary
	):
		_update_dynamic_text(feedback)
		_set_drop_target_highlights(active_drag_data)
		return
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
	_update_dynamic_text(feedback)


func _clear() -> void:
	_drop_target_roots.clear()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()


func _exit_tree() -> void:
	if get_viewport() != null and get_viewport().gui_is_dragging():
		get_viewport().gui_cancel_drag()


func _notification(what: int) -> void:
	if not is_inside_tree():
		return
	if what == NOTIFICATION_DRAG_BEGIN:
		_set_drop_target_highlights(get_viewport().gui_get_drag_data())
	elif what == NOTIFICATION_DRAG_END:
		_reset_drop_target_highlights()


func _active_drag_data() -> Variant:
	if not is_inside_tree():
		return null
	var viewport := get_viewport()
	if viewport == null or not viewport.gui_is_dragging():
		return null
	return viewport.gui_get_drag_data()


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
		timer_label.text = "%s  ·  %s%s" % [
			str(_round_definition.get("id", "?")),
			_format_seconds(ceili(float(remaining_ticks) / float(tick_rate))),
			"  ⏸" if bool(_round_state.get("paused", false)) else "",
		]
	var score_label := find_child("ScoreLabel", true, false) as Label
	if score_label != null:
		score_label.text = _score_summary_text()
	var selection_label := find_child("SelectedSourceLabel", true, false) as Label
	if selection_label != null:
		selection_label.visible = not _selected_source.is_empty()
		selection_label.text = "손에 든 아이템  ·  %s" % _source_description(_selected_source)
	var feedback_label := find_child("FeedbackLabel", true, false) as Label
	if feedback_label != null:
		feedback_label.visible = not feedback.strip_edges().is_empty()
		feedback_label.text = feedback.strip_edges()
	var waiting_label := find_child("WaitingRequestLabel", true, false) as Label
	if waiting_label != null:
		waiting_label.text = "+%d" % _round_state.get("waiting_requests", []).size()
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
		worker_label.text = _worker_summary_text(idle_workers, workers.size())


func _build_header() -> void:
	var header_panel := _make_panel("hud")
	header_panel.name = "PlayHudPanel"
	header_panel.custom_minimum_size = Vector2(0, 48)
	add_child(header_panel)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	header_panel.add_child(header)

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
	var paused_suffix := "  ⏸" if bool(_round_state.get("paused", false)) else ""
	var timer_label := _add_label(
		summary,
		"%s  ·  %s%s" % [
			str(_round_definition.get("id", "?")),
			_format_seconds(remaining_seconds),
			paused_suffix,
		],
		16,
		Color("fff1cf")
	)
	timer_label.name = "RoundTimerLabel"

	var score_label := _add_label(
		summary,
		_score_summary_text(),
		11,
		Color("d7c4a2")
	)
	score_label.name = "ScoreLabel"

	var pause_button := _make_button(
		"▶" if bool(_round_state.get("paused", false)) else "Ⅱ",
		Callable(self, "_emit_pause")
	)
	pause_button.name = "PauseButton"
	pause_button.tooltip_text = "재개" if bool(_round_state.get("paused", false)) else "일시정지"
	pause_button.custom_minimum_size = Vector2(44, 44)
	_apply_button_style(pause_button, "ghost")
	pause_button.disabled = not bool(
		_read_model.get("commands", {}).get("can_pause", false)
	)
	header.add_child(pause_button)


func _build_feedback(feedback: String) -> void:
	var selection_label := _add_label(
		self,
		"손에 든 아이템  ·  %s" % _source_description(_selected_source),
		11,
		Color("9ce3c7"),
		HORIZONTAL_ALIGNMENT_CENTER
	)
	selection_label.name = "SelectedSourceLabel"
	selection_label.visible = not _selected_source.is_empty()
	selection_label.custom_minimum_size = Vector2(0, 22)
	selection_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	selection_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	var message := feedback.strip_edges()
	var feedback_label := _add_label(
		self,
		message,
		11,
		Color("f6c66d"),
		HORIZONTAL_ALIGNMENT_CENTER
	)
	feedback_label.name = "FeedbackLabel"
	feedback_label.visible = not message.is_empty()
	feedback_label.custom_minimum_size = Vector2(0, 24 if _large_text_enabled else 22)
	feedback_label.max_lines_visible = 1
	feedback_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _build_requests() -> void:
	var request_row := HBoxContainer.new()
	request_row.name = "RequestTicketRow"
	request_row.add_theme_constant_override("separation", 5)
	request_row.custom_minimum_size = Vector2(0, 68)
	add_child(request_row)
	var active_requests: Array = _round_state.get("active_requests", [])
	if active_requests.is_empty():
		var empty_panel := _make_panel("request_empty")
		empty_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		request_row.add_child(empty_panel)
		_add_label(
			empty_panel,
			"새 의뢰를 기다리는 중 · 재료를 미리 준비하세요",
			11,
			Color("bcae99"),
			HORIZONTAL_ALIGNMENT_CENTER
		)
		return

	var tick_rate := maxi(1, int(_catalog.get("rules", {}).get("tick_rate", 20)))
	for request_value: Variant in active_requests:
		var request: Dictionary = request_value
		var item_text := _item_name(
			str(request.get("item_id", "")),
			int(request.get("required_level", 0))
		)
		var recipe_button := _make_button(
			item_text,
			Callable(self, "_emit_recipe").bind(
				str(request.get("item_id", "")),
				int(request.get("required_level", 0))
			),
			9
		)
		recipe_button.name = "RecipeButton_%s" % str(request.get("event_id", "unknown"))
		recipe_button.tooltip_text = "%s 제작법 보기" % item_text
		recipe_button.custom_minimum_size = Vector2(96, 68)
		recipe_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		recipe_button.clip_contents = true
		_apply_button_style(recipe_button, "request")
		_hide_button_text(recipe_button)
		request_row.add_child(recipe_button)

		var margin := MarginContainer.new()
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_theme_constant_override("margin_left", 5)
		margin.add_theme_constant_override("margin_top", 4)
		margin.add_theme_constant_override("margin_right", 5)
		margin.add_theme_constant_override("margin_bottom", 4)
		recipe_button.add_child(margin)
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var request_content := HBoxContainer.new()
		request_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		request_content.add_theme_constant_override("separation", 3)
		margin.add_child(request_content)
		var request_icon := _make_texture_decoration(
			VisualCatalogScript.item_texture(str(request.get("item_id", ""))),
			ITEM_ICON_SIZE,
			1.0
		)
		if request_icon != null:
			request_icon.name = "RequestIcon_%s" % str(request.get("event_id", "unknown"))
			request_content.add_child(request_icon)
		var request_box := VBoxContainer.new()
		request_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		request_box.add_theme_constant_override("separation", 0)
		request_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		request_content.add_child(request_box)
		var request_definition := _find_entry(
			_catalog.get("requests", []),
			str(request.get("request_id", ""))
		)
		var forecast := bool(request_definition.get("forecast", false))
		var request_item := _add_label(
			request_box,
			("[예고] " if forecast else "") + item_text,
			10,
			Color("3c2a22"),
			HORIZONTAL_ALIGNMENT_LEFT
		)
		request_item.name = "RequestItem_%s" % str(request.get("event_id", "unknown"))
		request_item.max_lines_visible = 1
		request_item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var patience_seconds := ceili(
			float(maxi(0, int(request.get("remaining_patience_ticks", 0)))) / float(tick_rate)
		)
		var request_timer := _add_label(
			request_box,
			"%d점 · %d초" % [int(request.get("score", 0)), patience_seconds],
			9,
			Color("71523b"),
			HORIZONTAL_ALIGNMENT_LEFT
		)
		request_timer.name = "RequestTimer_%s" % str(request.get("event_id", "unknown"))
		var guide_hint := _add_label(
			request_box,
			"제작법  ›",
			8,
			Color("a4572f"),
			HORIZONTAL_ALIGNMENT_LEFT
		)
		guide_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var waiting_count := int(_round_state.get("waiting_requests", []).size())
	if waiting_count > 0:
		var waiting_label := _add_label(
			request_row,
			"+%d" % waiting_count,
			10,
			Color("d9c8ae"),
			HORIZONTAL_ALIGNMENT_CENTER
		)
		waiting_label.name = "WaitingRequestLabel"
		waiting_label.custom_minimum_size = Vector2(24, 68)
		waiting_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _build_facilities() -> void:
	var board := _make_panel("board")
	board.name = "WorkshopBoard"
	board.custom_minimum_size = Vector2(0, FACILITY_GRID_HEIGHT + 8)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(board)

	var floor := Control.new()
	floor.name = "WorkshopFloor"
	floor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	floor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	floor.draw.connect(Callable(self, "_draw_workshop_floor").bind(floor))
	board.add_child(floor)

	var center := CenterContainer.new()
	center.name = "WorkshopGridCenter"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.add_child(center)

	var grid := GridContainer.new()
	grid.name = "FacilityGrid"
	grid.columns = 3
	grid.custom_minimum_size = Vector2(326, FACILITY_GRID_HEIGHT)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	center.add_child(grid)

	for facility_id: String in FACILITY_ORDER:
		_build_facility_cell(grid, facility_id)


func _build_facility_cell(parent: Container, facility_id: String) -> void:
	var installed: bool = (
		facility_id in ["FAC_SUPPLY", "FAC_TRASH"]
		or _round_state.get("facilities", {}).has(facility_id)
	)
	var panel := _make_panel("facility" if installed else "facility_locked")
	panel.name = "FacilityCell_%s" % facility_id
	panel.custom_minimum_size = Vector2(104, 142)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.clip_contents = true
	parent.add_child(panel)
	_add_facility_sprite(panel, facility_id)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	panel.add_child(box)
	var facility_name_label := _add_label(
		box,
		_facility_name(facility_id),
		10,
		Color("fff0d0") if installed else Color("7d746d"),
		HORIZONTAL_ALIGNMENT_CENTER
	)
	facility_name_label.name = "FacilityName_%s" % facility_id
	facility_name_label.custom_minimum_size = Vector2(0, 17)
	facility_name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	facility_name_label.max_lines_visible = 1
	facility_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	facility_name_label.add_theme_constant_override("outline_size", 2)
	facility_name_label.add_theme_color_override("font_outline_color", Color("201719"))

	if facility_id == "FAC_SUPPLY":
		_build_supply_cell(box)
		return
	if facility_id == "FAC_TRASH":
		var trash_spacer := Control.new()
		trash_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(trash_spacer)
		var trash_hint := _add_label(
			box,
			"여기에 버리기",
			9,
			Color("c4a898"),
			HORIZONTAL_ALIGNMENT_CENTER
		)
		trash_hint.custom_minimum_size = Vector2(0, 22)
		var trash_destination := {"kind": "trash"}
		_register_tappable_destination(panel, trash_destination)
		_register_drop_target_tree(panel, trash_destination)
		return

	var facilities: Dictionary = _round_state.get("facilities", {})
	if not facilities.has(facility_id):
		var locked_spacer := Control.new()
		locked_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(locked_spacer)
		_add_label(box, "잠김", 9, Color("756d68"), HORIZONTAL_ALIGNMENT_CENTER)
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
	status_label.custom_minimum_size = Vector2(0, 16)
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_label.max_lines_visible = 1
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	var content_spacer := Control.new()
	content_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(content_spacer)

	var item_row := HBoxContainer.new()
	item_row.add_theme_constant_override("separation", 3)
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
		_apply_button_style(input_button, "slot")
		_decorate_item_button(
			input_button,
			str(input_item.get("item_id", "")),
			"ItemIcon_%s" % input_button.name,
			9
		)
		input_button.tooltip_text = input_button.text
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
		_apply_button_style(output_button, "complete_slot")
		_decorate_item_button(
			output_button,
			str(output.get("item_id", "")),
			"ItemIcon_%s" % output_button.name,
			9
		)
		output_button.tooltip_text = output_button.text
		item_row.add_child(output_button)

	if status == "ready":
		var start_button := _make_button(
			"▶  시작",
			Callable(self, "_emit_start").bind(facility_id),
			9
		)
		start_button.name = "Start_%s" % facility_id
		start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		start_button.disabled = not _facility_command_available(facility_id, "can_start")
		_apply_button_style(start_button, "primary")
		box.add_child(start_button)
	elif status == "output":
		var store_button := _make_button(
			"✓  수납",
			Callable(self, "_emit_store").bind(facility_id),
			9
		)
		store_button.name = "Store_%s" % facility_id
		store_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		store_button.disabled = not _facility_command_available(facility_id, "can_store")
		_apply_button_style(store_button, "success")
		box.add_child(store_button)
	elif facility.get("inputs", []).is_empty() and status not in ["working", "output"]:
		var drop_hint := _add_label(
			box,
			"재료 놓기",
			9,
			Color("bfae92"),
			HORIZONTAL_ALIGNMENT_CENTER
		)
		drop_hint.custom_minimum_size = Vector2(0, 22)

	var destination := {
		"kind": "facility_input",
		"facility_id": facility_id,
	}
	_register_tappable_destination(panel, destination)
	_register_drop_target_tree(panel, destination)


func _build_supply_cell(parent: VBoxContainer) -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)
	var supply_grid := GridContainer.new()
	supply_grid.columns = 2
	supply_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	supply_grid.add_theme_constant_override("h_separation", 3)
	supply_grid.add_theme_constant_override("v_separation", 3)
	parent.add_child(supply_grid)
	for item_id_value: Variant in _round_definition.get("supply_items", []):
		var item_id := str(item_id_value)
		var source := {"kind": "supply", "item_id": item_id}
		var button := _make_source_button(_item_name(item_id, 0), source, 9)
		button.name = "SourceSupply_%s" % item_id
		_apply_button_style(button, "supply_slot")
		_decorate_item_button(
			button,
			item_id,
			"ItemIcon_%s" % button.name,
			9
		)
		button.tooltip_text = "%s 가져오기" % _item_name(item_id, 0)
		supply_grid.add_child(button)


func _build_worker_and_inventory() -> void:
	var dock := _make_panel("inventory")
	dock.name = "InventoryDock"
	dock.custom_minimum_size = Vector2(0, 58)
	dock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(dock)

	var dock_row := HBoxContainer.new()
	dock_row.add_theme_constant_override("separation", 4)
	dock.add_child(dock_row)

	var workers: Array = _round_state.get("workers", [])
	var idle_workers := 0
	for worker_value: Variant in workers:
		if str(worker_value.get("facility_id", "")).is_empty():
			idle_workers += 1
	var inventory: Array = _round_state.get("inventory", [])
	var capacity := int(_round_definition.get("inventory_capacity", inventory.size()))
	var occupied_count := 0
	for item_value: Variant in inventory:
		if item_value != null:
			occupied_count += 1

	var dock_status := VBoxContainer.new()
	dock_status.custom_minimum_size = Vector2(68, 48)
	dock_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock_status.alignment = BoxContainer.ALIGNMENT_CENTER
	dock_status.add_theme_constant_override("separation", 0)
	dock_row.add_child(dock_status)
	var worker_label := _add_label(
		dock_status,
		_worker_summary_text(idle_workers, workers.size()),
		8,
		Color("d8c7aa"),
		HORIZONTAL_ALIGNMENT_LEFT
	)
	worker_label.name = "WorkerStatusLabel"
	worker_label.custom_minimum_size = Vector2(0, 20)

	var first_empty_slot := -1
	for slot: int in range(capacity):
		var item_value: Variant = inventory[slot] if slot < inventory.size() else null
		if item_value == null:
			if first_empty_slot < 0:
				first_empty_slot = slot
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
		item_button.tooltip_text = item_button.text.replace("\n", " · ")
		item_button.custom_minimum_size = Vector2(44, 48)
		_apply_button_style(item_button, "slot")
		_decorate_item_button(
			item_button,
			str(item.get("item_id", "")),
			"ItemIcon_%s" % item_button.name,
			9
		)
		dock_row.add_child(item_button)

	# Empty inventory is represented by one compact bag target instead of four
	# permanent blank slots. The destination still resolves to the first free
	# simulator slot, so facility output remains fully draggable.
	if first_empty_slot >= 0:
		var inventory_destination := {"kind": "inventory", "slot": first_empty_slot}
		var bag_button := _make_button(
			"가방\n%d/%d" % [occupied_count, capacity],
			Callable(self, "_emit_destination").bind(inventory_destination),
			8
		)
		bag_button.name = "DropTargetInventory_%d" % first_empty_slot
		bag_button.tooltip_text = "가방에 넣기 · %d칸 남음" % (capacity - occupied_count)
		bag_button.custom_minimum_size = Vector2(52, 48)
		bag_button.disabled = not _round_interactive
		_apply_button_style(bag_button, "empty_slot")
		dock_row.add_child(bag_button)
		_register_drop_target_tree(bag_button, inventory_destination)

	var delivery_button := _make_button(
		"납품대",
		Callable(self, "_emit_destination").bind({"kind": "delivery"}),
		9
	)
	delivery_button.name = "DropTargetDelivery"
	delivery_button.tooltip_text = "완성 장비를 이곳에 놓으면 조건에 맞는 의뢰에 자동 납품합니다."
	delivery_button.custom_minimum_size = Vector2(58, 48)
	delivery_button.disabled = not _round_interactive
	_apply_button_style(delivery_button, "delivery")
	_decorate_button_with_texture(
		delivery_button,
		VisualCatalogScript.facility_texture("FAC_DELIVERY"),
		"FacilityDropIcon_FAC_DELIVERY",
		9
	)
	dock_row.add_child(delivery_button)
	_register_drop_target_tree(delivery_button, {"kind": "delivery"})


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
		0.94 if installed else 0.12
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
	var icon := _make_texture_decoration(texture, ITEM_ICON_SIZE, 1.0)
	if icon == null:
		return
	icon.name = icon_name
	button.add_child(icon)
	icon.anchor_left = 0.5
	icon.anchor_top = 0.5
	icon.anchor_right = 0.5
	icon.anchor_bottom = 0.5
	icon.offset_left = -float(ITEM_ICON_SIZE) / 2.0
	icon.offset_top = -float(ITEM_ICON_SIZE) / 2.0
	icon.offset_right = float(ITEM_ICON_SIZE) / 2.0
	icon.offset_bottom = float(ITEM_ICON_SIZE) / 2.0

	# Keep Button.text as the semantic/test contract while drawing an outlined copy
	# above the decorative icon. This avoids changing minimum widths in the dense
	# 3x2 mobile grid and keeps disabled buttons visibly disabled.
	_hide_button_text(button)
	var text_overlay := Label.new()
	text_overlay.name = "%s_Text" % icon_name
	text_overlay.text = _button_caption(visible_text)
	text_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_overlay.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	text_overlay.autowrap_mode = TextServer.AUTOWRAP_OFF
	text_overlay.max_lines_visible = 1
	text_overlay.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_overlay.add_theme_font_size_override("font_size", _scaled_font_size(mini(font_size, 8)))
	text_overlay.add_theme_constant_override("outline_size", 2)
	text_overlay.add_theme_color_override("font_outline_color", Color("241c19"))
	text_overlay.modulate = Color("91877a") if button.disabled else Color("f4e7d0")
	button.add_child(text_overlay)
	text_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if button.text.begins_with("● ") or button.text.begins_with("▣ "):
		var selected_cue := Label.new()
		selected_cue.name = "SelectedCue_%s" % icon_name
		selected_cue.text = "▣" if button.text.begins_with("▣ ") else "●"
		selected_cue.mouse_filter = Control.MOUSE_FILTER_IGNORE
		selected_cue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		selected_cue.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		selected_cue.add_theme_font_size_override("font_size", _scaled_font_size(8))
		selected_cue.add_theme_constant_override("outline_size", 2)
		selected_cue.add_theme_color_override("font_outline_color", Color("17302a"))
		selected_cue.modulate = Color("8ff0c8")
		button.add_child(selected_cue)
		selected_cue.anchor_left = 1.0
		selected_cue.anchor_top = 0.0
		selected_cue.anchor_right = 1.0
		selected_cue.anchor_bottom = 0.0
		selected_cue.offset_left = -17.0
		selected_cue.offset_top = 2.0
		selected_cue.offset_right = -2.0
		selected_cue.offset_bottom = 17.0


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


func _register_drag_source(control: Control, source: Dictionary) -> void:
	control.set_meta("drag_source", source.duplicate(true))
	_configure_drag_forwarding(control)


func _register_drop_target_tree(root: Control, destination: Dictionary) -> void:
	if not _drop_target_roots.has(root):
		_drop_target_roots.append(root)
	_register_drop_control(root, destination)
	for child_value: Variant in root.find_children("*", "Control", true, false):
		var child := child_value as Control
		if child != null and child.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			_register_drop_control(child, destination)


func _register_drop_control(control: Control, destination: Dictionary) -> void:
	control.set_meta("drop_destination", destination.duplicate(true))
	_configure_drag_forwarding(control)


func _configure_drag_forwarding(control: Control) -> void:
	control.set_drag_forwarding(
		Callable(self, "_forward_get_drag_data").bind(control),
		Callable(self, "_forward_can_drop_data").bind(control),
		Callable(self, "_forward_drop_data").bind(control)
	)


func _forward_get_drag_data(_at_position: Vector2, control: Control) -> Variant:
	if not control.has_meta("drag_source"):
		return null
	var source: Dictionary = control.get_meta("drag_source", {})
	var payload := _drag_payload_for_source(source)
	if payload.is_empty():
		return null
	control.set_drag_preview(_make_drag_preview(payload.get("item", {})))
	if is_inside_tree():
		get_viewport().gui_set_drag_description(
			"%s 이동" % _item_name(
				str(payload.get("item", {}).get("item_id", "")),
				int(payload.get("item", {}).get("enhancement_level", 0))
			)
		)
	return payload


func _forward_can_drop_data(
	_at_position: Vector2,
	data: Variant,
	control: Control
) -> bool:
	if not control.has_meta("drop_destination"):
		return false
	return _can_drop_payload(data, control.get_meta("drop_destination", {}))


func _forward_drop_data(
	_at_position: Vector2,
	data: Variant,
	control: Control
) -> void:
	if not control.has_meta("drop_destination"):
		return
	var destination: Dictionary = control.get_meta("drop_destination", {})
	if not _can_drop_payload(data, destination):
		return
	var source: Dictionary = data.get("source", {})
	item_drop_requested.emit(source.duplicate(true), destination.duplicate(true))


func _drag_payload_for_source(source: Dictionary) -> Dictionary:
	if not _round_interactive:
		return {}
	var inspected := RoundSimulatorScript.inspect_source(
		_round_state,
		source,
		_round_definition
	)
	if not bool(inspected.get("ok", false)):
		return {}
	return {
		"type": DRAG_PAYLOAD_TYPE,
		"source": source.duplicate(true),
		"item": inspected.get("item", {}).duplicate(true),
	}


func _can_drop_payload(data: Variant, destination: Dictionary) -> bool:
	if not data is Dictionary or str(data.get("type", "")) != DRAG_PAYLOAD_TYPE:
		return false
	var source_value: Variant = data.get("source", {})
	if not source_value is Dictionary:
		return false
	return _can_drop_source(source_value, destination)


func _can_drop_source(source: Dictionary, destination: Dictionary) -> bool:
	if not _round_interactive:
		return false
	var command_type := SimContractScript.COMMAND_MOVE
	var payload: Dictionary = {"source": source.duplicate(true)}
	match str(destination.get("kind", "")):
		"facility_input", "inventory":
			payload["destination"] = destination.duplicate(true)
		"delivery":
			command_type = SimContractScript.COMMAND_DELIVER
		"trash":
			command_type = SimContractScript.COMMAND_DISCARD
		_:
			return false
	var preview := RoundSimulatorScript.preview_command(
		_round_state,
		command_type,
		payload,
		_round_definition,
		_catalog
	)
	return bool(preview.get("accepted", false))


func _make_drag_preview(item: Dictionary) -> Control:
	var panel := _make_panel()
	panel.name = "ItemDragPreview"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(140, 48)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)
	var item_id := str(item.get("item_id", ""))
	var icon := _make_texture_decoration(
		VisualCatalogScript.item_texture(item_id),
		DRAG_PREVIEW_ICON_SIZE,
		1.0
	)
	if icon != null:
		row.add_child(icon)
	var label := _add_label(
		row,
		_item_name(item_id, int(item.get("enhancement_level", 0))),
		11,
		Color("fff0d0")
	)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.custom_minimum_size = Vector2(82, DRAG_PREVIEW_ICON_SIZE)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return panel


func _draw_workshop_floor(floor: Control) -> void:
	var floor_size := floor.size
	if floor_size.x <= 0.0 or floor_size.y <= 0.0:
		return
	floor.draw_rect(Rect2(Vector2.ZERO, floor_size), Color("2b211f"), true)
	var glow_radius := minf(floor_size.x, floor_size.y) * 0.48
	floor.draw_circle(
		Vector2(floor_size.x * 0.5, floor_size.y * 0.48),
		glow_radius,
		Color(0.25, 0.16, 0.12, 0.34)
	)
	var plank_height := 32.0
	var row := 0
	var y := plank_height
	while y < floor_size.y:
		floor.draw_line(
			Vector2(0.0, y),
			Vector2(floor_size.x, y),
			Color(0.10, 0.065, 0.06, 0.62),
			1.0
		)
		var seam_offset := 30.0 if row % 2 == 0 else 64.0
		var x := seam_offset
		while x < floor_size.x:
			floor.draw_line(
				Vector2(x, y - plank_height),
				Vector2(x, y),
				Color(0.12, 0.075, 0.065, 0.48),
				1.0
			)
			x += 92.0
		y += plank_height
		row += 1
	for corner: Vector2 in [
		Vector2(12.0, 12.0),
		Vector2(floor_size.x - 12.0, 12.0),
		Vector2(12.0, floor_size.y - 12.0),
		Vector2(floor_size.x - 12.0, floor_size.y - 12.0),
	]:
		floor.draw_circle(corner, 2.5, Color("9a6845"))


func _set_drop_target_highlights(data: Variant) -> void:
	for target: Control in _drop_target_roots:
		if not is_instance_valid(target):
			continue
		var destination: Dictionary = target.get_meta("drop_destination", {})
		var valid := _can_drop_payload(data, destination)
		target.set_meta("drop_valid", valid)
		target.pivot_offset = target.size * 0.5
		target.scale = Vector2(1.035, 1.035) if valid else Vector2.ONE
		target.modulate = Color("b9ffe1") if valid else Color.WHITE


func _reset_drop_target_highlights() -> void:
	for target: Control in _drop_target_roots:
		if not is_instance_valid(target):
			continue
		target.remove_meta("drop_valid")
		target.scale = Vector2.ONE
		target.modulate = Color.WHITE


func _make_panel(kind: String = "default") -> PanelContainer:
	var panel := PanelContainer.new()
	var style: StyleBoxFlat
	match kind:
		"hud":
			style = _play_style_box(Color("211d28"), Color("4a3d4a"), 12, 1, 7)
		"board":
			style = _play_style_box(Color("211c21"), Color("4a3937"), 14, 1, 4)
		"facility":
			style = _play_style_box(Color("352b2a"), Color("685047"), 12, 2, 4)
		"facility_locked":
			style = _play_style_box(Color("211e22"), Color("39343a"), 12, 1, 4)
		"inventory":
			style = _play_style_box(Color("242029"), Color("514451"), 12, 1, 5)
		"request_empty":
			style = _play_style_box(Color("252129"), Color("49404a"), 11, 1, 6)
		_:
			style = _play_style_box(Color("2b2530"), Color("625160"), 10, 2, 5)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _play_style_box(
	background: Color,
	border: Color,
	radius: int,
	bottom_depth: int,
	content_margin: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = bottom_depth
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = content_margin
	style.content_margin_top = content_margin
	style.content_margin_right = content_margin
	style.content_margin_bottom = content_margin + maxi(0, bottom_depth - 1)
	style.anti_aliasing = true
	return style


func _apply_button_style(button: Button, kind: String) -> void:
	var background := Color("3b3039")
	var border := Color("655260")
	var hover := Color("493945")
	var pressed := Color("2f272f")
	var font := Color("fff0d0")
	var radius := 10
	var depth := 1
	match kind:
		"ghost":
			background = Color("2b2630")
			border = Color("5c505e")
			hover = Color("3a323e")
			pressed = Color("211d26")
		"request":
			background = Color("e5c98d")
			border = Color("8a5f38")
			hover = Color("f0d9a3")
			pressed = Color("cfad70")
			font = Color("3c2a22")
			radius = 11
			depth = 2
		"slot":
			background = Color(0.11, 0.09, 0.12, 0.86)
			border = Color("725d50")
			hover = Color("393039")
			pressed = Color("171419")
			radius = 11
		"complete_slot":
			background = Color("233a32")
			border = Color("68c99f")
			hover = Color("2e4c40")
			pressed = Color("1b2f28")
			radius = 11
		"supply_slot":
			background = Color("243842")
			border = Color("5f9db3")
			hover = Color("31505d")
			pressed = Color("1c2c34")
			radius = 11
		"empty_slot":
			background = Color("211e25")
			border = Color("544a56")
			hover = Color("302a34")
			pressed = Color("17151a")
			font = Color("a89ba8")
			radius = 11
		"primary":
			background = Color("d66c35")
			border = Color("f0a052")
			hover = Color("e77e42")
			pressed = Color("ae4f29")
			font = Color("fff6df")
			depth = 2
		"success":
			background = Color("287359")
			border = Color("6ad0a6")
			hover = Color("32886a")
			pressed = Color("205b48")
			font = Color("effff7")
			depth = 2
		"delivery":
			background = Color("2a5361")
			border = Color("68b6c9")
			hover = Color("356979")
			pressed = Color("213f4a")
			font = Color("effaff")
			depth = 2
	button.add_theme_color_override("font_color", font)
	button.add_theme_color_override("font_hover_color", font.lightened(0.08))
	button.add_theme_color_override("font_pressed_color", font)
	button.add_theme_color_override("font_focus_color", font)
	button.add_theme_color_override("font_disabled_color", Color("827982"))
	button.add_theme_stylebox_override(
		"normal", _play_style_box(background, border, radius, depth, 3)
	)
	button.add_theme_stylebox_override(
		"hover", _play_style_box(hover, border.lightened(0.12), radius, depth, 3)
	)
	button.add_theme_stylebox_override(
		"pressed", _play_style_box(pressed, border, radius, 1, 3)
	)
	button.add_theme_stylebox_override(
		"disabled", _play_style_box(Color("262229"), Color("403943"), radius, 1, 3)
	)
	button.add_theme_stylebox_override(
		"focus", _play_style_box(Color.TRANSPARENT, Color("70cae8"), radius, 2, 1)
	)
	if button.text.begins_with("● ") or button.text.begins_with("▣ "):
		button.add_theme_stylebox_override(
			"normal",
			_play_style_box(background.lightened(0.05), Color("73d8b0"), radius, 2, 3)
		)
		button.add_theme_stylebox_override(
			"hover",
			_play_style_box(hover.lightened(0.06), Color("9bf0ce"), radius, 2, 3)
		)


func _hide_button_text(button: Button) -> void:
	for color_name: String in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_hover_pressed_color",
		"font_focus_color",
		"font_disabled_color",
	]:
		button.add_theme_color_override(color_name, Color.TRANSPARENT)


func _button_caption(text: String) -> String:
	var lines := text.split("\n", false)
	return str(lines[-1]).replace("● ", "").replace("▣ ", "") if not lines.is_empty() else text


func _make_button(text: String, callback: Callable, font_size: int = 11) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = MINIMUM_TAP_SIZE
	button.add_theme_font_size_override("font_size", _scaled_font_size(font_size))
	button.pressed.connect(callback)
	_apply_button_style(button, "default")
	return button


func _make_source_button(text: String, source: Dictionary, font_size: int = 10) -> Button:
	var selected_prefix := ("▣ " if _color_assist_enabled else "● ") if _is_selected(source) else ""
	var button := _make_button(
		selected_prefix + text,
		Callable(self, "_emit_source").bind(source.duplicate(true)),
		font_size
	)
	button.disabled = not _round_interactive
	_register_drag_source(button, source)
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
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _register_tappable_destination(control: Control, destination: Dictionary) -> void:
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	control.gui_input.connect(
		Callable(self, "_on_destination_gui_input").bind(destination.duplicate(true))
	)


func _on_destination_gui_input(event: InputEvent, destination: Dictionary) -> void:
	if not _round_interactive:
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or event.pressed:
		return
	if is_inside_tree() and get_viewport() != null and get_viewport().gui_is_dragging():
		return
	destination_requested.emit(destination.duplicate(true))


func _emit_source(source: Dictionary) -> void:
	source_requested.emit(source.duplicate(true))


func _emit_destination(destination: Dictionary) -> void:
	destination_requested.emit(destination.duplicate(true))


func _emit_recipe(item_id: String, enhancement_level: int) -> void:
	recipe_requested.emit(item_id, enhancement_level)


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
			return prefix + "재료 대기"
		"input":
			return prefix + "재료 받는 중"
		"ready":
			return prefix + "준비 완료"
		"working":
			var tick_rate := maxi(1, int(_catalog.get("rules", {}).get("tick_rate", 20)))
			var remaining_seconds := ceili(
				float(maxi(0, int(facility.get("remaining_ticks", 0)))) / float(tick_rate)
			)
			return prefix + "작업 중 · %d초" % remaining_seconds
		"output":
			var overheat_ticks := int(facility.get("overheat_remaining_ticks", 0))
			if overheat_ticks > 0:
				var tick_rate := maxi(1, int(_catalog.get("rules", {}).get("tick_rate", 20)))
				return prefix + "완료 · 과열 %d초" % ceili(float(overheat_ticks) / float(tick_rate))
			return prefix + "완료!"
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


func _score_summary_text() -> String:
	var score := int(_round_state.get("score", 0))
	var cutlines: Array = _round_definition.get("cutlines", [])
	var earned := 0
	var next_cutline := -1
	for cutline_value: Variant in cutlines:
		var cutline := int(cutline_value)
		if score >= cutline:
			earned += 1
		elif next_cutline < 0:
			next_cutline = cutline
	var stars := "★".repeat(earned) + "☆".repeat(maxi(0, 3 - earned))
	if next_cutline >= 0:
		return "%d점  ·  %s  다음 %d" % [score, stars, next_cutline]
	return "%d점  ·  %s  최고 등급" % [score, stars]


func _worker_summary_text(idle_workers: int, total_workers: int) -> String:
	var pips := "●".repeat(idle_workers) + "○".repeat(maxi(0, total_workers - idle_workers))
	return "일꾼 %s · %d/%d" % [pips, idle_workers, total_workers]


func _item_name(item_id: String, enhancement_level: int) -> String:
	var definition := _find_entry(_catalog.get("items", []), item_id)
	var display_name := str(definition.get("display_name", item_id))
	if enhancement_level > 0:
		display_name += " +%d" % enhancement_level
	return display_name


func _facility_name(facility_id: String) -> String:
	var definition := _find_entry(_catalog.get("facilities", []), facility_id)
	return str(definition.get("display_name", facility_id))


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
