class_name WildFieldGuide
extends PanelContainer
## 两种模式共用的只读手册。调用方决定暂停策略；内容数值从现有 Resource 读取。
signal close_requested
var selector: OptionButton
var text_view: RichTextLabel
var pages: Array[Dictionary] = []
var audio: WildUiFeedback
var _volume: HSlider

func _ready() -> void:
	add_theme_stylebox_override("panel",WildUiTheme.panel())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	add_child(column)
	var title := Label.new()
	title.text = "荒野生存手册 · F1"
	title.add_theme_font_size_override("font_size",24)
	column.add_child(title)
	selector = OptionButton.new()
	selector.custom_minimum_size.y = 38
	selector.item_selected.connect(_select)
	column.add_child(selector)
	text_view = RichTextLabel.new()
	text_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_view.add_theme_font_size_override("normal_font_size",17)
	text_view.bbcode_enabled = false
	column.add_child(text_view)
	var sound_row := HBoxContainer.new()
	column.add_child(sound_row)
	var sound_label := Label.new()
	sound_label.text = "界面音效"
	sound_row.add_child(sound_label)
	_volume = HSlider.new()
	_volume.max_value = 100
	_volume.step = 1
	_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume.value_changed.connect(func(value: float) -> void:
		if audio != null: audio.set_volume(value/100.0))
	sound_row.add_child(_volume)
	var audition := Button.new()
	audition.text = "试听"
	audition.pressed.connect(func() -> void:
		if audio != null: audio.play())
	sound_row.add_child(audition)
	var close := Button.new()
	close.text = "关闭 · Esc / F1"
	close.custom_minimum_size.y = 40
	close.pressed.connect(func() -> void: close_requested.emit())
	column.add_child(close)
	visible = false

## 从调用方提供的快照重建页面；不持有服务 / 网络对象，也不提交任何业务命令。
func open(view: Dictionary, config: WildGameConfig, catalog: WildItemCatalog, content: WildSurvivalContent, cooperative: bool = false) -> void:
	_volume.set_value_no_signal(audio.volume*100.0 if audio != null else 0.0)
	pages = build_pages(view,config,catalog,content,cooperative)
	selector.clear()
	for page: Dictionary in pages: selector.add_item(page["title"])
	_select(0)
	visible = true

func _select(index: int) -> void:
	selector.select(index)
	text_view.text = pages[index]["text"]
	text_view.scroll_to_line(0)

