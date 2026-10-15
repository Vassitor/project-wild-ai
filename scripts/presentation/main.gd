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
var _modal_description: RichTextLabel
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
var _vitals: WildVitalHud
var _header_panel: PanelContainer
var _summary_panel: PanelContainer
var _hint_panel: PanelContainer
var _footer_controls: Label
var _action_progress: ProgressBar
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
var field_guide: WildFieldGuide
var _guide_button: Button


func _ready() -> void:
	if WildCandidateVerification.start(get_tree()):
		queue_free()
		return
	# 跨单机 / 合作仅传档案位置，不能在切换场景时回退到另一个身份或正式档案。
	var handoff: Dictionary = get_tree().get_meta("profile_scene_handoff",{})
	get_tree().remove_meta("profile_scene_handoff")
	if handoff.has("profile"): _profile_path = handoff["profile"]
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
	var base_path: String = str(handoff.get("base","user://base_state.json" if _profile_path == "user://profile_identity.cfg" else _profile_path.get_basename() + "_base.json"))
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--base-store="):
			base_path = argument.trim_prefix("--base-store=")
	# Callable 不保证持有 RefCounted 目标；组合根负责文件适配器的整个生命周期。
	_base_store = WildDurableStateStore.new(base_path)
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
	_details_button.text = "H 身体"
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
	_skills_button.text = "K 技能"
	_skills_button.position = Vector2(24,292)
	_skills_button.size = Vector2(170,38)
	_skills_button.pressed.connect(_open_skills)
	add_child(_skills_button)
	_guide_button = Button.new()
	_guide_button.text = "F1 生存手册"
	_guide_button.pressed.connect(_open_guide)
	add_child(_guide_button)
	field_guide = WildFieldGuide.new()
	add_child(field_guide)
	field_guide.audio = WildUiFeedback.new()
	add_child(field_guide.audio)
	field_guide.audio.configure(self,_profile_path)
	field_guide.close_requested.connect(_close_station)
	session.base_state_changed.connect(_on_base_state_changed)
	session.world_content_changed.connect(_refresh_world_content)
	_on_base_state_changed()
	WildUiLayout.modal_backdrop(self, [_modal, _base_panel, survival_panel, body_details, skill_panel, field_guide])
	resized.connect(_layout_ui)
	_layout_ui()
	_layout_ui.call_deferred()
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


func _unhandled_input(event: InputEvent) -> void:
	if session != null and event.is_action_pressed(&"attack") and session.active_station().is_empty() and wilderness_world.visible:
		wilderness_world.request_attack()
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if session == null:
		return
	if event.is_action_pressed(&"field_guide"):
		if field_guide.visible: _close_station()
		else: _open_guide()
		get_viewport().set_input_as_handled()
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
	wilderness_world.combat_message.connect(func(message: String) -> void: _hint.text = message)
	wilderness_world.inspect_requested.connect(_inspect_resource)
	wilderness_world.visible = false
	wilderness_world.process_mode = Node.PROCESS_MODE_DISABLED
	viewport.add_child(wilderness_world)


func _create_hud() -> void:
	_header_panel = _panel(Rect2(20,16,320,78))
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation",2)
	_header_panel.add_child(heading)
	heading.add_child(_label("荒野之间",26,WildUiTheme.TEXT))
	_subtitle = _label("永久基地 / 森林边境",13,WildUiTheme.MUTED)
	heading.add_child(_subtitle)
	_summary_panel = _panel(Rect2(960,16,300,78))
	var summary_rows := VBoxContainer.new()
	_summary_panel.add_child(summary_rows)
	_summary_title = _label("下一次远行 · 7 日",20,WildUiTheme.GOLD)
	summary_rows.add_child(_summary_title)
	_summary_label = _label("",14,WildUiTheme.MUTED)
	summary_rows.add_child(_summary_label)
	_footer = _panel(Rect2(20,640,870,64))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	_footer.add_child(row)
	for station_id: StringName in WildBaseLayout.STATIONS:
		var button := Button.new()
		button.text = str(WildBaseLayout.STATIONS[station_id]["name"])
		button.custom_minimum_size = Vector2(100,40)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_open_station.bind(station_id))
		row.add_child(button)
	_footer_controls = _label("WASD 移动 · Shift 快走\nE 互动 · Tab 行装 · Esc 暂停",12,WildUiTheme.MUTED)
	_footer_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_footer_controls)
	_hint_panel = _panel(Rect2(380,568,520,48))
	_hint = _label("沿着步道，走近基地设施",14,WildUiTheme.GOLD)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_panel.add_child(_hint)
	_coop_button = Button.new()
	_coop_button.text = "2–4 人合作"
	_coop_button.pressed.connect(_open_coop)
	add_child(_coop_button)
	_return_button = Button.new()
	_return_button.text = "返回基地"
	_return_button.tooltip_text = "放弃生存会失去本局随身物资；确认前会显示说明。"
	_return_button.pressed.connect(_return_from_exploration)
	_return_button.visible = false
	add_child(_return_button)
	_minimap = WildWorldMinimap.new()
	_minimap.position = Vector2(1088,108)
	_minimap.size = Vector2(172,172)
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
	_summary_label.text = "货币 %d · 负重 %.1f / %.0f kg" % [view["currency"], view["carried_weight_kg"], CONFIG.hard_weight_limit_kg]
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
		_summary_title.text = "生存 7 日" if survival_enabled else "荒野探索 · 旧版档案"
		_return_button.text = "放弃本局" if survival_enabled else "结束探索"
	else:
		wilderness_world.leave()
		wilderness_world.get_viewport().canvas_transform = Transform2D.IDENTITY
		_loaded_run_id = ""
		_subtitle.text = "永久基地  /  森林边境" if not in_wilderness else "P1 占位荒野"
		_summary_title.text = "下一次远行 · 7 日"
		_return_button.text = "返回基地"
	_minimap.visible = random_world
	_footer.visible = not in_wilderness
	_coop_button.visible = not in_wilderness
	_layout_ui()
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
			_modal_description.text = WildExpeditionText.result(result,CONFIG)
			_modal_close.text = "返回基地"


