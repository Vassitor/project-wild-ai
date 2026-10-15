class_name WildCoopMain
extends Control
## P3.5 双人验证组合根。独立房间 / 身份 / 凭据，不触碰单机基地档案。
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")
var network: WildENetRoom
var session: WildCoopReplicaSession
var world_view: WildWildernessWorld
var survival_panel: WildSurvivalPanel
var body_details: WildBodyDetails
var skill_panel: WildSkillPanel
var _top_panel: PanelContainer
var _bottom_panel: PanelContainer
var _lobby: PanelContainer
var _inventory: PanelContainer
var _inventory_columns: HBoxContainer
var _grids: Dictionary[String, WildInventoryGrid] = {}
var _grid_signature: String = ""
var _hud: Label
var _status: Label
var _selection: Label
var _address: LineEdit
var _name_input: LineEdit
var _seed: LineEdit
var _port: SpinBox
var _start: Button
var _profile_override: String = ""
var _room_path: String = "user://coop_validation_room.json"
var _identity_path: String = ""
var _store: WildBaseStateStore
var _credentials: WildBaseStateStore
var _credential_data: Dictionary = {}
var _credential_key: String = ""
var _selected_container: String = ""
var _selected_item: String = ""
var _loaded_run: String = ""
var _exiting: bool = false
var _handling_end: bool = false
var _credentials_recovered: bool = false
var field_guide: WildFieldGuide

func full_mode() -> bool:
	return false

func _ready() -> void:
	WildInputBindings.install_defaults()
	_install_theme()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--coop-profile="): _profile_override = argument.trim_prefix("--coop-profile=")
		if argument.begins_with("--coop-room="): _room_path = argument.trim_prefix("--coop-room=")
	_store = WildBaseStateStore.new(_room_path)
	network = WildENetRoom.new()
	network.name = "Network"
	add_child(network)
	network.snapshot_received.connect(_on_snapshot)
	network.connection_status.connect(_set_status)
	network.command_completed.connect(_on_result)
	network.room_ended.connect(_on_ended)
	session = WildCoopReplicaSession.new()
	_create_world()
	_create_ui()
	WildUiLayout.modal_backdrop(self, [_inventory, survival_panel, body_details, skill_panel])
	resized.connect(_layout_ui)
	_layout_ui()
	_layout_ui.call_deferred()
	get_tree().auto_accept_quit = false

func _install_theme() -> void:
	theme = WildUiTheme.create()

## 合作界面使用相同逻辑视口布局；遮罩不修改合作会话的持续模拟策略。
func _layout_ui() -> void:
	if _top_panel == null or skill_panel == null: return
	var area: Vector2 = size
	_top_panel.position = Vector2(20,16)
	_top_panel.size = Vector2(area.x-40,86)
	var toolbar_height: float = 148 if area.x < 1160 else 128
	_bottom_panel.position = Vector2(20,area.y-toolbar_height-16)
	_bottom_panel.size = Vector2(area.x-40,toolbar_height)
	_lobby.size = Vector2(minf(780,area.x-40),maxf(260,area.y-280))
	_lobby.position = Vector2((area.x-_lobby.size.x)/2,114)
	WildUiLayout.center(_inventory,area,Vector2(1120,560))
	WildUiLayout.center(survival_panel,area,Vector2(760,580))
	WildUiLayout.center(body_details,area,Vector2(840,570))
	WildUiLayout.center(skill_panel,area,Vector2(1120,600))
	if field_guide != null: WildUiLayout.center(field_guide,area,Vector2(860,600))

func _create_world() -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.stretch_shrink = 2
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640,360)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	world_view = preload("res://scenes/wilderness/wilderness_world.tscn").instantiate() as WildWildernessWorld
	world_view.visible = false
	world_view.process_mode = Node.PROCESS_MODE_DISABLED
	world_view.inspect_requested.connect(_open_actions)
	world_view.combat_message.connect(func(message: String) -> void: _status.text = message)
	viewport.add_child(world_view)

