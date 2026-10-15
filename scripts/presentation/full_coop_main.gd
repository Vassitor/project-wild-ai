class_name WildFullCoopMain
extends WildCoopMain
## 完整合作组合根：个人档案 / 房主世界分别持久化，所有业务仍经服务提交。
var profile_store: WildDurableStateStore
var profile: WildBaseService
var profile_link: WildCoopProfileLink
var preparation_session: WildLocalSession
var preparation_panel: WildBasePanel
var preparation_skills: WildSkillPanel
var _rooms: OptionButton
var _room_root: String = "user://coop_rooms"
var _ready_button: Button
var _sleep_hours: OptionButton
var _gift_target: OptionButton
var _materials: OptionButton
var _choice_signature: String = ""
var _loaded_key: String = ""
var _preparation_controls: HFlowContainer
var _wild_controls: HFlowContainer
var _personal_base_override: String = ""
var _layout_queued: bool = false
var _shown_result_id: String = ""

func full_mode() -> bool:
	return true

func _ready() -> void:
	var handoff: Dictionary = get_tree().get_meta("profile_scene_handoff",{})
	get_tree().remove_meta("profile_scene_handoff")
	if handoff.has("profile"): _profile_override = handoff["profile"]
	_personal_base_override = str(handoff.get("base",""))
	if _profile_override.is_empty(): _profile_override = "user://profile_identity.cfg"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--profile="): _profile_override = argument.trim_prefix("--profile=")
		if argument.begins_with("--profile-store="): _profile_override = argument.trim_prefix("--profile-store=")
		if argument.begins_with("--base-store="): _personal_base_override = argument.trim_prefix("--base-store=")
	super._ready()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--coop-room="): _room_root = argument.trim_prefix("--coop-room=").get_basename()+"_rooms"
	network.full_cooperation = true
	network.content_fingerprint = WildNetworkCompatibility.fingerprint()
	network.credentials_lookup = func(room_id: String) -> String: return str(_credential_data.get("tokens",{}).get("room:"+room_id,""))
	_select_identity("host")
	_refresh_rooms()

func _create_ui() -> void:
	super._create_ui()
	var column: VBoxContainer = _bottom_panel.get_child(0) as VBoxContainer
	var row := HFlowContainer.new()
	row.add_theme_constant_override("separation",8)
	column.add_child(row)
	_preparation_controls = row
	_button(row,"基地补给 / 行装",_open_preparation.bind(&"supply"))
	_button(row,"基地学习",_open_preparation_skills)
	_button(row,"提交个人行装",_offer_loadout)
	_button(row,"撤回行装",func() -> void: network.request("profile.withdraw",{}))
	_ready_button = _button(row,"准备 / 取消准备",_toggle_ready)
	row = HFlowContainer.new()
	row.add_theme_constant_override("separation",8)
	column.add_child(row)
	_wild_controls = row
	_wild_controls.visible = false
	_button(row,"切换观战",_spectate_next)
	_sleep_hours = OptionButton.new()
	for hours: int in [1,2,4,8]: _sleep_hours.add_item("睡眠 %d 小时" % hours,hours)
	row.add_child(_sleep_hours)
	_button(row,"提议 / 同意睡眠",_sleep_vote)
	_button(row,"拒绝睡眠",func() -> void: network.request("sleep.vote",{"agree":false}))
	_gift_target = OptionButton.new()
	_gift_target.add_item("选择接收队友")
	row.add_child(_gift_target)
	_button(row,"赠送选中实例",_offer_gift)
	_button(row,"接受赠送",_accept_gift)
	_button(row,"取消赠送",_cancel_gift)
	_materials = OptionButton.new()
	_materials.add_item("仅私人材料")
	_materials.item_selected.connect(func(index: int) -> void: session.materials_box = str(_materials.get_item_metadata(index)))
	row.add_child(_materials)
	var lobby_column: VBoxContainer = (_lobby.get_child(0) as ScrollContainer).get_child(0) as VBoxContainer
	_rooms = OptionButton.new()
	_rooms.custom_minimum_size.y = 36
	lobby_column.add_child(_rooms)
	_button(lobby_column,"双人独立验证入口",func() -> void:
		if not network._active:
			_remember_profile()
			get_tree().change_scene_to_file("res://scenes/coop.tscn"))
	preparation_panel = WildBasePanel.new()
	preparation_panel.cooperation_preparation = true
	preparation_panel.visible = false
	add_child(preparation_panel)
	preparation_skills = WildSkillPanel.new()
	preparation_skills.visible = false
	add_child(preparation_skills)
	WildUiLayout.modal_backdrop(self,[preparation_panel,preparation_skills])
	# 流式按钮在容器排序后才得到换行高度；自动重排不能依赖测试或用户再次缩放。
	column.minimum_size_changed.connect(_schedule_layout)

