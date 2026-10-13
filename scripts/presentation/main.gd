class_name WildMain
extends Control
## 组合根：注入配置与身份、连接世界意图和会话结果、构建基地界面。
## 界面不修改身体、货币或库存，基地操作经会话提交。

const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const BASE_SCENE: PackedScene = preload("res://scenes/base/base_world.tscn")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const WILDERNESS_SCENE: PackedScene = preload("res://scenes/wilderness/wilderness_placeholder.tscn")
const RANDOM_WORLD_SCENE: PackedScene = preload("res://scenes/wilderness/wilderness_world.tscn")
const SURVIVAL_CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")

var session: WildLocalSession
var local_player_id: String
var base_world: WildBaseWorld
var _modal: PanelContainer
var _modal_title: Label
var _modal_description: Label
var _hint: Label
var _profile_path: String = "user://profile_identity.cfg"
var _base_panel: WildBasePanel
var _placeholder: WildWildernessPlaceholder
var _summary_label: Label
var _return_button: Button
var _footer: PanelContainer
var _base_store: WildBaseStateStore
var wilderness_world: WildWildernessWorld
var _generator: WildWorldGenerator
var _loaded_run_id: String = ""
var _subtitle: Label
var _coop_button: Button
var _summary_title: Label
var _modal_close: Button
var _minimap: WildWorldMinimap
var _autosave_elapsed: float = 0.0
var survival_panel: WildSurvivalPanel
var _body_panel: PanelContainer
var _body_label: Label
var _action_panel: PanelContainer
var _action_label: Label
var _cancel_action: Button
var _craft_button: Button
var _abandon_dialog: ConfirmationDialog
var _shown_result_id: String = ""
var _debug_time_scale: float = 1.0
var body_details: WildBodyDetails
var _details_button: Button
var skill_panel: WildSkillPanel
var _skills_button: Button


func _ready() -> void:
	WildInputBindings.install_defaults()
	_install_theme()
	var errors: PackedStringArray = CONFIG.validate()
	if not errors.is_empty():
		_show_startup_error("配置无法加载", "\n".join(errors))
		return
	# 测试路径通过启动参数注入，正式游戏仍使用每用户身份文件。
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--profile-store="):
			_profile_path = argument.trim_prefix("--profile-store=")
		if OS.is_debug_build() and argument.begins_with("--debug-time-scale="):
			_debug_time_scale = clampf(argument.trim_prefix("--debug-time-scale=").to_float(),1,100)
	var identity: WildOperationResult = WildProfileIdentityStore.new(_profile_path).load_or_create()
	if not identity.successful:
		_show_startup_error("无法读取玩家档案", "请检查档案文件与写入权限。\n错误：%s" % identity.code)
		return
	local_player_id = identity.payload["player_id"]
	session = WildLocalSession.new()
	session.register_player(WildPlayerState.new(local_player_id, identity.payload["display_name"], CONFIG))
	var base_path: String = "user://base_state.json" if _profile_path == "user://profile_identity.cfg" else _profile_path.get_basename() + "_base.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--base-store="):
			base_path = argument.trim_prefix("--base-store=")
	# Callable 不保证持有 RefCounted 目标；组合根负责文件适配器的整个生命周期。
	_base_store = WildBaseStateStore.new(base_path)
	_generator = WildWorldGenerator.new(CONFIG)
	var service := WildBaseService.new(CONFIG, CATALOG, _base_store.load_records, _base_store.save_record, func() -> bool: return RANDOM_WORLD_SCENE.can_instantiate(), _generator.generate,SURVIVAL_CONTENT)
	var initialized: WildOperationResult = service.initialize(local_player_id)
	if not initialized.successful:
		_show_startup_error("无法读取基地档案", "档案没有被覆盖。\n%s" % WildErrorMessages.describe(initialized.code))
		return
	session.register_base_service(local_player_id, service)
	session.station_opened.connect(_on_station_opened)
	session.station_closed.connect(_on_station_closed)
	session.pause_changed.connect(_on_pause_changed)
	_create_world()
	_create_hud()
	_create_modal()
	_create_base_panel()
	_create_survival_ui()
	body_details = WildBodyDetails.new()
	body_details.position = Vector2(270,140)
	body_details.size = Vector2(740,440)
	body_details.configure(session)
	body_details.close_requested.connect(_close_station)
	body_details.care_requested.connect(_open_survival_options)
	body_details.visible = false
	add_child(body_details)
	_details_button = Button.new()
	_details_button.text = "H 身体 / 疗养"
	_details_button.position = Vector2(24,244)
	_details_button.size = Vector2(170,38)
	_details_button.pressed.connect(_open_body_details)
	_details_button.visible = false
	add_child(_details_button)
	skill_panel = WildSkillPanel.new()
	skill_panel.position = Vector2(170,120)
	skill_panel.size = Vector2(940,540)
	skill_panel.configure(session,CONFIG)
	skill_panel.close_requested.connect(_close_station)
	skill_panel.visible = false
	add_child(skill_panel)
	_skills_button = Button.new()
	_skills_button.text = "K 生存技能"
	_skills_button.position = Vector2(24,292)
	_skills_button.size = Vector2(170,38)
	_skills_button.pressed.connect(_open_skills)
	add_child(_skills_button)
	session.base_state_changed.connect(_on_base_state_changed)
	session.world_content_changed.connect(_refresh_world_content)
	_on_base_state_changed()
	get_tree().auto_accept_quit = false


