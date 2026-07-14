extends Control

const DataRepositoryScript = preload("res://src/data/data_repository.gd")
const LegalTextRepositoryScript = preload("res://src/data/legal_text_repository.gd")
const ProfileScript = preload("res://src/app/profile_v1.gd")
const SaveRepositoryScript = preload("res://src/app/save_repository.gd")
const SettlementServiceScript = preload("res://src/app/settlement_service.gd")
const RoundSimulatorScript = preload("res://src/sim/round_simulator.gd")
const SimContractScript = preload("res://src/sim/sim_contract.gd")

var _content: VBoxContainer
var _data_repository: DataRepository
var _legal_repository: LegalTextRepository
var _save_repository: SaveRepository
var _profile: Dictionary = {}
var _profile_load_status: String = "missing"
var _snapshot_result: Dictionary = {"status": "missing", "value": {}}
var _round_definition: Dictionary = {}
var _round_state: Dictionary = {}
var _run_id: String = ""
var _pending_settlement: Dictionary = {}
var _notice: String = ""

func _ready() -> void:
	_build_shell()
	_show_boot("데이터와 저장을 확인하는 중…")
	call_deferred("_boot")

func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = Color("211a18")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	margin.add_child(_content)

func _boot() -> void:
	_data_repository = DataRepositoryScript.new()
	_legal_repository = LegalTextRepositoryScript.new()
	_save_repository = SaveRepositoryScript.new()
	var data_result := _data_repository.load_all()
	if not bool(data_result.get("ok", false)):
		_show_fatal("실행 데이터 오류", "\n".join(data_result.get("errors", [])))
		return
	var round_ids := _data_repository.get_round_ids()
	var profile_result := _save_repository.load_profile(round_ids)
	_profile_load_status = str(profile_result.get("status", "corrupt"))
	if _profile_load_status in ["ok", "recovered"]:
		_profile = profile_result.get("value", {})
		if _profile_load_status == "recovered":
			_notice = "주 저장이 손상되어 직전 정상 백업을 사용했습니다."
		_snapshot_result = _save_repository.load_snapshot(
			SimContractScript.SIM_VERSION,
			int(_data_repository.catalog.get("data_version", 0))
		)
	elif _profile_load_status == "missing":
		_profile = {}
	else:
		_show_fatal(
			"프로필을 복구할 수 없습니다",
			"자동으로 초기화하지 않았습니다.\n" + "\n".join(profile_result.get("errors", []))
		)
		return
	_show_title()

func _show_boot(message: String) -> void:
	_clear_content()
	_add_spacer()
	_add_heading("던전 오피스")
	_add_label(message, 16, HORIZONTAL_ALIGNMENT_CENTER)

func _show_title() -> void:
	_clear_content()
	_add_heading("던전 오피스")
	_add_label("결정론적 Android MVP 개발 뼈대", 16, HORIZONTAL_ALIGNMENT_CENTER)
	if not _notice.is_empty():
		_add_panel_text(_notice, Color("ffcf78"))
	if _profile.is_empty():
		_add_panel_text("저장된 진행이 없습니다. R1부터 시작합니다.")
		_add_button("새로 시작", _new_game)
	else:
		_add_panel_text(_profile_summary())
		if str(_snapshot_result.get("status", "missing")) in ["ok", "recovered"]:
			_add_button("중단한 라운드 이어하기", _continue_game)
		else:
			_add_button("계속", _continue_game)
		if _can_offer_enhancement_purchase():
			_add_button("강화 설비 세트 구매 · 150G", _purchase_enhancement_kit)
	_add_spacer()
	_add_button("개인정보처리방침", _show_privacy, false)
	_add_button("오픈소스 라이선스", _show_licenses, false)
	_add_label("오프라인 · 광고/분석/결제/네트워크 권한 없음", 12, HORIZONTAL_ALIGNMENT_CENTER)

func _new_game() -> void:
	_profile = ProfileScript.create(_data_repository.get_round_ids())
	var save_result := _save_repository.save_profile(_profile)
	if not bool(save_result.get("ok", false)):
		_show_fatal("새 프로필 저장 실패", str(save_result.get("error", "알 수 없는 오류")))
		return
	_profile_load_status = "ok"
	_start_round("R1")

