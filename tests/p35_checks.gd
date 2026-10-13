extends SceneTree
## 房主事务验证仅用内存与随机工作区档案，不访问正式档案。
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")
const FIXTURES = preload("res://tests/p35_fixtures.gd")
var passed: int = 0
var failed: int = 0
var saved: Dictionary = {}
var fail_save: bool = false
var service: WildCoopService

func _initialize() -> void:
	_run.call_deferred()

func _save(data: Dictionary, _preserve: bool = false) -> WildOperationResult:
	if fail_save: return WildOperationResult.reject(&"SAVE_FAILED")
	saved = data.duplicate(true)
	return WildOperationResult.accept()

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		push_error(label)

func command(actor: String, operation: String, payload: Dictionary = {}, request: String = "") -> WildOperationResult:
	return service.submit(actor,{"room_id":service.state.room_id,"run_id":service.state.run_id,"request_id":request if not request.is_empty() else WildStableId.create("request"),"operation":operation,"payload":payload})

func item(actor: String, definition: String) -> WildItemInstance:
	var id: String = WildInventoryOperations.choose(service.state.members[actor],StringName(definition))
	return WildInventoryOperations.find(service.state.members[actor],id).get("item")

func count(actor: String, definition: String) -> int:
	var total: int = 0
	for container: WildInventoryContainer in service.state.members[actor].containers.values():
		for entry: Dictionary in container.placements.values():
			var value: WildItemInstance = entry["item"]
			if str(value.item_id) == definition: total += value.quantity
	return total

