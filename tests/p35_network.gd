extends Node
## 两个独立进程经真实 ENet 交换；布置位置仅在测试房主内部执行。
## 采用默认 120 倍游戏时钟，动作费用 / 材料 / 空间规则沿用默认。
var config: WildGameConfig
var network: WildENetRoom
var service: WildCoopService
var store: WildBaseStateStore
var replica: WildCoopReplicaSession
var role: String = ""
var port: int = 0
var case_root: String = ""
var fault: bool = false
var passed: int = 0
var failed: int = 0
var results: Dictionary = {}
var statuses: PackedStringArray = []
var _started_at: int = 0
var _finished: bool = false
var _ending_received: bool = false
var _command_times: Array[float] = []
var suite_label: String = "P3.5"
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")
const FIXTURES = preload("res://tests/p35_fixtures.gd")

func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--role="): role = argument.trim_prefix("--role=")
		if argument.begins_with("--port="): port = argument.trim_prefix("--port=").to_int()
		if argument.begins_with("--case-root="): case_root = argument.trim_prefix("--case-root=")
		if argument == "--fault=100": fault = true
	assert(case_root.begins_with("res://.godot/verification/") and role in ["host","client"] and port >= 1024,"isolated arguments required")
	config = (load("res://data/game_config.tres") as WildGameConfig).duplicate(true)
	config.game_seconds_per_real_second = 120
	_started_at = Time.get_ticks_msec()
	network = WildENetRoom.new()
	network.name = "Network"
	add_child(network)
	network.bind_address = "127.0.0.1"
	print("%s UDP port %d" % [role,port])
	network.multiplayer.peer_connected.connect(func(peer: int) -> void: print("%s peer connected %d" % [role,peer]))
	network.fault_delay_ms = 50 if fault else 0
	network.fault_drop_every = 100 if fault else 0
	network.command_completed.connect(_on_result)
	network.connection_status.connect(_on_status)
	network.room_ended.connect(_on_end)
	network.configure_identity("host" if role == "host" else "guest",role,"host-secret" if role == "host" else "")
	if role == "host": _run_host.call_deferred()
	else: _run_client.call_deferred()

func _process(_delta: float) -> void:
	if not _finished and Time.get_ticks_msec()-_started_at > 120000:
		check(false,"network scenario timed out")
		_finish()

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
		print("%s %d ms PASS %s" % [role,Time.get_ticks_msec()-_started_at,label])
	else:
		failed += 1
		push_error("%s FAIL %s" % [role,label])

func _wait(predicate: Callable, seconds: float = 10) -> bool:
	var deadline: int = Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05).timeout
	return bool(predicate.call())

func _on_result(request: String, result: WildOperationResult) -> void:
	results[request] = result
	print("%s request %s => %s" % [role,request,result.code])

func _on_status(value: String) -> void:
	statuses.append(value)
	print("%s status %s" % [role,value])

func _on_end() -> void:
	_ending_received = true

func _request(operation: String, data: Dictionary, id: String) -> WildOperationResult:
	results.erase(id)
	var start: int = Time.get_ticks_msec()
	network.request(operation,data,id)
	if not await _wait(func() -> bool: return results.has(id)):
		check(false,"request timed out "+id)
		return WildOperationResult.reject(&"TIMEOUT")
	_command_times.append(float(Time.get_ticks_msec()-start))
	return results[id]

func _marker(id: String) -> void:
	await _request("survival.cancel",{},id)

func _has_marker(id: String) -> bool:
	return service.state.receipts.has("guest:"+id)

func _stage(value: String) -> void:
	service.state.survival.notice = value
	service.checkpoint()
	network._broadcast(true)

func _notice(value: String) -> bool:
	return network.latest.get("notice","") == value

func _quantity(actor: String, definition: String) -> int:
	var total: int = 0
	for container: WildInventoryContainer in service.state.members[actor].containers.values():
		for entry: Dictionary in container.placements.values():
			var item: WildItemInstance = entry["item"]
			if str(item.item_id) == definition: total += item.quantity
	return total

func _resource(kind: String) -> Dictionary:
	for entry: Dictionary in service.state.world.resources.values():
		if entry["kind"] == kind and entry["remaining"] > 0: return entry
	return {}

func _fixture_at(point: Vector2) -> void:
	for actor: String in service.state.members: service.state.world.players[actor] = point
	service.checkpoint()
	network._broadcast(true)