func _create_modal() -> void:
	_modal = _panel(Rect2(365, 218, 550, 282))
	_modal.name = "StationPanel"
	_modal.theme_type_variation = &""
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	_modal.add_child(column)
	_modal_title = _label("", 26, Color("f0e2c0"))
	column.add_child(_modal_title)
	# 长结算 / 恢复提示在固定内容区域滚动，不能由 Label 的瞬时折行最小高度撑出视口。
	_modal_description = RichTextLabel.new()
	_modal_description.add_theme_font_size_override("normal_font_size",18)
	_modal_description.add_theme_color_override("default_color",Color("bac9b5"))
	_modal_description.fit_content = false
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
	if field_guide != null: field_guide.visible = false
	if _guide_button != null: _guide_button.visible = false
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
	if field_guide != null: field_guide.visible = false
	if _guide_button != null: _guide_button.visible = true
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
	return {"tree": "树木", "stone": "石材", "berry": "浆果丛", "root": "根茎", "fiber": "纤维植物", "herb": "草药", "branch": "落枝", "fish": "鱼点", "spring": "清洁泉水","camp":"临时营地","fire":"篝火","output":"待领取产出","small_trap":"小套索","large_trap":"大型陷阱","cooking_table":"料理台","storage_box":"公共储物箱","rabbit":"兔","boar":"野猪","wolf":"狼"}.get(kind, kind)


func _create_survival_ui() -> void:
	_body_panel = _panel(Rect2(24,110,700,84))
	_vitals = WildVitalHud.new()
	_body_panel.add_child(_vitals)
	_body_panel.visible = false
	_action_panel = _panel(Rect2(330,636,620,62))
	var row := HBoxContainer.new()
	_action_panel.add_child(row)
	var action_column := VBoxContainer.new()
	action_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_column.add_theme_constant_override("separation",4)
	row.add_child(action_column)
	_action_label = _label("",14,WildUiTheme.TEXT)
	_action_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_column.add_child(_action_label)
	_action_progress = ProgressBar.new()
	_action_progress.show_percentage = false
	_action_progress.custom_minimum_size.y = 8
	action_column.add_child(_action_progress)
	_cancel_action = Button.new()
	_cancel_action.text = "取消动作"
	_cancel_action.pressed.connect(func() -> void: session.submit(WildGameCommand.new(local_player_id,&"survival.cancel")))
	row.add_child(_cancel_action)
	_action_panel.visible = false
	_craft_button = Button.new()
	_craft_button.position = Vector2(24,638)
	_craft_button.size = Vector2(280,52)
	_craft_button.text = "C / B 营地与料理"
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
	var clear_view: bool = not _base_panel.visible and not _modal.visible and not survival_panel.visible and not _abandon_dialog.visible and not body_details.visible and not skill_panel.visible and not field_guide.visible
	_skills_button.visible = clear_view
	_details_button.visible = clear_view
	_body_panel.visible = clear_view
	_action_panel.visible = clear_view
	_craft_button.visible = clear_view
	var body: Dictionary = view["body"]
	_vitals.display(body)
	var elapsed: float = view["elapsed_seconds"]
	var clock_minutes: int = int((28800 + elapsed)/60)
	_summary_title.text = "第 %d 日 %02d:%02d" % [1 + floori(float(clock_minutes)/1440),floori(float(clock_minutes)/60)%24,clock_minutes%60]
	_summary_label.text = "%s · %.1f kg" % [WildExpeditionText.countdown(elapsed+view["pending_seconds"],CONFIG),view["carried_weight_kg"]]
	var action: Dictionary = view["action"]
	_cancel_action.visible = not action.is_empty()
	_action_progress.visible = not action.is_empty()
	if not action.is_empty():
		_action_progress.value = 100.0 * (1.0 - maxf(0.0, action["remaining"] - view["pending_seconds"]) / maxf(1.0, action["duration"]))
	_action_label.text = "%s · 剩余 %.1f 分钟" % [_action_name(action["type"]),maxf(0,action["remaining"] - view["pending_seconds"])/60] if not action.is_empty() else "左键攻击 · E 互动 · C / B 营地 · Tab 行装"
	if not view["notice"].is_empty(): _hint.text = view["notice"]
	if view["save_blocked"]: _hint.text = "保存失败，模拟暂时停止，正在重试。"
	wilderness_world.show_time(elapsed)


