class_name WildVitalHud
extends VBoxContainer
## 只读身体快照的紧凑 HUD；血量 / 水分等业务指标由会话计算，视图不做模拟。
var _bars: Dictionary[String, ProgressBar] = {}
var _values: Dictionary[String, Label] = {}
var _nutrition: Label
var _symptoms: Label

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)
	var titles: Dictionary = {"health_points":"血量", "hydration":"水分", "stamina":"体力", "health":"健康"}
	var colors: Dictionary = {"health_points":Color("c67966"), "hydration":Color("75b2c1"), "stamina":Color("d7b365"), "health":Color("91ad70")}
	for id: String in titles:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 3)
		grid.add_child(column)
		var value := Label.new()
		value.text = titles[id]
		value.add_theme_font_size_override("font_size", 14)
		column.add_child(value)
		_values[id] = value
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(116, 8)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override("fill", WildUiTheme.frame(colors[id], colors[id].lightened(0.15), 0))
		column.add_child(bar)
		_bars[id] = bar
	_nutrition = Label.new()
	_nutrition.add_theme_font_size_override("font_size", 13)
	_nutrition.add_theme_color_override("font_color", WildUiTheme.MUTED)
	add_child(_nutrition)
	_symptoms = Label.new()
	_symptoms.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_symptoms.add_theme_font_size_override("font_size", 13)
	add_child(_symptoms)

## 参数是个人身体快照；固定 0–100 显示范围不改变原值或会话状态。
func display(body: Dictionary) -> void:
	if _nutrition == null: return
	for id: String in _bars:
		_bars[id].value = float(body.get(id, 0))
		_values[id].text = "%s  %.0f" % [{"health_points":"血量", "hydration":"水分", "stamina":"体力", "health":"健康"}[id], body.get(id, 0)]
	var nutrients: Dictionary = body.get("nutrition", {})
	_nutrition.text = "碳水 %.0f  脂肪 %.0f  蛋白 %.0f\n矿物 %.0f  维生素 %.0f  污染 %.0f" % [nutrients.get(&"carbohydrate",0), nutrients.get(&"fat",0), nutrients.get(&"protein",0), nutrients.get(&"mineral",0), nutrients.get(&"vitamin",0), body.get("pollution",0)]
	_symptoms.text = WildBodyDetails.symptoms(body)
	_symptoms.add_theme_color_override("font_color", WildUiTheme.GOLD if body.get("hydration",100) < 30 or body.get("health_points",100) < 30 else WildUiTheme.MUTED)
