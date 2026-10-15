extends SceneTree
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")
const PATHS = preload("res://tests/verification_paths.gd")
const P5 = preload("res://tests/p5_fixtures.gd")
var passed: int = 0
var failed: int = 0
var profiles: Dictionary[String,WildBaseState] = {}
var disk: Dictionary = {}
var fail_save: bool = false
var service: WildFullCoopService

func _initialize() -> void:
	if not PATHS.arguments_are_isolated(): quit(1); return
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		push_error(label)

func _save(raw: Dictionary, _preserve: bool = false) -> WildOperationResult:
	if fail_save: return WildOperationResult.reject(&"SAVE_FAILED")
	disk = raw.duplicate(true)
	return WildOperationResult.accept()

func command(actor: String, operation: String, payload: Dictionary = {}, id: String = "") -> WildOperationResult:
	return service.submit(actor,{"room_id":service.state.room_id,"run_id":service.state.run_id,"request_id":id if not id.is_empty() else WildStableId.create("test"),"operation":operation,"payload":payload})

func _new_room(count: int = 4) -> void:
	profiles.clear()
	service = WildFullCoopService.new(CONFIG,CATALOG,CONTENT,_save)
	check(service.create("p0","房主","17","secret").successful,"create full room")
	for i: int in range(count):
		var actor: String = "p%d" % i
		if i > 0: check(service.join(actor,actor,"").successful,"join "+actor)
		var state := WildBaseState.new(actor,CONFIG)
		var item := WildItemInstance.new(CATALOG.find(&"ration"),3)
		check(WildInventoryOperations.insert(state,CATALOG,CONFIG,item),"personal prepared kit")
		profiles[actor] = state
		var lease: WildOperationResult = WildCoopProfileRules.execute(state,"coop.reserve",{"room_id":service.state.room_id,"run_id":service.state.run_id},CONFIG,CATALOG)
		check(lease.successful and state.containers["backpack"].placements.is_empty(),"reserve removes usable items")
		check(command(actor,"profile.offer",lease.payload,"offer:"+actor).successful,"world accepts lease")
		check(command(actor,"room.ready",{"ready":true}).successful,"ready "+actor)

func _deliver(actor: String) -> void:
	for event: Dictionary in WildCoopDeliveries.pending(service.state,actor):
		check(WildCoopProfileRules.apply_event(profiles[actor],event,CONFIG,CATALOG).successful,"apply "+event["kind"])
		check(command(actor,"profile.ack",{"event_id":event["event_id"],"hash":event["hash"]}).successful,"durable delivery ack")

func _start() -> void:
	check(command("p0","room.start").successful,"ready roster starts")
	check(service.state.lifecycle["phase"] == "loading","loading barrier")
	var before: float = service.state.survival.pending_seconds
	service.advance(0.25)
	check(service.state.survival.pending_seconds == before,"clock waits for all loaded")
	for actor: String in profiles: check(command(actor,"room.loaded",{"world_hash":service.state.lifecycle["world_hash"]}).successful,"world ack")
	check(service.state.lifecycle["phase"] == "running","all loaded unfreezes clock")

