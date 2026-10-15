extends Node
## 四个独立 Godot 进程，网络业务只经 ENet；测试标记文件仅同步夹具布置阶段。
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")
const P5 = preload("res://tests/p5_fixtures.gd")
const PATHS = preload("res://tests/verification_paths.gd")
var role: String = ""
var case_root: String = ""
var port: int = 0
var fault: bool = false
var fault_rtt_ms: int = 0
var drop_every: int = 100
var resume: bool = false
var network: WildENetRoom
var service: WildFullCoopService
var world_store: WildDurableStateStore
var profile_store: WildDurableStateStore
var profile: WildBaseService
var link: WildCoopProfileLink
var replica: WildCoopReplicaSession
var results: Dictionary = {}
var passed: int = 0
var failed: int = 0
var started: int = 0
var finished: bool = false
var ended: bool = false
var token_store: WildBaseStateStore
var _loaded: bool = false
var _telemetry_at: int = 0
var statuses: Array[String] = []

func _ready() -> void:
	Engine.max_fps = 60
	if not PATHS.arguments_are_isolated(): get_tree().quit(1); return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--role="): role = argument.trim_prefix("--role=")
		if argument.begins_with("--case-root="): case_root = argument.trim_prefix("--case-root=")
		if argument.begins_with("--port="): port = argument.trim_prefix("--port=").to_int()
		if argument.begins_with("--fault="): fault_rtt_ms = argument.trim_prefix("--fault=").to_int(); fault = fault_rtt_ms > 0
		if argument.begins_with("--drop-every="): drop_every = argument.trim_prefix("--drop-every=").to_int()
		if argument == "--resume": resume = true
	if not PATHS.isolated_path(case_root) or role not in ["p0","p1","p2","p3"] or port < 1024: get_tree().quit(1); return
	started = Time.get_ticks_msec()
	network = WildENetRoom.new()
	network.name = "Network"
	network.full_cooperation = true
	network.content_fingerprint = WildNetworkCompatibility.fingerprint()
	network.bind_address = "127.0.0.1"
	network.fault_delay_ms = ceili(fault_rtt_ms/2.0) if fault else 0
	network.fault_drop_every = maxi(2,drop_every) if fault else 0
	add_child(network)
	network.command_completed.connect(func(id: String,result: WildOperationResult) -> void: results[id] = result)
	network.connection_status.connect(func(value: String) -> void:
		statuses.append(value)
		print(role+" "+value))
	network.room_ended.connect(func() -> void: ended = true)
	token_store = WildBaseStateStore.new(case_root+"/"+role+"-token.json")
	var secret: String = str(token_store.load_records().payload["primary"].get("token","host-secret" if role == "p0" else ""))
	network.configure_identity(role,role,secret,func(token: String) -> bool: return token_store.save_record({"token":token}).successful)
	profile_store = WildDurableStateStore.new(case_root+"/"+role+"-base.json")
	if not profile_store.load_records().payload.get("exists",false):
		var state := WildBaseState.new(role,CONFIG)
		for kind: String in ["ration","knife","flint","bottle","wood","fiber","stone"]: P5.give(state,kind,int({"ration":3,"wood":16,"fiber":10,"stone":3}.get(kind,1)))
		check(profile_store.save_record(state.record()).successful,"isolated personal kit saved")
	profile = WildBaseService.new(CONFIG,CATALOG,profile_store.load_records,profile_store.save_record,Callable(),Callable(),CONTENT)
	check(profile.initialize(role).successful,"personal base opens")
	link = WildCoopProfileLink.new()
	link.configure(network,profile,role)
	replica = WildCoopReplicaSession.new()
	replica.configure(network,role,CONFIG,CATALOG)
	network.snapshot_received.connect(_snapshot)
	if role == "p0": _host.call_deferred()
	else: _client.call_deferred()

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
		print(role+" PASS "+label)
	else:
		failed += 1
		push_error(role+" FAIL "+label)