func _notification(what: int) -> void:
	if session == null:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		session.set_focus_lost(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		session.set_focus_lost(false)
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		var saved: WildOperationResult = session.checkpoint(local_player_id)
		if saved.successful:
			get_tree().quit()
		else:
			_hint.text = "保存失败，请关闭面板后重试退出。"


func _process(delta: float) -> void:
	if session == null or wilderness_world == null or not wilderness_world.visible:
		return
	_minimap.player_position = session.world_position(local_player_id)
	_minimap.queue_redraw()
	_update_survival_hud()
	if not session.is_paused():
		_autosave_elapsed += delta
		if _autosave_elapsed >= CONFIG.exploration_autosave_seconds:
			_autosave_elapsed = 0.0
			if not session.checkpoint(local_player_id).successful:
				_hint.text = "位置保存失败，下次检查点将重试。"


func _physics_process(delta: float) -> void:
	if session == null or wilderness_world == null or not wilderness_world.visible: return
	var activity: String = "idle"
	var body: Dictionary = session.survival_snapshot(local_player_id)
	if not Input.get_vector(&"move_left",&"move_right",&"move_up",&"move_down").is_zero_approx():
		activity = "sprint" if Input.is_action_pressed(&"sprint") and not body.is_empty() and body["body"]["stamina"] > 0.001 else "walk"
	session.advance_world(local_player_id,minf(delta,0.1)*_debug_time_scale,activity)


func _unhandled_key_input(event: InputEvent) -> void:
	if session == null:
		return
	if event.is_action_pressed(&"pause"):
		if session.active_station().is_empty():
			session.submit(WildGameCommand.new(local_player_id, &"base.open_pause"))
		else:
			_close_station()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"interact") and session.active_station().is_empty():
		if session.flow.current_phase != WildRunFlow.Phase.WILDERNESS:
			base_world.request_interaction()
		elif wilderness_world.visible:
			wilderness_world.request_interaction()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"inventory"):
		if session.active_station() == &"storage":
			_close_station()
		else:
			_open_station(&"storage")
		get_viewport().set_input_as_handled()
	elif (event.is_action_pressed(&"craft") or event.is_action_pressed(&"build")) and not session.survival_snapshot(local_player_id).is_empty():
		_open_survival_options()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"body_details"):
		if body_details.visible: _close_station()
		else: _open_body_details()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"skills"):
		if skill_panel.visible: _close_station()
		else: _open_skills()
		get_viewport().set_input_as_handled()