func _run_host() -> void:
	store = WildBaseStateStore.new(case_root+"/room.json")
	service = WildCoopService.new(config,CATALOG,CONTENT,store.save_record)
	check(service.create("host","房主","17","host-secret").successful,"isolated host world")
	check(network.host(service,port) == OK,"ENet UDP server")
	var ready := FileAccess.open(case_root+"/ready.txt",FileAccess.WRITE)
	ready.store_string("ready")
	ready.close()
	check(await _wait(func() -> bool: return service.state.members.size() == 2),"real client handshake")
	if service.state.members.size() != 2:
		_finish()
		return
	check((await _request("room.start",{},"start")).successful,"network host start")
	_stage("move")
	var initial: Vector2 = service.state.world.players["guest"]
	var move_started: int = Time.get_ticks_msec()
	check(await _wait(func() -> bool: return _has_marker("move-done")),"client movement completed")
	var moved: float = initial.distance_to(service.state.world.players["guest"])
	var move_seconds: float = float(Time.get_ticks_msec()-move_started)/1000
	print("Movement: %.2f pixels over %.3f wall seconds" % [moved,move_seconds])
	check(moved > 0 and moved <= config.walking_speed_pixels_per_second*move_seconds+1,"authority input direction normalized, no client delta / teleport")
	var resource: Dictionary = _resource("tree")
	_fixture_at(service.state.world.centre(Vector2i(resource["x"],resource["y"])))
	var wood_before: int = _quantity("host","wood")
	var gather: Dictionary = {"action":"gather","resource_id":resource["id"],"version":resource["version"]}
	check((await _request("survival.start",gather,"host-gather")).successful,"host gather start")
	_stage("gather:"+resource["id"])
	check(await _wait(func() -> bool: return _has_marker("gather-raced")),"remote contested pickup checked")
	check(await _wait(func() -> bool: return not service.state.survival.actions.has("host"),30),"gather finished")
	check(_quantity("host","wood") == wood_before+2 and _quantity("guest","wood") == 16,"pickup conservation over ENet")
	check((await _request("survival.start",gather,"host-gather")).successful and _quantity("host","wood") == wood_before+2,"network receipt replay no new output")
	_fixture_at(service.state.world.centre(service.state.world.spawn))
	var site: WildOperationResult = WildBuildingRules.auto_site(service.state.members["host"],"host",Vector2i(2,2))
	check(site.successful,"real camp placement")
	if not site.successful:
		_finish()
		return
	var build: Dictionary = {"action":"build","recipe":"camp","x":site.payload["x"],"y":site.payload["y"]}
	check((await _request("survival.start",build,"camp")).successful,"camp reservation")
	_stage("build:%d:%d" % [site.payload["x"],site.payload["y"]])
	check(await _wait(func() -> bool: return _has_marker("build-raced")),"remote same site race checked")
	check(await _wait(func() -> bool: return service.state.survival.buildings.size() == 1,40),"camp committed")
	check(service.state.boxes.is_empty(),"camp does not grant free box")
	check(_quantity("host","wood") == wood_before+2-8 and _quantity("guest","wood") == 16,"builder consumes once")
	var box_site: WildOperationResult = FIXTURES.box_site(service.state.members["host"],"host")
	check(box_site.successful,"reachable box footprint")
	check((await _request("survival.start",{"action":"build","recipe":"storage_box","x":box_site.payload["x"],"y":box_site.payload["y"]},"build-box")).successful,"independent box construction")
	check(await _wait(func() -> bool: return service.state.boxes.size() == 1,25),"box committed after thirty game minutes")
	check(_quantity("host","wood") == wood_before+2-14 and _quantity("host","fiber") == 0,"box consumes six wood four fiber")
	var box: WildInventoryContainer = service.state.boxes.values()[0]
	var bag: WildInventoryContainer = service.state.members["host"].containers["backpack"]
	var wood_id: String = FIXTURES.stack_with_amount(service.state.members["host"],&"wood",2)
	var deposit: Dictionary = {"source":"backpack","target":box.container_id,"item_id":wood_id,"quantity":2,"auto":true,"source_version":bag.version,"target_version":box.version}
	check((await _request("inventory.transfer",deposit,"deposit")).successful,"public deposit through request")
	box = service.state.boxes[box.container_id]
	var withdrawal: Dictionary = {"source":box.container_id,"target":"backpack","item_id":box.placements.keys()[0],"quantity":2,"auto":true,"source_version":box.version,"target_version":service.state.members["host"].containers["backpack"].version}
	_stage("box")
	check(await _wait(func() -> bool: return _has_marker("box-done")),"client public withdraw / replay completed")
	check((await _request("inventory.transfer",withdrawal,"compete-box")).code == &"STALE_VERSION","second actor stale concurrent box request rejected")
	check(service.state.boxes[box.container_id].placements.is_empty() and _quantity("guest","wood") == 18,"shared item transferred once")
	var before_time: float = service.state.survival.elapsed_seconds
	_stage("menu")
	check(await _wait(func() -> bool: return _has_marker("menu-done")),"personal menu test completed")
	check(service.state.survival.elapsed_seconds > before_time+60,"menu did not pause host clock")
	var next: Dictionary = _resource("fiber")
	_fixture_at(service.state.world.centre(Vector2i(next["x"],next["y"])))
	_stage("disconnect:"+next["id"])
	check(await _wait(func() -> bool: return service.online.get("guest",false) == false),"actual ENet peer disconnect")
	var offline_water: float = service.state.survival.bodies["guest"].water
	var offline_position: Vector2 = service.state.world.players["guest"]
	check(not service.state.survival.actions.has("guest"),"disconnect cancels unfinished reservation")
	check(await _wait(func() -> bool: return _has_marker("reconnect-done"),15),"real original member reconnect")
	check(service.state.members.size() == 2 and service.state.world.players.size() == 2,"reconnect no duplicate actor")
	check(service.state.world.players["guest"].is_equal_approx(offline_position),"reconnect preserves position")
	check(service.state.survival.bodies["guest"].water < offline_water,"offline character continued body simulation")
	check(_quantity("guest","wood") == 18 and _quantity("guest","fiber") == 10,"reconnect preserves loadout, no cancelled output")
	_stage("finish")
	check(await _wait(func() -> bool: return _has_marker("ready-end")),"client final state agreement")
	check(network.end_host().successful,"host persisted before ending")
	await get_tree().create_timer(0.5).timeout
	network.close_connection()
	var decoded: WildCoopState = WildCoopCodec.decode(store.load_records().payload["primary"],config,CATALOG,CONTENT)
	check(decoded != null and decoded.members.size() == 2,"host final disk recovery")
	_finish()

