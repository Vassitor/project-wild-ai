extends SceneTree
## 真实合作组合根 / 控件 / 异步回执 / 恢复流程；仅使用随机工作区身份。
const UI: PackedScene = preload("res://scenes/coop.tscn")
const VERIFICATION = preload("res://tests/verification_paths.gd")
var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	if not VERIFICATION.arguments_are_isolated():
		push_error("Tests require workspace verification paths")
		quit(1)
		return
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		push_error(label)

func frames() -> void:
	for index: int in range(4): await process_frame

func _run() -> void:
	var ui: WildCoopMain = UI.instantiate() as WildCoopMain
	ui._profile_override = "res://.godot/verification/p35-ui-"+WildStableId.create("test")+".cfg"
	ui._room_path = ui._profile_override.get_basename()+"-room.json"
	root.add_child(ui)
	ui.network.bind_address = "127.0.0.1"
	ui._port.value = 41000+randi()%10000
	ui._seed.text = "invalid"
	ui._host(false)
	check(ui.network.authority == null and not FileAccess.file_exists(ui._room_path),"invalid seed cannot replace room / credentials")
	ui._seed.text = "17"
	ui._host(false)
	check(ui.network.authority != null,"actual cooperation root creates host")
	if ui.network.authority == null:
		quit(1)
		return
	var service: WildCoopService = ui.network.authority
	var actor: String = ui.network.actor_id
	check(service.join("ui-fixture-guest","队友","").successful,"display fixture member admitted before departure")
	ui._start_run()
	await frames()
	check(service.state.started,"start button uses asynchronous authority command")
	ui._open_inventory()
	check(ui._inventory.visible and not ui.session.is_paused() and not paused,"inventory never pauses cooperative tree")
	var knife: String = WildInventoryOperations.choose(service.state.members[actor],&"knife")
	ui._select_item("backpack",knife)
	check(not ui._selection.text.is_empty(),"actual grid selection shows item")
	var payload: Dictionary = {"source":"backpack","target":"main_hand","item_id":knife,"auto":true,"source_version":ui.network.latest["containers"]["backpack"]["version"],"target_version":ui.network.latest["containers"]["main_hand"]["version"]}
	check(ui.session.preview_transfer(actor,payload).successful,"read-only replica preview uses injected inventory rules")
	ui._transfer(payload)
	await frames()
	check(service.state.members[actor].containers["main_hand"].placements.has(knife),"grid transfer intent reaches persisted authority")
	ui._transfer(payload)
	await frames()
	check(ui._status.text.contains("库存已经更新"),"stale asynchronous result shown in UI")
	var ration: String = WildInventoryOperations.choose(service.state.members[actor],&"ration")
	ui._select_item("backpack",ration)
	ui._use_selected("eat")
	await frames()
	check(service.state.survival.actions.get(actor,{}).get("type","") == "eat","eat button executes actor-owned action")
	WildSurvivalSimulation.queue_time(service.state.survival,60,"idle")
	service._simulate(service.state,true)
	service.checkpoint()
	ui.network._broadcast(true)
	check((WildInventoryOperations.find(service.state.members[actor],ration)["item"] as WildItemInstance).quantity == 2,"UI food consumed once")
	ui._close_menus()
	ui._open_actions()
	var box_button: Button
	for child: Node in ui.survival_panel.find_children("*","Button",true,false):
		if child.text.begins_with("建公共储物箱"): box_button = child
	check(box_button != null,"cooperative menu exposes confirmed box recipe")
	if box_button != null:
		box_button.pressed.emit()
		check(not ui.survival_panel._pending_request.is_empty(),"UI shows pending instead of fake success")
		await frames()
		check(not ui.survival_panel.visible and service.state.survival.actions.has(actor),"host result closes action menu after confirmation")
		WildSurvivalSimulation.queue_time(service.state.survival,1800,"idle")
		service._simulate(service.state,true)
		service.checkpoint()
		ui.network._broadcast(true)
		ui._open_inventory()
		check(service.state.boxes.size() == 1 and ui._grids.size() == 5,"public box appears beside four private containers")
	# 显示层模拟收到服务器断开事件；真实断开 / 重连另外由双进程测试验证。
	ui.survival_panel._pending_request = "old-room-request"
	ui.network.authority = null
	ui._on_ended()
	check(ui._lobby.visible and not ui.world_view.visible and not ui.network._active,"disconnect returns to reconnect controls")
	check(ui.survival_panel._pending_request.is_empty(),"disconnect clears stale UI pending lock")
	var backup_before: Dictionary = ui._store.load_records().payload["backup"]
	var corrupted := FileAccess.open(ui._room_path,FileAccess.WRITE)
	corrupted.store_string("invalid json")
	corrupted.close()
	ui._host(true)
	check(ui.network.authority != null,"root recovers original host room from backup")
	check(JSON.stringify(ui._store.load_records().payload["backup"],"",true) == JSON.stringify(backup_before,"",true),"backup recovery preserves valid backup before replacing bad primary")
	await ui._leave()
	check(not ui.network._active and ui._lobby.visible,"normal host leave saved and closed")
	var future_credentials: Dictionary = ui._credentials.load_records().payload["primary"]
	future_credentials["credentials_version"] = 99
	ui._credentials.save_record(future_credentials,true)
	ui._host(true)
	check(not ui.network._active and ui._status.text.contains("版本不兼容"),"unknown credential version refused without backup downgrade")
	check(ui._credentials.load_records().payload["primary"]["credentials_version"] == 99,"unknown credential file remains unchanged")
	ui.queue_free()
	await process_frame
	service = null
	print("P3.5 UI checks: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)