func _schedule_layout() -> void:
	if _layout_queued: return
	_layout_queued = true
	_finish_layout.call_deferred()

func _finish_layout() -> void:
	_layout_queued = false
	_layout_ui()

func _layout_ui() -> void:
	super._layout_ui()
	if _bottom_panel != null:
		var height: float = maxf(204,_bottom_panel.get_child(0).get_combined_minimum_size().y+32)
		_bottom_panel.position.y = size.y-height-16
		_bottom_panel.size.y = height
	if _lobby != null: _lobby.size.y = maxf(140,_bottom_panel.position.y-126)
	if preparation_panel != null: WildUiLayout.center(preparation_panel,size,Vector2(1200,620))
	if preparation_skills != null: WildUiLayout.center(preparation_skills,size,Vector2(1120,600))
	if field_guide != null: field_guide.move_to_front()

func _select_identity(role: String) -> bool:
	if not super._select_identity(role): return false
	if profile != null: return true
	var path: String = "user://base_state.json" if _identity_path == "user://profile_identity.cfg" else _identity_path.get_basename()+"_base.json"
	if not _personal_base_override.is_empty(): path = _personal_base_override
	profile_store = WildDurableStateStore.new(path)
	profile = WildBaseService.new(CONFIG,CATALOG,profile_store.load_records,profile_store.save_record,Callable(),Callable(),CONTENT)
	var result: WildOperationResult = profile.initialize(network.actor_id)
	if not result.successful:
		_set_status("个人档案无法打开："+str(result.code))
		profile = null
		return false
	preparation_session = WildLocalSession.new()
	preparation_session.register_player(WildPlayerState.new(network.actor_id,network.nickname,CONFIG))
	preparation_session.register_base_service(network.actor_id,profile)
	preparation_panel.configure(preparation_session,network.actor_id,CATALOG,CONFIG)
	preparation_panel.close_requested.connect(func() -> void: preparation_panel.visible = false)
	preparation_skills.configure(preparation_session,CONFIG)
	preparation_skills.close_requested.connect(func() -> void: preparation_skills.visible = false)
	profile_link = WildCoopProfileLink.new()
	profile_link.configure(network,profile,network.actor_id)
	return true

func _save_token(secret: String) -> bool:
	# guest 凭据以房间 ID 留存，端口 / 房主恢复顺序改变后可经握手挑战选择原凭据。
	if _credential_key != "host" and not network.welcoming_room_id.is_empty(): _credential_data["tokens"]["room:"+network.welcoming_room_id] = secret
	return super._save_token(secret)

func _refresh_rooms() -> void:
	if _rooms == null or network.actor_id.is_empty(): return
	_rooms.clear()
	var files: PackedStringArray = DirAccess.get_files_at(_room_root) if DirAccess.dir_exists_absolute(_room_root) else PackedStringArray()
	files.sort()
	for file: String in files:
		if file.begins_with(network.actor_id+"_") and file.ends_with(".json"):
			_rooms.add_item(file.trim_prefix(network.actor_id+"_").trim_suffix(".json"))
			_rooms.set_item_metadata(_rooms.item_count-1,_room_root+"/"+file)
	if _rooms.item_count == 0: _rooms.add_item("暂无完整合作存档")
	else: _rooms.select(_rooms.item_count-1)

func _host(resume: bool) -> void:
	if network._active or not _select_identity("host"): return
	if profile.current_phase() != WildRunFlow.Phase.BASE:
		_set_status("先完成或取消当前单机任务，再进入合作。")
		return
	if resume:
		var selected: Variant = _rooms.get_item_metadata(_rooms.selected)
		if not selected is String:
			_set_status("请选择已保存的合作房间。")
			return
		_room_path = selected
	else:
		if WildCoopProfileRules.blocked(profile._state):
			_set_status("个人行装仍在原合作任务中，请恢复对应房间同步。")
			return
		_room_path = _room_root+"/"+network.actor_id+"_"+Time.get_datetime_string_from_system().replace(":","-")+"_"+WildStableId.create("room")+".json"
	_store = WildDurableStateStore.new(_room_path)
	var service := WildFullCoopService.new(CONFIG,CATALOG,CONTENT,_store.save_record)
	var result: WildOperationResult
	if resume:
		var loaded: WildOperationResult = _store.load_records()
		if not loaded.successful:
			_set_status("完整房间日志不可恢复："+str(loaded.code))
			return
		result = service.restore(loaded.payload["primary"],network.actor_id)
		if result.successful and network.token.sha256_text() != service.state.token_hashes[network.actor_id]: result = WildOperationResult.reject(&"IDENTITY_DENIED")
	else:
		if network.token.is_empty():
			network.token = WildStableId.create("host-secret")+WildStableId.create("secret")
			if not _save_token(network.token):
				_set_status("房主凭据保存失败。")
				return
		var seed_text: String = _seed.text if not _seed.text.is_empty() else WildWorldGenerator.random_seed()
		result = service.create(network.actor_id,network.nickname,seed_text,network.token)
	if not result.successful:
		_set_status("房间未打开："+str(result.code))
		return
	var error: Error = network.host(service,int(_port.value))
	if error != OK: _set_status("无法绑定 UDP 端口："+error_string(error))
	_refresh_rooms()

