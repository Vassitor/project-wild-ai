extends "res://tests/p35_network.gd"
## 真双进程：实际捕鱼等待默认时钟；营地 / 六小时陷阱按同一房主模拟加速测试。
const F = preload("res://tests/p5_fixtures.gd")
var _final_drop_injected: bool = false

func _ready() -> void:
	suite_label = "P5"
	super._ready()

func _advance(seconds: float) -> void:
	WildSurvivalSimulation.queue_time(service.state.survival,seconds,"idle")
	service._simulate(service.state,true)
	service.checkpoint()
	network._broadcast(true)

func _at_site(dimensions: Vector2i, near: Vector2i = Vector2i(-1,-1)) -> Dictionary:
	var site: Dictionary = F.open_site(service.state.members["host"],dimensions,near)
	service.state.world.players["guest"] = service.state.world.players["host"]+Vector2(0,4)
	return site

func _run_host() -> void:
	network.command_handled.connect(func(peer: int, request: String, _result: WildOperationResult) -> void:
		if fault and not _final_drop_injected and peer != 1 and request == "ready-end":
			_final_drop_injected = true
			network.force_next_drop = true)
	store = WildBaseStateStore.new(case_root+"/room.json")
	service = WildCoopService.new(config,CATALOG,CONTENT,store.save_record)
	check(service.create("host","房主","17","host-secret").successful,"progression isolated room")
	check(network.host(service,port) == OK,"progression ENet server")
	var ready := FileAccess.open(case_root+"/ready.txt",FileAccess.WRITE)
	ready.store_string("ready")
	ready.close()
	check(await _wait(func() -> bool: return service.state.members.size() == 2),"progression client handshake")
	if service.state.members.size() != 2: _finish(); return
	check((await _request("skill.train",{"branch":"building","tier":1},"host-building")).successful,"host lobby building learning")
	check((await _request("skill.train",{"branch":"trap","tier":1},"host-trap")).successful,"host lobby trap learning")
	_stage("school")
	check(await _wait(func() -> bool: return service.state.members["guest"].skills.levels["building"] == 1 and service.state.members["guest"].skills.levels["trap"] == 1),"guest independently learns before departure")
	check(service.state.members["host"].currency == 0 and service.state.members["guest"].currency == 0,"individual validation learning charges")
	check((await _request("room.start",{},"start")).successful,"progression start")
	var fish: Dictionary = {}
	for resource: Dictionary in service.state.world.resources.values():
		if resource["kind"] == "fish": fish = resource; break
	for actor: String in ["host","guest"]: service.state.world.players[actor] = service.state.world.centre(Vector2i(fish["x"],fish["y"]))
	service.state.survival.fishing_random_states["guest"] = F.random_state_for(true,0.6)
	_stage("fish:"+fish["id"])
	check(await _wait(func() -> bool: return service.state.survival.actions.get("guest",{}).get("type","") == "fish"),"remote fishing begins")
	check((await _request("survival.start",{"action":"fish","resource_id":fish["id"],"version":fish["version"],"bait":"fiber"},"host-fish-race")).code == &"RESOURCE_RESERVED","shared fish point exclusive")
	check(_quantity("host","fiber") == 10 and _quantity("guest","fiber") == 9,"rejected race rolls back immediate bait")
	check(await _wait(func() -> bool: return _has_marker("fish-done"),22),"remote fishing completes normally")
	check(_quantity("guest","raw_fish") == 1 and _quantity("host","raw_fish") == 0,"fish output private and replay no duplicate")
	check(service.state.members["guest"].skills.experience["fishing"] == 8 and service.state.members["host"].skills.experience["fishing"] == 0,"XP executing actor only")
	var site: Dictionary = _at_site(Vector2i(4,4))
	check(not site.is_empty(),"expandable camp real site")
	check((await _request("survival.start",{"action":"build","recipe":"camp","x":site["x"],"y":site["y"]},"host-camp")).successful,"camp actual materials reserved")
	_advance(service.state.survival.actions["host"]["remaining"])
	var camp: Dictionary = {}
	for building: Dictionary in service.state.survival.buildings.values():
		if building["kind"] == "camp": camp = building; break
	F.give(service.state.members["host"],"wood",4)
	for actor: String in ["host","guest"]:
		F.give(service.state.members[actor],"rope",2)
		F.give(service.state.members[actor],"hide",2)
	check((await _request("survival.start",{"action":"upgrade","building_id":camp["id"]},"host-upgrade")).successful,"upgrade authority")
	_stage("camp:"+camp["id"])
	check(await _wait(func() -> bool: return _has_marker("upgrade-raced")),"client expansion race attempted")
	check(_quantity("guest","wood") == 16 and _quantity("guest","rope") == 2,"failed expansion race retains guest materials")
	_advance(service.state.survival.actions["host"]["remaining"])
	check(service.state.survival.buildings[camp["id"]]["level"] == 2,"one expansion committed")
	check(service.state.members["host"].skills.experience["building"] == 16 and service.state.members["guest"].skills.experience["building"] == 0,"building XP owner of action")
	var animal: Dictionary = service.state.survival.prey.values()[0]
	site = _at_site(Vector2i.ONE,Vector2i(animal["x"],animal["y"]))
	F.give(service.state.members["host"],"wood")
	check((await _request("survival.start",{"action":"build","recipe":"small_trap","x":site["x"],"y":site["y"]},"host-trap-build")).successful,"actual trap construction")
	_advance(service.state.survival.actions["host"]["remaining"])
	var trap: Dictionary = {}
	for building: Dictionary in service.state.survival.buildings.values():
		if building["kind"] == "small_trap": trap = building; break
	F.give(service.state.members["host"],"berry",3)
	check((await _request("survival.start",{"action":"trap_bait","building_id":trap["id"],"quantity":3},"host-bait")).successful,"trap takes actual bait")
	_advance(service.state.survival.actions["host"]["remaining"])
	trap = service.state.survival.buildings[trap["id"]]
	trap["trap_random_state"] = F.random_state_for(true,0.4)
	_stage("trap-wait:"+trap["id"])
	check(await _wait(func() -> bool: return _has_marker("menu-checked")),"cooperative skill menu tested")
	_advance(maxf(0,trap["next_check"]-service.state.survival.elapsed_seconds)+1)
	trap = service.state.survival.buildings[trap["id"]]
	check(not trap["capture"].is_empty() and not service.state.survival.prey[trap["capture"]["prey_id"]]["alive"],"offscreen six hour actual prey capture")
	var caught_id: String = trap["capture"]["prey_id"]
	_stage("catch:"+trap["id"])
	check(await _wait(func() -> bool: return service.state.survival.actions.get("guest",{}).get("type","") == "trap_collect"),"remote collect begins")
	check((await _request("survival.start",{"action":"trap_collect","building_id":trap["id"]},"host-catch-race")).code == &"BUILDING_RESERVED","same capture lock")
	check(await _wait(func() -> bool: return _has_marker("catch-done")),"guest one catch completes")
	check(_quantity("guest","raw_meat") == 1 and _quantity("host","raw_meat") == 0,"one loot set private")
	check(service.state.members["guest"].skills.experience["trap"] == 8 and service.state.members["host"].skills.experience["trap"] == 0,"collector earns trap XP independently")
	_stage("reconnect")
	check(await _wait(func() -> bool: return not service.online.get("guest",true)),"progression disconnect")
	_advance(3600)
	_stage("rejoined")
	check(await _wait(func() -> bool: return _has_marker("rejoined-done")),"progression original member rejoined")
	check(service.checkpoint().successful,"growth / population checkpoint")
	var restored := WildCoopService.new(config,CATALOG,CONTENT,store.save_record)
	check(restored.restore(store.load_records().payload["primary"],"host").successful,"growth and traps JSON room restore")
	check(restored.state.members["guest"].skills.levels["trap"] == 1 and restored.state.members["guest"].skills.experience["trap"] == 8,"learned nodes and earned XP retain on host restore")
	check(not restored.state.survival.prey[caught_id]["alive"] and restored.state.survival.buildings[trap["id"]]["uses_left"] == 2,"trap use retained without respawn")
	_stage("finish")
	check(await _wait(func() -> bool: return _has_marker("ready-end")),"progression final agreement")
	check(network.end_host().successful,"progression saved end")
	if fault: check(network.forced_dropped_packets == 1,"final confirmation deliberately lost before ending")
	await get_tree().create_timer(0.4).timeout
	_finish()