func _action_name(kind: String) -> String:
	if kind == "treat": return "治疗"
	return {"gather":"采集 / 伐木","eat":"进食","drink":"饮水","fill":"取水","build":"建造","light":"取火","fuel":"添燃料","cook":"料理","boil":"煮水","rest":"休息","sleep":"睡眠","fish":"捕鱼","craft":"制作","upgrade":"升级营地","trap_bait":"投放陷阱饵","trap_collect":"收取猎物","trap_repair":"维护陷阱","demolish":"拆除建筑","collect_output":"领取产出"}.get(kind,kind)


func _update_hint(station_id: StringName) -> void:
	if _hint == null:
		return
	_hint.text = "[ E ]  %s" % WildBaseLayout.STATIONS[station_id]["name"] if not station_id.is_empty() else "沿着步道，走近基地中的设施"


func _install_theme() -> void:
	theme = WildUiTheme.create()


## 固定逻辑边距和可收缩居中面板；不改变世界相机或业务坐标。
func _layout_ui() -> void:
	if _header_panel == null or _skills_button == null: return
	var area: Vector2 = size
	_header_panel.position = Vector2(20,16)
	_header_panel.size = Vector2(320,78)
	_summary_panel.position = Vector2(area.x-320,16)
	_summary_panel.size = Vector2(300,78)
	_guide_button.position = Vector2(356,22)
	_guide_button.size = Vector2(144,40)
	_footer.position = Vector2(20,area.y-80)
	_footer.size = Vector2(area.x-410,64)
	_footer_controls.visible = area.x >= 1100
	_coop_button.position = Vector2(area.x-218,area.y-74)
	_coop_button.size = Vector2(198,48)
	var in_world: bool = wilderness_world != null and wilderness_world.visible
	_skills_button.position = Vector2(146,area.y-126) if in_world else Vector2(area.x-352,area.y-74)
	_skills_button.size = Vector2(114,40 if in_world else 48)
	_details_button.position = Vector2(20,area.y-126)
	_details_button.size = Vector2(114,40)
	_craft_button.position = Vector2(20,area.y-76)
	_craft_button.size = Vector2(210,52)
	_return_button.position = Vector2(area.x-214,area.y-76)
	_return_button.size = Vector2(194,52)
	_body_panel.position = Vector2(20,108)
	_body_panel.size = Vector2(292,198)
	_action_panel.position = Vector2(250,area.y-78)
	_action_panel.size = Vector2(area.x-484,58)
	_hint_panel.position = Vector2((area.x-520)/2,area.y-136)
	_hint_panel.size = Vector2(520,48)
	_minimap.position = Vector2(area.x-192,108)
	WildUiLayout.center(_base_panel,area,Vector2(1160,600))
	WildUiLayout.center(_modal,area,Vector2(660,410))
	WildUiLayout.center(survival_panel,area,Vector2(760,580))
	WildUiLayout.center(body_details,area,Vector2(840,570))
	WildUiLayout.center(skill_panel,area,Vector2(1120,600))
	WildUiLayout.center(field_guide,area,Vector2(860,600))


func _panel(bounds: Rect2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = bounds.position
	panel.size = bounds.size
	panel.theme_type_variation = &"HudPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	return panel


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _show_startup_error(title: String, message: String) -> void:
	var panel := _panel(Rect2(240, 230, 800, 220))
	var column := VBoxContainer.new()
	panel.add_child(column)
	column.add_child(_label(title, 28, Color("f0e2c0")))
	column.add_child(_label(message, 18, Color("bac9b5")))
	push_error(message)

func _open_coop() -> void:
	var result: WildOperationResult = session.checkpoint(local_player_id)
	if not result.successful:
		_hint.text = WildErrorMessages.describe(result.code)
		return
	get_tree().paused = false
	get_tree().set_meta("profile_scene_handoff",{"profile":_profile_path,"base":_base_store._path})
	get_tree().change_scene_to_file("res://scenes/coop_full.tscn")

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

func _open_guide() -> void:
	session.submit(WildGameCommand.new(local_player_id,&"base.open_pause"))
	_modal.visible = false
	_base_panel.visible = false
	survival_panel.visible = false
	body_details.visible = false
	skill_panel.visible = false
	field_guide.open(session.base_snapshot(local_player_id),CONFIG,CATALOG,SURVIVAL_CONTENT)


