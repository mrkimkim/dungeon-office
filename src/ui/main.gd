extends Control

const DataRepositoryScript = preload("res://src/data/data_repository.gd")
const LegalTextRepositoryScript = preload("res://src/data/legal_text_repository.gd")
const ProfileScript = preload("res://src/app/profile_v1.gd")
const SaveRepositoryScript = preload("res://src/app/save_repository.gd")
const SettlementServiceScript = preload("res://src/app/settlement_service.gd")
const RoundSimulatorScript = preload("res://src/sim/round_simulator.gd")
const SimContractScript = preload("res://src/sim/sim_contract.gd")
const PlayScreenScript = preload("res://src/ui/play_screen.gd")
const RecipeGuideScript = preload("res://src/ui/recipe_guide.gd")
const TitleForgeTexture = preload("res://art/mvp/runtime/backgrounds/bg_title_forge.png")

const AUTOSAVE_INTERVAL_SECONDS: float = 5.0
const PLAY_REFRESH_SECONDS: float = 0.2
const MAX_PLAY_DELTA_SECONDS: float = 0.25
const SUPPORT_PAGE: String = "https://mrkimkim.github.io/dungeon-office/"
const PRIVACY_PAGE: String = "https://mrkimkim.github.io/dungeon-office/privacy/"
const LICENSE_PAGE: String = "https://mrkimkim.github.io/dungeon-office/licenses/"

const ROUND_LEARNING: Dictionary = {
	"R1": "철광석을 제련하고 단검을 제작해 첫 의뢰를 납품합니다.",
	"R2": "용광로와 제작대를 동시에 굴리고, 완성품을 수납해 시설을 비웁니다.",
	"R3": "과열될 산출물을 회수하고, 모든 의뢰 대신 중요한 의뢰를 선택합니다.",
	"R4": "종반의 고가 철검 의뢰를 예고받고 미리 완성품을 비축합니다.",
	"R5": "장비와 강화석을 병렬 준비해 확률 없이 +1 장비를 완성합니다.",
}

var _content: VBoxContainer
var _background_color: ColorRect
var _background_art: TextureRect
var _background_overlay: ColorRect
var _data_repository: DataRepository
var _legal_repository: LegalTextRepository
var _save_repository: SaveRepository
var _profile: Dictionary = {}
var _snapshot_result: Dictionary = {"status": "missing", "value": {}, "errors": []}
var _boot_errors: Array = []

var _screen: String = "boot"
var _settings_return_screen: String = "map"
var _round_definition: Dictionary = {}
var _round_state: Dictionary = {}
var _run_id: String = ""
var _pending_settlement: Dictionary = {}
var _selected_source: Dictionary = {}
var _play_screen: Control
var _sfx_player: AudioStreamPlayer
var _legal_notice_label: Label

var _tick_accumulator: float = 0.0
var _refresh_accumulator: float = 0.0
var _autosave_accumulator: float = 0.0
var _notice: String = ""
var _feedback: String = ""
var _feedback_expires_at: int = 0
var _snapshot_save_failed: bool = false
var _confirm_cancel_callback: Callable
var _discard_next_play_delta: bool = true


func _ready() -> void:
	_build_shell()
	_show_boot("데이터와 저장을 확인하는 중…")
	call_deferred("_boot")


func _process(delta: float) -> void:
	if _screen != "play":
		return
	var round_status := str(_round_state.get("status", ""))
	if round_status == "ended":
		set_process(false)
		_save_snapshot()
		_settle_round()
		return
	if round_status != "running":
		return
	if bool(_round_state.get("paused", false)):
		return
	if _discard_next_play_delta:
		_discard_next_play_delta = false
		return

	var tick_rate := int(_data_repository.catalog.get("rules", {}).get("tick_rate", 20))
	var tick_seconds := 1.0 / float(maxi(1, tick_rate))
	# Some old Android devices report a large first-frame delta after startup or a
	# scheduler hitch. Real elapsed wall time must never fast-forward an offline round.
	var safe_delta := clampf(delta, 0.0, MAX_PLAY_DELTA_SECONDS)
	_tick_accumulator = minf(_tick_accumulator + safe_delta, MAX_PLAY_DELTA_SECONDS)
	_refresh_accumulator += safe_delta
	_autosave_accumulator += safe_delta
	var advanced := false
	while _tick_accumulator >= tick_seconds:
		_tick_accumulator -= tick_seconds
		var result := _step_commands([])
		advanced = true
		_consume_events(result.get("events", []))
		if str(_round_state.get("status", "")) != "running":
			break

	if str(_round_state.get("status", "")) == "ended":
		set_process(false)
		_save_snapshot()
		_settle_round()
		return

	if _autosave_accumulator >= AUTOSAVE_INTERVAL_SECONDS:
		_autosave_accumulator = 0.0
		_save_snapshot()
	if advanced and _refresh_accumulator >= PLAY_REFRESH_SECONDS:
		_refresh_accumulator = 0.0
		_render_play()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back_request()
		return
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_pause_for_interruption()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if not _handle_back_request():
		return
	get_viewport().set_input_as_handled()


func _handle_back_request() -> bool:
	match _screen:
		"play":
			_pause_round()
		"pause":
			_resume_round()
		"pause_brief":
			_show_pause()
		"recipe":
			_resume_round()
		"confirm":
			if _confirm_cancel_callback.is_valid():
				_confirm_cancel_callback.call()
		"brief", "shop":
			_show_map()
		"settings":
			_return_from_settings()
		"legal":
			_show_settings(_settings_return_screen)
		"map", "title":
			if is_inside_tree():
				get_tree().quit()
		"result":
			_show_map()
		_:
			return false
	return true


func _build_shell() -> void:
	theme = _build_app_theme()
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "GrayboxSfx"
	add_child(_sfx_player)

	_background_color = ColorRect.new()
	_background_color.name = "BackgroundColor"
	_background_color.color = Color("17151d")
	_background_color.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_color.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_background_color)

	_background_art = TextureRect.new()
	_background_art.name = "TitleForgeArt"
	_background_art.texture = TitleForgeTexture
	_background_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_background_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_background_art)

	_background_overlay = ColorRect.new()
	_background_overlay.name = "BackgroundOverlay"
	_background_overlay.color = Color(0.055, 0.043, 0.065, 0.5)
	_background_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_background_overlay)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(_content)
	_sync_background()