func _continue_game() -> void:
	if str(_snapshot_result.get("status", "missing")) in ["ok", "recovered"]:
		var snapshot: Dictionary = _snapshot_result.get("value", {})
		_round_state = snapshot.get("round_state", {})
		_run_id = str(snapshot.get("run_id", ""))
		_round_definition = _data_repository.get_round(str(_round_state.get("round_id", "")))
		if _round_definition.is_empty():
			_show_fatal("중단 저장 오류", "저장된 라운드를 현재 데이터에서 찾을 수 없습니다.")
			return
		if str(_round_state.get("status", "")) == "ended":
			_settle_round()
		else:
			_show_round()
		return
	var next_round := _choose_continue_round()
	_start_round(next_round)

func _choose_continue_round() -> String:
	var fallback := "R1"
	for round_id: String in _data_repository.get_round_ids():
		if not _profile.get("rounds", {}).has(round_id):
			continue
		if not bool(_profile["rounds"][round_id].get("unlocked", false)):
			continue
		var access := ProfileScript.can_enter(_profile, round_id, _data_repository.get_round(round_id))
		if not bool(access.get("allowed", false)):
			continue
		fallback = round_id
		if not bool(_profile["rounds"][round_id].get("first_cleared", false)):
			return round_id
	return fallback

func _start_round(round_id: String) -> void:
	_round_definition = _data_repository.get_round(round_id)
	if _round_definition.is_empty():
		_show_fatal("라운드 오류", "%s 데이터를 찾을 수 없습니다." % round_id)
		return
	var access := ProfileScript.can_enter(_profile, round_id, _round_definition)
	if not bool(access.get("allowed", false)):
		_notice = "라운드에 입장할 수 없습니다: %s" % access.get("reason", "unknown")
		_show_title()
		return
	var allocation := ProfileScript.allocate_run(_profile)
	var updated_profile: Dictionary = allocation["profile"]
	var profile_save := _save_repository.save_profile(updated_profile)
	if not bool(profile_save.get("ok", false)):
		_show_fatal("라운드 시작 저장 실패", str(profile_save.get("error", "알 수 없는 오류")))
		return
	_profile = updated_profile
	_run_id = str(allocation["run_id"])
	_round_state = RoundSimulatorScript.create_state(_round_definition, _data_repository.catalog)
	var snapshot_save := _save_repository.save_snapshot(_run_id, _round_state)
	if not bool(snapshot_save.get("ok", false)):
		_show_fatal("중단 저장 생성 실패", str(snapshot_save.get("error", "알 수 없는 오류")))
		return
	_snapshot_result = {"status": "ok", "value": {"run_id": _run_id, "round_state": _round_state}}
	_show_round()

func _show_round() -> void:
	_clear_content()
	var tick_rate := int(_data_repository.catalog.get("rules", {}).get("tick_rate", 20))
	var remaining_ticks := maxi(0, int(_round_state.get("deadline_ticks", 0)) - int(_round_state.get("tick", 0)))
	_add_heading("%s · %s" % [_round_definition.get("id", "?"), _round_definition.get("display_name", "")])
	_add_panel_text(
		"남은 시간 %d초  |  점수 %d\n활성 의뢰 %d  |  대기 %d\n인벤토리 %s" % [
			ceili(float(remaining_ticks) / float(tick_rate)),
			int(_round_state.get("score", 0)),
			_round_state.get("active_requests", []).size(),
			_round_state.get("waiting_requests", []).size(),
			_inventory_summary(),
		]
	)
	_add_label(_facility_summary(), 13)
	if str(_round_definition.get("id", "")) == "R1" and int(_round_state.get("tick", 0)) == 0:
		_add_button("R1 결정론 데모 실행", _run_r1_demo)
	_add_button("1초 진행", _advance_one_second)
	_add_button("기한까지 진행", _advance_to_deadline, false)
	_add_button("저장 후 타이틀", _save_and_title, false)
	_add_label("현재 화면은 시스템 계약을 검증하는 최소 UI입니다.", 12, HORIZONTAL_ALIGNMENT_CENTER)