func _run() -> void:
	service = WildCoopService.new(CONFIG,CATALOG,CONTENT,_save)
	check(service.create("host","房主","17","host-secret").successful,"create room")
	var joined: WildOperationResult = service.join("guest","队友","")
	check(joined.successful,"join lobby")
	var token: String = joined.payload.get("token","")
	check(service.state.members.size() == 2 and service.state.survival.bodies.size() == 2,"two independent bodies")
	check(service.state.members["host"].containers["backpack"] != service.state.members["guest"].containers["backpack"],"private backpack references")
	check(item("host","knife").instance_id != item("guest","knife").instance_id,"stable unique kit IDs")
	check(not service.join("host","冒名","").successful,"host identity cannot be claimed")
	check(not service.join("third","第三位","").successful,"prototype capacity 2")
	check(command("guest","room.start").code == &"HOST_ONLY","host starts only")
	check(command("host","room.start",{},"start").successful,"start committed")
	check(command("host","room.start",{},"start").successful,"start receipt replay")
	check(command("host","room.start",{"different":true},"start").code == &"REQUEST_ID_CONFLICT","conflicting replay rejected")
	check(service.join("third","中途加入","").code == &"ROSTER_LOCKED","roster locked")
	check(command("guest","survival.start",{"action":"sleep"}).code == &"COOP_SLEEP_PENDING","no solo sleep in coop")
	var guest_knife: String = item("guest","knife").instance_id
	check(command("host","survival.start",{"action":"eat","item_id":guest_knife}).code == &"NOT_EDIBLE","actor cannot read other inventory")
	check(command("host","inventory.transfer",{"source":"guest:backpack","target":"backpack"}).code == &"UNKNOWN_CONTAINER","no global personal container alias")
	check(command("host","inventory.transfer",{"source":"warehouse","target":"backpack"}).code == &"FORBIDDEN_CONTAINER","no wilderness warehouse")
	# 明确测试布置位置：不会通过游戏网络提供任意坐标设置接口。
	var resource: Dictionary = {}
	for entry: Dictionary in service.state.world.resources.values():
		if entry["kind"] == "branch":
			resource = entry
			break
	var point: Vector2 = service.state.world.centre(Vector2i(resource["x"],resource["y"]))
	service.state.world.players["host"] = point
	service.state.world.players["guest"] = point
	var gather: Dictionary = {"action":"gather","resource_id":resource["id"],"version":resource["version"]}
	check(command("host","survival.start",gather,"gather-one").successful,"resource reservation")
	var stamina: float = service.state.survival.bodies["guest"].stamina
	check(command("guest","survival.start",gather).code == &"RESOURCE_RESERVED","same resource race rejected")
	check(service.state.survival.bodies["guest"].stamina == stamina and not service.state.survival.actions.has("guest"),"race no stamina deduction")
	check(command("host","survival.start",gather,"gather-one").successful,"action start replay")
	var before: int = count("host","wood")
	var guest_before: int = count("guest","wood")
	WildSurvivalSimulation.queue_time(service.state.survival,300,"idle")
	service._simulate(service.state,true)
	check(count("host","wood") == before+1,"one gather output")
	check(count("guest","wood") == guest_before,"output actor inventory isolation")
	check(service.state.world.resources[resource["id"]]["remaining"] == 0,"resource consumed once")
	check(command("host","survival.start",gather,"gather-one").successful and count("host","wood") == before+1,"completion replay no duplicate")
	# 寻找真实规则认可的营地位置，验证同格建造锁与材料延迟提交。
	service.state.world.players["host"] = service.state.world.centre(service.state.world.spawn)
	service.state.world.players["guest"] = service.state.world.players["host"]
	var site: WildOperationResult = WildBuildingRules.auto_site(service.state.members["host"],"host",Vector2i(2,2))
	check(site.successful,"valid camp site")
	if site.successful:
		var build: Dictionary = {"action":"build","recipe":"camp","x":site.payload["x"],"y":site.payload["y"]}
		check(command("host","survival.start",build).successful,"build reserved")
		var material_before: int = count("host","wood")
		check(command("guest","survival.start",build).code == &"SITE_RESERVED","same footprint race rejected")
		check(count("host","wood") == material_before,"start does not consume materials")
		check(command("host","inventory.transfer",{}).code == &"ACTION_BUSY","reserved inventory immutable")
		var decoded_active: WildCoopState = WildCoopCodec.decode(service.state.record(),CONFIG,CATALOG,CONTENT)
		check(decoded_active != null and decoded_active.survival.actions.has("host"),"active action restore with correct private links")
		WildSurvivalSimulation.queue_time(service.state.survival,3600,"idle")
		service._simulate(service.state,true)
		check(service.state.survival.buildings.size() == 1 and service.state.boxes.is_empty(),"camp does not grant free storage")
		check(count("host","wood") == material_before-8 and count("guest","wood") == guest_before,"only builder materials consumed")
		var box_site: WildOperationResult = FIXTURES.box_site(service.state.members["host"],"host")
		check(box_site.successful,"reachable independent box footprint")
		check(command("host","survival.start",{"action":"build","recipe":"storage_box","x":box_site.payload["x"],"y":box_site.payload["y"]}).successful,"independent box build start")
		check(WildCoopCodec.decode(service.state.record(),CONFIG,CATALOG,CONTENT) != null,"box reservation restored")
		WildSurvivalSimulation.queue_time(service.state.survival,1800,"idle")
		service._simulate(service.state,true)
		check(service.state.boxes.size() == 1 and service.state.survival.buildings.size() == 2,"one independent box commit")
		check(count("host","wood") == material_before-14 and count("host","fiber") == 0,"box costs six wood four fiber")
		var box: WildInventoryContainer = service.state.boxes.values()[0]
		var private_bag: WildInventoryContainer = service.state.members["host"].containers["backpack"]
		var wood: WildItemInstance = WildInventoryOperations.find(service.state.members["host"],FIXTURES.stack_with_amount(service.state.members["host"],&"wood",2))["item"]
		var deposit: Dictionary = {"source":"backpack","target":box.container_id,"item_id":wood.instance_id,"quantity":2,"auto":true,"source_version":private_bag.version,"target_version":box.version}
		check(command("host","inventory.transfer",deposit,"deposit").successful,"public box deposit")
		check(command("host","inventory.transfer",deposit,"deposit").successful,"deposit dedup")
		box = service.state.boxes[box.container_id]
		check((box.placements.values()[0]["item"] as WildItemInstance).quantity == 2,"one deposited stack")
		var box_item: WildItemInstance = box.placements.values()[0]["item"]
		var guest_bag: WildInventoryContainer = service.state.members["guest"].containers["backpack"]
		var withdraw: Dictionary = {"source":box.container_id,"target":"backpack","item_id":box_item.instance_id,"quantity":2,"auto":true,"source_version":box.version,"target_version":guest_bag.version}
		check(command("guest","inventory.transfer",withdraw,"withdraw").successful,"guest can withdraw public items")
		check(command("host","inventory.transfer",withdraw).code == &"STALE_VERSION","public race uses box version")
		check(command("guest","inventory.transfer",withdraw,"withdraw").successful,"withdraw receipt replay")
		check(service.state.boxes[box.container_id].placements.is_empty(),"no public item duplicated")
		service.state.world.players["guest"] = service.state.world.centre(Vector2i(resource["x"],resource["y"]))
		if not WildBuildingRules.in_reach(service.state.world,"guest",service.state.survival.buildings.values()[0]):
			check(command("guest","inventory.transfer",withdraw).code == &"OUT_OF_REACH","remote box cannot be looted")
	var encoded: Dictionary = service.state.record()
	var restored: WildCoopState = WildCoopCodec.decode(JSON.parse_string(JSON.stringify(encoded)),CONFIG,CATALOG,CONTENT)
	check(restored != null,"JSON roundtrip room")
	if restored != null:
		check(restored.world == restored.members["guest"].world and restored.survival == restored.members["host"].survival,"restored shared references")
		check(restored.receipts.size() == service.state.receipts.size(),"receipts persisted")
	var private_view: Dictionary = service.snapshot("host",true)
	check(not private_view.has("token_hashes") and not JSON.stringify(private_view).contains(guest_knife),"snapshots protect private items and secrets")
	var bad: Dictionary = encoded.duplicate(true)
	bad["members"]["guest"]["containers"]["backpack"]["entries"][0]["item"]["id"] = bad["members"]["host"]["containers"]["backpack"]["entries"][0]["item"]["id"]
	check(WildCoopCodec.decode(bad,CONFIG,CATALOG,CONTENT) == null,"cross-player duplicate ID rejected")
	var own_ration: String = item("guest","ration").instance_id
	var before_json: String = JSON.stringify(service.state.record(),"",true)
	fail_save = true
	check(command("guest","survival.start",{"action":"eat","item_id":own_ration},"save-retry").code == &"SAVE_FAILED","failed persistence reports failure")
	check(JSON.stringify(service.state.record(),"",true) == before_json,"failed persistence fully rolls back")
	fail_save = false
	check(command("guest","survival.start",{"action":"eat","item_id":own_ration},"save-retry").successful,"same request retry after save failure")
	var cancelled_stamina: float = service.state.survival.bodies["guest"].stamina
	var cancelled_items: int = item("guest","ration").quantity
	check(service.member_disconnected("guest").successful,"disconnect saved")
	check(not service.state.survival.actions.has("guest") and service.state.members.size() == 2,"disconnect removes action not character")
	check(item("guest","ration").quantity == cancelled_items and service.state.survival.bodies["guest"].stamina == cancelled_stamina,"cancel preserves material no fee refund")
	var water: float = service.state.survival.bodies["guest"].water
	WildSurvivalSimulation.queue_time(service.state.survival,60,"idle")
	service._simulate(service.state,true)
	check(service.state.survival.bodies["guest"].water < water,"offline body simulation")
	check(service.join("guest","队友","wrong-secret").code == &"IDENTITY_DENIED","reconnect requires secret")
	check(service.join("guest","队友",token).successful,"original member reconnect")
	check(service.state.members.size() == 2 and item("guest","ration").quantity == cancelled_items,"reconnect no kit reset")
	var disk := WildBaseStateStore.new("res://.godot/verification/p35-"+WildStableId.create("test")+".json")
	check(disk.save_record(service.state.record()).successful,"isolated disk save")
	var loaded: WildOperationResult = disk.load_records()
	var recovered_service := WildCoopService.new(CONFIG,CATALOG,CONTENT,_save)
	check(recovered_service.restore(loaded.payload["primary"],"host").successful,"disk room restore")
	check(recovered_service.online.is_empty(),"restore does not resurrect connections")
	check(recovered_service.join("guest","队友",token).successful and recovered_service.state.members.size() == 2,"reconnect after host restart")
	# 断线保存失败：冻结 / 重试必须落实取消，不能复活离线生产。
	check(command("guest","survival.start",{"action":"eat","item_id":own_ration}).successful,"action before failing disconnect")
	fail_save = true
	check(service.member_disconnected("guest").code == &"SAVE_FAILED" and service.save_blocked,"failed disconnect freezes simulation")
	check(service.state.survival.actions.has("guest") and not service.online["guest"],"failed cancellation remains uncommitted, peer already offline")
	fail_save = false
	check(service.advance(0.1).successful,"retry disconnect checkpoint")
	check(not service.state.survival.actions.has("guest") and item("guest","ration").quantity == cancelled_items,"retry cancels without output")
	check(service.join("guest","队友",token).successful,"reconnect after cancellation retry")
	var bag_version: int = service.state.members["guest"].containers["backpack"].version
	var fresh: float = item("guest","ration").freshness_hours
	WildSurvivalSimulation.queue_time(service.state.survival,60,"idle")
	service._simulate(service.state,true)
	check(item("guest","ration").freshness_hours < fresh and service.state.members["guest"].containers["backpack"].version == bag_version,"continuous aging preserves structural version")
	service.state.survival.bodies["host"].stamina = 50
	service.state.survival.bodies["guest"].stamina = 50
	service.activities = {"host":"sprint","guest":"idle"}
	WildSurvivalSimulation.queue_time(service.state.survival,60,"idle")
	service._simulate(service.state,true)
	check(service.state.survival.bodies["host"].stamina < 50 and service.state.survival.bodies["guest"].stamina > 50,"each actor has independent activity / stamina")
	check(service.submit("guest",{"actor_id":"host","room_id":service.state.room_id,"run_id":service.state.run_id,"request_id":"spoof-actor","operation":"survival.start","payload":{"action":"eat","item_id":own_ration}}).successful,"envelope actor cannot override authenticated actor")
	check(service.state.survival.actions.has("guest") and not service.state.survival.actions.has("host"),"spoof action attributed to bound guest")
	check(service.end_room().successful and service.state.survival.actions.is_empty(),"host ending cancels all unfinished actions before save")
	var inconsistent: Dictionary = service.state.record()
	inconsistent["survival"]["outcome"] = "won"
	check(WildCoopCodec.decode(inconsistent,CONFIG,CATALOG,CONTENT) == null,"early won save rejected")
	inconsistent["survival"]["outcome"] = "lost"
	check(WildCoopCodec.decode(inconsistent,CONFIG,CATALOG,CONTENT) == null,"living party lost save rejected")
	inconsistent = service.state.record()
	inconsistent["boxes"] = {}
	check(WildCoopCodec.decode(inconsistent,CONFIG,CATALOG,CONTENT) == null,"missing public camp box save rejected")
	var transfer_bag: WildInventoryContainer = service.state.members["guest"].containers["backpack"]
	var moved_knife: WildItemInstance = item("guest","knife")
	check(command("guest","inventory.transfer",{"source":"backpack","target":"main_hand","item_id":moved_knife.instance_id,"auto":true,"source_version":transfer_bag.version,"target_version":service.state.members["guest"].containers["main_hand"].version}).successful,"private equipment transfer after clock progression")
	check(service.state.members["guest"].containers["main_hand"].placements.has(moved_knife.instance_id),"equipment instance preserved")
	var replica := WildCoopReplicaSession.new()
	check(not replica.is_paused(),"coop personal menus never pause")
	print("P3.5 domain checks: %d passed, %d failed" % [passed,failed])
	service = null
	quit(0 if failed == 0 else 1)