func _run_client() -> void:
	check(network.join("127.0.0.1",port) == OK,"progression ENet client")
	check(await _wait(func() -> bool: return network._welcomed),"progression welcome")
	replica = WildCoopReplicaSession.new()
	replica.configure(network,"guest",config,CATALOG)
	check(await _wait(func() -> bool: return _notice("school")),"lobby learning stage")
	var learn: Dictionary = {"branch":"building","tier":1,"actor_id":"host"}
	check((await _request("skill.train",learn,"guest-school")).successful,"bound lobby learning despite payload actor")
	check((await _request("skill.train",learn,"guest-school")).successful,"learning receipt replay")
	check((await _request("skill.train",{"branch":"trap","tier":1},"guest-trap")).successful,"personal second lobby node")
	check(await _wait(func() -> bool: return str(network.latest.get("notice","")).begins_with("fish:")),"fish stage")
	check(network.latest["currency"] == 0 and network.latest["skills"]["levels"]["trap"] == 1,"client private growth / currency view")
	var fish_id: String = str(network.latest["notice"]).trim_prefix("fish:")
	var payload: Dictionary = {"action":"fish","resource_id":fish_id,"version":network.latest["resources"][fish_id]["version"],"bait":"fiber","actor_id":"host"}
	if fault: network.force_next_drop = true
	check((await _request("survival.start",payload,"guest-fish")).successful,"real remote fishing")
	check(await _wait(func() -> bool: return network.latest["skills"]["experience"]["fishing"] == 8,22),"remote fish completion XP snapshot")
	check((await _request("survival.start",payload,"guest-fish")).successful,"completed fish start replay")
	check(not (await _request("skill.unlock",{"branch":"fishing","tier":3,"experience":10000},"forged-growth")).successful,"client cannot submit forged experience or skipped tier")
	await _marker("fish-done")
	check(await _wait(func() -> bool: return str(network.latest.get("notice","")).begins_with("camp:")),"expansion stage")
	var camp_id: String = str(network.latest["notice"]).trim_prefix("camp:")
	check((await _request("survival.start",{"action":"upgrade","building_id":camp_id},"guest-upgrade-race")).code == &"SITE_RESERVED","remote expansion race feedback")
	await _marker("upgrade-raced")
	check(await _wait(func() -> bool: return str(network.latest.get("notice","")).begins_with("trap-wait:")),"trap waiting stage")
	var trap_id: String = str(network.latest["notice"]).trim_prefix("trap-wait:")
	check(network.latest["buildings"][camp_id]["level"] == 2,"shared expanded footprint visible")
	check(not network.latest["buildings"][trap_id].has("trap_random_state"),"future trap random sequence not sent to client")
	var panel := WildSkillPanel.new()
	panel.configure(replica,config)
	add_child(panel)
	replica.submit(WildGameCommand.new("guest",&"base.open_pause"))
	panel.open("guest")
	var before: float = network.latest["elapsed_seconds"]
	await get_tree().create_timer(1.2).timeout
	var progressed: bool = await _wait(func() -> bool: return network.latest["elapsed_seconds"] > before+60,4)
	check(not replica.is_paused() and progressed,"live skill menu leaves world clock running")
	panel.queue_free()
	replica.submit(WildGameCommand.new("guest",&"base.close_station"))
	await _marker("menu-checked")
	check(await _wait(func() -> bool: return str(network.latest.get("notice","")).begins_with("catch:"),35),"actual capture stage")
	check((await _request("survival.start",{"action":"trap_collect","building_id":trap_id},"guest-catch")).successful,"remote actual capture collection")
	check(await _wait(func() -> bool: return network.latest["skills"]["experience"]["trap"] == 8),"collector XP and loot completion")
	check((await _request("survival.start",{"action":"trap_collect","building_id":trap_id},"guest-catch")).successful,"collection receipt replay")
	check((await _request("survival.start",{"action":"trap_collect","building_id":trap_id},"second-catch")).code == &"TRAP_EMPTY","same prey cannot be collected twice")
	await _marker("catch-done")
	check(await _wait(func() -> bool: return _notice("reconnect")),"growth reconnect stage")
	var secret: String = network.token
	network.close_connection()
	await get_tree().create_timer(2).timeout
	network.configure_identity("guest","队友",secret)
	check(network.join("127.0.0.1",port) == OK,"growth reconnect client")
	check(await _wait(func() -> bool: return network._welcomed),"growth reconnect welcome")
	check(network.latest["skills"]["levels"]["trap"] == 1 and network.latest["skills"]["experience"]["trap"] == 8 and network.latest["skills"]["experience"]["fishing"] == 8,"reconnect retains nodes / both XP branches")
	await _marker("rejoined-done")
	check(await _wait(func() -> bool: return _notice("finish")),"growth finish stage")
	if fault: check(network.forced_dropped_packets == 1 and network.retransmissions > 0,"bait request loss safely retried without duplicate consumption")
	await _marker("ready-end")
	check(results.has("ready-end") and results["ready-end"].successful,"terminal receipt resolves final committed request")
	check(await _wait(func() -> bool: return _ending_received),"growth ending received")
	_finish()