func _panel(bounds: Rect2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = bounds.position
	panel.size = bounds.size
	panel.theme_type_variation = &"HudPanel"
	add_child(panel)
	return panel

func _label(parent: Node, value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size",15)
	parent.add_child(label)
	return label

func _button(parent: Node, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 38
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _create_ui() -> void:
	var top := _panel(Rect2(20,16,1240,86))
	_top_panel = top
	_hud = _label(top,"2–4 人合作 · 个人行装 / 共享营地" if full_mode() else "双人合作 · 验证版\n私人背包 / 公共营地 · 个人菜单不暂停")
	_hud.add_theme_font_size_override("font_size",14)
	var bottom := _panel(Rect2(20,576,1240,128))
	_bottom_panel = bottom
	var column := VBoxContainer.new()
	bottom.add_child(column)
	_status = _label(column,"在个人基地整理行装，再建房或加入；提交后物资由房主世界托管。" if full_mode() else "新建或连接房间。本入口使用独立验证物资，不消耗永久基地物资。")
	var row := HFlowContainer.new()
	row.add_theme_constant_override("separation",12)
	column.add_child(row)
	_start = _button(row,"房主：全员出发" if full_mode() else "房主：两人出发",_start_run)
	_start.disabled = true
	_button(row,"Tab 行装 / 公共箱",_open_inventory)
	_button(row,"C / B 料理与营地",_open_actions)
	_button(row,"H 身体",_open_body_details)
	_button(row,"K 技能",_open_skills)
	_button(row,"F1 手册 / 摘要",_open_guide)
	_button(row,"取消动作",_cancel_action)
	_button(row,"断开 / 保存结束",_leave)
	_button(row,"返回单机",_back_to_base)
	field_guide = WildFieldGuide.new()
	add_child(field_guide)
	field_guide.close_requested.connect(_close_menus)
	field_guide.audio = WildUiFeedback.new()
	add_child(field_guide.audio)
	# 完整合作在身份确定后绑定同一份本地音效偏好；独立入口亦使用自己的身份路径。
	WildUiLayout.modal_backdrop(self,[field_guide])
	_lobby = _panel(Rect2(250,114,780,440))
	_lobby.theme_type_variation = &""
	var lobby_column := VBoxContainer.new()
	lobby_column.add_theme_constant_override("separation",12)
	var lobby_scroll := ScrollContainer.new()
	lobby_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_lobby.add_child(lobby_scroll)
	lobby_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_scroll.add_child(lobby_column)
	_label(lobby_column,"2–4 人合作 · 房主承载世界 · ENet / UDP" if full_mode() else "合作验证：房主承载世界 · ENet / UDP")
	_label(lobby_column,"全员提交个人行装并准备后出发；途中仅原成员可重连。\n死亡观战、尸体可取；全体在线存活者同意后睡眠跳时。" if full_mode() else "两人连接后由房主出发，途中只允许原成员重连。\n死亡观战、睡眠投票和逐人奖励将在 P6.5 完成。")
	_name_input = LineEdit.new()
	_name_input.text = "生存者"
	_name_input.placeholder_text = "昵称（最多 32 字）"
	_name_input.max_length = 32
	lobby_column.add_child(_name_input)
	var endpoint := HBoxContainer.new()
	lobby_column.add_child(endpoint)
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	_address.placeholder_text = "房主 IP"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	endpoint.add_child(_address)
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = CONFIG.default_network_port
	endpoint.add_child(_port)
	_seed = LineEdit.new()
	_seed.placeholder_text = "地图种子，留空随机"
	lobby_column.add_child(_seed)
	var actions := HFlowContainer.new()
	lobby_column.add_child(actions)
	_button(actions,"新建合作房间" if full_mode() else "新建验证房间",_host.bind(false))
	_button(actions,"恢复房主存档",_host.bind(true))
	_button(actions,"连接 / 原身份重连",_join)
	_label(lobby_column,"使用个人基地的仓库、货币和永久技能；空间 / 体积 / 负重限制沿用单机。\n断线行装不自动返还；恢复原房间后同步。房主档案按房间保留。\n好友合作信任本地档案；不同玩法或内容版本拒绝连接。" if full_mode() else "验证包：小刀、打火石、水壶、16 木材、10 纤维、3 石材、3 干粮。\n新建另有钓具、2 绷带 / 2 草药药剂；旧档恢复不补发。\n出发前按 K 可用 600 验证资金学习技能。\n新建会覆盖独立验证房间；恢复沿用旧世界与成员。\n同机两窗口默认分别使用房主 / 队员验证身份。")
	_inventory = _panel(Rect2(80,80,1120,560))
	_inventory.theme_type_variation = &""
	_inventory.visible = false
	var inventory_column := VBoxContainer.new()
	_inventory.add_child(inventory_column)
	var inventory_title: Label = _label(inventory_column,"行装与公共箱")
	inventory_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	inventory_title.add_theme_font_size_override("font_size",26)
	inventory_title.add_theme_color_override("font_color",WildUiTheme.GOLD)
	_label(inventory_column,"私人背包与附近公共箱 · 拖放整理 / R 旋转 · 世界持续推进").autowrap_mode = TextServer.AUTOWRAP_OFF
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 140
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_column.add_child(scroll)
	_inventory_columns = HBoxContainer.new()
	_inventory_columns.add_theme_constant_override("separation",24)
	scroll.add_child(_inventory_columns)
	_selection = _label(inventory_column,"选中食物后进食，选中水壶后饮水。")
	_selection.autowrap_mode = TextServer.AUTOWRAP_OFF
	var tools_row := HFlowContainer.new()
	inventory_column.add_child(tools_row)
	_button(tools_row,"进食选中物品",_use_selected.bind("eat"))
	_button(tools_row,"饮水 0.5 L",_use_selected.bind("drink"))
	_button(tools_row,"治疗选中药品",_use_selected.bind("treat"))
	_button(tools_row,"拆除附近空箱",_demolish_empty_box)
	_button(tools_row,"拆分一半（选中后点击）",_split_selected)
	_button(tools_row,"关闭",_close_menus)
	survival_panel = WildSurvivalPanel.new()
	survival_panel.position = Vector2(310,155)
	survival_panel.size = Vector2(660,425)
	survival_panel.visible = false
	add_child(survival_panel)
	body_details = WildBodyDetails.new()
	body_details.position = Vector2(270,135)
	body_details.size = Vector2(740,445)
	body_details.configure(session)
	body_details.close_requested.connect(_close_menus)
	body_details.care_requested.connect(_open_actions)
	body_details.visible = false
	add_child(body_details)
	skill_panel = WildSkillPanel.new()
	skill_panel.position = Vector2(170,120)
	skill_panel.size = Vector2(940,470)
	skill_panel.configure(session,CONFIG)
	skill_panel.close_requested.connect(_close_menus)
	skill_panel.visible = false
	add_child(skill_panel)

func _select_identity(role: String) -> bool:
	_identity_path = _profile_override if not _profile_override.is_empty() else "user://coop_%s_profile.cfg" % role
	var identity: WildOperationResult = WildProfileIdentityStore.new(_identity_path).load_or_create()
	if not identity.successful:
		_set_status("无法读取验证身份："+str(identity.code))
		return false
	var actor: String = identity.payload["player_id"]
	if field_guide.audio._owner == null: field_guide.audio.configure(self,_identity_path)
	if _name_input.text.strip_edges().is_empty(): _name_input.text = "生存者"
	_credentials = WildBaseStateStore.new(_identity_path.get_basename()+"_credentials.json")
	var loaded: WildOperationResult = _credentials.load_records()
	_credential_data = loaded.payload["primary"]
	_credentials_recovered = false
	if _credential_data.get("credentials_version",1) != 1:
		_set_status("凭据版本不兼容，未覆盖。")
		return false
	if _credential_data.has("actor") and _credential_data["actor"] != actor:
		_set_status("凭据属于其他身份，未覆盖。")
		return false
	if loaded.payload["exists"] and (_credential_data.get("actor","") != actor or not _credential_data.get("tokens",null) is Dictionary):
		_credential_data = loaded.payload["backup"]
		_credentials_recovered = true
	if not loaded.payload["exists"]: _credential_data = {"credentials_version":1,"actor":actor,"tokens":{}}
	if _credential_data.get("credentials_version",1) != 1 or _credential_data.get("actor","") != actor or not _credential_data.get("tokens",null) is Dictionary:
		_set_status("重连凭据无法读取，未覆盖。")
		return false
	_credential_key = "host" if role == "host" else "%s:%d" % [_address.text.strip_edges(),int(_port.value)]
	var secret: String = str(_credential_data["tokens"].get(_credential_key,""))
	network.configure_identity(actor,_name_input.text.strip_edges(),secret,_save_token)
	session.configure(network,actor,CONFIG,CATALOG)
	world_view.configure(session,actor,CONFIG)
	if survival_panel._session == null:
		survival_panel.configure(session,actor,CONFIG,CONTENT)
		survival_panel.close_requested.connect(_close_menus)
		survival_panel.action_started.connect(_close_menus)
	else: survival_panel._actor = actor
	return true

func _save_token(secret: String) -> bool:
	_credential_data["credentials_version"] = 1
	_credential_data["tokens"][_credential_key] = secret
	var result: WildOperationResult = _credentials.save_record(_credential_data,_credentials_recovered)
	if result.successful: _credentials_recovered = false
	return result.successful

func _host(resume: bool) -> void:
	if network._active or not _select_identity("host"): return
	var service := WildCoopService.new(CONFIG,CATALOG,CONTENT,_store.save_record)
	var result: WildOperationResult
	var recovered: bool = false
	if resume:
		var loaded: WildOperationResult = _store.load_records()
		if WildSaveVersions.future(loaded.payload["primary"]):
			_set_status("房间包含未来技能 / 生存子版本，未用旧备份覆盖。")
			return
		result = service.restore(loaded.payload["primary"],network.actor_id)
		if not result.successful and loaded.payload["primary"].get("coop_save_version",1) == 1 and loaded.payload["primary"].get("host_id",network.actor_id) == network.actor_id:
			result = service.restore(loaded.payload["backup"],network.actor_id)
			recovered = result.successful
		if result.successful and network.token.sha256_text() != service.state.token_hashes[network.actor_id]: result = WildOperationResult.reject(&"IDENTITY_DENIED")
	else:
		var seed_text: String = _seed.text if not _seed.text.is_empty() else WildWorldGenerator.random_seed()
		if not WildWorldGenerator.valid_seed(seed_text):
			_set_status(WildErrorMessages.describe(&"INVALID_SEED"))
			return
		var previous_token: String = network.token
		var secret: String = WildStableId.create("host-secret") + WildStableId.create("secret")
		if not _save_token(secret):
			_set_status("重连凭据保存失败，未创建房间。")
			return
		network.token = secret
		result = service.create(network.actor_id,network.nickname,seed_text,secret)
		if not result.successful:
			_save_token(previous_token)
			network.token = previous_token
	if not result.successful:
		_set_status(WildErrorMessages.describe(result.code))
		return
	if recovered:
		var repaired: WildOperationResult = _store.save_record(service.state.record(),true)
		if not repaired.successful:
			_set_status(WildErrorMessages.describe(repaired.code))
			return
	var error: Error = network.host(service,int(_port.value))
	if error != OK: _set_status("无法绑定 UDP 端口：%s" % error_string(error))

func _join() -> void:
	if network._active or not _select_identity("guest"): return
	var error: Error = network.join(_address.text.strip_edges(),int(_port.value))
	if error != OK: _set_status("无法连接：%s" % error_string(error))

func _on_snapshot(data: Dictionary) -> void:
	_lobby.visible = false
	if _loaded_run != data["run_id"] and not data.get("world",{}).is_empty():
		if not world_view.enter(data["world"]):
			_set_status("地图快照校验失败。")
			return
		_loaded_run = data["run_id"]
	world_view.refresh_dynamic(session.world_dynamic(network.actor_id))
	_refresh_inventory()
	_start.disabled = network.authority == null or data["started"] or data["players"].size() != 2

func _process(delta: float) -> void:
	if network == null or network.latest.is_empty(): return
	session.interpolate(delta)
	var data: Dictionary = network.latest
	var body: Dictionary = data["players"][network.actor_id]["body"]
	var roster: PackedStringArray = []
	for player: Dictionary in data["players"].values():
		var display_name: String = str(player["name"])
		if display_name.length() > 12: display_name = display_name.left(12)+"…"
		roster.append("%s · %s · 血量 %.0f" % [display_name,"在线" if player["online"] else "离线留存",player["body"]["health_points"]])
	var outcome_text: String = {"running":"生存中","won":"已完成","lost":"已结束"}.get(data["outcome"],"已结束")
	_hud.text = "双人合作 · %s · 累计 %.2f 小时 · %s\n血量 %.0f  水分 %.0f  体力 %.0f  行装 %.1f kg · 个人菜单不暂停\n%s" % ["进行中" if data["started"] else "等待出发",(data["elapsed_seconds"]+data["pending_seconds"])/3600,outcome_text,body["health_points"],body["hydration"],body["stamina"],data["carried_weight_kg"]," / ".join(roster)]
	_hud.tooltip_text = "WASD / Shift 移动 · E 互动 · Esc 关闭菜单\n"+" / ".join(data["players"].values().map(func(player: Dictionary) -> String: return str(player["name"])))
	world_view.show_time(data["elapsed_seconds"])
	if data["save_blocked"]: _set_status("房主保存失败，模拟冻结，正在重试。")
	if data["outcome"] != "running": _set_status("验证任务已结束，房间已保存；合作奖励 / 尸体 / 观战将在 P6.5 接入。")

func _start_run() -> void:
	network.request("room.start",{})

func _cancel_action() -> void:
	network.request("survival.cancel",{})

func _set_status(value: String) -> void:
	if _status != null: _status.text = value

func _on_result(_request: String, result: WildOperationResult) -> void:
	_set_status("房主已确认操作。" if result.successful else WildErrorMessages.describe(result.code))

func _open_actions(target: Dictionary = {}) -> void:
	if network.latest.is_empty(): return
	field_guide.visible = false
	skill_panel.visible = false
	body_details.visible = false
	if target.get("kind","") == "storage_box":
		if not _inventory.visible: _open_inventory()
		return
	_inventory.visible = false
	session.submit(WildGameCommand.new(network.actor_id,&"base.open_pause"))
	survival_panel.open(target)

func _close_menus() -> void:
	field_guide.visible = false
	skill_panel.visible = false
	body_details.visible = false
	_inventory.visible = false
	survival_panel.visible = false
	session.submit(WildGameCommand.new(network.actor_id,&"base.close_station"))

func _open_inventory() -> void:
	if network.latest.is_empty(): return
	field_guide.visible = false
	skill_panel.visible = false
	body_details.visible = false
	if _inventory.visible:
		_close_menus()
		return
	survival_panel.visible = false
	session.submit(WildGameCommand.new(network.actor_id,&"base.open_pause"))
	_inventory.visible = true
	_refresh_inventory()
	_layout_ui.call_deferred()

func _refresh_inventory() -> void:
	if not _inventory.visible: return
	var containers: Dictionary = network.latest["containers"]
	var signature: String = "|".join(containers.keys())
	if signature != _grid_signature:
		for child: Node in _inventory_columns.get_children():
			_inventory_columns.remove_child(child)
			child.queue_free()
		_grids.clear()
		_grid_signature = signature
		for id: String in containers:
			var column := VBoxContainer.new()
			var card := PanelContainer.new()
			card.theme_type_variation = &"CardPanel"
			_inventory_columns.add_child(card)
			card.add_child(column)
			# 物品格宽度决定栏目宽度；短标题不换行，避免单格装备的标题被压成竖排。
			var title: Label = _label(column,{"backpack":"私人背包","main_hand":"主手","off_hand":"副手","armor":"护甲"}.get(id,"队友尸体" if id.begins_with("corpse:") else "公共营地箱"))
			title.autowrap_mode = TextServer.AUTOWRAP_OFF
			var grid := WildInventoryGrid.new()
			grid.configure(containers[id],CATALOG,_preview,32)
			grid.transfer_requested.connect(_transfer)
			grid.item_selected.connect(_select_item)
			column.add_child(grid)
			_grids[id] = grid
	for id: String in _grids: _grids[id].configure(containers[id],CATALOG,_preview,32)

func _preview(payload: Dictionary) -> WildOperationResult:
	return session.preview_transfer(network.actor_id,payload)

func _transfer(payload: Dictionary) -> void:
	_set_status("等待房主校验库存…")
	network.request("inventory.transfer",payload)

func _select_item(container: String, id: String) -> void:
	_selected_container = container
	_selected_item = id
	var entry: Dictionary = _grids[container].entry_for(id)
	_selection.text = "%s × %d（%s）" % [CATALOG.find(StringName(entry["item"]["item_id"])).display_name,entry["item"]["quantity"],"公开" if container.begins_with("camp_box:") else "私人"]

func _use_selected(kind: String) -> void:
	network.request("survival.start",{"action":kind,"item_id":_selected_item,"litres":0.5})

func _demolish_empty_box() -> void:
	for id: String in network.latest.get("containers",{}):
		if id.begins_with("camp_box:") and network.latest["containers"][id]["entries"].is_empty():
			network.request("survival.start",{"action":"demolish","building_id":id.trim_prefix("camp_box:")})
			return
	_set_status("附近没有空的公共箱，先把物资取入行装。")

func _split_selected() -> void:
	if not _grids.has(_selected_container): return
	var entry: Dictionary = _grids[_selected_container].entry_for(_selected_item)
	if entry.is_empty() or entry["item"]["quantity"] < 2: return
	_grids[_selected_container].begin_partial_drag(_selected_item,floori(float(entry["item"]["quantity"])/2))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"field_guide"):
		if field_guide.visible: _close_menus()
		else: _open_guide()
	elif event.is_action_pressed(&"attack") and session != null and session.active_station().is_empty() and world_view.visible: world_view.request_attack()
	elif event.is_action_pressed(&"inventory"): _open_inventory()
	elif event.is_action_pressed(&"pause"): _close_menus()
	elif event.is_action_pressed(&"interact") and session.active_station().is_empty(): world_view.request_interaction()
	elif event.is_action_pressed(&"craft") or event.is_action_pressed(&"build"): _open_actions()
	elif event.is_action_pressed(&"body_details"):
		if body_details.visible: _close_menus()
		else: _open_body_details()
	elif event.is_action_pressed(&"skills"):
		if skill_panel.visible: _close_menus()
		else: _open_skills()

func _open_body_details() -> void:
	if network.latest.is_empty(): return
	field_guide.visible = false
	skill_panel.visible = false
	_inventory.visible = false
	survival_panel.visible = false
	session.submit(WildGameCommand.new(network.actor_id,&"base.open_pause"))
	body_details.open(network.actor_id)

func _open_skills() -> void:
	if network.latest.is_empty(): return
	field_guide.visible = false
	_inventory.visible = false
	survival_panel.visible = false
	body_details.visible = false
	session.submit(WildGameCommand.new(network.actor_id,&"base.open_pause"))
	skill_panel.open(network.actor_id)

func _guide_snapshot() -> Dictionary:
	return network.latest

func _open_guide() -> void:
	_close_menus()
	session.submit(WildGameCommand.new(network.actor_id,&"base.open_pause"))
	field_guide.open(_guide_snapshot(),CONFIG,CATALOG,CONTENT,true)
	field_guide.move_to_front()

func _on_ended() -> void:
	if _handling_end: return
	_handling_end = true
	survival_panel.reset_pending()
	skill_panel.reset_pending()
	_close_menus()
	if network.authority == null:
		network.close_connection()
		world_view.leave()
		session.reset_view()
		_loaded_run = ""
		_lobby.visible = true
		_start.disabled = true
	_handling_end = false

func _leave() -> void:
	if network.authority != null:
		var result: WildOperationResult = network.end_host()
		if not result.successful:
			_set_status("结束前保存失败，请重试。")
			return
		await get_tree().create_timer(0.3).timeout
	network.close_connection()
	world_view.leave()
	session.reset_view()
	survival_panel.reset_pending()
	skill_panel.reset_pending()
	_loaded_run = ""
	_lobby.visible = true
	_start.disabled = true
	_set_status("已断开。原队员可重新连接；房主可恢复存档。")

func _back_to_base() -> void:
	if network._active:
		await _leave()
		if network._active: return
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not _exiting:
		_exiting = true
		if network != null and network._active:
			await _leave()
			if network._active:
				_exiting = false
				return
		get_tree().quit()