func _create_world() -> void:
	var container := SubViewportContainer.new()
	container.name = "WorldView"
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.stretch_shrink = 2
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(container)
	var viewport := SubViewport.new()
	viewport.name = "WorldViewport"
	viewport.size = Vector2i(640, 360)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	base_world = BASE_SCENE.instantiate() as WildBaseWorld
	base_world.configure(CONFIG, local_player_id)
	base_world.interaction_requested.connect(_open_station)
	base_world.interaction_target_changed.connect(_update_hint)
	viewport.add_child(base_world)
	_placeholder = WILDERNESS_SCENE.instantiate() as WildWildernessPlaceholder
	_placeholder.config = CONFIG
	_placeholder.player_id = local_player_id
	_placeholder.visible = false
	_placeholder.process_mode = Node.PROCESS_MODE_DISABLED
	viewport.add_child(_placeholder)
	wilderness_world = RANDOM_WORLD_SCENE.instantiate() as WildWildernessWorld
	wilderness_world.configure(session, local_player_id, CONFIG)
	wilderness_world.target_changed.connect(_on_resource_target)
	wilderness_world.inspect_requested.connect(_inspect_resource)
	wilderness_world.visible = false
	wilderness_world.process_mode = Node.PROCESS_MODE_DISABLED
	viewport.add_child(wilderness_world)


func _create_hud() -> void:
	_coop_button = Button.new()
	_coop_button.position = Vector2(630,32)
	_coop_button.size = Vector2(260,48)
	_coop_button.text = "双人合作验证 · P3.5"
	_coop_button.pressed.connect(_open_coop_validation)
	add_child(_coop_button)
	var header := _panel(Rect2(24, 18, 570, 82))
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 2)
	header.add_child(heading)
	var title := _label("荒野之间", 30, Color("f0e2c0"))
	heading.add_child(title)
	_subtitle = _label("永久基地  /  森林边境", 15, Color("b1c2ad"))
	heading.add_child(_subtitle)
	var summary := _panel(Rect2(920, 18, 336, 82))
	var summary_rows := VBoxContainer.new()
	summary.add_child(summary_rows)
	_summary_title = _label("下一次远行  ·  生存 7 日", 20, Color("e8d8b1"))
	summary_rows.add_child(_summary_title)
	_summary_label = _label("", 14, Color("b1c2ad"))
	summary_rows.add_child(_summary_label)
	var footer := _panel(Rect2(24, 630, 1232, 70))
	_footer = footer
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	footer.add_child(row)
	for station_id: StringName in WildBaseLayout.STATIONS:
		var button := Button.new()
		button.text = str(WildBaseLayout.STATIONS[station_id]["name"])
		button.custom_minimum_size = Vector2(134, 42)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_open_station.bind(station_id))
		row.add_child(button)
	var controls := _label("WASD 移动   Shift 快走   E 交互\nTab 仓库   Esc 关闭 / 暂停", 14, Color("b1c2ad"))
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(controls)
	var hint_panel := _panel(Rect2(410, 563, 460, 45))
	_hint = _label("沿着步道，走近基地中的设施", 16, Color("e8d8b1"))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_panel.add_child(_hint)
	_return_button = Button.new()
	_return_button.position = Vector2(1020, 638)
	_return_button.size = Vector2(236, 52)
	_return_button.text = "返回基地 · 保留物资"
	_return_button.pressed.connect(_return_from_exploration)
	_return_button.visible = false
	add_child(_return_button)
	_minimap = WildWorldMinimap.new()
	_minimap.position = Vector2(1076, 116)
	_minimap.size = Vector2(180, 180)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_minimap.visible = false
	add_child(_minimap)


func _create_base_panel() -> void:
	_base_panel = WildBasePanel.new()
	_base_panel.position = Vector2(40, 106)
	_base_panel.size = Vector2(1200, 590)
	_base_panel.configure(session, local_player_id, CATALOG, CONFIG)
	_base_panel.close_requested.connect(_close_station)
	_base_panel.survival_action_started.connect(_close_station)
	_base_panel.visible = false
	add_child(_base_panel)