func _boot() -> void:
	set_process(false)
	_screen = "boot"
	_data_repository = DataRepositoryScript.new()
	_legal_repository = LegalTextRepositoryScript.new()
	_save_repository = SaveRepositoryScript.new()
	var data_result := _data_repository.load_all()
	if not bool(data_result.get("ok", false)):
		_show_fatal("실행 데이터 오류", "\n".join(data_result.get("errors", [])))
		return

	var round_ids := _data_repository.get_round_ids()
	var profile_result := _save_repository.load_profile(round_ids)
	var profile_load_status := str(profile_result.get("status", "corrupt"))
	_boot_errors = profile_result.get("errors", [])
	if profile_load_status in ["ok", "recovered"]:
		_profile = profile_result.get("value", {})
		if profile_load_status == "recovered":
			_notice = "주 저장이 손상되어 직전 정상 백업을 복구했습니다."
		_snapshot_result = _save_repository.load_snapshot(
			SimContractScript.SIM_VERSION,
			int(_data_repository.catalog.get("data_version", 0))
		)
		var snapshot_status := str(_snapshot_result.get("status", "missing"))
		if snapshot_status == "recovered":
			_notice = "진행 중 판의 주 저장이 손상되어 직전 정상 백업을 복구했습니다."
		elif snapshot_status in ["corrupt", "incompatible"]:
			_notice = "진행 중이던 판은 복구할 수 없습니다. 완료 기록과 골드는 안전합니다."
		if snapshot_status in ["ok", "recovered"]:
			var snapshot_run_id := str(_snapshot_result.get("value", {}).get("run_id", ""))
			var reconciliation := ProfileScript.reconcile_next_run_sequence(
				_profile,
				snapshot_run_id
			)
			if not bool(reconciliation.get("ok", false)):
				_boot_errors = ["snapshot contains an invalid run ID"]
				_show_boot_reconciliation_error()
				return
			if bool(reconciliation.get("changed", false)):
				var reconciled_profile: Dictionary = reconciliation["profile"]
				var reconcile_save := (
					_save_repository.save_recovered_profile(reconciled_profile)
					if profile_load_status == "recovered"
					else _save_repository.save_profile(reconciled_profile)
				)
				if not bool(reconcile_save.get("ok", false)):
					_boot_errors = [str(reconcile_save.get("error", "run sequence reconciliation failed"))]
					_show_boot_reconciliation_error()
					return
				_profile = reconciled_profile
	elif profile_load_status == "missing":
		_profile = {}
		_snapshot_result = {"status": "missing", "value": {}, "errors": []}
	else:
		_profile = {}
		_show_profile_error()
		return
	_show_title()


func _show_boot(message: String) -> void:
	_screen = "boot"
	_clear_content()
	_add_spacer(96)
	_add_heading("던전 오피스")
	_add_label(message, 16, HORIZONTAL_ALIGNMENT_CENTER)


func _show_title() -> void:
	set_process(false)
	_screen = "title"
	_clear_content()
	_add_spacer(54)
	_add_heading("던전 오피스")
	_add_label("작은 대장간에서 원정대의 무기를 준비하세요", 16, HORIZONTAL_ALIGNMENT_CENTER)
	_add_pending_notice()
	if _profile.is_empty():
		_add_panel_text("저장된 진행이 없습니다. 첫 거래처의 다섯 라운드를 시작합니다.")
		_add_button("새로 시작", _new_game)
	else:
		_add_panel_text(_profile_summary())
		if _has_valid_snapshot():
			var snapshot: Dictionary = _snapshot_result.get("value", {})
			var state: Dictionary = snapshot.get("round_state", {})
			_add_button("%s 이어하기" % str(state.get("round_id", "진행 중 판")), _continue_game)
			_add_button("지도에서 보기", _show_map, false)
		else:
			_add_button("계속", _show_map)
		if str(_snapshot_result.get("status", "missing")) in ["corrupt", "incompatible"]:
			_add_button("손상된 진행 중 판 폐기", _discard_broken_snapshot, false)
	_add_spacer()
	_add_button("설정", func() -> void: _show_settings("title"), false)
	_add_label("오프라인 · 광고/분석/결제/네트워크 권한 없음", 12, HORIZONTAL_ALIGNMENT_CENTER)
	_add_label("테스트 빌드 %s" % _app_version(), 12, HORIZONTAL_ALIGNMENT_CENTER)


func _new_game() -> void:
	_profile = ProfileScript.create(_data_repository.get_round_ids())
	var save_result := _save_repository.save_profile(_profile)
	if not bool(save_result.get("ok", false)):
		_profile = {}
		_show_retryable_error(
			"새 프로필 저장 실패",
			"진행은 시작되지 않았습니다.\n%s" % str(save_result.get("error", "알 수 없는 오류")),
			_new_game,
			_show_title
		)
		return
	_notice = ""
	_show_map()


func _continue_game() -> void:
	if not _has_valid_snapshot():
		_show_map()
		return
	var snapshot: Dictionary = _snapshot_result.get("value", {})
	_round_state = snapshot.get("round_state", {}).duplicate(true)
	_run_id = str(snapshot.get("run_id", ""))
	_round_definition = _data_repository.get_round(str(_round_state.get("round_id", "")))
	if _round_definition.is_empty():
		_show_retryable_error(
			"중단 저장 오류",
			"저장된 라운드를 현재 데이터에서 찾을 수 없습니다. 완료 기록은 보존됩니다.",
			_discard_broken_snapshot,
			_show_title
		)
		return
	if str(_round_state.get("status", "")) == "ended":
		_settle_round()
		return
	_selected_source = {}
	if not bool(_round_state.get("paused", false)):
		var command := SimContractScript.command(
			int(_round_state.get("tick", 0)),
			int(_round_state.get("next_command_sequence", 1)),
			SimContractScript.COMMAND_PAUSE
		)
		_step_commands([command])
	_save_snapshot()
	_show_pause("중단한 시점에서 복원했습니다. 준비되면 재개하세요.")


func _show_map() -> void:
	if _profile.is_empty():
		_show_title()
		return
	set_process(false)
	_screen = "map"
	_clear_content()
	_add_heading("새싹 원정대")
	_add_panel_text(_profile_summary())
	_add_pending_notice()
	if _has_valid_snapshot():
		var snapshot_state: Dictionary = _snapshot_result.get("value", {}).get("round_state", {})
		_add_panel_text("⏸ %s 라운드가 일시정지되어 있습니다." % snapshot_state.get("round_id", "?"), Color("ffcf78"))
		_add_button("중단 라운드 이어하기", _continue_game)
		_add_button("중단 라운드 포기", _confirm_abandon_snapshot, false)

	for round_id: String in _data_repository.get_round_ids():
		var definition := _data_repository.get_round(round_id)
		var record: Dictionary = _profile.get("rounds", {}).get(round_id, {})
		var access := ProfileScript.can_enter(_profile, round_id, definition)
		var label := "%s · %s" % [round_id, definition.get("display_name", "")]
		if bool(record.get("first_cleared", false)):
			label += "  %s" % _star_text(int(record.get("best_stars", 0)))
		elif not bool(record.get("unlocked", false)):
			label += "  🔒"
		elif str(access.get("reason", "")) == "missing_capability":
			label += "  🛠 설비 필요"
		var callback := Callable(self, "_open_round").bind(round_id)
		var button := _add_button(label, callback, false)
		button.name = "RoundButton_%s" % round_id
		button.disabled = _has_valid_snapshot()

	if _can_offer_enhancement_purchase() or bool(_profile.get("enhancement_capability_owned", false)):
		_add_button("강화 설비 상점", _show_shop, false)
	_add_button("설정", func() -> void: _show_settings("map"), false)
	_add_button("타이틀", _show_title, false)


func _open_round(round_id: String) -> void:
	if _has_valid_snapshot():
		_notice = "먼저 진행 중인 라운드를 이어하거나 포기하세요."
		_show_map()
		return
	var definition := _data_repository.get_round(round_id)
	var access := ProfileScript.can_enter(_profile, round_id, definition)
	if not bool(access.get("allowed", false)):
		if str(access.get("reason", "")) == "missing_capability":
			_notice = "R5에는 합성 작업대와 강화 모루가 필요합니다."
			_show_shop()
		else:
			_notice = "앞 라운드를 별 1개 이상으로 완료해야 합니다."
			_show_map()
		return
	_show_brief(round_id)