func _run_r1_demo() -> void:
	if str(_round_definition.get("id", "")) != "R1" or int(_round_state.get("tick", 0)) != 0:
		return
	_step_commands([_make_command(SimContractScript.COMMAND_MOVE, {
		"source": {"kind": "supply", "item_id": "MAT_IRON_ORE"},
		"destination": {"kind": "facility_input", "facility_id": "FAC_FURNACE"},
	}, 0)])
	_advance_until_facility_output("FAC_FURNACE")
	_step_commands([
		_make_command(SimContractScript.COMMAND_STORE, {"facility_id": "FAC_FURNACE"}, 0),
		_make_command(SimContractScript.COMMAND_MOVE, {
			"source": {"kind": "inventory", "slot": 0},
			"destination": {"kind": "facility_input", "facility_id": "FAC_WEAPON_BENCH"},
		}, 1),
		_make_command(SimContractScript.COMMAND_START, {"facility_id": "FAC_WEAPON_BENCH"}, 2),
	])
	_advance_until_facility_output("FAC_WEAPON_BENCH")
	_step_commands([
		_make_command(SimContractScript.COMMAND_STORE, {"facility_id": "FAC_WEAPON_BENCH"}, 0),
		_make_command(SimContractScript.COMMAND_DELIVER, {"source": {"kind": "inventory", "slot": 0}}, 1),
	])
	_advance_to_deadline()

func _make_command(type: String, payload: Dictionary, sequence_offset: int) -> Dictionary:
	return SimContractScript.command(
		int(_round_state.get("tick", 0)),
		int(_round_state.get("next_command_sequence", 1)) + sequence_offset,
		type,
		payload
	)

func _step_commands(commands: Array) -> void:
	var result := RoundSimulatorScript.step(
		_round_state,
		commands,
		_round_definition,
		_data_repository.catalog
	)
	_round_state = result["state"]

func _advance_until_facility_output(facility_id: String) -> void:
	while str(_round_state.get("status", "")) == "running":
		var facility: Dictionary = _round_state.get("facilities", {}).get(facility_id, {})
		if str(facility.get("status", "")) == "output":
			return
		_step_commands([])

func _advance_one_second() -> void:
	var tick_rate := int(_data_repository.catalog.get("rules", {}).get("tick_rate", 20))
	for _tick: int in range(tick_rate):
		if str(_round_state.get("status", "")) != "running":
			break
		_step_commands([])
	_after_round_action()

func _advance_to_deadline() -> void:
	while str(_round_state.get("status", "")) == "running":
		_step_commands([])
	_after_round_action()

func _after_round_action() -> void:
	var save_result := _save_repository.save_snapshot(_run_id, _round_state)
	if not bool(save_result.get("ok", false)):
		_notice = "최근 진행 저장 실패: %s" % save_result.get("error", "unknown")
	if str(_round_state.get("status", "")) == "ended":
		_settle_round()
	else:
		_show_round()

func _settle_round() -> void:
	_pending_settlement = SettlementServiceScript.calculate(_round_definition, _round_state, _run_id)
	_commit_settlement()

func _commit_settlement() -> void:
	var apply_result := ProfileScript.apply_settlement(
		_profile,
		_pending_settlement,
		_data_repository.get_round_ids()
	)
	if not bool(apply_result.get("ok", false)):
		_show_fatal("정산 오류", str(apply_result.get("reason", "unknown")))
		return
	var updated_profile: Dictionary = apply_result["profile"]
	var save_result := _save_repository.save_profile(updated_profile)
	if not bool(save_result.get("ok", false)):
		_show_settlement_error(str(save_result.get("error", "unknown")))
		return
	_profile = updated_profile
	_save_repository.delete_snapshot()
	_snapshot_result = {"status": "missing", "value": {}}
	_show_settlement(apply_result)

func _show_settlement(apply_result: Dictionary) -> void:
	_clear_content()
	var stars := int(_pending_settlement.get("stars", 0))
	_add_heading("원정 결과")
	_add_panel_text(
		"%s\n점수 %d · 별 %d개\n골드 +%d\n철회 %d · 과열 소실 %d" % [
			"공략 성공" if stars > 0 else "공략 실패",
			int(_pending_settlement.get("score", 0)),
			stars,
			int(apply_result.get("gold_awarded", 0)),
			int(_pending_settlement.get("withdrawal_count", 0)),
			int(_pending_settlement.get("overheat_loss_count", 0)),
		]
	)
	_add_button("타이틀로", _show_title)
	_add_button("같은 라운드 다시", func() -> void: _start_round(str(_round_definition.get("id", "R1"))), false)

func _show_settlement_error(error: String) -> void:
	_clear_content()
	_add_heading("결과 저장 실패")
	_add_panel_text("결과와 중단 저장을 보존했습니다.\n%s" % error, Color("ffcf78"))
	_add_button("저장 다시 시도", _commit_settlement)

func _save_and_title() -> void:
	var save_result := _save_repository.save_snapshot(_run_id, _round_state)
	if not bool(save_result.get("ok", false)):
		_notice = "중단 저장 실패: %s" % save_result.get("error", "unknown")
		_show_round()
		return
	_snapshot_result = {
		"status": "ok",
		"value": {"run_id": _run_id, "round_state": _round_state.duplicate(true)},
	}
	_notice = "라운드를 저장했습니다."
	_show_title()