func _on_base_state_changed() -> void:
	var view: Dictionary = session.base_snapshot(local_player_id)
	_summary_label.text = "货币 %d    行装 %.2f / %.0f kg" % [view["currency"], view["carried_weight_kg"], CONFIG.hard_weight_limit_kg]
	var in_wilderness: bool = session.flow.current_phase == WildRunFlow.Phase.WILDERNESS
	_coop_button.disabled = session.flow.current_phase != WildRunFlow.Phase.BASE
	var survival_enabled: bool = view.get("survival_enabled",false)
	var random_world: bool = in_wilderness and (view.get("exploration_only", false) or survival_enabled)
	var entered: bool = random_world and _loaded_run_id != view["run_id"]
	base_world.visible = not in_wilderness
	base_world.process_mode = Node.PROCESS_MODE_DISABLED if in_wilderness else Node.PROCESS_MODE_PAUSABLE
	_placeholder.visible = in_wilderness and not random_world
	_placeholder.process_mode = Node.PROCESS_MODE_PAUSABLE if _placeholder.visible else Node.PROCESS_MODE_DISABLED
	if random_world:
		if _loaded_run_id != view["run_id"]:
			var record: Dictionary = session.world_snapshot(local_player_id)
			if not wilderness_world.enter(record):
				_show_startup_error("无法显示荒野", "地图档案未通过检查。")
				return
			_minimap.configure(record)
			_loaded_run_id = view["run_id"]
			_autosave_elapsed = 0.0
		_subtitle.text = "%s · 种子 %s" % ["荒野生存" if survival_enabled else "荒野探索",view["seed"]]
		_summary_title.text = "生存 7 日" if survival_enabled else "探索原型 · 生存模拟待接入"
		_return_button.text = "放弃本局 · 失去随身物资" if survival_enabled else "结束探索 · 恢复行装"
	else:
		wilderness_world.leave()
		wilderness_world.get_viewport().canvas_transform = Transform2D.IDENTITY
		_loaded_run_id = ""
		_subtitle.text = "永久基地  /  森林边境" if not in_wilderness else "P1 占位荒野"
		_summary_title.text = "下一次远行  ·  生存 7 日"
		_return_button.text = "返回基地 · 保留物资"
	_minimap.visible = random_world
	_footer.visible = not in_wilderness
	_return_button.visible = in_wilderness
	_body_panel.visible = survival_enabled
	_action_panel.visible = survival_enabled
	_craft_button.visible = survival_enabled
	_details_button.visible = survival_enabled
	if not survival_enabled: body_details.visible = false
	_refresh_world_content()
	if in_wilderness:
		_hint.text = "WASD 探索 · E 查看资源 · Tab 行装" if random_world else "荒野边缘  ·  可返回基地继续整理行装"
		if not session.active_station().is_empty() and (entered or not session.survival_snapshot(local_player_id).get("action",{}).is_empty()):
			_close_station()
	else:
		_update_hint(base_world.interaction_target())
		var result: Dictionary = view.get("last_settlement",{})
		if not result.is_empty() and result["run_id"] != _shown_result_id:
			_shown_result_id = result["run_id"]
			session.submit(WildGameCommand.new(local_player_id,&"base.open_pause"))
			_modal_title.text = "生存成功" if result["won"] else "本局结束"
			_modal_description.text = "%s · 生存 %.1f 小时\n获得货币 %d\n%s" % [result["reason"],result["elapsed_seconds"]/3600,result["reward"],"随身物资已返仓；满仓物资可在仓库领取。" if result["won"] else "本局随身物资已失去，基地资金和物资保留。"]
			_modal_close.text = "返回基地"


func _create_modal() -> void:
	_modal = _panel(Rect2(365, 218, 550, 282))
	_modal.name = "StationPanel"
	_modal.visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	_modal.add_child(column)
	_modal_title = _label("", 26, Color("f0e2c0"))
	column.add_child(_modal_title)
	_modal_description = _label("", 18, Color("bac9b5"))
	_modal_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modal_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_modal_description)
	var close := Button.new()
	_modal_close = close
	close.text = "返回基地"
	close.custom_minimum_size = Vector2(0, 42)
	close.pressed.connect(_close_station)
	column.add_child(close)