func _process(_delta: float) -> void:
	if Time.get_ticks_msec()-_telemetry_at >= 10000:
		_telemetry_at = Time.get_ticks_msec()
		print(role+" telemetry "+str(Time.get_ticks_msec()-started)+" phase "+str(network.latest.get("cooperation",{}).get("phase",""))+" queue "+str(network._outbox.size())+" pending "+str(network._pending.keys()))
	if not finished and Time.get_ticks_msec()-started > 420000:
		check(false,"four player case timed out")
		_finish()

func _wait(predicate: Callable, seconds: float = 60) -> bool:
	var deadline: int = Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await get_tree().create_timer(0.05).timeout
	return bool(predicate.call())

func _request(operation: String, payload: Dictionary, id: String) -> WildOperationResult:
	results.erase(id)
	network.request(operation,payload,id)
	if not await _wait(func() -> bool: return results.has(id)):
		check(false,"request timeout "+id)
		return WildOperationResult.reject(&"TIMEOUT")
	print(role+" request "+operation+" => "+str((results[id] as WildOperationResult).code))
	return results[id]

func _snapshot(data: Dictionary) -> void:
	var coop: Dictionary = data.get("cooperation",{})
	if coop.get("phase","") == "loading" and not _loaded and not data.get("world",{}).is_empty():
		check(WildCanonicalData.digest(data["world"]) == coop["world_hash"] and WildWorldCodec.decode(data["world"],CONFIG) != null,"received authoritative scaled map / hash")
		_loaded = true
		network.request("room.loaded",{"world_hash":coop["world_hash"]},"loaded:"+role)

func _mark(name: String) -> void:
	FileAccess.open(case_root+"/"+role+"-"+name+".txt",FileAccess.WRITE).store_string("ready")

func _has(actor: String, name: String) -> bool:
	return FileAccess.file_exists(case_root+"/"+actor+"-"+name+".txt")

func _stage(name: String) -> void:
	FileAccess.open(case_root+"/stage.txt",FileAccess.WRITE).store_string(name)

func _at_stage(name: String) -> bool:
	return FileAccess.file_exists(case_root+"/stage.txt") and FileAccess.get_file_as_string(case_root+"/stage.txt") == name

func _all(name: String) -> bool:
	for actor: String in ["p1","p2","p3"]:
		if not _has(actor,name): return false
	return true