func _purchase_enhancement_kit() -> void:
	var result := ProfileScript.purchase_enhancement_kit(_profile, 150)
	if not bool(result.get("ok", false)):
		_notice = "구매 불가: %s" % result.get("reason", "unknown")
		_show_title()
		return
	var save_result := _save_repository.save_profile(result["profile"])
	if not bool(save_result.get("ok", false)):
		_notice = "구매 저장 실패: %s" % save_result.get("error", "unknown")
		_show_title()
		return
	_profile = result["profile"]
	_notice = "강화 설비 세트를 구매했습니다."
	_show_title()

func _can_offer_enhancement_purchase() -> bool:
	return (
		not bool(_profile.get("enhancement_capability_owned", false))
		and bool(_profile.get("rounds", {}).get("R4", {}).get("first_cleared", false))
	)

func _show_privacy() -> void:
	_show_legal_document("개인정보처리방침", _legal_repository.load_privacy())

func _show_licenses() -> void:
	_show_legal_document("오픈소스 라이선스", _legal_repository.load_licenses())

func _show_legal_document(title: String, result: Dictionary) -> void:
	_clear_content()
	_add_heading(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	var text := RichTextLabel.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.fit_content = true
	text.bbcode_enabled = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.text = str(result.get("text", "문서를 불러올 수 없습니다."))
	text.custom_minimum_size = Vector2(0, 480)
	text.add_theme_font_size_override("normal_font_size", 13)
	scroll.add_child(text)
	_add_button("지원 이메일 복사", _copy_support_email, false)
	_add_button("메일 앱 열기", _open_support_email, false)
	_add_button("뒤로", _show_title)

func _copy_support_email() -> void:
	DisplayServer.clipboard_set(LegalTextRepositoryScript.SUPPORT_EMAIL)
	_notice = "지원 이메일을 복사했습니다."
	_show_title()

func _open_support_email() -> void:
	OS.shell_open("mailto:" + LegalTextRepositoryScript.SUPPORT_EMAIL)

func _profile_summary() -> String:
	var cleared := 0
	for round_id: String in _data_repository.get_round_ids():
		if bool(_profile.get("rounds", {}).get(round_id, {}).get("first_cleared", false)):
			cleared += 1
	return "진행 %d/5 · 골드 %dG%s" % [
		cleared,
		int(_profile.get("gold", 0)),
		" · 계약 완료" if bool(_profile.get("mvp_completed", false)) else "",
	]

func _inventory_summary() -> String:
	var names: Array[String] = []
	for item_value: Variant in _round_state.get("inventory", []):
		if item_value == null:
			names.append("-")
		else:
			names.append(str(item_value.get("item_id", "?")))
	return "[" + ", ".join(names) + "]"

func _facility_summary() -> String:
	var rows: Array[String] = []
	var ids: Array = _round_state.get("facilities", {}).keys()
	ids.sort()
	for facility_id_value: Variant in ids:
		var facility: Dictionary = _round_state["facilities"][facility_id_value]
		if str(facility.get("status", "")) == "empty":
			continue
		rows.append("%s: %s (%d)" % [
			facility_id_value,
			facility.get("status", ""),
			int(facility.get("remaining_ticks", facility.get("overheat_remaining_ticks", 0))),
		])
	return "시설 상태: 모두 비어 있음" if rows.is_empty() else "시설 상태\n" + "\n".join(rows)

func _show_fatal(title: String, details: String) -> void:
	_clear_content()
	_add_heading(title)
	_add_panel_text(details, Color("ff9b8e"))
	_add_button("앱 종료", get_tree().quit, false)

func _clear_content() -> void:
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

func _add_heading(text: String) -> Label:
	return _add_label(text, 28, HORIZONTAL_ALIGNMENT_CENTER)

func _add_label(text: String, size: int = 14, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	_content.add_child(label)
	return label

func _add_panel_text(text: String, color: Color = Color("f2dfc2")) -> Label:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(panel)
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	panel.add_child(label)
	return label

func _add_button(text: String, callback: Callable, primary: bool = true) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 48 if primary else 42)
	button.add_theme_font_size_override("font_size", 16 if primary else 14)
	button.pressed.connect(callback)
	_content.add_child(button)
	return button

func _add_spacer() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 32)
	_content.add_child(spacer)