func _show_brief(round_id: String) -> void:
	set_process(false)
	_screen = "brief"
	_round_definition = _data_repository.get_round(round_id)
	_clear_content()
	_add_heading("%s · %s" % [round_id, _round_definition.get("display_name", "")])
	var tick_rate := int(_data_repository.catalog.get("rules", {}).get("tick_rate", 20))
	var deadline_seconds := int(_round_definition.get("deadline_ticks", 0)) / maxi(1, tick_rate)
	_add_panel_text("납품 기한 %d초\n%s" % [deadline_seconds, ROUND_LEARNING.get(round_id, "")])
	if round_id == "R4":
		_add_panel_text("예고: 종반에 고가 철검 +0 의뢰가 옵니다. 철검을 미리 완성해 두세요.", Color("d9c2ff"))
	elif round_id == "R5":
		_add_panel_text("예고: 중반 단검 +1, 종반 고가 철검 +1 의뢰가 옵니다. 장비와 강화석을 미리 준비하세요. 강화는 항상 성공합니다.", Color("d9c2ff"))
	_add_label("시설: %s" % _facility_names(_round_definition.get("facilities", [])), 13)
	_add_label("별 기준: %s" % _cutline_text(_round_definition.get("cutlines", [])), 13)
	_add_spacer()
	_add_button("라운드 개시", func() -> void: _start_round(round_id))
	_add_button("지도로", _show_map, false)


func _start_round(round_id: String) -> void:
	_round_definition = _data_repository.get_round(round_id)
	if _round_definition.is_empty():
		_show_fatal("라운드 오류", "%s 데이터를 찾을 수 없습니다." % round_id)
		return
	var access := ProfileScript.can_enter(_profile, round_id, _round_definition)
	if not bool(access.get("allowed", false)):
		_notice = "라운드에 입장할 수 없습니다: %s" % access.get("reason", "unknown")
		_show_map()
		return
	var allocation := ProfileScript.allocate_run(_profile)
	var updated_profile: Dictionary = allocation["profile"]
	var profile_save := _save_repository.save_profile(updated_profile)
	if not bool(profile_save.get("ok", false)):
		_show_retryable_error(
			"라운드 시작 저장 실패",
			"라운드는 시작되지 않았습니다.\n%s" % str(profile_save.get("error", "알 수 없는 오류")),
			func() -> void: _start_round(round_id),
			func() -> void: _show_brief(round_id)
		)
		return
	_profile = updated_profile
	_run_id = str(allocation["run_id"])
	_round_state = RoundSimulatorScript.create_state(_round_definition, _data_repository.catalog)
	_selected_source = {}
	_tick_accumulator = 0.0
	_refresh_accumulator = 0.0
	_autosave_accumulator = 0.0
	_snapshot_save_failed = false
	if not _save_snapshot():
		_show_retryable_error(
			"중단 저장 생성 실패",
			"안전한 중단 저장을 만들 수 없어 라운드를 시작하지 않았습니다.",
			func() -> void: _start_round(round_id),
			_show_map
		)
		return
	_set_feedback(_tutorial_hint(), 8.0)
	_show_play()


func _show_play() -> void:
	_screen = "play"
	_clear_content()
	_play_screen = PlayScreenScript.new()
	_play_screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_play_screen.source_requested.connect(_on_source_requested)
	_play_screen.destination_requested.connect(_on_destination_requested)
	_play_screen.item_drop_requested.connect(_on_item_drop_requested)
	_play_screen.recipe_requested.connect(_show_recipe_guide)
	_play_screen.start_requested.connect(_on_start_requested)
	_play_screen.store_requested.connect(_on_store_requested)
	_play_screen.pause_requested.connect(_pause_round)
	_content.add_child(_play_screen)
	_play_screen.set_display_options(_profile.get("settings", {}))
	_render_play()
	_discard_next_play_delta = true
	set_process(not bool(_round_state.get("paused", false)))


func _render_play() -> void:
	if _screen != "play" or not is_instance_valid(_play_screen):
		return
	if not _selected_source.is_empty():
		var inspected := RoundSimulatorScript.inspect_source(
			_round_state,
			_selected_source,
			_round_definition
		)
		if not bool(inspected.get("ok", false)):
			_selected_source = {}
	var visible_feedback := _feedback
	if _feedback_expires_at > 0 and Time.get_ticks_msec() >= _feedback_expires_at:
		_feedback = ""
		_feedback_expires_at = 0
		visible_feedback = _tutorial_hint()
	elif visible_feedback.is_empty():
		visible_feedback = _tutorial_hint()
	if _snapshot_save_failed:
		visible_feedback = "⚠ 최근 진행이 저장되지 않았습니다. 다음 조작 때 다시 시도합니다.\n" + visible_feedback
	_play_screen.render(
		_round_definition,
		_round_state,
		_data_repository.catalog,
		_selected_source,
		visible_feedback
	)


func _on_source_requested(source: Dictionary) -> void:
	if _selected_source == source:
		_selected_source = {}
		_set_feedback("선택을 취소했습니다.")
	else:
		_selected_source = source.duplicate(true)
		_set_feedback("아이템을 선택했습니다. 목적지를 누르거나 끌어 놓으세요.")
	_render_play()


func _on_destination_requested(destination: Dictionary) -> void:
	if _selected_source.is_empty():
		_set_feedback("먼저 공급함·인벤토리·시설의 아이템을 선택하세요.")
		_render_play()
		return
	var kind := str(destination.get("kind", ""))
	if kind == "cancel":
		_selected_source = {}
		_set_feedback("선택을 취소했습니다.")
		_render_play()
		return
	_attempt_item_transfer(_selected_source, destination)
	_render_play()


func _on_item_drop_requested(source: Dictionary, destination: Dictionary) -> void:
	_attempt_item_transfer(source, destination)
	_render_play()


func _attempt_item_transfer(source: Dictionary, destination: Dictionary) -> bool:
	var type := SimContractScript.COMMAND_MOVE
	var payload: Dictionary = {"source": source.duplicate(true)}
	var kind := str(destination.get("kind", ""))
	match kind:
		"facility_input", "inventory":
			payload["destination"] = destination.duplicate(true)
		"delivery":
			type = SimContractScript.COMMAND_DELIVER
		"trash":
			type = SimContractScript.COMMAND_DISCARD
		_:
			_set_feedback("이동할 수 없는 목적지입니다.")
			return false
	var accepted := _dispatch_command(type, payload)
	if accepted:
		_selected_source = {}
	return accepted


func _on_start_requested(facility_id: String) -> void:
	_selected_source = {}
	_dispatch_command(SimContractScript.COMMAND_START, {"facility_id": facility_id})
	_render_play()


func _on_store_requested(facility_id: String) -> void:
	_selected_source = {}
	_dispatch_command(SimContractScript.COMMAND_STORE, {"facility_id": facility_id})
	_render_play()


func _dispatch_command(type: String, payload: Dictionary = {}) -> bool:
	var command := SimContractScript.command(
		int(_round_state.get("tick", 0)),
		int(_round_state.get("next_command_sequence", 1)),
		type,
		payload
	)
	var step_result := _step_commands([command])
	var command_results: Array = step_result.get("command_results", [])
	if command_results.is_empty():
		_set_feedback("명령 결과를 확인할 수 없습니다.")
		return false
	var result: Dictionary = command_results[0]
	if not bool(result.get("accepted", false)):
		_set_feedback(_reject_message(str(result.get("reason", "unknown"))))
		_save_snapshot()
		return false
	_consume_events(result.get("events", []))
	_save_snapshot()
	return true


func _step_commands(commands: Array) -> Dictionary:
	var result := RoundSimulatorScript.step(
		_round_state,
		commands,
		_round_definition,
		_data_repository.catalog
	)
	_round_state = result["state"]
	return result


