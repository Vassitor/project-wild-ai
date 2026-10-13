extends "res://tests/p35_network.gd"
## 复用真实 ENet 驱动，增加 P4 权威医疗、身体详情、离线病程和读档场景。

func _ready() -> void:
	suite_label = "P4"
	super._ready()

func _run_host() -> void:
	store = WildBaseStateStore.new(case_root+"/room.json")
	service = WildCoopService.new(config,CATALOG,CONTENT,store.save_record)
	check(service.create("host","房主","17","host-secret").successful,"isolated health room")
	check(network.host(service,port) == OK,"health ENet server")
	var ready := FileAccess.open(case_root+"/ready.txt",FileAccess.WRITE)
	ready.store_string("ready")
	ready.close()
	check(await _wait(func() -> bool: return service.state.members.size() == 2),"health client handshake")
	if service.state.members.size() != 2: _finish(); return
	check((await _request("room.start",{},"start")).successful,"health host start")
	var host_bandage: WildItemInstance = WildInventoryOperations.find(service.state.members["host"],WildInventoryOperations.choose(service.state.members["host"],&"bandage"))["item"]
	service.state.survival.bodies["host"].bleeding = true
	service.state.survival.bodies["guest"].bleeding = true
	_stage("health:"+host_bandage.instance_id)
	check(var_to_bytes(network._position_frame()).size() < 1200,"compact unreliable frame stays below MTU budget")
	check(await _wait(func() -> bool: return _has_marker("healed")),"remote bandage completed")
	check(not service.state.survival.bodies["guest"].bleeding and service.state.survival.bodies["host"].bleeding,"private treatment affects guest only")
	check(_quantity("guest","bandage") == 1 and _quantity("host","bandage") == 2,"bandage conservation and retry dedup")
	service.state.survival.bodies["guest"].gastro_remaining_seconds = 43200
	_stage("medicine")
	check(await _wait(func() -> bool: return _has_marker("medicine-done"),15),"remote medicine complete")
	check(_quantity("guest","herbal_medicine") == 1,"medicine consumed once")
	check(service.state.survival.bodies["guest"].gastro_remaining_seconds < 21600 and service.state.survival.bodies["guest"].medicine_cooldown_seconds > 6000,"authoritative six hour treatment and cooldown")
	_stage("offline")
	check(await _wait(func() -> bool: return not service.online.get("guest",true)),"health client disconnect")
	var remaining_course: float = service.state.survival.bodies["guest"].gastro_remaining_seconds
	var rng: String = service.state.survival.bodies["guest"].health_random_state
	WildSurvivalSimulation.queue_time(service.state.survival,3600,"idle")
	service._simulate(service.state,true)
	check(service.state.survival.bodies["guest"].gastro_remaining_seconds <= remaining_course-3600,"offline one hour course advancement")
	check(service.state.survival.bodies["guest"].health_random_state == rng,"existing course not rerolled offline")
	_stage("rejoined")
	check(await _wait(func() -> bool: return _has_marker("rejoined-done")),"original member reconnects")
	check(service.state.members.size() == 2 and _quantity("guest","bandage") == 1 and _quantity("guest","herbal_medicine") == 1,"reconnect no actor or medicine duplication")
	check(service.checkpoint().successful,"health checkpoint")
	var persisted: Dictionary = store.load_records().payload["primary"]
	var restored := WildCoopService.new(config,CATALOG,CONTENT,store.save_record)
	check(restored.restore(persisted,"host").successful,"health room restore")
	check(_records_close(restored.state.survival.bodies["guest"].record(),service.state.survival.bodies["guest"].record()),"restore includes RNG and all health timers")
	_stage("finish")
	check(await _wait(func() -> bool: return _has_marker("ready-end")),"health final agreement")
	check(network.end_host().successful,"health end saved")
	await get_tree().create_timer(0.4).timeout
	_finish()

func _definition_id(definition: String) -> String:
	for entry: Dictionary in network.latest.get("containers",{}).get("backpack",{}).get("entries",[]):
		if entry["item"]["item_id"] == definition: return entry["item"]["id"]
	return ""

