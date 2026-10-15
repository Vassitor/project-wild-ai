extends "res://tests/p35_network.gd"
## 真实回环双进程：房主布置隔离战斗，客户端经 ENet 发实际攻击 / 重试 / 重连。
const F = preload("res://tests/p6_fixtures.gd")
const P5 = preload("res://tests/p5_fixtures.gd")

func _ready() -> void:
	suite_label = "P6"
	super._ready()

func _run_host() -> void:
	store = WildBaseStateStore.new(case_root+"/room.json")
	service = WildCoopService.new(config,CATALOG,CONTENT,store.save_record)
	check(service.create("host","房主","17","host-secret").successful,"combat room created")
	check(network.host(service,port) == OK,"loopback combat host")
	FileAccess.open(case_root+"/ready.txt",FileAccess.WRITE).store_string("ready")
	check(await _wait(func() -> bool: return service.state.members.size() == 2),"combat guest handshakes")
	if not service.state.members.has("guest"): _finish(); return
	check(await _wait(func() -> bool: return service.state.members["guest"].skills.levels["hunting"] == 1),"guest learns before departure")
	check((await _request("room.start",{},"start")).successful,"room starts locked animal party scaling")
	check(service.state.survival.departure_players == 2 and service.state.survival.prey.size() == 42,"two person population")
	var guest: WildBaseState = service.state.members["guest"]
	var rabbit: Dictionary = F.focus(guest)
	var target_id: String = rabbit["id"]
	F.equip(guest,"bow")
	P5.give(guest,"arrow",4)
	service.state.world.players["guest"] = WildCombatWorld.position(rabbit,service.state.world)-Vector2(96,0)
	service.state.world.players["host"] = service.state.world.players["guest"]+Vector2(48,0)
	_stage("hunt-ready")
	check(await _wait(func() -> bool: return not service.state.survival.prey[target_id]["alive"]),"remote projectile hunts real rabbit")
	check(await _wait(func() -> bool: return _has_marker("hunt-checked")),"guest confirms loot / replay")
	check(_quantity("guest","arrow") == 3,"lost request / replay consumes one arrow")
	check(_quantity("guest","raw_meat") == 1 and _quantity("host","raw_meat") == 0,"one private loot set")
	check(service.state.members["guest"].skills.experience["hunting"] == 12,"guest authoritative progression")
	check(service.state.members["host"].skills.experience["hunting"] == 0,"no teammate experience")
	check(service.state.survival.bodies["host"].hp == 100,"arrow passes teammate without PvP")
	_stage("menu")
	check(await _wait(func() -> bool: return _has_marker("menu-checked"),12),"client combat skill menu does not pause host time")
	_stage("disconnect")
	check(await _wait(func() -> bool: return not service.online.get("guest",true)),"original guest disconnects")
	guest = service.state.members["guest"]
	var wolf: Dictionary = {}
	for animal: Dictionary in service.state.survival.prey.values():
		if animal["kind"] == "wolf": wolf = animal; break
	var guest_cell: Vector2i = service.state.world.cell_at(service.state.world.players["guest"])
	F.place(wolf,service.state.world,guest_cell+Vector2i.RIGHT)
	wolf["alive"] = true
	wolf["hp"] = wolf["max_hp"]
	wolf["mode"] = "chase"
	wolf["target"] = "guest"
	wolf["loot_claimed"] = false
	wolf["ready_at"] = service.state.survival.elapsed_seconds
	service.state.world.players["guest"] = WildCombatWorld.position(wolf,service.state.world)-Vector2(24,0)
	service.state.world.players["host"] = service.state.world.centre(service.state.world.spawn)
	var armor := WildItemInstance.new(CATALOG.find(&"leather_armor"))
	guest.containers["armor"].placements[armor.instance_id] = {"item":armor,"position":Vector2i.ZERO,"rotated":false}
	check(service.checkpoint().successful,"offline wolf fixture saved")
	check(await _wait(func() -> bool: return service.state.survival.bodies["guest"].hp < 100),"offline character still attacked by host AI")
	check(service.state.survival.bodies["guest"].hp >= 80 and service.state.members["guest"].containers["armor"].placements[armor.instance_id]["item"].durability < 100,"armor reduces actual offline attack / wears")
	# 结束攻击夹具后恢复读档；断线不清空身体、成长、箭或冷却。
	wolf = service.state.survival.prey[wolf["id"]]
	wolf["mode"] = "return"
	wolf["target"] = ""
	F.place(wolf,service.state.world,guest_cell+Vector2i(6,2))
	service.state.world.players["guest"] = service.state.world.centre(service.state.world.spawn)+Vector2(0,8)
	check(service.checkpoint().successful,"combat offline checkpoint")
	FileAccess.open(case_root+"/reconnect.txt",FileAccess.WRITE).store_string("ready")
	check(await _wait(func() -> bool: return service.online.get("guest",false)),"original combat guest reconnects")
	check(await _wait(func() -> bool: return _has_marker("reconnected-check")),"client confirms retained body / growth")
	check(service.state.members.size() == 2 and _quantity("guest","arrow") == 3,"no extra character or ammo on reconnect")
	var restored := WildCoopService.new(config,CATALOG,CONTENT,store.save_record)
	check(restored.restore(store.load_records().payload["primary"],"host").successful,"actual JSON animal / projectile / body restore")
	check(not restored.state.survival.prey[target_id]["alive"] and restored.state.members["guest"].skills.experience["hunting"] == 12,"death and growth do not reset on load")
	_stage("finish")
	check(await _wait(func() -> bool: return _has_marker("ready-end")),"combat end agreement")
	check(network.end_host().successful,"combat room saved / ended")
	await get_tree().create_timer(0.4).timeout
	_finish()

