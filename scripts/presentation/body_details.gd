class_name WildBodyDetails
extends PanelContainer
## 单机 / 合作复用的只读身体面板。暂停策略和治疗意图交给组合根 / 会话。
signal close_requested
signal care_requested
var _session: WildLocalSession
var _actor: String
var _stats: Label
var _nutrition: Label
var _conditions: Label
var _explanation: Label
var _refresh_elapsed: float = 0

func configure(session: WildLocalSession) -> void:
	_session = session
	add_theme_stylebox_override("panel", WildUiTheme.panel())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",15)
	add_child(column)
	var title := Label.new()
	title.text = "身体与疗养 · H"
	title.add_theme_font_size_override("font_size",26)
	title.add_theme_color_override("font_color",WildUiTheme.GOLD)
	column.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 180
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",14)
	scroll.add_child(content)
	_stats = Label.new()
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_stats)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",16)
	content.add_child(row)
	_nutrition = Label.new()
	_nutrition.custom_minimum_size.x = 270
	_nutrition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_nutrition.tooltip_text = "营养储备是 0–100 的游戏指标。衰弱采用压缩病程：任一营养低于 20 连续 24 游戏小时触发。"
	var nutrition_card := PanelContainer.new()
	nutrition_card.theme_type_variation = &"CardPanel"
	nutrition_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nutrition_card)
	var nutrition_column := VBoxContainer.new()
	nutrition_card.add_child(nutrition_column)
	var nutrition_title := Label.new()
	nutrition_title.text = "营养储备"
	nutrition_title.add_theme_color_override("font_color",WildUiTheme.GOLD)
	nutrition_column.add_child(nutrition_title)
	nutrition_column.add_child(_nutrition)
	_conditions = Label.new()
	_conditions.custom_minimum_size.x = 280
	_conditions.tooltip_text = "出血：血量 −4 / h、健康 −1 / h；绷带止血。\n肠胃不适：饮水额外 −2 / h、健康 −2 / h。\n低营养持续 24 h 会衰弱，速度 ×0.85，恢复 ×0.7。"
	_conditions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var conditions_card := PanelContainer.new()
	conditions_card.theme_type_variation = &"CardPanel"
	conditions_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(conditions_card)
	var conditions_column := VBoxContainer.new()
	conditions_card.add_child(conditions_column)
	var conditions_title := Label.new()
	conditions_title.text = "症状与护甲"
	conditions_title.add_theme_color_override("font_color",WildUiTheme.GOLD)
	conditions_column.add_child(conditions_title)
	conditions_column.add_child(_conditions)
	_explanation = Label.new()
	_explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_explanation.add_theme_font_size_override("font_size",16)
	content.add_child(_explanation)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	var care := Button.new()
	care.text = "治疗 / 营地行动"
	care.custom_minimum_size = Vector2(200,40)
	care.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	care.pressed.connect(func() -> void: care_requested.emit())
	buttons.add_child(care)
	var close := Button.new()
	close.text = "关闭 · 继续探索"
	close.custom_minimum_size = Vector2(200,40)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(func() -> void: close_requested.emit())
	buttons.add_child(close)

func open(actor: String) -> void:
	_actor = actor
	visible = true
	refresh()

func _process(delta: float) -> void:
	if not visible: return
	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.25:
		_refresh_elapsed = 0
		refresh()

## 症状提示仅描述可观察的游戏效果；不显示个人疾病随机状态。
static func symptoms(body: Dictionary) -> String:
	var parts: PackedStringArray = []
	if body.get("bleeding",false): parts.append("出血 · 尽快包扎")
	if body.get("gastro_remaining_seconds",0) > 0: parts.append("肠胃不适")
	if body.get("weakness",false): parts.append("衰弱")
	if body.get("dehydrated",false): parts.append("脱水")
	if parts.is_empty() and (body.get("hydration",100) < 30 or body.get("nutrition",{}).values().min() < 30): parts.append("营养或饮水偏低")
	return " / ".join(parts) if not parts.is_empty() else "身体状态稳定"

func refresh() -> void:
	var body: Dictionary = _session.player_snapshot(_actor)
	if body.is_empty() or not body.has("pollution"): return
	_stats.text = "血量 %.1f / 100    健康 %.1f    水分 %.1f    体力 %.1f" % [body["health_points"],body["health"],body["hydration"],body["stamina"]]
	var rows: PackedStringArray = ["营养储备 / 100 · 当前每小时消耗"]
	var names: Array[String] = ["碳水","脂肪","蛋白质","矿物质","维生素"]
	for index: int in range(5):
		rows.append("%s  %.1f   (−%.1f / h)%s" % [names[index],body["nutrition"][WildPlayerState.NUTRIENT_IDS[index]],-body.get("nutrition_rates_per_hour",[0,0,0,0,0])[index]," · 缺乏" if body.get("shortages",[false,false,false,false,false])[index] else ""])
	rows.append("缺乏：低于 20 进入，补至 30 解除。")
	rows.append("食物在 10 分钟内逐渐消化。")
	_nutrition.text = "\n".join(rows)
	var armor: Dictionary = body.get("armor",{"durability":0,"physical_reduction":0})
	_conditions.text = "%s\n污染风险 %.1f · 自然下降 5 / h\n肠胃病程剩余 %.1f h\n药剂冷却剩余 %.1f h\n衰弱恢复进度 %.1f / 6 h\n护甲耐久 %.0f · 物理减伤 %.0f%%" % [symptoms(body),body["pollution"],body.get("gastro_remaining_seconds",0)/3600,body.get("medicine_cooldown_seconds",0)/3600,body.get("weakness_recovery_seconds",0)/3600,armor["durability"],armor["physical_reduction"]*100]
	_explanation.text = "水分消耗 %.1f / h · 体力恢复系数 %.0f%% · 总移动系数 %.0f%%\n体力恢复受碳水、水分和健康影响；18–30 kg 负重降低速度、增加劳动消耗。\n绷带止血；草药药剂缩短肠胃病程 6 h，间隔 2 h；衰弱需五项营养均 ≥30 连续 6 h。\n睡眠遇出血、受伤、血量或水分 ≤20 会中断。%s" % [body.get("water_consumption_per_hour",0),body.get("stamina_recovery_multiplier",1)*100,body.get("movement_multiplier",1)*100,"合作个人菜单持续推进世界。" if _session.is_cooperative() else "单机此面板暂停。"]