func _host() -> void:
	world_store = WildDurableStateStore.new(case_root+"/world.json")
	service = WildFullCoopService.new(CONFIG,CATALOG,CONTENT,world_store.save_record)
	if resume:
		check(service.restore(world_store.load_records().payload["primary"],role).successful,"process restart restores exact durable world")
	else:
		check(service.create(role,role,"17",network.token).successful,"full four player world created")
	check(network.host(service,port) == OK,"loopback ENet host")
	FileAccess.open(case_root+("/restart-ready.txt" if resume else "/ready.txt"),FileAccess.WRITE).store_string("ready")
	if not resume:
		check(link.reserve_and_offer().successful,"host personal escrow offered")
		check(await _wait(func() -> bool: return service.state.lifecycle["offers"].size() == 4 and service.state.lifecycle["ready"].values().count(true) == 3),"three separate clients offered / ready")
		check((await _request("room.ready",{"ready":true},"ready:p0")).successful,"host ready")
		check((await _request("room.start",{},"start")).successful,"four member departure")
		check(await _wait(func() -> bool: return service.state.lifecycle["phase"] == "running"),"all four map ACK barrier")
		check(service.state.world.resource_players == 4 and service.state.survival.departure_players == 4,"four person resource / animal scaling")
		check(JSON.stringify(network._position_frame()).length() < 1200,"four person frame fits initial budget")
		_stage("inspect")
		check(await _wait(func() -> bool: return _all("inspected")),"all clients see private full snapshots")
		_stage("practice")
		var resource: Dictionary = {}
		var resource_distance: float = INF
		for candidate: Dictionary in service.state.world.resources.values():
			var distance: float = Vector2(candidate["x"],candidate["y"]).distance_to(service.state.world.spawn)
			if candidate["kind"] == "fiber" and distance < resource_distance:
				resource = candidate
				resource_distance = distance
		service.state.world.players["p1"] = service.state.world.centre(Vector2i(resource["x"],resource["y"]))
		check(service.checkpoint().successful,"practice position fixture saved")
		WildBaseStateStore.new(case_root+"/practice.json").save_record({"id":resource["id"],"version":resource["version"]})
		network._broadcast(true)
		_mark("practice-ready")
		check(await _wait(func() -> bool: return service.state.survival.actions.has("p1")),"remote effective practice starts")
		if service.state.survival.actions.has("p1"):
			WildSurvivalSimulation.queue_time(service.state.survival,service.state.survival.actions["p1"]["remaining"],"idle")
			service._simulate(service.state,true)
			check(service.checkpoint().successful,"practice growth and outbox committed together")
			network._broadcast(true)
		check(await _wait(func() -> bool: return _has("p1","growth-saved")),"personal permanent growth saved before departure end")
		# 崩溃场景在完成一次真实个人成长后终止整个房主进程，PowerShell 启动新进程恢复。
		if fault:
			check(service.checkpoint().successful,"pre-crash world committed")
			FileAccess.open(case_root+"/crash-ready.txt",FileAccess.WRITE).store_string("ready")
			check(await _wait(func() -> bool: return _all("crash-ready")),"clients ready for host process interruption")
			_stage("crashing")
			await get_tree().create_timer(0.3).timeout
			_finish(true)
			return
	else:
		check(await _wait(func() -> bool: return service.online.values().count(true) == 4),"all original members reconnect after host process restart")
		check(service.state.members.size() == 4,"restart creates no fifth character")
		check(await _wait(func() -> bool: return _all("host-restored")),"clients confirm no second loadout import")
	# 并发取公共箱中同一实例；先用实际建造规则构建箱，再布置一枚测试箭矢。
	var box_build: String = await _build("storage_box")
	check(not box_build.is_empty(),"public storage constructed")
	if box_build.is_empty(): _finish(); return
	var box_id: String = "camp_box:"+box_build
	var box: WildInventoryContainer = service.state.boxes[box_id]
	var arrow := WildItemInstance.new(CATALOG.find(&"arrow"))
	box.placements[arrow.instance_id] = {"item":arrow,"position":Vector2i.ZERO,"rotated":false}
	for actor: String in service.state.members: service.state.world.players[actor] = service.state.world.players[role]
	check(service.checkpoint().successful,"one shared item fixture saved")
	WildBaseStateStore.new(case_root+"/race.json").save_record({"box":box_id,"item":arrow.instance_id,"version":box.version})
	network._broadcast(true)
	_stage("race")
	check(await _wait(func() -> bool: return _all("raced")),"three clients race same public item")
	var winners: int = 0
	for actor: String in ["p1","p2","p3"]: winners += _quantity(service.state.members[actor],"arrow")
	check(winners == 1 and service.state.boxes[box_id].placements.is_empty(),"one item across four member shared transaction")
	_stage("gift")
	check(await _wait(func() -> bool: return _has("p2","gifted")),"explicit recipient accepts actual gift")
	check(_quantity(service.state.members["p1"],"ration") == 0 and _quantity(service.state.members["p2"],"ration") == 6,"gift conservation / private ownership")
	var camp_id: String = await _build("camp")
	check(not camp_id.is_empty(),"actual camp built for unanimous sleep")
	for actor: String in service.state.members: service.state.world.players[actor] = service.state.world.players[role]
	check(service.checkpoint().successful,"all four near camp fixture saved")
	network._broadcast(true)
	_stage("sleep")
	check((await _request("sleep.vote",{"hours":1},"sleep-vote:p0")).successful,"host proposes cooperative sleep")
	check(await _wait(func() -> bool: return service.state.lifecycle["vote"].get("sleeping",false)),"all four network votes start shared sleep")
	check(service.apply_world_damage("p2",1,"environment").successful and service.state.lifecycle["vote"].is_empty(),"authority damage wakes all four")
	network._broadcast(true)
	_mark("sleep-interrupted")
	check(await _wait(func() -> bool: return _all("sleep-checked")),"all clients observe shared sleep interruption")
	_stage("offline-death")
	check(await _wait(func() -> bool: return not service.online.get("p3",true)),"original member disconnects")
	check(service.apply_world_damage("p3",1000,"physical").successful,"offline body can die")
	check(service.state.corpses.has("corpse:p3"),"offline death makes corpse")
	FileAccess.open(case_root+"/allow-reconnect.txt",FileAccess.WRITE).store_string("ready")
	check(await _wait(func() -> bool: return service.online.get("p3",false)),"dead original member reconnects")
	check(await _wait(func() -> bool: return _has("p3","dead-checked")),"dead client confirms no revival / action")
	_stage("loot")
	network._broadcast(true)
	check(await _wait(func() -> bool: return _has("p1","looted")),"teammate withdraws corpse rations")
	check(_quantity(service.state.members["p1"],"ration") == 3 and _quantity(service.state.members["p3"],"ration") == 0,"corpse transfer cannot duplicate dead inventory")
	# 布置合法到期前一分钟，真正共用模拟触发死亡优先 / 逐人结算；并非声称四进程跑满七日。
	var run: WildSurvivalState = service.state.survival
	run.elapsed_seconds = CONFIG.target_survival_hours*3600-60
	run.pending_seconds = 0
	run.segments.clear()
	for id: String in run.fish_refills: run.fish_refills[id] = CONFIG.target_survival_hours*3600+CONTENT.fish_refill_seconds
	run.next_animal_refill = CONFIG.target_survival_hours*3600+CONFIG.combat_rules.refill_seconds
	run.next_disturbance = CONFIG.target_survival_hours*3600+3600
	WildSurvivalSimulation.queue_time(run,60,"idle")
	service._simulate(service.state,true)
	check(service.checkpoint().successful and service.state.lifecycle["phase"] == "settled","shared terminal world / outboxes committed")
	network._broadcast(true)
	_stage("settled")
	check(await _wait(func() -> bool: return _all("settled")),"all three personal stores apply terminal delivery")
	check(not WildCoopProfileRules.blocked(profile._state) and profile.snapshot()["currency"] >= CONFIG.starting_currency+600,"host personal settlement applied")
	var restored := WildFullCoopService.new(CONFIG,CATALOG,CONTENT,world_store.save_record)
	check(restored.restore(world_store.load_records().payload["primary"],role).successful,"terminal world restores without extra rewards")
	check(network.end_host().successful,"host normal save / end")
	await get_tree().create_timer(0.6).timeout
	_finish()