func _run_client() -> void:
	check(network.join("127.0.0.1",port) == OK,"combat client connects")
	check(await _wait(func() -> bool: return not network.latest.is_empty()),"receives actual world")
	var secret: String = network.token
	check((await _request("skill.train",{"branch":"hunting","tier":1},"learn")).successful,"client personal bow skill")
	check(await _wait(func() -> bool: return _notice("hunt-ready")),"receives hunt stage")
	check(not network.latest["prey"].values()[0].has("random_state"),"AI RNG hidden from client")
	if fault: network.force_next_drop = true
	var attack: Dictionary = {"direction":[1.0,0.0],"damage":999999,"actor":"host","target":"host"}
	check((await _request("combat.attack",attack,"shot")).successful,"bound directional attack despite forged damage / actor")
	check(await _wait(func() -> bool: return network.latest["skills"]["experience"]["hunting"] == 12),"arrow kill growth reaches client")
	check((await _request("combat.attack",attack,"shot")).successful,"same shot receipt replay")
	check(_snapshot_quantity("arrow") == 3 and _snapshot_quantity("raw_meat") == 1,"client ammo / one loot")
	check((await _request("combat.damage",{"amount":99999},"forged-damage")).code == &"UNKNOWN_COMMAND","no client damage endpoint")
	if fault: check(network.forced_dropped_packets == 1 and network.retransmissions > 0,"lost shot request retried without second arrow")
	await _marker("hunt-checked")
	check(await _wait(func() -> bool: return _notice("menu")),"cooperative menu stage")
	var session := WildCoopReplicaSession.new()
	session.configure(network,"guest",config,CATALOG)
	var panel := WildSkillPanel.new()
	add_child(panel)
	panel.configure(session,config)
	session.submit(WildGameCommand.new("guest",&"base.open_pause"))
	panel.open("guest")
	var before: float = network.latest["elapsed_seconds"]
	await get_tree().create_timer(6).timeout
	check(network.latest["elapsed_seconds"] > before+120 and not session.is_paused(),"actual cooperative K panel continues simulation")
	session.submit(WildGameCommand.new("guest",&"base.close_station"))
	panel.queue_free()
	await _marker("menu-checked")
	check(await _wait(func() -> bool: return _notice("disconnect")),"disconnect stage")
	network.close_connection()
	check(await _wait(func() -> bool: return FileAccess.file_exists(case_root+"/reconnect.txt")),"host progressed offline threat")
	network.configure_identity("guest","队员",secret)
	check(network.join("127.0.0.1",port) == OK,"original identity joins again")
	check(await _wait(func() -> bool: return not network.latest.is_empty()),"new welcome after reconnect")
	check(network.latest["skills"]["experience"]["hunting"] == 12 and _snapshot_quantity("arrow") == 3,"growth and ammo retained")
	check(network.latest["players"]["guest"]["body"]["health_points"] < 100 and network.latest["players"]["guest"]["body"]["health_points"] > 0,"offline armor / injury retained")
	await _marker("reconnected-check")
	check(await _wait(func() -> bool: return _notice("finish")),"finish stage")
	check((await _request("survival.cancel",{},"ready-end")).successful,"last operation confirmed")
	check(await _wait(func() -> bool: return _ending_received),"saved room ending received")
	_finish()

func _snapshot_quantity(kind: String) -> int:
	var total: int = 0
	for container: Dictionary in network.latest["containers"].values():
		for entry: Dictionary in container["entries"]:
			if entry["item"]["item_id"] == kind: total += int(entry["item"]["quantity"])
	return total