func _consume_events(events: Array) -> void:
	for event_value: Variant in events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		match str(event.get("type", "")):
			"work_started":
				_set_feedback("작업을 시작했습니다.")
				_play_tone(440.0, 0.06)
			"work_completed":
				_set_feedback("✓ 작업이 끝났습니다. 산출물을 회수하세요.")
				_play_tone(660.0, 0.1, true)
			"delivered":
				_set_feedback("✓ 납품 완료 · +%d점" % int(event.get("score", 0)))
				_play_tone(880.0, 0.12, true)
			"item_moved", "item_stored":
				_play_tone(520.0, 0.04)
			"overheat_danger", "overheat_danger_entered":
				_set_feedback("! 용광로 산출물이 곧 과열됩니다.", 4.0)
				_play_tone(240.0, 0.15, true)
			"overheat_loss":
				_set_feedback("! 과열로 산출물을 잃었습니다.", 4.0)
				_play_tone(150.0, 0.2, true)
			"request_urgent", "request_urgent_entered":
				_set_feedback("의뢰 인내가 얼마 남지 않았습니다.")
				_play_tone(320.0, 0.1)
			"request_withdrawn":
				_set_feedback("의뢰가 철회됐습니다. 점수 감점은 없습니다.")
				_play_tone(280.0, 0.08)
			"deadline_warning", "deadline_warning_entered":
				_set_feedback("마감까지 30초 남았습니다.")
				_play_tone(360.0, 0.1)
			"deadline_countdown", "deadline_countdown_entered":
				_set_feedback("마감까지 10초 남았습니다.")
				_play_tone(420.0, 0.12, true)


func _pause_round() -> void:
	if _screen != "play" or bool(_round_state.get("paused", false)):
		return
	_dispatch_command(SimContractScript.COMMAND_PAUSE)
	set_process(false)
	_show_pause()


func _show_recipe_guide(item_id: String, enhancement_level: int) -> void:
	if _screen != "play":
		return
	if not bool(_round_state.get("paused", false)):
		if not _dispatch_command(SimContractScript.COMMAND_PAUSE):
			_render_play()
			return
	set_process(false)
	var guide := RecipeGuideScript.build(
		_data_repository.catalog,
		item_id,
		enhancement_level
	)
	_screen = "recipe"
	_clear_content()
	var target: Dictionary = guide.get("target", {})
	var target_name := str(target.get("display_name", item_id))
	var heading := _add_heading("%s 제작법" % target_name)
	heading.name = "RecipeTitleLabel"
	var pause_notice := _add_panel_text("제작법을 보는 동안 라운드는 일시정지됩니다.", Color("9fdcc8"))
	pause_notice.name = "RecipePauseNotice"

	var scroll := ScrollContainer.new()
	scroll.name = "RecipeScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "RecipeBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)

	if not bool(guide.get("ok", false)):
		var empty_label := _add_recipe_label(
			body,
			"제작법을 불러올 수 없습니다. 아이템은 그대로 보존됩니다.",
			14,
			Color("ffcf78")
		)
		empty_label.name = "RecipeEmptyLabel"
	else:
		var raw_texts: Array[String] = []
		for amount_value: Variant in guide.get("raw_materials", []):
			raw_texts.append(_recipe_amount_text(amount_value))
		var raw_panel := _add_recipe_panel(
			body,
			"필요 원자재\n%s" % " · ".join(raw_texts),
			Color("f0bf6a")
		)
		raw_panel.name = "RecipeRawMaterials"

		var tick_rate := maxi(
			1,
			int(_data_repository.catalog.get("rules", {}).get("tick_rate", 20))
		)
		var step_number := 1
		for step_value: Variant in guide.get("steps", []):
			var step: Dictionary = step_value
			var input_texts: Array[String] = []
			for input_value: Variant in step.get("inputs", []):
				input_texts.append(_recipe_amount_text(input_value))
			var run_count := int(step.get("run_count", 1))
			var seconds := ceili(
				float(int(step.get("total_duration_ticks", 0))) / float(tick_rate)
			)
			var process_text := "%s · %d초" % [
				str(step.get("facility_display_name", step.get("facility_id", ""))),
				seconds,
			]
			if run_count > 1:
				process_text += " · %d회" % run_count
			if str(step.get("worker_mode", "")) == "one":
				process_text += " · 일꾼 필요"
			var step_panel := _add_recipe_panel(
				body,
				"%d. %s\n%s  →  %s" % [
					step_number,
					process_text,
					" + ".join(input_texts),
					_recipe_amount_text(step.get("output", {})),
				],
				Color("f2dfc2")
			)
			step_panel.name = "RecipeStep_%s" % str(step.get("recipe_id", "unknown"))
			step_number += 1

	var close_button := _add_button("게임으로 돌아가기", _resume_round)
	close_button.name = "RecipeCloseButton"