func _build(kind: String) -> String:
	var personal: WildBaseState = service.state.members[role]
	var recipe: Dictionary = CONTENT.recipe(kind)
	var site: Dictionary = P5.open_site(personal,Vector2i(recipe["width"],recipe["height"]),service.state.world.spawn)
	if site.is_empty(): return ""
	var result: WildOperationResult = await _request("survival.start",{"action":"build","recipe":kind,"x":site["x"],"y":site["y"]},"build:"+kind)
	check(result.successful,"host submits actual construction "+kind)
	if not result.successful: return ""
	WildSurvivalSimulation.queue_time(service.state.survival,service.state.survival.actions[role]["remaining"],"idle")
	service._simulate(service.state,true)
	service.checkpoint()
	for id: String in service.state.survival.buildings:
		if service.state.survival.buildings[id]["kind"] == kind: return id
	return ""

func _client() -> void:
	if role == "p3":
		var fingerprint: String = network.content_fingerprint
		network.content_fingerprint = "wrong-version"
		check(network.join("127.0.0.1",port) == OK,"incompatible client transport connects")
		check(await _wait(func() -> bool: return statuses.any(func(value: String) -> bool: return value.contains("CONTENT_MISMATCH"))),"content mismatch rejected before roster / loadout")
		network.close_connection()
		network.content_fingerprint = fingerprint
	check(network.join("127.0.0.1",port) == OK,"real client connects")
	check(await _wait(func() -> bool: return not network.latest.is_empty()),"private welcome received")
	check(link.reserve_and_offer().successful,"personal departure lease submitted")
	check(await _wait(func() -> bool: return network.latest.get("cooperation",{}).get("has_loadout",false)),"host accepted actual inventory")
	check((await _request("room.ready",{"ready":true},"ready:"+role)).successful,"client ready")
	check(await _wait(func() -> bool: return _at_stage("inspect")),"all four running")
	check(await _wait(func() -> bool: return network.latest["players"].size() == 4 and network.latest["cooperation"]["phase"] == "running"),"four players synchronized")
	check(network.latest["containers"].has("backpack") and not network.latest["containers"].has("warehouse"),"private inventory excludes permanent warehouse")
	check(network.latest["players"].values().all(func(player: Dictionary) -> bool: return not player.has("containers")),"other player private items hidden")
	check((await _request("combat.damage",{"amount":999999},"forged-damage")).code == &"UNKNOWN_COMMAND","client has no damage endpoint")
	_mark("inspected")
	check(await _wait(func() -> bool: return _has("p0","practice-ready")),"practice stage ready")
	if role == "p1":
		var practice: Dictionary = WildBaseStateStore.new(case_root+"/practice.json").load_records().payload["primary"]
		check((await _request("survival.start",{"action":"gather","resource_id":practice["id"],"version":practice["version"]},"effective-practice")).successful,"bound client gathering command")
		check(await _wait(func() -> bool: return profile.snapshot()["skills"]["experience"]["gathering"] > 0),"effective practice delivered to permanent local skill profile")
		_mark("growth-saved")
	if fault:
		check(await _wait(func() -> bool: return FileAccess.file_exists(case_root+"/crash-ready.txt")),"host durable crash point")
		_mark("crash-ready")
		check(await _wait(func() -> bool: return ended),"actual old host process disconnected")
		check(WildCoopProfileRules.blocked(profile._state),"host crash retains escrow")
		network.close_connection()
		ended = false
		check(await _wait(func() -> bool: return FileAccess.file_exists(case_root+"/restart-ready.txt")),"new host process ready")
		var token: String = token_store.load_records().payload["primary"]["token"]
		network.configure_identity(role,role,token)
		check(network.join("127.0.0.1",port) == OK,"original token joins restored process")
		check(await _wait(func() -> bool: return not network.latest.is_empty()),"restored private snapshot")
		check(_snapshot_quantity("ration") == 3,"process restart does not copy second kit")
		if role == "p1": check(profile.snapshot()["skills"]["experience"]["gathering"] > 0 and network.latest["skills"]["experience"]["gathering"] > 0,"cross-process world / permanent skill growth retained")
		_mark("host-restored")
	check(await _wait(func() -> bool: return _at_stage("race")),"public race stage")
	var race: Dictionary = WildBaseStateStore.new(case_root+"/race.json").load_records().payload["primary"]
	check(await _wait(func() -> bool: return network.latest["containers"].has(race["box"])),"near public box synchronized")
	var transfer: Dictionary = {"source":race["box"],"target":"backpack","item_id":race["item"],"source_version":race["version"],"target_version":network.latest["containers"]["backpack"]["version"],"auto":true}
	if fault and role == "p1": network.force_next_drop = true
	var taken: WildOperationResult = await _request("inventory.transfer",transfer,"race-item")
	check(taken.successful or taken.code == &"STALE_VERSION","race either single success or explicit stale version")
	if taken.successful: check((await _request("inventory.transfer",transfer,"race-item")).successful,"lost / repeated take has same receipt")
	_mark("raced")
	check(await _wait(func() -> bool: return _at_stage("gift")),"gift stage")
	if role == "p1":
		var id: String = _snapshot_item("ration")
		check((await _request("gift.offer",{"target":"p2","item_id":id},"gift-offer")).successful,"giver submits explicit offer")
	if role == "p2":
		check(await _wait(func() -> bool: return not network.latest["cooperation"]["gifts"].is_empty()),"recipient sees pending offer")
		var gift: Dictionary = network.latest["cooperation"]["gifts"].values()[0]
		check((await _request("gift.accept",{"gift_id":gift["id"]},"gift-accept")).successful,"recipient confirms gift")
		check((await _request("gift.accept",{"gift_id":gift["id"]},"gift-accept")).successful,"gift confirmation replay idempotent")
		_mark("gifted")
	check(await _wait(func() -> bool: return _at_stage("sleep")),"four member sleep stage")
	check((await _request("sleep.vote",{"hours":1},"sleep-vote:"+role)).successful,"client agrees same sleep duration")
	check(await _wait(func() -> bool: return _has("p0","sleep-interrupted")),"host shared interruption committed")
	check(await _wait(func() -> bool: return network.latest["cooperation"]["vote"].is_empty()),"client sees entire group awake")
	_mark("sleep-checked")
	check(await _wait(func() -> bool: return _at_stage("offline-death")),"offline member stage")
	if role == "p3":
		var token: String = network.token
		network.close_connection()
		check(await _wait(func() -> bool: return FileAccess.file_exists(case_root+"/allow-reconnect.txt")),"offline death saved")
		network.configure_identity(role,role,token)
		check(network.join("127.0.0.1",port) == OK,"dead original member reconnects")
		check(await _wait(func() -> bool: return not network.latest.is_empty()),"dead private snapshot restored")
		check(network.latest["players"][role]["body"]["health_points"] == 0 and _snapshot_quantity("ration") == 0,"death / private inventory retained")
		check((await _request("survival.cancel",{},"dead-action")).code == &"INVALID_PHASE","dead client cannot act as spectator")
		_mark("dead-checked")
	check(await _wait(func() -> bool: return _at_stage("loot")),"corpse stage")
	if role == "p1":
		check(await _wait(func() -> bool: return network.latest["containers"].has("corpse:p3")),"near corpse view")
		var corpse: Dictionary = network.latest["containers"]["corpse:p3"]
		var id: String = ""
		for entry: Dictionary in corpse["entries"]:
			if entry["item"]["item_id"] == "ration": id = entry["item"]["id"]
		check((await _request("inventory.transfer",{"source":"corpse:p3","target":"backpack","item_id":id,"source_version":corpse["version"],"target_version":network.latest["containers"]["backpack"]["version"],"auto":true},"loot-corpse")).successful,"actual corpse withdrawal")
		_mark("looted")
	check(await _wait(func() -> bool: return _at_stage("settled")),"terminal world reached")
	check(await _wait(func() -> bool: return not WildCoopProfileRules.blocked(profile._state)),"personal terminal receipt committed")
	var currency: int = profile.snapshot()["currency"]
	check(currency == CONFIG.starting_currency if role == "p3" else currency >= CONFIG.starting_currency+600,"dead / living rewards independently correct")
	var reloaded := WildBaseService.new(CONFIG,CATALOG,profile_store.load_records,profile_store.save_record,Callable(),Callable(),CONTENT)
	check(reloaded.initialize(role).successful and reloaded.snapshot()["currency"] == currency,"actual JSON personal reward restores once")
	_mark("settled")
	check(await _wait(func() -> bool: return ended),"normal host ending delivered")
	check(profile.snapshot()["currency"] == currency,"terminal resend cannot duplicate currency")
	_finish()