func _open_station(station_id: StringName) -> void:
	var result: WildOperationResult = session.submit(WildGameCommand.new(local_player_id, &"base.open_station", {"station_id": str(station_id)}))
	if not result.successful:
		push_error("Station request rejected: %s" % result.code)


func _close_station() -> void:
	session.submit(WildGameCommand.new(local_player_id, &"base.close_station"))


func _on_station_opened(station_id: StringName) -> void:
	if _skills_button != null: _skills_button.visible = false
	if _details_button != null: _details_button.visible = false
	if skill_panel != null: skill_panel.visible = false
	if body_details != null: body_details.visible = false
	survival_panel.visible = false
	if station_id in [&"supply", &"storage", &"expedition"]:
		_modal.visible = false
		_base_panel.open(station_id)
		return
	_base_panel.visible = false
	if station_id == &"training":
		_modal.visible = false
		skill_panel.open(local_player_id)
		return
	var station: Dictionary = WildBaseLayout.station(station_id)
	_modal_title.text = station["name"]
	_modal_description.text = station["description"]
	_modal_close.text = "继续探索" if wilderness_world.visible else "返回基地"
	if station_id == &"pause" and wilderness_world.visible:
		_modal_title.text = "暂歇片刻"
		_modal_description.text = "单机已暂停，进度已保存。\nC / B 料理与建造，Tab 行装，E 附近互动。\n生存本局不能免费返还行装，放弃会失去随身物资。" if not session.survival_snapshot(local_player_id).is_empty() else "探索已暂停，当前位置已保存。\n关闭后继续；结束探索会恢复出发前行装。"
	_modal.visible = true


func _on_station_closed() -> void:
	if _skills_button != null: _skills_button.visible = true
	if skill_panel != null: skill_panel.visible = false
	if body_details != null: body_details.visible = false
	_modal.visible = false
	_base_panel.visible = false
	survival_panel.visible = false


func _on_pause_changed(paused: bool) -> void:
	get_tree().paused = paused
	if paused and session != null and not session.checkpoint(local_player_id).successful:
		_hint.text = "位置保存失败，关闭面板后可再次尝试。"


func _return_from_exploration() -> void:
	var view: Dictionary = session.base_snapshot(local_player_id)
	if view.get("survival_enabled",false):
		session.submit(WildGameCommand.new(local_player_id,&"base.open_pause"))
		_modal.visible = false
		_abandon_dialog.popup_centered(Vector2i(570,180))
		return
	var operation: StringName = &"expedition.return_exploration" if view.get("exploration_only", false) else &"expedition.return_placeholder"
	var result: WildOperationResult = session.submit(WildGameCommand.new(local_player_id, operation))
	if not result.successful:
		_hint.text = WildErrorMessages.describe(result.code)


func _on_resource_target(entry: Dictionary) -> void:
	_hint.text = "[ E ] 查看 %s" % _resource_name(entry["kind"]) if not entry.is_empty() else "WASD 探索 · E 查看资源 · Tab 行装"


func _inspect_resource(entry: Dictionary) -> void:
	var result: WildOperationResult = session.submit(WildGameCommand.new(local_player_id, &"world.inspect", {"resource_id": entry["id"], "version": entry.get("version",0)}))
	if not result.successful:
		_hint.text = WildErrorMessages.describe(result.code)
		return
	if not session.survival_snapshot(local_player_id).is_empty():
		_open_survival_options(entry)
		return
	session.submit(WildGameCommand.new(local_player_id, &"base.open_pause"))
	_modal_title.text = _resource_name(entry["kind"])
	var descriptions: Dictionary = {"tree": "可用小刀或斧头伐木。", "stone": "地面石材，可用来建篝火和制造工具。", "berry": "食物来源，每次采摘产出 3 份浆果。", "root": "食物来源，每次采摘产出 3 份根茎。", "fiber": "可制造绳索与陷阱。", "herb": "可用来制作草药制剂。", "branch": "不需要工具的木材来源。", "fish": "岸边鱼点，捕鱼需要钓具与鱼饵。", "spring": "清洁水源，可直接饮用，无需容器或净化。"}
	_modal_description.text = "%s\n当前资源储量：%d\n采集、饮水与劳动将在生存阶段开放。" % [descriptions[entry["kind"]], entry["remaining"]]


