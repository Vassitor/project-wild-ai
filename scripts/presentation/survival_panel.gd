class_name WildSurvivalPanel
extends PanelContainer
## 行动选择只提交意图。菜单暂停不推进生产，选择成功后关闭菜单回到世界执行。
signal close_requested
signal action_started
var _session: WildLocalSession
var _actor: String
var _body: VBoxContainer
var _message: Label
var _pending_request: String = ""
var _config: WildGameConfig
var _content: WildSurvivalContent

## 连接结束后撤销等待状态；旧房间回执不能锁住下一次动作菜单。
func reset_pending() -> void:
	_pending_request = ""

func configure(session: WildLocalSession, actor: String, config: WildGameConfig = null, content: WildSurvivalContent = null) -> void:
	_session = session
	_actor = actor
	_config = config if config != null else WildGameConfig.new()
	_content = content if content != null else WildSurvivalContent.new()
	_session.command_resolved.connect(_on_command_resolved)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("102219")
	style.border_color = Color("7b8d62")
	style.set_border_width_all(1)
	style.set_content_margin_all(20)
	add_theme_stylebox_override("panel",style)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation",10)
	add_child(_body)

func open(target: Dictionary = {}) -> void:
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	visible = true
	var names: Dictionary = {"tree":"树木","stone":"散石","berry":"浆果丛","root":"根茎","fiber":"纤维植物","herb":"草药","branch":"落枝","spring":"清洁泉水","fish":"鱼点","camp":"临时营地","fire":"篝火","storage_box":"公共储物箱","output":"待领取产出","small_trap":"小型套索","large_trap":"大型陷阱","cooking_table":"料理台","rabbit":"兔栖息地","boar":"野猪栖息地"}
	var title := Label.new()
	title.text = names.get(target.get("kind",""),"料理与营地")
	title.add_theme_font_size_override("font_size",25)
	_body.add_child(title)
	var help := Label.new()
	help.text = "合作菜单不暂停，动作由房主确认；执行中可取消。\n睡眠投票将在完整合作阶段开放。" if _session.is_cooperative() else "选择动作后时间继续推进；执行中可取消。\n睡眠会跳过时间，仍消耗饮水、营养与燃料。"
	help.add_theme_font_size_override("font_size",16)
	_body.add_child(help)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 220 if _session.is_cooperative() else 260
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(scroll)
	var options := VBoxContainer.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_theme_constant_override("separation",8)
	scroll.add_child(options)
	var bag: Dictionary = _session.base_snapshot(_actor)
	var bottle_id: String = ""
	var medicines: Array[Dictionary] = []
	for slot: String in ["off_hand","main_hand","backpack"]:
		for entry: Dictionary in bag["containers"][slot]["entries"]:
			if entry["item"]["item_id"] == "bottle": bottle_id = entry["item"]["id"]
			if entry["item"]["item_id"] in ["bandage","herbal_medicine"]: medicines.append(entry["item"])
	var kind: String = target.get("kind","")
	var levels: Dictionary = bag.get("skills",{}).get("levels",{})
	if kind in ["berry","root","fiber","herb"] and int(levels.get("gathering",0)) >= 1:
		var identified := Label.new()
		identified.text = {"berry":"辨识：浆果补碳水与维生素，可作鱼饵 / 陷阱饵。","root":"辨识：根茎供碳水与矿物质，烤熟有更高碳水。","fiber":"辨识：纤维可制绳 / 陷阱，也可作鱼饵。","herb":"辨识：草药可制药剂，需要医疗节点 1、清水和火源。"}[kind]
		identified.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		options.add_child(identified)
	for medicine: Dictionary in medicines:
		_add(options,"包扎出血 · 绷带 1 · 5 分钟" if medicine["item_id"] == "bandage" else "治疗肠胃不适 · 药剂 1 · 10 分钟",{"action":"treat","item_id":medicine["id"]})
	if kind in ["tree","stone","berry","root","fiber","herb","branch"]:
		_add(options,"伐木 · 斧头 15 分钟 / 小刀 45 分钟" if kind == "tree" else "采集 · 5 分钟",{"action":"gather","resource_id":target["id"],"version":target.get("version",0)})
	elif kind == "spring":
		for litres: float in [0.25,0.5,1.0]:
			_add(options,"直接饮用清水 %.2f L · 1 分钟" % litres,{"action":"drink","resource_id":target["id"],"version":target.get("version",0),"litres":litres})
			_add(options,"取清水 %.2f L · 1 分钟" % litres,{"action":"fill","resource_id":target["id"],"version":target.get("version",0),"item_id":bottle_id,"litres":litres})
	elif kind == "fire":
		_add(options,"取火 · 打火石 5 分钟 / 钻木 20 分钟",{"action":"light","building_id":target["id"]})
		_add(options,"添木材 1 · 增加 2 小时燃料",{"action":"fuel","building_id":target["id"]})
	elif kind == "camp":
		var level: int = int(target.get("level",1))
		var camp_info := Label.new()
		camp_info.text = "营地 %d · 休息回血 ×%.1f" % [level,_content.camp_hp_multipliers[level-1]]
		options.add_child(camp_info)
		if level < 3: _add(options,"升级营地 %d · 90 分钟 · 建造节点 %d" % [level+1,1 if level == 1 else 3],{"action":"upgrade","building_id":target["id"]})
		_add(options,"休息 1 小时 · 实时进行",{"action":"rest","building_id":target["id"],"hours":1})
		if not _session.is_cooperative():
			for hours: int in [1,2,4,8]: _add(options,"睡眠 %d 小时 · 跳时" % hours,{"action":"sleep","building_id":target["id"],"hours":hours})
	elif kind == "output":
		_add_command(options,"领取产出",&"survival.claim_output",{"id":target["id"]})
	elif kind == "fish":
		for bait: String in ["berry","fiber"]:
			_add(options,"捕鱼 · %s饵 1 · 钓具 · 30 分钟" % ("浆果" if bait == "berry" else "纤维"),{"action":"fish","resource_id":target["id"],"version":target["version"],"bait":bait})
			_add(options,"双份捕鱼 · 饵 2 · 捕鱼节点 2",{"action":"fish","resource_id":target["id"],"version":target["version"],"bait":bait,"double":true})
	elif kind in ["small_trap","large_trap"]:
		var status := Label.new()
		status.text = "剩余使用 %d / 3 · 饵 %d / 3 · %s\n只捕获 6 格内的对应实际猎物；无猎物不扣饵。" % [target["uses_left"],target["bait"],"已有捕获，等待收取" if not target["capture"].is_empty() else "距检查 %.1f h" % (maxf(0,target["next_check"]-_session.survival_snapshot(_actor)["elapsed_seconds"])/3600)]
		options.add_child(status)
		_add(options,"收取捕获 · 5 分钟",{"action":"trap_collect","building_id":target["id"]})
		for quantity: int in [1,2,3]: _add(options,"加浆果饵 %d" % quantity,{"action":"trap_bait","building_id":target["id"],"quantity":quantity})
		_add(options,"维护 · 纤维 2 · 恢复 1 次使用 · 10 分钟",{"action":"trap_maintain","building_id":target["id"]})
	elif kind in ["rabbit","boar"]:
		var habitat := Label.new()
		habitat.text = "静态%s栖息标记。附近放置%s并加浆果饵。\n游走 / 战斗将在 P6 开放。" % ["兔" if kind == "rabbit" else "野猪","小套索" if kind == "rabbit" else "大型陷阱"]
		options.add_child(habitat)
		if int(levels.get("hunting",0)) >= 2:
			var tracks := Label.new()
			tracks.text = "足迹辨识：%s，所在格 (%d, %d)，当前存活。" % ["兔" if kind == "rabbit" else "野猪",target["x"],target["y"]]
			options.add_child(tracks)
	if kind not in ["camp","output","fish"]:
		_add(options,"建临时营地 · 木材 8、纤维 6 · 60 分钟",{"action":"build","recipe":"camp"})
		_add(options,"建篝火 · 石材 3、木材 2 · 10 分钟",{"action":"build","recipe":"fire"})
		if _session.is_cooperative(): _add(options,"建公共储物箱 · 木材 6、纤维 4 · 30 分钟",{"action":"build","recipe":"storage_box"})
		_add(options,"烤根茎 · 根茎 1、燃烧篝火 · 10 分钟",{"action":"cook"})
		_add(options,"煮水 · 水壶内生水、燃烧篝火",{"action":"boil","item_id":bottle_id})
	if target.is_empty():
		_add(options,"岸边直接喝生水 0.5 L · 会积累污染风险",{"action":"drink","resource_id":"shore","litres":0.5})
		_add(options,"岸边取生水 0.5 L · 清水与生水不能混装",{"action":"fill","resource_id":"shore","item_id":bottle_id,"litres":0.5})
	if kind not in ["output","fish"]:
		_add(options,"料理台 · 木材 6、石 4、绳 1 · 45 分钟 · 建造 2",{"action":"build","recipe":"cooking_table"})
		_add(options,"小套索 · 纤维 4、木材 1 · 20 分钟 · 陷阱 1",{"action":"build","recipe":"small_trap"})
		_add(options,"大型陷阱 · 木材 4、绳 2、石 2 · 30 分钟 · 陷阱 2",{"action":"build","recipe":"large_trap"})
		for recipe: String in ["rope","arrow","bow","leather_armor","cooked_fish","cooked_meat","stew","herbal_medicine"]:
			var craft_names: Dictionary = {"rope":"绳 · 纤维 4","arrow":"箭 3 · 木材 / 石 / 纤维各 1","bow":"简弓 · 木材 3、绳 1","leather_armor":"皮甲 · 皮 4、绳 2","cooked_fish":"熟鱼 · 生鱼 1、火源","cooked_meat":"熟肉 · 生肉 1、火源","stew":"炖食 · 根茎 / 浆果 / 鱼或肉、清水、料理台 / 火源","herbal_medicine":"草药药剂 · 草药 2、清水、火源"}
			_add(options,"制造 %s · %.0f 分钟" % [craft_names[recipe],_content.recipe(recipe)["minutes"]],{"action":"craft","recipe":recipe})
	if target.get("entity_type","") == "building" or kind in ["camp","fire","cooking_table","small_trap","large_trap","storage_box"]:
		_add(options,"拆除 · 15 分钟 · 返还可回收材料 50%（陷阱另按剩余使用折算）",{"action":"demolish","building_id":target["id"]})
	_message = Label.new()
	_message.text = "条件不足时会说明原因，不扣材料和体力。"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_font_size_override("font_size",15)
	_body.add_child(_message)
	var close := Button.new()
	close.text = "关闭 · 继续探索"
	close.custom_minimum_size.y = 38
	close.pressed.connect(func() -> void: close_requested.emit())
	_body.add_child(close)