func _run() -> void:
	_durability()
	_new_room()
	check(service.join("p4","fifth","").code == &"ROOM_FULL","fifth member rejected")
	for actor: String in profiles:
		_deliver(actor)
		check(WildBaseStateCodec.decode(profiles[actor].record(),actor,CONFIG,CATALOG) != null,"escrow profile roundtrip")
	check(WildCoopCodec.decode(disk,CONFIG,CATALOG,CONTENT) != null,"lobby roundtrip")
	_start()
	check(service.state.world.resource_players == 4 and service.state.survival.departure_players == 4,"difficulty locks four players")
	var frame_probe := WildENetRoom.new()
	frame_probe.full_cooperation = true
	frame_probe.authority = service
	var frame: Dictionary = frame_probe._position_frame()
	var actors: Dictionary = {}
	for actor: String in frame["compact_players"]: actors["player_"+actor.sha256_text().left(32)] = frame["compact_players"][actor]
	frame["compact_players"] = actors
	frame.merge({"type":"frame","frame_sequence":99999,"input_ack":99999})
	check(var_to_bytes(frame).size() < 1200,"binary position frame with four full stable IDs stays below 1200 bytes")
	frame_probe.free()
	var positions: Dictionary = {}
	for point: Vector2 in service.state.world.players.values(): positions[point] = true
	check(positions.size() == 4,"distinct passable spawn cells")
	check(service.join("late","late","").code == &"ROSTER_LOCKED","new member cannot enter running world")
	check(WildCoopCodec.decode(disk,CONFIG,CATALOG,CONTENT) != null,"scaled world roundtrip")
	_gifts()
	_materials_and_sleeping()
	_sleep()
	_death_and_settlement()
	_cancel()
	_profile_failures_and_growth()
	_all_dead()
	_three_players()
	print("P6.5 domain checks: %d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)

func _gifts() -> void:
	service.state.world.players["p1"] = service.state.world.players["p0"]
	var id: String = service.state.members["p0"].containers["backpack"].placements.keys()[0]
	var offer: WildOperationResult = command("p0","gift.offer",{"target":"p1","item_id":id})
	check(offer.successful,"explicit gift offer")
	check(command("p0","survival.start",{"action":"eat","item_id":id}).code == &"GIFT_RESERVED","offered instance cannot be consumed")
	if not offer.successful: return
	check(command("p2","gift.accept",offer.payload).code == &"FORBIDDEN","unrelated player cannot accept")
	fail_save = true
	check(command("p1","gift.accept",offer.payload).code == &"SAVE_FAILED","gift write failure rolls back")
	fail_save = false
	check(not WildInventoryOperations.find(service.state.members["p0"],id).is_empty(),"failed gift retains sender ownership")
	check(command("p1","gift.accept",offer.payload,"gift-accept").successful,"recipient accepts")
	check(command("p1","gift.accept",offer.payload,"gift-accept").successful,"retry returns same receipt")
	check(WildInventoryOperations.find(service.state.members["p0"],id).is_empty(),"gift removes sender instance")
	check(WildInventoryOperations.choose(service.state.members["p1"],&"ration") != "","recipient owns rations")

func _sleep() -> void:
	check(command("p0","sleep.vote",{"hours":2}).successful,"sleep proposal")
	check(command("p1","sleep.vote",{"hours":4}).code == &"VOTE_CONFLICT","sleep durations must match")
	check(command("p2","sleep.vote",{"agree":false}).successful and service.state.lifecycle["vote"].is_empty(),"any living member can decline")
	var wall: Dictionary = {"now":0.0}
	service._real_clock = func() -> float: return wall["now"]
	service._realtime_anchor = 0
	service._realtime_base = service.state.lifecycle["real_seconds"]
	check(command("p0","sleep.vote",{"hours":1}).successful,"new proposal")
	wall["now"] = 31.0
	service.advance(0.001)
	check(service.state.lifecycle["vote"].is_empty(),"thirty wall-clock seconds expire proposal despite tiny physics delta")
	check(command("p0","sleep.vote",{"hours":1}).successful,"new wall-clock proposal")
	wall["now"] = 62.0
	check(command("p1","sleep.vote",{"hours":1}).successful and not service.state.lifecycle["vote"]["agree"].has("p0"),"late vote cannot revive expired agreement before next physics tick")
	command("p2","sleep.vote",{"agree":false})
	service.state.survival.bodies["p3"].water = 20
	service.online["p3"] = false
	check(command("p0","sleep.vote",{"hours":1}).code == &"SLEEP_UNSAFE","offline body's safety blocks skip")
	service.state.survival.bodies["p3"].water = 100
	service.online["p3"] = true

func _build(kind: String) -> String:
	var owner: WildBaseState = service.state.members["p0"]
	var recipe: Dictionary = CONTENT.recipe(kind)
	var site: Dictionary = P5.open_site(owner,Vector2i(recipe["width"],recipe["height"]),service.state.world.spawn)
	if site.is_empty(): site = P5.open_site(owner,Vector2i(recipe["width"],recipe["height"]))
	var payload: Dictionary = {"action":"build","recipe":kind,"x":site["x"],"y":site["y"]}
	for material: String in recipe["materials"]: P5.give(owner,material,recipe["materials"][material])
	check(command("p0","survival.start",payload).successful,"actual build "+kind)
	if not service.state.survival.actions.has("p0"): return ""
	WildSurvivalSimulation.queue_time(service.state.survival,service.state.survival.actions["p0"]["remaining"],"idle")
	service._simulate(service.state,true)
	check(service.checkpoint().successful,"build checkpoint "+kind)
	for id: String in service.state.survival.buildings:
		if service.state.survival.buildings[id]["kind"] == kind: return id
	return ""

func _materials_and_sleeping() -> void:
	var box_id: String = "camp_box:"+_build("storage_box")
	if not service.state.boxes.has(box_id): check(false,"built box exists"); return
	var box: WildInventoryContainer = service.state.boxes[box_id]
	var wood := WildItemInstance.new(CATALOG.find(&"wood"),1)
	box.placements[wood.instance_id] = {"item":wood,"position":Vector2i.ZERO,"rotated":false}
	# 两人制作箭矢需狩猎 1；库存本身不补木材，明确只从箱取。
	for actor: String in ["p1","p2"]:
		service.state.members[actor].skills.levels["hunting"] = 1
		service.state.world.players[actor] = service.state.world.players["p0"]
		P5.give(service.state.members[actor],"stone",1)
		P5.give(service.state.members[actor],"fiber",1)
	var result: WildOperationResult = command("p1","survival.start",{"action":"craft","recipe":"arrow","materials_box":box_id})
	check(result.successful,"craft explicitly reserves public wood")
	if result.successful:
		check(command("p2","survival.start",{"action":"craft","recipe":"arrow","materials_box":box_id}).code == &"MISSING_MATERIALS","shared material cannot be reserved twice")
		check(WildCoopCodec.decode(disk,CONFIG,CATALOG,CONTENT) != null,"shared material action roundtrip")
		var transfer: Dictionary = {"source":box_id,"target":"backpack","item_id":wood.instance_id,"source_version":service.state.boxes[box_id].version,"target_version":service.state.members["p2"].containers["backpack"].version,"auto":true}
		check(command("p2","inventory.transfer",transfer).code == &"MATERIAL_RESERVED","withdraw cannot steal active material reservation")
		WildSurvivalSimulation.queue_time(service.state.survival,service.state.survival.actions["p1"]["remaining"],"idle")
		service._simulate(service.state,true)
		check(service.checkpoint().successful and not service.state.boxes[box_id].placements.has(wood.instance_id),"completion consumes public wood once")
	P5.give(service.state.members["p2"],"wood",3)
	P5.give(service.state.members["p2"],"rope",1)
	check(command("p2","survival.start",{"action":"craft","recipe":"bow","materials_box":box_id}).successful,"private materials suffice despite selected empty public box")
	check(service.state.survival.actions["p2"].get("materials_box","unused") == "","unused public box is not a persistent dependency")
	check(command("p0","survival.start",{"action":"demolish","building_id":box_id.trim_prefix("camp_box:")}).successful,"teammate may demolish unused empty box")
	WildSurvivalSimulation.queue_time(service.state.survival,900,"idle")
	service._simulate(service.state,true)
	check(service.checkpoint().successful and not service.state.boxes.has(box_id) and service.state.survival.actions.has("p2"),"box removal does not cancel private craft")
	check(WildCoopCodec.decode(disk,CONFIG,CATALOG,CONTENT) != null,"no dangling box dependency in restored private craft")
	command("p2","survival.cancel")
	var camp_id: String = _build("camp")
	if camp_id.is_empty(): check(false,"camp built"); return
	for actor: String in profiles: service.state.world.players[actor] = service.state.world.players["p0"]
	for actor: String in profiles:
		service.state.survival.bodies[actor].bleeding = false
		check(command(actor,"sleep.vote",{"hours":1}).successful,"unanimous sleep vote "+actor)
	check(service.state.lifecycle["vote"].get("sleeping",false),"all online survivors begin same sleep")
	check(command("p0","survival.start",{"action":"rest"}).code == &"SLEEP_BUSY","skip blocks other work")
	check(service.apply_world_damage("p1",1,"environment").successful,"sleep receives authority damage")
	check(service.state.lifecycle["vote"].is_empty() and service.state.survival.actions.is_empty(),"damage wakes entire party immediately")
	for actor: String in profiles: check(command(actor,"sleep.vote",{"hours":1}).successful,"restart safe vote")
	var before: float = service.state.survival.elapsed_seconds
	for tick: int in range(60): service.advance(0.016)
	check(service.state.lifecycle["vote"].is_empty(),"one hour sleep completes bounded steps")
	check(service.state.survival.elapsed_seconds >= before+3600 and service.state.survival.elapsed_seconds < before+3660,"shared clock advances once per sleep minute")
	check(WildCoopCodec.decode(disk,CONFIG,CATALOG,CONTENT) != null,"post sleep world / bodies restore")
	var secret: String = "sleep-reconnect"
	service.state.token_hashes["p3"] = secret.sha256_text()
	check(service.member_disconnected("p3").successful,"offline member before new vote")
	for actor: String in ["p0","p1","p2"]: check(command(actor,"sleep.vote",{"hours":1}).successful,"online survivors agree while fourth offline")
	check(service.state.lifecycle["vote"].get("sleeping",false),"only online survivors vote")
	check(service.join("p3","p3",secret).successful and service.state.lifecycle["vote"].is_empty() and service.state.survival.actions.is_empty(),"returning living member cancels old quorum before input")

func _death_and_settlement() -> void:
	var body: WildBodyState = service.state.survival.bodies["p2"]
	check(service.apply_world_damage("p2",1000,"physical").successful,"authority lethal damage")
	check(body != service.state.survival.bodies["p2"] and service.state.survival.bodies["p2"].hp == 0,"candidate commits death")
	check(service.state.corpses.has("corpse:p2") and service.state.members["p2"].containers["backpack"].placements.is_empty(),"corpse takes private inventory atomically")
	check(command("p2","combat.attack",{"direction":[1,0]}).code == &"INVALID_PHASE","dead actor cannot act")
	check(WildCoopCodec.decode(disk,CONFIG,CATALOG,CONTENT) != null,"death corpse roundtrip")
	var token: String = "reconnect-test"
	service.state.token_hashes["p2"] = token.sha256_text()
	check(service.member_disconnected("p2").successful,"dead disconnect")
	check(service.join("p2","newname",token).successful and service.state.survival.bodies["p2"].hp == 0,"original reconnect does not revive")
	service.state.survival.outcome = "won"
	service.state.survival.elapsed_seconds = 168*3600
	for id: String in service.state.survival.fish_refills: service.state.survival.fish_refills[id] = 168*3600+CONTENT.fish_refill_seconds
	service.state.survival.next_animal_refill = 168*3600+CONFIG.combat_rules.refill_seconds
	service.state.survival.next_disturbance = 169*3600
	service.state.survival.actions.clear()
	service.state.survival.pending_seconds = 0
	service.state.survival.segments.clear()
	check(service.checkpoint().successful,"world settlement commits")
	check(service.state.lifecycle["phase"] == "settled","terminal lifecycle")
	check(WildCoopCodec.decode(disk,CONFIG,CATALOG,CONTENT) != null,"settled world roundtrip")
	for actor: String in profiles:
		var events: Array[Dictionary] = WildCoopDeliveries.pending(service.state,actor)
		_deliver(actor)
		var currency: int = profiles[actor].currency
		for event: Dictionary in events: check(WildCoopProfileRules.apply_event(profiles[actor],event,CONFIG,CATALOG).successful,"terminal replay harmless")
		check(profiles[actor].currency == currency and profiles[actor].cooperation["active"].is_empty(),"settlement exactly once unlocks profile")
		check(currency == CONFIG.starting_currency if actor == "p2" else currency >= CONFIG.starting_currency+CONFIG.success_base_reward,"only survivors get reward")
		check(WildBaseStateCodec.decode(profiles[actor].record(),actor,CONFIG,CATALOG) != null,"settled profile roundtrip")

func _cancel() -> void:
	_new_room(2)
	check(service.end_room().successful,"lobby cancellation saves release events")
	for actor: String in profiles:
		_deliver(actor)
		check(not profiles[actor].containers["backpack"].placements.is_empty() and profiles[actor].cooperation["active"].is_empty(),"cancelled departure restores original inventory")
	# 世界取消先于 offer 到达：原成员重连后仍能提交租约，收到明确退回收据。
	_new_room(2)
	var profile := WildBaseState.new("p1",CONFIG)
	P5.give(profile,"bottle",1)
	var reserved: WildOperationResult = WildCoopProfileRules.execute(profile,"coop.reserve",{"room_id":service.state.room_id,"run_id":service.state.run_id},CONFIG,CATALOG)
	service.state.lifecycle["offers"].erase("p1")
	service.state.members["p1"].containers["backpack"].placements.clear()
	check(service.end_room().successful,"world cancels before late offer")
	check(command("p1","profile.offer",reserved.payload).successful,"original member submits missed offer to cancelled world")
	for event: Dictionary in WildCoopDeliveries.pending(service.state,"p1"):
		if event["lease_id"] == reserved.payload["manifest"]["lease_id"]: check(WildCoopProfileRules.apply_event(profile,event,CONFIG,CATALOG).successful,"late offer receives deterministic release")
	check(not WildCoopProfileRules.blocked(profile) and not profile.containers["backpack"].placements.is_empty(),"unaccepted escrow cannot become permanently stuck")
	_new_room(2)
	check(command("p0","room.start").successful and service.state.lifecycle["phase"] == "loading","departure held before map loading")
	check(service.end_room().successful and not service.state.started and service.state.lifecycle["phase"] == "cancelled","cancelled loading returns to non-running terminal lobby")
	for actor: String in profiles:
		_deliver(actor)
		check(not WildCoopProfileRules.blocked(profiles[actor]) and not profiles[actor].containers["backpack"].placements.is_empty(),"loading cancellation returns original kit")
	check(WildCoopCodec.decode(disk,CONFIG,CATALOG,CONTENT) != null,"cancelled scaled loading world restores for missed receipts")

func _profile_failures_and_growth() -> void:
	_new_room(2)
	_start()
	var profile: WildBaseState = profiles["p1"]
	WildSkillRules.award(service.state.members["p1"],"gathering",CONFIG.skill_rules)
	check(service.checkpoint().successful,"authoritative growth saved before receipt")
	var events: Array[Dictionary] = WildCoopDeliveries.pending(service.state,"p1")
	check(events.size() == 2 and events[1]["kind"] == "growth","growth outbox follows accepted event")
	var growth: Dictionary = events.back()
	var base := WildBaseService.new(CONFIG,CATALOG,func() -> WildOperationResult: return WildOperationResult.accept({"exists":true,"primary":profile.record(),"backup":{}}),_save,Callable(),Callable(),CONTENT)
	check(base.initialize("p1").successful,"profile service restores active escrow")
	fail_save = true
	check(base.submit(WildGameCommand.new("p1",&"coop.apply_event",growth,"growth-write")).code == &"SAVE_FAILED","personal growth write failure rejects ACK")
	check(base.snapshot()["skills"]["experience"]["gathering"] == 0,"failed personal growth leaves old profile")
	fail_save = false
	check(base.submit(WildGameCommand.new("p1",&"coop.apply_event",growth,"growth-write")).successful,"same growth receipt retries after save repair")
	var experience: int = base.snapshot()["skills"]["experience"]["gathering"]
	check(experience > 0 and base.submit(WildGameCommand.new("p1",&"coop.apply_event",events[0])).successful,"newer cumulative growth can precede accepted event")
	check(base.snapshot()["skills"]["experience"]["gathering"] == experience,"older receipt cannot erase permanent growth")
	var network := WildENetRoom.new()
	network._active = true
	network._welcomed = true
	network.latest = {"room_id":service.state.room_id,"run_id":service.state.run_id}
	var bridge := WildCoopProfileLink.new()
	bridge.configure(network,base,"p1")
	bridge.apply_deliveries([growth])
	var ack_id: String = "ack:"+growth["hash"]
	check(network._pending.has(ack_id) and bridge._acknowledged.is_empty(),"sent ACK remains pending until host durable confirmation")
	network._pending.clear()
	bridge.apply_deliveries([growth])
	check(network._pending.has(ack_id),"disconnect before ACK result permits retransmission after reconnect")
	network.command_completed.emit(ack_id,WildOperationResult.accept())
	check(bridge._acknowledged.has(growth["hash"]),"host success receipt confirms ACK")
	network.free()
	check(base.submit(WildGameCommand.new("p1",&"supply.claim")).code == &"COOP_RESERVED","active lease blocks double supplies / parallel expeditions")
	var wrong: Dictionary = growth.duplicate(true)
	wrong["owner"] = "p0"
	wrong["hash"] = WildCoopProfileRules.digest(wrong)
	check(not base.submit(WildGameCommand.new("p1",&"coop.apply_event",wrong)).successful,"other player receipt cannot apply")
	profile.containers["warehouse"].capacity_l = 0.01
	var settlement: Dictionary = WildCoopDeliveries.emit_event(service.state,"p1","settlement",{"won":true,"reward":600,"items":[{"item":WildItemInstance.new(CATALOG.find(&"knife")).record(),"rotated":false}]})
	check(WildCoopProfileRules.apply_event(profile,settlement,CONFIG,CATALOG).successful and profile.pending.size() == 1,"full permanent warehouse keeps returned item pending")
	var money: int = profile.currency
	check(WildCoopProfileRules.apply_event(profile,settlement,CONFIG,CATALOG).successful and profile.currency == money and profile.pending.size() == 1,"pending overflow / reward replay exactly once")
	check(WildCanonicalData.digest({"a":99.96666666666667}) == WildCanonicalData.digest(JSON.parse_string(JSON.stringify({"a":99.96666666666667},"",true,true))),"protocol digest tolerates JSON ULP differences")

func _all_dead() -> void:
	_new_room(2)
	_start()
	check(not _build("camp").is_empty(),"death during group sleep camp")
	service.state.world.players["p1"] = service.state.world.players["p0"]
	check(command("p0","sleep.vote",{"hours":1}).successful and command("p1","sleep.vote",{"hours":1}).successful,"sleep before lethal event")
	check(service.apply_world_damage("p0",1000,"environment").successful,"first death leaves teammate running")
	check(service.state.lifecycle["vote"].is_empty() and service.state.survival.actions.is_empty(),"death wakes surviving sleepers")
	check(service.state.survival.outcome == "running","one living member continues")
	check(service.apply_world_damage("p1",1000,"environment").successful,"last authority death")
	check(service.state.survival.outcome == "lost" and service.state.lifecycle["phase"] == "settled" and service.state.corpses.size() == 2,"all dead loses / both corpses persist")
	for actor: String in profiles:
		_deliver(actor)
		check(profiles[actor].currency == CONFIG.starting_currency and profiles[actor].cooperation["active"].is_empty(),"all dead returns permanent profile without reward")
	check(WildCoopCodec.decode(disk,CONFIG,CATALOG,CONTENT) != null,"failed terminal world roundtrip")

func _three_players() -> void:
	_new_room(3)
	_start()
	check(service.state.world.resource_players == 3 and service.state.survival.departure_players == 3,"three member difficulty and roster")
	check(WildCoopCodec.decode(disk,CONFIG,CATALOG,CONTENT) != null,"three person world roundtrip")
	var legacy := WildCoopService.new(CONFIG,CATALOG,CONTENT,_save)
	check(legacy.restore(disk,"p0").code == &"WRONG_ROOM_MODE","validation service cannot load actual personal world")

func _durability() -> void:
	var path: String = "res://.godot/verification/p65-domain-"+WildStableId.create("journal")+"/state.json"
	var store := WildDurableStateStore.new(path)
	check(store.save_record({"value":1}).successful,"journal first commit")
	store.stage_check = func(stage: String) -> bool: return stage != "primary"
	check(store.save_record({"value":2}).successful,"commit header owns success even primary replacement fails")
	check(store.load_records().payload["primary"].get("value",0) == 2,"journal restores complete latest commit")
	store.stage_check = func(stage: String) -> bool: return stage != "commit"
	check(not store.save_record({"value":3}).successful,"uncommitted journal cannot acknowledge")
	check(store.load_records().payload["primary"].get("value",0) == 2,"failed commit retains previous complete state")
	check(not store.save_record({"value":4}).successful,"second failure remains rollback")
	check(store.load_records().payload["primary"].get("value",0) == 2,"repeated failure does not lose last committed journal")
	store.stage_check = Callable()
	check(store.save_record({"nutrition":[99.96666666666667,99.98333333333333],"direction":0.9892103817203015}).successful,"fractional body / AI values saved")
	check(store.load_records().successful,"JSON floating point roundtrip cannot invalidate durable commit")