func _resource_name(kind: String) -> String:
	return {"tree": "树木", "stone": "石材", "berry": "浆果丛", "root": "根茎", "fiber": "纤维植物", "herb": "草药", "branch": "落枝", "fish": "鱼点", "spring": "清洁泉水","camp":"临时营地","fire":"篝火","output":"待领取产出"}.get(kind, kind)


func _create_survival_ui() -> void:
	_body_panel = _panel(Rect2(24,110,700,84))
	_body_label = _label("",15,Color("e9e4bd"))
	_body_panel.add_child(_body_label)
	_body_panel.visible = false
	_action_panel = _panel(Rect2(330,636,620,62))
	var row := HBoxContainer.new()
	_action_panel.add_child(row)
	_action_label = _label("",15,Color("e9e4bd"))
	_action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_action_label)
	_cancel_action = Button.new()
	_cancel_action.text = "取消动作"
	_cancel_action.pressed.connect(func() -> void: session.submit(WildGameCommand.new(local_player_id,&"survival.cancel")))
	row.add_child(_cancel_action)
	_action_panel.visible = false
	_craft_button = Button.new()
	_craft_button.position = Vector2(24,638)
	_craft_button.size = Vector2(280,52)
	_craft_button.text = "C / B 料理、取水与营地"
	_craft_button.pressed.connect(_open_survival_options)
	_craft_button.visible = false
	add_child(_craft_button)
	survival_panel = WildSurvivalPanel.new()
	survival_panel.position = Vector2(315,200)
	survival_panel.size = Vector2(650,425)
	survival_panel.configure(session,local_player_id,CONFIG,SURVIVAL_CONTENT)
	survival_panel.close_requested.connect(_close_station)
	survival_panel.action_started.connect(_close_station)
	survival_panel.visible = false
	add_child(survival_panel)
	_abandon_dialog = ConfirmationDialog.new()
	_abandon_dialog.title = "放弃本局"
	_abandon_dialog.dialog_text = "放弃会失去当前背包和装备，无成功奖励。\n基地货币与仓库物资保留。"
	_abandon_dialog.ok_button_text = "确认放弃"
	_abandon_dialog.cancel_button_text = "继续生存"
	_abandon_dialog.confirmed.connect(func() -> void: session.submit(WildGameCommand.new(local_player_id,&"survival.abandon")))
	_abandon_dialog.canceled.connect(_close_station)
	add_child(_abandon_dialog)


func _open_survival_options(target: Dictionary = {}) -> void:
	if session.survival_snapshot(local_player_id).is_empty(): return
	body_details.visible = false
	session.submit(WildGameCommand.new(local_player_id,&"base.open_pause"))
	_modal.visible = false
	_base_panel.visible = false
	survival_panel.open(target)


func _refresh_world_content() -> void:
	if wilderness_world != null and wilderness_world.visible: wilderness_world.refresh_dynamic(session.world_dynamic(local_player_id))