func _add_recipe_panel(parent: Container, text: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	_add_recipe_label(panel, text, 13, color)
	return panel


func _add_recipe_label(
	parent: Node,
	text: String,
	font_size: int,
	color: Color
) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", _scaled_font_size(font_size))
	parent.add_child(label)
	return label


func _recipe_amount_text(amount_value: Variant) -> String:
	if not amount_value is Dictionary:
		return "?"
	var amount: Dictionary = amount_value
	var count := int(amount.get("count", 1))
	return "%s ×%d" % [str(amount.get("display_name", amount.get("item_id", "?"))), count]


func _pause_for_interruption() -> void:
	if _screen != "play" or bool(_round_state.get("paused", false)):
		return
	_dispatch_command(SimContractScript.COMMAND_PAUSE)
	set_process(false)
	_show_pause("앱이 백그라운드로 이동해 자동으로 일시정지했습니다.")


func _show_pause(message: String = "시간·작업·의뢰·과열이 모두 멈췄습니다.") -> void:
	_screen = "pause"
	set_process(false)
	_clear_content()
	_add_heading("일시정지")
	_add_panel_text(message)
	_add_pending_notice()
	_add_label(_round_status_summary(), 14)
	if _snapshot_save_failed:
		_add_panel_text("최근 진행 저장에 실패했습니다. 재개할 수 있지만 강제 종료 시 최근 조작이 사라질 수 있습니다.", Color("ffcf78"))
	_add_spacer()
	_add_button("재개", _resume_round)
	_add_button("의뢰서 보기", _show_pause_brief, false)
	_add_button("현재 라운드 재시작", _confirm_restart_round, false)
	_add_button("저장 후 지도 나가기", _save_and_map, false)
	_add_button("설정", func() -> void: _show_settings("pause"), false)


func _resume_round() -> void:
	if not bool(_round_state.get("paused", false)):
		_show_play()
		return
	if not _dispatch_command(SimContractScript.COMMAND_RESUME):
		set_process(false)
		if _screen == "recipe":
			_show_recipe_resume_error()
		elif _screen in ["pause", "pause_brief"]:
			_show_pause("재개하지 못했습니다. 라운드는 계속 정지되어 있습니다. 다시 시도하세요.")
		return
	_tick_accumulator = 0.0
	_refresh_accumulator = 0.0
	_show_play()


func _show_recipe_resume_error() -> void:
	var existing := find_child("RecipeResumeError", true, false) as Label
	if existing != null:
		existing.text = "재개하지 못했습니다. 라운드는 계속 정지되어 있습니다. 다시 시도하세요."
		return
	var label := _add_panel_text(
		"재개하지 못했습니다. 라운드는 계속 정지되어 있습니다. 다시 시도하세요.",
		Color("ffcf78")
	)
	label.name = "RecipeResumeError"
	var panel := label.get_parent()
	if panel != null and _content.get_child_count() >= 2:
		_content.move_child(panel, _content.get_child_count() - 2)


func _show_pause_brief() -> void:
	_screen = "pause_brief"
	_clear_content()
	_add_heading("%s 의뢰서" % _round_definition.get("id", ""))
	_add_panel_text(str(ROUND_LEARNING.get(str(_round_definition.get("id", "")), "")))
	if str(_round_definition.get("id", "")) in ["R4", "R5"]:
		_add_panel_text("예고 의뢰를 위해 완성 장비와 강화 재료를 미리 비축하세요.", Color("d9c2ff"))
	_add_label("별 기준: %s" % _cutline_text(_round_definition.get("cutlines", [])), 14)
	_add_button("일시정지로 돌아가기", _show_pause)


func _confirm_restart_round() -> void:
	_show_confirm(
		"현재 라운드 재시작",
		"현재 판과 중단 저장은 사라집니다. 골드와 최고 기록은 보존됩니다.",
		"재시작",
		func() -> void:
			_save_repository.delete_snapshot()
			_snapshot_result = {"status": "missing", "value": {}, "errors": []}
			_show_brief(str(_round_definition.get("id", "R1"))),
		_show_pause
	)


func _save_and_map() -> void:
	if not bool(_round_state.get("paused", false)):
		_dispatch_command(SimContractScript.COMMAND_PAUSE)
	if not _save_snapshot():
		_show_pause("저장에 실패해 지도 이동을 중단했습니다.")
		return
	_notice = "라운드를 일시정지 상태로 저장했습니다."
	_show_map()


func _confirm_abandon_snapshot() -> void:
	_show_confirm(
		"중단 라운드 포기",
		"진행 중인 판만 사라집니다. 골드·별·완료 기록은 보존됩니다.",
		"판 포기",
		_abandon_snapshot,
		_show_map
	)


func _abandon_snapshot() -> void:
	var result := _save_repository.delete_snapshot()
	if not bool(result.get("ok", false)):
		_notice = "중단 저장을 삭제하지 못했습니다."
	else:
		_snapshot_result = {"status": "missing", "value": {}, "errors": []}
		_round_state = {}
		_run_id = ""
		_notice = "진행 중이던 판을 포기했습니다. 완료 기록은 유지됩니다."
	_show_map()


func _discard_broken_snapshot() -> void:
	var result := _save_repository.delete_snapshot()
	if bool(result.get("ok", false)):
		_snapshot_result = {"status": "missing", "value": {}, "errors": []}
		_notice = "복구할 수 없는 진행 중 판만 폐기했습니다. 완료 기록과 골드는 유지됩니다."
	else:
		_notice = "손상된 중단 저장을 삭제하지 못했습니다. 다시 시도하세요."
	_show_title()


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
	_snapshot_result = {"status": "missing", "value": {}, "errors": []}
	_show_settlement(apply_result)


func _show_settlement(apply_result: Dictionary) -> void:
	_screen = "result"
	set_process(false)
	_clear_content()
	var stars := int(_pending_settlement.get("stars", 0))
	var round_id := str(_pending_settlement.get("round_id", _round_definition.get("id", "R1")))
	_add_heading("원정 결과")
	_add_panel_text(
		"%s\n%s\n점수 %d · 골드 +%d\n납품 %d건 · 철회 %d건(감점 없음)\n과열 소실 %d건" % [
			"공략 성공" if stars > 0 else "공략 실패 · 무사히 후퇴",
			_star_text(stars),
			int(_pending_settlement.get("score", 0)),
			int(apply_result.get("gold_awarded", 0)),
			_round_state.get("deliveries", []).size(),
			int(_pending_settlement.get("withdrawal_count", 0)),
			int(_pending_settlement.get("overheat_loss_count", 0)),
		]
	)
	_add_label("별 기준: %s" % _cutline_text(_round_definition.get("cutlines", [])), 14)
	if round_id == "R5" and stars > 0:
		_add_panel_text("✓ 새싹 원정대와 첫 계약을 체결했습니다. MVP의 다섯 라운드를 모두 완료했습니다.", Color("a8e6b0"))
	if stars == 0:
		_add_button("다시 도전", func() -> void: _show_brief(round_id))
	else:
		var round_ids := _data_repository.get_round_ids()
		var index := round_ids.find(round_id)
		if index >= 0 and index + 1 < round_ids.size():
			var next_round := round_ids[index + 1]
			if next_round == "R5" and not bool(_profile.get("enhancement_capability_owned", false)):
				_add_button("강화 설비 준비", _show_shop)
			else:
				_add_button("다음 라운드", func() -> void: _show_brief(next_round))
	_add_button("같은 라운드 다시", func() -> void: _show_brief(round_id), false)
	_add_button("지도로", _show_map, false)


func _show_settlement_error(error: String) -> void:
	_screen = "result_error"
	set_process(false)
	_clear_content()
	_add_heading("결과 저장 실패")
	_add_panel_text("이번 결과와 중단 저장을 보존했습니다. 중복 보상 없이 다시 저장할 수 있습니다.\n%s" % error, Color("ffcf78"))
	_add_button("저장 다시 시도", _commit_settlement)


func _show_shop() -> void:
	_screen = "shop"
	set_process(false)
	_clear_content()
	_add_heading("강화 설비 상점")
	_add_pending_notice()
	var product: Dictionary = _data_repository.catalog.get("shop_products", [])[0]
	var price := int(product.get("price_gold", 0))
	_add_panel_text("%s\n합성 작업대 + 강화 모루\n가격 %dG · 보유 %dG" % [
		product.get("display_name", "강화 설비 세트"),
		price,
		int(_profile.get("gold", 0)),
	])
	if bool(_profile.get("enhancement_capability_owned", false)):
		_add_panel_text("✓ 보유 중", Color("a8e6b0"))
	elif not bool(_profile.get("rounds", {}).get("R4", {}).get("first_cleared", false)):
		_add_panel_text("R4를 먼저 완료해야 상점을 이용할 수 있습니다.", Color("ffcf78"))
	elif int(_profile.get("gold", 0)) < price:
		_add_panel_text("골드 %dG가 더 필요합니다. 완료한 라운드를 다시 플레이해 모을 수 있습니다." % (price - int(_profile.get("gold", 0))), Color("ffcf78"))
		var disabled_button := _add_button("골드 부족", func() -> void: pass)
		disabled_button.disabled = true
	else:
		var purchase_button := _add_button(
			"%dG로 구매" % price,
			func() -> void: _confirm_purchase_enhancement_kit(price)
		)
		purchase_button.name = "PurchaseEnhancementButton"
	_add_button("지도로", _show_map, false)


func _confirm_purchase_enhancement_kit(price: int) -> void:
	var current_gold := int(_profile.get("gold", 0))
	_show_confirm(
		"강화 설비 구매",
		"합성 작업대와 강화 모루를 함께 얻습니다.\n%dG → %dG" % [
			current_gold,
			current_gold - price,
		],
		"구매",
		func() -> void: _purchase_enhancement_kit(price),
		_show_shop
	)


func _purchase_enhancement_kit(price: int) -> void:
	var result := ProfileScript.purchase_enhancement_kit(_profile, price)
	if not bool(result.get("ok", false)):
		_notice = "구매할 수 없습니다: %s" % result.get("reason", "unknown")
		_show_shop()
		return
	var save_result := _save_repository.save_profile(result["profile"])
	if not bool(save_result.get("ok", false)):
		_notice = "구매가 저장되지 않아 취소했습니다. 골드와 설비는 바뀌지 않았습니다."
		_show_shop()
		return
	_profile = result["profile"]
	_notice = "강화 설비 세트를 구매했습니다."
	_show_map()


func _can_offer_enhancement_purchase() -> bool:
	return (
		not bool(_profile.get("enhancement_capability_owned", false))
		and bool(_profile.get("rounds", {}).get("R4", {}).get("first_cleared", false))
	)


func _show_settings(return_screen: String = "map") -> void:
	if return_screen != "settings":
		_settings_return_screen = return_screen
	_screen = "settings"
	set_process(false)
	_clear_content()
	_add_heading("설정")
	if _profile.is_empty():
		_add_panel_text("프로필을 만든 뒤 설정이 기기에 저장됩니다.")
	else:
		var settings: Dictionary = _profile.get("settings", {})
		_add_setting_slider("음악", "music_volume", int(settings.get("music_volume", 100)))
		_add_setting_slider("효과음", "sfx_volume", int(settings.get("sfx_volume", 100)))
		_add_setting_toggle("햅틱", "haptics_enabled", bool(settings.get("haptics_enabled", true)))
		_add_setting_toggle("색 보조", "color_assist_enabled", bool(settings.get("color_assist_enabled", false)))
		_add_setting_toggle("큰 글씨", "large_text_enabled", bool(settings.get("large_text_enabled", false)))
	_add_button("개인정보처리방침", _show_privacy, false)
	_add_button("오픈소스 라이선스", _show_licenses, false)
	_add_button("뒤로", _return_from_settings)


func _add_setting_slider(label_text: String, key: String, value: int) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_content.add_child(row)
	var label := Label.new()
	label.text = "%s · %d" % [label_text, value]
	label.add_theme_font_size_override("font_size", _scaled_font_size(14))
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = value
	slider.custom_minimum_size = Vector2(0, 44)
	slider.value_changed.connect(func(new_value: float) -> void:
		label.text = "%s · %d" % [label_text, int(new_value)]
		_set_setting(key, int(new_value), false)
	)
	slider.drag_ended.connect(func(_changed: bool) -> void: _save_settings())
	row.add_child(slider)


func _add_setting_toggle(label_text: String, key: String, enabled: bool) -> void:
	var toggle := CheckButton.new()
	toggle.text = label_text
	toggle.button_pressed = enabled
	toggle.custom_minimum_size = Vector2(0, 44)
	toggle.add_theme_font_size_override("font_size", _scaled_font_size(14))
	toggle.toggled.connect(func(value: bool) -> void:
		_set_setting(key, value, true)
		if key == "haptics_enabled" and value:
			Input.vibrate_handheld(30)
	)
	_content.add_child(toggle)


func _set_setting(key: String, value: Variant, save_now: bool) -> void:
	if _profile.is_empty():
		return
	_profile["settings"][key] = value
	if save_now:
		_save_settings()


func _save_settings() -> void:
	if _profile.is_empty():
		return
	var result := _save_repository.save_profile(_profile)
	if not bool(result.get("ok", false)):
		_notice = "설정이 현재 실행에는 적용됐지만 다음 실행에 유지되지 않을 수 있습니다."


func _return_from_settings() -> void:
	_save_settings()
	match _settings_return_screen:
		"title":
			_show_title()
		"pause":
			_show_pause()
		_:
			_show_map()


func _show_privacy() -> void:
	_show_legal_document("개인정보처리방침", _legal_repository.load_privacy(), PRIVACY_PAGE)


func _show_licenses() -> void:
	_show_legal_document("오픈소스 라이선스", _legal_repository.load_licenses(), LICENSE_PAGE)


func _show_legal_document(
	title: String,
	result: Dictionary,
	public_url: String = SUPPORT_PAGE
) -> void:
	_screen = "legal"
	_clear_content()
	_add_heading(title)
	_add_label("던전 오피스 %s · 지원 %s" % [_app_version(), LegalTextRepositoryScript.SUPPORT_EMAIL], 12)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	var text := RichTextLabel.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.fit_content = true
	text.bbcode_enabled = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.text = str(result.get("text", "문서를 불러올 수 없습니다."))
	text.custom_minimum_size = Vector2(0, 360)
	text.add_theme_font_size_override("normal_font_size", _scaled_font_size(13))
	scroll.add_child(text)
	var support_row := _add_button_row()
	var copy_email_button := _add_button_to(support_row, "이메일 복사", _copy_support_email)
	copy_email_button.name = "CopySupportEmailButton"
	var mail_button := _add_button_to(support_row, "메일 앱 열기", _open_support_email)
	mail_button.name = "OpenSupportEmailButton"
	var public_row := _add_button_row()
	var copy_page_button := _add_button_to(
		public_row,
		"공개 URL 복사",
		func() -> void: _copy_text(public_url, "공개 페이지 주소를 복사했습니다.")
	)
	copy_page_button.name = "CopyPublicUrlButton"
	var open_page_button := _add_button_to(
		public_row,
		"브라우저 열기",
		func() -> void: _open_external_url(public_url)
	)
	open_page_button.name = "OpenPublicUrlButton"
	_legal_notice_label = _add_label("", 12, HORIZONTAL_ALIGNMENT_CENTER)
	_legal_notice_label.name = "LegalNoticeLabel"
	_legal_notice_label.modulate = Color("ffcf78")
	_add_button("뒤로", func() -> void: _show_settings(_settings_return_screen), false)


func _copy_support_email() -> void:
	_copy_text(LegalTextRepositoryScript.SUPPORT_EMAIL, "지원 이메일을 복사했습니다.")


func _copy_text(value: String, success_notice: String) -> void:
	DisplayServer.clipboard_set(value)
	_set_legal_notice(success_notice)


func _open_support_email() -> void:
	var error := OS.shell_open("mailto:" + LegalTextRepositoryScript.SUPPORT_EMAIL)
	if error != OK:
		_set_legal_notice("메일 앱을 열 수 없습니다. 지원 이메일을 복사해 사용하세요.")


func _open_external_url(url: String) -> void:
	var error := OS.shell_open(url)
	if error != OK:
		_set_legal_notice("브라우저를 열 수 없습니다. 공개 URL을 복사해 사용하세요.")


func _set_legal_notice(message: String) -> void:
	if _screen == "legal" and is_instance_valid(_legal_notice_label):
		_legal_notice_label.text = message
		return
	_notice = message


func _show_profile_error() -> void:
	_screen = "data_error"
	set_process(false)
	_clear_content()
	_add_heading("프로필을 복구할 수 없습니다")
	_add_panel_text("완료 기록·골드가 들어 있는 저장을 자동 초기화하지 않았습니다. 다시 읽거나 명시적으로 새 게임을 시작할 수 있습니다.", Color("ffcf78"))
	_add_button("다시 시도", _boot)
	_add_button("오류 정보 보기", func() -> void: _show_error_details(_boot_errors), false)
	_add_button("새 게임 시작", _confirm_replace_profile_first, false)


func _show_boot_reconciliation_error() -> void:
	_screen = "data_error"
	set_process(false)
	_clear_content()
	_add_heading("중단 진행 복구를 완료할 수 없습니다")
	_add_panel_text(
		"중복 보상을 방지하기 위한 복구 정보를 저장하지 못했습니다. "
		+ "기존 완료 기록과 중단 판은 삭제하지 않았습니다.",
		Color("ffcf78")
	)
	_add_button("다시 시도", _boot)
	_add_button("오류 정보 보기", func() -> void: _show_error_details(_boot_errors), false)
	_add_button("앱 종료", get_tree().quit, false)


func _confirm_replace_profile_first() -> void:
	_show_confirm(
		"손상된 프로필 교체 · 1/2",
		"복구할 수 없는 기존 프로필 파일을 삭제하고 처음부터 시작합니다.",
		"다음 확인",
		_confirm_replace_profile_second,
		_show_profile_error
	)


func _confirm_replace_profile_second() -> void:
	_show_confirm(
		"손상된 프로필 교체 · 2/2",
		"이 작업은 되돌릴 수 없습니다. 정말 새 게임을 시작할까요?",
		"삭제하고 새로 시작",
		_replace_corrupt_profile,
		_show_profile_error
	)


func _replace_corrupt_profile() -> void:
	var result := _save_repository.delete_all()
	if not bool(result.get("ok", false)):
		_boot_errors = result.get("errors", [])
		_show_profile_error()
		return
	_profile = {}
	_snapshot_result = {"status": "missing", "value": {}, "errors": []}
	_new_game()


func _show_error_details(errors: Array) -> void:
	_screen = "error_details"
	_clear_content()
	_add_heading("오류 정보")
	_add_panel_text("\n".join(errors) if not errors.is_empty() else "추가 오류 정보가 없습니다.")
	_add_button("정보 복사", func() -> void: _copy_text("\n".join(errors), "오류 정보를 복사했습니다."), false)
	_add_button("뒤로", _show_profile_error)


func _show_confirm(
	title: String,
	body: String,
	confirm_text: String,
	confirm_callback: Callable,
	cancel_callback: Callable
) -> void:
	_screen = "confirm"
	_confirm_cancel_callback = cancel_callback
	set_process(false)
	_clear_content()
	_add_heading(title)
	_add_panel_text(body, Color("ffcf78"))
	_add_spacer()
	_add_button("취소", cancel_callback)
	_add_button(confirm_text, confirm_callback, false)


func _show_retryable_error(
	title: String,
	body: String,
	retry_callback: Callable,
	back_callback: Callable
) -> void:
	_screen = "error"
	set_process(false)
	_clear_content()
	_add_heading(title)
	_add_panel_text(body, Color("ffcf78"))
	_add_button("다시 시도", retry_callback)
	_add_button("뒤로", back_callback, false)


func _save_snapshot() -> bool:
	if _run_id.is_empty() or _round_state.is_empty():
		return false
	var result := _save_repository.save_snapshot(_run_id, _round_state)
	_snapshot_save_failed = not bool(result.get("ok", false))
	if not _snapshot_save_failed:
		_snapshot_result = {
			"status": "ok",
			"value": {"run_id": _run_id, "round_state": _round_state.duplicate(true)},
			"errors": [],
		}
	return not _snapshot_save_failed


func _has_valid_snapshot() -> bool:
	return str(_snapshot_result.get("status", "missing")) in ["ok", "recovered"]


func _tutorial_hint() -> String:
	var round_id := str(_round_state.get("round_id", ""))
	if round_id != "R1" or not _round_state.get("deliveries", []).is_empty():
		return "아이템을 목적지로 끌어 놓으세요. 준비된 작업자 시설은 시작을 누르세요."
	var furnace: Dictionary = _round_state.get("facilities", {}).get("FAC_FURNACE", {})
	var bench: Dictionary = _round_state.get("facilities", {}).get("FAC_WEAPON_BENCH", {})
	if str(furnace.get("status", "")) == "empty" and str(bench.get("status", "")) == "empty":
		return "① 공급함의 철광석을 용광로로 끌어 놓으세요."
	if str(furnace.get("status", "")) == "working":
		return "② 철 주괴를 제련 중입니다. 완료되면 산출물을 선택하세요."
	if str(furnace.get("status", "")) == "output":
		return "③ 용광로의 철 주괴를 무기 제작대로 끌어 놓으세요."
	if str(bench.get("status", "")) == "ready":
		return "④ 무기 제작대의 시작 버튼을 누르세요. 일꾼 한 명이 작업합니다."
	if str(bench.get("status", "")) == "working":
		return "⑤ 단검 제작 중입니다. 완료되면 산출물을 선택하세요."
	if str(bench.get("status", "")) == "output":
		return "⑥ 완성된 단검을 인벤토리 옆 납품대로 끌어 놓으세요."
	return "철 주괴를 무기 제작대에 넣고 단검을 만드세요."


func _reject_message(reason: String) -> String:
	var messages: Dictionary = {
		"round_not_running": "이미 끝난 라운드입니다.",
		"wrong_tick": "상태가 갱신됐습니다. 다시 선택하세요.",
		"stale_sequence": "이미 처리한 조작입니다.",
		"sequence_gap": "조작 순서가 맞지 않습니다. 다시 시도하세요.",
		"paused": "일시정지 중에는 생산을 지시할 수 없습니다.",
		"invalid_source": "선택한 아이템을 더 이상 사용할 수 없습니다.",
		"item_not_found": "아이템을 찾을 수 없습니다.",
		"invalid_destination": "그곳으로 옮길 수 없습니다.",
		"facility_unavailable": "이번 라운드에서 사용할 수 없는 시설입니다.",
		"facility_busy": "시설이 작업 또는 산출물로 막혀 있습니다.",
		"invalid_recipe_input": "이 시설의 레시피에 맞지 않는 재료입니다.",
		"input_incomplete": "필요한 재료가 모두 들어오지 않았습니다.",
		"no_idle_worker": "유휴 일꾼이 없습니다. 진행 중인 작업을 기다리세요.",
		"no_output": "회수할 산출물이 없습니다.",
		"inventory_full": "인벤토리가 가득 찼습니다. 사용·납품·파기해 자리를 만드세요.",
		"not_equipment": "장비만 납품할 수 있습니다.",
		"no_matching_request": "조건이 맞는 활성 의뢰가 없습니다. 아이템은 보존됩니다.",
	}
	_play_tone(180.0, 0.08)
	return str(messages.get(reason, "지금은 그 행동을 할 수 없습니다. (%s)" % reason))


func _play_tone(frequency: float, duration: float, haptic: bool = false) -> void:
	if not is_inside_tree() or not is_instance_valid(_sfx_player):
		return
	var settings: Dictionary = _profile.get("settings", {}) if not _profile.is_empty() else {}
	var volume := int(settings.get("sfx_volume", 100))
	if volume > 0:
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = 22050.0
		generator.buffer_length = maxf(0.1, duration + 0.05)
		_sfx_player.stream = generator
		_sfx_player.volume_db = linear_to_db(float(volume) / 100.0)
		_sfx_player.play()
		var playback := _sfx_player.get_stream_playback() as AudioStreamGeneratorPlayback
		if playback != null:
			var frame_count := maxi(1, int(generator.mix_rate * duration))
			var frames := PackedVector2Array()
			frames.resize(frame_count)
			for frame: int in range(frame_count):
				var envelope := 1.0 - (float(frame) / float(frame_count))
				var sample := sin(TAU * frequency * float(frame) / generator.mix_rate) * 0.18 * envelope
				frames[frame] = Vector2(sample, sample)
			playback.push_buffer(frames)
	if haptic and bool(settings.get("haptics_enabled", true)):
		Input.vibrate_handheld(35)


func _set_feedback(text: String, seconds: float = 3.0) -> void:
	_feedback = text
	_feedback_expires_at = Time.get_ticks_msec() + int(seconds * 1000.0)


func _profile_summary() -> String:
	var cleared := 0
	var total_stars := 0
	for round_id: String in _data_repository.get_round_ids():
		var record: Dictionary = _profile.get("rounds", {}).get(round_id, {})
		if bool(record.get("first_cleared", false)):
			cleared += 1
		total_stars += int(record.get("best_stars", 0))
	return "진행 %d/5 · 별 %d/15 · 골드 %dG%s" % [
		cleared,
		total_stars,
		int(_profile.get("gold", 0)),
		" · 계약 완료" if bool(_profile.get("mvp_completed", false)) else "",
	]


func _round_status_summary() -> String:
	var tick_rate := int(_data_repository.catalog.get("rules", {}).get("tick_rate", 20))
	var remaining := maxi(0, int(_round_state.get("deadline_ticks", 0)) - int(_round_state.get("tick", 0)))
	return "%s · 남은 %d초 · 점수 %d\n납품 %d · 철회 %d · 과열 소실 %d" % [
		_round_state.get("round_id", "?"),
		ceili(float(remaining) / float(maxi(1, tick_rate))),
		int(_round_state.get("score", 0)),
		_round_state.get("deliveries", []).size(),
		int(_round_state.get("withdrawal_count", 0)),
		int(_round_state.get("overheat_loss_count", 0)),
	]


func _facility_names(ids: Array) -> String:
	var names: Array[String] = []
	for id_value: Variant in ids:
		var id := str(id_value)
		if id in ["FAC_DELIVERY", "FAC_TRASH", "FAC_SUPPLY"]:
			continue
		var definition := DataRepositoryScript.find_by_id(_data_repository.catalog.get("facilities", []), id)
		names.append(str(definition.get("display_name", id)))
	return ", ".join(names)


func _cutline_text(cutlines: Array) -> String:
	if cutlines.size() < 3:
		return "-"
	return "★ %d · ★★ %d · ★★★ %d" % [int(cutlines[0]), int(cutlines[1]), int(cutlines[2])]


func _star_text(stars: int) -> String:
	return "★".repeat(clampi(stars, 0, 3)) + "☆".repeat(3 - clampi(stars, 0, 3))


func _app_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.1.0-test"))


func _scaled_font_size(base_size: int) -> int:
	if _profile.is_empty():
		return base_size
	return int(round(float(base_size) * (1.25 if bool(_profile.get("settings", {}).get("large_text_enabled", false)) else 1.0)))


func _show_fatal(title: String, details: String) -> void:
	_screen = "fatal"
	set_process(false)
	_clear_content()
	_add_heading(title)
	_add_panel_text(details, Color("ff9b8e"))
	_add_button("앱 종료", get_tree().quit, false)


func _clear_content() -> void:
	if _content == null:
		return
	_sync_background()
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_play_screen = null
	_legal_notice_label = null


func _sync_background() -> void:
	if _background_art == null or _background_overlay == null or _background_color == null:
		return
	var show_title_art := _screen in ["boot", "title"]
	_background_art.visible = show_title_art
	_background_overlay.visible = show_title_art
	_background_color.color = Color("17151d") if show_title_art else Color("1d1922")


func _build_app_theme() -> Theme:
	var app_theme := Theme.new()
	app_theme.set_color("font_color", "Label", Color("fff0d0"))
	app_theme.set_color("font_outline_color", "Label", Color(0.12, 0.08, 0.09, 0.9))
	app_theme.set_constant("outline_size", "Label", 1)
	app_theme.set_color("default_color", "RichTextLabel", Color("fff0d0"))
	app_theme.set_color("font_color", "Button", Color("fff0d0"))
	app_theme.set_color("font_hover_color", "Button", Color.WHITE)
	app_theme.set_color("font_pressed_color", "Button", Color("fff7e5"))
	app_theme.set_color("font_disabled_color", "Button", Color("8d8287"))
	app_theme.set_stylebox("normal", "Button", _ui_style_box(
		Color("604047"), Color("a4633f"), 10, 4, Color(0.04, 0.025, 0.035, 0.72)
	))
	app_theme.set_stylebox("hover", "Button", _ui_style_box(
		Color("72505a"), Color("f0a259"), 10, 4, Color(0.04, 0.025, 0.035, 0.76)
	))
	app_theme.set_stylebox("pressed", "Button", _ui_style_box(
		Color("4f353d"), Color("f07b43"), 10, 1, Color(0.04, 0.025, 0.035, 0.42)
	))
	app_theme.set_stylebox("disabled", "Button", _ui_style_box(
		Color("302a33"), Color("514850"), 10, 2, Color(0.02, 0.02, 0.025, 0.35)
	))
	app_theme.set_stylebox("focus", "Button", _ui_style_box(
		Color(0, 0, 0, 0), Color("63bce6"), 10, 2, Color(0, 0, 0, 0)
	))
	app_theme.set_stylebox("panel", "PanelContainer", _ui_style_box(
		Color("2c2631"), Color("695462"), 12, 3, Color(0.025, 0.018, 0.028, 0.7)
	))
	app_theme.set_stylebox("normal", "LineEdit", _ui_style_box(
		Color("231f28"), Color("695462"), 8, 2, Color(0.02, 0.015, 0.02, 0.55)
	))
	return app_theme


func _ui_style_box(
	background: Color,
	border: Color,
	corner_radius: int,
	bottom_depth: int,
	shadow: Color
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = bottom_depth
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.corner_radius_bottom_right = corner_radius
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7 + bottom_depth
	style.shadow_color = shadow
	style.shadow_size = 4 if bottom_depth > 1 else 2
	style.shadow_offset = Vector2(0, 2 if bottom_depth > 1 else 1)
	style.anti_aliasing = true
	return style


func _add_heading(text: String) -> Label:
	return _add_label(text, 26, HORIZONTAL_ALIGNMENT_CENTER)


func _add_label(text: String, size: int = 14, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", _scaled_font_size(size))
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
	label.add_theme_font_size_override("font_size", _scaled_font_size(14))
	panel.add_child(label)
	return label


func _add_pending_notice() -> void:
	if _notice.is_empty():
		return
	var label := _add_panel_text(_notice, Color("ffcf78"))
	label.name = "PendingNoticeLabel"
	_notice = ""


func _add_button(text: String, callback: Callable, primary: bool = true) -> Button:
	var button := _make_button(text, callback, primary)
	_content.add_child(button)
	return button


func _add_button_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(row)
	return row


func _add_button_to(parent: Container, text: String, callback: Callable) -> Button:
	var button := _make_button(text, callback, false)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	return button


func _make_button(text: String, callback: Callable, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 48 if primary else 44)
	button.add_theme_font_size_override("font_size", _scaled_font_size(16 if primary else 14))
	if primary:
		button.add_theme_stylebox_override("normal", _ui_style_box(
			Color("b85b35"), Color("f3a455"), 11, 5, Color(0.04, 0.025, 0.03, 0.78)
		))
		button.add_theme_stylebox_override("hover", _ui_style_box(
			Color("cc6940"), Color("ffc26f"), 11, 5, Color(0.04, 0.025, 0.03, 0.8)
		))
		button.add_theme_stylebox_override("pressed", _ui_style_box(
			Color("98482e"), Color("f07b43"), 11, 1, Color(0.04, 0.025, 0.03, 0.42)
		))
	button.pressed.connect(callback)
	return button


func _add_spacer(height: int = 18) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	_content.add_child(spacer)