func _quantity(state: WildBaseState, kind: String) -> int:
	var value: int = 0
	for container: WildInventoryContainer in state.containers.values():
		for entry: Dictionary in container.placements.values():
			if str((entry["item"] as WildItemInstance).item_id) == kind: value += (entry["item"] as WildItemInstance).quantity
	return value

func _snapshot_quantity(kind: String) -> int:
	var value: int = 0
	for id: String in WildCoopProfileRules.SLOTS:
		for entry: Dictionary in network.latest["containers"][id]["entries"]:
			if entry["item"]["item_id"] == kind: value += int(entry["item"]["quantity"])
	return value

func _snapshot_item(kind: String) -> String:
	for entry: Dictionary in network.latest["containers"]["backpack"]["entries"]:
		if entry["item"]["item_id"] == kind: return entry["item"]["id"]
	return ""

func _finish(crash_stage: bool = false) -> void:
	if finished: return
	finished = true
	var record: Dictionary = {"passed":passed,"failed":failed,"dropped_packets":network.dropped_packets,"retransmissions":network.retransmissions,"crash_stage":crash_stage,"configured_rtt_ms":fault_rtt_ms,"drop_every":network.fault_drop_every,"sent_packets":network.sent_packets}
	WildBaseStateStore.new(case_root+"/"+role+("-before-restart" if crash_stage else "")+"-result.json").save_record(record)
	network.close_connection()
	print("P6.5 "+role+" network checks: %d passed, %d failed" % [passed,failed])
	get_tree().quit(0 if failed == 0 else 1)
