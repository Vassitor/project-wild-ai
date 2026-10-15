class_name WildUiTheme
extends RefCounted
## 单机 / 合作共享的纯表现主题：Ninja 木框、营地色板与控件状态，不拥有玩法数据。

const TEXT := Color("f1e4c6")
const MUTED := Color("b5bea5")
const GOLD := Color("dfba7a")
const BACKGROUND := Color("172b25")
const WOOD: Texture2D = preload("res://assets/ninja_adventure/ui/nine_path_panel.png")
const BUTTON_NORMAL: Texture2D = preload("res://assets/ninja_adventure/ui/button_normal.png")
const BUTTON_HOVER: Texture2D = preload("res://assets/ninja_adventure/ui/button_hover.png")
const BUTTON_PRESSED: Texture2D = preload("res://assets/ninja_adventure/ui/button_pressed.png")
const BUTTON_DISABLED: Texture2D = preload("res://assets/ninja_adventure/ui/button_disabled.png")

## 每个组合根创建独立 Theme；图片共享只读，控件状态由 Godot 管理。
static func create() -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "SimHei"])
	theme.default_font = font
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color("fff2d5"))
	theme.set_color("font_disabled_color", "Button", Color("8b8e7e"))
	theme.set_stylebox("normal", "Button", _wood(BUTTON_NORMAL, 4, 8))
	theme.set_stylebox("hover", "Button", _wood(BUTTON_HOVER, 4, 8))
	theme.set_stylebox("pressed", "Button", _wood(BUTTON_PRESSED, 4, 8))
	theme.set_stylebox("disabled", "Button", _wood(BUTTON_DISABLED, 4, 8))
	theme.set_stylebox("focus", "Button", frame(Color(0,0,0,0), GOLD, 0))
	theme.set_stylebox("panel", "PanelContainer", panel())
	theme.set_type_variation("HudPanel", "PanelContainer")
	theme.set_stylebox("panel", "HudPanel", frame(Color("192e27"), Color("876b49"), 12))
	theme.set_type_variation("CardPanel", "PanelContainer")
	theme.set_stylebox("panel", "CardPanel", card())
	for type: String in ["LineEdit", "ItemList", "TextEdit"]:
		theme.set_stylebox("normal", type, frame(Color("10231f"), Color("566652"), 8))
		theme.set_stylebox("focus", type, frame(Color("142923"), GOLD, 8))
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_placeholder_color", type, MUTED)
	theme.set_stylebox("selected", "ItemList", frame(Color("53604a"), GOLD, 4))
	theme.set_stylebox("selected_focus", "ItemList", frame(Color("53604a"), GOLD, 4))
	theme.set_stylebox("background", "ProgressBar", frame(Color("0f201b"), Color("435747"), 0))
	theme.set_stylebox("fill", "ProgressBar", frame(Color("8daf71"), Color("a9c38b"), 0))
	for type: String in ["VBoxContainer", "HBoxContainer", "HFlowContainer"]:
		theme.set_constant("separation", type, 10)
	theme.set_constant("h_separation", "HFlowContainer", 10)
	theme.set_constant("v_separation", "HFlowContainer", 8)
	return theme

static func _wood(texture: Texture2D, margin: int, padding: int) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = margin
	style.texture_margin_right = margin
	style.texture_margin_top = margin
	style.texture_margin_bottom = margin
	style.set_content_margin_all(padding)
	style.content_margin_left = maxi(padding, 12)
	style.content_margin_right = maxi(padding, 12)
	return style

## 木框适合主面板；内部卡片和 HUD 用薄框，避免反复叠加厚边。
static func panel() -> StyleBoxTexture:
	return _wood(WOOD, 8, 20)

static func card() -> StyleBoxFlat:
	return frame(Color("20362e"), Color("52634b"), 12)

static func frame(background: Color, border: Color, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_content_margin_all(padding)
	return style
