extends Node
## 随候选包提供的专用 QA 入口；常规 tests/ 不导出，诊断写入限定 EXE 旁随机目录。
## 发布模板禁用外部脚本覆盖，因此由 candidate_qa 特征与显式参数启用，先于正式身份初始化。
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")
var case_root: String = ""
var role: String = "smoke"
var port: int = 0
var passed: int = 0
var failed: int = 0
var ui: WildFullCoopMain

func _ready() -> void:
	Engine.max_fps = 60
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case-root="): case_root = argument.trim_prefix("--case-root=").replace("\\","/")
		if argument.begins_with("--role="): role = argument.trim_prefix("--role=")
		if argument.begins_with("--port="): port = argument.trim_prefix("--port=").to_int()
	var workspace: String = OS.get_executable_path().get_base_dir()
	if not case_root.begins_with(workspace+"/qa/p8-export-") or case_root.contains("..") or role not in ["smoke","host","client"]: get_tree().quit(1); return
	DirAccess.make_dir_recursive_absolute(case_root)
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1; push_error(label)

func _wait(predicate: Callable, seconds: float = 90) -> bool:
	var deadline: int = Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline: await get_tree().create_timer(0.05).timeout
	return bool(predicate.call())

func _run() -> void:
	check(not OS.has_feature("editor"),"actual export template, no editor")
	check(WildNetworkCompatibility.fingerprint().length()==64,"export content manifest available after script conversion")
	check(not ResourceLoader.exists("res://tests/p65_network.tscn"),"test scenes excluded from shipped pack")
	if role == "smoke": await _smoke()
	else: await _network()
	FileAccess.open(case_root+"/"+role+"-result.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"failed":failed,"role":role,"engine":Engine.get_version_info()["string"]},"\t"))
	print("P8 exported "+role+" checks: %d passed, %d failed" % [passed,failed])
	get_tree().quit(0 if failed==0 else 1)

func _smoke() -> void:
	var main: WildMain = load("res://scenes/main.tscn").instantiate() as WildMain
	main._profile_path = case_root+"/smoke.cfg"
	get_tree().root.add_child(main)
	await get_tree().process_frame
	check(main.session != null and main._base_store._path.begins_with(case_root),"export main opens isolated profile")
	main._open_guide()
	check(main.field_guide.visible and get_tree().paused,"export handbook and pause")
	main._close_station()
	check(main.session.submit(WildGameCommand.new(main.local_player_id,&"expedition.prepare",{"seed":"17"})).successful,"export prepares")
	check(main.session.submit(WildGameCommand.new(main.local_player_id,&"expedition.commit")).successful,"export random world loads assets")
	main.session._base_services[main.local_player_id]._state.survival.elapsed_seconds=CONFIG.target_survival_hours*3600-60
	check(main.session.advance_world(main.local_player_id,0.5,"idle").successful,"export deadline fixture commits")
	check(main.session.base_snapshot(main.local_player_id)["last_settlement"]["won"],"export result / reward survives")
	main._close_station()
	check(main.session.checkpoint(main.local_player_id).successful,"export durable checkpoint")
	main.queue_free()
	await get_tree().process_frame
	ui = load("res://scenes/coop_full.tscn").instantiate() as WildFullCoopMain
	ui._profile_override = case_root+"/smoke.cfg"
	ui._room_root=case_root+"/rooms"
	get_tree().root.add_child(ui)
	await get_tree().process_frame
	check(ui.profile != null and ui._rooms != null,"export complete cooperation scene / personal profile")
	ui._open_guide()
	check(ui.field_guide.visible and not get_tree().paused,"export cooperative guide does not pause")
	ui._close_menus()
	ui.queue_free()
	await get_tree().process_frame

func _network() -> void:
	ui=load("res://scenes/coop_full.tscn").instantiate() as WildFullCoopMain
	ui._profile_override=case_root+"/"+role+".cfg"
	ui._room_root=case_root+"/rooms"
	get_tree().root.add_child(ui)
	await get_tree().process_frame
	ui.network.bind_address="127.0.0.1"
	ui.network.fault_delay_ms=75
	ui.network.fault_drop_every=20
	ui._port.value=port
	if role=="host":
		ui._host(false)
		FileAccess.open(case_root+"/ready.txt",FileAccess.WRITE).store_string("ready")
	else:
		ui._address.text="127.0.0.1"
		ui._join()
	check(await _wait(func() -> bool: return ui.network.latest.get("players",{}).size()==2),"exported two-player actual ENet / manifest handshake")
	if ui.network.latest.get("players",{}).size()!=2: return
	check(ui.profile_link.reserve_and_offer().successful,"export actual personal lease")
	check(await _wait(func() -> bool: return ui.network.latest.get("cooperation",{}).get("ready",{}).size()==2),"export offers accepted")
	ui._toggle_ready()
	if role=="host":
		check(await _wait(func() -> bool: return ui.network.authority.state.lifecycle["ready"].values().count(true)==2),"export all ready")
		ui.network.request("room.start",{})
	check(await _wait(func() -> bool: return ui.network.latest.get("cooperation",{}).get("phase","")=="running"),"export all loaded, clock runs")
	ui._open_guide()
	check(not get_tree().paused,"export co-op menu policy")
	ui._close_menus()
	if role=="client":
		var actor: String=ui.network.actor_id
		ui.network.close_connection()
		await get_tree().create_timer(1).timeout
		ui._join()
		check(await _wait(func() -> bool: return not ui.network.latest.is_empty()),"export original identity reconnect")
		check(ui.network.actor_id==actor,"export reconnect preserves actor")
		FileAccess.open(case_root+"/reconnected.txt",FileAccess.WRITE).store_string("ready")
	else:
		check(await _wait(func() -> bool: return FileAccess.file_exists(case_root+"/reconnected.txt")),"export client reconnect completed")
		var room: WildCoopState=ui.network.authority.state
		room.survival.elapsed_seconds=CONFIG.target_survival_hours*3600-60
		for id: String in room.survival.fish_refills: room.survival.fish_refills[id]=CONFIG.target_survival_hours*3600+43200
		room.survival.next_animal_refill=CONFIG.target_survival_hours*3600+86400
		ui.network.authority.checkpoint()
	check(await _wait(func() -> bool: return not WildCoopProfileRules.blocked(ui.profile._state) and not ui.profile.snapshot()["last_settlement"].is_empty()),"export per-player terminal written and lease closed")
	check(ui.profile.snapshot()["last_settlement"].get("won",false) and ui.profile.snapshot()["currency"]>=1200,"export individual reward")
	FileAccess.open(case_root+"/"+role+"-settled.txt",FileAccess.WRITE).store_string("ready")
	if role=="host":
		check(await _wait(func() -> bool: return FileAccess.file_exists(case_root+"/client-settled.txt")),"export both profiles committed")
		await ui._leave()
	else: await _wait(func() -> bool: return not ui.network._active)
	ui.queue_free()
	await get_tree().process_frame