## JSON 浮点文本往返允许 1e-6 误差；随机序列、标志、结构必须完全相同。
func _records_close(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not _records_close(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index: int in range(a.size()):
			if not _records_close(a[index],b[index]): return false
		return true
	if WildDataValidation.number(a) and WildDataValidation.number(b): return absf(float(a)-float(b)) < 0.000001
	return a == b

func _run_client() -> void:
	check(network.join("127.0.0.1",port) == OK,"health ENet client")
	check(await _wait(func() -> bool: return network._welcomed),"health welcome")
	replica = WildCoopReplicaSession.new()
	replica.configure(network,"guest",config,CATALOG)
	check(await _wait(func() -> bool: return str(network.latest.get("notice","")).begins_with("health:")),"health fixture delivered")
	var foreign_item: String = str(network.latest["notice"]).trim_prefix("health:")
	check((await _request("survival.start",{"action":"treat","item_id":foreign_item,"actor_id":"host"},"foreign-treatment")).code == &"NOT_MEDICINE","foreign treatment and forged actor rejected")
	if fault: network.force_next_drop = true
	var payload: Dictionary = {"action":"treat","item_id":_definition_id("bandage"),"actor_id":"host"}
	check((await _request("survival.start",payload,"self-bandage")).successful,"own bandage despite forged payload actor")
	check(await _wait(func() -> bool: return not network.latest["players"]["guest"]["body"]["bleeding"],8),"healed authoritative snapshot")
	check((await _request("survival.start",payload,"self-bandage")).successful,"completed bandage replay")
	check(not (await _request("body.damage",{"amount":1,"actor_id":"host"},"unauthorized-damage")).successful,"network cannot inject damage")
	check(network.latest["players"]["host"]["body"]["bleeding"],"host illness unchanged")
	await _marker("healed")
	check(await _wait(func() -> bool: return _notice("medicine")),"gastro stage")
	var details := WildBodyDetails.new()
	details.configure(replica)
	add_child(details)
	replica.submit(WildGameCommand.new("guest",&"base.open_pause"))
	details.open("guest")
	var before: float = network.latest["elapsed_seconds"]
	await get_tree().create_timer(1.1).timeout
	details.refresh()
	var progressed: bool = await _wait(func() -> bool: return network.latest["elapsed_seconds"] > before+60,4)
	check(not replica.is_paused() and progressed,"body detail menu advances authoritative world")
	check(details._conditions.text.contains("肠胃不适") and details._explanation.text.contains("体力恢复系数"),"live ENet body detail feedback")
	replica.submit(WildGameCommand.new("guest",&"base.close_station"))
	details.queue_free()
	check((await _request("survival.start",{"action":"treat","item_id":_definition_id("herbal_medicine")},"self-medicine")).successful,"remote medicine accepted")
	check(await _wait(func() -> bool: return network.latest["players"]["guest"]["body"]["medicine_cooldown_seconds"] > 0,8),"medicine effect snapshot")
	check((await _request("survival.start",{"action":"treat","item_id":_definition_id("herbal_medicine")},"medicine-too-soon")).code == &"MEDICINE_COOLDOWN","remote cooldown rejects repeat dose")
	check(not network.latest["players"]["guest"]["body"].has("health_random_state"),"private illness RNG absent from packets")
	await _marker("medicine-done")
	check(await _wait(func() -> bool: return _notice("offline")),"offline health stage")
	var token_copy: String = network.token
	network.close_connection()
	await get_tree().create_timer(2).timeout
	network.configure_identity("guest","队友",token_copy)
	check(network.join("127.0.0.1",port) == OK,"health reconnect")
	check(await _wait(func() -> bool: return network._welcomed),"health reconnect welcome")
	check(network.latest["players"]["guest"]["body"]["gastro_remaining_seconds"] < 18000 and network.latest["players"]["guest"]["body"]["medicine_cooldown_seconds"] < 3600,"reconnect retains progressed course and cooldown")
	await _marker("rejoined-done")
	check(await _wait(func() -> bool: return _notice("finish")),"health finish stage")
	if fault: check(network.forced_dropped_packets == 1 and network.retransmissions > 0,"treatment request loss safely retried")
	await _marker("ready-end")
	check(await _wait(func() -> bool: return _ending_received),"health saved ending notification")
	_finish()