func _join() -> void:
	if network._active or not _select_identity("guest"): return
	if profile.current_phase() != WildRunFlow.Phase.BASE:
		_set_status("先结束当前单机任务，再加入合作。")
		return
	var error: Error = network.join(_address.text.strip_edges(),int(_port.value))
	if error != OK: _set_status("无法连接："+error_string(error))

func _open_preparation(station: StringName) -> void:
	if profile == null: return
	if WildCoopProfileRules.blocked(profile._state):
		_set_status("行装已托管；大厅中先撤回，或等待原任务结算。")
		return
	preparation_skills.visible = false
	field_guide.visible = false
	preparation_panel.open(station)
	_layout_ui()

func _open_preparation_skills() -> void:
	if profile == null or WildCoopProfileRules.blocked(profile._state):
		_set_status("出发前可在基地学习；托管后请先撤回行装。")
		return
	preparation_panel.visible = false
	field_guide.visible = false
	preparation_skills.open(network.actor_id)
	_layout_ui()

func _offer_loadout() -> void:
	if profile_link == null: return
	var result: WildOperationResult = profile_link.reserve_and_offer()
	_set_status("个人行装已锁定，等待房主确认。" if result.successful else "行装未提交："+str(result.code))

func _toggle_ready() -> void:
	if network.latest.is_empty(): return
	var prepared: bool = network.latest.get("cooperation",{}).get("ready",{}).get(network.actor_id,false)
	network.request("room.ready",{"ready":not prepared})

func _on_snapshot(data: Dictionary) -> void:
	_lobby.visible = false
	var coop: Dictionary = data.get("cooperation",{})
	var phase: String = coop.get("phase","")
	_preparation_controls.visible = phase in ["lobby","cancelled","settled"]
	_wild_controls.visible = phase == "running"
	if phase in ["loading","running","settled"]:
		var key: String = str(data["run_id"])+str(coop.get("world_hash",""))
		if key != _loaded_key and not data.get("world",{}).is_empty():
			if phase == "loading" and WildCanonicalData.digest(data["world"]) != coop["world_hash"]:
				_set_status("世界摘要校验失败，尚未确认加载。")
				return
			if not world_view.enter(data["world"]):
				_set_status("世界快照校验失败。")
				return
			_loaded_key = key
			_loaded_run = data["run_id"]
		if phase == "loading" and _loaded_key == key and not coop.get("loaded",{}).get(network.actor_id,false): network.request("room.loaded",{"world_hash":coop["world_hash"]},"loaded:"+str(data["run_id"]))
		world_view.refresh_dynamic(session.world_dynamic(network.actor_id))
	else: world_view.leave()
	_start.disabled = network.authority == null or phase != "lobby" or data["players"].size() < 2
	_ready_button.disabled = phase != "lobby" or not coop.get("has_loadout",false)
	_refresh_inventory()
	_refresh_choices(data)

func _refresh_choices(data: Dictionary) -> void:
	var choices: Array = data["players"].keys()+data["containers"].keys()
	var signature: String = "|".join(choices)
	if signature == _choice_signature: return
	_choice_signature = signature
	_gift_target.clear()
	for actor: String in data["players"]:
		if actor == network.actor_id: continue
		_gift_target.add_item(data["players"][actor]["name"])
		_gift_target.set_item_metadata(_gift_target.item_count-1,actor)
	_materials.clear()
	_materials.add_item("仅私人材料")
	_materials.set_item_metadata(0,"")
	for id: String in data["containers"]:
		if not id.begins_with("camp_box:"): continue
		_materials.add_item("使用附近公共箱材料")
		_materials.set_item_metadata(_materials.item_count-1,id)
	session.materials_box = ""

