extends RefCounted

const MainScript = preload("res://src/ui/main.gd")

static func run(test: TestFramework) -> void:
	var app: Control = MainScript.new()
	app._build_shell()
	app._show_legal_document("오픈소스 라이선스", {
		"ok": true,
		"text": "긴 법적 고지 문장이 모바일 화면 폭 안에서 자동으로 줄바꿈되어야 합니다.",
	})

	var scrolls := app.find_children("*", "ScrollContainer", true, false)
	var labels := app.find_children("*", "RichTextLabel", true, false)
	test.assert_equal(scrolls.size(), 1, "legal screen must contain one scroll container")
	test.assert_equal(labels.size(), 1, "legal screen must contain one rich text label")
	if scrolls.size() == 1:
		var scroll: ScrollContainer = scrolls[0]
		test.assert_equal(
			scroll.size_flags_horizontal,
			Control.SIZE_EXPAND_FILL,
			"legal scroll must fill the available width"
		)
		test.assert_equal(
			scroll.horizontal_scroll_mode,
			ScrollContainer.SCROLL_MODE_DISABLED,
			"legal scroll must not collapse into an unbounded horizontal document"
		)
	if labels.size() == 1:
		var label: RichTextLabel = labels[0]
		test.assert_equal(
			label.size_flags_horizontal,
			Control.SIZE_EXPAND_FILL,
			"legal text must fill the scroll viewport width"
		)
		test.assert_equal(
			label.autowrap_mode,
			TextServer.AUTOWRAP_WORD_SMART,
			"legal text must wrap long lines on mobile"
		)

	app.free()