## 返回纯文本页面；配方 / 商品 / 技能数值取当前只读定义，最近结算取历史快照。
static func build_pages(view: Dictionary, config: WildGameConfig, catalog: WildItemCatalog, content: WildSurvivalContent, cooperative: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.append({"title":"起步与出发检查","text":("合作个人菜单不暂停；阅读时请找安全位置。\n" if cooperative else "单机打开菜单暂停，选定长动作后关闭菜单执行。\n")+"\n基地：E 靠近设施 → 补给站购买 → 仓库拖到背包 / 装备槽 → 远行整备 → 确认出发。合作在大厅先提交行装，再准备，由房主全员出发。\n\n"+WildExpeditionText.checklist(view,config,content)+"\n\n第一天：找清泉补水，采浆果与根茎，拾落枝 / 石 / 纤维，建临时营地与篝火。刀主手可防身，打火石可可靠取火。基础行动不需要永久技能；免费刀、水壶、打火石在基地仓库领取后仍需装包。\n\nWASD 移动，Shift 疾跑，E 互动，Tab 行装，R 旋转，Shift 点击拆分；左键朝鼠标方向攻击；C / B 营地料理；H 身体；K 技能。"})
	result.append({"title":"三条食物路线","text":"采集：徒手采浆果与根茎，每次 %.0f 分钟。根茎烤熟提高碳水；浆果补维生素。脂肪与蛋白质偏少，应搭配鱼、肉或干粮。\n\n捕鱼：带钓具，E 鱼点，消耗浆果 / 纤维饵 1；每次 %.0f 分钟，基础成功率 %.0f%%，失败也消耗鱼饵与时间。生鱼烤熟后吃；鱼点每 %.0f 小时补充 %d 份。无技能也可单份捕鱼。\n\n狩猎：主手刀 / 斧近战，无技能要求；兔较安全，野猪与狼会反击。弓和箭需要狩猎 1。杀死实际动物才掉肉和皮，失败挥空也磨损武器。生肉烤熟后吃。陷阱需要技能、投饵和附近对应实际动物。\n\n鱼肉补脂肪与蛋白质，仍需植物补碳水与维生素。食物在 Tab 选中后进食，10 分钟消化生效；生食、腐败食物、生水会积累污染。" % [content.gather_minutes,content.fishing_minutes,content.fishing_probability*100,content.fish_refill_seconds/3600,content.fish_refill_quantity]})
	var recipes: PackedStringArray = ["C / B 打开营地与料理；E 营地 / 火 / 陷阱可直接操作。材料完成时消耗；取消保留已花时间、体力。捕鱼在开始时扣饵。\n"]
	var recipe_names: Dictionary = {"camp":"临时营地","fire":"篝火","storage_box":"公共箱（合作）","roasted_root":"烤根茎","cooking_table":"料理台","small_trap":"小套索","large_trap":"大型陷阱","camp_2":"二级营地","camp_3":"三级营地"}
	var ids: Array = content.recipes.keys()+content.advanced_recipes.keys()
	for id: String in ids:
		var recipe: Dictionary = content.recipe(id)
		var materials: PackedStringArray = []
		for kind: String in recipe["materials"]: materials.append("%s × %d" % [catalog.find(StringName(kind)).display_name,recipe["materials"][kind]])
		if id == "stew": materials.append("生鱼或生肉 × 1")
		var needs: PackedStringArray = []
		if recipe.has("skill"): needs.append("%s %d" % [config.skill_rules.branch_names[recipe["skill"]],recipe["tier"]])
		if recipe.get("fire",false) or id == "roasted_root": needs.append("燃烧篝火")
		if recipe.get("table",false): needs.append("料理台")
		if recipe.has("water_l"): needs.append("清水 %.2f L" % recipe["water_l"])
		var definition: WildItemDefinition = catalog.find(StringName(id))
		var name_text: String = recipe_names.get(id,definition.display_name if definition != null else id)
		recipes.append("%s × %d · %.0f 分钟\n%s%s\n" % [name_text,recipe.get("quantity",1),recipe["minutes"],"、".join(materials),"；需要 "+"、".join(needs) if not needs.is_empty() else "；无技能要求"])
	result.append({"title":"配方与建造","text":"\n".join(recipes)})
	var skills: PackedStringArray = ["K 查看并学习；有效实践由执行者获得经验，每 %d 经验换本分支 1 点。三个节点依次需要 %d / %d / %d 点，或在基地花 %d / %d / %d 货币学习。免费基础行动不依赖学习。\n" % [config.skill_rules.experience_per_point,config.skill_rules.point_costs[0],config.skill_rules.point_costs[1],config.skill_rules.point_costs[2],config.skill_rules.training_costs[0],config.skill_rules.training_costs[1],config.skill_rules.training_costs[2]]]
	for branch: String in WildSkillCatalog.BRANCHES: skills.append("%s：%s\n有效实践 +%d 经验\n" % [config.skill_rules.branch_names[branch]," → ".join(config.skill_rules.descriptions[branch]),config.skill_rules.experience_rewards[branch]])
	result.append({"title":"技能与经济","text":"\n".join(skills)+"\n起始货币 %d；成功基础奖励 %d，探索最多 100，九类有效活动各 10（每类一次）。失败无奖励；成长保留。训练与采购共用资金，首局不必先训练。" % [config.starting_currency,config.success_base_reward]})
	var items: PackedStringArray = ["商品购买进入基地仓库，必须手动装包。只按格子、体积和重量限制，不限制件数。%.0f kg 起减速，%.0f kg 为硬上限；背包容量 %.0f L。\n" % [config.soft_weight_limit_kg,config.hard_weight_limit_kg,config.backpack_capacity_l]]
	for definition: WildItemDefinition in catalog.definitions:
		if definition.purchasable: items.append("%s · %d 货币 · %dx%d 格 · %.2f kg / %.2f L" % [definition.display_name,definition.price,definition.grid_size.x,definition.grid_size.y,definition.unit_weight_kg,definition.unit_volume_l])
	items.append("\nTab 选择实例可进食 / 饮水 / 装备；整理时可旋转、拆分、堆叠。不同料理品质不能合并。负重包括随身装备、水和物资。工具耐久耗尽后不能使用。")
	result.append({"title":"采购与行装","text":"\n".join(items)})
	result.append({"title":"身体、疾病与疗养","text":"H 查看血量、健康、饮水、体力、五类营养和症状；营养分别为糖分、脂肪、蛋白质、矿物质、维生素。\n\n保持饮水并搭配植物与鱼肉。低营养持续会导致衰弱，污染可能引发肠胃不适；吃东西需要消化时间。清泉可直接喝；岸边生水应装壶后在火旁煮净，清水和生水不能混装。\n\n出血：在 E / C 菜单使用绷带包扎。肠胃不适：草药药剂治疗；制作需要医疗 1、草药、火与清水，也可基地购买。衰弱：恢复各类营养并持续疗养。护甲降低物理伤害，会磨损；它不能抵消缺水或饥饿。\n\n原地恢复体力，临时营地可休息回血。睡眠跳时仍模拟身体、燃料、动物与危险；低血量、低水分、出血或附近危险时先处理。"})
	result.append({"title":"合作、保存与返航","text":"2–4 人合作，房主兼玩家。局域网 / IP 直连；任务开始后只允许原成员重连。背包私人，营地箱公开，赠送需对方接受。制作可在下方选择附近公共箱材料。谁执行谁获经验。\n\n全体在线存活成员同意同一睡眠时长后跳时，威胁 / 断线中断。个人菜单不暂停。死亡后观战、无复活，物资留尸体供队友取走；全员死亡失败。到期只有存活者获个人奖励并返还自己的随身物资。\n\n单机自动保存与退出检查点；合作由房主保存世界，各玩家保存个人档案。房主离开保存并结束，不自动迁移；断线角色留在原地，可能死亡。原身份重连同步成长与结算。保存失败时按界面提示重试，不重新建档覆盖。\n\n成功只返还随身物资，营地箱 / 尸体 / 待领取产出不会自动返仓。满仓物资进持久待领取区；回基地仓库腾空后领取。零货币可领取缺少的免费刀 / 水壶 / 打火石再出发，免费物资不能卖钱。"})
	result.append({"title":"最近任务摘要","text":WildExpeditionText.result(view.get("last_settlement",{}),config)})
	return result