func _process(delta: float) -> void:
	if network == null or network.latest.is_empty(): return
	session.interpolate(delta)
	var data: Dictionary = network.latest
	var coop: Dictionary = data.get("cooperation",{})
	var body: Dictionary = data["players"][network.actor_id]["body"]
	var roster: PackedStringArray = []
	for actor: String in data["players"]:
		var player: Dictionary = data["players"][actor]
		roster.append("%s %s%s" % [str(player["name"]).left(10),"观战" if player["body"]["health_points"] <= 0 else ("在线" if player["online"] else "离线")," ✓" if coop.get("ready",{}).get(actor,false) else ""])
	_hud.text = "2–4 人合作 · %s · %s · %s\n血量 %.0f  水分 %.0f  体力 %.0f  行装 %.1f kg · 菜单不暂停\n%s" % [{"lobby":"准备大厅","loading":"等待全员加载","running":"荒野生存","settled":"逐人结算","cancelled":"已取消"}.get(coop.get("phase",""),"连接中"),WildExpeditionText.countdown(data["elapsed_seconds"]+data["pending_seconds"],CONFIG),"死亡后观战" if body["health_points"] <= 0 else "存活",body["health_points"],body["hydration"],body["stamina"],data["carried_weight_kg"]," / ".join(roster)]
	world_view.show_time(data["elapsed_seconds"])
	if data["save_blocked"]: _set_status("房主保存失败，模拟冻结，等待重试。")
	elif coop.get("phase","") == "settled":
		var settlement: Dictionary = profile.snapshot().get("last_settlement",{}) if profile != null else {}
		_set_status("任务结束；个人进度已同步，奖励 %d。返回基地查看物资。" % int(settlement.get("reward",0)) if profile != null and not WildCoopProfileRules.blocked(profile._state) else "任务结束，正在同步个人进度。")
		if settlement.get("run_id","") == data["run_id"] and _shown_result_id != data["run_id"] and not WildCoopProfileRules.blocked(profile._state):
			_shown_result_id = data["run_id"]
			_open_guide()
			field_guide._select(field_guide.pages.size()-1)
	elif not coop.get("vote",{}).is_empty():
		var vote: Dictionary = coop["vote"]
		_set_status("全体睡眠跳时中，遇险中断。" if vote.get("sleeping",false) else "睡眠提案 %d 小时，%d 人同意；请选择同意或拒绝。" % [vote["hours"],vote["agree"].size()])
	else:
		for gift: Dictionary in coop.get("gifts",{}).values():
			if gift["target"] == network.actor_id and gift.has("item"):
				_set_status("%s 赠送 %s × %d；点击「接受赠送」接收或「取消赠送」拒绝。" % [data["players"][gift["from"]]["name"],CATALOG.find(StringName(gift["item"]["item_id"])).display_name,gift["item"]["quantity"]])
				break

func _sleep_vote() -> void:
	var vote: Dictionary = network.latest.get("cooperation",{}).get("vote",{})
	network.request("sleep.vote",{"hours":int(vote.get("hours",_sleep_hours.get_selected_id()))})

func _offer_gift() -> void:
	if _gift_target.selected < 0 or _selected_item.is_empty():
		_set_status("先在行装面板选中实例，再选择接收队友。")
		return
	network.request("gift.offer",{"target":str(_gift_target.get_item_metadata(_gift_target.selected)),"item_id":_selected_item})

func _accept_gift() -> void:
	for gift: Dictionary in network.latest.get("cooperation",{}).get("gifts",{}).values():
		if gift["target"] == network.actor_id:
			network.request("gift.accept",{"gift_id":gift["id"]})
			return
	_set_status("没有待接收的赠送。")

func _cancel_gift() -> void:
	for gift: Dictionary in network.latest.get("cooperation",{}).get("gifts",{}).values(): network.request("gift.cancel",{"gift_id":gift["id"]})

func _spectate_next() -> void:
	world_view.spectate_next()

func _close_menus() -> void:
	super._close_menus()
	if preparation_panel != null: preparation_panel.visible = false
	if preparation_skills != null: preparation_skills.visible = false

func _guide_snapshot() -> Dictionary:
	var view: Dictionary = profile.snapshot() if profile != null else {}
	if not network.latest.is_empty():
		view = network.latest.duplicate(true)
		if profile != null: view["last_settlement"] = profile.snapshot().get("last_settlement",{})
	return view

func _open_actions(target: Dictionary = {}) -> void:
	if target.get("kind","") == "corpse":
		_open_inventory()
		return
	super._open_actions(target)

func _leave() -> void:
	await super._leave()
	_loaded_key = ""
	_choice_signature = ""
	_preparation_controls.visible = true
	_wild_controls.visible = false
	_refresh_rooms()

func _on_result(request: String, result: WildOperationResult) -> void:
	if result.code == &"GENERATION_FAILED":
		_set_status("投放准备失败，个人行装仍在大厅托管；可重试或撤回行装。")
		return
	super._on_result(request,result)

func _remember_profile() -> void:
	if profile_store != null: get_tree().set_meta("profile_scene_handoff",{"profile":_identity_path,"base":profile_store._path})

func _back_to_base() -> void:
	if network._active:
		await _leave()
		if network._active: return
	_remember_profile()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")