func _update_survival_hud() -> void:
	var view: Dictionary = session.survival_snapshot(local_player_id)
	if view.is_empty(): return
	var clear_view: bool = not _base_panel.visible and not _modal.visible and not survival_panel.visible and not _abandon_dialog.visible and not body_details.visible and not skill_panel.visible
	_skills_button.visible = clear_view
	_details_button.visible = clear_view
	_body_panel.visible = clear_view
	_action_panel.visible = clear_view
	_craft_button.visible = clear_view
	var body: Dictionary = view["body"]
	var nutrients: Dictionary = body["nutrition"]
	_body_label.text = "血量 %.0f    健康 %.0f    水分 %.0f    体力 %.0f    污染风险 %.0f\n碳水 %.0f   脂肪 %.0f   蛋白质 %.0f   矿物质 %.0f   维生素 %.0f\n%s" % [body["health_points"],body["health"],body["hydration"],body["stamina"],body["pollution"],nutrients[&"carbohydrate"],nutrients[&"fat"],nutrients[&"protein"],nutrients[&"mineral"],nutrients[&"vitamin"],WildBodyDetails.symptoms(body)]
	var elapsed: float = view["elapsed_seconds"]
	var clock_minutes: int = int((28800 + elapsed)/60)
	_summary_title.text = "第 %d 日 %02d:%02d" % [1 + floori(float(clock_minutes)/1440),floori(float(clock_minutes)/60)%24,clock_minutes%60]
	_summary_label.text = "距目标 %.1f 小时 · 行装 %.1f kg" % [maxf(0,CONFIG.target_survival_hours-elapsed/3600),view["carried_weight_kg"]]
	var action: Dictionary = view["action"]
	_cancel_action.visible = not action.is_empty()
	_action_label.text = "%s · 剩余 %.1f 分钟" % [_action_name(action["type"]),maxf(0,action["remaining"] - view["pending_seconds"])/60] if not action.is_empty() else "E 互动 · C / B 料理与营地 · Tab 进食"
	if not view["notice"].is_empty(): _hint.text = view["notice"]
	if view["save_blocked"]: _hint.text = "保存失败，模拟暂时停止，正在重试。"
	wilderness_world.show_time(elapsed)
	_body_label.text += " · " + WildBodyDetails.symptoms(body)


func _action_name(kind: String) -> String:
	if kind == "treat": return "治疗"
	return {"gather":"采集 / 伐木","eat":"进食","drink":"饮水","fill":"取水","build":"建造","light":"取火","fuel":"添燃料","cook":"料理","boil":"煮水","rest":"休息","sleep":"睡眠"}.get(kind,kind)


func _update_hint(station_id: StringName) -> void:
	if _hint == null:
		return
	_hint.text = "[ E ]  %s" % WildBaseLayout.STATIONS[station_id]["name"] if not station_id.is_empty() else "沿着步道，走近基地中的设施"


func _install_theme() -> void:
	var game_theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "SimHei"])
	game_theme.default_font = font
	game_theme.default_font_size = 18
	game_theme.set_stylebox("normal", "Button", _style(Color("2f483b"), Color("58705a")))
	game_theme.set_stylebox("hover", "Button", _style(Color("405a46"), Color("c5aa73")))
	game_theme.set_stylebox("pressed", "Button", _style(Color("24392e"), Color("c5aa73")))
	game_theme.set_color("font_color", "Button", Color("ebdebb"))
	theme = game_theme


func _panel(bounds: Rect2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = bounds.position
	panel.size = bounds.size
	panel.add_theme_stylebox_override("panel", _style(Color(0.065, 0.105, 0.085, 0.94), Color("51644b")))
	add_child(panel)
	return panel


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _show_startup_error(title: String, message: String) -> void:
	var panel := _panel(Rect2(240, 230, 800, 220))
	var column := VBoxContainer.new()
	panel.add_child(column)
	column.add_child(_label(title, 28, Color("f0e2c0")))
	column.add_child(_label(message, 18, Color("bac9b5")))
	push_error(message)

func _open_coop_validation() -> void:
	var result: WildOperationResult = session.checkpoint(local_player_id)
	if not result.successful:
		_hint.text = WildErrorMessages.describe(result.code)
		return
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/coop.tscn")

func _open_body_details() -> void:
	if session.survival_snapshot(local_player_id).is_empty(): return
	session.submit(WildGameCommand.new(local_player_id,&"base.open_pause"))
	_modal.visible = false
	_base_panel.visible = false
	survival_panel.visible = false
	body_details.open(local_player_id)

func _open_skills() -> void:
	session.submit(WildGameCommand.new(local_player_id,&"base.open_pause"))
	_modal.visible = false
	_base_panel.visible = false
	survival_panel.visible = false
	body_details.visible = false
	skill_panel.open(local_player_id)