func _add(parent: Control,label: String,payload: Dictionary) -> void:
	_add_command(parent,label,&"survival.start",payload)

func _add_command(parent: Control,label: String,operation: StringName,payload: Dictionary) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 36
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	var requirement: Dictionary = _content.recipe(str(payload.get("recipe","")))
	if payload.get("action","") == "fish" and payload.get("double",false): requirement = {"skill":"fishing","tier":2}
	if payload.get("action","") == "upgrade":
		var run: Dictionary = _session.survival_snapshot(_actor)
		var level: int = int(run.get("buildings",{}).get(payload["building_id"],{}).get("level",1))
		requirement = {"skill":"building","tier":1 if level == 1 else 3}
	if requirement.has("skill"):
		var level: int = int(_session.base_snapshot(_actor).get("skills",{}).get("levels",{}).get(requirement["skill"],0))
		if level < int(requirement["tier"]):
			button.disabled = true
			button.text += " · 未解锁"
			button.tooltip_text = "需要%s节点 %d，按 K 查看。" % [_config.skill_rules.branch_names[requirement["skill"]],requirement["tier"]]
	button.pressed.connect(func() -> void:
		if not _pending_request.is_empty(): return
		var result: WildOperationResult = _session.submit(WildGameCommand.new(_actor,operation,payload))
		if result.successful:
			visible = false
			action_started.emit()
		elif result.code == &"PENDING":
			_pending_request = result.payload["request_id"]
			_message.text = "等待房主确认…"
		else: _message.text = WildErrorMessages.describe(result.code))

func _on_command_resolved(request: String, result: WildOperationResult) -> void:
	if request != _pending_request: return
	_pending_request = ""
	if result.successful:
		visible = false
		action_started.emit()
	elif is_instance_valid(_message): _message.text = WildErrorMessages.describe(result.code)

