extends RefCounted

const PlayScreenScript = preload("res://src/ui/play_screen.gd")
const VisualCatalogScript = preload("res://src/ui/visual_catalog.gd")


class DragTestPlayScreen extends PlayScreen:
	var forced_drag_data: Variant = null

	func _active_drag_data() -> Variant:
		return forced_drag_data


static func run(test: TestFramework) -> void:
	for facility_id: String in [
		"FAC_SUPPLY",
		"FAC_FURNACE",
		"FAC_WEAPON_BENCH",
		"FAC_SYNTH_BENCH",
		"FAC_ENHANCE_ANVIL",
		"FAC_DELIVERY",
		"FAC_TRASH",
	]:
		test.assert_true(
			VisualCatalogScript.facility_texture(facility_id) != null,
			"visual catalog must resolve facility art for %s" % facility_id
		)
	for item_id: String in [
		"MAT_IRON_ORE",
		"MAT_WOOD",
		"MAT_MANA_SHARD",
		"MAT_IRON_INGOT",
		"MAT_CHARCOAL",
		"MAT_ENHANCEMENT_STONE",
		"EQ_DAGGER",
		"EQ_IRON_SWORD",
	]:
		test.assert_true(
			VisualCatalogScript.item_texture(item_id) != null,
			"visual catalog must resolve item art for %s" % item_id
		)
	test.assert_true(
		VisualCatalogScript.item_texture("ITEM_WITHOUT_ART") == null,
		"an unmapped visual ID must safely fall back to text-only UI"
	)

	var screen := DragTestPlayScreen.new()
	var selected_source := {"kind": "supply", "item_id": "MAT_IRON_ORE"}
	screen.render(
		{
			"id": "R1",
			"display_name": "첫 납품",
			"deadline_ticks": 1800,
			"cutlines": [10, 20, 30],
			"inventory_capacity": 4,
			"supply_items": ["MAT_IRON_ORE"],
		},
		{
			"status": "running",
			"paused": false,
			"tick": 20,
			"deadline_ticks": 1800,
			"score": 10,
			"deliveries": [],
			"waiting_requests": [{
				"event_id": "R1-E2",
				"request_id": "REQ_DAGGER_STD",
				"item_id": "EQ_DAGGER",
				"required_level": 0,
				"score": 10,
				"patience_ticks": 400,
				"remaining_patience_ticks": 400,
				"release_tick": 20,
				"activated_tick": -1,
				"urgent_emitted": false,
			}],
			"active_requests": [{
				"event_id": "R1-E1",
				"request_id": "REQ_DAGGER_STD",
				"item_id": "EQ_DAGGER",
				"required_level": 0,
				"score": 10,
				"remaining_patience_ticks": 400,
			}],
			"workers": [
				{"worker_id": "WORKER_01", "facility_id": ""},
				{"worker_id": "WORKER_02", "facility_id": "FAC_WEAPON_BENCH"},
			],
			"inventory": [null, null, null, null],
			"facilities": {
				"FAC_FURNACE": {
					"status": "output",
					"inputs": [],
					"output": {"item_id": "MAT_IRON_INGOT", "enhancement_level": 0},
					"overheat_remaining_ticks": 100,
				},
				"FAC_WEAPON_BENCH": {
					"status": "ready",
					"inputs": [{"item_id": "MAT_IRON_INGOT", "enhancement_level": 0}],
					"output": null,
				},
			},
		},
		{
			"rules": {
				"tick_rate": 20,
				"overheat_grace_ticks": 160,
				"overheat_danger_ticks": 60,
			},
			"items": [
				{
					"id": "MAT_IRON_ORE",
					"display_name": "철광석",
					"category": "raw_material",
				},
				{
					"id": "MAT_IRON_INGOT",
					"display_name": "철 주괴",
					"category": "processed_material",
				},
				{
					"id": "EQ_DAGGER",
					"display_name": "단검",
					"category": "equipment",
				},
			],
			"facilities": [
				{"id": "FAC_SUPPLY", "display_name": "재료 공급함"},
				{"id": "FAC_FURNACE", "display_name": "용광로"},
				{"id": "FAC_TRASH", "display_name": "쓰레기통"},
				{"id": "FAC_WEAPON_BENCH", "display_name": "무기 제작대"},
				{"id": "FAC_SYNTH_BENCH", "display_name": "합성 작업대"},
				{"id": "FAC_ENHANCE_ANVIL", "display_name": "강화 모루"},
			],
			"recipes": [
				{
					"id": "RCP_SMELT_IRON",
					"facility_id": "FAC_FURNACE",
					"inputs": [{
						"item_id": "MAT_IRON_ORE",
						"enhancement_level": 0,
						"count": 1,
					}],
					"output": {
						"item_id": "MAT_IRON_INGOT",
						"enhancement_level": 0,
						"count": 1,
					},
					"worker_mode": "none",
					"overheat_output": true,
					"duration_ticks": 160,
				},
				{
					"id": "RCP_CRAFT_DAGGER",
					"facility_id": "FAC_WEAPON_BENCH",
					"inputs": [{
						"item_id": "MAT_IRON_INGOT",
						"enhancement_level": 0,
						"count": 1,
					}],
					"output": {
						"item_id": "EQ_DAGGER",
						"enhancement_level": 0,
						"count": 1,
					},
					"worker_mode": "one",
					"overheat_output": false,
					"duration_ticks": 120,
				},
			],
			"requests": [{"id": "REQ_DAGGER_STD", "forecast": false}],
		},
		selected_source,
		"테스트 피드백"
	)

	var facility_cells := screen.find_children("FacilityCell_*", "PanelContainer", true, false)
	test.assert_equal(facility_cells.size(), 6, "play screen must keep the fixed 3x2 facility set")
	test.assert_true(
		screen.find_child("WorkshopBoard", true, false) is PanelContainer,
		"play facilities must live on a dedicated workbench instead of stretching as a form"
	)
	var workshop_floor := screen.find_child("WorkshopFloor", true, false) as Control
	test.assert_true(workshop_floor != null, "the workbench must provide a spatial floor layer")
	test.assert_equal(
		workshop_floor.mouse_filter,
		Control.MOUSE_FILTER_IGNORE,
		"workbench decoration must never intercept drag input"
	)
	for required_name: String in [
		"PauseButton",
		"SourceSupply_MAT_IRON_ORE",
		"SourceOutput_FAC_FURNACE",
		"Store_FAC_FURNACE",
		"Start_FAC_WEAPON_BENCH",
		"DropTargetDelivery",
		"RecipeButton_R1-E1",
	]:
		test.assert_true(
			screen.find_child(required_name, true, false) != null,
			"play screen is missing %s" % required_name
		)
	for required_art_name: String in [
		"FacilitySprite_FAC_FURNACE",
		"RequestIcon_R1-E1",
		"ItemIcon_SourceSupply_MAT_IRON_ORE",
		"ItemIcon_SourceOutput_FAC_FURNACE",
		"ItemIcon_SourceInput_FAC_WEAPON_BENCH_0",
		"FacilityDropIcon_FAC_DELIVERY",
	]:
		test.assert_true(
			screen.find_child(required_art_name, true, false) != null,
			"play screen is missing runtime art node %s" % required_art_name
		)
	var furnace_sprite := screen.find_child(
		"FacilitySprite_FAC_FURNACE",
		true,
		false
	) as TextureRect
	test.assert_true(
		furnace_sprite.custom_minimum_size.x >= 56.0
		and furnace_sprite.custom_minimum_size.x <= 68.0
		and furnace_sprite.custom_minimum_size.y == furnace_sprite.custom_minimum_size.x,
		"facility artwork stays prominent, square, and inside its dedicated layout row"
	)
	test.assert_equal(
		furnace_sprite.get_parent().name,
		"FacilityArtLayer_FAC_FURNACE",
		"facility art must occupy its own row instead of overlapping status text"
	)
	for decoration_value: Variant in screen.find_children("*", "TextureRect", true, false):
		var decoration: TextureRect = decoration_value
		test.assert_equal(
			decoration.mouse_filter,
			Control.MOUSE_FILTER_IGNORE,
			"runtime art must never intercept play input: %s" % decoration.name
		)
		test.assert_equal(
			decoration.texture_filter,
			CanvasItem.TEXTURE_FILTER_LINEAR,
			"scaled runtime art must use linear filtering: %s" % decoration.name
		)
	for decorated_button_name: String in [
		"SourceSupply_MAT_IRON_ORE",
		"SourceOutput_FAC_FURNACE",
		"SourceInput_FAC_WEAPON_BENCH_0",
		"DropTargetDelivery",
	]:
		var decorated_button := screen.find_child(
			decorated_button_name,
			true,
			false
		) as Button
		test.assert_equal(
			decorated_button.texture_filter,
			CanvasItem.TEXTURE_FILTER_LINEAR,
			"buttons containing runtime art must use linear filtering: %s" % decorated_button_name
		)
		test.assert_equal(
			decorated_button.get_theme_color("font_color"),
			Color.TRANSPARENT,
			"decorated buttons must not draw native text over their icon: %s" % decorated_button_name
		)
		test.assert_true(
			decorated_button.clip_text,
			"semantic button text must not expand compact decorated controls: %s" % decorated_button_name
		)
	test.assert_true(
		screen.find_child("SelectedCue_ItemIcon_SourceSupply_MAT_IRON_ORE", true, false) != null,
		"a selected decorated source must retain a non-color shape cue"
	)
	test.assert_contains(
		(screen.find_child("SourceSupply_MAT_IRON_ORE", true, false) as Button).text,
		"철광석",
		"item artwork must not replace a source button's semantic text"
	)
	test.assert_equal(
		(screen.find_child("DropTargetDelivery", true, false) as Button).text,
		"납품대",
		"delivery artwork must not replace the existing action text"
	)
	var delivery_button := screen.find_child("DropTargetDelivery", true, false) as Button
	var bag_button := screen.find_child("DropTargetInventory_0", true, false) as Button
	test.assert_true(
		delivery_button.custom_minimum_size.x >= 88.0
		and delivery_button.custom_minimum_size.y >= 56.0,
		"delivery must read as the primary dock target"
	)
	test.assert_true(
		delivery_button.custom_minimum_size.x >= bag_button.custom_minimum_size.x + 24.0,
		"delivery must be visibly wider than the compact bag target"
	)
	var delivery_icon := screen.find_child(
		"FacilityDropIcon_FAC_DELIVERY",
		true,
		false
	) as TextureRect
	test.assert_true(
		delivery_icon.custom_minimum_size.x >= 40.0
		and delivery_icon.custom_minimum_size.y == delivery_icon.custom_minimum_size.x,
		"delivery receives a dedicated prominent square icon"
	)
	var store_button := screen.find_child("Store_FAC_FURNACE", true, false) as Button
	test.assert_true(
		store_button.custom_minimum_size.x >= 44.0
		and store_button.custom_minimum_size.x <= 76.0
		and store_button.custom_minimum_size.y >= 44.0
		and store_button.custom_minimum_size.y <= 48.0,
		"store stays compact while preserving its accessible tap target"
	)
	test.assert_false(
		bool(store_button.size_flags_horizontal & Control.SIZE_EXPAND),
		"store must not stretch into a full-width facility block"
	)
	var request_content := screen.find_child("RequestContent_R1-E1", true, false) as HBoxContainer
	var request_stack := screen.find_child("RequestTextStack_R1-E1", true, false) as VBoxContainer
	test.assert_equal(
		request_content.get_theme_constant("separation"),
		6,
		"request artwork and text keep an explicit readable gap"
	)
	test.assert_equal(
		request_stack.alignment,
		BoxContainer.ALIGNMENT_CENTER,
		"request copy is vertically centered beside its artwork"
	)
	test.assert_equal(
		(screen.find_child("WaitingRequestLabel", true, false) as Label).text,
		"대기\n1",
		"queued requests use a labeled badge instead of an unexplained +1"
	)
	for spaced_container_name: String in [
		"FacilityGrid",
		"FacilityActionRow_FAC_FURNACE",
		"InventoryActionRow",
	]:
		var spaced_container := screen.find_child(
			spaced_container_name,
			true,
			false
		) as Container
		test.assert_true(
			spaced_container.get_theme_constant("separation") >= 8
			or spaced_container.get_theme_constant("h_separation") >= 8,
			"adjacent tap targets keep an 8px gap: %s" % spaced_container_name
		)
	for aligned_label_name: String in [
		"FacilityName_FAC_FURNACE",
		"FacilityStatus_FAC_FURNACE",
		"WorkerStatusLabel",
	]:
		test.assert_equal(
			(screen.find_child(aligned_label_name, true, false) as Label).vertical_alignment,
			VERTICAL_ALIGNMENT_CENTER,
			"fixed-height text must be vertically centered: %s" % aligned_label_name
		)
	for visual_stack_name: String in [
		"VisualStack_ItemIcon_SourceSupply_MAT_IRON_ORE",
		"VisualStack_ItemIcon_SourceOutput_FAC_FURNACE",
		"VisualStack_FacilityDropIcon_FAC_DELIVERY",
	]:
		var visual_stack := screen.find_child(visual_stack_name, true, false) as VBoxContainer
		test.assert_true(
			visual_stack != null and visual_stack.get_child_count() == 2,
			"decorated buttons separate artwork and caption into two layout rows: %s" % visual_stack_name
		)

	var inventory_destinations := screen.find_children(
		"DropTargetInventory_*",
		"Button",
		true,
		false
	)
	test.assert_equal(
		inventory_destinations.size(),
		1,
		"empty inventory must collapse into one compact bag destination"
	)
	test.assert_equal(
		(screen.find_child("DropTargetInventory_0", true, false) as Button).text,
		"가방\n0/4",
		"the compact bag target must expose capacity without four blank slots"
	)

	screen.play_delivery_impact({"event_id": "R1-E1", "score": 10})
	var impact_layer := screen.find_child("DeliveryImpactLayer", true, false) as Control
	test.assert_true(impact_layer != null, "a successful delivery creates one visual impact layer")
	test.assert_equal(
		str(impact_layer.get_meta("event_id", "")),
		"R1-E1",
		"delivery impact retains the matched request identity"
	)
	test.assert_equal(
		(screen.find_child("DeliveryImpactScore", true, false) as Label).text,
		"+10점",
		"delivery impact names the awarded score"
	)
	test.assert_equal(
		(screen.find_child("DeliveryImpactStamp", true, false) as Label).text,
		"납품 완료!",
		"delivery impact contains a non-color completion stamp"
	)
	for impact_control_value: Variant in impact_layer.find_children("*", "Control", true, false):
		var impact_control := impact_control_value as Control
		test.assert_equal(
			impact_control.mouse_filter,
			Control.MOUSE_FILTER_IGNORE,
			"delivery impact must never block play input: %s" % impact_control.name
		)
	screen.play_delivery_impact({"event_id": "R1-E2", "score": 20})
	var impact_layers := screen.find_children("DeliveryImpactLayer", "Control", true, false)
	test.assert_equal(impact_layers.size(), 1, "repeated deliveries replace rather than stack impact layers")
	test.assert_equal(
		int((impact_layers[0] as Control).get_meta("score", 0)),
		20,
		"a repeated delivery refreshes impact with the latest score"
	)
	screen._structure_signature = ""
	screen.render(
		screen._round_definition,
		screen._round_state,
		screen._catalog,
		selected_source,
		"HUD 재구성 테스트"
	)
	impact_layers = screen.find_children("DeliveryImpactLayer", "Control", true, false)
	test.assert_equal(
		impact_layers.size(),
		1,
		"HUD rebuilds must not cut a delivery impact short"
	)
	test.assert_equal(
		(impact_layers[0] as Control).get_parent().name,
		"DeliveryEffectHost",
		"delivery impact lives on the persistent non-interactive overlay"
	)
	test.assert_equal(
		(screen.find_child("RequestItem_R1-E1", true, false) as Label).text,
		"단검",
		"request identity must not be overwritten by its live timer"
	)
	test.assert_equal(
		(screen.find_child("RequestTimer_R1-E1", true, false) as Label).text,
		"10점 · 20초",
		"request timer must show the live score and patience"
	)
	test.assert_equal(
		(screen.find_child("FacilityName_FAC_FURNACE", true, false) as Label).text,
		"용광로",
		"facility identity must remain separate from its live status"
	)
	test.assert_contains(
		(screen.find_child("FacilityStatus_FAC_FURNACE", true, false) as Label).text,
		"5초 내 이동",
		"a hot output names the action and remaining safe time"
	)
	var overheat_bar := screen.find_child(
		"OverheatBar_FAC_FURNACE",
		true,
		false
	) as ProgressBar
	test.assert_true(overheat_bar != null, "a hot output exposes a persistent visual countdown")
	test.assert_equal(int(overheat_bar.max_value), 160, "the countdown bar uses the full grace period")
	test.assert_equal(int(overheat_bar.value), 100, "the countdown bar reflects live remaining grace")
	test.assert_true(
		screen.find_child("OverheatBar_FAC_WEAPON_BENCH", true, false) == null,
		"non-hot worker outputs never receive a misleading expiry indicator"
	)
	var danger_state: Dictionary = screen._round_state.duplicate(true)
	danger_state["tick"] = 25
	danger_state["facilities"]["FAC_FURNACE"]["overheat_remaining_ticks"] = 60
	screen.render(
		screen._round_definition,
		danger_state,
		screen._catalog,
		selected_source,
		"과열 임박"
	)
	var danger_label := screen.find_child(
		"FacilityStatus_FAC_FURNACE",
		true,
		false
	) as Label
	test.assert_contains(
		danger_label.text,
		"3초 뒤 소실",
		"the danger phase states the exact consequence before the output disappears"
	)
	overheat_bar = screen.find_child("OverheatBar_FAC_FURNACE", true, false) as ProgressBar
	test.assert_equal(int(overheat_bar.value), 60, "the visual countdown updates at danger entry")
	var danger_fill := overheat_bar.get_theme_stylebox("fill") as StyleBoxFlat
	test.assert_equal(
		danger_fill.bg_color,
		Color("ff5d52"),
		"the danger phase changes the persistent countdown from amber to red"
	)
	for button_value: Variant in screen.find_children("*", "Button", true, false):
		var button: Button = button_value
		test.assert_true(
			button.custom_minimum_size.x >= 44.0 and button.custom_minimum_size.y >= 44.0,
			"every play button must have a 44x44 minimum tap target: %s" % button.name
		)
	for removed_destination_name: String in [
		"Destination_FAC_FURNACE",
		"Destination_FAC_WEAPON_BENCH",
		"DestinationTrash",
		"DestinationInventory",
		"DestinationDelivery",
		"DestinationTrashAction",
		"DestinationCancel",
	]:
		test.assert_true(
			screen.find_child(removed_destination_name, true, false) == null,
			"obsolete bottom action must be absent: %s" % removed_destination_name
		)

	var furnace_output_source := {
		"kind": "facility_output",
		"facility_id": "FAC_FURNACE",
	}
	var furnace_output_payload: Dictionary = screen._drag_payload_for_source(
		furnace_output_source
	)
	test.assert_equal(
		str(furnace_output_payload.get("type", "")),
		PlayScreenScript.DRAG_PAYLOAD_TYPE,
		"drag payload uses the stable item-source contract"
	)
	test.assert_equal(
		furnace_output_payload.get("source", {}),
		furnace_output_source,
		"drag payload preserves its authoritative source DTO"
	)
	test.assert_equal(
		furnace_output_payload.get("item", {}).get("item_id", ""),
		"MAT_IRON_INGOT",
		"drag payload includes the inspected item"
	)
	test.assert_true(
		screen._can_drop_payload(
			furnace_output_payload,
			{"kind": "inventory", "slot": 0}
		),
		"a furnace output can be dropped into a specific empty inventory slot"
	)
	test.assert_false(
		screen._can_drop_payload(furnace_output_payload, {"kind": "delivery"}),
		"processed material cannot be dropped on the delivery target"
	)
	test.assert_false(
		screen._can_drop_payload(
			{"type": "wrong-payload", "source": furnace_output_source},
			{"kind": "inventory", "slot": 0}
		),
		"drop validation rejects foreign payload contracts"
	)
	var supply_payload: Dictionary = screen._drag_payload_for_source(selected_source)
	test.assert_false(
		screen._can_drop_payload(supply_payload, {"kind": "trash"}),
		"the infinite supply source cannot be discarded by drag"
	)

	var pause_before := screen.find_child("PauseButton", true, false) as Button
	var next_state: Dictionary = screen._round_state.duplicate(true)
	next_state["tick"] = 40
	next_state["active_requests"][0]["remaining_patience_ticks"] = 380
	screen.render(
		screen._round_definition,
		next_state,
		screen._catalog,
		selected_source,
		"숫자만 갱신"
	)
	var pause_after := screen.find_child("PauseButton", true, false) as Button
	test.assert_equal(
		pause_after.get_instance_id(),
		pause_before.get_instance_id(),
		"timer-only refresh must preserve the HUD tree and avoid layout flicker"
	)
	test.assert_contains(
		str((screen.find_child("FeedbackLabel", true, false) as Label).text),
		"숫자만 갱신",
		"in-place refresh updates feedback text"
	)
	test.assert_equal(
		(screen.find_child("RequestItem_R1-E1", true, false) as Label).text,
		"단검",
		"in-place refresh preserves the request identity"
	)
	test.assert_equal(
		(screen.find_child("RequestTimer_R1-E1", true, false) as Label).text,
		"10점 · 19초",
		"in-place refresh changes only the request timer"
	)
	test.assert_equal(
		(screen.find_child("FacilityName_FAC_FURNACE", true, false) as Label).text,
		"용광로",
		"in-place refresh preserves the facility identity"
	)

	var observed_sources: Array[Dictionary] = []
	var observed_destinations: Array[Dictionary] = []
	var observed_drops: Array[Dictionary] = []
	var observed_recipes: Array[Dictionary] = []
	var observed_starts: Array[String] = []
	var observed_stores: Array[String] = []
	var pause_count := [0]
	screen.source_requested.connect(func(source: Dictionary) -> void: observed_sources.append(source))
	screen.destination_requested.connect(
		func(destination: Dictionary) -> void: observed_destinations.append(destination)
	)
	screen.item_drop_requested.connect(
		func(source: Dictionary, destination: Dictionary) -> void:
			observed_drops.append({
				"source": source,
				"destination": destination,
			})
	)
	screen.recipe_requested.connect(
		func(item_id: String, enhancement_level: int) -> void:
			observed_recipes.append({
				"item_id": item_id,
				"enhancement_level": enhancement_level,
			})
	)
	screen.start_requested.connect(func(facility_id: String) -> void: observed_starts.append(facility_id))
	screen.store_requested.connect(func(facility_id: String) -> void: observed_stores.append(facility_id))
	screen.pause_requested.connect(func() -> void: pause_count[0] += 1)

	(screen.find_child("SourceSupply_MAT_IRON_ORE", true, false) as Button).pressed.emit()
	(screen.find_child("DropTargetDelivery", true, false) as Button).pressed.emit()
	(screen.find_child("RecipeButton_R1-E1", true, false) as Button).pressed.emit()
	(screen.find_child("Start_FAC_WEAPON_BENCH", true, false) as Button).pressed.emit()
	(screen.find_child("Store_FAC_FURNACE", true, false) as Button).pressed.emit()
	(screen.find_child("PauseButton", true, false) as Button).pressed.emit()
	var facility_tap := InputEventMouseButton.new()
	facility_tap.button_index = MOUSE_BUTTON_LEFT
	facility_tap.pressed = true
	screen._on_destination_gui_input(
		facility_tap,
		{"kind": "facility_input", "facility_id": "FAC_WEAPON_BENCH"}
	)
	test.assert_equal(
		observed_destinations,
		[{"kind": "delivery"}],
		"a destination tile must not activate on touch-down"
	)
	facility_tap.pressed = false
	screen._on_destination_gui_input(
		facility_tap,
		{"kind": "facility_input", "facility_id": "FAC_WEAPON_BENCH"}
	)
	var inventory_drop_target := screen.find_child(
		"DropTargetInventory_0",
		true,
		false
	) as Control
	var delivery_drop_target := screen.find_child(
		"DropTargetDelivery",
		true,
		false
	) as Control
	screen._forward_drop_data(
		Vector2.ZERO,
		furnace_output_payload,
		inventory_drop_target
	)
	screen._forward_drop_data(Vector2.ZERO, supply_payload, delivery_drop_target)
	test.assert_equal(observed_sources, [selected_source], "supply tap must emit its source DTO")
	test.assert_equal(observed_destinations, [
		{"kind": "delivery"},
		{"kind": "facility_input", "facility_id": "FAC_WEAPON_BENCH"},
	], "delivery and facility release taps emit their destination DTOs")
	test.assert_equal(observed_drops, [{
		"source": furnace_output_source,
		"destination": {"kind": "inventory", "slot": 0},
	}], "a valid forwarded drop emits one atomic source/destination request")
	test.assert_equal(observed_recipes, [{
		"item_id": "EQ_DAGGER",
		"enhancement_level": 0,
	}], "request recipe action emits the exact requested item and level")
	test.assert_equal(observed_starts, ["FAC_WEAPON_BENCH"], "ready facility must emit start")
	test.assert_equal(observed_stores, ["FAC_FURNACE"], "output facility must emit store")
	test.assert_equal(pause_count[0], 1, "pause tap must emit once")

	var inventory_state: Dictionary = next_state.duplicate(true)
	inventory_state["inventory"][0] = {
		"item_id": "MAT_IRON_INGOT",
		"enhancement_level": 0,
	}
	screen.render(
		screen._round_definition,
		inventory_state,
		screen._catalog,
		{},
		"인벤토리 아이콘"
	)
	test.assert_true(
		screen.find_child("ItemIcon_SourceInventory_0", true, false) != null,
		"occupied inventory slots must retain item artwork"
	)
	test.assert_contains(
		(screen.find_child("SourceInventory_0", true, false) as Button).text,
		"철 주괴",
		"inventory artwork must retain the slot's text label"
	)

	var delivery_state: Dictionary = next_state.duplicate(true)
	delivery_state["inventory"][0] = {
		"item_id": "EQ_DAGGER",
		"enhancement_level": 0,
	}
	screen.render(
		screen._round_definition,
		delivery_state,
		screen._catalog,
		{},
		"납품 가능 장비"
	)
	var dagger_payload: Dictionary = screen._drag_payload_for_source({
		"kind": "inventory",
		"slot": 0,
	})
	test.assert_true(
		screen._can_drop_payload(dagger_payload, {"kind": "delivery"}),
		"matching equipment can be dropped on the delivery target"
	)
	test.assert_false(
		screen._can_drop_payload(
			dagger_payload,
			{"kind": "facility_input", "facility_id": "FAC_FURNACE"}
		),
		"equipment is rejected by an incompatible processing facility"
	)
	screen._set_drop_target_highlights(dagger_payload)
	var highlighted_delivery := screen.find_child(
		"DropTargetDelivery",
		true,
		false
	) as Control
	var rejected_furnace := screen.find_child(
		"FacilityCell_FAC_FURNACE",
		true,
		false
	) as Control
	test.assert_true(
		highlighted_delivery.scale.x > 1.0,
		"a valid drop target receives a non-color scale cue"
	)
	test.assert_equal(
		rejected_furnace.scale,
		Vector2.ONE,
		"an invalid target is not given the valid-target scale cue"
	)
	screen._reset_drop_target_highlights()
	test.assert_equal(
		highlighted_delivery.scale,
		Vector2.ONE,
		"ending a drag resets the target shape cue"
	)

	screen.forced_drag_data = dagger_payload
	var request_withdrawn_state: Dictionary = delivery_state.duplicate(true)
	request_withdrawn_state["active_requests"] = []
	screen.render(
		screen._round_definition,
		request_withdrawn_state,
		screen._catalog,
		{},
		"드래그 중 의뢰 철회"
	)
	test.assert_false(
		bool(highlighted_delivery.get_meta("drop_valid", true)),
		"render revalidates a destination whose legality changes during a drag"
	)
	test.assert_equal(
		highlighted_delivery.scale,
		Vector2.ONE,
		"a destination that becomes invalid loses its shape cue during the drag"
	)
	screen.forced_drag_data = null
	screen._reset_drop_target_highlights()
	screen.render(
		screen._round_definition,
		delivery_state,
		screen._catalog,
		{},
		"드래그 종료"
	)

	var paused_state: Dictionary = delivery_state.duplicate(true)
	paused_state["paused"] = true
	screen.render(
		screen._round_definition,
		paused_state,
		screen._catalog,
		{},
		"일시정지"
	)
	test.assert_true(
		screen._drag_payload_for_source({"kind": "inventory", "slot": 0}).is_empty(),
		"paused play cannot create a draggable item payload"
	)
	test.assert_false(
		screen._can_drop_payload(
			furnace_output_payload,
			{"kind": "inventory", "slot": 1}
		),
		"paused play rejects an otherwise legal drop"
	)

	var full_inventory_state: Dictionary = delivery_state.duplicate(true)
	full_inventory_state["paused"] = false
	full_inventory_state["inventory"] = [
		{"item_id": "EQ_DAGGER", "enhancement_level": 0},
		{"item_id": "MAT_IRON_INGOT", "enhancement_level": 0},
		{"item_id": "MAT_IRON_INGOT", "enhancement_level": 0},
		{"item_id": "MAT_IRON_INGOT", "enhancement_level": 0},
	]
	screen.set_display_options({"large_text_enabled": true})
	screen.render(
		screen._round_definition,
		full_inventory_state,
		screen._catalog,
		{},
		"큰 글씨 · 가득 찬 가방"
	)
	test.assert_equal(
		screen.find_children("SourceInventory_*", "Button", true, false).size(),
		4,
		"large-text mode keeps every occupied inventory source"
	)
	test.assert_true(
		screen.find_children("DropTargetInventory_*", "Button", true, false).is_empty(),
		"a full inventory does not create a misleading empty bag target"
	)
	var large_delivery_caption := screen.find_child(
		"FacilityDropIcon_FAC_DELIVERY_Text",
		true,
		false
	) as Label
	test.assert_equal(
		large_delivery_caption.max_lines_visible,
		1,
		"large-text delivery caption stays on one dedicated row"
	)
	test.assert_true(
		(screen.find_child("DropTargetDelivery", true, false) as Button).custom_minimum_size.x >= 88.0,
		"large-text mode preserves the prominent delivery target"
	)

	var dense_round_definition: Dictionary = screen._round_definition.duplicate(true)
	dense_round_definition["id"] = "R5"
	dense_round_definition["supply_items"] = [
		"MAT_IRON_ORE",
		"MAT_WOOD",
		"MAT_MANA_SHARD",
	]
	var dense_state: Dictionary = full_inventory_state.duplicate(true)
	dense_state["active_requests"] = []
	for request_index: int in range(3):
		dense_state["active_requests"].append({
			"event_id": "R5-E%d" % (request_index + 1),
			"request_id": "REQ_DAGGER_STD",
			"item_id": "EQ_DAGGER",
			"required_level": 1 if request_index == 2 else 0,
			"score": 10,
			"remaining_patience_ticks": 400,
		})
	screen.render(
		dense_round_definition,
		dense_state,
		screen._catalog,
		{},
		"큰 글씨 · 의뢰 3개 · 공급품 3개"
	)
	test.assert_true(
		screen.find_child("FacilitySprite_FAC_SUPPLY", true, false) == null,
		"a two-row supply grid yields decorative art space to usable controls"
	)
	test.assert_equal(
		screen.find_children("SourceSupply_*", "Button", true, false).size(),
		3,
		"dense late-round supply keeps all three draggable materials"
	)
	var dense_request_row := screen.find_child("RequestTicketRow", true, false) as HBoxContainer
	var dense_request_minimum_width := 0.0
	for dense_child: Node in dense_request_row.get_children():
		if dense_child is Control:
			dense_request_minimum_width += (dense_child as Control).get_combined_minimum_size().x
	dense_request_minimum_width += float(
		maxi(0, dense_request_row.get_child_count() - 1)
		* dense_request_row.get_theme_constant("separation")
	)
	test.assert_true(
		dense_request_minimum_width <= 328.0,
		"three active requests plus a waiting badge fit the mobile content width"
	)
	for dense_recipe_value: Variant in screen.find_children(
		"RecipeButton_R5-*",
		"Button",
		true,
		false
	):
		var dense_recipe := dense_recipe_value as Button
		test.assert_true(
			dense_recipe.clip_text and dense_recipe.custom_minimum_size.x <= 80.0,
			"dense request cards cap semantic text width: %s" % dense_recipe.name
		)
	test.assert_true(
		(screen.find_child("RequestItem_R5-E3", true, false) as Label).text.begins_with("+1"),
		"compact enhanced requests keep the required level before any ellipsis"
	)

	screen.free()
