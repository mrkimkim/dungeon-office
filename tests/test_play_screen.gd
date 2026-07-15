extends RefCounted

const PlayScreenScript = preload("res://src/ui/play_screen.gd")
const VisualCatalogScript = preload("res://src/ui/visual_catalog.gd")


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

	var screen: PlayScreen = PlayScreenScript.new()
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
			"waiting_requests": [],
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
			"rules": {"tick_rate": 20},
			"items": [
				{"id": "MAT_IRON_ORE", "display_name": "철광석"},
				{"id": "MAT_IRON_INGOT", "display_name": "철 주괴"},
				{"id": "EQ_DAGGER", "display_name": "단검"},
			],
			"facilities": [
				{"id": "FAC_SUPPLY", "display_name": "재료 공급함"},
				{"id": "FAC_FURNACE", "display_name": "용광로"},
				{"id": "FAC_TRASH", "display_name": "쓰레기통"},
				{"id": "FAC_WEAPON_BENCH", "display_name": "무기 제작대"},
				{"id": "FAC_SYNTH_BENCH", "display_name": "합성 작업대"},
				{"id": "FAC_ENHANCE_ANVIL", "display_name": "강화 모루"},
			],
			"requests": [{"id": "REQ_DAGGER_STD", "forecast": false}],
		},
		selected_source,
		"테스트 피드백"
	)

	var facility_cells := screen.find_children("FacilityCell_*", "PanelContainer", true, false)
	test.assert_equal(facility_cells.size(), 6, "play screen must keep the fixed 3x2 facility set")
	for required_name: String in [
		"PauseButton",
		"SourceSupply_MAT_IRON_ORE",
		"SourceOutput_FAC_FURNACE",
		"Store_FAC_FURNACE",
		"Start_FAC_WEAPON_BENCH",
		"DestinationDelivery",
		"DestinationTrashAction",
		"DestinationCancel",
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
		"FacilityActionIcon_FAC_DELIVERY",
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
	test.assert_equal(
		furnace_sprite.custom_minimum_size,
		Vector2(56, 56),
		"facility sprites use a stable 56px logical footprint"
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
		"DestinationDelivery",
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
	test.assert_contains(
		(screen.find_child("SourceSupply_MAT_IRON_ORE", true, false) as Button).text,
		"철광석",
		"item artwork must not replace a source button's semantic text"
	)
	test.assert_equal(
		(screen.find_child("DestinationDelivery", true, false) as Button).text,
		"납품",
		"delivery artwork must not replace the existing action text"
	)

	var inventory_destinations := screen.find_children(
		"DestinationInventory_*",
		"Button",
		true,
		false
	)
	test.assert_equal(inventory_destinations.size(), 4, "play screen must show four real inventory slots")
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
		"완료",
		"facility status must have its own live label"
	)
	for button_value: Variant in screen.find_children("*", "Button", true, false):
		var button: Button = button_value
		test.assert_true(
			button.custom_minimum_size.x >= 44.0 and button.custom_minimum_size.y >= 44.0,
			"every play button must have a 44x44 minimum tap target: %s" % button.name
		)
	test.assert_false(
		(screen.find_child("DestinationInventory", true, false) as Button).disabled,
		"authoritative command preview enables a legal inventory destination"
	)
	test.assert_true(
		(screen.find_child("DestinationDelivery", true, false) as Button).disabled,
		"authoritative command preview disables delivery for raw material"
	)
	test.assert_true(
		(screen.find_child("DestinationTrashAction", true, false) as Button).disabled,
		"the infinite supply source cannot be discarded"
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
	var observed_starts: Array[String] = []
	var observed_stores: Array[String] = []
	var pause_count := [0]
	screen.source_requested.connect(func(source: Dictionary) -> void: observed_sources.append(source))
	screen.destination_requested.connect(
		func(destination: Dictionary) -> void: observed_destinations.append(destination)
	)
	screen.start_requested.connect(func(facility_id: String) -> void: observed_starts.append(facility_id))
	screen.store_requested.connect(func(facility_id: String) -> void: observed_stores.append(facility_id))
	screen.pause_requested.connect(func() -> void: pause_count[0] += 1)

	(screen.find_child("SourceSupply_MAT_IRON_ORE", true, false) as Button).pressed.emit()
	(screen.find_child("DestinationDelivery", true, false) as Button).pressed.emit()
	(screen.find_child("Start_FAC_WEAPON_BENCH", true, false) as Button).pressed.emit()
	(screen.find_child("Store_FAC_FURNACE", true, false) as Button).pressed.emit()
	(screen.find_child("PauseButton", true, false) as Button).pressed.emit()
	test.assert_equal(observed_sources, [selected_source], "supply tap must emit its source DTO")
	test.assert_equal(observed_destinations, [{"kind": "delivery"}], "delivery tap must emit destination")
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

	screen.free()