func _run_client() -> void:
	check(network.join("127.0.0.1",port) == OK,"ENet localhost client")
	check(await _wait(func() -> bool: return network._welcomed),"complete map snapshot handshake")
	if not network._welcomed:
		_finish()
		return
	var world: WildWorldData = WildWorldCodec.decode(network.latest["world"],config)
	check(world != null and world.seed_text == "17" and world.players.size() == 2,"host map decoded, no local regeneration")
	check(not network.latest.has("members") and not network.latest.has("token_hashes"),"private snapshot boundary")
	replica = WildCoopReplicaSession.new()
	replica.configure(network,"guest",config,CATALOG)
	check(await _wait(func() -> bool: return _notice("move")),"movement stage")
	# 输入大于 1 也只能按配置速度行走；客户端无 delta 字段。
	var direction := Vector2.RIGHT
	var point: Vector2 = world.centre(world.spawn)
	for option: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		if WildWorldRules.feet_clear(world,point+option*64):
			direction = option
			break
	network.set_input(direction*999,false)
	await get_tree().create_timer(1).timeout
	network.set_input(Vector2.ZERO,false)
	await get_tree().create_timer(0.3).timeout
	await _marker("move-done")
	check(await _wait(func() -> bool: return str(network.latest.get("notice","")).begins_with("gather:")),"gather contention stage")
	var resource_id: String = str(network.latest["notice"]).trim_prefix("gather:")
	var gather: Dictionary = {"action":"gather","resource_id":resource_id,"version":network.latest["resources"][resource_id]["version"]}
	check((await _request("survival.start",gather,"race-gather")).code == &"RESOURCE_RESERVED","remote resource lock feedback")
	await _marker("gather-raced")
	check(await _wait(func() -> bool: return str(network.latest.get("notice","")).begins_with("build:"),35),"build contention stage")
	var parts: PackedStringArray = str(network.latest["notice"]).split(":")
	check((await _request("survival.start",{"action":"build","recipe":"camp","x":parts[1].to_int(),"y":parts[2].to_int()},"race-build")).code == &"SITE_RESERVED","remote footprint lock feedback")
	await _marker("build-raced")
	check(await _wait(func() -> bool: return _notice("box"),65),"public box stage")
	var box: Dictionary = {}
	for id: String in network.latest["containers"]:
		if id.begins_with("camp_box:"): box = network.latest["containers"][id]
	check(not box.is_empty() and box["entries"].size() == 1,"public box snapshot visible nearby")
	if box.is_empty():
		_finish()
		return
	var withdrawal: Dictionary = {"source":box["id"],"target":"backpack","item_id":box["entries"][0]["item"]["id"],"quantity":2,"auto":true,"source_version":box["version"],"target_version":network.latest["containers"]["backpack"]["version"]}
	if fault: network.force_next_drop = true # 另加一次定向请求丢失，验证同 ID 重试。
	check((await _request("inventory.transfer",withdrawal,"withdraw")).successful,"reliable transaction recovered from app loss")
	check((await _request("inventory.transfer",withdrawal,"withdraw")).successful,"same request replay successful")
	await _marker("box-done")
	check(await _wait(func() -> bool: return _notice("menu")),"menu stage")
	replica.submit(WildGameCommand.new("guest",&"base.open_pause"))
	var before_time: float = network.latest["elapsed_seconds"]
	await get_tree().create_timer(1.2).timeout
	# 故障网络下分钟提交 / 快照可能晚到；保持菜单打开并有界等待，冻结仍会失败。
	var progressed: bool = await _wait(func() -> bool: return network.latest["elapsed_seconds"] > before_time+60,4)
	check(not replica.is_paused() and progressed,"personal menu leaves authoritative time running")
	replica.submit(WildGameCommand.new("guest",&"base.close_station"))
	await _marker("menu-done")
	check(await _wait(func() -> bool: return str(network.latest.get("notice","")).begins_with("disconnect:")),"disconnect stage")
	resource_id = str(network.latest["notice"]).trim_prefix("disconnect:")
	check((await _request("survival.start",{"action":"gather","resource_id":resource_id,"version":network.latest["resources"][resource_id]["version"]},"cancel-offline")).successful,"start before disconnect")
	var secret: String = network.token
	network.close_connection()
	await get_tree().create_timer(1.5).timeout
	# 新身份也能建立 UDP 连接，但不能进入已锁定名单。
	network.configure_identity("intruder","中途玩家","")
	network.join("127.0.0.1",port)
	check(await _wait(func() -> bool: return " ".join(statuses).contains("ROSTER_LOCKED")),"late new member rejected over network")
	network.close_connection()
	network.configure_identity("guest","队友",secret)
	check(network.join("127.0.0.1",port) == OK,"reconnect ENet client")
	check(await _wait(func() -> bool: return network._welcomed),"reconnect secret accepted")
	check(network.latest["players"].size() == 2 and network.latest["action"].is_empty(),"reconnect snapshot no new actor or unfinished action")
	await _marker("reconnect-done")
	check(await _wait(func() -> bool: return _notice("finish")),"final agreement stage")
	var total: int = 0
	for entry: Dictionary in network.latest["containers"]["backpack"]["entries"]:
		if entry["item"]["item_id"] == "wood": total += int(entry["item"]["quantity"])
	check(total == 18,"client authoritative inventory matches host")
	if fault:
		check(network.dropped_packets > 0 and network.retransmissions > 0,"100 ms / 1% app fault injection exercised")
		check(_command_times.max() >= 90,"recorded remote command delay >= simulated RTT")
	await _marker("ready-end")
	check(await _wait(func() -> bool: return _ending_received),"host saved and ended notification")
	_finish()

func _finish() -> void:
	if _finished: return
	_finished = true
	print("%s transport status %d, peers %s, sent %d, received %d" % [role,network.multiplayer.multiplayer_peer.get_connection_status(),network.multiplayer.get_peers(),network.sent_packets,network.received_packets])
	var telemetry: Dictionary = {"role":role,"passed":passed,"failed":failed,"fault_rtt_ms":100 if fault else 0,"fault_drop_every":100 if fault else 0,"fault_layer":"application messages over real ENet, not OS UDP shaping","sent_packets":network.sent_packets,"dropped_packets":network.dropped_packets,"forced_dropped_packets":network.forced_dropped_packets,"retransmissions":network.retransmissions,"command_ms":_command_times,"elapsed_real_ms":Time.get_ticks_msec()-_started_at}
	if network.authority != null: telemetry["unreliable_frame_payload_bytes"] = var_to_bytes(network._position_frame()).size()
	WildBaseStateStore.new(case_root+"/"+role+"-result.json").save_record(telemetry)
	print("%s ENet %s: %d passed, %d failed" % [suite_label,role,passed,failed])
	network.close_connection()
	service = null
	replica = null
	get_tree().quit(0 if failed == 0 else 1)
