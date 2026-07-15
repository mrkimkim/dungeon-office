extends RefCounted

const MainScript = preload("res://src/ui/main.gd")

static func run(test: TestFramework) -> void:
	test.assert_false(
		bool(ProjectSettings.get_setting("application/config/quit_on_go_back", true)),
		"Android Back must reach the app router before any quit decision"
	)
	var app: Control = MainScript.new()
	app._build_shell()
	app._screen = "title"
	app._clear_content()
	var title_art := app.find_child("TitleForgeArt", true, false) as TextureRect
	test.assert_true(title_art != null, "title screen must include the bundled pseudo-3D forge art")
	if title_art != null:
		test.assert_true(title_art.visible, "title forge art is visible on the title screen")
		test.assert_true(title_art.texture != null, "title forge art texture is loaded offline")
	app._screen = "settings"
	app._clear_content()
	if title_art != null:
		test.assert_false(title_art.visible, "busy title art is hidden behind information screens")
	test.assert_true(app.theme != null, "a shared casual diorama UI theme is installed")
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
	for required_button: String in [
		"CopySupportEmailButton",
		"OpenSupportEmailButton",
		"CopyPublicUrlButton",
		"OpenPublicUrlButton",
	]:
		test.assert_true(
			app.find_child(required_button, true, false) != null,
			"legal screen must expose %s" % required_button
		)
	app._copy_text("https://example.invalid/", "복사 완료")
	test.assert_equal(
		(app.find_child("LegalNoticeLabel", true, false) as Label).text,
		"복사 완료",
		"legal copy fallback must provide visible inline feedback"
	)

	app.free()
